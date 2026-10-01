// Parameters Porridge has and Oatmeal doesn't. They follow Oatmeal's 342 parameters as host
// parameters, and live in the synth's parameter mirror from slot `firstSlot` on.
// Append only: hosts and presets know parameters by id, and the order fixes the host order.
// Every default leaves the sound exactly as Oatmeal's, except Oat_Mode: off by default, so
// MIDI lands on its own sample rather than at the next 64-sample block.

type kind =
  | Float({min: float, max: float, init: float, text: float => string, unit?: string})
  | Choice({names: array<string>, init: int})

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
]

let slotOf = i => firstSlot + i
