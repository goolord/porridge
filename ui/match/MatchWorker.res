// A sound matcher worker (bundle/match-worker.js, which the view runs after the engine's class,
// bundle/match-engine.js, in one script: see MatchPool.res). It has an engine of its own, and
// renders and scores what it is sent, one candidate at a time, against the session it was last
// set up for.

open MatchProtocol

let post: response => unit = %raw(`m => self.postMessage(m)`)
let listen: (request => unit) => unit = %raw(`f => { self.onmessage = e => f(e.data); }`)
// the engine's class, declared by the script before this one
let engineClass: unit => MatchEngine.engineClass = %raw(`() => PorridgeMatchEngine`)

let engine = ref(None)
let context = ref(None)

let messageOf = (e, fallback) => e->JsExn.fromException->Option.flatMap(JsExn.message)->Option.getOr(fallback)

let handle = async (request: request) =>
  switch (request, engine.contents) {
  | (Init({wasm}), _) =>
    switch await MatchEngine.make(engineClass(), wasm) {
    | e =>
      engine := Some(e)
      post(Ready)
    | exception e => post(Failed({task: -1, message: messageOf(e, "the engine didn't start")}))
    }
  | (Prepare({task, name, samples, sampleRate}), _) =>
    switch SoundTarget.prepare(~name, {samples, sampleRate, frameSize: None, sides: None}) {
    | Ok(target) =>
      let (envelope, spectrum) =
        MatchSearch.targetPicture(Spectrum.measure(target.samples, ~period=SoundTarget.period(target)))
      post(Target({task, target, envelope, spectrum}))
    | Error(message) => post(Failed({task, message}))
    }
  | (_, None) => post(Failed({task: -1, message: "the engine isn't ready"}))
  | (Setup({setup}), Some(engine)) =>
    context := Some(MatchSearch.makeContext(engine, setup.target, ~base=setup.base, ~tables=setup.tables))
  | (Evaluate({task, genes, weights, threshold}), Some(_)) =>
    switch context.contents {
    | Some(ctx) =>
      let (loss, candidate) = MatchSearch.evaluate(ctx, Float64Array.fromArray(genes), ~weights, ~threshold)
      post(Evaluated({task, loss, candidate}))
    | None => post(Failed({task, message: "nothing to match"}))
    }
  }

let taskOf = (request: request) =>
  switch request {
  | Prepare({task}) | Evaluate({task}) => task
  | Init(_) | Setup(_) => -1
  }

let () = listen(request =>
  handle(request)
  ->Promise.catch(e => {
    post(Failed({task: taskOf(request), message: messageOf(e, "the matcher failed")}))
    Promise.resolve()
  })
  ->ignore
)
