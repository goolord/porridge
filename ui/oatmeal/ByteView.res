// Typed reads and writes into byte arrays. Programs are little-endian; the VST fxp/fxb
// containers are big-endian. Unsigned 32-bit values are floats, since they don't fit an int.

type t = Uint8Array.t

type dataView
@new external dataView: (ArrayBuffer.t, int, int) => dataView = "DataView"
@send external getFloat32: (dataView, int, bool) => float = "getFloat32"
@send external setFloat32: (dataView, int, float, bool) => unit = "setFloat32"
@send external getInt32: (dataView, int, bool) => int = "getInt32"
@send external setInt32: (dataView, int, int, bool) => unit = "setInt32"
@send external getUint32: (dataView, int, bool) => float = "getUint32"
// Takes any number and stores ToUint32 of it, like `x >>> 0`.
@send external setUint32: (dataView, int, float, bool) => unit = "setUint32"

let view = (u: t) =>
  dataView(u->TypedArray.buffer, u->TypedArray.byteOffset, u->TypedArray.byteLength)

let getF32 = (u, off) => u->view->getFloat32(off, true)
let setF32 = (u, off, x) => u->view->setFloat32(off, x, true)
let getI32 = (u, off) => u->view->getInt32(off, true)
let setI32 = (u, off, x) => u->view->setInt32(off, x, true)
let getU32 = (u, off) => u->view->getUint32(off, true)
let setU32 = (u, off, x) => u->view->setUint32(off, x, true)

let getF32BE = (u, off) => u->view->getFloat32(off, false)
let getI32BE = (u, off) => u->view->getInt32(off, false)

let scratch = Uint8Array.fromLength(4)

// `x >>> 0`: the uint32 that x wraps to (NaN and infinities give 0).
let toUint32 = x => {
  scratch->setU32(0, x)
  scratch->getU32(0)
}

let float32OfBits = bits => {
  scratch->setI32(0, bits)
  scratch->getF32(0)
}

let bitsOfFloat32 = x => {
  scratch->setF32(0, x)
  scratch->getI32(0)
}

// Unchecked element access, for the inner loops over shapes.
@get_index external getUnsafe: (Float32Array.t, int) => float = ""
@set_index external setUnsafe: (Float32Array.t, int, float) => unit = ""
@get_index external byteAt: (t, int) => int = ""

// target.set(source, offset)
@send external blit: (t, t, int) => unit = "set"
