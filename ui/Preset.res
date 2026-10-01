// Porridge's own preset format. A preset is a JSON document:
//
//   {
//     "porridge": "preset", "version": 1,
//     "name": "Warm pad", "author": "", "category": "pad", "tags": ["slow"], "description": "",
//     "params": { "Cutoff": 0.42, "O1_Waveform": 1, ... },   // endpoint id -> internal value
//     "tables": { "wave1": "<base64 float32 LE>", ... }       // only tables that differ from Init
//   }
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
}

type t = {
  meta: meta,
  // every parameter, by endpoint id
  values: Bank.values,
  tables: tables,
}

let defs = Lazy.make(() => ParamDefs.makeDefs())
let defsById = Lazy.make(() => Lazy.get(defs)->Array.map(d => (d.id, d))->Map.fromArray)

let defaultValues = () => Lazy.get(defs)->Array.map(d => (d.ParamDefs.id, d.init))->Map.fromArray

let defaultTables = Lazy.make(() => extractTables(makeDefaultProgram("Init")))

let copyTables = tables => tablesFrom(table => tables->getTable(table)->TypedArray.copy)

let emptyMeta = name => {name, author: "", category: "", tags: [], description: ""}

let make = name => {
  meta: emptyMeta(name),
  values: defaultValues(),
  tables: copyTables(Lazy.get(defaultTables)),
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
  | Pw => Math.round(x * ParamDefs.pw32) / ParamDefs.pw32
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
  {meta: emptyMeta(getName(bytes)), values, tables: extractTables(bytes)}
}

// Parameters Oatmeal doesn't have are left out.
let toOatmeal = p => {
  let bytes = makeDefaultProgram(p.meta.name)
  Bank.writeValues(bytes, p.values)
  allTables->Array.forEach(table => writeTable(bytes, table, p.tables->getTable(table)))
  bytes
}

//==============================================================================
// JSON

let tableKey = table =>
  switch table {
  | Wave1 => "wave1"
  | Wave2 => "wave2"
  | LfoShape1 => "lfoShape1"
  | LfoShape2 => "lfoShape2"
  | VelocityCurve => "velocityCurve"
  | AftertouchCurve => "aftertouchCurve"
  }

// The shortest decimal that reads back as the same parameter value, so files stay
// readable ("0.3", not "0.30000001192092896").
let shortNumber = (d, x) =>
  if !Float.isFinite(x) {
    0.
  } else if canonical(d, x) != x {
    x
  } else {
    let rec go = digits =>
      if digits > 10 {
        x
      } else {
        let y = Float.parseFloat(x->Float.toPrecision(~digits))
        canonical(d, y) == x ? y : go(digits + 1)
      }
    go(1)
  }

let sameTable = (a: Float32Array.t, b: Float32Array.t) =>
  TypedArray.length(a) == TypedArray.length(b) &&
    a->TypedArray.everyWithIndex((x, i) =>
      ByteView.bitsOfFloat32(x) == ByteView.bitsOfFloat32(ByteView.getUnsafe(b, i))
    )

// (a copy has a buffer of its own, so the bytes are exactly the table's)
let encodeTable = (data: Float32Array.t) =>
  Bank.toBase64(Uint8Array.fromBuffer(data->TypedArray.copy->TypedArray.buffer))

let decodeTable = (s, length) => {
  let bytes = Bank.fromBase64(s)
  if TypedArray.length(bytes) < length * 4 {
    None
  } else {
    // copy into an aligned buffer before viewing it as floats
    let aligned = Uint8Array.fromLength(length * 4)
    aligned->ByteView.blit(bytes->TypedArray.subarray(~start=0, ~end=length * 4), 0)
    Some(Float32Array.fromBuffer(aligned->TypedArray.buffer, ~length))
  }
}

let str = s => JSON.String(s)
let num = x => JSON.Number(x)

let toJson = (p, ~header=true) => {
  let fields = Dict.make()
  if header {
    fields->Dict.set("porridge", str("preset"))
    fields->Dict.set("version", num(Int.toFloat(formatVersion)))
  }
  fields->Dict.set("name", str(p.meta.name))
  fields->Dict.set("author", str(p.meta.author))
  fields->Dict.set("category", str(p.meta.category))
  fields->Dict.set("tags", JSON.Array(p.meta.tags->Array.map(str)))
  fields->Dict.set("description", str(p.meta.description))

  let params = Dict.make()
  Lazy.get(defs)->Array.forEach(d =>
    p.values->Map.get(d.id)->Option.forEach(x => params->Dict.set(d.id, num(shortNumber(d, x))))
  )
  fields->Dict.set("params", JSON.Object(params))

  let tables = Dict.make()
  allTables->Array.forEach(table => {
    let data = p.tables->getTable(table)
    if !sameTable(data, Lazy.get(defaultTables)->getTable(table)) {
      tables->Dict.set(tableKey(table), str(encodeTable(data)))
    }
  })
  fields->Dict.set("tables", JSON.Object(tables))
  JSON.Object(fields)
}

let getString = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.String(s)) => s
  | _ => ""
  }

let fromJsonObject = (d: dict<JSON.t>) => {
  let values = defaultValues()
  switch d->Dict.get("params") {
  | Some(Object(params)) =>
    params->Dict.forEachWithKey((v, id) =>
      switch v {
      | Number(x) => clampValue(id, x)->Option.forEach(x => values->Map.set(id, x))
      | _ => ()
      }
    )
  | _ => ()
  }

  let given = switch d->Dict.get("tables") {
  | Some(Object(tables)) => tables
  | _ => Dict.make()
  }
  let tables = tablesFrom(table =>
    switch given->Dict.get(tableKey(table)) {
    | Some(String(s)) => decodeTable(s, tableLength(table))
    | _ => None
    }->Option.getOr(Lazy.get(defaultTables)->getTable(table)->TypedArray.copy)
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
    },
    values,
    tables,
  }
}

let bankToJson = (presets, ~name="") => {
  let fields = Dict.make()
  fields->Dict.set("porridge", str("bank"))
  fields->Dict.set("version", num(Int.toFloat(formatVersion)))
  fields->Dict.set("name", str(name))
  fields->Dict.set("presets", JSON.Array(presets->Array.map(toJson(_, ~header=false))))
  JSON.Object(fields)
}

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

// Any file Porridge can load: its own presets and banks, and every Oatmeal format.
let parseFile = (bytes): result<parsed, string> =>
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

let writePreset = p => utf8Encode(JSON.stringify(toJson(p), ~space=1))
let writeBank = (presets, ~name=?) => utf8Encode(JSON.stringify(bankToJson(presets, ~name?), ~space=1))

//==============================================================================
// The bank in the patch's stored state

let encodeBank = presets => JSON.stringify(bankToJson(presets))

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
