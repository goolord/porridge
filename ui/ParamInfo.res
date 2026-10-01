// Host-facing metadata per parameter index (used by tools/gen.mjs to declare the patch's
// endpoints): name, range, default, switch names, and a unit when the internal value is
// the number the original displays.

// The original has a few duplicate or misleading names; hosts need unique ones.
let renamed = index =>
  switch index {
  | 30 => Some("LFO 2 unit")
  | 67 => Some("Chorus mode")
  | 68 => Some("Chorus stereo")
  | 75 => Some("Delay on")
  | 78 => Some("D reverse L")
  | 79 => Some("D reverse R")
  | 90 => Some("Reverb on")
  | 103 => Some("Voice mode")
  | 29 => Some("LFO 1 > LFO 2 rate")
  | 40 => Some("LFO 2 > LFO 1 rate")
  | _ => None
  }

// The DLL leaves 124..128 unnamed.
let unisonNames = [
  "Unison voices",
  "Unison detune",
  "Unison spread",
  "Unison pitch jitter",
  "Unison pan jitter",
]

let defs = Lazy.make(() => ParamDefs.makeDefs())

let unitFor = (d: ParamDefs.t) =>
  if d.names != None || d.isInt {
    None
  } else {
    // the unit is only meaningful when the displayed number equals the internal value
    let probe = [0.3, 0.7]->Array.map(d.fromNorm)
    let matchesValue = x =>
      switch /^(-?\d+(\.\d+)?) (ms|Hz|dB|st|cents|sec|semitones)\b/->RegExp.exec(d.valueText(x)) {
      | Some(m) =>
        switch RegExp.Result.matches(m)[0] {
        | Some(Some(number)) =>
          !(Math.abs(Float.parseFloat(number) - x) > 0.02 * Math.max(1., Math.abs(x)))
        | _ => false
        }
      | None => false
      }
    if probe->Array.every(matchesValue) {
      probe[0]
      ->Option.flatMap(x => /^-?\d+(\.\d+)? (\S+)/->RegExp.exec(d.valueText(x)))
      ->Option.flatMap(m => RegExp.Result.matches(m)[1]->Option.flatMap(unit => unit))
    } else {
      None
    }
  }

type t = {
  hostName: string,
  min: float,
  max: float,
  init: float,
  names: option<array<string>>,
  unit: option<string>,
}

let paramInfo = index => {
  let d = Lazy.get(defs)->Array.getUnsafe(index)
  let hostName = switch renamed(index) {
  | Some(name) => name
  | None => unisonNames[index - 124]->Option.getOr(d.name)
  }
  {hostName, min: d.min, max: d.max, init: d.init, names: d.names, unit: unitFor(d)}
}
