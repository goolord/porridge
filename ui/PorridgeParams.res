// Parameters Porridge has and Oatmeal doesn't. They follow Oatmeal's 342 parameters as host
// parameters, and live in the synth's parameter mirror from slot `firstSlot` on.
// Append only: hosts and presets know parameters by id, and the order fixes the host order.
// Every default leaves the sound exactly as Oatmeal's, except Oat_Mode: off by default, so
// MIDI lands on its own sample rather than at the next 64-sample block.

type kind =
  // read: a typed value (in the text's units) to the parameter's value
  | Float({min: float, max: float, init: float, text: float => string, read?: string => option<float>})
  // list: the value list it shows, if it's one of those (ValueList)
  | Choice({names: array<string>, init: int, list?: ValueList.t})
  // the same range, knob law and text as an Oatmeal parameter (a second effect's copy of it)
  | Like(string)
  // ... with a default of its own
  | LikeWithDefault(string, float)

// about: what it does, which its status text says after its value
type spec = {id: string, name: string, kind: kind, about?: string}

let firstSlot = 2600

let percent = x => Float.toFixed(x * 100., ~digits=1) ++ " %"

// A knob that holds its position 0..1 for a value from lo to hi on a log scale (frequencies,
// rates, times), so that hosts automate it as it turns; the DSP works out lo * (hi / lo) ^ v.
let expValue = (lo: float, hi: float, v: float) => lo * Math.pow(hi / lo, ~exp=v)
let expPos = (lo: float, hi: float, x: float) => Math.log(x / lo) / Math.log(hi / lo)

// A typed number, with k for thousands ("1.5k", "2 kHz")
let typedNumber = s => {
  let x = Float.parseFloat(s)
  let k = String.includes(String.toLowerCase(s), "k") && !String.includes(String.toLowerCase(s), "ms")
  Float.isFinite(x) ? Some(k ? x * 1000. : x) : None
}

let expKnob = (~lo, ~hi, ~init, ~text) => Float({
  min: 0.,
  max: 1.,
  init: expPos(lo, hi, init),
  text: v => text(expValue(lo, hi, v)),
  read: s => typedNumber(s)->Option.map(x => Math.max(0., Math.min(1., expPos(lo, hi, Math.max(x, lo))))),
})

let hzText = (x: float) =>
  x >= 1000. ? Float.toFixed(x / 1000., ~digits=2) ++ " kHz" : Float.toFixed(x, ~digits=x < 100. ? 1 : 0) ++ " Hz"
let msText = (x: float) => x >= 1000. ? Float.toFixed(x / 1000., ~digits=2) ++ " s" : Float.toFixed(x, ~digits=x < 10. ? 2 : 1) ++ " ms"
let secondsText = (x: float) => Float.toFixed(x, ~digits=x < 10. ? 2 : 1) ++ " s"
let dbText = (x: float) => (x > 0. ? "+" : "") ++ Float.toFixed(x, ~digits=1) ++ " dB"
let degreesText = (x: float) => Float.toFixed(x, ~digits=0) ++ "°"
let signedPercent = x => (x > 0. ? "+" : "") ++ Float.toFixed(x * 100., ~digits=1) ++ " %"

let macroSpecs = Array.fromInitializer(~length=ModMatrix.macros, i => {
  id: ModMatrix.macroId(i + 1),
  name: `Macro ${Int.toString(i + 1)}`,
  kind: Float({min: 0., max: 1., init: 0., text: percent}),
})

let sourceNames = ModMatrix.sources->Array.map(s => s.label)
let targetNames = ModMatrix.targets->Array.map(t => t.label)

// slots first .. last (1-based)
let slotSpecsFor = (first, last) =>
  Array.fromInitializer(~length=last - first + 1, i => {
    let k = first + i
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

let slotSpecs = slotSpecsFor(1, ModMatrix.firstSlots)

// The slots that came later, then every slot's options: hold (the value latched when the note
// starts, so that each note keeps the one it began with), slew (the value eased towards, for a
// time up to 2 s) and curve (the source bent before the amount: see ModMatrix.curved). Then
// which note a per-note source follows when it moves something on the whole sound.
let moreSlotSpecs = slotSpecsFor(ModMatrix.firstSlots + 1, ModMatrix.slots)

let slewText = x => x <= 0. ? "off" : msText(ModMatrix.slewMs(x))

let slotOptionSpecs = Array.fromInitializer(~length=ModMatrix.slots, i => {
  let k = i + 1
  let n = Int.toString(k)
  [
    {id: ModMatrix.holdId(k), name: `Mod ${n} hold`, kind: Choice({names: ["free", "latch at note-on"], init: 0})},
    {id: ModMatrix.slewId(k), name: `Mod ${n} slew`, kind: Float({min: 0., max: 1., init: 0., text: slewText})},
    {
      id: ModMatrix.curveId(k),
      name: `Mod ${n} curve`,
      kind: Float({min: -1., max: 1., init: 0., text: x => x == 0. ? "straight" : signedPercent(x)}),
    },
  ]
})->Array.flat

let followSpecs = [
  {
    id: "MM_Follow",
    name: "Mod follows",
    kind: Choice({names: ["the newest note", "every note, by level"], init: 0}),
  },
]

let semitones = x => Float.toFixed(x, ~digits=1) ++ " st"

let mpeSpecs = [
  {
    id: "MPE_On",
    name: "MPE",
    kind: Choice({names: ["off", "on"], init: 0}),
    about: "With MPE, controllers (bend, pressure, slide, CCs) move once per 64-sample block, smoothed; notes keep their own sample",
  },
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
// arpeggiator) applied at the start of the next 64-sample block instead of on its sample, and
// legato leaving the right side's filter envelopes untriggered (a stereo voice's right filter
// stays shut).
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
// moves away from the start level faster, negative slower. "Decay" is decay 2's; decay 1's
// came later, as a group of its own (decay1CurveSpecs).
//
// An envelope: its parameters' prefix (Attack, F_Attack ...), the name its curves go by
// (Curve_Amp_Attack ...), and its name in host parameter names.
type envelope = {prefix: string, curveName: string, name: string}

let ampEnv = {prefix: "", curveName: "Amp", name: "Amp"}
let filterEnv = {prefix: "F_", curveName: "Filter", name: "Filter"}
let modEnv = n => {prefix: `M${Int.toString(n)}_`, curveName: `Mod${Int.toString(n)}`, name: `Mod ${Int.toString(n)}`}
// (each oscillator's own envelope came later, with its curves: oscEnv)
let envelopes = [ampEnv, filterEnv, modEnv(1), modEnv(2)]

let stageNames = [("Attack", "attack"), ("Decay", "decay 2"), ("Release", "release")]

let curveId = (env, stage) => `Curve_${env}_${stage}`
let decay1CurveId = env => curveId(env, "Decay1")

let curveKind = Float({min: -1., max: 1., init: 0., text: signedPercentOrZero})

let curveSpecs = envelopes->Array.flatMap(env =>
  stageNames->Array.map(((stage, stageName)) => {
    id: curveId(env.curveName, stage),
    name: `${env.name} env ${stageName} curve`,
    kind: curveKind,
  })
)

let decay1CurveSpecs = envelopes->Array.map(env => {
  id: decay1CurveId(env.curveName),
  name: `${env.name} env decay 1 curve`,
  kind: curveKind,
})

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
// three times. The first chorus, delay, reverb and EQ are Oatmeal's; the others are copies, with
// Oatmeal's parameters again under numbered ids (D_Wet: D2_Wet, D3_Wet). The rack's distortions
// are copies of Oatmeal's distortion (Sat2_ .. Sat4_), which itself stays in the voices or
// before the rack.
//
// There were four of each (five distortions) until October 2026: every copy costs memory and
// host parameters whether it's used or not. The fourth copies are retired: their parameters are
// gone, but their rack values and modulation targets keep their places (presets and the DSP
// know those by number), and a program that used one loads it onto a free copy (Preset).
//
// A rack slot holds one effect (rackEntries). Slots holding one of Oatmeal's four take them in
// FX_Order's order, so FX_Order still orders them, and programs from before the rack, which
// leave it at its default, keep their order. The DSP runs a copy by swapping its parameters into
// the first's slots.
let rackSlots = 8
let rackId = k => `FX_Rack_${Int.toString(k)}`

// Where a kind of effect can run: only on the whole sound (the rack), there or in every voice
// (the voice lane, VL_1..4), or only in the voice lane.
type runsIn = Rack | Both | LaneOnly

type rackKind = {
  key: string,
  // its host parameters' name
  name: string,
  // its name in the add menus and the rack (the key when left out)
  menuName?: string,
  // what it does, for the add menus' hover texts
  about: string,
  // the value of its switch (its first parameter) that switches it on, by label ("on" when left
  // out): a chorus comes on as a sine, a distortion as soft clipping
  onLabel?: string,
  runsIn: runsIn,
  // the first's parameters, with names for the copies' host parameters
  params: array<(string, string)>,
  // the copies' numbers
  copies: array<int>,
  // the copies it had once, after those: retired (see above)
  retired?: array<int>,
  // Porridge's own effects: the first is in the rack too, as copy 1 (Oatmeal's chorus, delay,
  // reverb and EQ are the four FX_Order orders; its distortion sits before the rack)
  firstInRack: bool,
}

// The filter's drive: input gain into the analog types (FilterTypes.hasDrive), 0 .. +24 dB.
let driveText = (x: float) => "+" ++ Float.toFixed(x * 24., ~digits=1) ++ " dB"
let filterDriveSpecs = [
  {id: "F_Drive", name: "Filter drive", kind: Float({min: 0., max: 1., init: 0., text: driveText})},
]

//==============================================================================
// Porridge's own effects for the rack. Each has a switch (X_On) and its parameters; the copies
// number them like the others (Fl_Rate, Fl2_Rate ...). Frequencies, rates and times hold their
// knob position (expKnob): the DSP works out lo * (hi / lo) ^ v.

let onSpec = (id, name) => {id, name, kind: Choice({names: onOff, init: 0})}
let unit = (min, max, init) => Float({min, max, init, text: percent})
let bipolar = init => Float({min: -1., max: 1., init, text: signedPercentOrZero})
let decibels = (min, max, init) => Float({min, max, init, text: dbText})
let hzKnob = init => expKnob(~lo=20., ~hi=20000., ~init, ~text=hzText)
let rateKnob = init => expKnob(~lo=0.02, ~hi=20., ~init, ~text=fixedUnit(2, "Hz"))
let ratioText = x => Float.toFixed(x, ~digits=1) ++ ":1"

let flangerSpecs = [
  onSpec("Fl_On", "Flanger on"),
  {id: "Fl_Rate", name: "Flanger rate", kind: rateKnob(0.3)},
  {id: "Fl_Depth", name: "Flanger depth", kind: unit(0., 1., 0.5)},
  {id: "Fl_Delay", name: "Flanger delay", kind: expKnob(~lo=0.1, ~hi=20., ~init=1., ~text=msText)},
  {id: "Fl_Feedback", name: "Flanger feedback", kind: bipolar(0.5)},
  {id: "Fl_Phase", name: "Flanger stereo phase", kind: Float({min: 0., max: 180., init: 90., text: degreesText})},
  {id: "Fl_Mix", name: "Flanger mix", kind: unit(0., 1., 0.5)},
]

let phaserSpecs = [
  onSpec("Ph_On", "Phaser on"),
  {id: "Ph_Rate", name: "Phaser rate", kind: rateKnob(0.2)},
  {id: "Ph_Depth", name: "Phaser depth", kind: unit(0., 1., 0.6)},
  {id: "Ph_Freq", name: "Phaser frequency", kind: hzKnob(800.)},
  {id: "Ph_Feedback", name: "Phaser feedback", kind: bipolar(0.3)},
  {id: "Ph_Stages", name: "Phaser stages", kind: Choice({names: ["2", "4", "6", "8", "12", "16"], init: 2})},
  {id: "Ph_Spread", name: "Phaser stage spread", kind: unit(0., 1., 0.5)},
  {id: "Ph_Phase", name: "Phaser stereo phase", kind: Float({min: 0., max: 180., init: 90., text: degreesText})},
  {id: "Ph_Track", name: "Phaser note tracking", kind: unit(0., 1., 0.)},
  {id: "Ph_Mix", name: "Phaser mix", kind: unit(0., 1., 0.5)},
]

// The compressor, multiband like Dynastia or OTT: three bands (or one: the mid band's settings),
// each compressed downward above its threshold and upward below its up threshold, then trimmed.
// The compress amount scales every band's gain change; mix blends with the dry sound.
let compressorBands = [("Low", "low"), ("Mid", "mid"), ("High", "high")]

let compressorSpecs = [
  onSpec("Cp_On", "Compressor on"),
  {id: "Cp_Bands", name: "Compressor bands", kind: Choice({names: ["single band", "3 bands"], init: 1})},
  {id: "Cp_Depth", name: "Compressor amount", kind: unit(0., 1., 1.)},
  {id: "Cp_Attack", name: "Compressor attack", kind: expKnob(~lo=0.1, ~hi=300., ~init=10., ~text=msText)},
  {id: "Cp_Release", name: "Compressor release", kind: expKnob(~lo=5., ~hi=3000., ~init=120., ~text=msText)},
  {id: "Cp_InGain", name: "Compressor input gain", kind: decibels(-24., 24., 0.)},
  {id: "Cp_OutGain", name: "Compressor output gain", kind: decibels(-24., 24., 0.)},
  {id: "Cp_LowSplit", name: "Compressor low split", kind: hzKnob(120.)},
  {id: "Cp_HighSplit", name: "Compressor high split", kind: hzKnob(2500.)},
  {id: "Cp_Mix", name: "Compressor mix", kind: unit(0., 1., 1.)},
  ...compressorBands->Array.flatMap(((band, name)) => [
    {id: `Cp_${band}Thresh`, name: `Compressor ${name} threshold`, kind: decibels(-60., 0., -24.)},
    {id: `Cp_${band}Ratio`, name: `Compressor ${name} ratio`, kind: Float({min: 1., max: 20., init: 4., text: ratioText})},
    {id: `Cp_${band}UpThresh`, name: `Compressor ${name} up threshold`, kind: decibels(-60., 0., -48.)},
    {id: `Cp_${band}UpRatio`, name: `Compressor ${name} up ratio`, kind: Float({min: 1., max: 10., init: 2., text: ratioText})},
    {id: `Cp_${band}Gain`, name: `Compressor ${name} gain`, kind: decibels(-24., 24., 0.)},
    {id: `Cp_${band}On`, name: `Compressor ${name} band on`, kind: Choice({names: onOff, init: 1})},
  ]),
]

let reverbModels = ["hall", "plate", "nitrous", "basin", "vintage"]

let spaceSpecs = [
  onSpec("Rv_On", "Algo reverb on"),
  {id: "Rv_Model", name: "Algo reverb model", kind: Choice({names: reverbModels, init: 0})},
  {id: "Rv_Size", name: "Algo reverb size", kind: unit(0., 1., 0.5)},
  {id: "Rv_Decay", name: "Algo reverb decay", kind: expKnob(~lo=0.1, ~hi=30., ~init=2., ~text=secondsText)},
  {id: "Rv_Predelay", name: "Algo reverb predelay", kind: Float({min: 0., max: 250., init: 0., text: msText})},
  {id: "Rv_Damp", name: "Algo reverb damping", kind: hzKnob(8000.)},
  {id: "Rv_LowCut", name: "Algo reverb low cut", kind: hzKnob(80.)},
  {id: "Rv_Width", name: "Algo reverb width", kind: unit(0., 1., 1.)},
  {id: "Rv_Mod", name: "Algo reverb modulation", kind: unit(0., 1., 0.3)},
  {id: "Rv_Mix", name: "Algo reverb mix", kind: unit(0., 1., 0.3)},
]

// The convolver's impulses: built in (the DSP makes them), and a file of the user's (each
// convolver has one, kept with the program).
let impulseNames = [
  "room",
  "hall",
  "cathedral",
  "plate",
  "spring",
  "cabinet 1×12",
  "cabinet 4×12",
  "metal tank",
  "telephone",
  "swell",
  "noise bloom",
  "file",
]
let impulseFile = Array.length(impulseNames) - 1

let convolveSpecs = [
  onSpec("Cv_On", "Convolve on"),
  {id: "Cv_Impulse", name: "Convolve impulse", kind: Choice({names: impulseNames, init: 1})},
  {id: "Cv_Mix", name: "Convolve mix", kind: unit(0., 1., 0.3)},
  {id: "Cv_Predelay", name: "Convolve predelay", kind: Float({min: 0., max: 250., init: 0., text: msText})},
  {id: "Cv_Length", name: "Convolve length", kind: unit(0.02, 1., 1.)},
  {id: "Cv_Reverse", name: "Convolve reverse", kind: Choice({names: onOff, init: 0})},
  {id: "Cv_LowCut", name: "Convolve low cut", kind: hzKnob(20.)},
  {id: "Cv_HighCut", name: "Convolve high cut", kind: hzKnob(20000.)},
  {id: "Cv_Width", name: "Convolve width", kind: unit(0., 1., 1.)},
  {id: "Cv_Gain", name: "Convolve gain", kind: decibels(-24., 24., 0.)},
]

// The frequency shifter's shift: the knob (-1..1) cubed, times 5 kHz.
let bodeShift = (v: float) => v * v * v * 5000.
let bodeShiftText = v => {
  let hz = bodeShift(v)
  let size = Math.abs(hz)
  (hz > 0. ? "+" : "") ++ (
    size >= 1000.
      ? Float.toFixed(hz / 1000., ~digits=2) ++ " kHz"
      : Float.toFixed(hz, ~digits=size < 10. ? 2 : 1) ++ " Hz"
  )
}
let bodeShiftValue = (hz: float) => {
  let v = Math.min(1., Math.cbrt(Math.abs(hz) / 5000.))
  hz < 0. ? -.v : v
}

let bodeSpecs = [
  onSpec("Bd_On", "Bode on"),
  {
    id: "Bd_Shift",
    name: "Bode shift",
    kind: Float({min: -1., max: 1., init: 0.2, text: bodeShiftText, read: s => typedNumber(s)->Option.map(bodeShiftValue)}),
  },
  {id: "Bd_Mode", name: "Bode mode", kind: Choice({names: ["up", "down", "stereo (L up, R down)", "ring"], init: 0})},
  {id: "Bd_Feedback", name: "Bode feedback", kind: unit(0., 1., 0.)},
  {id: "Bd_Delay", name: "Bode delay", kind: expKnob(~lo=1., ~hi=1000., ~init=100., ~text=msText)},
  {id: "Bd_Mix", name: "Bode mix", kind: unit(0., 1., 0.5)},
]

let filterFxSpecs = [
  onSpec("Ff_On", "FX filter on"),
  {id: "Ff_Type", name: "FX filter type", kind: Choice({names: FilterTypes.all, init: 16, list: FxFilterType})},
  {id: "Ff_Cutoff", name: "FX filter cutoff", kind: hzKnob(1200.)},
  {id: "Ff_Resonance", name: "FX filter resonance", kind: unit(0., 1., 0.2)},
  {id: "Ff_Morph", name: "FX filter morph", kind: unit(0., 1., 0.)},
  {id: "Ff_Drive", name: "FX filter drive", kind: Float({min: 0., max: 1., init: 0., text: driveText})},
  {id: "Ff_Spread", name: "FX filter stereo spread", kind: Float({min: -24., max: 24., init: 0., text: semitones})},
  {id: "Ff_Mix", name: "FX filter mix", kind: unit(0., 1., 1.)},
]

let bassMonoText = (v: float) => v <= 0. ? "off" : hzText(expValue(20., 1000., v))
let bassMonoValue = (hz: float) => hz < 20. ? 0. : Math.min(1., expPos(20., 1000., hz))

let utilitySpecs = [
  onSpec("Ut_On", "Utility on"),
  {id: "Ut_Gain", name: "Utility gain", kind: decibels(-48., 24., 0.)},
  {id: "Ut_Pan", name: "Utility pan", kind: bipolar(0.)},
  {id: "Ut_Width", name: "Utility width", kind: Float({min: 0., max: 2., init: 1., text: percent})},
  {id: "Ut_InvL", name: "Utility invert left", kind: Choice({names: onOff, init: 0})},
  {id: "Ut_InvR", name: "Utility invert right", kind: Choice({names: onOff, init: 0})},
  {id: "Ut_Swap", name: "Utility swap sides", kind: Choice({names: onOff, init: 0})},
  {
    id: "Ut_BassMono",
    name: "Utility bass mono",
    kind: Float({min: 0., max: 1., init: 0., text: bassMonoText, read: s => typedNumber(s)->Option.map(bassMonoValue)}),
  },
]

// The ambience: very small spaces, for a little stereo and tone (dsp/Ambience.cmajor): Porridge's
// room, and the Airwindows reverbs ClearCoat and VerbTiny. Size, time, predelay, high cut, width
// and mix work on every model; density and the high and low times on the room's.
let ambienceModels = ["room", "clear coat", "verb tiny"]

let ambienceSpecs = [
  onSpec("Am_On", "Ambience on"),
  {id: "Am_Model", name: "Ambience model", kind: Choice({names: ambienceModels, init: 0})},
  {id: "Am_Size", name: "Ambience size", kind: unit(0., 1., 0.2)},
  {id: "Am_Time", name: "Ambience time", kind: unit(0., 1., 0.)},
  {id: "Am_Density", name: "Ambience density", kind: unit(0., 1., 1.)},
  {id: "Am_Predelay", name: "Ambience predelay", kind: Float({min: 0., max: 250., init: 0., text: msText})},
  {id: "Am_HighCut", name: "Ambience high cut", kind: hzKnob(9460.)},
  {id: "Am_HighTime", name: "Ambience high time", kind: bipolar(0.)},
  {id: "Am_HighFreq", name: "Ambience high freq", kind: hzKnob(6320.)},
  {id: "Am_LowTime", name: "Ambience low time", kind: bipolar(0.)},
  {id: "Am_LowFreq", name: "Ambience low freq", kind: hzKnob(200.)},
  {id: "Am_Width", name: "Ambience width", kind: bipolar(0.)},
  {id: "Am_Mix", name: "Ambience mix", kind: unit(0., 1., 0.3)},
]

// The air: Airwindows Air4 (dsp/Airwindows.cmajor). Air turns the highs up or down against the
// rest, body the rest; dark freq and darken are Sinew, a slew limit that's tighter near full
// scale, and how much of it is mixed in. Half air and half body leave the sound as it was.
let airGain = (v: float) => {
  let g = v * 2.
  // (at 48 kHz: the top of the knob goes further at higher rates)
  g > 1. ? Math.pow(g, ~exp=3. + Math.sqrt(48000. / 44100.)) : g
}
let gainDbText = (g: float) => g <= 0. ? "-inf dB" : dbText(20. * Math.log10(g))

let airSpecs = [
  onSpec("Ai_On", "Air on"),
  {id: "Ai_Air", name: "Air amount", kind: Float({min: 0., max: 1., init: 0.5, text: v => gainDbText(airGain(v))})},
  {id: "Ai_Body", name: "Air body", kind: Float({min: 0., max: 1., init: 0.5, text: v => gainDbText(v * 2.)})},
  {id: "Ai_DarkFreq", name: "Air dark freq", kind: unit(0., 1., 0.52)},
  {id: "Ai_Darken", name: "Air darken", kind: unit(0., 1., 0.)},
]

let newKindSpecs = [flangerSpecs, phaserSpecs, compressorSpecs, spaceSpecs, convolveSpecs, bodeSpecs, filterFxSpecs, utilitySpecs]

let rackParams = specs => specs->Array.map(s => (s.id, s.name))

let newKinds = [
  {
    key: "flanger",
    name: "Flanger",
    about: "a flanger: a short swept delay",
    runsIn: Both,
    params: rackParams(flangerSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "phaser",
    name: "Phaser",
    about: "a phaser: swept notches",
    runsIn: Both,
    params: rackParams(phaserSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "compressor",
    name: "Compressor",
    about: "a compressor, one band or three (like OTT)",
    runsIn: Rack,
    params: rackParams(compressorSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "space",
    name: "Algo reverb",
    menuName: "algo reverb",
    about: "an algorithmic reverb: hall, plate, nitrous, basin, vintage",
    runsIn: Rack,
    params: rackParams(spaceSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "convolve",
    name: "Convolve",
    menuName: "convolution",
    about: "a convolver: rooms, cabinets and odd spaces from impulses, or a file of your own",
    runsIn: Rack,
    params: rackParams(convolveSpecs),
    copies: [2],
    firstInRack: true,
  },
  {
    key: "bode",
    name: "Bode",
    menuName: "freq shifter",
    about: "a frequency shifter (Bode), and a shifted delay",
    runsIn: Rack,
    params: rackParams(bodeSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "filter",
    name: "Filter",
    about: "a filter of any of the synth's types",
    runsIn: Both,
    params: rackParams(filterFxSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "utility",
    name: "Utility",
    about: "gain, pan, width, phase and bass mono",
    runsIn: Both,
    params: rackParams(utilitySpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  // (after the others: rack values and parameters added later go at the end)
  {
    key: "ambience",
    name: "Ambience",
    about: "a very small space: a little stereo and tone",
    runsIn: Rack,
    params: rackParams(ambienceSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
  {
    key: "air",
    name: "Air",
    about: "air: lifts or tames the very top (Airwindows Air4)",
    runsIn: Rack,
    params: rackParams(airSpecs),
    copies: [2, 3],
    retired: [4],
    firstInRack: true,
  },
]

// The distortion's knobs for its model types (dsp/Airwindows.cmajor), whose meaning each
// model sets (DistTypes), and the mix with the dry sound, which every type has. They came after
// the rack's copies, so their copies are in a group of their own.
let distModelSpecs = [
  {id: "Sat_Drive", name: "Dist drive", kind: unit(0., 1., 0.5)},
  {id: "Sat_Tone", name: "Dist tone", kind: unit(0., 1., 0.5)},
  {id: "Sat_Character", name: "Dist character", kind: unit(0., 1., 0.)},
  {id: "Sat_Mix", name: "Dist mix", kind: unit(0., 1., 1.)},
]
let distModelParams = [("Sat_Drive", "drive"), ("Sat_Tone", "tone"), ("Sat_Character", "character"), ("Sat_Mix", "mix")]
let isDistModelParam = id => distModelParams->Array.some(((first, _)) => first == id)

// Effects only the voice lane holds (dsp/VoiceFx.cmajor): they follow each note's key.
// The shifter moves every partial by a fraction of the note's frequency (and some Hz); the
// resonator rings at the model's ratios of the note.
let shifterRatioText = v => {
  let r = 2. * v * v * v
  (r > 0. ? "+" : "") ++ Float.toFixed(r, ~digits=Math.abs(r) < 0.1 ? 3 : 2) ++ " × note"
}
let shifterHzText = v => {
  let hz = 1000. * v * v * v
  (hz > 0. ? "+" : "") ++ Float.toFixed(hz, ~digits=Math.abs(hz) < 10. ? 2 : 1) ++ " Hz"
}
let resonatorModels = ["harmonic", "odd", "fifths", "bar", "bell", "membrane"]

let shifterSpecs = [
  onSpec("Sh_On", "Shifter on"),
  {id: "Sh_Ratio", name: "Shifter ratio", kind: Float({min: -1., max: 1., init: 0.5, text: shifterRatioText})},
  {id: "Sh_Hz", name: "Shifter offset", kind: Float({min: -1., max: 1., init: 0., text: shifterHzText})},
  {id: "Sh_Mode", name: "Shifter mode", kind: Choice({names: ["up", "down", "stereo (L up, R down)", "ring"], init: 0})},
  {id: "Sh_Mix", name: "Shifter mix", kind: unit(0., 1., 0.5)},
]

let resonatorSpecs = [
  onSpec("Rs_On", "Resonator on"),
  {id: "Rs_Model", name: "Resonator model", kind: Choice({names: resonatorModels, init: 0})},
  {id: "Rs_Pitch", name: "Resonator pitch", kind: Float({min: -24., max: 24., init: 0., text: semitones})},
  {id: "Rs_Decay", name: "Resonator decay", kind: expKnob(~lo=10., ~hi=10000., ~init=400., ~text=msText)},
  {id: "Rs_Bright", name: "Resonator brightness", kind: unit(0., 1., 0.5)},
  {id: "Rs_Mix", name: "Resonator mix", kind: unit(0., 1., 0.5)},
]

// The resonator's gain (its ringing's level, apart from the mix) came later: its first and copy
// are in a group of their own.
let resonatorGainSpecs = [{id: "Rs_Gain", name: "Resonator gain", kind: decibels(-24., 24., 0.)}]

// The octaver: an octave down, from a switch that flips the sound's sign on every other cycle of
// the note (found through a lowpass at the note, so that only its fundamental counts), and an
// octave up, from the sound rectified; each at its own level, with the dry sound's.
let octaverSpecs = [
  onSpec("Oc_On", "Octaver on"),
  {id: "Oc_Sub", name: "Octaver down", kind: unit(0., 1., 0.7)},
  {id: "Oc_Up", name: "Octaver up", kind: unit(0., 1., 0.)},
  {id: "Oc_Dry", name: "Octaver dry", kind: unit(0., 1., 1.)},
]

let voiceKinds = [
  {
    key: "shifter",
    name: "Shifter",
    menuName: "key shifter",
    about: "a frequency shifter that follows the key: each note's partials move by a part of its own pitch",
    runsIn: LaneOnly,
    params: rackParams(shifterSpecs),
    copies: [2],
    firstInRack: true,
  },
  {
    key: "resonator",
    name: "Resonator",
    about: "a resonator tuned to each note: strings, bars, bells and drums ringing at its pitch",
    runsIn: LaneOnly,
    params: [...rackParams(resonatorSpecs), ...rackParams(resonatorGainSpecs)],
    copies: [2],
    firstInRack: true,
  },
  {
    key: "octaver",
    name: "Octaver",
    about: "an octave down and an octave up, found from each note's own pitch",
    runsIn: LaneOnly,
    params: rackParams(octaverSpecs),
    copies: [2],
    firstInRack: true,
  },
]

// The FX filter's note tracking came later: its first and copies are in the voice lane's group.
let filterTrackSpecs = [
  {id: "Ff_Track", name: "FX filter note tracking", kind: unit(0., 1., 0.)},
]

// What came later still, for the voices (their firsts and copies are in the VoiceExtras group):
// the phaser's and flanger's LFOs follow the note's pitch (rate tracking) and start each note at a
// random point (random start); the flanger's delay follows the note's period, so that with
// feedback it rings at the note; the lo-fi sampler's rates land on whole multiples of the note.
let pitchTrackText = x => x == 0. ? "off" : percent(x)
let laterKindSpecs = [
  ("phaser", [
    {id: "Ph_RateTrack", name: "Phaser rate tracking", kind: Float({min: 0., max: 1., init: 0., text: pitchTrackText})},
    {id: "Ph_PhaseRand", name: "Phaser random start", kind: unit(0., 1., 0.)},
  ]),
  ("flanger", [
    {id: "Fl_RateTrack", name: "Flanger rate tracking", kind: Float({min: 0., max: 1., init: 0., text: pitchTrackText})},
    {id: "Fl_PhaseRand", name: "Flanger random start", kind: unit(0., 1., 0.)},
    {id: "Fl_Track", name: "Flanger delay tracking", kind: Float({min: 0., max: 1., init: 0., text: pitchTrackText})},
  ]),
  ("distortion", [
    {id: "Sat_Track", name: "Dist lo-fi note tracking", kind: Choice({names: ["off", "on"], init: 0})},
  ]),
]

let laterKindParams = key =>
  laterKindSpecs->Array.find(((k, _)) => k == key)->Option.mapOr([], ((_, specs)) => rackParams(specs))
let isLaterKindParam = id => laterKindSpecs->Array.some(((_, specs)) => specs->Array.some(s => s.id == id))

let rackKinds = [
  {
    key: "chorus",
    name: "Chorus",
    about: "Oatmeal's chorus: detuned copies of the sound",
    onLabel: "sine",
    runsIn: Rack,
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
    copies: [2, 3],
    retired: [4],
    firstInRack: false,
  },
  {
    key: "delay",
    name: "Delay",
    about: "Oatmeal's delay: echoes, left and right",
    runsIn: Rack,
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
    copies: [2, 3],
    retired: [4],
    firstInRack: false,
  },
  {
    key: "reverb",
    name: "Reverb",
    about: "Oatmeal's reverb",
    runsIn: Rack,
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
    copies: [2, 3],
    retired: [4],
    firstInRack: false,
  },
  {
    key: "eq",
    name: "EQ",
    menuName: "EQ",
    about: "Oatmeal's EQ: five bands",
    runsIn: Both,
    params:[("EQ_On", "on"), ...[1, 2, 3, 4, 5]->Array.flatMap(b => {
      let n = Int.toString(b)
      [
        (`EQ_${n}_Freq`, `band ${n} freq`),
        (`EQ_${n}_Amp`, `band ${n} amp`),
        (`EQ_${n}_Slope`, `band ${n} slope`),
        (`EQ_${n}_Type`, `band ${n} type`),
      ]
    })],
    copies: [2, 3],
    retired: [4],
    firstInRack: false,
  },
  {
    key: "distortion",
    name: "Distortion",
    about: "a distortion: Oatmeal's curves, a shape of your own, or the Airwindows models",
    onLabel: "soft clip",
    runsIn: Both,
    params: [
      ("Sat_Type", "type"),
      ("Sat_Oversample", "oversample"),
      ("Sat_Pregain", "pregain"),
      ("Sat_Limit", "limit"),
      ("Sat_Postgain", "postgain"),
      ...shaperParams,
      ...distModelParams,
      ...laterKindParams("distortion"),
    ],
    copies: [2, 3, 4],
    retired: [5],
    firstInRack: false,
  },
  // (the filter's note tracking came later: see filterTrackSpecs; and the phaser's and flanger's
  // tracking and random start later still: laterKindSpecs)
  ...newKinds->Array.map(k => {
    let k = k.key == "filter" ? {...k, params: [...k.params, ("Ff_Track", "note tracking")]} : k
    {...k, params: [...k.params, ...laterKindParams(k.key)]}
  }),
  ...voiceKinds,
]

// The id of copy n's parameter (D_Wet, 3: D3_Wet).
let copyId = (id, n) =>
  switch String.indexOf(id, "_") {
  | i if i > 0 => String.slice(id, ~start=0, ~end=i) ++ Int.toString(n) ++ String.slice(id, ~start=i)
  | _ => id
  }

let retiredOf = k => k.retired->Option.getOr([])
let isRetired = ((key, n)) => rackKinds->Array.some(k => k.key == key && retiredOf(k)->Array.includes(n))

// Every value a rack slot has had, by value: nothing, Oatmeal's four, then every copy (the
// retired ones too, which keep their values).
let rackHistory: array<option<(string, int)>> = [
  None,
  Some(("chorus", 1)),
  Some(("delay", 1)),
  Some(("reverb", 1)),
  Some(("eq", 1)),
  ...rackKinds->Array.flatMap(k =>
    [...(k.firstInRack ? [1] : []), ...k.copies, ...retiredOf(k)]->Array.map(n => Some((k.key, n)))
  ),
]

// What a rack slot can hold, by value (None: nothing, or a retired copy, which runs nothing).
let rackEntries = rackHistory->Array.map(entry => entry->Option.filter(e => !isRetired(e)))

// The retired copy a rack value was, if it was one.
let retiredEntry = v => rackHistory[v]->Option.flatMap(e => e)->Option.filter(isRetired)

let rackNames = rackHistory->Array.map(entry =>
  switch entry {
  | None => "empty"
  | Some((key, n) as e) =>
    let name = rackKinds->Array.find(k => k.key == key)->Option.mapOr(key, k => k.name)
    let name = n == 1 ? name : `${name} ${Int.toString(n)}`
    isRetired(e) ? name ++ " (retired)" : name
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

// (only: the parameters to copy; the retired copies' are in their places, for `endpoints`, and
// left out of `all`)
let copySpecsOf = (kinds, ~only=_ => true) => kinds->Array.flatMap(k =>
  [...k.copies, ...retiredOf(k)]->Array.flatMap(n =>
    k.params
    ->Array.filter(((id, _)) => only(id))
    ->Array.map(((id, label)) => {
      id: copyId(id, n),
      name: `${k.name} ${Int.toString(n)} ${label}`,
      kind: Like(id),
    })
  )
)

// Oatmeal's effects' copies, and Porridge's own effects' copies (which come after them; the
// ambience's, the distortion's model knobs' and the air's are in groups of their own)
let laterKinds = ["ambience", "air", "shifter", "resonator", "octaver"]
let laterParams = ["Ff_Track"]
let copySpecs = copySpecsOf(
  rackKinds->Array.filter(k => !k.firstInRack),
  ~only=id => !isDistModelParam(id) && !isLaterKindParam(id),
)
let newCopySpecs = copySpecsOf(
  rackKinds->Array.filter(k => k.firstInRack && !(laterKinds->Array.includes(k.key))),
  ~only=id => !(laterParams->Array.includes(id)) && !isLaterKindParam(id),
)
let ambienceCopySpecs = copySpecsOf(rackKinds->Array.filter(k => k.key == "ambience"))
let distModelCopySpecs = copySpecsOf(rackKinds->Array.filter(k => k.key == "distortion"), ~only=isDistModelParam)
let airCopySpecs = copySpecsOf(rackKinds->Array.filter(k => k.key == "air"))

// Each oscillator's own envelope: while it's on, the oscillator's level follows it (under the
// amp envelope, which still ends the note). Its stages are like the amp envelope's, with curves
// of their own; it runs once per 64-sample block, as the mod envelopes do, and the oscillator
// ramps its level between blocks.
let oscEnv = n => {
  prefix: `OE${Int.toString(n)}_`,
  curveName: `Osc${Int.toString(n)}`,
  name: `Osc ${Int.toString(n)}`,
}

let oscEnvSpecs = [1, 2]->Array.flatMap(n => {
  let {prefix, curveName: env, name} = oscEnv(n)
  let id = k => prefix ++ k
  let name = name ++ " env"
  [
    {id: id("On"), name, kind: Choice({names: onOff, init: 0})},
    {id: id("Attack"), name: name ++ " attack", kind: Like("Attack")},
    {id: id("Hold"), name: name ++ " hold", kind: Like("Hold")},
    // (decay 2's range and text: decay 1's text reads the amp envelope's breakpoint)
    {id: id("Decay1"), name: name ++ " decay 1", kind: Like("Decay2")},
    {id: id("Breakpoint"), name: name ++ " breakpoint", kind: Like("Breakpoint")},
    {id: id("Decay2"), name: name ++ " decay 2", kind: Like("Decay2")},
    // (at the top, so that switching it on leaves the level as it was: a gate)
    {id: id("Sustain"), name: name ++ " sustain", kind: LikeWithDefault("Sustain", 1.)},
    {id: id("Release"), name: name ++ " release", kind: Like("Release")},
    ...stageNames->Array.map(((stage, stageName)) => {
      id: curveId(env, stage),
      name: `${name} ${stageName} curve`,
      kind: curveKind,
    }),
    {id: decay1CurveId(env), name: `${name} decay 1 curve`, kind: curveKind},
  ]
})

// The key EQ: eight bands at the end of each voice, an octave apart on the note's harmonics 1,
// 2, 4 ... 128, so that its curve moves with the note: a low shelf half an octave under the note,
// then peaks an octave wide (a band past 18 kHz fades out over the next octave).
let keyEqBands = 8
let keyEqGainId = k => `KEQ_${Int.toString(k)}_Gain`
let keyEqHarmonic = k => Math.pow(2., ~exp=Int.toFloat(k - 1))

let keyEqSpecs = [
  {id: "KEQ_On", name: "Key EQ", kind: Choice({names: onOff, init: 0})},
  ...Array.fromInitializer(~length=keyEqBands, i => {
    id: keyEqGainId(i + 1),
    name: i == 0 ? "Key EQ low shelf gain" : `Key EQ ${Float.toString(keyEqHarmonic(i + 1))}× gain`,
    kind: decibels(-24., 24., 0.),
  }),
]

// Each oscillator's noise: its pitch moved every sample by lowpassed noise (how far, and how
// bright the noise is), which roughens the waveform without any hiss of its own.
let oscNoiseSpecs = [1, 2]->Array.flatMap(n => {
  let osc = Int.toString(n)
  [
    {id: `O${osc}_Noise`, name: `Osc ${osc} noise`, kind: Float({min: 0., max: 1., init: 0., text: percent})},
    {id: `O${osc}_NoiseColour`, name: `Osc ${osc} noise colour`, kind: Float({min: 0., max: 1., init: 0.7, text: percent})},
  ]
})

// In the PM 2 > 1, ring and AM osc mixes, osc 2 heard as well as modulating (at this much of
// its level, which is also the depth): an oscillator that modulates another and sounds beside
// it, as Synplant's B does.
let pairMixSpecs = [{id: "O2_PairMix", name: "Osc 2 heard", kind: Float({min: 0., max: 1., init: 0., text: percent})}]

// LFO 3: a plain LFO that only the modulation matrix reaches. Per-voice (each voice its own,
// from the note's start) or shared by every voice (restarted by each note, or running free),
// at a rate in Hz or a length in beats, from a phase of its own, faded in after a delay. The
// wander source's rate goes with it. Its shapes are named as LFO 1 and 2's are, and its menu
// has them in their order (ValueList.Lfo3Shape); the values keep their own.
let lfo3Shapes = ["Sine", "Triangle", "Saw", "Saw down", "Square", "Stepping random", "Smooth random"]
let lfo3Syncs = ["free", "4 bars", "2 bars", "1 bar", "1/2", "1/2 T", "1/4", "1/4 T", "1/8", "1/8 T", "1/16", "1/16 T", "1/32"]
let lfoModes = ["per-voice", "shared, reset on note", "shared, free"]

let lfo3Specs = [
  {id: "LFO_3_Shape", name: "LFO 3 shape", kind: Choice({names: lfo3Shapes, init: 0, list: Lfo3Shape})},
  {id: "LFO_3_Mode", name: "LFO 3 mode", kind: Choice({names: lfoModes, init: 0})},
  {id: "LFO_3_Rate", name: "LFO 3 rate", kind: expKnob(~lo=0.02, ~hi=50., ~init=2., ~text=fixedUnit(2, "Hz"))},
  {id: "LFO_3_Sync", name: "LFO 3 sync", kind: Choice({names: lfo3Syncs, init: 0})},
  {id: "LFO_3_Phase", name: "LFO 3 phase", kind: Float({min: 0., max: 1., init: 0., text: x => degreesText(x * 360.)})},
  {id: "LFO_3_PhaseRand", name: "LFO 3 random phase", kind: Float({min: 0., max: 1., init: 0., text: percent})},
  {id: "LFO_3_Delay", name: "LFO 3 delay", kind: Float({min: 0., max: 5000., init: 0., text: fixedUnit(0, "ms")})},
  {id: "LFO_3_Fade", name: "LFO 3 fade-in", kind: Float({min: 0., max: 5000., init: 0., text: fixedUnit(0, "ms")})},
  {id: "Wander_Rate", name: "Wander rate", kind: expKnob(~lo=0.02, ~hi=10., ~init=0.5, ~text=fixedUnit(2, "Hz"))},
]

type feature =
  | Macros
  | Modulations
  | Mpe
  | OatMode
  | Drift
  | FxOrder
  | PmFeedback
  | FilterMorph
  | Curves
  | LfoExtras
  | UnisonExtras
  | EffectsRack
  | EqSwitch
  | CustomShape
  | RackCopies
  | FilterDrive
  | RackEffects
  | Decay1Curves
  | OscEnvs
  | Ambience
  | DistModels
  | AirEffect
  | KeyEq
  | OscNoise
  | PairMix
  | MoreModulations
  | Lfo3
  | VoiceLane
  | ResonatorGain
  | VoiceExtras

// The voice lane (dsp/VoiceFx.cmajor): up to laneSlots effects in every voice, which each note
// runs its own copy of, holding the same values as the rack's slots (only the kinds that work in
// a voice: FxRack.laneKinds); how many of them come before the filter, and before the amp
// envelope (the rest come after it, and react to how each note swells and fades).
let laneSlots = 4
let laneId = k => `VL_${Int.toString(k)}`
let lanePositions = ["0", "1", "2", "3", "4"]

let laneSpecs = [
  ...Array.fromInitializer(~length=laneSlots, i => {
    id: laneId(i + 1),
    name: `Voice FX slot ${Int.toString(i + 1)}`,
    kind: Choice({names: rackNames, init: 0}),
  }),
  {id: "VL_FilterAt", name: "Voice FX before the filter", kind: Choice({names: lanePositions, init: 0})},
  {id: "VL_AmpAt", name: "Voice FX before the amp", kind: Choice({names: lanePositions, init: 0})},
]

let voiceLaneSpecs = Array.concat(
  laneSpecs,
  Array.concat(
    Array.concat(filterTrackSpecs, copySpecsOf(rackKinds->Array.filter(k => k.key == "filter"), ~only=id => id == "Ff_Track")),
    Array.concat(
      Array.concat(shifterSpecs, resonatorSpecs),
      copySpecsOf(rackKinds->Array.filter(k => k.key == "shifter" || k.key == "resonator"), ~only=id => id != "Rs_Gain"),
    ),
  ),
)

// Each connection's steps: its source snapped to that many levels across its range (after the
// curve), 0 or 1 for none. 25 steps of a bipolar source on pitch ±24 st at half the amount are
// semitones.
let stepsText = x => x < 1.5 ? "off" : `${Int.toString(Float.toInt(Math.round(x)))} steps`
let stepSpecs = Array.fromInitializer(~length=ModMatrix.slots, i => {
  id: ModMatrix.stepsId(i + 1),
  name: `Mod ${Int.toString(i + 1)} steps`,
  kind: Float({min: 0., max: 49., init: 0., text: stepsText}),
})

// The voices' extras: the phaser's, flanger's and lo-fi sampler's tracking and random starts
// (firsts, then copies), the octaver and its copy, and the connections' steps.
let voiceExtraSpecs = [
  ...laterKindSpecs->Array.flatMap(((_, specs)) => specs),
  ...copySpecsOf(rackKinds->Array.filter(k => laterKindSpecs->Array.some(((key, _)) => key == k.key)), ~only=isLaterKindParam),
  ...octaverSpecs,
  ...copySpecsOf(rackKinds->Array.filter(k => k.key == "octaver")),
  ...stepSpecs,
]

// (with the retired copies' parameters)
let groupsAsAdded = [
  (Macros, macroSpecs),
  (Modulations, slotSpecs),
  (Mpe, mpeSpecs),
  (OatMode, oatSpecs),
  (Drift, driftSpecs),
  (FxOrder, fxOrderSpecs),
  (PmFeedback, pmSpecs),
  (FilterMorph, filterSpecs),
  (Curves, curveSpecs),
  (LfoExtras, lfoSpecs),
  (UnisonExtras, unisonSpecs),
  (EffectsRack, rackSpecs),
  (EqSwitch, eqOnSpecs),
  (CustomShape, shaperSpecs),
  (RackCopies, copySpecs),
  (FilterDrive, filterDriveSpecs),
  // Porridge's own effects, then their copies
  (RackEffects, Array.concat(newKindSpecs->Array.flat, newCopySpecs)),
  (Decay1Curves, decay1CurveSpecs),
  (OscEnvs, oscEnvSpecs),
  (Ambience, Array.concat(ambienceSpecs, ambienceCopySpecs)),
  (DistModels, Array.concat(distModelSpecs, distModelCopySpecs)),
  (AirEffect, Array.concat(airSpecs, airCopySpecs)),
  (KeyEq, keyEqSpecs),
  (OscNoise, oscNoiseSpecs),
  (PairMix, pairMixSpecs),
  (MoreModulations, Array.concat(moreSlotSpecs, Array.concat(slotOptionSpecs, followSpecs))),
  (Lfo3, lfo3Specs),
  (VoiceLane, voiceLaneSpecs),
  (
    ResonatorGain,
    Array.concat(resonatorGainSpecs, copySpecsOf(rackKinds->Array.filter(k => k.key == "resonator"), ~only=id => id == "Rs_Gain")),
  ),
  (VoiceExtras, voiceExtraSpecs),
]

// The retired copies' parameters: no longer the patch's, presets' or hosts'.
let retiredIds = Set.fromArray(
  rackKinds->Array.flatMap(k => retiredOf(k)->Array.flatMap(n => k.params->Array.map(((id, _)) => copyId(id, n)))),
)
let isRetiredId = id => retiredIds->Set.has(id)

let groups = groupsAsAdded->Array.map(((f, specs)) => (f, specs->Array.filter(s => !isRetiredId(s.id))))

let all = groups->Array.flatMap(((_, specs)) => specs)

// Every parameter endpoint there has been, in order, and whether it's retired: the patch keeps a
// retired one's place (as an endpoint that isn't a parameter), because CLAP hosts know
// parameters by their endpoint's number, which counts the endpoints before it.
let endpoints = groupsAsAdded->Array.flatMap(((_, specs)) => specs->Array.map(s => (s.id, isRetiredId(s.id))))

let slotOf = i => firstSlot + i
