// The modulation matrix: what can modulate (sources) and what can be modulated (targets).
// Both lists are append-only: presets store sources and targets by key, the DSP and the
// host parameters by index (tools/gen.mjs generates dsp/ModTables.cmajor from them).
//
// A connection adds  source × amount (× via source)  to its target. Parameter targets are
// moved in knob space: amount 1 sweeps the whole knob, whatever the parameter's law. The
// other targets act on the voice directly.

let slots = 32
// the slots there were at first, whose parameters come before the rest of Porridge's
let firstSlots = 16

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
  {key: "lfo3", label: "LFO 3", bipolar: true, help: "LFO 3 (on the synth page's modulation panel), -1..1"},
  {
    key: "interval",
    label: "interval",
    bipolar: true,
    help: "how far the note is from the one before: -1 two octaves down, 0 the same, 1 two octaves up",
  },
  {key: "alternate", label: "alternate", bipolar: true, help: "1 and -1 on every other note"},
  {key: "cycle", label: "cycle", bipolar: false, help: "0, 1/3, 2/3 and 1 over four notes, round and round"},
  {
    key: "voiceLevel",
    label: "voice level",
    bipolar: false,
    help: "how loud the note itself is, at the end of its voice: 0 at -60 dB, 1 at 0 dB",
  },
  {
    key: "wander",
    label: "wander",
    bipolar: true,
    help: "a slow random drift of the note's own, -1..1 (its knob sets the rate)",
  },
  {key: "glide", label: "glide", bipolar: false, help: "1 as a glide starts, falling to 0 as it arrives"},
  {
    key: "heldNotes",
    label: "held notes",
    bipolar: false,
    help: "how many notes are held: 0 with one, 1 with eight or more",
  },
]

// The sources, grouped for menus, by key (a source left out here is shown in a last group of
// its own, so appending one to the list above is enough).
let sourceGroups = [
  (
    "lfos & envelopes",
    ["lfo1", "lfo2", "lfo3", "modEnv1", "modEnv2", "ampEnv", "filterEnv", "voiceLevel", "wander"],
  ),
  (
    "note & performance",
    [
      "velocity",
      "key",
      "interval",
      "alternate",
      "cycle",
      "glide",
      "aftertouch",
      "bend",
      "slide",
      "modWheel",
      "random",
      "noise",
      "heldNotes",
      "x",
      "y",
    ],
  ),
  ("macros", ["macro1", "macro2", "macro3", "macro4"]),
  ("controllers", ["cc1", "cc2", "cc3", "cc4", "cc5", "cc6"]),
]

// Whether a source has a value for each note (each voice its own) or one every voice shares,
// with the program's settings read by get: the LFOs follow their mode, aftertouch the touch
// mode (and MPE), bend and slide MPE.
type scope = EachNote | Shared

let sourceScope = (get: string => float, key) =>
  switch key {
  | "lfo1" => get("LFO_1_Sync") == 0. ? EachNote : Shared
  | "lfo2" => get("LFO_2_Sync") == 0. ? EachNote : Shared
  | "lfo3" => get("LFO_3_Mode") == 0. ? EachNote : Shared
  | "aftertouch" => get("AftertouchMode") == 2. || get("MPE_On") != 0. ? EachNote : Shared
  | "bend" | "slide" => get("MPE_On") != 0. ? EachNote : Shared
  | "modWheel" | "x" | "y" | "heldNotes" => Shared
  | key if String.startsWith(key, "macro") || String.startsWith(key, "cc") => Shared
  | _ => EachNote
  }

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
  knob("Sat_Pregain", "dist pregain", "distortion"),
  knob("Sat_Postgain", "dist postgain", "distortion"),
  knob("LFO_1_Speed", "LFO 1 rate", "lfo"),
  knob("LFO_1_Pitch", "LFO 1 pitch", "lfo"),
  knob("LFO_1_Cutoff_1", "LFO 1 cut 1", "lfo"),
  knob("LFO_1_Pan", "LFO 1 pan", "lfo"),
  knob("LFO_2_Speed", "LFO 2 rate", "lfo"),
  knob("LFO_2_Pitch", "LFO 2 pitch", "lfo"),
  knob("LFO_2_Cutoff_1", "LFO 2 cut 1", "lfo"),
  knob("LFO_2_Pan", "LFO 2 pan", "lfo"),
  knob("C_Rate", "chorus rate", "chorus"),
  knob("C_Depth", "chorus depth", "chorus"),
  knob("C_Feedback", "chorus feedback", "chorus"),
  knob("C_Mix", "chorus mix", "chorus"),
  knob("D_FeedbackL", "delay feedback L", "delay"),
  knob("D_FeedbackR", "delay feedback R", "delay"),
  knob("D_LP", "delay lowpass", "delay"),
  knob("D_HP", "delay highpass", "delay"),
  knob("D_Wet", "delay wet", "delay"),
  knob("R_Dullness", "reverb dullness", "reverb"),
  knob("R_Brightness", "reverb brightness", "reverb"),
  knob("R_Wet", "reverb wet", "reverb"),
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
  knob("Gain", "output gain", "output"),
  knob("F_Morph", "filter morph", "filter"),
  knob("PM_Feedback", "pm feedback", "osc"),
  knob("U_Width", "unison width", "osc"),
  knob("Drift_Pitch", "drift pitch", "osc"),
  // the rack's copies of the effects (PorridgeParams.rackKinds): their levels
  ...[2, 3, 4]->Array.map(n => knob(`C${Int.toString(n)}_Mix`, `chorus ${Int.toString(n)} mix`, "chorus")),
  ...[2, 3, 4]->Array.map(n => knob(`D${Int.toString(n)}_Wet`, `delay ${Int.toString(n)} wet`, "delay")),
  ...[2, 3, 4]->Array.map(n => knob(`R${Int.toString(n)}_Wet`, `reverb ${Int.toString(n)} wet`, "reverb")),
  ...[2, 3, 4, 5]->Array.map(n => knob(`Sat${Int.toString(n)}_Pregain`, `dist ${Int.toString(n)} pregain`, "distortion")),
  knob("F_Drive", "filter drive", "filter"),
  // Porridge's own effects (the first of each kind)
  knob("Fl_Rate", "flanger rate", "flanger"),
  knob("Fl_Depth", "flanger depth", "flanger"),
  knob("Fl_Feedback", "flanger feedback", "flanger"),
  knob("Fl_Mix", "flanger mix", "flanger"),
  knob("Ph_Rate", "phaser rate", "phaser"),
  knob("Ph_Freq", "phaser frequency", "phaser"),
  knob("Ph_Feedback", "phaser feedback", "phaser"),
  knob("Ph_Mix", "phaser mix", "phaser"),
  knob("Cp_Depth", "compressor depth", "compressor"),
  knob("Cp_InGain", "compressor input", "compressor"),
  knob("Cp_Mix", "compressor mix", "compressor"),
  knob("Rv_Size", "algo reverb size", "space"),
  knob("Rv_Mix", "algo reverb mix", "space"),
  knob("Cv_Mix", "convolve mix", "convolve"),
  knob("Bd_Shift", "bode shift", "bode"),
  knob("Bd_Feedback", "bode feedback", "bode"),
  knob("Bd_Mix", "bode mix", "bode"),
  knob("Ff_Cutoff", "FX filter cutoff", "fxfilter"),
  knob("Ff_Resonance", "FX filter resonance", "fxfilter"),
  knob("Ff_Morph", "FX filter morph", "fxfilter"),
  knob("Ff_Drive", "FX filter drive", "fxfilter"),
  knob("Ut_Gain", "utility gain", "utility"),
  knob("Ut_Pan", "utility pan", "utility"),
  knob("Ut_Width", "utility width", "utility"),
  knob("Am_Size", "ambience size", "ambience"),
  knob("Am_Time", "ambience time", "ambience"),
  knob("Am_Mix", "ambience mix", "ambience"),
  knob("Sat_Drive", "dist drive", "distortion"),
  knob("Sat_Tone", "dist tone", "distortion"),
  knob("Sat_Mix", "dist mix", "distortion"),
  knob("Ai_Air", "air amount", "air"),
]

// copy n's parameter (as PorridgeParams.copyId: D_Wet, 3 is D3_Wet)
let copyParam = (id, n) => {
  let i = String.indexOf(id, "_")
  String.slice(id, ~start=0, ~end=i) ++ Int.toString(n) ++ String.slice(id, ~start=i)
}

// An effect's parameters as targets: its first's (`chorus rate`), then each copy's (`chorus 2
// rate`).
let effectTargets = (group, name, copies, params) =>
  [1, ...copies]->Array.flatMap(n =>
    params->Array.map(((id, what)) =>
      n == 1
        ? knob(id, `${name} ${what}`, group)
        : knob(copyParam(id, n), `${name} ${Int.toString(n)} ${what}`, group)
    )
  )

// More of the effects' parameters, and the rack copies' (those already above are left out).
// Not the delay's lengths, the reverb's size and predelay or the convolver's length: changing
// those restarts the effect. A fixed batch: targets added later go after it.
let targets = {
  let more = [
    ...effectTargets(
      "chorus",
      "chorus",
      [2, 3, 4],
      [("C_Rate", "rate"), ("C_Depth", "depth"), ("C_Feedback", "feedback"), ("C_Mix", "mix"), ("C_MinDelay", "delay")],
    ),
    ...effectTargets(
      "delay",
      "delay",
      [2, 3, 4],
      [
        ("D_FeedbackL", "feedback L"),
        ("D_FeedbackR", "feedback R"),
        ("D_LP", "lowpass"),
        ("D_HP", "highpass"),
        ("D_Wet", "wet"),
        ("D_Dry", "dry"),
        ("D_InputPan", "input pan"),
        ("D_Rotation", "rotation"),
      ],
    ),
    ...effectTargets(
      "reverb",
      "reverb",
      [2, 3, 4],
      [
        ("R_Dullness", "dullness"),
        ("R_Brightness", "brightness"),
        ("R_Wet", "wet"),
        ("R_Dry", "dry"),
        ("R_Length", "length"),
        ("R_EarlyMix", "early mix"),
        ("R_Rotation", "rotation"),
      ],
    ),
    // the bands' gains, then their frequencies and slopes (EQ 1 slope, EQ 2 band 1 gain)
    ...[1, 2, 3, 4]->Array.flatMap(n =>
      [("Amp", "gain"), ("Freq", "freq"), ("Slope", "slope")]->Array.flatMap(((p, what)) =>
        [1, 2, 3, 4, 5]->Array.map(b => {
          let (id, band) = (`EQ_${Int.toString(b)}_${p}`, Int.toString(b))
          n == 1
            ? knob(id, `EQ ${band} ${what}`, "eq")
            : knob(copyParam(id, n), `EQ ${Int.toString(n)} band ${band} ${what}`, "eq")
        })
      )
    ),
    ...effectTargets(
      "distortion",
      "dist",
      [2, 3, 4, 5],
      [("Sat_Pregain", "pregain"), ("Sat_Postgain", "postgain"), ("Sat_Limit", "limit")],
    ),
    ...effectTargets(
      "flanger",
      "flanger",
      [2, 3, 4],
      [
        ("Fl_Rate", "rate"),
        ("Fl_Depth", "depth"),
        ("Fl_Feedback", "feedback"),
        ("Fl_Mix", "mix"),
        ("Fl_Delay", "delay"),
        ("Fl_Phase", "phase"),
      ],
    ),
    ...effectTargets(
      "phaser",
      "phaser",
      [2, 3, 4],
      [
        ("Ph_Rate", "rate"),
        ("Ph_Freq", "frequency"),
        ("Ph_Feedback", "feedback"),
        ("Ph_Mix", "mix"),
        ("Ph_Depth", "depth"),
        ("Ph_Spread", "spread"),
        ("Ph_Phase", "phase"),
        ("Ph_Track", "tracking"),
      ],
    ),
    ...effectTargets(
      "compressor",
      "compressor",
      [2, 3, 4],
      [
        ("Cp_Depth", "depth"),
        ("Cp_InGain", "input"),
        ("Cp_Mix", "mix"),
        ("Cp_OutGain", "output"),
        ("Cp_Attack", "attack"),
        ("Cp_Release", "release"),
        ("Cp_LowSplit", "low split"),
        ("Cp_HighSplit", "high split"),
        ("Cp_LowGain", "low gain"),
        ("Cp_MidGain", "mid gain"),
        ("Cp_HighGain", "high gain"),
      ],
    ),
    ...effectTargets(
      "space",
      "algo reverb",
      [2, 3, 4],
      [
        ("Rv_Size", "size"),
        ("Rv_Mix", "mix"),
        ("Rv_Decay", "decay"),
        ("Rv_Predelay", "predelay"),
        ("Rv_Damp", "damping"),
        ("Rv_LowCut", "low cut"),
        ("Rv_Width", "width"),
        ("Rv_Mod", "modulation"),
      ],
    ),
    ...effectTargets(
      "convolve",
      "convolve",
      [2],
      [
        ("Cv_Mix", "mix"),
        ("Cv_Gain", "gain"),
        ("Cv_Predelay", "predelay"),
        ("Cv_LowCut", "low cut"),
        ("Cv_HighCut", "high cut"),
        ("Cv_Width", "width"),
      ],
    ),
    ...effectTargets(
      "bode",
      "bode",
      [2, 3, 4],
      [("Bd_Shift", "shift"), ("Bd_Feedback", "feedback"), ("Bd_Mix", "mix"), ("Bd_Delay", "delay")],
    ),
    ...effectTargets(
      "fxfilter",
      "FX filter",
      [2, 3, 4],
      [
        ("Ff_Cutoff", "cutoff"),
        ("Ff_Resonance", "resonance"),
        ("Ff_Morph", "morph"),
        ("Ff_Drive", "drive"),
        ("Ff_Spread", "spread"),
        ("Ff_Mix", "mix"),
      ],
    ),
    ...effectTargets(
      "utility",
      "utility",
      [2, 3, 4],
      [("Ut_Gain", "gain"), ("Ut_Pan", "pan"), ("Ut_Width", "width"), ("Ut_BassMono", "bass mono")],
    ),
    ...effectTargets(
      "ambience",
      "ambience",
      [2, 3, 4],
      [
        ("Am_Size", "size"),
        ("Am_Time", "time"),
        ("Am_Mix", "mix"),
        ("Am_Density", "density"),
        ("Am_Predelay", "predelay"),
        ("Am_HighCut", "high cut"),
        ("Am_Width", "width"),
        ("Am_HighTime", "high time"),
        ("Am_HighFreq", "high freq"),
        ("Am_LowTime", "low time"),
        ("Am_LowFreq", "low freq"),
      ],
    ),
  ]
  [...targets, ...more->Array.filter(t => !(targets->Array.some(o => o.key == t.key)))]
}

// Targets added after that batch, in the order they came.
let targets = [
  ...targets,
  knob("LFO_3_Rate", "LFO 3 rate", "lfo"),
  knob("LFO_3_Fade", "LFO 3 fade-in", "lfo"),
  knob("Wander_Rate", "wander rate", "lfo"),
  ...effectTargets("fxfilter", "FX filter", [2, 3, 4], [("Ff_Track", "tracking")]),
  ...effectTargets("shifter", "shifter", [2], [("Sh_Ratio", "ratio"), ("Sh_Hz", "offset"), ("Sh_Mix", "mix")]),
  ...effectTargets(
    "resonator",
    "resonator",
    [2],
    [("Rs_Pitch", "pitch"), ("Rs_Decay", "decay"), ("Rs_Bright", "brightness"), ("Rs_Mix", "mix")],
  ),
]

// The target groups, by the key in each target's group, with their titles.
let groups = [
  ("voice", "voice"),
  ("osc", "oscillators"),
  ("filter", "filter"),
  ("lfo", "LFOs"),
  ("output", "output"),
  ("chorus", "chorus"),
  ("delay", "delay"),
  ("reverb", "reverb"),
  ("eq", "EQ"),
  ("distortion", "distortion"),
  ("flanger", "flanger"),
  ("phaser", "phaser"),
  ("compressor", "compressor"),
  ("space", "algo reverb"),
  ("convolve", "convolve"),
  ("bode", "bode"),
  ("fxfilter", "FX filter"),
  ("utility", "utility"),
  ("ambience", "ambience"),
  ("air", "air"),
  ("shifter", "shifter"),
  ("resonator", "resonator"),
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
// how the connection holds and smooths its value (PorridgeParams.slotOptionSpecs)
let holdId = k => `Mod${Int.toString(k)}_Hold`
let slewId = k => `Mod${Int.toString(k)}_Slew`
let curveId = k => `Mod${Int.toString(k)}_Curve`
let slotIds = k => [sourceId(k), targetId(k), amountId(k), viaId(k), holdId(k), slewId(k), curveId(k)]

// A connection's slew (Mod_Slew 0..1) in milliseconds: up to two seconds.
let slewMs = x => 2000. * x * x

// What a connection's curve does to its source's value (-1..1 or 0..1): bent towards the ends
// (curve > 0) or towards 0 (curve < 0), the same both ways for a bipolar source. The DSP's
// modCurve does the same.
let curved = (x, curve) =>
  curve == 0.
    ? x
    : {
        let y = Math.pow(Math.abs(x), ~exp=Math.pow(4., ~exp=-.curve))
        x < 0. ? -.y : y
      }

// What slot k holds, by source and target index (0 is none), read with get.
type slot = {
  source: int,
  target: int,
  amount: float,
  via: int,
  // latched at note-on
  hold: bool,
  slew: float,
  curve: float,
}

let readSlot = (get: string => float, k) => {
  source: Float.toInt(get(sourceId(k))),
  target: Float.toInt(get(targetId(k))),
  amount: get(amountId(k)),
  via: Float.toInt(get(viaId(k))),
  hold: get(holdId(k)) != 0.,
  slew: get(slewId(k)),
  curve: get(curveId(k)),
}

let isSlotParam = id => String.startsWith(id, "Mod") && String.includes(id, "_")

let macros = 4
let macroId = k => `Macro_${Int.toString(k)}`
