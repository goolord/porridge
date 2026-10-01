// Program/bank plumbing shared by the view and the headless worker.
// A program is kept exactly as Oatmeal stores it: a 10376-byte version-38 chunk.
// Parameter endpoints carry the same internal values the chunk holds.

open OatmealFormat

let filterOffset = 8428

let readField = (bytes, field: Fields.t) =>
  switch field.kind {
  | F32 => bytes->ByteView.getF32(field.offset)
  | I32 => bytes->ByteView.getI32(field.offset)->Int.toFloat
  | Filter1 => (bytes->ByteView.getI32(filterOffset) &&& 0xffff)->Int.toFloat
  | Filter2 => (bytes->ByteView.getI32(filterOffset) >>> 16 &&& 0xffff)->Int.toFloat
  | Pw => bytes->ByteView.getU32(field.offset) / 4294967296.
  }

let writeField = (bytes, field: Fields.t, x) => {
  let int = x => Float.toInt(Math.round(x))
  switch field.kind {
  | F32 => bytes->ByteView.setF32(field.offset, x)
  | I32 => bytes->ByteView.setI32(field.offset, int(x))
  | Filter1 =>
    let packed = bytes->ByteView.getI32(filterOffset)
    bytes->ByteView.setI32(filterOffset, packed &&& ~~~0xffff ||| int(x) &&& 0xffff)
  | Filter2 =>
    let packed = bytes->ByteView.getI32(filterOffset)
    bytes->ByteView.setI32(filterOffset, packed &&& 0xffff ||| (int(x) &&& 0xffff) << 16)
  | Pw => bytes->ByteView.setU32(field.offset, Math.round(x * 4294967296.))
  }
}

// Parameter values by endpoint id.
type values = Map.t<string, float>

let programValues = (bytes): values =>
  Fields.all->Array.map(field => (field.id, readField(bytes, field)))->Map.fromArray

let writeValues = (bytes, values: values) =>
  Fields.all->Array.forEach(field =>
    values->Map.get(field.id)->Option.forEach(x => writeField(bytes, field, x))
  )

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

let sendShapes = (pc, shapes) =>
  allTables->Array.forEach(table => sendShape(pc, table, shapes->getTable(table)))

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
