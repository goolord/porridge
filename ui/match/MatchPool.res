// The sound matcher's workers, as the view runs them. The first time someone matches a sound,
// the engine (bundle/match-engine.wasm and .js), the worker (bundle/match-worker.js) and the
// predictor (bundle/match-model.bin, if the build has one) are read from the patch's resources,
// the module is compiled once, and the workers start, each with an engine of its own (about
// 50 MB each with its base kept, so at most twelve, and one core left for the rest).
//
// Work goes out as tasks, each to the next idle worker: rendering and scoring one candidate
// (`evaluate`), or preparing a sample. A worker is set up for a
// session (the target and the base patch) before its first evaluation in it. The workers stop
// when the pool is disposed.

open MatchProtocol

type worker
@new external makeWorker: string => worker = "Worker"
@send external postMessage: (worker, request) => unit = "postMessage"
@set external setOnMessage: (worker, {"data": response} => unit) => unit = "onmessage"
@set external setOnError: (worker, unit => unit) => unit = "onerror"
@send external terminate: worker => unit = "terminate"
@new external makeTextBlob: (array<string>, Web.blobOptions) => Web.blob = "Blob"
let compile: Uint8Array.t => promise<MatchEngine.wasmModule> = %raw(`bytes => WebAssembly.compile(bytes)`)
let cores: unit => int = %raw(`() => navigator.hardwareConcurrency || 2`)
@val external floatsOf: Float64Array.t => array<float> = "Array.from"

let maxWorkers = 12

type task = {
  id: int,
  // the session it renders in, if it is an evaluation
  session: option<int>,
  // the run it belongs to (dropped from the queue when that is cancelled)
  run: int,
  make: int => request,
  reply: response => unit,
}

type slot = {worker: worker, mutable session: int, mutable busy: option<task>}

type t = {
  slots: array<slot>,
  url: string,
  queue: array<task>,
  sessions: Map.t<int, setup>,
  mutable nextId: int,
}

let next = t => {
  t.nextId = t.nextId + 1
  t.nextId
}

// Gives queued tasks to idle workers.
let rec pump = t =>
  t.slots->Array.forEach(slot =>
    if slot.busy == None {
      switch t.queue->Array.shift {
      | Some(task) =>
        slot.busy = Some(task)
        task.session->Option.forEach(session =>
          if slot.session != session {
            t.sessions->Map.get(session)->Option.forEach(setup => slot.worker->postMessage(Setup({session, setup})))
            slot.session = session
          }
        )
        slot.worker->postMessage(task.make(task.id))
      | None => ()
      }
    }
  )

and onReply = (t, slot, r: response) => {
  slot.busy->Option.forEach(task => {
    slot.busy = None
    task.reply(r)
  })
  pump(t)
}

let errorText = e => e->JsExn.fromException->Option.flatMap(JsExn.message)->Option.getOr("unknown error")

// Starts the workers; an error if the engine isn't in the plugin or won't run here.
let start = async (pc): result<t, string> => {
  let glue = await Resources.readText(pc, "bundle/match-engine.js")
  let code = await Resources.readText(pc, "bundle/match-worker.js")
  let bytes = await Resources.readBytes(pc, "bundle/match-engine.wasm")
  let model = await Resources.readBytes(pc, "bundle/match-model.bin")
  switch (glue, code, bytes) {
  | (Some(glue), Some(code), Some(bytes)) =>
    switch await compile(bytes) {
    | exception e => Error("The matcher's engine won't run here: " ++ errorText(e))
    | wasm =>
      let url = Web.createObjectURL(makeTextBlob([glue, "\n", code], {mimeType: "text/javascript"}))
      let count = Math.Int.max(1, Math.Int.min(maxWorkers, cores() - 1))
      let t = {
        slots: Array.fromInitializer(~length=count, _ => {worker: makeWorker(url), session: -1, busy: None}),
        url,
        queue: [],
        sessions: Map.make(),
        nextId: 0,
      }
      let started = await Promise.all(
        t.slots->Array.map(slot =>
          Promise.make((resolve, _) => {
            slot.worker->setOnError(() => resolve(Some("a matcher worker didn't start")))
            slot.worker->setOnMessage(m =>
              switch m["data"] {
              | Ready =>
                slot.worker->setOnMessage(m => onReply(t, slot, m["data"]))
                resolve(None)
              | Failed({message}) => resolve(Some(message))
              | _ => ()
              }
            )
            slot.worker->postMessage(Init({wasm, model}))
          })
        ),
      )
      switch started->Array.find(Option.isSome) {
      | Some(Some(message)) =>
        t.slots->Array.forEach(s => terminate(s.worker))
        Web.revokeObjectURL(url)
        Error("The matcher's engine won't run here: " ++ message)
      | _ => Ok(t)
      }
    }
  | _ => Error("This build has no matcher engine (run tools/match-engine.mjs)")
  }
}

let dispose = t => {
  t.slots->Array.forEach(s => terminate(s.worker))
  Web.revokeObjectURL(t.url)
}

let workers = t => Array.length(t.slots)

let request = (t, ~session=?, ~run=0, make) =>
  Promise.make((resolve, _) => {
    t.queue->Array.push({id: next(t), session, run, make, reply: resolve})
    pump(t)
  })

// A new session: what the evaluations given its number render against.
let session = (t, setup) => {
  let id = next(t)
  // the workers only ever need the newest few
  t.sessions->Map.keys->Array.fromIterator->Array.filter(s => s < id - 8)->Array.forEach(s => t.sessions->Map.delete(s)->ignore)
  t.sessions->Map.set(id, setup)
  id
}

// A run's number, which its tasks carry, so that cancelling it drops the ones still queued.
let newRun = next

// Drops a run's queued tasks; those already with a worker finish, and are ignored.
let cancelRun = (t, run) => {
  let dropped = t.queue->Array.filter(task => task.run == run)
  let kept = t.queue->Array.filter(task => task.run != run)
  t.queue->Array.splice(~start=0, ~remove=Array.length(t.queue), ~insert=kept)
  dropped->Array.forEach(task => task.reply(Failed({task: task.id, message: "cancelled"})))
}

// Renders and scores genes in a session (MatchRun.evaluate); a failure scores nothing.
let evaluate = (t, ~session, ~run, genes: Float64Array.t, weights, threshold, fit, short) =>
  request(t, ~session, ~run, task => Evaluate({task, genes: floatsOf(genes), weights, threshold, fit, short}))->Promise.thenResolve(r =>
    switch r {
    | Evaluated({result}) => result
    | _ => ({loss: infinity, genes: floatsOf(genes), candidate: None}: MatchSearch.result)
    }
  )

// Renders and scores a patch given as values in a session (MatchRun.evaluateValues); a failure
// scores nothing.
let evaluateValues = (t, ~session, ~run, values, note) =>
  request(t, ~session, ~run, task => EvaluateValues({task, values, note}))->Promise.thenResolve(r =>
    switch r {
    | Valued({valued}) => valued
    | _ => ({loss: infinity, similarity: 0., envelope: [], spectrum: [], gain: 1.}: MatchSearch.valued)
    }
  )

let prepare = async (t, ~name, audio: AudioFile.t) =>
  switch await request(t, task => Prepare({task, name, samples: audio.samples, sides: audio.sides, sampleRate: audio.sampleRate})) {
  | Target({target, envelope, spectrum, suggestions}) => Ok((target, envelope, spectrum, suggestions))
  | Failed({message}) => Error(message)
  | _ => Error(`${name} couldn't be read`)
  }
