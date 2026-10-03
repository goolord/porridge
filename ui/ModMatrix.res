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

// Whether a source has a value for each note (each voice its own) or one every voice shares.
type scope = EachNote | Shared

// A source's scope: always the same, or depending on the program's settings, read by get.
type sourceScope = Fixed(scope) | Depends((string => float) => scope)

// A macro knob (0 the first) or an assignable controller, or neither.
type sourceKind = Plain | Macro(int) | Controller

// colour: its colour on the chips, the ranges it sweeps and its cables; help: what the source is,
// for the status line
type source = {
  key: string,
  label: string,
  colour: string,
  bipolar: bool,
  scope: sourceScope,
  kind: sourceKind,
  help: string,
}

let lfoHelp = "the LFO's shape, -1..1 (without its depth modulation)"
let modEnvHelp = "the mod envelope, with its velocity sensitivity"
let xyHelp = "the XY pad, including its random walk"
let macroHelp = "a macro knob on this page"
let ccHelp = "an assignable controller from the Play page"

// the colours: the voice's own envelopes, the macros, the controllers, and the note and the
// player's hands
let envColour = "#3d7a6d"
let macroColour = "#6a2c70"
let ccColour = "#7a5a1e"
let playColour = "#a3501c"

// The scopes that follow a setting: an LFO's mode (per-voice at 0), and MPE's
let perVoiceAt0 = (id, get: string => float) => get(id) == 0. ? EachNote : Shared
let withMpe = (get: string => float) => get("MPE_On") != 0. ? EachNote : Shared

let lfo = (n, colour, mode) => {
  key: `lfo${Int.toString(n)}`,
  label: `LFO ${Int.toString(n)}`,
  colour,
  bipolar: true,
  scope: Depends(get => perVoiceAt0(mode, get)),
  kind: Plain,
  help: lfoHelp,
}

let macro = n => {
  key: `macro${Int.toString(n)}`,
  label: `macro ${Int.toString(n)}`,
  colour: macroColour,
  bipolar: false,
  scope: Fixed(Shared),
  kind: Macro(n - 1),
  help: macroHelp,
}

let cc = n => {
  key: `cc${Int.toString(n)}`,
  label: `controller ${Int.toString(n)}`,
  colour: ccColour,
  bipolar: false,
  scope: Fixed(Shared),
  kind: Controller,
  help: ccHelp,
}

let sources = [
  {
    key: "none",
    label: "none",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "",
  },
  lfo(1, "#1c3c73", "LFO_1_Sync"),
  lfo(2, "#4a74b4", "LFO_2_Sync"),
  {
    key: "modEnv1",
    label: "mod env 1",
    colour: "#2e6b3a",
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: modEnvHelp,
  },
  {
    key: "modEnv2",
    label: "mod env 2",
    colour: "#5c8f3c",
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: modEnvHelp,
  },
  {
    key: "ampEnv",
    label: "amp env",
    colour: envColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "the amp envelope level",
  },
  {
    key: "filterEnv",
    label: "filter env",
    colour: envColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "the filter envelope level",
  },
  {
    key: "velocity",
    label: "velocity",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "note-on velocity, through the velocity curve",
  },
  {
    key: "key",
    label: "key",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "the note: -1 at note 0, 0 at middle C (60), 1 at note 120 and above",
  },
  {
    key: "aftertouch",
    label: "aftertouch",
    colour: playColour,
    bipolar: false,
    // per-voice in poly touch mode
    scope: Depends(get => get("AftertouchMode") == 2. ? EachNote : withMpe(get)),
    kind: Plain,
    help: "poly aftertouch in poly touch mode, channel pressure otherwise; with MPE, the note's pressure",
  },
  {
    key: "modWheel",
    label: "mod wheel",
    colour: playColour,
    bipolar: false,
    scope: Fixed(Shared),
    kind: Plain,
    help: "controller 1",
  },
  {
    key: "bend",
    label: "pitch bend",
    colour: playColour,
    bipolar: true,
    scope: Depends(withMpe),
    kind: Plain,
    help: "the pitch bend wheel, -1..1; with MPE, the note's own bend",
  },
  {
    key: "x",
    label: "X",
    colour: playColour,
    bipolar: true,
    scope: Fixed(Shared),
    kind: Plain,
    help: xyHelp,
  },
  {
    key: "y",
    label: "Y",
    colour: playColour,
    bipolar: true,
    scope: Fixed(Shared),
    kind: Plain,
    help: xyHelp,
  },
  {
    key: "random",
    label: "random",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "a random value for every note, -1..1",
  },
  ...[1, 2, 3, 4]->Array.map(macro),
  ...[1, 2, 3, 4, 5, 6]->Array.map(cc),
  {
    key: "slide",
    label: "slide (CC 74)",
    colour: playColour,
    bipolar: false,
    scope: Depends(withMpe),
    kind: Plain,
    help: "MPE: the note's slide (controller 74), 0..1",
  },
  {
    key: "noise",
    label: "noise",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "white noise at the control rate: a new random value for each voice every 64 samples, -1..1",
  },
  {
    ...lfo(3, "#7895c8", "LFO_3_Mode"),
    help: "LFO 3 (on the synth page's modulation panel), -1..1",
  },
  {
    key: "interval",
    label: "interval",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "how far the note is from the one before: -1 two octaves down, 0 the same, 1 two octaves up",
  },
  {
    key: "alternate",
    label: "alternate",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "1 and -1 on every other note",
  },
  {
    key: "cycle",
    label: "cycle",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "0, 1/3, 2/3 and 1 over four notes, round and round",
  },
  {
    key: "voiceLevel",
    label: "voice level",
    colour: envColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "how loud the note itself is, at the end of its voice: 0 at -60 dB, 1 at 0 dB",
  },
  {
    key: "wander",
    label: "wander",
    colour: "#8a6d3b",
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "a slow random drift of the note's own, -1..1 (its knob sets the rate)",
  },
  {
    key: "glide",
    label: "glide",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "1 as a glide starts, falling to 0 as it arrives",
  },
  {
    key: "heldNotes",
    label: "held notes",
    colour: playColour,
    bipolar: false,
    scope: Fixed(Shared),
    kind: Plain,
    help: "how many notes are held: 0 with one, 1 with eight or more",
  },
  {
    key: "chord",
    label: "chord place",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "where the note sits among the held notes: -1 the lowest, 1 the highest, 0 a note alone (kept once released)",
  },
  {
    key: "gap",
    label: "gap",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "how long after the note before this one started: 0 within 10 ms (a chord), 1 at 2 s or more",
  },
  {
    key: "legato",
    label: "legato",
    colour: playColour,
    bipolar: false,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "1 when another note was still held as this one started, 0 when none was",
  },
  {
    key: "pitch",
    label: "pitch",
    colour: playColour,
    bipolar: true,
    scope: Fixed(EachNote),
    kind: Plain,
    help: "the note's pitch as it sounds, with glide, bend and pitch modulation: -1 five octaves under middle C, 1 five over",
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
      "pitch",
      "chord",
      "interval",
      "gap",
      "legato",
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

// A source's scope, with the program's settings read by get (the LFOs follow their mode,
// aftertouch the touch mode and MPE, bend and slide MPE).
let scopeOf = (get, source) =>
  switch source.scope {
  | Fixed(scope) => scope
  | Depends(scope) => scope(get)
  }

let sourceScope = (get, key) => sources->Array.find(s => s.key == key)->Option.mapOr(EachNote, scopeOf(get, _))

type law =
  // the parameter's knob, in knob space
  | Knob(string)
  // semitones at amount 1
  | Pitch(float)
  // linear gain 1 + m (silent at -1)
  | Volume
  // pan position offset, hard left/right at ±1 from the centre
  | Pan
  // a parameter of a copy Porridge no longer has: moves nothing
  | Retired
  // slot g's knob i (0-based g: the rack's 0..7, the lane's 8..11; i from 1): the parameter the
  // slot's kind has there (PorridgeParams.knobsOf), whichever it is
  | Slot(int, int)

// label: the knob's own label, with its block where that alone is ambiguous ("osc 1 level"):
// every route to it is named so, whatever system it's in (OatmealParams.targetName)
type target = {key: string, label: string, group: string, law: law}

// The groups of Porridge's own effects, whose parameters only the slots have since October 2026:
// their targets are the slots' (Slot, below), and the ones by parameter keep their places,
// retired (presets that have them load them as the slots' targets: Preset).
let slotOnlyGroups = ["flanger", "phaser", "compressor", "space", "convolve", "bode", "fxfilter", "utility", "ambience", "air", "resonator", "octaver", "shifter"]

let knob = (id, label, group) =>
  slotOnlyGroups->Array.includes(group) ? {key: id, label, group: "retired", law: Retired} : {key: id, label, group, law: Knob(id)}

// The effects' copies Porridge no longer has (PorridgeParams' retired ones: the fourth of each
// kind, the fifth distortion). Their targets keep their places (the DSP and the Mod_Target
// parameters know targets by index), in a group of their own that no menu shows.
// (every copy's, since the slots took them over in October 2026)
let isRetiredCopy = (_group, _n) => true

// copy n's parameter id as a target in this group
let copyKnob = (id, label, group, n) =>
  isRetiredCopy(group, n) ? {key: id, label, group: "retired", law: Retired} : knob(id, label, group)

// Targets of a kind Porridge no longer has (the key shifter, which the frequency shifter took in:
// PorridgeParams.mergedInto), in their places.
let retiredTargets = targets => targets->Array.map(t => {...t, group: "retired", law: Retired})

let targets = [
  {key: "none", label: "none", group: "", law: Volume},
  {key: "pitch", label: "pitch ±24 st", group: "voice", law: Pitch(24.)},
  {key: "finePitch", label: "pitch ±1 st", group: "voice", law: Pitch(1.)},
  {key: "volume", label: "volume", group: "voice", law: Volume},
  {key: "pan", label: "pan", group: "voice", law: Pan},
  knob("O1_Amp", "osc 1 level", "osc"),
  knob("O1_PWM_W", "osc 1 pulse width", "osc"),
  knob("O1_PWM_R", "osc 1 pwm rate", "osc"),
  knob("O1_PWM_D", "osc 1 pwm depth", "osc"),
  knob("O2_Amp", "osc 2 level", "osc"),
  knob("O2_PWM_W", "osc 2 pulse width", "osc"),
  knob("O2_PWM_R", "osc 2 pwm rate", "osc"),
  knob("O2_PWM_D", "osc 2 pwm depth", "osc"),
  knob("Transpose", "osc 2 transpose", "osc"),
  knob("Detune", "osc 2 detune", "osc"),
  knob("N_Amp", "noise level", "osc"),
  knob("N_Resonance", "noise resonance", "osc"),
  knob("N_Transpose", "noise transpose", "osc"),
  knob("U_Detune", "unison detune", "osc"),
  knob("U_Spread", "unison spread", "osc"),
  knob("Cutoff", "cutoff", "filter"),
  knob("Resonance", "resonance", "filter"),
  knob("F_EnvMod", "filter env amount", "filter"),
  knob("F_Track", "filter key track", "filter"),
  knob("F_Split", "filter split", "filter"),
  knob("F_Mix", "filter mix", "filter"),
  knob("Sat_Pregain", "dist pregain", "distortion"),
  knob("Sat_Postgain", "dist postgain", "distortion"),
  knob("LFO_1_Speed", "LFO 1 rate", "lfo"),
  knob("LFO_1_Pitch", "LFO 1 pitch depth", "lfo"),
  knob("LFO_1_Cutoff_1", "LFO 1 cutoff depth", "lfo"),
  knob("LFO_1_Pan", "LFO 1 pan depth", "lfo"),
  knob("LFO_2_Speed", "LFO 2 rate", "lfo"),
  knob("LFO_2_Pitch", "LFO 2 pitch depth", "lfo"),
  knob("LFO_2_Cutoff_1", "LFO 2 cutoff depth", "lfo"),
  knob("LFO_2_Pan", "LFO 2 pan depth", "lfo"),
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
  ...[2, 3, 4]->Array.map(n => copyKnob(`C${Int.toString(n)}_Mix`, `chorus ${Int.toString(n)} mix`, "chorus", n)),
  ...[2, 3, 4]->Array.map(n => copyKnob(`D${Int.toString(n)}_Wet`, `delay ${Int.toString(n)} wet`, "delay", n)),
  ...[2, 3, 4]->Array.map(n => copyKnob(`R${Int.toString(n)}_Wet`, `reverb ${Int.toString(n)} wet`, "reverb", n)),
  ...[2, 3, 4, 5]->Array.map(n =>
    copyKnob(`Sat${Int.toString(n)}_Pregain`, `dist ${Int.toString(n)} pregain`, "distortion", n)
  ),
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
  knob("Cv_Mix", "convolution mix", "convolve"),
  knob("Bd_Shift", "freq shifter shift", "bode"),
  knob("Bd_Feedback", "freq shifter feedback", "bode"),
  knob("Bd_Mix", "freq shifter mix", "bode"),
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
// rate`), the retired ones' too.
let effectTargets = (group, name, copies, params) =>
  [1, ...copies]->Array.flatMap(n =>
    params->Array.map(((id, what)) =>
      n == 1
        ? knob(id, `${name} ${what}`, group)
        : copyKnob(copyParam(id, n), `${name} ${Int.toString(n)} ${what}`, group, n)
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
            : copyKnob(copyParam(id, n), `EQ ${Int.toString(n)} band ${band} ${what}`, "eq", n)
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
      "convolution",
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
      "freq shifter",
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
  knob("LFO_3_Fade", "LFO 3 fade in", "lfo"),
  knob("Wander_Rate", "wander rate", "lfo"),
  ...effectTargets("fxfilter", "FX filter", [2, 3, 4], [("Ff_Track", "tracking")]),
  ...retiredTargets(effectTargets("shifter", "key shifter", [2], [("Sh_Ratio", "ratio"), ("Sh_Hz", "offset"), ("Sh_Mix", "mix")])),
  ...effectTargets(
    "resonator",
    "resonator",
    [2],
    [("Rs_Pitch", "pitch"), ("Rs_Decay", "decay"), ("Rs_Bright", "brightness"), ("Rs_Mix", "mix")],
  ),
  ...effectTargets("resonator", "resonator", [2], [("Rs_Gain", "gain")]),
  ...effectTargets("phaser", "phaser", [2, 3, 4], [("Ph_RateTrack", "rate tracking")]),
  ...effectTargets("flanger", "flanger", [2, 3, 4], [("Fl_RateTrack", "rate tracking"), ("Fl_Track", "delay tracking")]),
  ...effectTargets("octaver", "octaver", [2], [("Oc_Sub", "down"), ("Oc_Up", "up"), ("Oc_Dry", "dry")]),
  knob("O1_Morph", "osc 1 morph", "osc"),
  knob("O1_PD", "osc 1 phase dist", "osc"),
  knob("O2_Morph", "osc 2 morph", "osc"),
  knob("O2_PD", "osc 2 phase dist", "osc"),
  ...effectTargets("bode", "freq shifter", [2, 3], [("Bd_Ratio", "× note")]),
]

// The slots' knobs (PorridgeParams.knobId: FX1_1 .. FX8_28, then VL1_1 .. VL4_21), whatever
// each slot holds: a connection to one moves the parameter the slot's kind has there.
let rackSlotCount = 8
let laneSlotCount = 4
let rackKnobCount = 28
let laneKnobCount = 21
let slotKnobs = g => g < rackSlotCount ? rackKnobCount : laneKnobCount
let slotTargetKey = (g, i) =>
  g < rackSlotCount
    ? `FX${Int.toString(g + 1)}_${Int.toString(i)}`
    : `VL${Int.toString(g - rackSlotCount + 1)}_${Int.toString(i)}`
let targets = [
  ...targets,
  ...Array.fromInitializer(~length=rackSlotCount + laneSlotCount, g =>
    Array.fromInitializer(~length=slotKnobs(g), i => {
      key: slotTargetKey(g, i + 1),
      label: slotTargetKey(g, i + 1),
      group: "slot",
      law: Slot(g, i + 1),
    })
  )->Array.flat,
]

// The target of slot g's knob i.
let firstSlotTarget = targets->Array.findIndex(t => t.group == "slot")
let slotTarget = (g, i) => {
  let before = ref(0)
  for k in 0 to g - 1 {
    before := before.contents + slotKnobs(k)
  }
  firstSlotTarget + before.contents + i - 1
}

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
  ("convolve", "convolution"),
  ("bode", "freq shifter"),
  ("fxfilter", "FX filter"),
  ("utility", "utility"),
  ("ambience", "ambience"),
  ("air", "air"),
  ("resonator", "resonator"),
  ("octaver", "octaver"),
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
// (came later: PorridgeParams.stepSpecs)
let stepsId = k => `Mod${Int.toString(k)}_Steps`
let slotIds = k => [sourceId(k), targetId(k), amountId(k), viaId(k), holdId(k), slewId(k), curveId(k), stepsId(k)]

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

// A connection's steps (Mod_Steps) as a count of levels, or 0 for none.
let stepCount = x => {
  let n = Float.toInt(Math.round(x))
  n >= 2 ? n : 0
}

// The source's value (after the curve) snapped to n levels across its range (-1..1 for a
// bipolar source, 0..1 for the rest), or as it is for n 0. The DSP's modSteps does the same.
let stepped = (x, n, ~bipolar) =>
  if n < 2 {
    x
  } else {
    let m = Int.toFloat(n - 1)
    bipolar ? Math.round((x + 1.) * 0.5 * m) / m * 2. - 1. : Math.round(x * m) / m
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
  // levels (0: none)
  steps: int,
}

let readSlot = (get: string => float, k) => {
  source: Float.toInt(get(sourceId(k))),
  target: Float.toInt(get(targetId(k))),
  amount: get(amountId(k)),
  via: Float.toInt(get(viaId(k))),
  hold: get(holdId(k)) != 0.,
  slew: get(slewId(k)),
  curve: get(curveId(k)),
  steps: stepCount(get(stepsId(k))),
}

let isSlotParam = id => String.startsWith(id, "Mod") && String.includes(id, "_")

let macros = 4
let macroId = k => `Macro_${Int.toString(k)}`
