// The modulation matrix: what can modulate (sources) and what can be modulated (targets).
// Both lists are append-only: presets store sources and targets by key, the DSP and the
// host parameters by index (tools/gen.mjs generates dsp/ModTables.cmajor from them).
//
// A connection adds  source × amount (× via source)  to its target. Parameter targets are
// moved in knob space: amount 1 sweeps the whole knob, whatever the parameter's law. The
// other targets act on the voice directly.

let slots = 16

// help: what the source is, for the mod page's status line
type source = {key: string, label: string, bipolar: bool, help: string}

let lfoHelp = "the LFO's shape, -1..1 (without its depth modulation)"
let modEnvHelp = "the mod envelope, with its velocity sensitivity"
let xyHelp = "the XY pad, including its random walk"
let macroHelp = "a macro knob on this page"
let ccHelp = "an assignable controller from the MIDI page"

let sources = [
  {key: "none", label: "none", bipolar: false, help: ""},
  {key: "lfo1", label: "LFO 1", bipolar: true, help: lfoHelp},
  {key: "lfo2", label: "LFO 2", bipolar: true, help: lfoHelp},
  {key: "modEnv1", label: "mod env 1", bipolar: false, help: modEnvHelp},
  {key: "modEnv2", label: "mod env 2", bipolar: false, help: modEnvHelp},
  {key: "ampEnv", label: "amp env", bipolar: false, help: "the amp envelope level"},
  {key: "filterEnv", label: "filter env", bipolar: false, help: "the filter envelope level"},
  {
    key: "velocity",
    label: "velocity",
    bipolar: false,
    help: "note-on velocity, through the velocity curve",
  },
  {
    key: "key",
    label: "key",
    bipolar: true,
    help: "the note: -1 at note 0, 0 at middle C (60), 1 at note 120 and above",
  },
  {
    key: "aftertouch",
    label: "aftertouch",
    bipolar: false,
    help: "poly aftertouch in poly touch mode, channel pressure otherwise; with MPE, the note's pressure",
  },
  {key: "modWheel", label: "mod wheel", bipolar: false, help: "controller 1"},
  {
    key: "bend",
    label: "pitch bend",
    bipolar: true,
    help: "the pitch bend wheel, -1..1; with MPE, the note's own bend",
  },
  {key: "x", label: "X", bipolar: true, help: xyHelp},
  {key: "y", label: "Y", bipolar: true, help: xyHelp},
  {key: "random", label: "random", bipolar: true, help: "a random value for every note, -1..1"},
  {key: "macro1", label: "macro 1", bipolar: false, help: macroHelp},
  {key: "macro2", label: "macro 2", bipolar: false, help: macroHelp},
  {key: "macro3", label: "macro 3", bipolar: false, help: macroHelp},
  {key: "macro4", label: "macro 4", bipolar: false, help: macroHelp},
  {key: "cc1", label: "controller 1", bipolar: false, help: ccHelp},
  {key: "cc2", label: "controller 2", bipolar: false, help: ccHelp},
  {key: "cc3", label: "controller 3", bipolar: false, help: ccHelp},
  {key: "cc4", label: "controller 4", bipolar: false, help: ccHelp},
  {key: "cc5", label: "controller 5", bipolar: false, help: ccHelp},
  {key: "cc6", label: "controller 6", bipolar: false, help: ccHelp},
  {
    key: "slide",
    label: "slide (CC 74)",
    bipolar: false,
    help: "MPE: the note's slide (controller 74), 0..1",
  },
  {
    key: "noise",
    label: "noise",
    bipolar: true,
    help: "white noise at the control rate: a new random value for each voice every 64 samples, -1..1",
  },
]

// The sources, grouped for the mod page, by key (a source left out here is shown in a last
// group of its own, so appending one to the list above is enough).
let sourceGroups = [
  ("lfos & envelopes", ["lfo1", "lfo2", "modEnv1", "modEnv2", "ampEnv", "filterEnv"]),
  (
    "note & performance",
    ["velocity", "key", "aftertouch", "bend", "slide", "modWheel", "random", "noise", "x", "y"],
  ),
  ("macros", ["macro1", "macro2", "macro3", "macro4"]),
  ("controllers", ["cc1", "cc2", "cc3", "cc4", "cc5", "cc6"]),
]

type law =
  // the parameter's knob, in knob space
  | Knob(string)
  // semitones at amount 1
  | Pitch(float)
  // linear gain 1 + m (silent at -1)
  | Volume
  // pan position offset, hard left/right at ±1 from the centre
  | Pan

type target = {key: string, label: string, group: string, law: law}

let knob = (id, label, group) => {key: id, label, group, law: Knob(id)}

let targets = [
  {key: "none", label: "none", group: "", law: Volume},
  {key: "pitch", label: "pitch ±24 st", group: "voice", law: Pitch(24.)},
  {key: "finePitch", label: "pitch ±1 st", group: "voice", law: Pitch(1.)},
  {key: "volume", label: "volume", group: "voice", law: Volume},
  {key: "pan", label: "pan", group: "voice", law: Pan},
  knob("O1_Amp", "osc 1 amp", "osc"),
  knob("O1_PWM_W", "osc 1 pulsewidth", "osc"),
  knob("O1_PWM_R", "osc 1 pwm rate", "osc"),
  knob("O1_PWM_D", "osc 1 pwm depth", "osc"),
  knob("O2_Amp", "osc 2 amp", "osc"),
  knob("O2_PWM_W", "osc 2 pulsewidth", "osc"),
  knob("O2_PWM_R", "osc 2 pwm rate", "osc"),
  knob("O2_PWM_D", "osc 2 pwm depth", "osc"),
  knob("Transpose", "osc 2 transpose", "osc"),
  knob("Detune", "osc 2 detune", "osc"),
  knob("N_Amp", "noise amp", "osc"),
  knob("N_Resonance", "noise resonance", "osc"),
  knob("N_Transpose", "noise transpose", "osc"),
  knob("U_Detune", "unison detune", "osc"),
  knob("U_Spread", "unison spread", "osc"),
  knob("Cutoff", "cutoff", "filter"),
  knob("Resonance", "resonance", "filter"),
  knob("F_EnvMod", "filter env mod", "filter"),
  knob("F_Track", "filter keytrack", "filter"),
  knob("F_Split", "filter split", "filter"),
  knob("F_Mix", "filter mix", "filter"),
  knob("Sat_Pregain", "dist pregain", "filter"),
  knob("Sat_Postgain", "dist postgain", "filter"),
  knob("LFO_1_Speed", "LFO 1 rate", "lfo"),
  knob("LFO_1_Pitch", "LFO 1 pitch", "lfo"),
  knob("LFO_1_Cutoff_1", "LFO 1 cut 1", "lfo"),
  knob("LFO_1_Pan", "LFO 1 pan", "lfo"),
  knob("LFO_2_Speed", "LFO 2 rate", "lfo"),
  knob("LFO_2_Pitch", "LFO 2 pitch", "lfo"),
  knob("LFO_2_Cutoff_1", "LFO 2 cut 1", "lfo"),
  knob("LFO_2_Pan", "LFO 2 pan", "lfo"),
  knob("C_Rate", "chorus rate", "fx"),
  knob("C_Depth", "chorus depth", "fx"),
  knob("C_Feedback", "chorus feedback", "fx"),
  knob("C_Mix", "chorus mix", "fx"),
  knob("D_FeedbackL", "delay feedback L", "fx"),
  knob("D_FeedbackR", "delay feedback R", "fx"),
  knob("D_LP", "delay lowpass", "fx"),
  knob("D_HP", "delay highpass", "fx"),
  knob("D_Wet", "delay wet", "fx"),
  knob("R_Dullness", "reverb dullness", "fx"),
  knob("R_Brightness", "reverb brightness", "fx"),
  knob("R_Wet", "reverb wet", "fx"),
  knob("EQ_1_Amp", "EQ 1 gain", "eq"),
  knob("EQ_2_Amp", "EQ 2 gain", "eq"),
  knob("EQ_3_Amp", "EQ 3 gain", "eq"),
  knob("EQ_4_Amp", "EQ 4 gain", "eq"),
  knob("EQ_5_Amp", "EQ 5 gain", "eq"),
  knob("EQ_1_Freq", "EQ 1 freq", "eq"),
  knob("EQ_2_Freq", "EQ 2 freq", "eq"),
  knob("EQ_3_Freq", "EQ 3 freq", "eq"),
  knob("EQ_4_Freq", "EQ 4 freq", "eq"),
  knob("EQ_5_Freq", "EQ 5 freq", "eq"),
  knob("Gain", "output gain", "fx"),
  knob("F_Morph", "filter morph", "filter"),
  knob("PM_Feedback", "pm feedback", "osc"),
  knob("U_Width", "unison width", "osc"),
  knob("Drift_Pitch", "drift pitch", "osc"),
  // the rack's copies of the effects (PorridgeParams.rackKinds): their levels
  ...[2, 3, 4]->Array.map(n => knob(`C${Int.toString(n)}_Mix`, `chorus ${Int.toString(n)} mix`, "rack")),
  ...[2, 3, 4]->Array.map(n => knob(`D${Int.toString(n)}_Wet`, `delay ${Int.toString(n)} wet`, "rack")),
  ...[2, 3, 4]->Array.map(n => knob(`R${Int.toString(n)}_Wet`, `reverb ${Int.toString(n)} wet`, "rack")),
  ...[2, 3, 4, 5]->Array.map(n => knob(`Sat${Int.toString(n)}_Pregain`, `dist ${Int.toString(n)} pregain`, "rack")),
  knob("F_Drive", "filter drive", "filter"),
  // Porridge's own effects (the first of each kind)
  knob("Fl_Rate", "flanger rate", "fx2"),
  knob("Fl_Depth", "flanger depth", "fx2"),
  knob("Fl_Feedback", "flanger feedback", "fx2"),
  knob("Fl_Mix", "flanger mix", "fx2"),
  knob("Ph_Rate", "phaser rate", "fx2"),
  knob("Ph_Freq", "phaser frequency", "fx2"),
  knob("Ph_Feedback", "phaser feedback", "fx2"),
  knob("Ph_Mix", "phaser mix", "fx2"),
  knob("Cp_Depth", "compressor depth", "fx2"),
  knob("Cp_InGain", "compressor input", "fx2"),
  knob("Cp_Mix", "compressor mix", "fx2"),
  knob("Rv_Size", "algo reverb size", "fx2"),
  knob("Rv_Mix", "algo reverb mix", "fx2"),
  knob("Cv_Mix", "convolve mix", "fx2"),
  knob("Bd_Shift", "bode shift", "fx2"),
  knob("Bd_Feedback", "bode feedback", "fx2"),
  knob("Bd_Mix", "bode mix", "fx2"),
  knob("Ff_Cutoff", "FX filter cutoff", "fx2"),
  knob("Ff_Resonance", "FX filter resonance", "fx2"),
  knob("Ff_Morph", "FX filter morph", "fx2"),
  knob("Ff_Drive", "FX filter drive", "fx2"),
  knob("Ut_Gain", "utility gain", "fx2"),
  knob("Ut_Pan", "utility pan", "fx2"),
  knob("Ut_Width", "utility width", "fx2"),
]

// The target groups, by the key in each target's group, with their titles.
let groups = [
  ("voice", "voice"),
  ("osc", "oscillators"),
  ("filter", "filter & distortion"),
  ("lfo", "LFOs"),
  ("fx", "effects"),
  ("eq", "EQ"),
  ("rack", "rack copies"),
  ("fx2", "more effects"),
]

let sourceIndex = key => sources->Array.findIndex(s => s.key == key)
let targetIndex = key => targets->Array.findIndex(t => t.key == key)

// the target that moves this parameter's knob, if any
let targetOfParam = id => targets->Array.findIndex(t => t.law == Knob(id))

// The slots' numbers, 1-based like their parameters.
let slotNumbers = Array.fromInitializer(~length=slots, i => i + 1)

// The parameters of slot k (1-based).
let sourceId = k => `Mod${Int.toString(k)}_Source`
let targetId = k => `Mod${Int.toString(k)}_Target`
let amountId = k => `Mod${Int.toString(k)}_Amount`
let viaId = k => `Mod${Int.toString(k)}_Via`
let slotIds = k => [sourceId(k), targetId(k), amountId(k), viaId(k)]

// What slot k holds, by source and target index (0 is none), read with get.
type slot = {source: int, target: int, amount: float, via: int}

let readSlot = (get: string => float, k) => {
  source: Float.toInt(get(sourceId(k))),
  target: Float.toInt(get(targetId(k))),
  amount: get(amountId(k)),
  via: Float.toInt(get(viaId(k))),
}

let isSlotParam = id => String.startsWith(id, "Mod") && String.includes(id, "_")

let macros = 4
let macroId = k => `Macro_${Int.toString(k)}`
