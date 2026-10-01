// Oatmeal (Fuzzpilz, release 38-1) preset / bank file formats.
//
// Everything is normalised to the current (v38) program layout: a 10376-byte Uint8Array
//   [0..12)      magic 'Oatm','eal.','prgm' as little-endian dwords (bytes "mtaO.laemgrp")
//   [12..16)     int32 version = 38
//   [16..10352)  program struct (all multi-byte values little-endian; float32 / int32 / uint32)
//   [10352..10376) name, 24 bytes, NUL-terminated (Latin-1)
// Supported inputs: native program (.omp, "Oatmeal.prgm"), native bank (.omb, "Oatmeal.bank"),
// VST .fxp (FPCh opaque chunk, FxCk parameter list), VST .fxb (FBCh opaque chunk, FxBk list of FxCk),
// the factory bank oatmealprs.dat (= a v38 .omb).  Program versions 31..38 are converted exactly like
// Oatmeal.dll's setChunk (0x1004f880) does; see docs/internals/presets_params.md.

open ByteView

let currentVersion = 38
let programSize = 10376
let bankPrograms = 64
let bankHeaderSize = 16
let bankSize = bankHeaderSize + bankPrograms * programSize // 664080
let nameOffset = 10352
let nameLength = 24

// magic dwords as stored (little-endian ASCII: 'Oatm' is the dword 0x4f61746d -> bytes 6d 74 61 4f)
let magicOatm = 0x4f61746d
let magicEal = 0x65616c2e
let magicPrgm = 0x7072676d
let magicBank = 0x62616e6b

// The table-like regions of the program struct.
type table =
  | Wave1 // float[512]  user waveform osc 1 (-1..1)
  | Wave2 // float[512]  user waveform osc 2
  | LfoShape1 // float[512]  LFO 1 user shape (0..1)
  | LfoShape2 // float[512]  LFO 2 user shape
  | VelocityCurve // float[64]
  | AftertouchCurve // float[64]

let allTables = [Wave1, Wave2, LfoShape1, LfoShape2, VelocityCurve, AftertouchCurve]

let tableOffset = table =>
  switch table {
  | Wave1 => 32
  | Wave2 => 2080
  | LfoShape1 => 4136
  | LfoShape2 => 6184
  | VelocityCurve => 9596
  | AftertouchCurve => 9852
  }

let tableLength = table =>
  switch table {
  | Wave1 | Wave2 | LfoShape1 | LfoShape2 => 512
  | VelocityCurve | AftertouchCurve => 64
  }

// Old program layouts accepted by the DLL.  All versions share the v38 field offsets; older versions
// are simply shorter (fields were only ever appended), so conversion = "defaults, then memcpy the old
// struct over offsets [16, 16+copy)".  size = minimal chunk size the DLL accepts (a program chunk is
// 16 header + copy + 24 name (+16 unused for v33+)); name = byte offset of the 24-byte name.
// From setChunk 0x1004f880 / converters 0x10052c20..0x10052d40 (rep movsd counts 0x8fe,0x900,0x944,
// 0x948,0x94a,0xa12,0xa12 dwords).
type layout = {size: int, copy: int, name: int}

let versionLayout = version =>
  switch version {
  | 31 => Some({size: 9248, copy: 9208, name: 9224})
  | 32 => Some({size: 9256, copy: 9216, name: 9232})
  | 33 => Some({size: 9528, copy: 9488, name: 9504})
  | 34 => Some({size: 9544, copy: 9504, name: 9520})
  | 35 => Some({size: 9552, copy: 9512, name: 9528})
  | 36 | 37 => Some({size: 10352, copy: 10312, name: 10328})
  | 38 => Some({size: 10376, copy: 10336, name: 10352})
  | _ => None
  }

// Mod-envelope (M1/M2) target index remap applied to programs of version <= 34 (0x10052b70): the DLL maps
// old index -> FourCC (table 0x1007dc10: NULL CUT1 CUT2 RESO AMP1 AMP2 AMPN PCH2 PCHN PWW1 PWR1 PWD1 PWW2 PWR2
// PWD2 'PAN ' NRES LF1S LF2S LF1D LF2D, 0) -> new index (0x10052860).  Net effect: target "1 pitch" (PCH1,
// new index 7) did not exist before v35, old indices 7..20 move up by one.  Old index 21 has no FourCC and
// stays 21 (DLL quirk).  The XY remap (0x1007db40 / 0x10052660) is the identity for all 18 old indices.
// CC targets did not exist before v36.  Values outside the tables are left unchanged.
let modTargetRemapV34 = [
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  21,
]
let xyTargetRemapV34 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
let modTargetOffsets = [9392, 9396, 9400, 9404, 9488, 9492, 9496, 9500] // M1 target 1..4, M2 target 1..4
let xyTargetOffsets = [9160, 9164, 9168, 9172, 9196, 9200, 9204, 9208] // X target 1..4, Y target 1..4

// Non-zero dwords written by the DLL's default-program initialiser 0x10052d70 (outside the tables).
// Everything else in [16, 10352) is 0, except the tables (see makeDefaultProgram) and three padding
// areas the initialiser never touches (16..32, 4128..4136, 8296..8300, 10348..10352), which we zero.
// "derived" fields are recomputed by the synth every process() call (see derivedFields); their stored
// values are what the DLL computes at 44100 Hz.
type dword = F(float) | I(int) | U(float)

let defaultDwords = [
  (8232, F(4.)), // amp env +0 fade time
  (8236, F(5.)), // p60:Attack
  (8244, F(40.)), // p62:Decay 1
  (8248, F(1000.)), // p64:Decay 2
  (8252, F(50.)), // p66:Release
  (8256, F(20.)), // p66:Release
  (8260, F(0.0056689344)), // amp env +28 derived coef
  (8264, F(0.0045351475)), // amp env +32 derived coef
  (8272, F(1.)), // amp env +40 derived coef
  (8276, F(1.)), // p63:Breakpoint
  (8280, F(0.99998426)), // amp env +48 derived coef
  (8284, F(0.5)), // p65:Sustain
  (8288, F(0.9968721)), // amp env +56 derived coef
  (8292, F(0.993754)), // amp env +60 derived coef
  (8300, F(4.)), // filter env +0 fade time
  (8304, F(5.)), // p45:F attack
  (8312, F(40.)), // p47:F decay 1
  (8316, F(1000.)), // p49:F decay 2
  (8320, F(50.)), // p51:F release
  (8324, F(20.)), // p51:F release
  (8328, F(0.0056689344)), // filter env +28 derived coef
  (8332, F(0.0045351475)), // filter env +32 derived coef
  (8340, F(1.)), // filter env +40 derived coef
  (8344, F(1.)), // p48:F breakpoint
  (8348, F(0.99998426)), // filter env +48 derived coef
  (8352, F(0.5)), // p50:F sustain
  (8356, F(0.9968721)), // filter env +56 derived coef
  (8360, F(0.993754)), // filter env +60 derived coef
  (8364, F(4.)), // filter2 env (derived) +0 fade time
  (8368, F(5.)), // filter2 env (derived) +4
  (8376, F(40.)), // filter2 env (derived) +12
  (8380, F(1000.)), // filter2 env (derived) +16
  (8384, F(50.)), // filter2 env (derived) +20
  (8388, F(20.)), // filter2 env (derived) +24
  (8392, F(0.0056689344)), // filter2 env (derived) +28 derived coef
  (8396, F(0.0045351475)), // filter2 env (derived) +32 derived coef
  (8404, F(1.)), // filter2 env (derived) +40 derived coef
  (8408, F(1.)), // filter2 env (derived) +44
  (8412, F(0.99998426)), // filter2 env (derived) +48 derived coef
  (8416, F(0.5)), // filter2 env (derived) +52
  (8420, F(0.9968721)), // filter2 env (derived) +56 derived coef
  (8424, F(0.993754)), // filter2 env (derived) +60 derived coef
  (8432, F(0.5)), // p43:Cutoff
  (8448, F(0.29166666)), // p55:F split
  (8452, F(2.)), // p56:F envspeed
  (8456, F(0.5)), // p54:F mix
  (8484, U(2147483648.)), // p3:1 Pulsewidth (uint32 phase 0.5*2^32)
  (8488, U(2147483648.)), // p9:2 Pulsewidth (uint32 phase 0.5*2^32)
  (8508, F(1.)), // p1:1 Amp
  (8516, F(1.)), // p12:Transpose
  (8544, I(1)), // p19:LFO 1 unit
  (8552, I(2)), // p23:LFO 1 mode
  (8556, F(20.)), // p21:LFO 1 speed
  (8580, I(1)), // p30:LFO 1 unit
  (8588, I(2)), // p34:LFO 2 mode
  (8592, F(25.)), // p32:LFO 2 speed
  (8624, I(4)), // p69:C voices
  (8628, F(0.02)), // p70:C speed
  (8632, F(4.)), // p71:C delay
  (8636, F(8.)), // p72:C depth
  (8640, F(0.8)), // p74:C mix
  (8652, I(5)), // p76:D unit
  (8668, F(0.5)), // p84:D input pan
  (8676, F(3.)), // p80:D length L
  (8680, F(0.7)), // p82:D feedbk L
  (8684, F(3.)), // p81:D length R
  (8688, F(0.7)), // p83:D feedbk R
  (8692, F(0.7)), // p86:D lowpass
  (8700, F(1.)), // p88:D dry out
  (8704, F(0.8)), // p89:D wet out
  (8712, F(30.)), // p91:R size
  (8716, F(1.2)), // p92:R length
  (8720, F(0.8)), // p93:R dullness
  (8724, F(0.2)), // p94:R brightness
  (8728, F(1.)), // p95:R dry out
  (8732, F(0.2)), // p96:R wet out
  (8736, F(-0.72256637)), // p97:R 1
  (8740, F(-2.3561945)), // p98:R 2
  (8744, F(0.84823006)), // p99:R 3
  (8748, F(2.261947)), // p100:R rotation
  (8756, F(0.5)), // p102:R early mix
  (8760, I(1)), // p103:Voice mode
  (8764, I(8)), // p104:Max polyphony
  (8772, I(1)), // p106:Glide mode
  (8776, F(0.1)), // p107:Output gain
  (8780, F(0.65)), // p108:Velocity sensitivity
  (8784, I(2)), // p109:Aftertouch mode
  (8800, F(1.)), // p113:Random amp
  (8804, F(1.)), // p114:Random freq
  (8812, F(1.)), // p116:Osc phase rand
  (8824, F(1.)), // p119:PWM phase rand
  (8840, I(1)), // p123:LFO retrigger
  (8848, I(8)), // p130:Arp unit
  (8852, I(1)), // p131:Arp quantize
  (8856, F(1.)), // p132:Arp step
  (8860, I(1)), // p133:Arp step 1
  (8872, I(1)), // p136:Arp step 4
  (8884, I(1)), // p139:Arp step 7
  (8924, I(7)), // p149:Arp pattern length
  (8988, F(-12.)), // p165:P start
  (8992, F(0.5)), // derived pitch env
  (8996, F(20.)), // p166:P attack
  (9004, F(12.)), // p167:P peak
  (9008, F(2.)), // derived pitch env
  (9012, F(100.)), // p168:P decay
  (9016, F(1.)), // derived pitch env
  (9024, F(1.)), // derived pitch env
  (9032, F(1.)), // derived pitch env
  (9060, F(440.)), // p178:Tune main
  (9064, F(2.)), // p179:Octave
  (9068, F(0.6931472)), // derived ln(octave)
  (9076, F(-9.)), // p181:Pan reference
  (9128, F(12.)), // p194:Bend range
  (9232, F(1000.)), // p218:EQ 1 freq
  (9236, F(1000.)), // p219:EQ 2 freq
  (9240, F(1000.)), // p220:EQ 3 freq
  (9244, F(1000.)), // p221:EQ 4 freq
  (9248, F(1000.)), // p222:EQ 5 freq
  (9272, F(1.)), // p228:EQ 1 slope
  (9276, F(1.)), // p229:EQ 2 slope
  (9280, F(1.)), // p230:EQ 3 slope
  (9284, F(1.)), // p231:EQ 4 slope
  (9288, F(1.)), // p232:EQ 5 slope
  (9312, F(4.)), // mod env 1 +0 fade time
  (9316, F(5.)), // p238:M1 attack
  (9324, F(40.)), // p240:M1 decay 1
  (9328, F(1000.)), // p242:M1 decay 2
  (9332, F(50.)), // p244:M1 release
  (9336, F(20.)), // p244:M1 release
  (9340, F(0.0056689344)), // mod env 1 +28 derived coef
  (9344, F(0.0045351475)), // mod env 1 +32 derived coef
  (9352, F(1.)), // mod env 1 +40 derived coef
  (9356, F(1.)), // p241:M1 breakpoint
  (9360, F(0.99998426)), // mod env 1 +48 derived coef
  (9364, F(0.5)), // p243:M1 sustain
  (9368, F(0.9968721)), // mod env 1 +56 derived coef
  (9372, F(0.993754)), // mod env 1 +60 derived coef
  (9408, F(4.)), // mod env 2 +0 fade time
  (9412, F(5.)), // p254:M2 attack
  (9420, F(40.)), // p256:M2 decay 1
  (9424, F(1000.)), // p258:M2 decay 2
  (9428, F(50.)), // p260:M2 release
  (9432, F(20.)), // p260:M2 release
  (9436, F(0.0056689344)), // mod env 2 +28 derived coef
  (9440, F(0.0045351475)), // mod env 2 +32 derived coef
  (9448, F(1.)), // mod env 2 +40 derived coef
  (9452, F(1.)), // p257:M2 breakpoint
  (9456, F(0.99998426)), // mod env 2 +48 derived coef
  (9460, F(0.5)), // p259:M2 sustain
  (9464, F(0.9968721)), // mod env 2 +56 derived coef
  (9468, F(0.993754)), // mod env 2 +60 derived coef
  (9528, I(1)), // p270:MIDI channel 1
  (9532, I(1)), // p271:MIDI channel 2
  (9536, I(1)), // p272:MIDI channel 3
  (9540, I(1)), // p273:MIDI channel 4
  (9544, I(1)), // p274:MIDI channel 5
  (9548, I(1)), // p275:MIDI channel 6
  (9552, I(1)), // p276:MIDI channel 7
  (9556, I(1)), // p277:MIDI channel 8
  (9560, I(1)), // p278:MIDI channel 9
  (9564, I(1)), // p279:MIDI channel 10
  (9568, I(1)), // p280:MIDI channel 11
  (9572, I(1)), // p281:MIDI channel 12
  (9576, I(1)), // p282:MIDI channel 13
  (9580, I(1)), // p283:MIDI channel 14
  (9584, I(1)), // p284:MIDI channel 15
  (9588, I(1)), // p285:MIDI channel 16
  (9592, I(1)), // p286:Sustain pedal
  (10328, I(1)), // p124:U voices
  (10332, F(1.)), // p125:U detune
  (10336, F(0.25)), // p126:U spread
]

type region = {from: int, @as("to") until: int, what: string}

// Fields of the struct that the DLL recomputes from other fields (live copy, every process() call).
// Stored values in files are stale snapshots (computed at the saving machine's sample rate).
let derivedFields = [
  {
    from: 8260,
    until: 8276,
    what: "amp env coefficients (+0x1c,+0x20 float, +0x24 int hold samples, +0x28)",
  },
  {from: 8280, until: 8284, what: "amp env decay-2 coefficient (+0x30)"},
  {from: 8288, until: 8296, what: "amp env release coefficients (+0x38,+0x3c)"},
  {from: 8328, until: 8344, what: "filter env coefficients"},
  {from: 8348, until: 8352, what: "filter env coef"},
  {from: 8356, until: 8364, what: "filter env release coefs"},
  {
    from: 8364,
    until: 8428,
    what: "filter-2 env = filter env times * F envspeed, breakpoint/sustain copies, coefficients",
  },
  {from: 8992, until: 8996, what: "pitch env start ratio 2^(start/12) (0 if start <= -48)"},
  {from: 9000, until: 9004, what: "pitch env attack increment"},
  {from: 9008, until: 9012, what: "pitch env peak ratio octave^(peak/12)"},
  {from: 9016, until: 9020, what: "pitch env decay multiplier"},
  {from: 9024, until: 9028, what: "pitch env sustain ratio octave^(sustain/12)"},
  {from: 9032, until: 9036, what: "pitch env release multiplier octave^(release/(12*SR))"},
  {from: 9068, until: 9072, what: "ln(Octave)"},
  {from: 9340, until: 9356, what: "mod env 1 coefficients"},
  {from: 9360, until: 9364, what: "mod env 1 coef"},
  {from: 9368, until: 9376, what: "mod env 1 release coefs"},
  {from: 9436, until: 9452, what: "mod env 2 coefficients"},
  {from: 9456, until: 9460, what: "mod env 2 coef"},
  {from: 9464, until: 9472, what: "mod env 2 release coefs"},
]

// ---------------------------------------------------------------------------------------------------
// small helpers

exception Invalid(string)

let fail = message => throw(Invalid(message))

// Runs a conversion, turning its Invalid exception into an Error.
let guard = f =>
  try Ok(f()) catch {
  | Invalid(message) => Error(message)
  }

let latin1 = (bytes: t) => {
  let n = TypedArray.length(bytes)
  let rec go = (i, s) =>
    if i >= n {
      s
    } else {
      switch bytes->byteAt(i) {
      | 0 => s
      | c => go(i + 1, s ++ String.fromCharCode(c))
      }
    }
  go(0, "")
}

let putLatin1 = (bytes: t, offset, s, maxLength) =>
  for i in 0 to Math.Int.min(String.length(s), maxLength) - 1 {
    bytes->TypedArray.set(offset + i, String.charCodeAtUnsafe(s, i) &&& 0xff)
  }

// Program name (up to the first NUL of the 24-byte field).
let getName = prog =>
  prog->TypedArray.subarray(~start=nameOffset, ~end=nameOffset + nameLength)->latin1

// Set name (Latin-1, truncated to 23 chars, NUL padded).
let setName = (prog, name) => {
  prog->TypedArray.fill(0, ~start=nameOffset, ~end=nameOffset + nameLength)->ignore
  prog->putLatin1(nameOffset, name, nameLength - 1)
}

let readTable = (prog, table) => {
  let offset = tableOffset(table)
  Float32Array.fromLength(tableLength(table))->TypedArray.mapWithIndex((_, i) =>
    prog->getF32(offset + 4 * i)
  )
}

// Missing values are written as 0.
let writeTable = (prog, table, values) => {
  let offset = tableOffset(table)
  for i in 0 to tableLength(table) - 1 {
    prog->setF32(offset + 4 * i, values->TypedArray.get(i)->Option.getOr(0.))
  }
}

// Copies of the table regions of a v38 program.
type tables = {
  wave1: Float32Array.t,
  wave2: Float32Array.t,
  lfoShape1: Float32Array.t,
  lfoShape2: Float32Array.t,
  velocityCurve: Float32Array.t,
  aftertouchCurve: Float32Array.t,
}

let getTable = (tables, table) =>
  switch table {
  | Wave1 => tables.wave1
  | Wave2 => tables.wave2
  | LfoShape1 => tables.lfoShape1
  | LfoShape2 => tables.lfoShape2
  | VelocityCurve => tables.velocityCurve
  | AftertouchCurve => tables.aftertouchCurve
  }

let setTable = (tables, table, data) =>
  switch table {
  | Wave1 => {...tables, wave1: data}
  | Wave2 => {...tables, wave2: data}
  | LfoShape1 => {...tables, lfoShape1: data}
  | LfoShape2 => {...tables, lfoShape2: data}
  | VelocityCurve => {...tables, velocityCurve: data}
  | AftertouchCurve => {...tables, aftertouchCurve: data}
  }

let tablesFrom = f => {
  wave1: f(Wave1),
  wave2: f(Wave2),
  lfoShape1: f(LfoShape1),
  lfoShape2: f(LfoShape2),
  velocityCurve: f(VelocityCurve),
  aftertouchCurve: f(AftertouchCurve),
}

let extractTables = prog => tablesFrom(table => readTable(prog, table))

type kind =
  | @as("program") Program
  | @as("bank") Bank

let writeHeader = (bytes, kind, version) => {
  bytes->setI32(0, magicOatm)
  bytes->setI32(4, magicEal)
  bytes->setI32(
    8,
    switch kind {
    | Program => magicPrgm
    | Bank => magicBank
    },
  )
  bytes->setI32(12, version)
}

type header = {kind: kind, version: int}

// The kind and version of a native chunk, or None if the Oatmeal magic is absent.
let readNativeHeader = bytes =>
  if (
    TypedArray.length(bytes) < 16 || bytes->getI32(0) != magicOatm || bytes->getI32(4) != magicEal
  ) {
    None
  } else {
    let version = bytes->getI32(12)
    switch bytes->getI32(8) {
    | m if m == magicPrgm => Some({kind: Program, version})
    | m if m == magicBank => Some({kind: Bank, version})
    | _ => None
    }
  }

// ---------------------------------------------------------------------------------------------------
// defaults

let defaultProgram = Lazy.make(() => {
  let p = Uint8Array.fromLength(programSize)
  writeHeader(p, Program, currentVersion)
  defaultDwords->Array.forEach(((offset, value)) =>
    switch value {
    | F(x) => p->setF32(offset, x)
    | U(x) => p->setU32(offset, x)
    | I(x) => p->setI32(offset, x)
    }
  )
  // tables: wave1 = wave2 = sin(k*pi_f/256) ; LFO shapes = (sin+1)/2 ; velocity and aftertouch curve = k * (float)(1/63)
  let piF = Math.fround(Math.Constants.pi)
  let inv63F = Math.fround(1. / 63.)
  for k in 0 to 511 {
    let s = Math.sin(Int.toFloat(k) * piF / 256.) // x87: fild k; fmul pi_f; fmul 1/256; fsin (exact products)
    p->setF32(tableOffset(Wave1) + 4 * k, s)
    p->setF32(tableOffset(Wave2) + 4 * k, s)
    // x87 keeps sin() in 80-bit precision before (s+1)*0.5; only k=384 (s ~ -1) differs from double math
    let l = k == 384 ? 4.29905134928521e-15 /* bits 0x279ae3c0 */ : (s + 1.) * 0.5
    p->setF32(tableOffset(LfoShape1) + 4 * k, l)
    p->setF32(tableOffset(LfoShape2) + 4 * k, l)
  }
  for k in 0 to 63 {
    p->setF32(tableOffset(VelocityCurve) + 4 * k, Int.toFloat(k) * inv63F)
    p->setF32(tableOffset(AftertouchCurve) + 4 * k, Int.toFloat(k) * inv63F)
  }
  p
})

// Exact reproduction of the DLL's default-program initialiser 0x10052d70 (+ v38 header + name).
// This is also the "Init" program (default_prog.bin) apart from padding.
let makeDefaultProgram = name => {
  let out = Lazy.get(defaultProgram)->TypedArray.copy
  setName(out, name)
  out
}

// ---------------------------------------------------------------------------------------------------
// program conversion

type program = {name: string, bytes: Uint8Array.t}
type converted = {bytes: Uint8Array.t, name: string, version: int, warnings: array<string>}
type convertedBank = {version: int, programs: array<program>, warnings: array<string>}

let remapTargetsV34 = p => {
  let remap = (offsets, table) =>
    offsets->Array.forEach(offset =>
      table[p->getI32(offset)]->Option.forEach(target => p->setI32(offset, target))
    )
  remap(modTargetOffsets, modTargetRemapV34)
  remap(xyTargetOffsets, xyTargetRemapV34)
}

// Convert one native program chunk ("Oatmeal.prgm", versions 31..38) to a v38 program.
// Mirrors setChunk(isPreset=true) 0x1004f880:
//   v38 (or newer, with ~allowNewer): raw copy of min(len, 10376) bytes (over the default program here;
//       the DLL copies over whatever program was in the slot, so a short v38 chunk keeps stale data there).
//   v31..v37: len must be >= layout size else error ("Not enough data!"); name = 24 bytes at
//       layout.name; struct = defaults (0x10052d70) then bytes [16, 16+copy) of the source; v<=34 remaps
//       M1/M2 target indices (modTargetRemapV34).
// The header is always rewritten to 'Oatmeal.prgm' v38 (the DLL leaves the slot's old header in place).
let convertProgram = (src, ~allowNewer) => {
  let version = switch readNativeHeader(src) {
  | Some({kind: Program, version}) => version
  | _ => fail("not an Oatmeal program chunk (magic mismatch)")
  }
  let v = Int.toString(version)
  let warnings = []
  if version > currentVersion {
    if !allowNewer {
      fail(`program version ${v} is newer than 38`)
    }
    warnings->Array.push(
      `version ${v} > 38 loaded as raw v38 (DLL asks "Try loading the program anyway?")`,
    )
  }
  if version < 31 {
    fail(`program version ${v} < 31 is not supported by Oatmeal 38`)
  }
  let out = makeDefaultProgram("")
  let length = TypedArray.length(src)
  switch versionLayout(version) {
  | Some(layout) if version < currentVersion =>
    if length < layout.size {
      fail(
        `Not enough data! v${v} program needs ${Int.toString(
            layout.size,
          )} bytes, got ${Int.toString(length)}`,
      )
    }
    out->blit(src->TypedArray.subarray(~start=16, ~end=16 + layout.copy), 16)
    out->blit(
      src->TypedArray.subarray(~start=layout.name, ~end=layout.name + nameLength),
      nameOffset,
    )
    if version <= 34 {
      remapTargetsV34(out)
    }
  | _ =>
    let n = Math.Int.min(length, programSize)
    if n < programSize {
      warnings->Array.push(
        `short v38 chunk (${Int.toString(
            n,
          )} bytes); remaining bytes taken from the default program`,
      )
    }
    out->blit(src->TypedArray.subarray(~start=16, ~end=n), 16)
  }
  writeHeader(out, Program, currentVersion)
  {bytes: out, name: getName(out), version, warnings}
}

// Convert a native bank chunk ("Oatmeal.bank") to 64 v38 programs.
// Layout: 16-byte bank header (magic 'Oatm','eal.','bank', int version), then 64 programs of
// layout size bytes each, each with its own 16-byte program header (ignored by the DLL:
// the bank version decides the layout).  The DLL needs len >= 16 + 64*size for v31..v37 (else nothing
// is loaded); a v38 bank is raw-copied (min(len, 664080) bytes).
// ~lenient: accept truncated banks, returning only the complete programs (+ warning).
let convertBank = (src, ~lenient) => {
  let version = switch readNativeHeader(src) {
  | Some({kind: Bank, version}) => version
  | _ => fail("not an Oatmeal bank chunk (magic mismatch)")
  }
  let v = Int.toString(version)
  let layout = switch versionLayout(version) {
  | Some(layout) => layout
  | None => fail(`bank version ${v} not supported ("Version mismatch")`)
  }
  let length = TypedArray.length(src)
  let need = bankHeaderSize + bankPrograms * layout.size
  let warnings = []
  let count = if length < need {
    let complete = Math.Int.max(0, (length - bankHeaderSize) / layout.size)
    if !lenient && version != currentVersion {
      fail(
        `Not enough data! v${v} bank needs ${Int.toString(need)} bytes, got ${Int.toString(
            length,
          )}`,
      )
    }
    warnings->Array.push(
      `truncated bank: ${Int.toString(length)} of ${Int.toString(need)} bytes, ${Int.toString(
          complete,
        )} complete programs`,
    )
    complete
  } else {
    bankPrograms
  }
  let programs = Array.fromInitializer(~length=count, k => {
    let offset = bankHeaderSize + k * layout.size
    let chunk = src->TypedArray.slice(~start=offset, ~end=offset + layout.size)
    writeHeader(chunk, Program, version) // the DLL converts by bank version, not by program header
    let {name, bytes} = convertProgram(chunk, ~allowNewer=false)
    {name, bytes}
  })
  {version, programs, warnings}
}

// ---------------------------------------------------------------------------------------------------
// VST fxp / fxb containers (big-endian headers)

type rec fx = {
  fxMagic: string,
  byteSize: int,
  formatVersion: int,
  fxID: string,
  fxVersion: int,
  count: int,
  body: fxBody,
}
and fxBody =
  // FPCh: opaque program chunk
  | ProgramChunk({name: string, chunkSize: int, chunk: Uint8Array.t})
  // FxCk: parameter list
  | ProgramParams({name: string, params: array<float>})
  // FBCh: opaque bank chunk; currentProgram is VST 2.4 fxb v2 only (junk in many files)
  | BankChunk({currentProgram: int, chunkSize: int, chunk: Uint8Array.t})
  // FxBk: list of FxCk programs
  | BankParams(array<fx>)

let fourcc = (bytes, offset) =>
  String.fromCharCodeMany([
    bytes->byteAt(offset),
    bytes->byteAt(offset + 1),
    bytes->byteAt(offset + 2),
    bytes->byteAt(offset + 3),
  ])

// Parse a VST fxp/fxb container.
let rec readFx = bytes => {
  let length = TypedArray.length(bytes)
  if length < 28 || fourcc(bytes, 0) != "CcnK" {
    fail("not a VST fxp/fxb file")
  }
  let count = bytes->getI32BE(24)
  let range = (start, end) => bytes->TypedArray.subarray(~start, ~end=Math.Int.min(length, end))
  let fxMagic = fourcc(bytes, 8)
  let body = switch fxMagic {
  | "FPCh" =>
    let chunkSize = bytes->getI32BE(56)
    ProgramChunk({name: latin1(range(28, 56)), chunkSize, chunk: range(60, 60 + chunkSize)})
  | "FxCk" =>
    let n = Math.Int.max(0, Math.Int.min(count, (length - 56) / 4))
    ProgramParams({
      name: latin1(range(28, 56)),
      params: Array.fromInitializer(~length=n, i => bytes->getF32BE(56 + 4 * i)),
    })
  | "FBCh" =>
    let chunkSize = bytes->getI32BE(156)
    BankChunk({currentProgram: bytes->getI32BE(28), chunkSize, chunk: range(160, 160 + chunkSize)})
  | "FxBk" =>
    // 28 + future[128], then the programs back to back
    let rec programs = (k, offset, acc) =>
      if k >= count || offset + 60 > length {
        acc
      } else {
        let size = 56 + 4 * bytes->getI32BE(offset + 24)
        programs(k + 1, offset + size, [...acc, readFx(range(offset, offset + size))])
      }
    BankParams(programs(0, 156, []))
  | magic => fail("unknown fx magic " ++ magic)
  }
  {
    fxMagic,
    byteSize: bytes->getI32BE(4),
    formatVersion: bytes->getI32BE(12),
    fxID: fourcc(bytes, 16),
    fxVersion: bytes->getI32BE(20),
    count,
    body,
  }
}

// Program from a VST parameter list (FxCk): Init program + setParameter(i, v) for each param in order.
let programFromParams = (values, name) => {
  let p = makeDefaultProgram(name)
  values->Array.forEachWithIndex((v, i) =>
    if i < OatmealParams.paramCount {
      OatmealParams.setParamNormalized(p, i, v)
    }
  )
  p
}

// ---------------------------------------------------------------------------------------------------
// top-level

type container =
  | @as("native") Native
  | @as("fxp") Fxp
  | @as("fxb") Fxb
  | @as("fxp-params") FxpParams
  | @as("fxb-params") FxbParams

type parsed = {
  kind: kind,
  container: container,
  version: int,
  programs: array<program>,
  warnings: array<string>,
}

let parseChunk = (chunk, container, warnings, ~lenient, ~allowNewer) =>
  switch readNativeHeader(chunk) {
  | None => fail("Oops! Magic mismatch (not an Oatmeal chunk)")
  | Some({kind: Program, version}) =>
    let r = convertProgram(chunk, ~allowNewer)
    {
      kind: Program,
      container,
      version,
      programs: [{name: r.name, bytes: r.bytes}],
      warnings: Array.concat(warnings, r.warnings),
    }
  | Some({kind: Bank, version}) =>
    let b = convertBank(chunk, ~lenient)
    {
      kind: Bank,
      container,
      version,
      programs: b.programs,
      warnings: Array.concat(warnings, b.warnings),
    }
  }

// Parse any supported file into v38 programs.
// ~lenient (default true): salvage complete programs from truncated banks (e.g. Oatmeal_Emdot1.fxb).
let parseFile = (bytes, ~lenient=true, ~allowNewer=false) =>
  guard(() =>
    if TypedArray.length(bytes) < 4 || fourcc(bytes, 0) != "CcnK" {
      parseChunk(bytes, Native, [], ~lenient, ~allowNewer)
    } else {
      let fx = readFx(bytes)
      let warnings =
        fx.fxID == "FzOm"
          ? []
          : [`fxID is ${JSON.Encode.string(fx.fxID)->JSON.stringify}, not FzOm`]
      let truncated = (chunk, chunkSize) => {
        let n = TypedArray.length(chunk)
        n < chunkSize
          ? [
              ...warnings,
              `file truncated: chunk has ${Int.toString(n)} of ${Int.toString(chunkSize)} bytes`,
            ]
          : warnings
      }
      let fromParams = p =>
        switch p.body {
        | ProgramParams({name, params}) => {name, bytes: programFromParams(params, name)}
        | _ => fail(`unexpected ${p.fxMagic} program in an FxBk bank`)
        }
      switch fx.body {
      | ProgramParams(_) => {
          kind: Program,
          container: FxpParams,
          version: currentVersion,
          programs: [fromParams(fx)],
          warnings,
        }
      | BankParams(programs) => {
          kind: Bank,
          container: FxbParams,
          version: currentVersion,
          programs: programs->Array.map(fromParams),
          warnings,
        }
      | ProgramChunk({chunk, chunkSize}) =>
        parseChunk(chunk, Fxp, truncated(chunk, chunkSize), ~lenient, ~allowNewer)
      | BankChunk({chunk, chunkSize}) =>
        parseChunk(chunk, Fxb, truncated(chunk, chunkSize), ~lenient, ~allowNewer)
      }
    }
  )

// ---------------------------------------------------------------------------------------------------
// writers (always v38)

// Native program file (.omp) = the v38 chunk itself.
let writeProgramChunk = prog => {
  let out = prog->TypedArray.slice(~start=0, ~end=programSize)
  writeHeader(out, Program, currentVersion)
  out
}

// Native bank (.omb): header + 64 programs (missing programs are filled with default programs named "Init <k>").
let writeBankChunk = programs => {
  let out = Uint8Array.fromLength(bankSize)
  writeHeader(out, Bank, currentVersion)
  for k in 0 to bankPrograms - 1 {
    let p = switch programs[k] {
    | Some(p) => writeProgramChunk(p)
    | None => makeDefaultProgram(`Init ${Int.toString(k)}`)
    }
    out->blit(p, bankHeaderSize + k * programSize)
  }
  out
}
