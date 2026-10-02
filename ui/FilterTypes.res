// The filter types: Oatmeal's 16, then Porridge's (long names for menus and the status bar,
// compact names for the narrow value fields). The voice filters (Filter, Filter2) and the
// rack's filter (Ff_Type) share the list; dsp/Filter.cmajor runs them.
//
// Values are append only (presets and hosts keep the number).

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

// The type menu's groups, in the order of their first types; a heading starts each.
type group = Oatmeal | ZeroDelay | Normal | Multi | Analog | Combs | Vowels | Misc

let groupTitle = group =>
  switch group {
  | Oatmeal => "Oatmeal"
  | ZeroDelay => "zero-delay feedback"
  | Normal => "normal"
  | Multi => "multi (morph)"
  | Analog => "analog"
  | Combs => "effects: comb, flanger, phaser"
  | Vowels => "effects: vowels"
  | Misc => "effects: EQ, ring mod, S&H, space"
  }

type info = {
  name: string,
  short: string,
  // the nearest of Oatmeal's types, for an export (one of Oatmeal's is itself)
  oat: int,
  group: group,
  // whether the drive (F_Drive, Ff_Drive) drives it: the analog types
  drive: bool,
  // what the morph knob (F_Morph, Ff_Morph) does for it, if anything
  morph: option<string>,
}

let lowBandHigh = Some("lowpass › bandpass › highpass")
let vowels = Some("vowel A › E › I › O › U")

// Porridge's types, from 16 on.
let porridge = [
  {name: "SVF LP > BP > HP", short: "SVF morph", oat: 2, group: ZeroDelay, drive: false, morph: lowBandHigh},
  {name: "ladder", short: "ladder", oat: 3, group: ZeroDelay, drive: false, morph: None},
  {name: "diode ladder", short: "diode", oat: 3, group: ZeroDelay, drive: false, morph: None},
  {name: "Sallen-Key", short: "Sallen-Key", oat: 2, group: ZeroDelay, drive: false, morph: None},
  {name: "comb", short: "comb", oat: 0, group: ZeroDelay, drive: false, morph: Some("feedback + › none › −")},
  {name: "formant", short: "formant", oat: 9, group: ZeroDelay, drive: false, morph: vowels},
  {name: "bandpass 12 dB", short: "BP 12", oat: 8, group: Normal, drive: false, morph: None},
  {name: "bandpass 24 dB", short: "BP 24", oat: 9, group: Normal, drive: false, morph: None},
  {name: "peak 12 dB", short: "peak 12", oat: 8, group: Normal, drive: false, morph: None},
  {name: "peak 24 dB", short: "peak 24", oat: 9, group: Normal, drive: false, morph: None},
  {name: "notch 12 dB", short: "notch 12", oat: 10, group: Normal, drive: false, morph: None},
  {name: "notch 24 dB", short: "notch 24", oat: 10, group: Normal, drive: false, morph: None},
  {name: "L/B/H 24 (morph)", short: "L/B/H 24", oat: 3, group: Multi, drive: false, morph: lowBandHigh},
  {name: "L/N/H (morph)", short: "L/N/H", oat: 10, group: Multi, drive: false, morph: Some("lowpass › notch › highpass")},
  {name: "B/P/B (morph)", short: "B/P/B", oat: 8, group: Multi, drive: false, morph: Some("bandpass › peak › bandpass")},
  {name: "N/P/N (morph)", short: "N/P/N", oat: 10, group: Multi, drive: false, morph: Some("notch › peak › notch")},
  {name: "MG low 6", short: "MG 6", oat: 1, group: Analog, drive: true, morph: None},
  {name: "MG low 12", short: "MG 12", oat: 2, group: Analog, drive: true, morph: None},
  {name: "MG low 18", short: "MG 18", oat: 3, group: Analog, drive: true, morph: None},
  {name: "MG low 24", short: "MG 24", oat: 3, group: Analog, drive: true, morph: None},
  {name: "MG dirty", short: "MG dirty", oat: 12, group: Analog, drive: true, morph: None},
  {name: "acid ladder", short: "acid", oat: 12, group: Analog, drive: true, morph: Some("resonance squash")},
  {name: "French LP", short: "French LP", oat: 11, group: Analog, drive: true, morph: lowBandHigh},
  {name: "German LP", short: "German LP", oat: 11, group: Analog, drive: true, morph: None},
  {name: "clean drive", short: "clean drive", oat: 2, group: Analog, drive: true, morph: lowBandHigh},
  {name: "PZ SVF", short: "PZ SVF", oat: 2, group: Analog, drive: true, morph: lowBandHigh},
  {name: "comb +", short: "comb +", oat: 0, group: Combs, drive: false, morph: Some("damping in the loop")},
  {name: "comb −", short: "comb −", oat: 0, group: Combs, drive: false, morph: Some("damping in the loop")},
  {name: "flanger", short: "flanger", oat: 0, group: Combs, drive: false, morph: Some("notched › delayed only")},
  {name: "flanger +", short: "flanger +", oat: 0, group: Combs, drive: false, morph: Some("notched › delayed only")},
  {name: "flanger −", short: "flanger −", oat: 0, group: Combs, drive: false, morph: Some("notched › delayed only")},
  {name: "phaser", short: "phaser", oat: 13, group: Combs, drive: false, morph: Some("stage spread")},
  {name: "phaser +", short: "phaser +", oat: 13, group: Combs, drive: false, morph: Some("stage spread")},
  {name: "phaser −", short: "phaser −", oat: 13, group: Combs, drive: false, morph: Some("stage spread")},
  {name: "formant I", short: "formant I", oat: 9, group: Vowels, drive: false, morph: vowels},
  {name: "formant II", short: "formant II", oat: 9, group: Vowels, drive: false, morph: vowels},
  {name: "formant III", short: "formant III", oat: 9, group: Vowels, drive: false, morph: vowels},
  {name: "low EQ", short: "low EQ", oat: 0, group: Misc, drive: false, morph: Some("boost › cut")},
  {name: "band EQ", short: "band EQ", oat: 0, group: Misc, drive: false, morph: Some("boost › cut")},
  {name: "high EQ", short: "high EQ", oat: 0, group: Misc, drive: false, morph: Some("boost › cut")},
  {name: "ring mod", short: "ring mod", oat: 0, group: Misc, drive: false, morph: Some("sine › square carrier")},
  {name: "sample & hold", short: "S&H", oat: 0, group: Misc, drive: false, morph: Some("smoothing")},
  {name: "diffusor", short: "diffusor", oat: 0, group: Misc, drive: false, morph: Some("wet › dry")},
  {name: "reverb", short: "reverb", oat: 0, group: Misc, drive: false, morph: Some("wet › dry")},
]

// Every type, Oatmeal's first.
let types = Array.concat(
  oatmeal->Array.mapWithIndex((name, t) => {
    name,
    short: oatmealShort->Array.getUnsafe(t),
    oat: t,
    group: Oatmeal,
    drive: false,
    morph: None,
  }),
  porridge,
)

let porridgeNames = porridge->Array.map(i => i.name)
let porridgeShort = porridge->Array.map(i => i.short)

let all = types->Array.map(i => i.name)

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

// The rack filter's type parameters (Ff_Type, Ff2_Type ...).
let isFxType = id => String.startsWith(id, "Ff") && String.endsWith(id, "_Type")

// The heading the type menu shows above type t, where a group starts.
let heading = t =>
  switch (types[t], types[t - 1]) {
  | (Some(i), Some(before)) if i.group == before.group => None
  | (Some(i), _) => Some(groupTitle(i.group))
  | (None, _) => None
  }
