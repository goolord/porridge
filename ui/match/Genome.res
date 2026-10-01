// What the sound matcher searches: 40 genes, each from 0 to 1, that set the parts of a patch
// that shape a single note (the oscillators and how they combine, the filter and its envelope,
// the amp and pitch envelopes, vibrato and filter wobble, drive, chorus and reverb). A choice
// gene picks one of its options by which equal part of 0..1 it falls in. `decode` turns genes
// into parameter values, which go on top of the patch the match starts from (Init, or the
// candidate a re-match keeps parts of).
//
// Two genes only change how a candidate is rendered, not the patch: the octave and the tuning
// it is played at against the sample's pitch, so that a pitch found an octave off or a little
// out (vibrato, chorus, a sweep) doesn't hold the match back.
//
// The first oscillator's "fitted" wave is the user waveform, which the match sets to the
// sample's own harmonics (SoundTarget.fitWave) when it has a pitch.
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
  {key: "o1Wave", group: #osc, options: 5},
  {key: "o1Level", group: #osc, options: 0},
  {key: "width", group: #osc, options: 0},
  {key: "o2Wave", group: #osc, options: 4},
  {key: "o2Level", group: #osc, options: 0},
  {key: "o2Interval", group: #osc, options: 7},
  {key: "o2Fine", group: #osc, options: 0},
  {key: "o2Detune", group: #osc, options: 0},
  {key: "oscMix", group: #osc, options: 7},
  {key: "feedback", group: #osc, options: 0},
  {key: "noise", group: #osc, options: 0},
  {key: "noiseColour", group: #osc, options: 0},
  {key: "unison", group: #osc, options: 4},
  {key: "unisonDetune", group: #osc, options: 0},
  {key: "octave", group: #osc, options: 3},
  {key: "tune", group: #osc, options: 0},
  {key: "filterType", group: #filter, options: 10},
  {key: "cutoff", group: #filter, options: 0},
  {key: "resonance", group: #filter, options: 0},
  {key: "filterEnv", group: #filter, options: 0},
  {key: "filterAttack", group: #filter, options: 0},
  {key: "filterDecay", group: #filter, options: 0},
  {key: "filterSustain", group: #filter, options: 0},
  {key: "filterDrop", group: #filter, options: 0},
  {key: "filterDecay1", group: #filter, options: 0},
  {key: "attack", group: #env, options: 0},
  {key: "decay", group: #env, options: 0},
  {key: "sustain", group: #env, options: 0},
  {key: "drop", group: #env, options: 0},
  {key: "decay1", group: #env, options: 0},
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

// the genes a search's first stage moves for each structure it tries: the first oscillator's
// pulse width, the filter, the envelopes and the tuning (MatchSearch)
let core = [
  "width",
  "cutoff",
  "resonance",
  "filterEnv",
  "filterAttack",
  "filterDecay",
  "filterSustain",
  "filterDrop",
  "filterDecay1",
  "attack",
  "decay",
  "sustain",
  "drop",
  "decay1",
  "tune",
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
let waves = [0., 6., 7., 8., 4.] // sine, saw HQ, pulse HQ, triangle HQ, user (the fitted wave)
let waveNames = ["sine", "saw", "pulse", "triangle", "fitted wave"]
let fittedWave = 4
let intervals = [0., 12., -12., 7., 19., 24., 5.]
// normal, hard sync, FM 1 > 2, PM 2 > 1, PM 1 feedback, ring 1 × 2, AM 2 > 1
let mixModes = [0., 1., 2., 3., 4., 5., 6.]
let mixNames = ["", "sync", "FM", "PM", "feedback", "ring", "AM"]
// the modes where osc 2 only modulates osc 1 (and osc 1 only osc 2 in FM)
let modulates = mode => mode == 3 || mode == 5 || mode == 6
let unisonVoices = [1., 2., 3., 4.]
let octaves = [0, -12, 12]
let filterTypes =
  [
    "2P lowpass",
    "4P lowpass",
    "2P highpass",
    "2P wide bandpass",
    "ladder",
    "formant",
    "comb",
    "formant I",
    "formant II",
    "formant III",
  ]->Array.map(FilterTypes.index)

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

// Envelope times, in ms.
let attackMs = v => logScale(v, 0.2, 3000.)
let decayMs = v => logScale(v, 10., 10000.)
let decay1Ms = v => logScale(v, 10., 3000.)
let filterAttackMs = v => logScale(v, 0.2, 2000.)
let pitchMs = v => logScale(v, 10., 3000.)
// an LFO rate in Hz to a speed in the "10 ms" unit
let lfoSpeed = hz => 100. / hz
let vibratoHz = v => logScale(v, 1.5, 12.)
let wobbleHz = v => logScale(v, 0.3, 12.)
// A gene whose middle fifth is none and whose ends reach ±range, squared towards the middle: the
// pitch sweep's start (±36 semitones) and osc 2's fine ratio (±12).
let bipolar = (v, range) => {
  let u = 2. * v - 1.
  let past = Math.max(0., Math.abs(u) - 0.2) / 0.8
  (u < 0. ? -.range : range) * past * past
}
let ofBipolar = (st, range) => {
  let past = Math.sqrt(Math.min(range, Math.abs(st)) / range)
  let u = 0.2 + 0.8 * past
  (1. + (st < 0. ? -.u : u)) / 2.
}
let pitchSemitones = v => bipolar(v, 36.)
let pitchGene = st => ofBipolar(st, 36.)
let fineSemitones = v => bipolar(v, 12.)
// the breakpoint: below dropOff none (one decay stage); then from just under the peak to -36 dB
let breakpointOf = v => v < 0.1 ? 1. : ampOfDb(-36. * (v - 0.1) / 0.9)
let dropOf = bp => bp > 0.999 ? 0. : 0.1 + 0.9 * clamp01(-.dbOfAmp(bp) / 36.)
// the render's tuning against the sample's pitch, cents
let tuneCents = v => 100. * (v - 0.5)
// below these a gene switches its part off
let o2Off = 0.12
let noiseOff = 0.12
let effectOff = 0.15
let modOff = 0.2

// The key a candidate is played at, and its tuning: the sample's, moved by the render genes.
let playedNote = (x, ~note) => Math.Int.max(12, Math.Int.min(115, note + octaves->Array.getUnsafe(choice(x, "octave"))))
let playedCents = (x, ~cents) => cents + tuneCents(get(x, "tune"))

let secondOscSounds = x => {
  let mode = choice(x, "oscMix")
  get(x, "o2Level") >= o2Off || mode == 2
}

// Every parameter the genes set, with its value: the same ids whatever the genes, so that the
// result replaces all of them. `note` is the key the match plays (playedNote), which the
// cutoff is set for; `base` reads the patch the values go on (for its effects rack).
let decode = (x: Float64Array.t, ~note, ~base: string => float): array<(string, float)> => {
  let v = get(x, ...)
  let out = []
  let set = (id, value) => out->Array.push((id, value))

  // oscillators
  let mode = choice(x, "oscMix")
  set("O1_Waveform", waves->Array.getUnsafe(choice(x, "o1Wave")))
  set("O2_Waveform", waves->Array.getUnsafe(choice(x, "o2Wave")))
  // osc 1 is the modulator in FM mode, where its level is the depth; osc 2's level is the depth
  // in the PM, ring and AM modes
  set("O1_Amp", ampOfDb(-24. + 36. * v("o1Level")))
  let o2 = v("o2Level")
  set("O2_Amp", o2 < o2Off ? 0. : ampOfDb(-30. + 36. * (o2 - o2Off) / (1. - o2Off)))
  let width = 0.5 - 0.45 * v("width")
  set("O1_PWM_W", width)
  set("O2_PWM_W", width)
  set("O1_PWM_D", 0.)
  set("O2_PWM_D", 0.)
  set("Transpose", (intervals->Array.getUnsafe(choice(x, "o2Interval")) + fineSemitones(v("o2Fine"))) / 12.)
  set("Detune", 6. * v("o2Detune") * v("o2Detune"))
  set("OscMix", mixModes->Array.getUnsafe(mode))
  set("PM_Feedback", mode == 3 || mode == 4 ? v("feedback") : 0.)
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
  set("F_Decay1", decay1Ms(v("filterDecay1")))
  set("F_Breakpoint", breakpointOf(v("filterDrop")))
  set("F_Decay2", decayMs(v("filterDecay")))
  set("F_Sustain", v("filterSustain"))

  // the amp envelope: the release isn't heard in the match, so it follows the decay: a sound
  // that dies away rings on when the key is let go, a held one stops soon after
  let decay = decayMs(v("decay"))
  let sustain = def("Sustain").fromNorm(v("sustain"))
  let release = sustain < 0.05 ? decay : Math.min(1500., 60. + 0.3 * decay)
  set("Attack", attackMs(v("attack")))
  set("Hold", 0.)
  set("Decay1", decay1Ms(v("decay1")))
  set("Breakpoint", breakpointOf(v("drop")))
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

// The amp envelope's genes for envelope stages (EnvelopeFit), and back.
let envelopeKeys = ["attack", "decay1", "drop", "decay", "sustain"]
let stagesOf = (e: Float64Array.t): EnvelopeFit.stages => {
  attackMs: attackMs(e->get64(0)),
  decay1Ms: decay1Ms(e->get64(1)),
  breakpoint: breakpointOf(e->get64(2)),
  decay2Ms: decayMs(e->get64(3)),
  sustain: def("Sustain").fromNorm(e->get64(4)),
}

// Where the search starts for a target: a saw through a lowpass, nothing else, with the amp
// envelope fitted to the sample's loudness, the cutoff from its brightness and its pitch
// movement as a sweep.
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
  set("o2Fine", 0.5)
  set("o2Detune", 0.3)
  setChoice("oscMix", 0)
  set("feedback", 0.)
  set("noise", 0.)
  set("noiseColour", 0.)
  setChoice("unison", 0)
  set("unisonDetune", 0.4)
  setChoice("octave", 0)
  set("tune", 0.5)
  setChoice("filterType", 1)
  let hz = Math.max(200., Math.min(10000., 2. * t.brightness))
  set("cutoff", FilterTypes.cutoffOfHz(~filterType=filterTypes->Array.getUnsafe(1), hz))
  set("resonance", 0.1)
  let percussive = t.sustain < 0.1
  set("filterEnv", percussive ? 0.6 : Math.sqrt(0.15 / 0.85))
  set("filterAttack", 0.)
  set("filterDecay", ofLogScale(Math.max(10., 1000. * t.decay * 0.7), 10., 10000.))
  set("filterSustain", percussive ? 0.2 : 0.8)
  set("filterDrop", 0.)
  set("filterDecay1", 0.3)
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

  // the amp envelope: from the sample's attack, decay and sustain, then fitted to its loudness
  let start = Float64Array.fromArray([
    ofLogScale(Math.max(0.2, 1000. * t.attack * 0.6), 0.2, 3000.),
    0.3,
    0.,
    ofLogScale(Math.max(10., 1000. * t.decay), 10., 10000.),
    def("Sustain").toNorm(t.sustain),
  ])
  let loudness = t.loudness
  let peak = loudness->Array.reduce(neg_infinity, Math.max)
  let target = loudness->Array.map(l => l - peak)
  let fit = e => EnvelopeFit.distance(stagesOf(e), target, ~floor=-60.)
  let (best, _) = [start, Float64Array.fromArray([start->get64(0), 0.15, 0.5, start->get64(3), start->get64(4)])]
  ->Array.map(s => EnvelopeFit.minimize(fit, s, ~step=0.15, ~iterations=160))
  ->Array.reduce(None, (best, (x, f)) =>
    switch best {
    | Some((_, b)) if b <= f => best
    | _ => Some((x, f))
    }
  )
  ->Option.getOr((start, 0.))
  envelopeKeys->Array.forEachWithIndex((key, i) => set(key, best->get64(i)))
  x
}

// How many of the optional parts the genes switch on (a second oscillator, noise, unison, a
// mix mode, an off-harmonic ratio, a pitch sweep, vibrato, wobble, drive, chorus, reverb). The
// search charges a little for each, so that a part stays only if it helps the match.
let parts = (x: Float64Array.t) => {
  let v = get(x, ...)
  let mode = choice(x, "oscMix")
  [
    secondOscSounds(x) || modulates(mode),
    mode != 0,
    Math.abs(fineSemitones(v("o2Fine"))) >= 0.05 && (secondOscSounds(x) || modulates(mode)),
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
  let o2 = secondOscSounds(x) || modulates(mode)
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

// Which genes make a difference to a patch: those of the parts it has on (osc 2's when it
// sounds or modulates, the noise colour with noise, the second decay stages with a breakpoint
// and so on). The rest are left out where genes are compared or learned.
let relevant = (x: Float64Array.t) => {
  let v = get(x, ...)
  let mode = choice(x, "oscMix")
  let o2 = secondOscSounds(x) || modulates(mode)
  let pulse = choice(x, "o1Wave") == 2 || o2 && choice(x, "o2Wave") == 2
  genes->Array.map(g =>
    switch g.key {
    | "width" => pulse
    | "o2Wave" | "o2Interval" | "o2Fine" | "o2Detune" => o2
    | "feedback" => mode == 3 || mode == 4
    | "noiseColour" => v("noise") >= noiseOff
    | "unisonDetune" => choice(x, "unison") > 0
    | "filterDecay1" => v("filterDrop") >= 0.1
    | "decay1" => v("drop") >= 0.1
    | "pitchTime" => Math.abs(pitchSemitones(v("pitchEnv"))) >= 0.25
    | "vibratoRate" => v("vibrato") >= modOff
    | "wobbleRate" => v("wobble") >= modOff
    | "reverbTime" => v("reverb") >= effectOff
    | _ => true
    }
  )
}

// A random patch the genes can make, for tests and for training the predictor: every gene
// anywhere, each optional part more often off than on, played at the sample's own pitch and
// never with the fitted wave (which needs a sample).
let random = (random: unit => float) => {
  let x = Float64Array.fromLength(count)
  for i in 0 to count - 1 {
    x->set64(i, random())
  }
  let set = (key, value) => x->set64(indexOf(key), value)
  let setChoice = (key, i) => set(key, valueOfChoice(i, gene(indexOf(key)).options))
  let often = p => random() < p
  if choice(x, "o1Wave") == fittedWave {
    setChoice("o1Wave", Float.toInt(random() * 4.))
  }
  [("o2Level", 0.5), ("noise", 0.7), ("vibrato", 0.75), ("wobble", 0.75), ("drive", 0.7), ("chorus", 0.75), ("reverb", 0.75)]->Array.forEach(((
    key,
    p,
  )) =>
    if often(p) {
      set(key, 0.)
    }
  )
  if often(0.5) {
    setChoice("oscMix", 0)
  }
  if often(0.6) {
    setChoice("unison", 0)
  }
  if often(0.7) {
    set("pitchEnv", 0.5)
  }
  if often(0.6) {
    set("o2Fine", 0.5)
  }
  if often(0.5) {
    set("drop", 0.)
  }
  if often(0.6) {
    set("filterDrop", 0.)
  }
  setChoice("octave", 0)
  set("tune", 0.5)
  x
}

// Patches that between them switch every part on (each mix mode, filter type and wave, with
// unison, noise, sweeps, modulation, drive, chorus and the longest reverb): rendering them shows
// which of the engine's memory a candidate's render can change (MatchEngine.learnPages).
let probes = () =>
  Array.fromInitializer(~length=10, k => {
    let x = Float64Array.fromLength(count)
    genes->Array.forEachWithIndex((g, i) => x->set64(i, g.options == 0 ? 0.8 : valueOfChoice(mod(k, g.options), g.options)))
    let set = (key, value) => x->set64(indexOf(key), value)
    set("octave", valueOfChoice(0, 3))
    set("tune", 0.5)
    set("unison", valueOfChoice(3, 4))
    set("reverbTime", 1.)
    set("pitchEnv", k < 5 ? 0.95 : 0.05)
    x
  })

// A short description of a patch, for its card: "saw + pulse +12 · 4P LP · pluck · reverb".
let describe = (x: Float64Array.t) => {
  let v = get(x, ...)
  let wave = key => waveNames->Array.getUnsafe(choice(x, key))
  let mode = choice(x, "oscMix")
  let o2 = secondOscSounds(x) || modulates(mode)
  let semis = intervals->Array.getUnsafe(choice(x, "o2Interval")) + fineSemitones(v("o2Fine"))
  let rounded = Math.round(semis * 10.) / 10.
  let intervalText = rounded == 0. ? "" : (rounded > 0. ? " +" : " ") ++ Float.toString(rounded)
  let oscText =
    (
      !o2
        ? wave("o1Wave")
        : switch mode {
          | 2 => `${wave("o1Wave")} FM ${wave("o2Wave")}${intervalText}`
          | 3 => `${wave("o2Wave")}${intervalText} PM ${wave("o1Wave")}`
          | 5 => `${wave("o1Wave")} ring ${wave("o2Wave")}${intervalText}`
          | 6 => `${wave("o1Wave")} AM ${wave("o2Wave")}${intervalText}`
          | _ => `${wave("o1Wave")} + ${wave("o2Wave")}${intervalText}`
          }
    ) ++
    (mode == 1 || mode == 4 ? " " ++ mixNames->Array.getUnsafe(mode) : "") ++
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
