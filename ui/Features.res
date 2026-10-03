// The patch's features (the noise generator, unison, the dual filter, an LFO ...): whether each
// is in use, and the parameters that decide it. Panels mark the tabs of those in use (Panel.mark),
// so that nothing that sounds hides behind a tab; a summary of the patch can read the same.

type t = {
  key: string,
  name: string,
  // the parameters isActive reads
  ids: array<string>,
  isActive: (string => float) => bool,
}

// A parameter away from its default.
let changed = (get: string => float, id) =>
  Lazy.get(ParamDefs.byId)->Map.get(id)->Option.mapOr(false, d => get(id) != d.init)

let make = (key, name, ids, isActive) => {key, name, ids, isActive}

// in use while any of these is away from its default
let anyChanged = (key, name, ids) => make(key, name, ids, get => ids->Array.some(changed(get, _)))

// in use while this list or switch isn't at its first value
let switched = (key, name, id) => make(key, name, [id], get => get(id) != 0.)

// in use while the source moves something (Modulators.from)
let source = (key, name) =>
  make(key, name, Modulators.fromIds(key), get => Modulators.movesAnything(get, key))

let noise = make("noise", "noise", ["N_Amp"], get => get("N_Amp") > 0.)
let oscNoise = make("oscNoise", "osc roughness", ["O1_Noise", "O2_Noise"], get =>
  get("O1_Noise") > 0. || get("O2_Noise") > 0.
)
let oscShape = make("oscShape", "osc morph and phase dist", ["O1_Morph", "O1_PD", "O2_Morph", "O2_PD"], get =>
  get("O1_Morph") > 0. || get("O1_PD") > 0. || get("O2_Morph") > 0. || get("O2_PD") > 0.
)
let unison = make("unison", "unison", ["U_Voices"], get => get("U_Voices") > 1.)
let drift = make("drift", "drift", ["Drift_Pitch", "Drift_Cutoff"], get =>
  get("Drift_Pitch") > 0. || get("Drift_Cutoff") > 0.
)
let oscPhase = anyChanged(
  "oscPhase",
  "osc phase",
  ["OscPhase", "OscPhaseRand", "OscRetrig", "PWMPhase", "PWMPhaseRand", "PWMRetrig"],
)
let lfoPhase = anyChanged("lfoPhase", "LFO phase", ["LFOPhase", "LFOPhaseRand", "LFORetrig"])
let oscEnv = n => switched(`oscEnv${Int.toString(n)}`, `osc ${Int.toString(n)} env`, `OE${Int.toString(n)}_On`)
// (the osc mix modes beyond Oatmeal's: PM, PM feedback, ring, AM)
let oscMix = switched("oscMix", "osc mix", "OscMix")
let dualFilter = switched("dualFilter", "dual filter", "F_Double")
let keyEq = switched("keyEq", "key EQ", "KEQ_On")
let voiceLane = make("voiceLane", "per-voice effects", VoiceLane.ids, get => FxRack.readLane(get) != [])
let distortion = make("distortion", "distortion", [FxRack.switchId(FxRack.oatmealDistortion)], get =>
  FxRack.isOn(FxRack.oatmealDistortion, get)
)
let pitchEnv = switched("pitchEnv", "pitch env", "PEnv_On")
let modEnv1 = source("modEnv1", "mod env 1")
let modEnv2 = source("modEnv2", "mod env 2")
let lfo1 = source("lfo1", "LFO 1")
let lfo2 = source("lfo2", "LFO 2")
let lfo3 = source("lfo3", "LFO 3")
let glide = make("glide", "glide", ["Glide"], get => get("Glide") > 0.)
let touch = make("touch", "aftertouch", ["OscAftertouch", "O1_Afterpitch", "O2_Afterpitch"], get =>
  ["OscAftertouch", "O1_Afterpitch", "O2_Afterpitch"]->Array.some(id => get(id) != 0.)
)
let random = anyChanged("random", "random", ["RandomFreq", "RandomPan", "RandomAmp", "FreqPan"])
let tuning = anyChanged(
  "tuning",
  "tuning",
  [
    "Tune_Main",
    "Tune_Octave",
    "Tune_CutReference",
    "Tune_PanReference",
    "Tune_C",
    "Tune_Db",
    "Tune_D",
    "Tune_Eb",
    "Tune_E",
    "Tune_F",
    "Tune_Gb",
    "Tune_G",
    "Tune_Ab",
    "Tune_A",
    "Tune_Bb",
    "Tune_B",
  ],
)

let all = [
  oscShape,
  noise,
  oscNoise,
  unison,
  drift,
  oscPhase,
  lfoPhase,
  oscEnv(1),
  oscEnv(2),
  oscMix,
  dualFilter,
  keyEq,
  voiceLane,
  distortion,
  pitchEnv,
  modEnv1,
  modEnv2,
  lfo1,
  lfo2,
  lfo3,
  glide,
  touch,
  random,
  tuning,
]

let isOn = (model, f) => f.isActive(id => model->ParamModel.get(id))
