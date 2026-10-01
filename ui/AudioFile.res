// Reads the samples dropped onto the Shapes page. WAV and AIFF are parsed here, so that a
// wavetable's frames keep their exact length and its frame size can be read from the file;
// anything else goes to the browser's decoder (at 48 kHz).

type t = {
  // mono: the channels averaged
  samples: Float32Array.t,
  sampleRate: float,
  // the frame length a wavetable declares: Serum's "clm " chunk or Surge's "srge"
  frameSize: option<int>,
  // the first two channels apart, when there are two or more (impulse responses keep them)
  sides: option<(Float32Array.t, Float32Array.t)>,
}

let extensions = [
  ".wav",
  ".wave",
  ".aif",
  ".aiff",
  ".aifc",
  ".flac",
  ".mp3",
  ".ogg",
  ".oga",
  ".opus",
  ".m4a",
  ".aac",
]

// for a file dialog
let accept = extensions->Array.join(",")

let isAudio = filename => {
  let lower = filename->String.toLowerCase
  extensions->Array.some(ext => lower->String.endsWith(ext))
}

let setAt = TypedArray.set

//==============================================================================
// Bytes

type bytes = {view: DataView.t, size: int}

let tag = (b, off) =>
  if off + 4 > b.size {
    ""
  } else {
    String.fromCharCode(b.view->DataView.getUint8(off)) ++
    String.fromCharCode(b.view->DataView.getUint8(off + 1)) ++
    String.fromCharCode(b.view->DataView.getUint8(off + 2)) ++
    String.fromCharCode(b.view->DataView.getUint8(off + 3))
  }

// A chunk size, cut down to the bytes the file has left after 'off' (sizes can be placeholders
// such as 0xffffffff in files written while recording).
let chunkSize = (b, off, ~littleEndian) => {
  let size = Int.toFloat(b.view->DataView.getUint32(off, ~littleEndian))
  Float.toInt(Math.max(0., Math.min(size, Int.toFloat(b.size - off - 4))))
}

// Walks the chunks from 'off' to the end of the file.
let chunks = (b, off, ~littleEndian, f) => {
  let pos = ref(off)
  while pos.contents + 8 <= b.size {
    let id = tag(b, pos.contents)
    let size = chunkSize(b, pos.contents + 4, ~littleEndian)
    f(id, pos.contents + 8, size)
    pos := pos.contents + 8 + size + mod(size, 2)
  }
}

type encoding = Int(int) | Float(int)

// Mixes interleaved frames down to mono, or takes channel `only`. Integer samples take whole
// bytes (20 bits are read as 24, the low bits zero); 8-bit WAV is unsigned, 8-bit AIFF signed.
let decodeFrames = (b, ~offset, ~bytes, ~channels, ~encoding, ~littleEndian, ~unsigned8=false, ~only=?) => {
  let width = switch encoding {
  | Int(bits) => (bits + 7) / 8
  | Float(bits) => bits / 8
  }
  let block = width * channels
  let frames = block > 0 ? Math.Int.max(0, b.size - offset)->Math.Int.min(bytes) / block : 0
  let out = Float32Array.fromLength(frames)
  let read = off =>
    switch encoding {
    | Int(_) if width == 1 =>
      unsigned8
        ? Int.toFloat(b.view->DataView.getUint8(off) - 128) / 128.
        : Int.toFloat(b.view->DataView.getInt8(off)) / 128.
    | Int(_) if width == 2 => Int.toFloat(b.view->DataView.getInt16(off, ~littleEndian)) / 32768.
    | Int(_) if width == 3 =>
      let (b0, b1, b2) = (
        b.view->DataView.getUint8(off),
        b.view->DataView.getUint8(off + 1),
        b.view->DataView.getUint8(off + 2),
      )
      let (lo, hi) = littleEndian ? (b0, b2) : (b2, b0)
      let v = lo + (b1 << 8) + (hi << 16)
      Int.toFloat(v >= 0x800000 ? v - 0x1000000 : v) / 8388608.
    | Int(_) => Int.toFloat(b.view->DataView.getInt32(off, ~littleEndian)) / 2147483648.
    | Float(64) => b.view->DataView.getFloat64(off, ~littleEndian)
    | Float(_) => b.view->DataView.getFloat32(off, ~littleEndian)
    }
  switch only {
  | Some(c) =>
    for i in 0 to frames - 1 {
      out->setAt(i, read(offset + i * block + c * width))
    }
  | None =>
    let scale = 1. / Int.toFloat(Math.Int.max(1, channels))
    for i in 0 to frames - 1 {
      let sum = ref(0.)
      for c in 0 to channels - 1 {
        sum := sum.contents + read(offset + i * block + c * width)
      }
      out->setAt(i, sum.contents * scale)
    }
  }
  out
}

// The sound, from decode: the channels mixed (None) or one of them (Some(channel)).
let decoded = (decode: option<int> => Float32Array.t, ~channels, ~sampleRate, ~frameSize) => Ok({
  samples: decode(None),
  sampleRate,
  frameSize,
  // the first two channels of a file with two or more
  sides: channels >= 2 ? Some((decode(Some(0)), decode(Some(1)))) : None,
})

let supported = encoding =>
  switch encoding {
  | Int(bits) => bits >= 8 && bits <= 32
  | Float(bits) => bits == 32 || bits == 64
  }

//==============================================================================
// WAV

// Serum writes "<!>2048 ..." into a "clm " chunk.
let serumFrameSize = (b, off, size) => {
  let text = Array.fromInitializer(~length=Math.Int.min(size, 16), i =>
    String.fromCharCode(b.view->DataView.getUint8(off + i))
  )->Array.join("")
  if text->String.startsWith("<!>") {
    Int.fromString(text->String.slice(~start=3)->String.split(" ")->Array.getUnsafe(0))
  } else {
    None
  }
}

let readWav = (b): result<t, string> => {
  let format = ref(None)
  let data = ref(None)
  let frameSize = ref(None)
  chunks(b, 12, ~littleEndian=true, (id, off, size) =>
    switch id {
    | "fmt " if size >= 16 =>
      let code = b.view->DataView.getUint16(off, ~littleEndian=true)
      // WAVE_FORMAT_EXTENSIBLE: the real format is at the start of the sub-format GUID
      let code = code == 0xfffe && size >= 26 ? b.view->DataView.getUint16(off + 24, ~littleEndian=true) : code
      let channels = b.view->DataView.getUint16(off + 2, ~littleEndian=true)
      let rate = Int.toFloat(b.view->DataView.getUint32(off + 4, ~littleEndian=true))
      let bits = b.view->DataView.getUint16(off + 14, ~littleEndian=true)
      format := Some((code, channels, rate, bits))
    | "data" => data := Some((off, size))
    | "clm " => frameSize := serumFrameSize(b, off, size)
    | "srge" if size >= 8 => frameSize := Some(b.view->DataView.getInt32(off + 4, ~littleEndian=true))
    | _ => ()
    }
  )
  switch (format.contents, data.contents) {
  | (Some((code, channels, sampleRate, bits)), Some((offset, bytes))) =>
    let encoding = switch code {
    | 1 => Some(Int(bits))
    | 3 => Some(Float(bits))
    | _ => None
    }
    switch encoding {
    | Some(encoding) if supported(encoding) && channels > 0 && sampleRate > 0. =>
      let decode = only =>
        decodeFrames(b, ~offset, ~bytes, ~channels, ~encoding, ~littleEndian=true, ~unsigned8=true, ~only?)
      decoded(decode, ~channels, ~sampleRate, ~frameSize=frameSize.contents)
    | _ =>
      Error(`it's a kind of WAV that can't be read here (format ${Int.toString(code)}, ${Int.toString(bits)} bits)`)
    }
  | _ => Error("it's a WAV file without sound in it")
  }
}

//==============================================================================
// AIFF

// The 80-bit extended float AIFF stores its sample rate in.
let extended = (b, off) => {
  let e = b.view->DataView.getUint16(off, ~littleEndian=false)
  let exponent = Int.toFloat((e &&& 0x7fff) - 16383)
  let hi = Int.toFloat(b.view->DataView.getUint32(off + 2, ~littleEndian=false))
  let lo = Int.toFloat(b.view->DataView.getUint32(off + 6, ~littleEndian=false))
  let v = hi * Math.pow(2., ~exp=exponent - 31.) + lo * Math.pow(2., ~exp=exponent - 63.)
  (e &&& 0x8000) != 0 ? -.v : v
}

let readAiff = (b, ~compressed): result<t, string> => {
  let format = ref(None)
  let data = ref(None)
  chunks(b, 12, ~littleEndian=false, (id, off, size) =>
    switch id {
    | "COMM" if size >= 18 =>
      let channels = b.view->DataView.getInt16(off, ~littleEndian=false)
      let bits = b.view->DataView.getInt16(off + 6, ~littleEndian=false)
      let rate = extended(b, off + 8)
      let compression = compressed && size >= 22 ? tag(b, off + 18) : "NONE"
      format := Some((channels, bits, rate, compression))
    | "SSND" if size >= 8 =>
      let skip = b.view->DataView.getUint32(off, ~littleEndian=false)
      data := Some((off + 8 + skip, size - 8 - skip))
    | _ => ()
    }
  )
  switch (format.contents, data.contents) {
  | (Some((channels, bits, sampleRate, compression)), Some((offset, bytes))) =>
    let encoding = switch compression {
    | "NONE" | "twos" => Some((Int(bits), false))
    | "sowt" => Some((Int(bits), true))
    | "fl32" | "FL32" => Some((Float(32), false))
    | "fl64" | "FL64" => Some((Float(64), false))
    | _ => None
    }
    switch encoding {
    | Some((encoding, littleEndian)) if supported(encoding) && channels > 0 && sampleRate > 0. =>
      let decode = only => decodeFrames(b, ~offset, ~bytes, ~channels, ~encoding, ~littleEndian, ~only?)
      decoded(decode, ~channels, ~sampleRate, ~frameSize=None)
    | _ => Error(`it's a compressed AIFF ("${compression}"), which can't be read here`)
    }
  | _ => Error("it's an AIFF file without sound in it")
  }
}

// WAV and AIFF; None for anything else.
let parse = (bytes: Uint8Array.t): option<result<t, string>> => {
  let b = {
    view: DataView.fromBuffer(
      bytes->TypedArray.buffer,
      ~byteOffset=bytes->TypedArray.byteOffset,
      ~length=bytes->TypedArray.byteLength,
    ),
    size: bytes->TypedArray.byteLength,
  }
  switch (tag(b, 0), tag(b, 8)) {
  | ("RIFF", "WAVE") => Some(readWav(b))
  | ("FORM", "AIFF") => Some(readAiff(b, ~compressed=false))
  | ("FORM", "AIFC") => Some(readAiff(b, ~compressed=true))
  | _ => None
  }
}

//==============================================================================
// Everything else: the browser's decoder

type audioBuffer
type offlineContext
@new external offlineContext: (int, int, float) => offlineContext = "OfflineAudioContext"
@send
external decodeAudioData: (offlineContext, ArrayBuffer.t) => promise<audioBuffer> =
  "decodeAudioData"
@get external numberOfChannels: audioBuffer => int = "numberOfChannels"
@get external bufferRate: audioBuffer => float = "sampleRate"
@get external bufferLength: audioBuffer => int = "length"
@send external getChannelData: (audioBuffer, int) => Float32Array.t = "getChannelData"

let decodeInBrowser = async (bytes: Uint8Array.t) => {
  // decodeAudioData takes the buffer over, so it gets a copy
  let copy = TypedArray.copy(bytes)->TypedArray.buffer
  let buffer = await offlineContext(1, 1, 48000.)->decodeAudioData(copy)
  let channels = buffer->numberOfChannels
  let n = buffer->bufferLength
  let out = Float32Array.fromLength(n)
  for c in 0 to channels - 1 {
    let d = buffer->getChannelData(c)
    for i in 0 to n - 1 {
      out->setAt(i, ByteView.getUnsafe(out, i) + ByteView.getUnsafe(d, i) / Int.toFloat(channels))
    }
  }
  let sides = channels >= 2 ? Some((buffer->getChannelData(0), buffer->getChannelData(1))) : None
  {samples: out, sampleRate: buffer->bufferRate, frameSize: None, sides}
}

let decode = async (bytes, filename): result<t, string> =>
  switch parse(bytes) {
  | Some(Error(e)) => Error(`Couldn't read ${filename}: ${e}`)
  | Some(Ok(audio)) => Ok(audio)
  | None =>
    try {
      Ok(await decodeInBrowser(bytes))
    } catch {
    | _ => Error(`Couldn't decode ${filename}; WAV and AIFF files always work`)
    }
  }

// Reads and decodes a file the user picked or dropped.
let readFile = async file =>
  switch await Web.readBytes(file) {
  | Ok(bytes) =>
    // (reading a WAV or AIFF cut short in the wrong place can throw)
    try await decode(bytes, file->Web.fileName) catch {
    | JsExn(e) => Error(Web.readError(file, e))
    }
  | Error(e) => Error(e)
  }
