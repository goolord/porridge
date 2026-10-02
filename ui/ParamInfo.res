// Host-facing metadata per parameter index (used by tools/gen.mjs to declare the patch's
// endpoints): name, range, default, switch names, a unit when the internal value is the
// number the original displays, and whether hosts list it.

// The original has a few duplicate or misleading names, and leaves the unison parameters
// unnamed; hosts need unique ones.
let renamed = id =>
  switch id {
  | "LFO_2_Unit" => Some("LFO 2 unit")
  | "C_Mode" => Some("Chorus mode")
  | "C_Stereo" => Some("Chorus stereo")
  | "D_On" => Some("Delay on")
  | "D_ReverseL" => Some("D reverse L")
  | "D_ReverseR" => Some("D reverse R")
  | "R_On" => Some("Reverb on")
  | "PolyMode" => Some("Voice mode")
  | "LFO_1_2" => Some("LFO 1 > LFO 2 rate")
  | "LFO_2_1" => Some("LFO 2 > LFO 1 rate")
  | "U_Voices" => Some("Unison voices")
  | "U_Detune" => Some("Unison detune")
  | "U_Spread" => Some("Unison spread")
  | "U_PitchJitter" => Some("Unison pitch jitter")
  | "U_PanJitter" => Some("Unison pan jitter")
  | _ => None
  }

let defs = ParamDefs.all

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

// Parameters that set up routing rather than the sound (where a connection or an Oatmeal mod
// slot goes and what it hears, which effect a rack or voice slot holds, the custom shape's
// points, MIDI setup, tuning, Oat mode): hosts don't list them (automatable: false). The patch
// still has them, so presets, the plugin's saved state and the view set and read them as before.
let oatmealSetup = /^(M[12]_Target_\d|XY_[HV]_(Target_\d|CC)|CC\d(_Target_\d)?|MIDI_Channel_\d+|Tune_\w+)$/

let porridgeSetup = Lazy.make(() => {
  let distortion = PorridgeParams.rackKinds->Array.find(k => k.key == "distortion")->Option.getOrThrow
  let shaper = PorridgeParams.shaperParams->Array.map(Pair.first)
  Set.fromArray([
    ...ModMatrix.slotNumbers->Array.flatMap(k =>
      ModMatrix.slotIds(k)->Array.filter(id => id != ModMatrix.amountId(k))
    ),
    ...shaper,
    ...distortion.copies->Array.flatMap(n => shaper->Array.map(PorridgeParams.copyId(_, n))),
    ...Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1)),
    ...PorridgeParams.laneSpecs->Array.map(s => s.id),
    "FX_Order",
    "MM_Follow",
    "MPE_On",
    "MPE_BendRange",
    "Oat_Mode",
  ])
})

let isSetup = id =>
  switch id {
  | "SustainPedal" | "AftertouchMode" | "BendRange" | "Voices" | "Sat_Mode" | "F_Double" => true
  | id => oatmealSetup->RegExp.test(id) || Lazy.get(porridgeSetup)->Set.has(id)
  }

type t = {
  hostName: string,
  min: float,
  max: float,
  init: float,
  names: option<array<string>>,
  unit: option<string>,
  automatable: bool,
}

let paramInfo = index => {
  let d = Lazy.get(defs)->Array.getUnsafe(index)
  let hostName = renamed(d.id)->Option.getOr(d.name)
  {
    hostName,
    min: d.min,
    max: d.max,
    init: d.init,
    names: d.names,
    unit: unitFor(d),
    automatable: !isSetup(d.id),
  }
}
