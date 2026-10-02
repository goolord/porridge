// The synth as the sound matcher renders it: Porridge's DSP compiled to WebAssembly
// (bundle/match-engine.js and .wasm, built by tools/match-engine.mjs), one instance per worker.
//
// Every render starts from the same state: the base patch is loaded and settled once, the
// instance's memory is kept, and before each candidate it is put back. Renders are
// deterministic, so a candidate's loss means the same each time.
//
// Putting all of it back (43 MB) was most of a render's time with several workers at once, as
// they share the memory's bandwidth; but a render changes well under a megabyte of it (one
// voice, the effects it uses, the parameters). So `learnPages` renders a few probes that
// switch every part on and notes the 4 kB pages they change, and only those are put back.
// Every `checkEvery` renders the other pages are checked against the base's checksums; any
// changed (a part no probe used) means all of it is put back and they join the rest.
//
// The base is kept sparsely: only its pages that aren't all zeros (about 5 MB of the 43), each
// page's checksum, and the bytes of the pages renders change.

type engineClass
type wasmModule
type instance

let construct: engineClass => instance = %raw(`C => new C()`)
@set external setModule: (instance, wasmModule) => unit = "wasmModule"
@send external initialise: (instance, int, float) => promise<bool> = "initialise"
@send external advance: (instance, int) => unit = "advance"
@send external getOutputFrames: (instance, array<Float32Array.t>, int, int) => unit = "getOutputFrames_out"
@send external sendMidi: (instance, {"message": int}) => unit = "sendInputEvent_midiIn"
@send external sendShape: (instance, Bank.shapePayload) => unit = "sendInputEvent_shapeIn"
@send external sendCurve: (instance, Bank.shapePayload) => unit = "sendInputEvent_curveIn"
@get external memoryOf: instance => Uint8Array.t = "byteMemory"

// Sends a parameter's value, if the engine has the parameter (a newer view with an older engine
// leaves out what it doesn't know).
let sendParam: (instance, string, float) => unit = %raw(`(e, id, v) => {
  const f = e["sendInputEvent_" + id];
  if (f !== undefined) f.call(e, v);
}`)

@get_index external get32: (Float32Array.t, int) => float = ""
@set_index external set32: (Float32Array.t, int, float) => unit = ""
// target.set(source, offset)
@send external blit: (Float32Array.t, Float32Array.t, int) => unit = "set"

let sampleRate = Spectrum.sampleRate
// the synth applies MIDI a 64-sample block late
let latency = 64
let block = 512
// rendered after the values are sent and before the note, while the controls settle
let settle = 1024
let velocity = 100

//==============================================================================
// The memory in 4 kB pages. Sets of pages are [start, end) byte ranges of runs, in pairs; a
// set's bytes are its pages' contents one after another.

let pageSize = 4096
let checkEvery = 256

// each page's checksum (FNV-1a over its 32-bit words), skipping marked pages (left 0)
let checksums: (Uint8Array.t, option<Uint8Array.t>) => Uint32Array.t = %raw(`(mem, marks) => {
  const words = new Int32Array(mem.buffer, mem.byteOffset, mem.length >> 2);
  const per = 4096 >> 2;
  const pages = Math.ceil(words.length / per);
  const out = new Uint32Array(pages);
  for (let p = 0; p < pages; p++) {
    if (marks && marks[p]) continue;
    let h = 0x811c9dc5;
    const end = Math.min(words.length, (p + 1) * per);
    for (let i = p * per; i < end; i++) h = Math.imul(h ^ words[i], 16777619);
    out[p] = h >>> 0;
  }
  return out;
}`)

// marks the unmarked pages whose checksum isn't the one given; how many
let markDiffering: (Uint8Array.t, Uint32Array.t, Uint8Array.t) => int = %raw(`(mem, sums, marks) => {
  const now = new Uint32Array(sums.length);
  const words = new Int32Array(mem.buffer, mem.byteOffset, mem.length >> 2);
  const per = 4096 >> 2;
  let added = 0;
  for (let p = 0; p < sums.length; p++) {
    if (marks[p]) continue;
    let h = 0x811c9dc5;
    const end = Math.min(words.length, (p + 1) * per);
    for (let i = p * per; i < end; i++) h = Math.imul(h ^ words[i], 16777619);
    if ((h >>> 0) !== sums[p]) { marks[p] = 1; added++; }
  }
  return added;
}`)

// the pages that aren't all zeros, marked
let nonZero: Uint8Array.t => Uint8Array.t = %raw(`mem => {
  const words = new Int32Array(mem.buffer, mem.byteOffset, mem.length >> 2);
  const per = 4096 >> 2;
  const marks = new Uint8Array(Math.ceil(words.length / per));
  for (let p = 0; p < marks.length; p++) {
    const end = Math.min(words.length, (p + 1) * per);
    for (let i = p * per; i < end; i++) if (words[i] !== 0) { marks[p] = 1; break; }
  }
  return marks;
}`)

let rangesOf: Uint8Array.t => Int32Array.t = %raw(`marks => {
  const out = [];
  for (let p = 0; p < marks.length; p++)
    if (marks[p] && (p === 0 || !marks[p - 1])) {
      let q = p;
      while (q + 1 < marks.length && marks[q + 1]) q++;
      out.push(p * 4096, (q + 1) * 4096);
    }
  return Int32Array.from(out);
}`)

let marksOf: (Int32Array.t, int) => Uint8Array.t = %raw(`(ranges, pages) => {
  const marks = new Uint8Array(pages);
  for (let k = 0; k < ranges.length; k += 2)
    for (let p = ranges[k] / 4096; p < ranges[k + 1] / 4096; p++) marks[p] = 1;
  return marks;
}`)

let bytesOf: (Uint8Array.t, Int32Array.t) => Uint8Array.t = %raw(`(mem, ranges) => {
  let size = 0;
  for (let k = 0; k < ranges.length; k += 2) size += Math.min(ranges[k + 1], mem.length) - ranges[k];
  const out = new Uint8Array(size);
  let at = 0;
  for (let k = 0; k < ranges.length; k += 2) {
    const end = Math.min(ranges[k + 1], mem.length);
    out.set(mem.subarray(ranges[k], end), at);
    at += end - ranges[k];
  }
  return out;
}`)

let copyBack: (Uint8Array.t, Uint8Array.t, Int32Array.t) => unit = %raw(`(mem, bytes, ranges) => {
  let at = 0;
  for (let k = 0; k < ranges.length; k += 2) {
    const n = Math.min(ranges[k + 1], mem.length) - ranges[k];
    mem.set(bytes.subarray(at, at + n), ranges[k]);
    at += n;
  }
}`)

let clear: Uint8Array.t => unit = %raw(`mem => mem.fill(0)`)

//==============================================================================

// The base, as it is kept: its non-zero pages and their bytes, every page's checksum, and the
// pages renders change with their bytes once the probes have found them.
type base = {
  filled: Int32Array.t,
  filledBytes: Uint8Array.t,
  sums: Uint32Array.t,
  mutable dirty: option<(Int32Array.t, Uint8Array.t)>,
}

type t = {
  instance: instance,
  left: Float32Array.t,
  right: Float32Array.t,
  // the engine as it started, which every base is loaded on (so that a base, and every render
  // on it, is the same whatever the engine did before)
  pristine: base,
  mutable base: option<base>,
  // renders since the other pages were last checked
  mutable sinceCheck: int,
}

// The memory as a base: its non-zero pages and every page's checksum.
let keep = (mem: Uint8Array.t) => {
  let filled = rangesOf(nonZero(mem))
  {filled, filledBytes: bytesOf(mem, filled), sums: checksums(mem, None), dirty: None}
}

let make = async (cls, module_) => {
  let instance = construct(cls)
  instance->setModule(module_)
  let _ = await instance->initialise(2, sampleRate)
  {
    instance,
    left: Float32Array.fromLength(block),
    right: Float32Array.fromLength(block),
    pristine: keep(instance->memoryOf),
    base: None,
    sinceCheck: 0,
  }
}

let memory = t => t.instance->memoryOf
let pageCount = t => (TypedArray.length(memory(t)) + pageSize - 1) / pageSize

// All of the base back.
let restoreAll = (t, b) => {
  clear(memory(t))
  copyBack(memory(t), b.filledBytes, b.filled)
}

// The pages renders change back, or all of it before they are known. Now and then the other
// pages are checked; if any changed, all of it goes back and they join the pages put back.
let restore = t =>
  t.base->Option.forEach(b =>
    switch b.dirty {
    | None => restoreAll(t, b)
    | Some((ranges, bytes)) =>
      t.sinceCheck = t.sinceCheck + 1
      if t.sinceCheck >= checkEvery {
        t.sinceCheck = 0
        let marks = marksOf(ranges, pageCount(t))
        if markDiffering(memory(t), b.sums, marks) > 0 {
          restoreAll(t, b)
          let ranges = rangesOf(marks)
          b.dirty = Some((ranges, bytesOf(memory(t), ranges)))
        } else {
          copyBack(memory(t), bytes, ranges)
        }
      } else {
        copyBack(memory(t), bytes, ranges)
      }
    }
  )

let send = (t, values: array<(string, float)>) =>
  values->Array.forEach(((id, v)) => t.instance->sendParam(id, v))

// Runs n frames, adding the mono mix into out from `at` (or dropping it without out), and the
// side signal into `side`.
let run = (t, n, ~out=?, ~side=?, ~at=0) => {
  let pos = ref(0)
  while pos.contents < n {
    let k = Math.Int.min(block, n - pos.contents)
    t.instance->advance(k)
    switch out {
    | Some(out) =>
      t.instance->getOutputFrames([t.left, t.right], k, 0)
      for i in 0 to k - 1 {
        out->set32(at + pos.contents + i, 0.5 * (t.left->get32(i) + t.right->get32(i)))
      }
      side->Option.forEach(side =>
        for i in 0 to k - 1 {
          side->set32(at + pos.contents + i, 0.5 * (t.left->get32(i) - t.right->get32(i)))
        }
      )
    | None => ()
    }
    pos := pos.contents + k
  }
}

// Loads the patch every candidate starts from: its values and its waveforms and curves, on
// the engine as it started.
let setBase = (t, values: Bank.values, tables: OatmealFormat.tables) => {
  restoreAll(t, t.pristine)
  values->Map.forEachWithKey((v, id) => t.instance->sendParam(id, v))
  OatmealFormat.allTables->Array.forEach(table => {
    let {which, endpoint} = OatmealFormat.tableInfo(table)
    let payload: Bank.shapePayload = {which, data: Bank.arrayOfFloats(tables->OatmealFormat.getTable(table))}
    endpoint == "shapeIn" ? t.instance->sendShape(payload) : t.instance->sendCurve(payload)
  })
  t.instance->sendMidi({"message": 0xb0 * 65536 + 123 * 256})
  run(t, 8192)
  t.base = Some(keep(memory(t)))
  t.sinceCheck = 0
}

let noteMessage = (status, note, vel) => {"message": status * 65536 + note * 256 + vel}

// A note held for `frames` (the key played `note`, tuned by `cents`) with these values on the
// base, as mono samples.
let render = (t, values, ~note, ~cents, ~frames) => {
  restore(t)
  send(t, values)
  t.instance->sendParam("Tune_Main", 440. * Math.pow(2., ~exp=cents / 1200.))
  run(t, settle)
  t.instance->sendMidi(noteMessage(0x90, note, velocity))
  let out = Float32Array.fromLength(frames)
  run(t, latency)
  run(t, frames, ~out)
  out
}

// The same as mono and side samples.
let renderSides = (t, values, ~note, ~cents, ~frames) => {
  restore(t)
  send(t, values)
  t.instance->sendParam("Tune_Main", 440. * Math.pow(2., ~exp=cents / 1200.))
  run(t, settle)
  t.instance->sendMidi(noteMessage(0x90, note, velocity))
  let out = Float32Array.fromLength(frames)
  let side = Float32Array.fromLength(frames)
  run(t, latency)
  run(t, frames, ~out, ~side)
  (out, side)
}

// The same, with the key let go after `held` frames, in stereo, for listening.
let renderStereo = (t, values, ~note, ~cents, ~held, ~frames) => {
  restore(t)
  send(t, values)
  t.instance->sendParam("Tune_Main", 440. * Math.pow(2., ~exp=cents / 1200.))
  run(t, settle)
  t.instance->sendMidi(noteMessage(0x90, note, velocity))
  run(t, latency)
  let left = Float32Array.fromLength(frames)
  let right = Float32Array.fromLength(frames)
  let pos = ref(0)
  let released = ref(false)
  while pos.contents < frames {
    if !released.contents && pos.contents >= held {
      t.instance->sendMidi(noteMessage(0x80, note, 0))
      released := true
    }
    let limit = released.contents ? frames : Math.Int.min(frames, held)
    let k = Math.Int.min(block, limit - pos.contents)
    t.instance->advance(k)
    t.instance->getOutputFrames([t.left, t.right], k, 0)
    left->blit(t.left->TypedArray.subarray(~start=0, ~end=k), pos.contents)
    right->blit(t.right->TypedArray.subarray(~start=0, ~end=k), pos.contents)
    pos := pos.contents + k
  }
  (left, right)
}

// Finds the pages renders change: renders each probe (values that between them switch every
// part a candidate can have on) as long as a candidate's render, and notes what changed.
let learnPages = (t, probes: array<array<(string, float)>>, ~note, ~frames) =>
  t.base->Option.forEach(b => {
    b.dirty = None
    let marks = Uint8Array.fromLength(pageCount(t))
    probes->Array.forEach(values => {
      render(t, values, ~note, ~cents=0., ~frames)->ignore
      markDiffering(memory(t), b.sums, marks)->ignore
    })
    restoreAll(t, b)
    let ranges = rangesOf(marks)
    b.dirty = Some((ranges, bytesOf(memory(t), ranges)))
    t.sinceCheck = 0
  })

// How much is put back before each render, in bytes (for tests).
let restoredBytes = t =>
  t.base->Option.mapOr(0, b =>
    switch b.dirty {
    | Some((_, bytes)) => TypedArray.length(bytes)
    | None => TypedArray.length(memory(t))
    }
  )
