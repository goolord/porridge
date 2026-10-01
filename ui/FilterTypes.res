// The filter types: Oatmeal's 16, then Porridge's (long names for menus and the status bar,
// compact names for the narrow value fields). The voice filters (Filter, Filter2) and the
// rack's filter (Ff_Type) share the list; dsp/Filter.cmajor runs them.

let oatmeal = [
  "off",
  "1P lowpass",
  "2P lowpass",
  "4P lowpass",
  "1P highpass",
  "2P highpass",
  "4P highpass",
  "2P wide bandpass",
  "2P narrow bandpass",
  "4P bandpass",
  "2P notch",
  "nonlinear 2P lowpass",
  "nonlinear 4P lowpass",
  "phaser, 4 stages",
  "phaser, 12 stages",
  "phaser, 36 stages",
]

let oatmealShort = [
  "off",
  "1P LP",
  "2P LP",
  "4P LP",
  "1P HP",
  "2P HP",
  "4P HP",
  "2P BP wide",
  "2P BP narrow",
  "4P BP",
  "2P notch",
  "2P LP drive",
  "4P LP drive",
  "phaser 4",
  "phaser 12",
  "phaser 36",
]

// Porridge's types, from 16 on: (long, short, the nearest Oatmeal type for an export)
let porridge = [
  ("SVF LP > BP > HP", "SVF morph", 2),
  ("ladder", "ladder", 3),
  ("diode ladder", "diode", 3),
  ("Sallen-Key", "Sallen-Key", 2),
  ("comb", "comb", 0),
  ("formant", "formant", 9),
  // normal
  ("bandpass 12 dB", "BP 12", 8),
  ("bandpass 24 dB", "BP 24", 9),
  ("peak 12 dB", "peak 12", 8),
  ("peak 24 dB", "peak 24", 9),
  ("notch 12 dB", "notch 12", 10),
  ("notch 24 dB", "notch 24", 10),
  // multi: morphing
  ("L/B/H 24 (morph)", "L/B/H 24", 3),
  ("L/N/H (morph)", "L/N/H", 10),
  ("B/P/B (morph)", "B/P/B", 8),
  ("N/P/N (morph)", "N/P/N", 10),
  // analog
  ("MG low 6", "MG 6", 1),
  ("MG low 12", "MG 12", 2),
  ("MG low 18", "MG 18", 3),
  ("MG low 24", "MG 24", 3),
  ("MG dirty", "MG dirty", 12),
  ("acid ladder", "acid", 12),
  ("French LP", "French LP", 11),
  ("German LP", "German LP", 11),
  ("clean drive", "clean drive", 2),
  ("PZ SVF", "PZ SVF", 2),
  // combs, flanges, phase
  ("comb +", "comb +", 0),
  ("comb −", "comb −", 0),
  ("flanger", "flanger", 0),
  ("flanger +", "flanger +", 0),
  ("flanger −", "flanger −", 0),
  ("phaser", "phaser", 13),
  ("phaser +", "phaser +", 13),
  ("phaser −", "phaser −", 13),
  // vowels
  ("formant I", "formant I", 9),
  ("formant II", "formant II", 9),
  ("formant III", "formant III", 9),
  // misc
  ("low EQ", "low EQ", 0),
  ("band EQ", "band EQ", 0),
  ("high EQ", "high EQ", 0),
  ("ring mod", "ring mod", 0),
  ("sample & hold", "S&H", 0),
  ("diffusor", "diffusor", 0),
  ("reverb", "reverb", 0),
]

let porridgeNames = porridge->Array.map(((long, _, _)) => long)
let porridgeShort = porridge->Array.map(((_, short, _)) => short)

let all = Array.concat(oatmeal, porridgeNames)
let allShort = Array.concat(oatmealShort, porridgeShort)

let firstPorridge = Array.length(oatmeal)

// The closest type Oatmeal has, for an export.
let oatmealType = t =>
  t < firstPorridge ? t : porridge[t - firstPorridge]->Option.mapOr(0, ((_, _, oat)) => oat)

// The index of a type by its long name (which must exist).
let index = name =>
  switch all->Array.findIndex(n => n == name) {
  | -1 => JsError.panic("no filter type " ++ name)
  | i => i
  }

// The groups of the type menu, by the first type of each: their titles.
let groups = [
  (0, "Oatmeal"),
  (16, "zero-delay feedback"),
  (22, "normal"),
  (28, "multi (morph)"),
  (32, "analog"),
  (42, "comb, flange, phase"),
  (50, "formant"),
  (53, "misc"),
]

// Types that F_Drive / Ff_Drive drives: the analog ones.
let hasDrive = t => t >= 32 && t <= 41

// What the morph knob (F_Morph, Ff_Morph) does for a type, if anything.
let morphText = t =>
  if t == 16 || t == 28 {
    Some("lowpass › bandpass › highpass")
  } else if t == 29 {
    Some("lowpass › notch › highpass")
  } else if t == 30 {
    Some("bandpass › peak › bandpass")
  } else if t == 31 {
    Some("notch › peak › notch")
  } else if t == 20 {
    Some("feedback + › none › −")
  } else if t == 21 || t >= 50 && t <= 52 {
    Some("vowel A › E › I › O › U")
  } else if t == 37 {
    Some("resonance squash")
  } else if t == 38 || t == 40 || t == 41 {
    Some("lowpass › bandpass › highpass")
  } else if t == 42 || t == 43 {
    Some("damping in the loop")
  } else if t >= 44 && t <= 46 {
    Some("notched › delayed only")
  } else if t >= 47 && t <= 49 {
    Some("stage spread")
  } else if t >= 53 && t <= 55 {
    Some("boost › cut")
  } else if t == 56 {
    Some("sine › square carrier")
  } else if t == 57 {
    Some("smoothing")
  } else if t == 58 || t == 59 {
    Some("wet › dry")
  } else {
    None
  }

// The rack filter's type parameters (Ff_Type, Ff2_Type ...).
let isFxType = id => String.startsWith(id, "Ff") && String.endsWith(id, "_Type")

// The heading the type menu shows above type t, where a group starts.
let heading = t => groups->Array.find(((first, _)) => first == t)->Option.map(((_, title)) => title)
