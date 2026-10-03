// The filter types: Oatmeal's 16, then Porridge's (long names for the status bar and the
// tools, compact "family · character" texts for the narrow value fields). The voice filters
// (Filter, Filter2) and the rack's filter (Ff_Type) share the list; dsp/Filter.cmajor runs them.
//
// Values are append only (presets and hosts keep the number). The menu goes by sound instead
// (families below), and maps what is picked onto these values.
//
// Two values are another type's sound, and the DSP runs them as that type, so every program,
// whatever shares or moves the filter's morph and resonance, sounds as it did: Sallen-Key is
// the SVF's lowpass (morph 0) with its own resonance law (2 - 1.98 res for the SVF's 2 - 1.96
// res), and peak 12 dB is B/P/B at morph 0.5 (the same coefficients). The low EQ is not the high
// EQ mirrored: their shapes match (a low shelf boost is a high shelf cut), but the low EQ is
// louder by the shelf's gain, up to 24 dB.

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
  "lowpass · 1P",
  "lowpass · 2P",
  "lowpass · 4P",
  "highpass · 1P",
  "highpass · 2P",
  "highpass · 4P",
  "bandpass · wide",
  "bandpass · narrow",
  "bandpass · 4P",
  "notch · 2P",
  "lowpass · 2P drive",
  "lowpass · 4P drive",
  "phaser · 4 stages",
  "phaser · 12 stages",
  "phaser · 36 stages",
]

type info = {
  name: string,
  short: string,
  // the nearest of Oatmeal's types, for an export (one of Oatmeal's is itself)
  oat: int,
  // whether the drive (F_Drive, Ff_Drive) drives it: the analog types
  drive: bool,
  // what the morph knob (F_Morph, Ff_Morph) does for it, if anything
  morph: option<string>,
}

let lowBandHigh = Some("lowpass › bandpass › highpass")
let vowels = Some("vowel A › E › I › O › U")

// Porridge's types, from 16 on.
let porridge = [
  {name: "SVF LP > BP > HP", short: "lowpass · SVF", oat: 2, drive: false, morph: lowBandHigh},
  {name: "ladder", short: "lowpass · ladder", oat: 3, drive: false, morph: None},
  {name: "diode ladder", short: "lowpass · diode", oat: 3, drive: false, morph: None},
  {name: "Sallen-Key", short: "lowpass · Sallen-K.", oat: 2, drive: false, morph: None},
  {name: "comb", short: "comb", oat: 0, drive: false, morph: Some("feedback + › none › −")},
  {name: "formant", short: "formant · vowels", oat: 9, drive: false, morph: vowels},
  {name: "bandpass 12 dB", short: "bandpass · 12 dB", oat: 8, drive: false, morph: None},
  {name: "bandpass 24 dB", short: "bandpass · 24 dB", oat: 9, drive: false, morph: None},
  {name: "peak 12 dB", short: "peak · 12 dB", oat: 8, drive: false, morph: None},
  {name: "peak 24 dB", short: "peak · 24 dB", oat: 9, drive: false, morph: None},
  {name: "notch 12 dB", short: "notch · 12 dB", oat: 10, drive: false, morph: None},
  {name: "notch 24 dB", short: "notch · 24 dB", oat: 10, drive: false, morph: None},
  {name: "L/B/H 24 (morph)", short: "morph · L›B›H 24", oat: 3, drive: false, morph: lowBandHigh},
  {name: "L/N/H (morph)", short: "morph · L›N›H", oat: 10, drive: false, morph: Some("lowpass › notch › highpass")},
  {name: "B/P/B (morph)", short: "morph · B›P›B", oat: 8, drive: false, morph: Some("bandpass › peak › bandpass")},
  {name: "N/P/N (morph)", short: "morph · N›P›N", oat: 10, drive: false, morph: Some("notch › peak › notch")},
  {name: "MG low 6", short: "lowpass · MG 6", oat: 1, drive: true, morph: None},
  {name: "MG low 12", short: "lowpass · MG 12", oat: 2, drive: true, morph: None},
  {name: "MG low 18", short: "lowpass · MG 18", oat: 3, drive: true, morph: None},
  {name: "MG low 24", short: "lowpass · MG 24", oat: 3, drive: true, morph: None},
  {name: "MG dirty", short: "lowpass · MG dirty", oat: 12, drive: true, morph: None},
  {name: "acid ladder", short: "lowpass · acid", oat: 12, drive: true, morph: Some("resonance squash")},
  {name: "French LP", short: "lowpass · French", oat: 11, drive: true, morph: lowBandHigh},
  {name: "German LP", short: "lowpass · German", oat: 11, drive: true, morph: None},
  {name: "clean drive", short: "lowpass · driven", oat: 2, drive: true, morph: lowBandHigh},
  {name: "PZ SVF", short: "lowpass · PZ SVF", oat: 2, drive: true, morph: lowBandHigh},
  {name: "comb +", short: "comb · +", oat: 0, drive: false, morph: Some("damping in the loop")},
  {name: "comb −", short: "comb · −", oat: 0, drive: false, morph: Some("damping in the loop")},
  {name: "flanger", short: "flanger", oat: 0, drive: false, morph: Some("notched › delayed only")},
  {name: "flanger +", short: "flanger · +", oat: 0, drive: false, morph: Some("notched › delayed only")},
  {name: "flanger −", short: "flanger · −", oat: 0, drive: false, morph: Some("notched › delayed only")},
  {name: "phaser", short: "phaser", oat: 13, drive: false, morph: Some("stage spread")},
  {name: "phaser +", short: "phaser · +", oat: 13, drive: false, morph: Some("stage spread")},
  {name: "phaser −", short: "phaser · −", oat: 13, drive: false, morph: Some("stage spread")},
  {name: "formant I", short: "formant · I", oat: 9, drive: false, morph: vowels},
  {name: "formant II", short: "formant · II", oat: 9, drive: false, morph: vowels},
  {name: "formant III", short: "formant · III", oat: 9, drive: false, morph: vowels},
  {name: "low EQ", short: "shelf · low", oat: 0, drive: false, morph: Some("boost › cut")},
  {name: "band EQ", short: "peak · bell", oat: 0, drive: false, morph: Some("boost › cut")},
  {name: "high EQ", short: "shelf · high", oat: 0, drive: false, morph: Some("boost › cut")},
  {name: "ring mod", short: "ring mod", oat: 0, drive: false, morph: Some("sine › square carrier")},
  {name: "sample & hold", short: "sample & hold", oat: 0, drive: false, morph: Some("smoothing")},
  {name: "diffusor", short: "diffusor", oat: 0, drive: false, morph: Some("wet › dry")},
  {name: "reverb", short: "reverb", oat: 0, drive: false, morph: Some("wet › dry")},
]

// Every type, Oatmeal's first.
let types = Array.concat(
  oatmeal->Array.mapWithIndex((name, t) => {
    name,
    short: oatmealShort->Array.getUnsafe(t),
    oat: t,
    drive: false,
    morph: None,
  }),
  porridge,
)

let porridgeNames = porridge->Array.map(i => i.name)
let porridgeShort = porridge->Array.map(i => i.short)

let all = types->Array.map(i => i.name)
let allShort = types->Array.map(i => i.short)

let firstPorridge = Array.length(oatmeal)

// The cutoff knob's law (0..1 to Hz): cubic, up to 11 kHz for Oatmeal's types and 20 kHz for
// Porridge's (zero-delay-feedback) ones.
let cutoffRange = filterType => filterType >= firstPorridge ? 19980. : 10980.
let cutoffHz = (~filterType, c: float) => c * c * c * cutoffRange(filterType) + 20.
let cutoffOfHz = (~filterType, hz: float) =>
  Math.cbrt(Math.max(0., Math.min(1., (hz - 20.) / cutoffRange(filterType))))

// The closest type Oatmeal has, for an export.
let oatmealType = t => types[t]->Option.mapOr(0, i => i.oat)

// The index of a type by its long name (which must exist).
let index = name =>
  switch all->Array.findIndex(n => n == name) {
  | -1 => JsError.panic("no filter type " ++ name)
  | i => i
  }

let hasDrive = t => types[t]->Option.mapOr(false, i => i.drive)

let morphText = t => types[t]->Option.flatMap(i => i.morph)

//==============================================================================
// the menu, by sound

// A character of a family: a type, or several that differ in one way (slope, polarity, stages,
// how wide), each picked by a chip. Oatmeal's are classic. A hidden one is the same sound as
// one the menu offers (the perceptual study measured them within a fraction of a dB): it still
// loads, and shows in its family while it is set.
type character = {
  label: string,
  // the type the row picks, and its variants' (none: just the one)
  value: int,
  variants: array<(string, int)>,
  classic: bool,
  hidden: bool,
}

let one = (~classic=false, ~hidden=false, label, value) => {label, value, variants: [], classic, hidden}
// (the row picks `pick`, or its first variant)
let some = (~classic=false, ~pick=?, label, variants) => {
  label,
  value: pick->Option.getOr(variants->Array.getUnsafe(0)->Pair.second),
  variants,
  classic,
  hidden: false,
}
let classic = (~pick=?, label, variants) => some(~classic=true, ~pick?, label, variants)

// The families, in the menu's order; each row picks its first character's type.
let families = [
  (
    "lowpass",
    [
      one("SVF 12 dB", 16),
      one("ladder 24 dB", 17),
      one("diode ladder", 18),
      one("acid ladder", 37),
      some("analog (MG)", [("6", 32), ("12", 33), ("18", 34)]),
      one("analog, dirty", 36),
      some("driven", [("clean", 40), ("French", 38), ("PZ", 41)]),
      classic(~pick=3, "Oatmeal", [("1P", 1), ("2P", 2), ("4P", 3)]),
      classic(~pick=12, "Oatmeal, driven", [("2P", 11), ("4P", 12)]),
      // (the SVF at morph 0; the ladder; the French)
      one(~hidden=true, "Sallen-Key", 19),
      one(~hidden=true, "analog (MG) 24", 35),
      one(~hidden=true, "driven German", 39),
    ],
  ),
  ("highpass", [classic(~pick=5, "Oatmeal", [("1P", 4), ("2P", 5), ("4P", 6)])]),
  (
    "bandpass",
    [
      one("24 dB", 23),
      classic("Oatmeal", [("wide", 7), ("narrow", 8), ("4P", 9)]),
      // (Oatmeal's 2P narrow)
      one(~hidden=true, "12 dB", 22),
    ],
  ),
  (
    "notch",
    [
      one("24 dB", 27),
      one(~classic=true, "Oatmeal 2P", 10),
      // (Oatmeal's 2P notch)
      one(~hidden=true, "12 dB", 26),
    ],
  ),
  ("peak", [some("peak", [("12 dB", 24), ("24 dB", 25)]), one("bell, boost › cut", 54)]),
  ("shelf", [one("low, boost › cut", 53), one("high, boost › cut", 55)]),
  (
    "morph",
    [
      some("low › band › high", [("12 dB", 16), ("24 dB", 28)]),
      one("low › notch › high", 29),
      one("band › peak › band", 30),
      one("notch › peak › notch", 31),
    ],
  ),
  (
    "comb, flanger",
    [
      one("comb", 20),
      some("flanger", [("0", 44), ("+", 45), ("−", 46)]),
      // (the comb at either end of its morph)
      one(~hidden=true, "comb +", 42),
      one(~hidden=true, "comb −", 43),
    ],
  ),
  ("phaser", [some("phaser", [("4", 47), ("8 +", 48), ("8 −", 49)]), classic(~pick=14, "Oatmeal", [("4", 13), ("12", 14), ("36", 15)])]),
  ("formant", [one("vowels", 21), one("vowels I: two formants", 50), one("vowels II: female", 51), one("vowels III: talk box", 52)]),
  ("effects", [one("ring mod", 56), one("sample & hold", 57), one("diffusor", 58), one("reverb", 59)]),
]

// The type a character's row picks, and all its types.
let pick = c => c.value
let typesOf = c => c.variants == [] ? [c.value] : c.variants->Array.map(Pair.second)
