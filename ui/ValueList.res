// The value lists that list parameters show: a list's names where Porridge words Oatmeal's its
// own way, its compact names for the narrow value fields, the values Porridge adds after
// Oatmeal's (and what an Oatmeal export makes of them), and its menu's order. Icons draws each
// list's icons (Icons.ofList).
//
// A parameter's definition names its list (ParamDefs.t.list), and a rack copy of a parameter
// (PorridgeParams' Like) keeps its first's, so nothing here goes by parameter id but ofOatmeal.

type t =
  // the oscillators' waveforms (O1_Waveform, O2_Waveform): Oatmeal's, then the HQ ones
  | Waveform
  // LFO 1 and 2's shapes
  | LfoShape
  // the voice filter's types (Filter): Oatmeal's, then Porridge's (FilterTypes)
  | FilterType
  // filter 2's: the same, except that the first follows filter 1
  | Filter2Type
  // the rack filter's (Ff_Type, a parameter of Porridge's): every type from the start, each
  // shown by its full name
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

type menu =
  // every value in order
  | Plain
  // every value in order, with the heading where a group starts above it (but the first)
  | Headed(int => option<string>)
  // in an order of its own, with the heading above the first of each group (values left out
  // aren't offered, but still show when set)
  | Ordered(array<(int, option<string>)>)

type info = {
  // the names of Oatmeal's values, where Porridge has its own (None: Oatmeal's)
  names: option<array<string>>,
  // compact names of Oatmeal's values for the narrow value fields (None: the names)
  short: option<array<string>>,
  added: option<added>,
  menu: menu,
}

// Filter 2's first value follows filter 1 instead of being off.
let asFilter2 = (names, first) => [first, ...names->Array.slice(~start=1)]

let filterAdded = {
  names: FilterTypes.porridgeNames,
  short: FilterTypes.porridgeShort,
  toOatmeal: k => FilterTypes.oatmealType(FilterTypes.firstPorridge + k),
  exportNote: "Porridge's filter types (exported as the nearest Oatmeal type)",
}

let info = list =>
  switch list {
  | Waveform => {
      names: None,
      short: None,
      added: Some({
        names: ["Saw HQ", "Pulse HQ", "Triangle HQ"],
        short: ["Saw HQ", "Pulse HQ", "Triangle HQ"],
        // (saw, pulse, triangle)
        toOatmeal: k => k + 1,
        exportNote: "the HQ waveforms (exported as the plain ones)",
      }),
      menu: Plain,
    }
  | LfoShape => {names: None, short: None, added: None, menu: Plain}
  | FilterType => {
      names: Some(FilterTypes.oatmeal),
      short: Some(FilterTypes.oatmealShort),
      added: Some(filterAdded),
      menu: Headed(FilterTypes.heading),
    }
  | Filter2Type => {
      names: Some(FilterTypes.oatmeal->asFilter2("same as filter 1")),
      short: Some(FilterTypes.oatmealShort->asFilter2("as filter 1")),
      added: Some(filterAdded),
      menu: Headed(FilterTypes.heading),
    }
  | FxFilterType => {names: None, short: None, added: None, menu: Headed(FilterTypes.heading)}
  | FilterDouble => {names: None, short: None, added: None, menu: Plain}
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
      // (off, Oatmeal's first value, is the effect's light on the FX page)
      menu: Ordered(DistTypes.order->Array.filter(((v, _)) => v != 0)),
    }
  | DistMode => {
      names: None,
      short: Some(["whole sound", "per-voice, post-filter", "per-voice, pre-filter", "double"]),
      added: None,
      menu: Plain,
    }
  | VoiceMode => {names: None, short: Some(["mono", "poly", "mono legato"]), added: None, menu: Plain}
  | TouchMode => {names: None, short: Some(["ignore", "channel", "poly"]), added: None, menu: Plain}
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
    }
  | GlideMode => {
      names: None,
      short: Some(["P", "P·o", "P/o", "P·(o+1/o)", "P·(1+o)", "P·(1+1/o)", "P·(1+o+1/o)"]),
      added: None,
      menu: Plain,
    }
  | ArpMode => {
      names: None,
      short: Some(["off", "pattern", "global subseq", "chord pattern", "chord", "transp. chords"]),
      added: None,
      menu: Plain,
    }
  | DelayReverse => {names: None, short: Some(["normal", "rev. out", "rev. fb"]), added: None, menu: Plain}
  // (off is the effect's light, as for the distortion)
  | ChorusMode => {names: None, short: None, added: None, menu: Ordered([1, 2, 3, 4]->Array.map(v => (v, None)))}
  }

// The list each of Oatmeal's list parameters shows, if it's one of these (Porridge's parameters
// name theirs: PorridgeParams).
let ofOatmeal = id =>
  switch id {
  | "O1_Waveform" | "O2_Waveform" => Some(Waveform)
  | "LFO_1_Shape" | "LFO_2_Shape" => Some(LfoShape)
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

// The menu of a list of `count` values: each value in the order it shows them, with the heading
// above it where a group starts.
let menu = (list: option<t>, count) =>
  switch list->Option.mapOr(Plain, l => info(l).menu) {
  | Plain => Array.fromInitializer(~length=count, v => (v, None))
  | Headed(heading) => Array.fromInitializer(~length=count, v => (v, v > 0 ? heading(v) : None))
  | Ordered(order) => order->Array.filter(((v, _)) => v < count)
  }
