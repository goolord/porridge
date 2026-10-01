// Porridge's own preset format. A preset is a JSON document:
//
//   {
//     "porridge": "preset", "version": 1,
//     "name": "Warm pad", "author": "", "category": "pad", "tags": ["slow"], "description": "",
//     "params": { "Cutoff": 0.42, "O1_Waveform": 1, ... },   // endpoint id -> internal value
//     "modulations": [ { "source": "lfo1", "target": "Cutoff", "amount": 0.25, "via": "modWheel" } ],
//     "macros": ["brightness", "", "", ""],                    // macro knob names
//     "tables": { "wave1": "<base64 float32 LE>", ... },      // only tables that differ from Init
//     "tuning": { "scl": "<.scl text>", "kbm": "<.kbm text>" }, // microtuning, if any
//     "impulses": [ { "name": "hall.wav", "rate": 48000, "left": "<base64 float32 LE>",
//                     "right": "..." }, null ]           // the convolvers' files (Impulse.res), if any
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

let defs = Lazy.make(() => ParamDefs.makeDefs())
let defsById = Lazy.make(() => Lazy.get(defs)->Array.map(d => (d.id, d))->Map.fromArray)

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

let make = name => {
  meta: emptyMeta(name),
  values: defaultValues(),
  tables: copyTables(Lazy.get(defaultTables)),
  tuning: None,
  impulses: Impulse.none(),
}

// A whole bank: presets, then Init programs.
let fillBank = presets =>
  Array.fromInitializer(~length=bankPrograms, i =>
    switch presets[i] {
    | Some(p) => p
    | None => make(`Init ${Int.toString(i)}`)
    }
  )

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

let clampValue = (id, x) =>
  Lazy.get(defsById)->Map.get(id)->Option.map(d => canonical(d, d.clamp(x)))

//==============================================================================
// Oatmeal

let fromOatmeal = (bytes: Uint8Array.t) => {
  let values = defaultValues()
  Bank.programValues(bytes)->Map.forEachWithKey((x, id) =>
    clampValue(id, x)->Option.forEach(x => values->Map.set(id, x))
  )
  {meta: emptyMeta(getName(bytes)), values, tables: extractTables(bytes), tuning: None, impulses: Impulse.none()}
}

let valueOf = (p, id) =>
  p.values->Map.get(id)->Option.getOr(Lazy.get(defsById)->Map.get(id)->Option.mapOr(0., d => d.init))

// What an Oatmeal export of this preset loses.
let porridgeOnly = p => {
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
  // values Porridge added to Oatmeal's lists (HQ waveforms, osc mix modes, filter types)
  let extended = ids =>
    ids->Array.some(id =>
      p.values->Map.get(id)->Option.mapOr(false, x => ParamDefs.oatmealValue(id, x) != x)
    )
  // (Oatmeal always plays like Oat mode)
  [
    changed(Modulations) ? Some("modulations") : None,
    changed(Macros) ? Some("macros") : None,
    changed(Mpe) ? Some("MPE settings") : None,
    changed(Drift) ? Some("the analog drift") : None,
    {
      // Oatmeal's chain is chorus, delay, reverb, EQ; effects left out of the rack are exported
      // switched off, so only their order is lost
      let firsts = FxRack.read(valueOf(p, _))->Array.filter(FxRack.isFirst)
      firsts != FxRack.firsts->Array.filter(e => FxRack.holds(firsts, e)) ? Some("the effects order") : None
    },
    switch FxRack.read(valueOf(p, _))->Array.filter(e => !FxRack.isFirst(e)) {
    | [] => None
    | copies =>
      Some(`the rack's extra effects (${copies->Array.map(e => FxRack.kindName(e.kind))->Array.join(", ")})`)
    },
    changed(Curves) || changed(Decay1Curves) ? Some("the envelope curves") : None,
    changed(LfoExtras) ? Some("the LFO delay, slew, steps and one-shot") : None,
    changed(UnisonExtras) ? Some("the unison extras") : None,
    extended(["Sat_Type"]) ? Some("the custom distortion shape (exported as soft clipping)") : None,
    extended(["O1_Waveform", "O2_Waveform"]) ? Some("the HQ waveforms (exported as the plain ones)") : None,
    extended(["OscMix"]) || changed(PmFeedback) ? Some("the PM, ring and AM osc mix (exported as normal)") : None,
    extended(["Filter", "Filter2"]) || changed(FilterMorph)
      ? Some("Porridge's filter types (exported as the nearest Oatmeal type)")
      : None,
    p.tuning != None ? Some("the microtuning") : None,
    changed(FilterDrive) ? Some("the filter drive") : None,
    String.length(p.meta.name) > nameLength - 1 ? Some("the full name") : None,
  ]->Array.filterMap(x => x)
}

// Parameters Oatmeal doesn't have are left out, and list values it doesn't have become the
// closest ones it does.
let toOatmeal = p => {
  let bytes = makeDefaultProgram(p.meta.name)
  let values = p.values->Map.entries->Iterator.toArray->Array.map(((id, x)) => (id, ParamDefs.oatmealValue(id, x)))->Map.fromArray
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

let toJson = (p, ~header=true) => {
  let params = Lazy.get(defs)->Array.filterMap(d =>
    ModMatrix.isSlotParam(d.id)
      ? None
      : p.values->Map.get(d.id)->Option.map(x => (d.id, num(shortNumber(d, x))))
  )

  let modulations = ModMatrix.slotNumbers->Array.filterMap(k => {
    let slot = ModMatrix.readSlot(id => p.values->Map.get(id)->Option.getOr(0.), k)
    switch (ModMatrix.sources[slot.source], ModMatrix.targets[slot.target]) {
    | (Some(source), Some(target)) if source.key != "none" && target.key != "none" =>
      let via = switch ModMatrix.sources[slot.via] {
      | Some(via) if via.key != "none" => [("via", str(via.key))]
      | _ => []
      }
      Some(
        JSON.Object(
          Dict.fromArray([
            ("source", str(source.key)),
            ("target", str(target.key)),
            ("amount", num(Math.fround(slot.amount)->shortFloat)),
            ...via,
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

let fromJsonObject = (d: dict<JSON.t>) => {
  let values = defaultValues()
  let params = switch d->Dict.get("params") {
  | Some(Object(params)) => params
  | _ => Dict.make()
  }
  params->Dict.forEachWithKey((v, id) =>
    switch v {
    | Number(x) => clampValue(id, x)->Option.forEach(x => values->Map.set(id, x))
    | _ => ()
    }
  )
  // files from before decay 1 had a curve of its own: the decay curve bent both decays
  PorridgeParams.envNames->Array.forEach(((env, _)) => {
    let decay1 = PorridgeParams.decay1CurveId(env)
    let decay = PorridgeParams.curveId(env, "Decay")
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
  switch d->Dict.get("modulations") {
  | Some(Array(items)) =>
    items->Array.forEach(item =>
      switch item {
      | Object(m) if slot.contents <= ModMatrix.slots =>
        let source = ModMatrix.sourceIndex(getString(m, "source"))
        let target = ModMatrix.targetIndex(getString(m, "target"))
        let via = ModMatrix.sourceIndex(getString(m, "via"))
        let amount = switch m->Dict.get("amount") {
        | Some(Number(x)) => x
        | _ => 0.
        }
        if source > 0 && target > 0 {
          let k = slot.contents
          let set = (id, x) => clampValue(id, x)->Option.forEach(x => values->Map.set(id, x))
          set(ModMatrix.sourceId(k), Int.toFloat(source))
          set(ModMatrix.targetId(k), Int.toFloat(target))
          set(ModMatrix.amountId(k), amount)
          set(ModMatrix.viaId(k), Int.toFloat(Math.Int.max(via, 0)))
          slot := k + 1
        }
      | _ => ()
      }
    )
  | _ => ()
  }

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

  {
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
}

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

type parsed = {kind: kind, presets: array<t>, warnings: array<string>}

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
    switch d->Dict.get("porridge") {
    | Some(String("preset")) => Ok({kind: Single, presets: [fromJsonObject(d)], warnings})
    | Some(String("bank")) =>
      let presets = switch d->Dict.get("presets") {
      | Some(Array(items)) =>
        items->Array.filterMap(item =>
          switch item {
          | Object(p) => Some(fromJsonObject(p))
          | _ => None
          }
        )
      | _ => []
      }
      Ok({kind: Many, presets, warnings})
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
    let json = JSON.stringify(toJson(p, ~header=false))
    encoded->WeakMap.set(p, json)->ignore
    json
  }

let encodeBank = presets => {
  // the bank's fields, ending in "presets":[]}
  let empty = JSON.stringify(bankToJson([]))
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
    | None => make(i == 0 ? "Init" : `Init ${Int.toString(i)}`)
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

// Older sessions stored the bank as base64 Oatmeal chunks.
let decodeBank = s =>
  if String.startsWith(String.trim(s), "{") {
    switch parseJson(s) {
    | Ok({presets}) => Some(presets)
    | Error(_) => None
    }
  } else {
    Some(Bank.decodeBank(s)->Array.map(fromOatmeal))
  }
