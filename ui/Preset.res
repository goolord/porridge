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

let defaultValues = () => Lazy.get(defs)->Array.map(d => (d.ParamDefs.id, d.init))->Map.fromArray

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
    FxRack.values(rack->Array.filter(e => !idle(e)))->Array.forEach(((id, x)) => values->Map.set(id, x))
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

// A value as a loaded program keeps it (ParamDefs' load), or None for a parameter there isn't.
let loadValue = (id, x) =>
  Lazy.get(defsById)->Map.get(id)->Option.map(d => canonical(d, d.load(x)))

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

// ~sparse leaves out the parameters that read back as their default (a missing parameter has
// its default value), which shrinks the bank in the stored state to a fraction of its size
let toJson = (p, ~header=true, ~sparse=false) => {
  let params = Lazy.get(defs)->Array.filterMap(d =>
    ModMatrix.isSlotParam(d.id)
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
            ("target", str(target.key)),
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

// A program from before the rack's fourth copies were retired (PorridgeParams) may hold one in a
// rack or voice slot. It moves onto a free copy of its kind, with its parameters and the
// connections to them: a copy that no slot holds and no connection moves, so the program sounds
// as it did. With none free, it's left out with its connections, and the warning says so.
// Connections to retired copies that no slot held moved nothing, and go. Returns the program's
// params and modulations as they load, and the warnings.
//
// A kind retired as a whole (the key shifter, which became the frequency shifter's ratio of the
// note: PorridgeParams.mergedInto) loads the same way, onto a free copy of the kind it became,
// its settings read as that kind's (PorridgeParams.mergedParams: each parameter, the one it
// becomes and the factor on its knob, which scales the connections' amounts too); the new
// kind's other parameters keep their defaults.
let retireCopies = (name, params: dict<JSON.t>, modulations: array<JSON.t>) => {
  let params = params->Dict.copy
  let modulations = ref(modulations)
  let warnings = []
  let number = id =>
    switch params->Dict.get(id) {
    | Some(Number(x)) => Some(x)
    | _ => None
    }
  let setNumber = (id, x) => params->Dict.set(id, JSON.Number(x))
  let rackIds = Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1))
  let laneIds = Array.fromInitializer(~length=PorridgeParams.laneSlots, k => PorridgeParams.laneId(k + 1))
  let slotIds = Array.concat(rackIds, laneIds)
  let holding = v => slotIds->Array.filter(id => number(id) == Some(Int.toFloat(v)))
  let targetOf = m =>
    switch m {
    | JSON.Object(m) => getString(m, "target")
    | _ => ""
    }
  let idOf = (first, n) => n == 1 ? first : PorridgeParams.copyId(first, n)

  // its parameters, and the connections to them, go to copy `to`'s; the slots that held it
  // hold `value`
  // (each connection to one of from's parameters scaled by its factor)
  let move = (v, ~from, ~to, ~value, ~factors=?) => {
    from->Array.forEachWithIndex((id, i) => {
      let id2 = to->Array.getUnsafe(i)
      switch params->Dict.get(id) {
      | Some(x) => params->Dict.set(id2, x)
      | None => params->Dict.delete(id2)
      }
      params->Dict.delete(id)
    })
    holding(v)->Array.forEach(id => setNumber(id, Int.toFloat(value)))
    modulations :=
      modulations.contents->Array.map(m =>
        switch m {
        | Object(o) if from->Array.includes(getString(o, "target")) =>
          let o = o->Dict.copy
          let i = from->Array.indexOf(getString(o, "target"))
          o->Dict.set("target", str(to->Array.getUnsafe(i)))
          factors->Option.forEach(f => o->Dict.set("amount", num(getNumber(o, "amount") * f->Array.getUnsafe(i))))
          JSON.Object(o)
        | m => m
        }
      )
  }

  // a retired kind's copy `old` as copy n of the kind it became: its settings read as that
  // kind's (with its own defaults where the program has none), the rest of copy n at theirs
  let merge = (v, ~retired: PorridgeParams.rackKind, ~old, ~kind: PorridgeParams.rackKind, ~n, ~value) => {
    let pairs = PorridgeParams.mergedParams(retired.key)
    let from = pairs->Array.map(((p, _, _)) => idOf(p, old))
    // (the key shifter's offset stopped at ±1 kHz, the end of its knob, where the shift goes on
    // to ±5 kHz: connections that took it there now take it further)
    if retired.key == "shifter" {
      let id = idOf("Sh_Hz", old)
      let base = number(id)->Option.getOr(PorridgeParams.retiredInit("Sh_Hz"))
      let reach = modulations.contents->Array.reduce(0., (sum, m) =>
        switch m {
        | Object(o) if getString(o, "target") == id => sum + 2. * Math.abs(getNumber(o, "amount"))
        | _ => sum
        }
      )
      if Math.abs(base) + reach > 1. {
        warnings->Array.push(
          `"${name}" has a key shifter whose offset its connections take past ±1 kHz, where it used to stop: as the frequency shifter's shift it goes on, up to ±1.7 kHz`,
        )
      }
    }
    // its settings on the new kind's knobs
    pairs->Array.forEachWithIndex(((p, _, factor), i) => {
      let id = from->Array.getUnsafe(i)
      setNumber(id, number(id)->Option.getOr(PorridgeParams.retiredInit(p)) * factor)
    })
    kind.params->Array.forEach(((first, _)) => params->Dict.delete(idOf(first, n)))
    move(
      v,
      ~from,
      ~to=pairs->Array.map(((_, q, _)) => idOf(q, n)),
      ~value,
      ~factors=pairs->Array.map(((_, _, factor)) => factor),
    )
    // (its other parameters go with it)
    retired.params->Array.forEach(((first, _)) => params->Dict.delete(idOf(first, old)))
  }

  // out of the rack, or the lane, which is kept without gaps and whose places count the effects
  // before them
  let leaveOut = v =>
    holding(v)->Array.toReversed->Array.forEach(id =>
      switch laneIds->Array.indexOf(id) {
      | -1 => setNumber(id, 0.)
      | i =>
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
    )

  slotIds
  ->Array.filterMap(number)
  ->Array.reduce([], (acc, v) => acc->Array.includes(v) ? acc : [...acc, v])
  ->Array.forEach(v => {
    let v = Float.toInt(v)
    PorridgeParams.retiredEntry(v)->Option.forEach(((key, old)) => {
      let retired = PorridgeParams.allKinds->Array.find(k => k.key == key)->Option.getOrThrow
      // (the kind it became, for a kind retired as a whole)
      let kind = switch retired.mergedInto {
      | Some(into) => PorridgeParams.rackKinds->Array.find(k => k.key == into)->Option.getOrThrow
      | None => retired
      }
      let key = kind.key
      let ids = n => kind.params->Array.map(((first, _)) => idOf(first, n))
      // a copy of its kind (not Oatmeal's chorus, delay, reverb or EQ, which FX_Order places)
      // that no slot holds and no connection moves
      let free =
        PorridgeParams.rackEntries
        ->Array.mapWithIndex((e, value) => (value, e))
        ->Array.find(((value, e)) =>
          switch e {
          | Some((k, n)) if k == key && (n > 1 || kind.firstInRack) =>
            holding(value) == [] &&
              !(modulations.contents->Array.some(m => ids(n)->Array.includes(targetOf(m))))
          | _ => false
          }
        )
      switch (free, retired.mergedInto) {
      | (Some((value, Some((_, n)))), None) => move(v, ~from=ids(old), ~to=ids(n), ~value)
      | (Some((value, Some((_, n)))), Some(_)) => merge(v, ~retired, ~old, ~kind, ~n, ~value)
      | (_, None) =>
        let what = `${kind.name} ${Int.toString(old)}`
        warnings->Array.push(
          `"${name}" has ${what}, which Porridge no longer has, and no other ${kind.name->String.toLowerCase} free to take it: it's left out`,
        )
        leaveOut(v)
      | (_, Some(_)) =>
        let what = old == 1 ? retired.name : `${retired.name} ${Int.toString(old)}`
        let into = kind.menuName->Option.getOr(kind.name)
        warnings->Array.push(
          `"${name}" has ${what}, which Porridge now has as its ${into}, and no ${into} free to take it: it's left out`,
        )
        leaveOut(v)
      }
    })
  })
  let kept = modulations.contents->Array.filter(m => !PorridgeParams.isRetiredId(targetOf(m)))
  (params, kept, warnings)
}

// A preset, and what loading it couldn't keep.
let fromJsonChecked = (d: dict<JSON.t>) => {
  let values = defaultValues()
  let (params, modulations, warnings) = retireCopies(
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
      let target = ModMatrix.targetIndex(getString(m, "target"))
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
    impulses: d->Dict.get("impulses")->Option.mapOr(Impulse.none(), Impulse.listFromJson),
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
