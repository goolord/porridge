// What the sound matcher searches: 32 genes, each from 0 to 1, that set the parts of a patch
// that shape a single note (the oscillators, the filter and its envelope, the amp and pitch
// envelopes, vibrato and filter wobble, drive, chorus and reverb). A choice gene picks one of
// its options by which equal part of 0..1 it falls in. `decode` turns genes into parameter
// values, which go on top of the patch the match starts from (Init, or the candidate a
// re-match keeps parts of).
//
// The genes are in groups that the drawer can lock (MatchDrawer.res), and each search keeps
// some of them still (MatchSearch.islands).

@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

type group = [#osc | #filter | #env | #mod | #fx]

let groups: array<group> = [#osc, #filter, #env, #mod, #fx]

let groupName = (g: group) =>
  switch g {
  | #osc => "Oscillators"
  | #filter => "Filter"
  | #env => "Envelopes"
  | #mod => "Modulation"
  | #fx => "Effects"
  }

// options: 0 for a continuous gene, else the number of choices
type gene = {key: string, group: group, options: int}

let genes: array<gene> = [
  {key: "o1Wave", group: #osc, options: 4},
  {key: "o1Level", group: #osc, options: 0},
  {key: "width", group: #osc, options: 0},
  {key: "o2Wave", group: #osc, options: 4},
  {key: "o2Level", group: #osc, options: 0},
  {key: "o2Interval", group: #osc, options: 7},
  {key: "o2Detune", group: #osc, options: 0},
  {key: "oscMix", group: #osc, options: 4},
  {key: "noise", group: #osc, options: 0},
  {key: "noiseColour", group: #osc, options: 0},
  {key: "unison", group: #osc, options: 4},
  {key: "unisonDetune", group: #osc, options: 0},
  {key: "filterType", group: #filter, options: 6},
  {key: "cutoff", group: #filter, options: 0},
  {key: "resonance", group: #filter, options: 0},
  {key: "filterEnv", group: #filter, options: 0},
  {key: "filterAttack", group: #filter, options: 0},
  {key: "filterDecay", group: #filter, options: 0},
  {key: "filterSustain", group: #filter, options: 0},
  {key: "attack", group: #env, options: 0},
  {key: "decay", group: #env, options: 0},
  {key: "sustain", group: #env, options: 0},
  {key: "pitchEnv", group: #env, options: 0},
  {key: "pitchTime", group: #env, options: 0},
  {key: "vibrato", group: #mod, options: 0},
  {key: "vibratoRate", group: #mod, options: 0},
  {key: "wobble", group: #mod, options: 0},
  {key: "wobbleRate", group: #mod, options: 0},
  {key: "drive", group: #fx, options: 0},
  {key: "chorus", group: #fx, options: 0},
  {key: "reverb", group: #fx, options: 0},
  {key: "reverbTime", group: #fx, options: 0},
]

let count = Array.length(genes)

// the genes a search's first stage moves: the first oscillator, the filter and the envelopes
// (MatchSearch.phase)
let core = [
  "o1Wave",
  "width",
  "filterType",
  "cutoff",
  "resonance",
  "filterEnv",
  "filterAttack",
  "filterDecay",
  "filterSustain",
  "attack",
  "decay",
  "sustain",
]

let indexOf = {
  let indices = genes->Array.mapWithIndex((g, i) => (g.key, i))->Map.fromArray
  key =>
    switch indices->Map.get(key) {
    | Some(i) => i
    | None => JsError.panic("no gene " ++ key)
    }
}

let gene = i => genes->Array.getUnsafe(i)

// The options of the choice genes.
let waves = [0., 6., 7., 8.] // sine, saw HQ, pulse HQ, triangle HQ
let waveNames = ["sine", "saw", "pulse", "triangle"]
let intervals = [0., 12., -12., 7., 19., 24., 5.]
let mixModes = [0., 1., 2., 5.] // normal, hard sync, FM 1 > 2, ring 1 × 2
let mixNames = ["", "sync", "FM", "ring"]
let unisonVoices = [1., 2., 3., 4.]
let filterTypes =
  ["2P lowpass", "4P lowpass", "2P highpass", "2P wide bandpass", "ladder", "formant"]->Array.map(
    FilterTypes.index,
  )

// a choice gene's option, and the gene value in the middle of an option
let choiceOf = (x, options) => Math.Int.max(0, Math.Int.min(options - 1, Float.toInt(x * Int.toFloat(options))))
let valueOfChoice = (i, options) => (Int.toFloat(i) + 0.5) / Int.toFloat(options)

let get = (x: Float64Array.t, key) => x->get64(indexOf(key))
let choice = (x, key) => choiceOf(get(x, key), gene(indexOf(key)).options)

let clamp01 = v => Math.max(0., Math.min(1., v))
let ampOfDb = db => Math.pow(10., ~exp=db / 20.)
let dbOfAmp = a => 20. * Math.log10(Math.max(a, 1e-9))
// 0..1 to lo..hi on a log scale
let logScale = (v: float, lo: float, hi: float) => lo * Math.pow(hi / lo, ~exp=v)
let ofLogScale = (x: float, lo: float, hi: float) => clamp01(Math.log(x / lo) / Math.log(hi / lo))

let def = id => Lazy.get(Preset.defsById)->Map.get(id)->Option.getOrThrow

// Amp envelope times, in ms.
let attackMs = v => logScale(v, 0.2, 3000.)
let decayMs = v => logScale(v, 10., 10000.)
let filterAttackMs = v => logScale(v, 0.2, 2000.)
let pitchMs = v => logScale(v, 10., 3000.)
// an LFO rate in Hz to a speed in the "10 ms" unit
let lfoSpeed = hz => 100. / hz
let vibratoHz = v => logScale(v, 1.5, 12.)
let wobbleHz = v => logScale(v, 0.3, 12.)
// the pitch sweep's start, from 36 semitones down to 36 up, none in the middle fifth
let pitchSemitones = v => {
  let u = 2. * v - 1.
  let past = Math.max(0., Math.abs(u) - 0.2) / 0.8
  (u < 0. ? -36. : 36.) * past * past
}
let pitchGene = st => {
  let past = Math.sqrt(Math.min(36., Math.abs(st)) / 36.)
  let u = 0.2 + 0.8 * past
  (1. + (st < 0. ? -.u : u)) / 2.
}
// below these a gene switches its part off
let o2Off = 0.12
let noiseOff = 0.12
let effectOff = 0.15
let modOff = 0.2

// Every parameter the genes set, with its value: the same ids whatever the genes, so that the
// result replaces all of them. `note` is the key the match plays, which the cutoff is set for;
// `base` reads the patch the values go on (for its effects rack).
let decode = (x: Float64Array.t, ~note, ~base: string => float): array<(string, float)> => {
  let v = get(x, ...)
  let out = []
  let set = (id, value) => out->Array.push((id, value))

  // oscillators
  let mode = choice(x, "oscMix")
  set("O1_Waveform", waves->Array.getUnsafe(choice(x, "o1Wave")))
  set("O2_Waveform", waves->Array.getUnsafe(choice(x, "o2Wave")))
  // osc 1 is the modulator in FM mode, where its level is the depth
  set("O1_Amp", ampOfDb(-24. + 36. * v("o1Level")))
  let o2 = v("o2Level")
  set("O2_Amp", o2 < o2Off ? 0. : ampOfDb(-30. + 36. * (o2 - o2Off) / (1. - o2Off)))
  let width = 0.5 - 0.45 * v("width")
  set("O1_PWM_W", width)
  set("O2_PWM_W", width)
  set("O1_PWM_D", 0.)
  set("O2_PWM_D", 0.)
  set("Transpose", intervals->Array.getUnsafe(choice(x, "o2Interval")) / 12.)
  set("Detune", 6. * v("o2Detune") * v("o2Detune"))
  set("OscMix", mixModes->Array.getUnsafe(mode))
  let noise = v("noise")
  set("N_Amp", noise < noiseOff ? 0. : ampOfDb(-36. + 36. * (noise - noiseOff) / (1. - noiseOff)))
  set("N_Resonance", 0.9 * v("noiseColour") * v("noiseColour"))
  set("N_Transpose", 0.)
  let voices = unisonVoices->Array.getUnsafe(choice(x, "unison"))
  set("U_Voices", voices)
  set("U_Detune", voices > 1. ? 3. + 45. * v("unisonDetune") * v("unisonDetune") : 1.)
  set("U_Spread", voices > 1. ? 0.6 : 0.25)

  // the filter: the cutoff is the knob's at the matched key, half key-tracked from there
  set("Filter", Int.toFloat(filterTypes->Array.getUnsafe(choice(x, "filterType"))))
  set("Filter2", 0.)
  set("F_Double", 0.)
  set("Cutoff", v("cutoff"))
  set("Resonance", 0.85 * v("resonance"))
  set("F_Track", 0.5)
  set("Tune_CutReference", Math.max(-24., Math.min(24., -0.5 * (Int.toFloat(note) - 69.))))
  let fe = v("filterEnv")
  set("F_EnvMod", -0.15 + 0.85 * fe * fe)
  set("F_Attack", filterAttackMs(v("filterAttack")))
  set("F_Hold", 0.)
  set("F_Breakpoint", 1.)
  set("F_Decay2", decayMs(v("filterDecay")))
  set("F_Sustain", v("filterSustain"))

  // the amp envelope: the release isn't heard in the match, so it follows the decay: a sound
  // that dies away rings on when the key is let go, a held one stops soon after
  let decay = decayMs(v("decay"))
  let sustain = def("Sustain").fromNorm(v("sustain"))
  let release = sustain < 0.05 ? decay : Math.min(1500., 60. + 0.3 * decay)
  set("Attack", attackMs(v("attack")))
  set("Hold", 0.)
  set("Breakpoint", 1.)
  set("Decay2", decay)
  set("Sustain", sustain)
  set("Release", release)
  set("F_Release", release)

  // the pitch envelope: from its start to the note
  let st = pitchSemitones(v("pitchEnv"))
  let pitchOn = Math.abs(st) >= 0.25
  set("PEnv_On", pitchOn ? 1. : 0.)
  set("PEnv_Start", pitchOn ? st : 0.)
  set("PEnv_Attack", 0.2)
  set("PEnv_Peak", pitchOn ? st : 0.)
  set("PEnv_Decay", pitchMs(v("pitchTime")))
  set("PEnv_Sustain", 0.)
  set("PEnv_Release", 0.)

  // vibrato on LFO 1, filter wobble on LFO 2, both sines restarting with each note
  let vib = v("vibrato")
  set("LFO_1_Unit", 1.)
  set("LFO_1_Shape", 0.)
  set("LFO_1_Sync", 0.)
  set("LFO_1_Speed", lfoSpeed(vibratoHz(v("vibratoRate"))))
  set("LFO_1_Pitch", vib < modOff ? 0. : def("LFO_1_Pitch").fromNorm(0.5 * (vib - modOff) / (1. - modOff)))
  set("LFO_1_Cutoff_1", 0.)
  let wob = v("wobble")
  set("LFO_2_Unit", 1.)
  set("LFO_2_Shape", 0.)
  set("LFO_2_Sync", 0.)
  set("LFO_2_Speed", lfoSpeed(wobbleHz(v("wobbleRate"))))
  set("LFO_2_Cutoff_1", wob < modOff ? 0. : 0.5 * Math.pow((wob - modOff) / (1. - modOff), ~exp=2.))
  set("LFO_2_Pitch", 0.)

  // drive: a soft clip on each voice after the filter, its pregain made up for after
  let drive = v("drive")
  let driveOn = drive >= effectOff
  let pregain = driveOn ? 30. * (drive - effectOff) / (1. - effectOff) : 0.
  set("Sat_Type", driveOn ? 2. : 0.)
  set("Sat_Mode", 1.)
  set("Sat_Pregain", pregain)
  set("Sat_Postgain", -0.5 * pregain)

  // chorus and reverb, which go in the rack (after what the base has there)
  let chorus = v("chorus")
  let chorusOn = chorus >= effectOff
  set("C_Mode", chorusOn ? 1. : 0.)
  set("C_Stereo", 1.)
  set("C_Mix", chorusOn ? 0.2 + 0.6 * (chorus - effectOff) / (1. - effectOff) : 0.5)
  let reverb = v("reverb")
  let reverbOn = reverb >= effectOff
  set("R_On", reverbOn ? 1. : 0.)
  set("R_Dry", 1.)
  set("R_Wet", reverbOn ? ampOfDb(-24. + 24. * (reverb - effectOff) / (1. - effectOff)) : 0.2)
  set("R_Length", logScale(v("reverbTime"), 0.3, 6.))
  set("R_Size", 20. + 100. * v("reverbTime"))
  let chorusFx: FxRack.effect = {kind: #chorus, copy: 1}
  let reverbFx: FxRack.effect = {kind: #reverb, copy: 1}
  let kept = FxRack.read(base)->Array.filter(e => e != chorusFx && e != reverbFx)
  let rack = Array.concat(kept, [chorusOn ? Some(chorusFx) : None, reverbOn ? Some(reverbFx) : None]->Array.filterMap(e => e))
  FxRack.values(rack->Array.slice(~start=0, ~end=PorridgeParams.rackSlots))->Array.forEach(((id, x)) => set(id, x))
  out
}

// Where the search starts for a target: its envelope, brightness and pitch movement, a saw
// through a lowpass, and nothing else.
let seed = (t: SoundTarget.t) => {
  let x = Float64Array.fromLength(count)
  let set = (key, value) => x->set64(indexOf(key), clamp01(value))
  let setChoice = (key, i) => set(key, valueOfChoice(i, gene(indexOf(key)).options))
  setChoice("o1Wave", 1)
  set("o1Level", 24. / 36.)
  set("width", 0.)
  setChoice("o2Wave", 1)
  set("o2Level", 0.)
  setChoice("o2Interval", 0)
  set("o2Detune", 0.3)
  setChoice("oscMix", 0)
  set("noise", 0.)
  set("noiseColour", 0.)
  setChoice("unison", 0)
  set("unisonDetune", 0.4)
  setChoice("filterType", 1)
  let hz = Math.max(200., Math.min(10000., 2. * t.brightness))
  set("cutoff", FilterTypes.cutoffOfHz(~filterType=filterTypes->Array.getUnsafe(1), hz))
  set("resonance", 0.1)
  let percussive = t.sustain < 0.1
  set("filterEnv", percussive ? 0.6 : Math.sqrt(0.15 / 0.85))
  set("filterAttack", 0.)
  set("filterDecay", ofLogScale(Math.max(10., 1000. * t.decay * 0.7), 10., 10000.))
  set("filterSustain", percussive ? 0.2 : 0.8)
  set("attack", ofLogScale(Math.max(0.2, 1000. * t.attack * 0.6), 0.2, 3000.))
  set("decay", ofLogScale(Math.max(10., 1000. * t.decay), 10., 10000.))
  set("sustain", def("Sustain").toNorm(t.sustain))
  set("pitchEnv", Math.abs(t.pitchDrop) < 0.5 ? 0.5 : pitchGene(t.pitchDrop))
  set("pitchTime", ofLogScale(60., 10., 3000.))
  set("vibrato", 0.)
  set("vibratoRate", ofLogScale(5., 1.5, 12.))
  set("wobble", 0.)
  set("wobbleRate", ofLogScale(2., 0.3, 12.))
  set("drive", 0.)
  set("chorus", 0.)
  set("reverb", 0.)
  set("reverbTime", 0.4)
  x
}

// How many of the optional parts the genes switch on (a second oscillator, noise, unison, a
// mix mode, a pitch sweep, vibrato, wobble, drive, chorus, reverb). The search charges a little
// for each, so that a part stays only if it helps the match.
let parts = (x: Float64Array.t) => {
  let v = get(x, ...)
  let mode = choice(x, "oscMix")
  [
    v("o2Level") >= o2Off || mode == 2,
    mode != 0,
    v("noise") >= noiseOff,
    choice(x, "unison") > 0,
    Math.abs(pitchSemitones(v("pitchEnv"))) >= 0.25,
    v("vibrato") >= modOff,
    v("wobble") >= modOff,
    v("drive") >= effectOff,
    v("chorus") >= effectOff,
    v("reverb") >= effectOff,
  ]->Array.reduce(0, (n, on) => on ? n + 1 : n)
}

// What a patch is made of, as its card names it: the first wave, the filter type, the mix mode,
// the second oscillator's wave and interval if it sounds, and which optional parts are on.
// Two cards with the same structure read as the same patch whatever their knobs.
let structure = (x: Float64Array.t) => {
  let v = get(x, ...)
  let mode = choice(x, "oscMix")
  let o2 = v("o2Level") >= o2Off || mode == 2
  [
    choice(x, "o1Wave"),
    choice(x, "filterType"),
    mode,
    o2 ? 1 + choice(x, "o2Wave") * 8 + choice(x, "o2Interval") : 0,
    choice(x, "unison"),
    v("noise") >= noiseOff ? 1 : 0,
    Math.abs(pitchSemitones(v("pitchEnv"))) >= 0.25 ? 1 : 0,
    v("vibrato") >= modOff ? 1 : 0,
    v("wobble") >= modOff ? 1 : 0,
    v("drive") >= effectOff ? 1 : 0,
    v("chorus") >= effectOff ? 1 : 0,
    v("reverb") >= effectOff ? 1 : 0,
  ]
}

// A short description of a patch, for its card: "saw + pulse +12 · 4P LP · pluck · reverb".
let describe = (x: Float64Array.t) => {
  let v = get(x, ...)
  let wave = key => waveNames->Array.getUnsafe(choice(x, key))
  let mode = choice(x, "oscMix")
  let o2 = v("o2Level") >= o2Off || mode == 2
  let interval = intervals->Array.getUnsafe(choice(x, "o2Interval"))
  let intervalText = interval == 0. ? "" : (interval > 0. ? " +" : " ") ++ Float.toString(interval)
  let oscText =
    (o2 ? (mode == 2 ? wave("o1Wave") ++ " FM " ++ wave("o2Wave") : `${wave("o1Wave")} + ${wave("o2Wave")}${intervalText}`) : wave("o1Wave")) ++
    (mode == 1 || mode == 3 ? " " ++ mixNames->Array.getUnsafe(mode) : "") ++
    (v("noise") >= noiseOff ? " + noise" : "") ++
    switch unisonVoices->Array.getUnsafe(choice(x, "unison")) {
    | 1. => ""
    | n => ` ×${Float.toString(n)}`
    }
  let filterType = filterTypes->Array.getUnsafe(choice(x, "filterType"))
  let filterText = Array.concat(FilterTypes.oatmealShort, FilterTypes.porridgeShort)->Array.getUnsafe(filterType)
  let sustain = def("Sustain").fromNorm(v("sustain"))
  let shape = if attackMs(v("attack")) > 150. {
    "slow attack"
  } else if sustain < 0.05 {
    decayMs(v("decay")) < 400. ? "short hit" : "pluck"
  } else if sustain < 0.5 {
    "decaying"
  } else {
    "held"
  }
  let extras = [
    Math.abs(pitchSemitones(v("pitchEnv"))) >= 0.25 ? Some("pitch sweep") : None,
    v("vibrato") >= modOff ? Some("vibrato") : None,
    v("wobble") >= modOff ? Some("wobble") : None,
    v("drive") >= effectOff ? Some("drive") : None,
    v("chorus") >= effectOff ? Some("chorus") : None,
    v("reverb") >= effectOff ? Some("reverb") : None,
  ]->Array.filterMap(e => e)
  [oscText, filterText, shape, ...extras]->Array.join(" · ")
}
