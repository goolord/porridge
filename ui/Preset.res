// Porridge's own preset format. A preset is a JSON document:
//
//   {
//     "porridge": "preset", "version": 1,
//     "name": "Warm pad", "author": "", "category": "pad", "tags": ["slow"], "description": "",
//     "params": { "Cutoff": 0.42, "O1_Waveform": 1, ... },   // endpoint id -> internal value
//     "modulations": [ { "source": "lfo1", "target": "Cutoff", "amount": 0.25, "via": "modWheel",
//                        "hold": "latch", "slew": 0.3, "curve": -0.5, "steps": 13 } ],   // (options only when set)
//     "macros": ["brightness", "", "", ""],                    // macro knob names
//     "tables": { "wave1": "<base64 float32 LE>", ... },      // only tables that differ from Init
//     "tuning": { "scl": "<.scl text>", "kbm": "<.kbm text>" }, // microtuning, if any
//     "impulses": [ { "name": "hall.wav", "rate": 48000, "left": "<base64 float32 LE>",
//                     "right": "..." }, null, null ]     // the convolvers' files and the noise's sample
//                                                            // (Impulse.res), if any
//   }
//
// The modulation matrix's slot parameters (Mod1_Source ...) are written as "modulations",
// by source and target key (ModMatrix.res), not as parameters.
//
// A bank is { "porridge": "bank", "version": 1, "name": ..., "presets": [preset, ...] }.
//
// Rules that keep the format open for later features:
//  - a missing parameter or table has its default (Init) value, so new parameters are added
//    with neutral defaults and old files keep sounding the same;
//  - unknown parameters and tables are ignored;
//  - "version" is raised only for changes old readers can't skip over.
//
// Oatmeal files (.omp, .omb, .fxp, .fxb, .dat) are imported into this format, and presets can be
// exported back to Oatmeal for the parameters it has.

open OatmealFormat

let formatVersion = 1
let maxNameLength = 64

type meta = {
  name: string,
  author: string,
  category: string,
  tags: array<string>,
  description: string,
  macroNames: array<string>,
}

type t = {
  meta: meta,
  // every parameter, by endpoint id
  values: Bank.values,
  tables: tables,
  // a Scala scale and keyboard mapping; None plays Oatmeal's tuning
  tuning: option<Scala.source>,
  // each convolver's impulse from a file (Cv_Impulse "file")
  impulses: array<option<Impulse.t>>,
}

let defs = ParamDefs.all
let defsById = ParamDefs.byId
let useDefs = ParamDefs.useDefs

// A program holds every parameter but the performance state (the wheels: PorridgeParams'
// isPerformance), which programs, files, A/B and the random patches leave out: its values from
// a set of parameter values (the view's).
let inProgram = id => !PorridgeParams.isPerformance(id)
let programValues = (values: Bank.values): Bank.values =>
  values->Map.entries->Iterator.toArray->Array.filter(((id, _)) => inProgram(id))->Map.fromArray

let defaultValues = () =>
  Lazy.get(defs)->Array.filter(d => inProgram(d.ParamDefs.id))->Array.map(d => (d.id, d.init))->Map.fromArray

let defaultTables = Lazy.make(() => extractTables(makeDefaultProgram("Init")))

let copyTables = tables => tablesFrom(table => tables->getTable(table)->TypedArray.copy)

let emptyMeta = name => {
  name,
  author: "",
  category: "",
  tags: [],
  description: "",
  macroNames: Array.make(~length=ModMatrix.macros, ""),
}

// Leaves Oatmeal's chorus, delay, reverb and EQ out of the rack where they do nothing: switched
// off, or for the EQ, with every band off. Oatmeal always runs all four, so its programs (and
// Init, which starts from its defaults) would otherwise carry idle effects in the chain. The
// effects' settings stay, for when one is put back in the rack.
let withoutIdleEffects = (values: Bank.values) => {
  let get = id => values->Map.get(id)->Option.getOr(0.)
  let idle = (e: FxRack.effect) =>
    FxRack.isFirst(e) &&
    (!FxRack.isOn(e, get) || e.kind == #eq && FxRack.eqBandTypes(e)->Array.every(id => get(id) == 0.))
  let rack = FxRack.read(get)
  if rack->Array.some(idle) {
    FxRack.values(get, rack->Array.filter(e => !idle(e)))->Array.forEach(((id, x)) => values->Map.set(id, x))
  }
  values
}

// The defaults, with an empty effects rack (what the tools measure against).
let make = name => {
  meta: emptyMeta(name),
  values: withoutIdleEffects(defaultValues()),
  tables: copyTables(Lazy.get(defaultTables)),
  tuning: None,
  impulses: Impulse.none(),
}

// Init, as a new program starts: the defaults, with the HQ saw on both oscillators. (Oatmeal's
// sine stays the waveforms' default: the bank in the plugin's state leaves defaults out, so a
// new default would change the programs stored without one.)
let init = name => {
  let p = make(name)
  ["O1_Waveform", "O2_Waveform"]->Array.forEach(id => p.values->Map.set(id, ParamDefs.choiceValue(id, "Saw")))
  p
}

// A whole bank: presets, then Init programs. The Init programs share one set of values and
// tables (a preset's are never changed in place), which spares making 64 of each at startup.
let fillBank = presets => {
  let init = Lazy.make(() => init("Init"))
  Array.fromInitializer(~length=bankPrograms, i =>
    switch presets[i] {
    | Some(p) => p
    | None => {...Lazy.get(init), meta: emptyMeta(`Init ${Int.toString(i)}`)}
    }
  )
}

let name = p => p.meta.name

let withName = (p, name) => {
  ...p,
  meta: {...p.meta, name: name->String.trim->String.slice(~start=0, ~end=maxNameLength)},
}

// The number a parameter actually holds: float parameters are float32, like the DSP's
// endpoints, and pulse widths are 32-bit fractions. So "0.7" in a file reads back as the
// same value an Oatmeal program holds.
let canonical = (d: ParamDefs.t, x) =>
  switch d.kind {
  | F32 => Math.fround(x)
  | Pw => Math.round(x * OatmealParams.pw32) / OatmealParams.pw32
  | I32 | Filter1 | Filter2 => x
  }

// A value as a loaded program keeps it (ParamDefs' load), or None for a parameter there isn't
// (or one programs don't hold).
let loadValue = (id, x) =>
  inProgram(id) ? Lazy.get(defsById)->Map.get(id)->Option.map(d => canonical(d, d.load(x))) : None

//==============================================================================
// Oatmeal

let fromOatmeal = (bytes: Uint8Array.t) => {
  let values = defaultValues()
  Bank.programValues(bytes)->Map.forEachWithKey((x, id) =>
    loadValue(id, x)->Option.forEach(x => values->Map.set(id, x))
  )
  {
    meta: emptyMeta(getName(bytes)),
    values: withoutIdleEffects(values),
    tables: extractTables(bytes),
    tuning: None,
    impulses: Impulse.none(),
  }
}

let valueOf = (p, id) =>
  p.values->Map.get(id)->Option.getOr(Lazy.get(defsById)->Map.get(id)->Option.mapOr(0., d => d.init))

// The note an Oatmeal export's warning gives for a value list's values that Oatmeal doesn't have.
let listLoss = (list: ValueList.t) => ValueList.info(list).added->Option.map(a => a.exportNote)

// What an Oatmeal export loses when one of Porridge's features has a parameter changed from its
// default: a line of the export's warning, or None where that loses nothing, or where the warning
// tells it otherwise. (A switch, so that a new feature has to say.)
let featureLoss = (feature: PorridgeParams.feature) =>
  switch feature {
  | Modulations | MoreModulations => Some("modulations")
  | Lfo3 => Some("LFO 3 and the wander rate")
  | VoiceLane | ResonatorGain => Some("the voices' own effects (and the FX filter's note tracking)")
  | VoiceExtras =>
    Some("the phaser's, flanger's and lo-fi sampler's note tracking and random starts, the octaver and the modulation steps")
  | Macros => Some("macros")
  | Mpe => Some("MPE settings")
  | Drift => Some("the analog drift")
  | Curves | Decay1Curves => Some("the envelope curves")
  | OscEnvs => Some("the oscillator envelopes")
  | KeyEq => Some("the key EQ")
  | OscNoise => Some("the oscillator noise")
  | OscShape => Some("the oscillators' morph and phase distortion")
  | PairMix => Some("osc 2 heard in PM, ring and AM")
  | LfoExtras => Some("the LFO delay, slew, steps and one-shot")
  | UnisonExtras => Some("the unison extras")
  | FilterDrive => Some("the filter drive")
  // (for the osc mix modes and the filter types Porridge added)
  | PmFeedback => listLoss(OscMix)
  | FilterMorph => listLoss(FilterType)
  // (Oatmeal always plays like Oat mode)
  | OatMode => None
  // the rack: what it holds says what's lost (the effects order, its extra effects)
  | FxOrder | EffectsRack | EqSwitch | RackCopies | RackEffects | Ambience | AirEffect | BodeRatio => None
  // the custom shape and the models' knobs go with the distortion types they're for (the mix,
  // which works on every type, is told apart)
  | CustomShape | DistModels => None
  // (the type says: a density of white noise loses nothing)
  | NoiseType => None
  // (not part of a program)
  | PlayWheels => None
  }

// What an Oatmeal export of this preset loses: the lines of its warning.
let porridgeOnly = p => {
  let lost = []
  let add = line =>
    line->Option.forEach(line =>
      if !(lost->Array.includes(line)) {
        lost->Array.push(line)
      }
    )
  // a feature's parameters are changed from their defaults
  let changed = feature =>
    PorridgeParams.groups->Array.some(((f, specs)) =>
      f == feature &&
        specs->Array.some(spec =>
          switch (p.values->Map.get(spec.id), Lazy.get(defsById)->Map.get(spec.id)) {
          | (Some(x), Some(d)) => x != d.init
          | _ => false
          }
        )
    )
  let feature = f => changed(f) ? add(featureLoss(f)) : ()
  let features = (fs: array<PorridgeParams.feature>) => fs->Array.forEach(feature)
  // Oatmeal's list parameters (of a list, or any) holding a value Porridge added
  let oatmealLists = (~list=?) =>
    Lazy.get(defs)->Array.forEach(d =>
      if d.index < OatmealParams.paramCount && (list == None || d.list == list) {
        switch (p.values->Map.get(d.id), d.list) {
        | (Some(x), Some(l)) if ParamDefs.oatmealValue(d, x) != x => add(listLoss(l))
        | _ => ()
        }
      }
    )
  let rack = FxRack.read(valueOf(p, _))

  // in the warning's order
  features([Modulations, MoreModulations, Lfo3, VoiceLane, ResonatorGain, VoiceExtras, Macros, Mpe, Drift])
  // Oatmeal's chain is chorus, delay, reverb, EQ; effects left out of the rack are exported
  // switched off, so only their order is lost
  let firsts = rack->Array.filter(FxRack.isFirst)
  if firsts != FxRack.firsts->Array.filter(e => FxRack.holds(firsts, e)) {
    add(Some("the effects order"))
  }
  switch rack->Array.filter(e => !FxRack.isFirst(e)) {
  | [] => ()
  | copies => add(Some(`the rack's extra effects (${copies->Array.map(e => FxRack.kindName(e.kind))->Array.join(", ")})`))
  }
  features([Curves, Decay1Curves, OscEnvs, KeyEq, OscShape, OscNoise, PairMix, LfoExtras, UnisonExtras])
  if valueOf(p, "N_Type") != 0. {
    add(Some("the noise types (exported as white noise)"))
  }
  oatmealLists(~list=DistType)
  if p.values->Map.get("Sat_Mix")->Option.mapOr(false, x => x != 1.) {
    add(Some("the distortion mix"))
  }
  oatmealLists(~list=Waveform)
  oatmealLists(~list=OscMix)
  feature(PmFeedback)
  oatmealLists(~list=FilterType)
  oatmealLists(~list=Filter2Type)
  feature(FilterMorph)
  if p.tuning != None {
    add(Some("the microtuning"))
  }
  feature(FilterDrive)
  // (24 bytes with a NUL, in Latin-1)
  if String.length(p.meta.name) > nameLength - 1 || /[^\x00-\xff]/->RegExp.test(p.meta.name) {
    add(Some("the full name"))
  }
  // then any not told above (a feature or a list added later)
  PorridgeParams.groups->Array.forEach(((f, _)) => feature(f))
  oatmealLists()
  lost
}

// Parameters Oatmeal doesn't have are left out, and list values it doesn't have become the
// closest ones it does.
let toOatmeal = p => {
  let bytes = makeDefaultProgram(p.meta.name)
  let values =
    p.values
    ->Map.entries
    ->Iterator.toArray
    ->Array.map(((id, x)) => (id, Lazy.get(defsById)->Map.get(id)->Option.mapOr(x, ParamDefs.oatmealValue(_, x))))
    ->Map.fromArray
  // Oatmeal always runs its four effects: those left out of the rack go switched off, and an EQ
  // that is off (Oatmeal's has no switch) loses its bands
  let rack = FxRack.read(valueOf(p, _))
  FxRack.firsts->Array.forEach(e =>
    if !FxRack.holds(rack, e) || !FxRack.isOn(e, valueOf(p, _)) {
      switch e.kind {
      | #eq => FxRack.eqBandTypes(e)->Array.forEach(id => values->Map.set(id, 0.))
      | _ => values->Map.set(FxRack.switchId(e), 0.)
      }
    }
  )
  values->Map.forEachWithKey((x, id) => Bank.writeValue(bytes, id, x))
  allTables->Array.forEach(table => writeTable(bytes, table, p.tables->getTable(table)))
  bytes
}

//==============================================================================
// JSON

// The shortest decimal that reads back as the same parameter value, so files stay
// readable ("0.3", not "0.30000001192092896").
let shortNumberWith = (canonical, x) =>
  if !Float.isFinite(x) {
    0.
  } else if canonical(x) != x {
    x
  } else {
    let rec go = digits =>
      if digits > 10 {
        x
      } else {
        let y = Float.parseFloat(x->Float.toPrecision(~digits))
        canonical(y) == x ? y : go(digits + 1)
      }
    go(1)
  }

let shortNumber = (d, x) => shortNumberWith(canonical(d, _), x)
let shortFloat = x => shortNumberWith(Math.fround, x)

let sameTable = (a: Float32Array.t, b: Float32Array.t) =>
  TypedArray.length(a) == TypedArray.length(b) &&
    a->TypedArray.everyWithIndex((x, i) =>
      ByteView.bitsOfFloat32(x) == ByteView.bitsOfFloat32(ByteView.getUnsafe(b, i))
    )

let decodeTable = (s, length) => {
  let data = Bank.floatsFromBase64(s)
  TypedArray.length(data) < length ? None : Some(data->TypedArray.slice(~start=0, ~end=length))
}

let str = s => JSON.String(s)
let num = x => JSON.Number(x)

// A target's key in a file: a slot's knob's by what it moves ("Fl_Rate@3"), the others' own.
let targetKey = (get, t, target: ModMatrix.target) =>
  switch target.law {
  | Slot(_, _) => SlotParams.targetParam(get, t)->Option.getOr("none")
  | _ => target.key
  }

// A file's target key as a target, with the program's values (a slot's parameter's is its
// slot's knob while the slot holds its kind).
let targetIndexIn = (values: Bank.values, key) =>
  switch PorridgeParams.parseSlotParam(key) {
  | Some((first, g)) =>
    let get = id => values->Map.get(id)->Option.getOr(0.)
    SlotParams.kindAt(get, g)->Option.mapOr(-1, k =>
      k.params->Array.some(((p, _)) => p == first) ? SlotParams.targetOfParam(key) : -1
    )
  | None => ModMatrix.targetIndex(key)
  }

// ~sparse leaves out the parameters that read back as their default (a missing parameter has
// its default value), which shrinks the bank in the stored state to a fraction of its size
let toJson = (p, ~header=true, ~sparse=false) => {
  let get = id => p.values->Map.get(id)->Option.getOr(0.)
  // a slot's parameters: those of the kind it holds
  let inSlot = id =>
    switch PorridgeParams.parseSlotParam(id) {
    | Some((first, g)) =>
      SlotParams.kindAt(get, g)->Option.mapOr(false, k => k.params->Array.some(((p, _)) => p == first))
    | None => true
    }
  let params = Lazy.get(defs)->Array.filterMap(d =>
    ModMatrix.isSlotParam(d.id) || !inSlot(d.id) || !inProgram(d.id)
      ? None
      : p.values
        ->Map.get(d.id)
        ->Option.map(x => (d.id, shortNumber(d, x)))
        ->Option.filter(((id, x)) => !sparse || loadValue(id, x) != Some(d.init))
        ->Option.map(((id, x)) => (id, num(x)))
  )

  let modulations = ModMatrix.slotNumbers->Array.filterMap(k => {
    let slot = ModMatrix.readSlot(id => p.values->Map.get(id)->Option.getOr(0.), k)
    switch (ModMatrix.sources[slot.source], ModMatrix.targets[slot.target]) {
    | (Some(source), Some(target)) if source.key != "none" && target.key != "none" =>
      let via = switch ModMatrix.sources[slot.via] {
      | Some(via) if via.key != "none" => [("via", str(via.key))]
      | _ => []
      }
      let options = [
        ...(slot.hold ? [("hold", str("latch"))] : []),
        ...(slot.slew != 0. ? [("slew", num(Math.fround(slot.slew)->shortFloat))] : []),
        ...(slot.curve != 0. ? [("curve", num(Math.fround(slot.curve)->shortFloat))] : []),
        ...(slot.steps > 0 ? [("steps", num(Int.toFloat(slot.steps)))] : []),
      ]
      Some(
        JSON.Object(
          Dict.fromArray([
            ("source", str(source.key)),
            ("target", str(targetKey(get, slot.target, target))),
            ("amount", num(Math.fround(slot.amount)->shortFloat)),
            ...via,
            ...options,
          ]),
        ),
      )
    | _ => None
    }
  })

  let tables = allTables->Array.filterMap(table => {
    let data = p.tables->getTable(table)
    sameTable(data, Lazy.get(defaultTables)->getTable(table))
      ? None
      : Some((tableInfo(table).key, str(Bank.floatsToBase64(data))))
  })

  JSON.Object(
    Dict.fromArray([
      ...(header ? [("porridge", str("preset")), ("version", num(Int.toFloat(formatVersion)))] : []),
      ("name", str(p.meta.name)),
      ("author", str(p.meta.author)),
      ("category", str(p.meta.category)),
      ("tags", JSON.Array(p.meta.tags->Array.map(str))),
      ("description", str(p.meta.description)),
      ("params", JSON.Object(Dict.fromArray(params))),
      ("modulations", JSON.Array(modulations)),
      ("macros", JSON.Array(p.meta.macroNames->Array.map(str))),
      ("tables", JSON.Object(Dict.fromArray(tables))),
      ...p.tuning->Option.mapOr([], t => [("tuning", Scala.toJson(t))]),
      ...(Impulse.isEmpty(p.impulses) ? [] : [("impulses", Impulse.listToJson(p.impulses))]),
    ]),
  )
}

let getString = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.String(s)) => s
  | _ => ""
  }

let getNumber = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.Number(x)) => x
  | _ => 0.
  }

// A program from before the slots (October 2026) has its effects' parameters as copies' (D2_Wet,
// Fl3_Rate, and Porridge's own kinds' firsts, Fl_Rate): each effect in a rack or voice slot
// takes its parameters (and its custom shape's points, and the connections to them) into that
// slot ("D_Wet@3"), and keeps its rack value where that is an instance still (the old fourth
// copies are again). Copies in no slot sounded nothing: they go, with their connections.
//
// A kind retired as a whole (the key shifter, which became the frequency shifter's ratio of the
// note: PorridgeParams.mergedInto) loads as the kind it became, its settings read as that kind's
// (PorridgeParams.mergedParams: each parameter, the one it becomes and the factor on its knob,
// which scales the connections' amounts too); the new kind's other parameters keep their
// defaults.
//
// The convolver has one instance now: a program with two keeps the first in the rack (with its
// impulse file, which moves to the first file's place) and leaves the second out, and the warning
// says so. Returns the program's params and modulations as they load, the warnings, and which of
// the old impulse files (0, 1) the convolver keeps, if it moved.
type migrated = {
  params: dict<JSON.t>,
  modulations: array<JSON.t>,
  warnings: array<string>,
  convolverFile: option<int>,
}

let migrateSlots = (name, params: dict<JSON.t>, modulations: array<JSON.t>) => {
  let params = params->Dict.copy
  let modulations = ref(modulations)
  let warnings = []
  let convolverFile = ref(None)
  let number = id =>
    switch params->Dict.get(id) {
    | Some(Number(x)) => Some(x)
    | _ => None
    }
  let setNumber = (id, x) => params->Dict.set(id, JSON.Number(x))
  let idOf = (first, n) => n == 1 ? first : PorridgeParams.copyId(first, n)
  let laneIds = Array.fromInitializer(~length=PorridgeParams.laneSlots, k => PorridgeParams.laneId(k + 1))
  let kindByKey = key => PorridgeParams.allKinds->Array.find(k => k.key == key)
  let shaper = PorridgeParams.shaperParams->Array.map(Pair.first)

  // Moves copy n of kind `old` (as kind `kind`, with the merge's factors) into slot key: its
  // parameters, and the connections to them.
  let moveInto = (~old: PorridgeParams.rackKind, ~kind: PorridgeParams.rackKind, ~n, ~key) => {
    let pairs = switch old.mergedInto {
    | Some(_) => PorridgeParams.mergedParams(old.key)->Array.map(((p, q, f)) => (idOf(p, n), q, f))
    | None =>
      [...old.params->Array.map(Pair.first), ...(old.key == "distortion" ? shaper : [])]
      ->Array.reduce([], (acc, p) => acc->Array.includes(p) ? acc : [...acc, p])
      ->Array.map(p => (idOf(p, n), p, 1.))
    }
    // (a merged kind's settings: its own defaults where the program has none)
    if old.mergedInto != None {
      // (the key shifter's offset stopped at ±1 kHz, the end of its knob, where the shift goes on
      // to ±5 kHz: connections that took it there now take it further)
      let hz = idOf("Sh_Hz", n)
      let base = number(hz)->Option.getOr(PorridgeParams.retiredInit("Sh_Hz"))
      let reach = modulations.contents->Array.reduce(0., (sum, m) =>
        switch m {
        | Object(o) if getString(o, "target") == hz => sum + 2. * Math.abs(getNumber(o, "amount"))
        | _ => sum
        }
      )
      if Math.abs(base) + reach > 1. {
        warnings->Array.push(
          `"${name}" has a key shifter whose offset its connections take past ±1 kHz, where it used to stop: as the frequency shifter's shift it goes on, up to ±1.7 kHz`,
        )
      }
      PorridgeParams.mergedParams(old.key)->Array.forEach(((p, _, _)) =>
        if number(idOf(p, n)) == None {
          setNumber(idOf(p, n), PorridgeParams.retiredInit(p))
        }
      )
    }
    pairs->Array.forEach(((from, first, factor)) => {
      let to = PorridgeParams.slotParamId(first, key)
      switch number(from) {
      | Some(x) => setNumber(to, x * factor)
      | None => params->Dict.delete(to)
      }
      params->Dict.delete(from)
      modulations :=
        modulations.contents->Array.map(m =>
          switch m {
          | Object(o) if getString(o, "target") == from =>
            let o = o->Dict.copy
            o->Dict.set("target", str(to))
            o->Dict.set("amount", num(getNumber(o, "amount") * factor))
            JSON.Object(o)
          | m => m
          }
        )
    })
    ignore(kind)
  }

  // out of the lane, which is kept without gaps and whose places count the effects before them
  let leaveLane = i => {
    laneIds->Array.forEachWithIndex((id, k) =>
      if k >= i {
        setNumber(id, laneIds[k + 1]->Option.flatMap(number)->Option.getOr(0.))
      }
    )
    ["VL_FilterAt", "VL_AmpAt"]->Array.forEach(place =>
      number(place)->Option.forEach(at =>
        if at > Int.toFloat(i) {
          setNumber(place, at - 1.)
        }
      )
    )
  }

  // the old copy a slot's value names (a value from before the slots), as (its kind, its number)
  let oldEntry = v =>
    switch PorridgeParams.rackHistory[v]->Option.flatMap(e => e) {
    | Some((key, n)) => kindByKey(key)->Option.map(k => (k, n))
    | None => None
    }
  let isOld = ((k: PorridgeParams.rackKind, n)) =>
    // (a copy that had parameters of its own: Porridge's kinds' every one, Oatmeal's from 2)
    PorridgeParams.historyOf(k)->Array.includes(n) && (k.firstInRack || n > 1)
  // (a program written since then has its slots' parameters by name, and nothing to move)
  let legacy = !(params->Dict.keysToArray->Array.some(id => String.includes(id, "@")))

  // the rack
  let convolvers = ref(0)
  for slot in 0 to PorridgeParams.rackSlots - 1 {
    let id = PorridgeParams.rackId(slot + 1)
    let v = number(id)->Option.mapOr(0, Float.toInt)
    switch oldEntry(v) {
    | Some((k, n)) if v > 4 =>
      let key = PorridgeParams.slotKey(slot)
      if legacy && isOld((k, n)) {
        moveInto(~old=k, ~kind=k, ~n, ~key)
      }
      if k.key == "convolve" {
        convolvers := convolvers.contents + 1
        if convolvers.contents > 1 {
          warnings->Array.push(
            `"${name}" has two convolvers, and Porridge runs one: the second (FX slot ${Int.toString(slot + 1)}) is left out`,
          )
          setNumber(id, 0.)
        } else if n != 1 {
          // (the only convolver was the second: it's the convolver now, with its file)
          setNumber(id, Int.toFloat(PorridgeParams.entryValue("convolve", 1)))
          convolverFile := Some(n - 1)
        }
      }
    | _ => ()
    }
  }

  // the lane: values name kinds (any of their entries); a retired kind loads as what it became
  laneIds->Array.forEachWithIndex((id, l) => {
    let v = number(id)->Option.mapOr(0, Float.toInt)
    switch oldEntry(v) {
    | Some((k, n)) =>
      let key = PorridgeParams.slotKey(PorridgeParams.rackSlots + l)
      let kind = switch k.mergedInto {
      | Some(into) => kindByKey(into)->Option.getOr(k)
      | None => k
      }
      if legacy && isOld((k, n)) {
        moveInto(~old=k, ~kind, ~n, ~key)
      }
      setNumber(id, Int.toFloat(PorridgeParams.laneValue(kind)))
    | None => ()
    }
  })
  // (an empty lane slot before others: none in a program the view wrote, but keep it gapless)
  let rec closeGaps = i =>
    if i < PorridgeParams.laneSlots - 1 {
      if number(laneIds->Array.getUnsafe(i))->Option.getOr(0.) == 0. && laneIds->Array.slice(~start=i + 1, ~end=PorridgeParams.laneSlots)->Array.some(id => number(id)->Option.getOr(0.) != 0.) {
        leaveLane(i)
        closeGaps(i)
      } else {
        closeGaps(i + 1)
      }
    }
  closeGaps(0)

  // what's left of the old copies sounded nothing
  params->Dict.keysToArray->Array.forEach(id =>
    if PorridgeParams.isLegacyId(id) {
      params->Dict.delete(id)
    }
  )
  let kept = modulations.contents->Array.filter(m => {
    let t = switch m {
    | JSON.Object(m) => getString(m, "target")
    | _ => ""
    }
    !PorridgeParams.isLegacyId(t)
  })
  {params, modulations: kept, warnings, convolverFile: convolverFile.contents}
}

// A preset, and what loading it couldn't keep.
let fromJsonChecked = (d: dict<JSON.t>) => {
  let values = defaultValues()
  let {params, modulations, warnings, convolverFile} = migrateSlots(
    getString(d, "name"),
    switch d->Dict.get("params") {
    | Some(Object(params)) => params
    | _ => Dict.make()
    },
    switch d->Dict.get("modulations") {
    | Some(Array(items)) => items
    | _ => []
    },
  )
  params->Dict.forEachWithKey((v, id) =>
    switch v {
    | Number(x) => loadValue(id, x)->Option.forEach(x => values->Map.set(id, x))
    | _ => ()
    }
  )
  // files from before decay 1 had a curve of its own: the decay curve bent both decays
  PorridgeParams.envelopes->Array.forEach(env => {
    let decay1 = PorridgeParams.decay1CurveId(env.curveName)
    let decay = PorridgeParams.curveId(env.curveName, "Decay")
    if params->Dict.get(decay1) == None {
      values->Map.get(decay)->Option.forEach(x => values->Map.set(decay1, x))
    }
  })

  let given = switch d->Dict.get("tables") {
  | Some(Object(tables)) => tables
  | _ => Dict.make()
  }
  let tables = tablesFrom(table =>
    switch given->Dict.get(tableInfo(table).key) {
    | Some(String(s)) => decodeTable(s, tableLength(table))
    | _ => None
    }->Option.getOr(Lazy.get(defaultTables)->getTable(table)->TypedArray.copy)
  )

  // modulations fill the matrix slots in order
  let slot = ref(1)
  modulations->Array.forEach(item =>
    switch item {
    | Object(m) if slot.contents <= ModMatrix.slots =>
      let source = ModMatrix.sourceIndex(getString(m, "source"))
      let target = targetIndexIn(values, getString(m, "target"))
      let via = ModMatrix.sourceIndex(getString(m, "via"))
      let number = getNumber(m, ...)
      let amount = number("amount")
      if source > 0 && target > 0 {
        let k = slot.contents
        let set = (id, x) => loadValue(id, x)->Option.forEach(x => values->Map.set(id, x))
        set(ModMatrix.sourceId(k), Int.toFloat(source))
        set(ModMatrix.targetId(k), Int.toFloat(target))
        set(ModMatrix.amountId(k), amount)
        set(ModMatrix.viaId(k), Int.toFloat(Math.Int.max(via, 0)))
        set(ModMatrix.holdId(k), getString(m, "hold") == "latch" ? 1. : 0.)
        set(ModMatrix.slewId(k), number("slew"))
        set(ModMatrix.curveId(k), number("curve"))
        set(ModMatrix.stepsId(k), number("steps"))
        slot := k + 1
      }
    | _ => ()
    }
  )

  let macroNames = Array.fromInitializer(~length=ModMatrix.macros, i =>
    switch d->Dict.get("macros") {
    | Some(Array(names)) =>
      switch names[i] {
      | Some(String(s)) => s
      | _ => ""
      }
    | _ => ""
    }
  )

  let tags = switch d->Dict.get("tags") {
  | Some(Array(tags)) =>
    tags->Array.filterMap(t =>
      switch t {
      | String(s) if String.trim(s) != "" => Some(String.trim(s))
      | _ => None
      }
    )
  | _ => []
  }

  let preset = {
    meta: {
      name: getString(d, "name")->String.slice(~start=0, ~end=maxNameLength),
      author: getString(d, "author"),
      category: getString(d, "category"),
      tags,
      description: getString(d, "description"),
      macroNames,
    },
    values,
    tables,
    tuning: d
    ->Dict.get("tuning")
    ->Option.flatMap(Scala.fromJson)
    ->Option.filter(source => Scala.table(source)->Result.isOk),
    impulses: {
      // (one convolver: a second one's file goes, and the only one's, if it was the second's,
      // takes the first's place; the noise's sample keeps its own)
      let list = d->Dict.get("impulses")->Option.mapOr(Impulse.none(), Impulse.listFromJson)
      convolverFile->Option.forEach(i => list->Array.setUnsafe(0, list[i]->Option.flatMap(x => x)))
      list->Array.setUnsafe(1, None)
      list
    },
  }
  (preset, warnings)
}

let fromJsonObject = d => fromJsonChecked(d)->Pair.first

let bankToJson = (presets, ~name="") =>
  JSON.Object(
    Dict.fromArray([
      ("porridge", str("bank")),
      ("version", num(Int.toFloat(formatVersion))),
      ("name", str(name)),
      ("presets", JSON.Array(presets->Array.map(toJson(_, ~header=false)))),
    ]),
  )

type kind = Single | Many

// name: a bank file's name for itself, or ""
type parsed = {kind: kind, presets: array<t>, warnings: array<string>, name: string}

let parseJson = (text): result<parsed, string> =>
  switch JSON.parseOrThrow(text) {
  | Object(d) =>
    let version = switch d->Dict.get("version") {
    | Some(Number(v)) => v
    | _ => 1.
    }
    let warnings =
      version > Int.toFloat(formatVersion)
        ? ["this file is from a newer Porridge; some settings may be missing"]
        : []
    let read = items => {
      let checked = items->Array.filterMap(item =>
        switch item {
        | JSON.Object(p) => Some(fromJsonChecked(p))
        | _ => None
        }
      )
      (checked->Array.map(Pair.first), [...warnings, ...checked->Array.flatMap(Pair.second)])
    }
    switch d->Dict.get("porridge") {
    | Some(String("preset")) =>
      let (presets, warnings) = read([JSON.Object(d)])
      Ok({kind: Single, presets, warnings, name: ""})
    | Some(String("bank")) =>
      let (presets, warnings) = read(
        switch d->Dict.get("presets") {
        | Some(Array(items)) => items
        | _ => []
        },
      )
      Ok({kind: Many, presets, warnings, name: getString(d, "name")})
    | _ => Error("not a Porridge preset or bank")
    }
  | _ => Error("not a Porridge preset or bank")
  | exception _ => Error("not valid JSON")
  }

let utf8Decode: Uint8Array.t => string = %raw(`bytes => new TextDecoder("utf-8").decode(bytes)`)
let utf8Encode: string => Uint8Array.t = %raw(`text => new TextEncoder().encode(text)`)

let looksLikeJson = (bytes: Uint8Array.t) => {
  let n = TypedArray.length(bytes)
  let rec first = i =>
    if i >= n {
      false
    } else {
      switch ByteView.byteAt(bytes, i) {
      | 32 | 9 | 10 | 13 | 0xef | 0xbb | 0xbf => first(i + 1) // whitespace, UTF-8 BOM
      | 123 => true // {
      | _ => false
      }
    }
  first(0)
}

// Any file Porridge can load: its own presets and banks, and every Oatmeal format. (Reading a
// file cut short in the wrong place can throw: that's an error too.)
let parseFile = (bytes): result<parsed, string> =>
  try {
    if looksLikeJson(bytes) {
      parseJson(utf8Decode(bytes))
    } else {
      switch OatmealFormat.parseFile(bytes) {
      | Ok({kind, programs, warnings}) =>
        Ok({
          kind: kind == Program ? Single : Many,
          presets: programs->Array.map(p => fromOatmeal(p.bytes)),
          warnings,
          name: "",
        })
      | Error(e) => Error(e)
      }
    }
  } catch {
  | JsExn(e) => Error(e->JsExn.message->Option.getOr("unreadable"))
  }

// A file the user opened, with at least one program in it, or what to tell them.
let parseForLoading = (bytes, filename) =>
  switch parseFile(bytes) {
  | Error(e) => Error(`${filename} isn't a Porridge or Oatmeal program or bank (${e})`)
  | Ok({presets: []}) => Error(`${filename} has no programs in it`)
  | parsed => parsed
  }

// The files parseFile reads, for a file dialog.
let extensions = [".porridge", ".json", ".omp", ".omb", ".fxp", ".fxb", ".dat"]

let writePreset = p => utf8Encode(JSON.stringify(toJson(p), ~space=1))
let writeBank = (presets, ~name=?) => utf8Encode(JSON.stringify(bankToJson(presets, ~name?), ~space=1))

//==============================================================================
// The bank in the patch's stored state

// It's written on every program change, so each preset's JSON is kept (presets aren't
// changed once made) and only new ones are encoded.
let encoded: WeakMap.t<t, string> = WeakMap.make()

let encodePreset = p =>
  switch encoded->WeakMap.get(p) {
  | Some(json) => json
  | None =>
    let json = JSON.stringify(toJson(p, ~header=false, ~sparse=true))
    encoded->WeakMap.set(p, json)->ignore
    json
  }

let encodeBank = (presets, ~name="") => {
  // the bank's fields, ending in "presets":[]}
  let empty = JSON.stringify(bankToJson([], ~name))
  String.slice(empty, ~start=0, ~end=-2) ++
  presets->Array.map(encodePreset)->Array.join(",") ++ "]}"
}

// Oatmeal's factory bank (presets/oatmealprs.dat), as a new instance starts with it: its
// programs, then Init programs up to a full bank. tools/bundle.mjs stores it, encoded, in
// bundle/factory-bank.json for the worker.
let factoryBank = bytes => {
  let programs = switch OatmealFormat.parseFile(bytes) {
  | Ok({programs}) => programs
  | Error(e) => JsError.panic("the factory bank can't be read: " ++ e)
  }
  Array.fromInitializer(~length=bankPrograms, i =>
    switch programs[i] {
    | Some(p) => fromOatmeal(p.bytes)
    | None => init(i == 0 ? "Init" : `Init ${Int.toString(i)}`)
    }
  )
}

// The first preset of an encoded bank, without decoding the rest.
let decodeFirst = s =>
  switch JSON.parseOrThrow(s) {
  | Object(d) =>
    switch d->Dict.get("presets") {
    | Some(Array(items)) =>
      switch items[0] {
      | Some(Object(p)) => Some(fromJsonObject(p))
      | _ => None
      }
    | _ => None
    }
  | _ => None
  | exception _ => None
  }

// The bank's name and presets, and what loading them couldn't keep. Older sessions stored the
// bank as base64 Oatmeal chunks.
let decodeNamedBank = s =>
  if String.startsWith(String.trim(s), "{") {
    switch parseJson(s) {
    | Ok({presets, name, warnings}) => Some((name, presets, warnings))
    | Error(_) => None
    }
  } else {
    Some(("", Bank.decodeBank(s)->Array.map(fromOatmeal), []))
  }

let decodeBank = s => decodeNamedBank(s)->Option.map(((_, presets, _)) => presets)
