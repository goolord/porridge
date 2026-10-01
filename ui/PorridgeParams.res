// Parameters Porridge has and Oatmeal doesn't. They follow Oatmeal's 342 parameters as host
// parameters, and live in the synth's parameter mirror from slot `firstSlot` on.
// Append only: hosts and presets know parameters by id, and the order fixes the host order.
// Every default leaves the sound exactly as Oatmeal's, except Oat_Mode: off by default, so
// MIDI lands on its own sample rather than at the next 64-sample block.

type kind =
  | Float({min: float, max: float, init: float, text: float => string, unit?: string})
  | Choice({names: array<string>, init: int})
  // the same range, knob law and text as an Oatmeal parameter (a second effect's copy of it)
  | Like(string)

type spec = {id: string, name: string, kind: kind}

let firstSlot = 2600

let percent = x => Float.toFixed(x * 100., ~digits=1) ++ " %"
let signedPercent = x => (x > 0. ? "+" : "") ++ Float.toFixed(x * 100., ~digits=1) ++ " %"

let macroSpecs = Array.fromInitializer(~length=ModMatrix.macros, i => {
  id: ModMatrix.macroId(i + 1),
  name: `Macro ${Int.toString(i + 1)}`,
  kind: Float({min: 0., max: 1., init: 0., text: percent}),
})

let sourceNames = ModMatrix.sources->Array.map(s => s.label)
let targetNames = ModMatrix.targets->Array.map(t => t.label)

let slotSpecs = Array.fromInitializer(~length=ModMatrix.slots, i => {
  let k = i + 1
  let n = Int.toString(k)
  [
    {id: ModMatrix.sourceId(k), name: `Mod ${n} source`, kind: Choice({names: sourceNames, init: 0})},
    {id: ModMatrix.targetId(k), name: `Mod ${n} target`, kind: Choice({names: targetNames, init: 0})},
    {
      id: ModMatrix.amountId(k),
      name: `Mod ${n} amount`,
      kind: Float({min: -1., max: 1., init: 0., text: signedPercent}),
    },
    {id: ModMatrix.viaId(k), name: `Mod ${n} via`, kind: Choice({names: sourceNames, init: 0})},
  ]
})->Array.flat

let semitones = x => Float.toFixed(x, ~digits=1) ++ " st"

let mpeSpecs = [
  {id: "MPE_On", name: "MPE", kind: Choice({names: ["off", "on"], init: 0})},
  {
    id: "MPE_BendRange",
    name: "MPE note bend range",
    kind: Float({min: 0., max: 96., init: 48., text: semitones}),
  },
]

let onOff = ["off", "on"]
let fixedUnit = (digits, unit) => x => Float.toFixed(x, ~digits) ++ " " ++ unit
let signedPercentOrZero = x => x == 0. ? "0 %" : signedPercent(x)

// Oat mode keeps the Oatmeal behaviour Porridge otherwise improves on: MIDI (and the
// arpeggiator) applied at the start of the next 64-sample block instead of on its sample.
let oatSpecs = [{id: "Oat_Mode", name: "Oat mode", kind: Choice({names: onOff, init: 0})}]

// Slow random pitch and cutoff offsets: per unison copy for pitch, per voice for cutoff.
let driftSpecs = [
  {id: "Drift_Pitch", name: "Drift pitch", kind: Float({min: 0., max: 50., init: 0., text: fixedUnit(1, "cents")})},
  {
    id: "Drift_Cutoff",
    name: "Drift cutoff",
    kind: Float({min: 0., max: 12., init: 0., text: semitones}),
  },
  {id: "Drift_Rate", name: "Drift rate", kind: Float({min: 0.02, max: 5., init: 0.5, text: fixedUnit(2, "Hz")})},
]

// The order of chorus, delay, reverb and EQ: every permutation, Oatmeal's first.
let fxNames = ["chorus", "delay", "reverb", "EQ"]
let fxShort = ["C", "D", "R", "EQ"]

// Permutation k of 0..3 in lexicographic order (the DSP decodes it the same way).
let fxOrder = k => {
  let left = [0, 1, 2, 3]
  let k = ref(k)
  [6, 2, 1, 1]->Array.map(f => {
    let i = k.contents / f
    k := mod(k.contents, f)
    let x = left->Array.getUnsafe(i)
    left->Array.splice(~start=i, ~remove=1, ~insert=[])
    x
  })
}

// The permutation index of an order.
let fxOrderIndex = (order: array<int>) =>
  Array.fromInitializer(~length=24, i => i)
  ->Array.find(k => fxOrder(k) == order)
  ->Option.getOr(0)

let fxOrderSpecs = [
  {
    id: "FX_Order",
    name: "Effects order",
    kind: Choice({
      names: Array.fromInitializer(~length=24, k =>
        fxOrder(k)->Array.map(i => fxShort->Array.getUnsafe(i))->Array.join(" > ")
      ),
      init: 0,
    }),
  },
]

// Osc mix modes PM 2 > 1 and PM 1 feedback: osc 1's self-feedback.
let pmSpecs = [{id: "PM_Feedback", name: "PM feedback", kind: Float({min: 0., max: 1., init: 0., text: percent})}]

// The zero-delay-feedback filters' morph: SVF lowpass > bandpass > highpass; formant vowel.
let filterSpecs = [{id: "F_Morph", name: "Filter morph", kind: Float({min: 0., max: 1., init: 0., text: percent})}]

// A shape per envelope stage: 0 is Oatmeal's (linear attack, exponential decays), positive
// moves away from the start level faster, negative slower.
let envNames = [("Amp", "Amp"), ("Filter", "Filter"), ("Mod1", "Mod 1"), ("Mod2", "Mod 2")]
let stageNames = [("Attack", "attack"), ("Decay", "decay"), ("Release", "release")]

let curveId = (env, stage) => `Curve_${env}_${stage}`

let curveSpecs = envNames->Array.flatMap(((env, envName)) =>
  stageNames->Array.map(((stage, stageName)) => {
    id: curveId(env, stage),
    name: `${envName} env ${stageName} curve`,
    kind: Float({min: -1., max: 1., init: 0., text: signedPercentOrZero}),
  })
)

let lfoSteps = ["off", "2", "3", "4", "6", "8", "12", "16", "24", "32"]

let lfoSpecs = [1, 2]->Array.flatMap(n => {
  let l = `LFO_${Int.toString(n)}`
  let name = `LFO ${Int.toString(n)}`
  [
    {id: l ++ "_Delay", name: name ++ " delay", kind: Float({min: 0., max: 5000., init: 0., text: fixedUnit(0, "ms")})},
    {id: l ++ "_Fade", name: name ++ " fade-in", kind: Float({min: 0., max: 5000., init: 0., text: fixedUnit(0, "ms")})},
    {id: l ++ "_Slew", name: name ++ " slew", kind: Float({min: 0., max: 1., init: 0., text: percent})},
    {id: l ++ "_Steps", name: name ++ " sample & hold", kind: Choice({names: lfoSteps, init: 0})},
    {id: l ++ "_OneShot", name: name ++ " one-shot", kind: Choice({names: onOff, init: 0})},
  ]
})

let unisonSpecs = [
  {id: "U_DetuneCurve", name: "Unison detune curve", kind: Float({min: 0., max: 1., init: 0., text: percent})},
  {id: "U_RandomPhase", name: "Unison random phase", kind: Choice({names: onOff, init: 0})},
  {id: "U_Width", name: "Unison width", kind: Float({min: 0., max: 2., init: 1., text: percent})},
]

// The distortion's custom shape (its type "custom shape"), like Fruity WaveShaper: up to
// shaperPoints points from input -1 to 1 (the first and last at the ends), each with the
// output there and the bend of the segment that ends at it. Shaper_Points holds the count
// less 2. The DSP renders it into a table whenever it changes.
let shaperPoints = 16
let shaperX = k => `Sat_X${Int.toString(k)}`
let shaperY = k => `Sat_Y${Int.toString(k)}`
let shaperBend = k => `Sat_C${Int.toString(k)}`
let signed2 = x => Float.toFixed(x, ~digits=2)

let shaperParams: array<(string, string)> = [
  ("Sat_Points", "points"),
  ...Array.fromInitializer(~length=shaperPoints, i => {
    let n = Int.toString(i + 1)
    [(shaperX(i + 1), `point ${n} in`), (shaperY(i + 1), `point ${n} out`), (shaperBend(i + 1), `point ${n} bend`)]
  })->Array.flat,
]

let shaperSpecs = [
  {
    id: "Sat_Points",
    name: "Dist shape points",
    kind: Choice({names: Array.fromInitializer(~length=shaperPoints - 1, i => Int.toString(i + 2)), init: 0}),
  },
  ...Array.fromInitializer(~length=shaperPoints, i => {
    let k = i + 1
    let n = Int.toString(k)
    // two points: a straight line from (-1, -1) to (1, 1)
    let end = k == 1 ? -1. : 1.
    [
      {id: shaperX(k), name: `Dist shape point ${n} in`, kind: Float({min: -1., max: 1., init: end, text: signed2})},
      {id: shaperY(k), name: `Dist shape point ${n} out`, kind: Float({min: -1., max: 1., init: end, text: signed2})},
      {id: shaperBend(k), name: `Dist shape point ${n} bend`, kind: Float({min: -1., max: 1., init: 0., text: signedPercentOrZero})},
    ]
  })->Array.flat,
]

// The effects rack: up to eight effects on the whole sound, in any order, each of them up to
// four times. The first chorus, delay, reverb and EQ are Oatmeal's; the others are copies, with
// Oatmeal's parameters again under numbered ids (D_Wet: D2_Wet, D3_Wet, D4_Wet). The rack's
// distortions are copies of Oatmeal's distortion (Sat2_ .. Sat5_), which itself stays in the
// voices or before the rack.
//
// A rack slot holds one effect (rackEntries). Slots holding one of Oatmeal's four take them in
// FX_Order's order, so FX_Order still orders them, and programs from before the rack, which
// leave it at its default, keep their order. The DSP runs a copy by swapping its parameters into
// the first's slots.
let rackSlots = 8
let rackId = k => `FX_Rack_${Int.toString(k)}`

type rackKind = {
  key: string,
  name: string,
  // the first's parameters, with names for the copies' host parameters
  params: array<(string, string)>,
  // the copies' numbers
  copies: array<int>,
}

let rackKinds = [
  {
    key: "chorus",
    name: "Chorus",
    params: [
      ("C_Mode", "mode"),
      ("C_Stereo", "stereo"),
      ("C_Voices", "voices"),
      ("C_Rate", "speed"),
      ("C_MinDelay", "delay"),
      ("C_Depth", "depth"),
      ("C_Feedback", "feedback"),
      ("C_Mix", "mix"),
    ],
    copies: [2, 3, 4],
  },
  {
    key: "delay",
    name: "Delay",
    params: [
      ("D_On", "on"),
      ("D_Unit", "unit"),
      ("D_Quantize", "quantize"),
      ("D_ReverseL", "reverse L"),
      ("D_ReverseR", "reverse R"),
      ("D_LengthL", "length L"),
      ("D_LengthR", "length R"),
      ("D_FeedbackL", "feedback L"),
      ("D_FeedbackR", "feedback R"),
      ("D_InputPan", "input pan"),
      ("D_Rotation", "rotation"),
      ("D_LP", "lowpass"),
      ("D_HP", "highpass"),
      ("D_Dry", "dry out"),
      ("D_Wet", "wet out"),
    ],
    copies: [2, 3, 4],
  },
  {
    key: "reverb",
    name: "Reverb",
    params: [
      ("R_On", "on"),
      ("R_Size", "size"),
      ("R_Length", "length"),
      ("R_Dullness", "dullness"),
      ("R_Brightness", "brightness"),
      ("R_Dry", "dry out"),
      ("R_Wet", "wet out"),
      ("R_1", "1"),
      ("R_2", "2"),
      ("R_3", "3"),
      ("R_Rotation", "rotation"),
      ("R_Predelay", "predelay"),
      ("R_EarlyMix", "early mix"),
    ],
    copies: [2, 3, 4],
  },
  {
    key: "eq",
    name: "EQ",
    params: [("EQ_On", "on"), ...[1, 2, 3, 4, 5]->Array.flatMap(b => {
      let n = Int.toString(b)
      [
        (`EQ_${n}_Freq`, `band ${n} freq`),
        (`EQ_${n}_Amp`, `band ${n} amp`),
        (`EQ_${n}_Slope`, `band ${n} slope`),
        (`EQ_${n}_Type`, `band ${n} type`),
      ]
    })],
    copies: [2, 3, 4],
  },
  {
    key: "distortion",
    name: "Distortion",
    params: [
      ("Sat_Type", "type"),
      ("Sat_Oversample", "oversample"),
      ("Sat_Pregain", "pregain"),
      ("Sat_Limit", "limit"),
      ("Sat_Postgain", "postgain"),
      ...shaperParams,
    ],
    copies: [2, 3, 4, 5],
  },
]

// The id of copy n's parameter (D_Wet, 3: D3_Wet).
let copyId = (id, n) =>
  switch String.indexOf(id, "_") {
  | i if i > 0 => String.slice(id, ~start=0, ~end=i) ++ Int.toString(n) ++ String.slice(id, ~start=i)
  | _ => id
  }

// What a rack slot can hold, by value: nothing, Oatmeal's four, then every copy.
let rackEntries: array<option<(string, int)>> = [
  None,
  Some(("chorus", 1)),
  Some(("delay", 1)),
  Some(("reverb", 1)),
  Some(("eq", 1)),
  ...rackKinds->Array.flatMap(k => k.copies->Array.map(n => Some((k.key, n)))),
]

let rackNames = rackEntries->Array.map(entry =>
  switch entry {
  | None => "empty"
  | Some((key, n)) =>
    let name = rackKinds->Array.find(k => k.key == key)->Option.mapOr(key, k => k.name)
    n == 1 ? name : `${name} ${Int.toString(n)}`
  }
)

// Oatmeal's chain: chorus, delay, reverb, EQ
let rackDefault = [1, 2, 3, 4, 0, 0, 0, 0]

let rackSpecs = Array.fromInitializer(~length=rackSlots, i => {
  id: rackId(i + 1),
  name: `FX slot ${Int.toString(i + 1)}`,
  kind: Choice({names: rackNames, init: rackDefault->Array.getUnsafe(i)}),
})

// Oatmeal's EQ has no switch; Porridge's switches it (and its copies) off without losing its bands.
let eqOnSpecs = [{id: "EQ_On", name: "EQ on", kind: Choice({names: onOff, init: 1})}]

let copySpecs = rackKinds->Array.flatMap(k =>
  k.copies->Array.flatMap(n =>
    k.params->Array.map(((id, label)) => {
      id: copyId(id, n),
      name: `${k.name} ${Int.toString(n)} ${label}`,
      kind: Like(id),
    })
  )
)

let all = [
  ...macroSpecs,
  ...slotSpecs,
  ...mpeSpecs,
  ...oatSpecs,
  ...driftSpecs,
  ...fxOrderSpecs,
  ...pmSpecs,
  ...filterSpecs,
  ...curveSpecs,
  ...lfoSpecs,
  ...unisonSpecs,
  ...rackSpecs,
  ...eqOnSpecs,
  ...shaperSpecs,
  ...copySpecs,
]

let slotOf = i => firstSlot + i
