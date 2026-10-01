// The synth as the sound matcher renders it: Porridge's DSP compiled to WebAssembly
// (bundle/match-engine.js and .wasm, built by tools/match-engine.mjs), one instance per worker.
//
// Every render starts from the same state: the base patch is loaded and settled once, the
// instance's memory is kept, and before each candidate it is put back. Renders are
// deterministic, so a candidate's loss means the same each time.

type engineClass
type wasmModule
type instance
type state

let construct: engineClass => instance = %raw(`C => new C()`)
@set external setModule: (instance, wasmModule) => unit = "wasmModule"
@send external initialise: (instance, int, float) => promise<bool> = "initialise"
@send external advance: (instance, int) => unit = "advance"
@send external getOutputFrames: (instance, array<Float32Array.t>, int, int) => unit = "getOutputFrames_out"
@send external getState: instance => state = "getState"
@send external restoreState: (instance, state) => unit = "restoreState"
@send external sendMidi: (instance, {"message": int}) => unit = "sendInputEvent_midiIn"
@send external sendShape: (instance, Bank.shapePayload) => unit = "sendInputEvent_shapeIn"
@send external sendCurve: (instance, Bank.shapePayload) => unit = "sendInputEvent_curveIn"

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

type t = {
  instance: instance,
  left: Float32Array.t,
  right: Float32Array.t,
  // the base patch, loaded and settled
  mutable snapshot: option<state>,
}

let make = async (cls, module_) => {
  let instance = construct(cls)
  instance->setModule(module_)
  let _ = await instance->initialise(2, sampleRate)
  {instance, left: Float32Array.fromLength(block), right: Float32Array.fromLength(block), snapshot: None}
}

let send = (t, values: array<(string, float)>) =>
  values->Array.forEach(((id, v)) => t.instance->sendParam(id, v))

// Runs n frames, adding the mono mix into out from `at` (or dropping it without out).
let run = (t, n, ~out=?, ~at=0) => {
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
    | None => ()
    }
    pos := pos.contents + k
  }
}

// Loads the patch every candidate starts from: its values and its waveforms and curves.
let setBase = (t, values: Bank.values, tables: OatmealFormat.tables) => {
  t.snapshot->Option.forEach(s => t.instance->restoreState(s))
  values->Map.forEachWithKey((v, id) => t.instance->sendParam(id, v))
  OatmealFormat.allTables->Array.forEach(table => {
    let {which, endpoint} = OatmealFormat.tableInfo(table)
    let payload: Bank.shapePayload = {which, data: Bank.arrayOfFloats(tables->OatmealFormat.getTable(table))}
    endpoint == "shapeIn" ? t.instance->sendShape(payload) : t.instance->sendCurve(payload)
  })
  t.instance->sendMidi({"message": 0xb0 * 65536 + 123 * 256})
  run(t, 8192)
  t.snapshot = Some(t.instance->getState)
}

let noteMessage = (status, note, vel) => {"message": status * 65536 + note * 256 + vel}

// A note held for `frames` (the key played `note`, tuned by `cents`) with these values on the
// base, as mono samples.
let render = (t, values, ~note, ~cents, ~frames) => {
  t.snapshot->Option.forEach(s => t.instance->restoreState(s))
  send(t, values)
  t.instance->sendParam("Tune_Main", 440. * Math.pow(2., ~exp=cents / 1200.))
  run(t, settle)
  t.instance->sendMidi(noteMessage(0x90, note, velocity))
  let out = Float32Array.fromLength(frames)
  run(t, latency)
  run(t, frames, ~out)
  out
}

// The same, with the key let go after `held` frames, in stereo, for listening.
let renderStereo = (t, values, ~note, ~cents, ~held, ~frames) => {
  t.snapshot->Option.forEach(s => t.instance->restoreState(s))
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
