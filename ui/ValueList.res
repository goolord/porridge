// The value lists that list parameters show: a list's names where Porridge words Oatmeal's its
// own way, its compact names for the narrow value fields, the values Porridge adds after
// Oatmeal's (and what an Oatmeal export makes of them), and its menu. Icons draws each list's
// icons (Icons.ofList).
//
// A menu goes by sound, not by value: it can group values into families (the filter's
// lowpasses), give a row's variants as chips (12 dB, 24 dB), and keep rare values behind
// "more". It only ever maps what is picked onto the list's values, which stay as they are:
// values are append only, and presets and hosts keep the number.
//
// A parameter's definition names its list (ParamDefs.t.list), and a rack copy of a parameter
// (PorridgeParams' Like) keeps its first's, so nothing here goes by parameter id but ofOatmeal.

type t =
  // the oscillators' waveforms (O1_Waveform, O2_Waveform): Oatmeal's, then the HQ ones
  | Waveform
  // LFO 1 and 2's shapes
  | LfoShape
  // LFO 3's shapes (LFO_3_Shape, a parameter of Porridge's)
  | Lfo3Shape
  // LFO 1 and 2's rate units, the delay's and the arpeggiator's
  | LfoUnit
  | DelayUnit
  | ArpUnit
  // the voice filter's types (Filter): Oatmeal's, then Porridge's (FilterTypes)
  | FilterType
  // filter 2's: the same, except that the first follows filter 1
  | Filter2Type
  // the rack filter's (Ff_Type, a parameter of Porridge's): every type from the start
  | FxFilterType
  // the filter doubling (F_Double)
  | FilterDouble
  // the distortion's types (Sat_Type): Oatmeal's, then the custom shape and the models (DistTypes)
  | DistType
  // where the distortion is (Sat_Mode)
  | DistMode
  | VoiceMode
  | TouchMode
  // the oscillator mix: Oatmeal's, then Porridge's PM, ring and AM
  | OscMix
  | GlideMode
  | ArpMode
  // the delay's reverse switches (D_ReverseL, D_ReverseR)
  | DelayReverse
  | ChorusMode

// Values Porridge adds after Oatmeal's last one. Oatmeal programs never hold them; an Oatmeal
// export makes each the closest one Oatmeal has, and its warning says what that loses.
type added = {
  names: array<string>,
  short: array<string>,
  // the Oatmeal value for the k-th added one (0 the first)
  toOatmeal: int => int,
  exportNote: string,
}

// A row of a menu: a value under a heading or a rule, named its own way (else by its name),
// with a badge, or behind "more"; or a row for several values, with their variants as chips at
// its end, or a family whose own menu opens beside it. A row with variants or a family's picks
// its value when it is clicked itself.
type rec entry = {
  value: int,
  label?: string,
  heading?: string,
  rule?: bool,
  badge?: string,
  more?: bool,
  variants?: array<(string, int)>,
  sub?: array<entry>,
}

type menu =
  // every value in order
  | Plain
  // rows of their own, given the current value (values left out aren't offered, but still
  // show when set; a menu may show one where it belongs while it is set)
  | Entries(int => array<entry>)

type info = {
  // the names of Oatmeal's values, where Porridge has its own (None: Oatmeal's)
  names: option<array<string>>,
  // compact names of Oatmeal's values for the narrow value fields (None: the names)
  short: option<array<string>>,
  added: option<added>,
  menu: menu,
  // what a value is, for the menu's hover texts (None: its name, where its row says otherwise)
  about: option<int => string>,
}

// Rows in an order of their own, with a heading above the first of each group.
let ordered = (rows: array<(int, option<string>)>) => Entries(_ => rows->Array.map(((value, heading)) => {value, ?heading}))

// Every value a menu offers, in its order, each once: a row's, its chips' and its family's.
let offered = entries => {
  let seen = Set.make()
  let rec values = e => {
    let others = switch (e.sub, e.variants) {
    | (Some(sub), _) => sub->Array.flatMap(values)
    | (None, Some(chips)) => chips->Array.map(Pair.second)
    | (None, None) => []
    }
    others->Array.includes(e.value) ? others : [e.value, ...others]
  }
  entries->Array.flatMap(values)->Array.filter(v =>
    if seen->Set.has(v) {
      false
    } else {
      seen->Set.add(v)
      true
    }
  )
}

// Filter 2's first value follows filter 1 instead of being off.
let asFilter2 = (names, first) => [first, ...names->Array.slice(~start=1)]

let filterAdded = {
  names: FilterTypes.porridgeNames,
  short: FilterTypes.porridgeShort,
  toOatmeal: k => FilterTypes.oatmealType(FilterTypes.firstPorridge + k),
  exportNote: "Porridge's filter types (exported as the nearest Oatmeal type)",
}

// The filter's menu: off (or filter 2's "same as filter 1"), then the families (FilterTypes),
// each opening its characters beside it. A hidden character shows only while it is set.
let filterMenu = current => [
  {value: 0},
  ...FilterTypes.families->Array.map(((name, characters: array<FilterTypes.character>)) => {
    value: characters->Array.getUnsafe(0)->FilterTypes.pick,
    label: name,
    sub: characters
    ->Array.filter(c => !c.hidden || FilterTypes.typesOf(c)->Array.includes(current))
    ->Array.map(c => {
      value: c.value,
      label: c.label,
      badge: ?(c.classic ? Some("classic") : None),
      variants: ?(c.variants == [] ? None : Some(c.variants)),
    }),
  }),
]

// The distortion's menu: its characters (DistTypes), the custom shape below them. (Off, the
// list's first value, is the effect's light on the FX page.)
let distMenu = _ =>
  DistTypes.characters->Array.map(c => {
    value: c.value,
    label: c.label,
    rule: c.value == DistTypes.custom,
    variants: ?(c.variants == [] ? None : Some(c.variants)),
  })

// The rate units (LFO_n_Unit, D_Unit, Arp_Unit) all run free (ms, 10 ms, sec), then by the
// beat: quintuplets (4/5), triplets (2/3) and straight, for each note length. The menus put
// the straight ones first and the rest behind "more", as rarely used (the usage census: three
// units cover about 90 % of LFOs, 16ths alone 85 % of arpeggios), except the delay's triplets
// (2/3 8ths: 13 % of delays).
let freeUnits = [0, 1, 2]
let unitMenu = (~lengths, ~freeFirst, ~tripletsShown) => {
  // the k-th note length's quintuplet unit, then its triplet and straight ones
  let quintuplets = Array.fromInitializer(~length=lengths, k => 3 + 3 * k)
  let triplets = quintuplets->Array.map(q => q + 1)
  let straight = quintuplets->Array.map(q => q + 2)
  let group = (values, ~heading=?, ~more=false) =>
    values->Array.mapWithIndex((value, i) => {value, heading: ?(i == 0 ? heading : None), more})
  let free = group(freeUnits, ~heading=?(freeFirst ? None : Some("not synced")), ~more=!freeFirst)
  Entries(_ => [
    ...freeFirst ? free : [],
    ...straight->Array.mapWithIndex((value, i) => {value, rule: freeFirst && i == 0}),
    ...group(triplets, ~heading="triplets", ~more=!tripletsShown),
    ...group(quintuplets, ~heading="quintuplets", ~more=true),
    ...freeFirst ? [] : free,
  ])
}

// The glide modes' plain names: how long a glide takes, from the glide time (P) and the
// interval in octaves (o).
let glideNames = [
  "constant time",
  "by interval",
  "by inverse interval",
  "time × (o + 1/o)",
  "time × (1 + o)",
  "time × (1 + 1/o)",
  "time × (1 + o + 1/o)",
]
let glideAbout = [
  "Every glide takes the glide time, however far it goes",
  "A glide takes the glide time for each octave it goes: wider leaps take longer (Oatmeal's P × octaves)",
  "Wider leaps glide faster: the glide time divided by the octaves (Oatmeal's P / octaves)",
  "Slowest for small and large leaps, quickest for an octave (Oatmeal's P × (o + 1/o))",
  "The glide time, and as much again for each octave (Oatmeal's P × (1 + o))",
  "The glide time, and more the smaller the leap (Oatmeal's P × (1 + 1/o))",
  "The glide time, more for small leaps and more for large ones (Oatmeal's P × (1 + o + 1/o))",
]

let info = list =>
  switch list {
  // The HQ (anti-aliased) saw, pulse and triangle are the waves; Oatmeal's alias, and are there
  // for its programs, which keep them (and an Oatmeal export makes the HQ ones Oatmeal's).
  | Waveform => {
      names: Some(["Sine", "Oatmeal saw", "Oatmeal pulse", "Oatmeal triangle", "User", "User PWM"]),
      short: Some(["Sine", "Oat saw", "Oat pulse", "Oat tri", "User", "User PWM"]),
      added: Some({
        names: ["Saw", "Pulse", "Triangle"],
        short: ["Saw", "Pulse", "Triangle"],
        // (saw, pulse, triangle)
        toOatmeal: k => k + 1,
        exportNote: "the HQ waveforms (exported as Oatmeal's aliasing ones)",
      }),
      menu: ordered([
        (0, None),
        (6, None),
        (7, None),
        (8, None),
        (4, None),
        (5, None),
        (1, Some("Oatmeal (aliasing)")),
        (2, None),
        (3, None),
      ]),
      about: None,
    }
  // (the random ones' fields say which, beside their icons)
  | LfoShape => {
      names: None,
      short: Some(["Sine", "Saw", "Square", "Triangle", "Smooth", "Stepping", "User"]),
      added: None,
      menu: Plain,
      about: None,
    }
  // (in LFO 1 and 2's order: PorridgeParams.lfo3Shapes)
  | Lfo3Shape => {
      names: None,
      short: Some(["Sine", "Triangle", "Saw", "Saw ↓", "Square", "Stepping", "Smooth"]),
      added: None,
      menu: ordered([0, 2, 3, 4, 1, 6, 5]->Array.map(v => (v, None))),
      about: None,
    }
  | LfoUnit => {
      names: None,
      short: None,
      added: None,
      menu: unitMenu(~lengths=5, ~freeFirst=true, ~tripletsShown=false),
      about: None,
    }
  | DelayUnit => {
      names: None,
      short: None,
      added: None,
      menu: unitMenu(~lengths=4, ~freeFirst=false, ~tripletsShown=true),
      about: None,
    }
  | ArpUnit => {
      names: None,
      short: None,
      added: None,
      menu: unitMenu(~lengths=5, ~freeFirst=false, ~tripletsShown=false),
      about: None,
    }
  | FilterType => {
      names: Some(FilterTypes.oatmeal),
      short: Some(FilterTypes.oatmealShort),
      added: Some(filterAdded),
      menu: Entries(filterMenu),
      about: None,
    }
  | Filter2Type => {
      names: Some(FilterTypes.oatmeal->asFilter2("same as filter 1")),
      short: Some(FilterTypes.oatmealShort->asFilter2("as filter 1")),
      added: Some(filterAdded),
      menu: Entries(filterMenu),
      about: None,
    }
  | FxFilterType => {names: None, short: Some(FilterTypes.allShort), added: None, menu: Entries(filterMenu), about: None}
  | FilterDouble => {names: None, short: None, added: None, menu: Plain, about: None}
  | DistType => {
      names: None,
      short: None,
      added: Some({
        names: DistTypes.porridgeNames,
        short: DistTypes.porridgeShort,
        // (soft clip)
        toOatmeal: _ => 2,
        exportNote: "Porridge's distortion types (exported as soft clipping)",
      }),
      menu: Entries(distMenu),
      about: Some(DistTypes.describe),
    }
  | DistMode => {
      names: None,
      short: Some(["whole sound", "per-voice, post-filter", "per-voice, pre-filter", "double"]),
      added: None,
      menu: Plain,
      about: None,
    }
  | VoiceMode => {names: None, short: Some(["mono", "poly", "mono legato"]), added: None, menu: Plain, about: None}
  | TouchMode => {names: None, short: Some(["ignore", "channel", "poly"]), added: None, menu: Plain, about: None}
  | OscMix => {
      names: None,
      short: Some(["normal", "hardsync", "FM 1 > 2"]),
      added: Some({
        names: ["PM 2 > 1", "PM 1 feedback", "ring 1 × 2", "AM 2 > 1"],
        short: ["PM 2 > 1", "PM 1 fb", "ring 1×2", "AM 2 > 1"],
        // (normal)
        toOatmeal: _ => 0,
        exportNote: "the PM, ring and AM osc mix (exported as normal)",
      }),
      menu: Plain,
      about: None,
    }
  // (constant time and by interval are 96 % of the glides in the usage census)
  | GlideMode => {
      names: Some(glideNames),
      short: Some(["constant", "by interval", "inverse", "o + 1/o", "1 + o", "1 + 1/o", "1 + o + 1/o"]),
      added: None,
      menu: Entries(_ => glideNames->Array.mapWithIndex((_, value) => {value, more: value >= 2})),
      about: Some(v => glideAbout[v]->Option.getOr("")),
    }
  | ArpMode => {
      names: None,
      short: Some(["off", "pattern", "global subseq", "chord pattern", "chord", "transp. chords"]),
      added: None,
      menu: Plain,
      about: None,
    }
  | DelayReverse => {names: None, short: Some(["normal", "rev. out", "rev. fb"]), added: None, menu: Plain, about: None}
  // (off is the effect's light, as for the distortion)
  | ChorusMode => {names: None, short: None, added: None, menu: ordered([1, 2, 3, 4]->Array.map(v => (v, None))), about: None}
  }

// The list each of Oatmeal's list parameters shows, if it's one of these (Porridge's parameters
// name theirs: PorridgeParams).
let ofOatmeal = id =>
  switch id {
  | "O1_Waveform" | "O2_Waveform" => Some(Waveform)
  | "LFO_1_Shape" | "LFO_2_Shape" => Some(LfoShape)
  | "LFO_1_Unit" | "LFO_2_Unit" => Some(LfoUnit)
  | "D_Unit" => Some(DelayUnit)
  | "Arp_Unit" => Some(ArpUnit)
  | "Filter" => Some(FilterType)
  | "Filter2" => Some(Filter2Type)
  | "F_Double" => Some(FilterDouble)
  | "Sat_Type" => Some(DistType)
  | "Sat_Mode" => Some(DistMode)
  | "PolyMode" => Some(VoiceMode)
  | "AftertouchMode" => Some(TouchMode)
  | "OscMix" => Some(OscMix)
  | "GlideMode" => Some(GlideMode)
  | "Arp_Mode" => Some(ArpMode)
  | "D_ReverseL" | "D_ReverseR" => Some(DelayReverse)
  | "C_Mode" => Some(ChorusMode)
  | _ => None
  }

// The menu of a list of `count` values while it is at `current`: its rows in order.
let menu = (list: option<t>, count, ~current) =>
  switch list->Option.mapOr(Plain, l => info(l).menu) {
  | Plain => Array.fromInitializer(~length=count, value => {value: value})
  | Entries(rows) => rows(current)->Array.filter(e => e.value < count)
  }
