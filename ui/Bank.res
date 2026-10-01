// Program/bank plumbing shared by the view and the headless worker.
// A program is kept exactly as Oatmeal stores it: a 10376-byte version-38 chunk.
// Parameter endpoints carry the same internal values the chunk holds.

open OatmealFormat

// A field's endpoint value: the internal value, except pulse width (a 0..1 fraction). The
// second filter type is read as a signed word, like the DLL does; its values (0..21) read the
// same either way.
let readField = (bytes, field: Fields.t) => {
  let x = OatmealParams.readInternal(bytes, field.index)
  field.kind == Pw ? OatmealParams.pwOfPhase(x) : x
}

// Like setParameter, an envelope's release also writes the DLL's second release field.
let writeField = (bytes, field: Fields.t, x) =>
  OatmealParams.writeInternal(
    bytes,
    field.index,
    switch field.kind {
    | F32 => x
    | Pw => OatmealParams.pwToPhase(x)
    | I32 | Filter1 | Filter2 => Math.round(x)
    },
  )

let fieldsById = Fields.all->Array.map(field => (field.id, field))->Map.fromArray

// Parameter values by endpoint id.
type values = Map.t<string, float>

let programValues = (bytes): values =>
  Fields.all->Array.map(field => (field.id, readField(bytes, field)))->Map.fromArray

// One value by endpoint id (0 for a parameter Oatmeal doesn't have).
let readValue = (bytes, id) => fieldsById->Map.get(id)->Option.mapOr(0., readField(bytes, _))

// Parameters Oatmeal doesn't have are skipped.
let writeValue = (bytes, id, x) =>
  fieldsById->Map.get(id)->Option.forEach(field => writeField(bytes, field, x))

let writeValues = (bytes, values: values) =>
  values->Map.forEachWithKey((x, id) => writeValue(bytes, id, x))

//==============================================================================
// Sending to the patch

type shapePayload = {which: int, data: array<float>}

@val external arrayOfFloats: Float32Array.t => array<float> = "Array.from"

// The endpoint that takes a table, and its index there.
let shapeEndpoint = table =>
  switch table {
  | Wave1 => ("shapeIn", 0)
  | Wave2 => ("shapeIn", 1)
  | LfoShape1 => ("shapeIn", 2)
  | LfoShape2 => ("shapeIn", 3)
  | VelocityCurve => ("curveIn", 0)
  | AftertouchCurve => ("curveIn", 1)
  }

let sendShape = (pc, table, data) => {
  let (endpoint, which) = shapeEndpoint(table)
  pc->PatchConnection.sendEventOrValueNow(endpoint, {which, data: arrayOfFloats(data)})
}

type tuningPayload = {on: int, semitones: array<float>}

// a microtuning (or Oatmeal's tuning, for None) to the patch
let sendTuning = (pc, tuning: option<Scala.source>) => {
  let payload = switch tuning->Option.map(Scala.table) {
  | Some(Ok({semitones})) => {on: 1, semitones}
  | _ => {on: 0, semitones: Array.make(~length=128, 0.)}
  }
  pc->PatchConnection.sendEventOrValueNow("tuningIn", payload)
}

// the stored-state form of a microtuning: JSON text, or "" for none
let encodeTuning = (tuning: option<Scala.source>) =>
  switch tuning {
  | Some({scl, kbm}) =>
    JSON.stringify(JSON.Object(Dict.fromArray([("scl", JSON.String(scl)), ("kbm", JSON.String(kbm))])))
  | None => ""
  }

let decodeTuning = (s): option<Scala.source> =>
  switch JSON.parseOrThrow(s) {
  | Object(d) =>
    switch (d->Dict.get("scl"), d->Dict.get("kbm")) {
    | (Some(String(scl)), Some(String(kbm))) => Some({scl, kbm})
    | _ => None
    }
  | _ => None
  | exception _ => None
  }

let sendValues = (pc, values: values) =>
  values->Map.forEachWithKey((x, id) => pc->PatchConnection.sendEventOrValueNow(id, x))

//==============================================================================
// State encoding (base64 without relying on btoa/atob, which the worker may not have)

let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let digitOf = Array.make(~length=128, 0)
for i in 0 to 63 {
  digitOf->Array.setUnsafe(String.charCodeAtUnsafe(alphabet, i), i)
}

let toBase64 = (bytes: Uint8Array.t) => {
  let n = TypedArray.length(bytes)
  let byte = i => i < n ? bytes->ByteView.byteAt(i) : 0
  let digit = d => String.charAt(alphabet, d &&& 63)
  Array.fromInitializer(~length=(n + 2) / 3, k => {
    let i = 3 * k
    let t = byte(i) << 16 ||| byte(i + 1) << 8 ||| byte(i + 2)
    digit(t >> 18) ++
    digit(t >> 12) ++
    (i + 1 < n ? digit(t >> 6) : "=") ++ (i + 2 < n ? digit(t) : "=")
  })->Array.join("")
}

let fromBase64 = s => {
  let clean = s->String.replaceRegExp(/[^A-Za-z0-9+\/]/g, "")
  let length = String.length(clean)
  let n = length * 3 / 4
  let out = Uint8Array.fromLength(n)
  let digit = i => i < length ? digitOf->Array.getUnsafe(String.charCodeAtUnsafe(clean, i)) : 0
  for k in 0 to (length + 3) / 4 - 1 {
    let i = 4 * k
    let t = digit(i) << 18 ||| digit(i + 1) << 12 ||| digit(i + 2) << 6 ||| digit(i + 3)
    [t >> 16, t >> 8, t]->Array.forEachWithIndex((b, j) =>
      if 3 * k + j < n {
        out->TypedArray.set(3 * k + j, b &&& 255)
      }
    )
  }
  out
}

let encodeBank = programs => {
  let all = Uint8Array.fromLength(bankPrograms * programSize)
  programs->Array.forEachWithIndex((p, i) => all->ByteView.blit(p, i * programSize))
  toBase64(all)
}

let decodeBank = s => {
  let all = fromBase64(s)
  Array.fromInitializer(~length=bankPrograms, i =>
    all->TypedArray.slice(~start=i * programSize, ~end=(i + 1) * programSize)
  )
}

// Shapes are stored as the float32 bytes of every table, in allTables order.
let shapesLength = allTables->Array.reduce(0, (n, table) => n + tableLength(table))

let packedOffset = table =>
  allTables
  ->Array.slice(~start=0, ~end=allTables->Array.indexOf(table))
  ->Array.reduce(0, (n, t) => n + tableLength(t))

let encodeShapes = shapes => {
  let packed = Float32Array.fromLength(shapesLength)
  allTables->Array.forEach(table => {
    let src = shapes->getTable(table)
    let offset = packedOffset(table)
    for i in 0 to tableLength(table) - 1 {
      packed->TypedArray.set(offset + i, src->TypedArray.get(i)->Option.getOr(0.))
    }
  })
  toBase64(Uint8Array.fromBuffer(packed->TypedArray.buffer))
}

let decodeShapes = s => {
  let bytes = fromBase64(s)
  if TypedArray.length(bytes) < shapesLength * 4 {
    None
  } else {
    let packed = Float32Array.fromBuffer(bytes->TypedArray.buffer, ~length=shapesLength)
    Some(
      tablesFrom(table => {
        let offset = packedOffset(table)
        packed->TypedArray.slice(~start=offset, ~end=offset + tableLength(table))
      }),
    )
  }
}
