// oatmeal-format.js -- Oatmeal (Fuzzpilz, release 38-1) preset / bank file formats.
//
// Plain ES module, no dependencies, runs in browsers and Node >= 18 (no Node-only APIs).
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

import { PARAM_COUNT, setParamNormalized, readInternal, toNormalizedF32 } from './oatmeal-params.js';

export const CURRENT_VERSION = 38;
export const PROGRAM_SIZE = 10376;
export const BANK_PROGRAMS = 64;
export const BANK_HEADER_SIZE = 16;
export const BANK_SIZE = BANK_HEADER_SIZE + BANK_PROGRAMS * PROGRAM_SIZE; // 664080
export const NAME_OFFSET = 10352;
export const NAME_LENGTH = 24;

// magic dwords as stored (little-endian ASCII: 'Oatm' is the dword 0x4f61746d -> bytes 6d 74 61 4f)
const MAGIC_OATM = 0x4f61746d, MAGIC_EAL = 0x65616c2e, MAGIC_PRGM = 0x7072676d, MAGIC_BANK = 0x62616e6b;

/** Offsets (chunk offsets) of the table-like regions of the program struct. */
export const OFFSETS = Object.freeze({
  wave1: 32,            // float[512]  user waveform osc 1 (-1..1)
  wave2: 2080,          // float[512]  user waveform osc 2
  lfoShape1: 4136,      // float[512]  LFO 1 user shape (0..1)
  lfoShape2: 6184,      // float[512]  LFO 2 user shape
  velocityCurve: 9596,  // float[64]
  aftertouchCurve: 9852,// float[64]
  name: NAME_OFFSET,
});

/**
 * Old program layouts accepted by the DLL.  All versions share the v38 field offsets; older versions
 * are simply shorter (fields were only ever appended), so conversion = "defaults, then memcpy the old
 * struct over offsets [16, 16+copy)".  size = minimal chunk size the DLL accepts (a program chunk is
 * 16 header + copy + 24 name (+16 unused for v33+)); name = byte offset of the 24-byte name.
 * From setChunk 0x1004f880 / converters 0x10052c20..0x10052d40 (rep movsd counts 0x8fe,0x900,0x944,
 * 0x948,0x94a,0xa12,0xa12 dwords).
 */
export const VERSION_LAYOUT = Object.freeze({
  31: { size: 9248, copy: 9208, name: 9224 },
  32: { size: 9256, copy: 9216, name: 9232 },
  33: { size: 9528, copy: 9488, name: 9504 },
  34: { size: 9544, copy: 9504, name: 9520 },
  35: { size: 9552, copy: 9512, name: 9528 },
  36: { size: 10352, copy: 10312, name: 10328 },
  37: { size: 10352, copy: 10312, name: 10328 },
  38: { size: 10376, copy: 10336, name: 10352 },
});

/**
 * Mod-envelope (M1/M2) target index remap applied to programs of version <= 34 (0x10052b70): the DLL maps
 * old index -> FourCC (table 0x1007dc10: NULL CUT1 CUT2 RESO AMP1 AMP2 AMPN PCH2 PCHN PWW1 PWR1 PWD1 PWW2 PWR2
 * PWD2 'PAN ' NRES LF1S LF2S LF1D LF2D, 0) -> new index (0x10052860).  Net effect: target "1 pitch" (PCH1,
 * new index 7) did not exist before v35, old indices 7..20 move up by one.  Old index 21 has no FourCC and
 * stays 21 (DLL quirk).  The XY remap (0x1007db40 / 0x10052660) is the identity for all 18 old indices.
 * CC targets did not exist before v36.  Values outside the tables are left unchanged.
 */
export const MOD_TARGET_REMAP_V34 = Object.freeze([0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 21]);
export const XY_TARGET_REMAP_V34 = Object.freeze([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
const M_TARGET_OFFSETS = [9392, 9396, 9400, 9404, 9488, 9492, 9496, 9500];   // M1 target 1..4, M2 target 1..4
const XY_TARGET_OFFSETS = [9160, 9164, 9168, 9172, 9196, 9200, 9204, 9208];  // X target 1..4, Y target 1..4

/**
 * Non-zero dwords written by the DLL's default-program initialiser 0x10052d70 (outside the tables).
 * Everything else in [16, 10352) is 0, except the tables (see makeDefaultProgram) and three padding
 * areas the initialiser never touches (16..32, 4128..4136, 8296..8300, 10348..10352), which we zero.
 * 'f' = float32, 'i' = int32, 'u' = uint32.  "derived" fields are recomputed by the synth every process()
 * call (see DERIVED_FIELDS); their stored values are what the DLL computes at 44100 Hz.
 */
const DEFAULT_DWORDS = [
    [8232, 'f', 4], // amp env +0 fade time
    [8236, 'f', 5], // p60:Attack
    [8244, 'f', 40], // p62:Decay 1
    [8248, 'f', 1000], // p64:Decay 2
    [8252, 'f', 50], // p66:Release
    [8256, 'f', 20], // p66:Release
    [8260, 'f', 0.0056689344], // amp env +28 derived coef
    [8264, 'f', 0.0045351475], // amp env +32 derived coef
    [8272, 'f', 1], // amp env +40 derived coef
    [8276, 'f', 1], // p63:Breakpoint
    [8280, 'f', 0.99998426], // amp env +48 derived coef
    [8284, 'f', 0.5], // p65:Sustain
    [8288, 'f', 0.9968721], // amp env +56 derived coef
    [8292, 'f', 0.993754], // amp env +60 derived coef
    [8300, 'f', 4], // filter env +0 fade time
    [8304, 'f', 5], // p45:F attack
    [8312, 'f', 40], // p47:F decay 1
    [8316, 'f', 1000], // p49:F decay 2
    [8320, 'f', 50], // p51:F release
    [8324, 'f', 20], // p51:F release
    [8328, 'f', 0.0056689344], // filter env +28 derived coef
    [8332, 'f', 0.0045351475], // filter env +32 derived coef
    [8340, 'f', 1], // filter env +40 derived coef
    [8344, 'f', 1], // p48:F breakpoint
    [8348, 'f', 0.99998426], // filter env +48 derived coef
    [8352, 'f', 0.5], // p50:F sustain
    [8356, 'f', 0.9968721], // filter env +56 derived coef
    [8360, 'f', 0.993754], // filter env +60 derived coef
    [8364, 'f', 4], // filter2 env (derived) +0 fade time
    [8368, 'f', 5], // filter2 env (derived) +4
    [8376, 'f', 40], // filter2 env (derived) +12
    [8380, 'f', 1000], // filter2 env (derived) +16
    [8384, 'f', 50], // filter2 env (derived) +20
    [8388, 'f', 20], // filter2 env (derived) +24
    [8392, 'f', 0.0056689344], // filter2 env (derived) +28 derived coef
    [8396, 'f', 0.0045351475], // filter2 env (derived) +32 derived coef
    [8404, 'f', 1], // filter2 env (derived) +40 derived coef
    [8408, 'f', 1], // filter2 env (derived) +44
    [8412, 'f', 0.99998426], // filter2 env (derived) +48 derived coef
    [8416, 'f', 0.5], // filter2 env (derived) +52
    [8420, 'f', 0.9968721], // filter2 env (derived) +56 derived coef
    [8424, 'f', 0.993754], // filter2 env (derived) +60 derived coef
    [8432, 'f', 0.5], // p43:Cutoff
    [8448, 'f', 0.29166666], // p55:F split
    [8452, 'f', 2], // p56:F envspeed
    [8456, 'f', 0.5], // p54:F mix
    [8484, 'u', 2147483648], // p3:1 Pulsewidth (uint32 phase 0.5*2^32)
    [8488, 'u', 2147483648], // p9:2 Pulsewidth (uint32 phase 0.5*2^32)
    [8508, 'f', 1], // p1:1 Amp
    [8516, 'f', 1], // p12:Transpose
    [8544, 'i', 1], // p19:LFO 1 unit
    [8552, 'i', 2], // p23:LFO 1 mode
    [8556, 'f', 20], // p21:LFO 1 speed
    [8580, 'i', 1], // p30:LFO 1 unit
    [8588, 'i', 2], // p34:LFO 2 mode
    [8592, 'f', 25], // p32:LFO 2 speed
    [8624, 'i', 4], // p69:C voices
    [8628, 'f', 0.02], // p70:C speed
    [8632, 'f', 4], // p71:C delay
    [8636, 'f', 8], // p72:C depth
    [8640, 'f', 0.8], // p74:C mix
    [8652, 'i', 5], // p76:D unit
    [8668, 'f', 0.5], // p84:D input pan
    [8676, 'f', 3], // p80:D length L
    [8680, 'f', 0.7], // p82:D feedbk L
    [8684, 'f', 3], // p81:D length R
    [8688, 'f', 0.7], // p83:D feedbk R
    [8692, 'f', 0.7], // p86:D lowpass
    [8700, 'f', 1], // p88:D dry out
    [8704, 'f', 0.8], // p89:D wet out
    [8712, 'f', 30], // p91:R size
    [8716, 'f', 1.2], // p92:R length
    [8720, 'f', 0.8], // p93:R dullness
    [8724, 'f', 0.2], // p94:R brightness
    [8728, 'f', 1], // p95:R dry out
    [8732, 'f', 0.2], // p96:R wet out
    [8736, 'f', -0.72256637], // p97:R 1
    [8740, 'f', -2.3561945], // p98:R 2
    [8744, 'f', 0.84823006], // p99:R 3
    [8748, 'f', 2.261947], // p100:R rotation
    [8756, 'f', 0.5], // p102:R early mix
    [8760, 'i', 1], // p103:Voice mode
    [8764, 'i', 8], // p104:Max polyphony
    [8772, 'i', 1], // p106:Glide mode
    [8776, 'f', 0.1], // p107:Output gain
    [8780, 'f', 0.65], // p108:Velocity sensitivity
    [8784, 'i', 2], // p109:Aftertouch mode
    [8800, 'f', 1], // p113:Random amp
    [8804, 'f', 1], // p114:Random freq
    [8812, 'f', 1], // p116:Osc phase rand
    [8824, 'f', 1], // p119:PWM phase rand
    [8840, 'i', 1], // p123:LFO retrigger
    [8848, 'i', 8], // p130:Arp unit
    [8852, 'i', 1], // p131:Arp quantize
    [8856, 'f', 1], // p132:Arp step
    [8860, 'i', 1], // p133:Arp step 1
    [8872, 'i', 1], // p136:Arp step 4
    [8884, 'i', 1], // p139:Arp step 7
    [8924, 'i', 7], // p149:Arp pattern length
    [8988, 'f', -12], // p165:P start
    [8992, 'f', 0.5], // derived pitch env
    [8996, 'f', 20], // p166:P attack
    [9004, 'f', 12], // p167:P peak
    [9008, 'f', 2], // derived pitch env
    [9012, 'f', 100], // p168:P decay
    [9016, 'f', 1], // derived pitch env
    [9024, 'f', 1], // derived pitch env
    [9032, 'f', 1], // derived pitch env
    [9060, 'f', 440], // p178:Tune main
    [9064, 'f', 2], // p179:Octave
    [9068, 'f', 0.6931472], // derived ln(octave)
    [9076, 'f', -9], // p181:Pan reference
    [9128, 'f', 12], // p194:Bend range
    [9232, 'f', 1000], // p218:EQ 1 freq
    [9236, 'f', 1000], // p219:EQ 2 freq
    [9240, 'f', 1000], // p220:EQ 3 freq
    [9244, 'f', 1000], // p221:EQ 4 freq
    [9248, 'f', 1000], // p222:EQ 5 freq
    [9272, 'f', 1], // p228:EQ 1 slope
    [9276, 'f', 1], // p229:EQ 2 slope
    [9280, 'f', 1], // p230:EQ 3 slope
    [9284, 'f', 1], // p231:EQ 4 slope
    [9288, 'f', 1], // p232:EQ 5 slope
    [9312, 'f', 4], // mod env 1 +0 fade time
    [9316, 'f', 5], // p238:M1 attack
    [9324, 'f', 40], // p240:M1 decay 1
    [9328, 'f', 1000], // p242:M1 decay 2
    [9332, 'f', 50], // p244:M1 release
    [9336, 'f', 20], // p244:M1 release
    [9340, 'f', 0.0056689344], // mod env 1 +28 derived coef
    [9344, 'f', 0.0045351475], // mod env 1 +32 derived coef
    [9352, 'f', 1], // mod env 1 +40 derived coef
    [9356, 'f', 1], // p241:M1 breakpoint
    [9360, 'f', 0.99998426], // mod env 1 +48 derived coef
    [9364, 'f', 0.5], // p243:M1 sustain
    [9368, 'f', 0.9968721], // mod env 1 +56 derived coef
    [9372, 'f', 0.993754], // mod env 1 +60 derived coef
    [9408, 'f', 4], // mod env 2 +0 fade time
    [9412, 'f', 5], // p254:M2 attack
    [9420, 'f', 40], // p256:M2 decay 1
    [9424, 'f', 1000], // p258:M2 decay 2
    [9428, 'f', 50], // p260:M2 release
    [9432, 'f', 20], // p260:M2 release
    [9436, 'f', 0.0056689344], // mod env 2 +28 derived coef
    [9440, 'f', 0.0045351475], // mod env 2 +32 derived coef
    [9448, 'f', 1], // mod env 2 +40 derived coef
    [9452, 'f', 1], // p257:M2 breakpoint
    [9456, 'f', 0.99998426], // mod env 2 +48 derived coef
    [9460, 'f', 0.5], // p259:M2 sustain
    [9464, 'f', 0.9968721], // mod env 2 +56 derived coef
    [9468, 'f', 0.993754], // mod env 2 +60 derived coef
    [9528, 'i', 1], // p270:MIDI channel 1
    [9532, 'i', 1], // p271:MIDI channel 2
    [9536, 'i', 1], // p272:MIDI channel 3
    [9540, 'i', 1], // p273:MIDI channel 4
    [9544, 'i', 1], // p274:MIDI channel 5
    [9548, 'i', 1], // p275:MIDI channel 6
    [9552, 'i', 1], // p276:MIDI channel 7
    [9556, 'i', 1], // p277:MIDI channel 8
    [9560, 'i', 1], // p278:MIDI channel 9
    [9564, 'i', 1], // p279:MIDI channel 10
    [9568, 'i', 1], // p280:MIDI channel 11
    [9572, 'i', 1], // p281:MIDI channel 12
    [9576, 'i', 1], // p282:MIDI channel 13
    [9580, 'i', 1], // p283:MIDI channel 14
    [9584, 'i', 1], // p284:MIDI channel 15
    [9588, 'i', 1], // p285:MIDI channel 16
    [9592, 'i', 1], // p286:Sustain pedal
    [10328, 'i', 1], // p124:U voices
    [10332, 'f', 1], // p125:U detune
    [10336, 'f', 0.25], // p126:U spread
];

/** Fields of the struct that the DLL recomputes from other fields (live copy, every process() call).
 *  Stored values in files are stale snapshots (computed at the saving machine's sample rate). */
export const DERIVED_FIELDS = Object.freeze([
  { from: 8260, to: 8276, what: 'amp env coefficients (+0x1c,+0x20 float, +0x24 int hold samples, +0x28)' },
  { from: 8280, to: 8284, what: 'amp env decay-2 coefficient (+0x30)' },
  { from: 8288, to: 8296, what: 'amp env release coefficients (+0x38,+0x3c)' },
  { from: 8328, to: 8344, what: 'filter env coefficients' }, { from: 8348, to: 8352, what: 'filter env coef' },
  { from: 8356, to: 8364, what: 'filter env release coefs' },
  { from: 8364, to: 8428, what: 'filter-2 env = filter env times * F envspeed, breakpoint/sustain copies, coefficients' },
  { from: 8992, to: 8996, what: 'pitch env start ratio 2^(start/12) (0 if start <= -48)' },
  { from: 9000, to: 9004, what: 'pitch env attack increment' },
  { from: 9008, to: 9012, what: 'pitch env peak ratio octave^(peak/12)' },
  { from: 9016, to: 9020, what: 'pitch env decay multiplier' },
  { from: 9024, to: 9028, what: 'pitch env sustain ratio octave^(sustain/12)' },
  { from: 9032, to: 9036, what: 'pitch env release multiplier octave^(release/(12*SR))' },
  { from: 9068, to: 9072, what: 'ln(Octave)' },
  { from: 9340, to: 9356, what: 'mod env 1 coefficients' }, { from: 9360, to: 9364, what: 'mod env 1 coef' },
  { from: 9368, to: 9376, what: 'mod env 1 release coefs' },
  { from: 9436, to: 9452, what: 'mod env 2 coefficients' }, { from: 9456, to: 9460, what: 'mod env 2 coef' },
  { from: 9464, to: 9472, what: 'mod env 2 release coefs' },
]);

/** Regions that hold no program data (stale memory / padding in real files); ignore when comparing. */
export const PADDING_FIELDS = Object.freeze([
  { from: 16, to: 32, what: 'runtime scratch (usually int sampleRate, 0, double samplesPerBeat of the saving session)' },
  { from: 4128, to: 4136, what: 'padding between wave2 and LFO shape 1' },
  { from: 8296, to: 8300, what: 'runtime pointer in the live program copy (heap garbage in files)' },
  { from: 10348, to: 10352, what: 'padding after unison fields (never written by the DLL)' },
]);

// ---------------------------------------------------------------------------------------------------
// small helpers
export function toU8(x) {
  if (x instanceof Uint8Array) return x;
  if (x instanceof ArrayBuffer) return new Uint8Array(x);
  if (ArrayBuffer.isView(x)) return new Uint8Array(x.buffer, x.byteOffset, x.byteLength);
  if (Array.isArray(x)) return Uint8Array.from(x);
  throw new TypeError('expected bytes (Uint8Array/ArrayBuffer)');
}
const dv = (u8) => new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
export function getF32(prog, off) { return dv(prog).getFloat32(off, true); }
export function setF32(prog, off, v) { dv(prog).setFloat32(off, v, true); }
export function getI32(prog, off) { return dv(prog).getInt32(off, true); }
export function setI32(prog, off, v) { dv(prog).setInt32(off, v | 0, true); }
export function getU32(prog, off) { return dv(prog).getUint32(off, true); }
export function setU32(prog, off, v) { dv(prog).setUint32(off, v >>> 0, true); }
function latin1(bytes) { let s = ''; for (const b of bytes) { if (b === 0) break; s += String.fromCharCode(b); } return s; }

/** Program name (up to the first NUL of the 24-byte field). */
export function getName(prog) { return latin1(toU8(prog).subarray(NAME_OFFSET, NAME_OFFSET + NAME_LENGTH)); }
/** Set name (Latin-1, truncated to 23 chars, NUL padded). */
export function setName(prog, name) {
  const p = toU8(prog);
  p.fill(0, NAME_OFFSET, NAME_OFFSET + NAME_LENGTH);
  const s = String(name);
  for (let i = 0; i < Math.min(s.length, NAME_LENGTH - 1); i++) p[NAME_OFFSET + i] = s.charCodeAt(i) & 0xff;
}
function readFloats(prog, off, n) { const d = dv(toU8(prog)), out = new Float32Array(n); for (let i = 0; i < n; i++) out[i] = d.getFloat32(off + 4 * i, true); return out; }
function writeFloats(prog, off, arr, n) { const d = dv(toU8(prog)); for (let i = 0; i < n; i++) d.setFloat32(off + 4 * i, arr[i], true); }
/** Copies of the table regions of a v38 program. */
export function extractTables(prog) {
  return {
    wave1: readFloats(prog, OFFSETS.wave1, 512), wave2: readFloats(prog, OFFSETS.wave2, 512),
    lfoShape1: readFloats(prog, OFFSETS.lfoShape1, 512), lfoShape2: readFloats(prog, OFFSETS.lfoShape2, 512),
    velocityCurve: readFloats(prog, OFFSETS.velocityCurve, 64), aftertouchCurve: readFloats(prog, OFFSETS.aftertouchCurve, 64),
  };
}
export function writeTable(prog, which, values) {
  const n = which === 'velocityCurve' || which === 'aftertouchCurve' ? 64 : 512;
  writeFloats(prog, OFFSETS[which], values, n);
}

function writeHeader(u8, kind, version) {
  const d = dv(u8);
  d.setUint32(0, MAGIC_OATM, true); d.setUint32(4, MAGIC_EAL, true);
  d.setUint32(8, kind === 'bank' ? MAGIC_BANK : MAGIC_PRGM, true); d.setInt32(12, version, true);
}
/** Returns {kind:'program'|'bank', version} or null if the Oatmeal magic is absent. */
export function readNativeHeader(bytes) {
  const u = toU8(bytes);
  if (u.length < 16) return null;
  const d = dv(u);
  if (d.getUint32(0, true) !== MAGIC_OATM || d.getUint32(4, true) !== MAGIC_EAL) return null;
  const m = d.getUint32(8, true);
  if (m !== MAGIC_PRGM && m !== MAGIC_BANK) return null;
  return { kind: m === MAGIC_BANK ? 'bank' : 'program', version: d.getInt32(12, true) };
}

// ---------------------------------------------------------------------------------------------------
// defaults

let _defaultCache = null;
/** Exact reproduction of the DLL's default-program initialiser 0x10052d70 (+ v38 header + name).
 *  This is also the "Init" program (default_prog.bin) apart from padding. */
export function makeDefaultProgram(name = 'Init') {
  if (!_defaultCache) {
    const p = new Uint8Array(PROGRAM_SIZE), d = dv(p);
    writeHeader(p, 'program', CURRENT_VERSION);
    for (const [off, t, v] of DEFAULT_DWORDS) {
      if (t === 'f') d.setFloat32(off, v, true); else if (t === 'u') d.setUint32(off, v, true); else d.setInt32(off, v, true);
    }
    // tables: wave1 = wave2 = sin(k*pi_f/256) ; LFO shapes = (sin+1)/2 ; velocity and aftertouch curve = k * (float)(1/63)
    const PI_F = Math.fround(Math.PI), INV63_F = Math.fround(1 / 63);
    for (let k = 0; k < 512; k++) {
      const s = Math.sin(k * PI_F / 256);   // x87: fild k; fmul pi_f; fmul 1/256; fsin (exact products)
      d.setFloat32(OFFSETS.wave1 + 4 * k, s, true); d.setFloat32(OFFSETS.wave2 + 4 * k, s, true);
      // x87 keeps sin() in 80-bit precision before (s+1)*0.5; only k=384 (s ~ -1) differs from double math
      const l = k === 384 ? 4.29905134928521e-15 /* bits 0x279ae3c0 */ : (s + 1) * 0.5;
      d.setFloat32(OFFSETS.lfoShape1 + 4 * k, l, true); d.setFloat32(OFFSETS.lfoShape2 + 4 * k, l, true);
    }
    for (let k = 0; k < 64; k++) {
      d.setFloat32(OFFSETS.velocityCurve + 4 * k, k * INV63_F, true);
      d.setFloat32(OFFSETS.aftertouchCurve + 4 * k, k * INV63_F, true);
    }
    _defaultCache = p;
  }
  const out = _defaultCache.slice();
  setName(out, name);
  return out;
}

// ---------------------------------------------------------------------------------------------------
// program conversion

/**
 * Convert one native program chunk ("Oatmeal.prgm", versions 31..38) to a v38 program (Uint8Array 10376).
 * Mirrors setChunk(isPreset=true) 0x1004f880:
 *   v38 (or newer, if opts.allowNewer): raw copy of min(len, 10376) bytes (over the default program here;
 *       the DLL copies over whatever program was in the slot, so a short v38 chunk keeps stale data there).
 *   v31..v37: len must be >= VERSION_LAYOUT[v].size else error ("Not enough data!"); name = 24 bytes at
 *       layout.name; struct = defaults (0x10052d70) then bytes [16, 16+copy) of the source; v<=34 remaps
 *       M1/M2 target indices (MOD_TARGET_REMAP_V34).
 * The header is always rewritten to 'Oatmeal.prgm' v38 (the DLL leaves the slot's old header in place).
 * Returns { bytes, name, version, warnings }.
 */
export function programToV38(src, opts = {}) {
  const u = toU8(src);
  const h = readNativeHeader(u);
  if (!h || h.kind !== 'program') throw new Error('not an Oatmeal program chunk (magic mismatch)');
  const warnings = [];
  let v = h.version;
  if (v > CURRENT_VERSION) {
    if (!opts.allowNewer) throw new Error('program version ' + v + ' is newer than 38');
    warnings.push('version ' + v + ' > 38 loaded as raw v38 (DLL asks "Try loading the program anyway?")');
  }
  if (v < 31) throw new Error('program version ' + v + ' < 31 is not supported by Oatmeal 38');
  const out = makeDefaultProgram('');
  if (v >= CURRENT_VERSION) {
    const n = Math.min(u.length, PROGRAM_SIZE);
    if (n < PROGRAM_SIZE) warnings.push('short v38 chunk (' + n + ' bytes); remaining bytes taken from the default program');
    out.set(u.subarray(16, n), 16);
  } else {
    const L = VERSION_LAYOUT[v];
    if (u.length < L.size) throw new Error('Not enough data! v' + v + ' program needs ' + L.size + ' bytes, got ' + u.length);
    out.set(u.subarray(16, 16 + L.copy), 16);
    out.set(u.subarray(L.name, L.name + NAME_LENGTH), NAME_OFFSET);
    if (v <= 34) remapTargetsV34(out);
  }
  writeHeader(out, 'program', CURRENT_VERSION);
  return { bytes: out, name: getName(out), version: v, warnings };
}

function remapTargetsV34(p) {
  const d = dv(p);
  for (const off of M_TARGET_OFFSETS) {
    const t = d.getInt32(off, true);
    if (t >= 0 && t < MOD_TARGET_REMAP_V34.length) d.setInt32(off, MOD_TARGET_REMAP_V34[t], true);
  }
  for (const off of XY_TARGET_OFFSETS) {
    const t = d.getInt32(off, true);
    if (t >= 0 && t < XY_TARGET_REMAP_V34.length) d.setInt32(off, XY_TARGET_REMAP_V34[t], true);
  }
}

/**
 * Convert a native bank chunk ("Oatmeal.bank") to 64 v38 programs.
 * Layout: 16-byte bank header (magic 'Oatm','eal.','bank', int version), then 64 programs of
 * VERSION_LAYOUT[version].size bytes each, each with its own 16-byte program header (ignored by the DLL:
 * the bank version decides the layout).  The DLL needs len >= 16 + 64*size for v31..v37 (else nothing
 * is loaded); a v38 bank is raw-copied (min(len, 664080) bytes).
 * opts.lenient: accept truncated banks, returning only the complete programs (+ warning).
 * Returns { version, programs: [{name, bytes}], warnings }.
 */
export function bankToV38(src, opts = {}) {
  const u = toU8(src);
  const h = readNativeHeader(u);
  if (!h || h.kind !== 'bank') throw new Error('not an Oatmeal bank chunk (magic mismatch)');
  const v = h.version;
  if (v < 31 || v > CURRENT_VERSION) throw new Error('bank version ' + v + ' not supported ("Version mismatch")');
  const L = VERSION_LAYOUT[v], warnings = [];
  const need = BANK_HEADER_SIZE + BANK_PROGRAMS * L.size;
  let count = BANK_PROGRAMS;
  if (u.length < need) {
    const complete = Math.max(0, Math.floor((u.length - BANK_HEADER_SIZE) / L.size));
    if (!opts.lenient && v !== CURRENT_VERSION) throw new Error('Not enough data! v' + v + ' bank needs ' + need + ' bytes, got ' + u.length);
    warnings.push('truncated bank: ' + u.length + ' of ' + need + ' bytes, ' + complete + ' complete programs');
    count = complete;
  }
  const programs = [];
  for (let k = 0; k < count; k++) {
    const o = BANK_HEADER_SIZE + k * L.size;
    const pv = new Uint8Array(L.size);
    pv.set(u.subarray(o, o + L.size));
    writeHeader(pv, 'program', v);           // the DLL converts by bank version, not by program header
    const r = programToV38(pv);
    programs.push({ name: r.name, bytes: r.bytes });
  }
  return { version: v, programs, warnings };
}

// ---------------------------------------------------------------------------------------------------
// VST fxp / fxb containers (big-endian headers)

function fourcc(u, o) { return String.fromCharCode(u[o], u[o + 1], u[o + 2], u[o + 3]); }
function be32(u, o) { return dv(u).getInt32(o, false); }
/** Parse a VST fxp/fxb container.  Returns {fxMagic, fxID, fxVersion, count, name?, chunk?, params?, programs?} */
export function parseFxContainer(bytes) {
  const u = toU8(bytes);
  if (u.length < 28 || fourcc(u, 0) !== 'CcnK') throw new Error('not a VST fxp/fxb file');
  const fxMagic = fourcc(u, 8), fxID = fourcc(u, 16);
  const r = { fxMagic, byteSize: be32(u, 4), formatVersion: be32(u, 12), fxID, fxVersion: be32(u, 20), count: be32(u, 24) };
  if (fxMagic === 'FPCh' || fxMagic === 'FxCk') {
    r.name = latin1(u.subarray(28, 56));
    if (fxMagic === 'FPCh') {
      const size = be32(u, 56);
      r.chunkSize = size; r.chunk = u.subarray(60, Math.min(u.length, 60 + size));
    } else {
      const d = dv(u); r.params = [];
      for (let i = 0; i < r.count && 56 + 4 * i + 4 <= u.length; i++) r.params.push(d.getFloat32(56 + 4 * i, false));
    }
  } else if (fxMagic === 'FBCh') {
    const size = be32(u, 156);
    r.currentProgram = be32(u, 28);          // VST 2.4 fxb v2 only; junk in many files
    r.chunkSize = size; r.chunk = u.subarray(160, Math.min(u.length, 160 + size));
  } else if (fxMagic === 'FxBk') {
    r.programs = [];
    let o = 156;                              // 28 + future[128]
    for (let k = 0; k < r.count && o + 60 <= u.length; k++) {
      const n = be32(u, o + 24);
      const len = 56 + 4 * n;
      r.programs.push(parseFxContainer(u.subarray(o, o + len)));
      o += len;
    }
  } else throw new Error('unknown fx magic ' + fxMagic);
  return r;
}

/** Program from a VST parameter list (FxCk): Init program + setParameter(i, v) for each param in order. */
export function programFromParams(values, name = '') {
  const p = makeDefaultProgram(name);
  const n = Math.min(values.length, PARAM_COUNT);
  for (let i = 0; i < n; i++) setParamNormalized(p, i, values[i]);
  return p;
}

// ---------------------------------------------------------------------------------------------------
// top-level

/**
 * Parse any supported file.  Returns
 *   { kind: 'program'|'bank', container: 'native'|'fxp'|'fxb'|'fxp-params'|'fxb-params',
 *     version, programs: [{ name, bytes: v38 Uint8Array(10376) }], warnings }
 * opts.lenient (default true): salvage complete programs from truncated banks (e.g. Oatmeal_Emdot1.fxb).
 */
export function parseFile(bytes, opts = {}) {
  const lenient = opts.lenient !== false;
  const u = toU8(bytes);
  const warnings = [];
  let container = 'native', chunk = u, fx = null;
  if (u.length >= 4 && fourcc(u, 0) === 'CcnK') {
    fx = parseFxContainer(u);
    if (fx.fxID !== 'FzOm') warnings.push('fxID is ' + JSON.stringify(fx.fxID) + ', not FzOm');
    if (fx.fxMagic === 'FxCk') {
      return { kind: 'program', container: 'fxp-params', version: CURRENT_VERSION,
        programs: [{ name: fx.name, bytes: programFromParams(fx.params, fx.name) }], warnings };
    }
    if (fx.fxMagic === 'FxBk') {
      return { kind: 'bank', container: 'fxb-params', version: CURRENT_VERSION,
        programs: fx.programs.map((p) => ({ name: p.name, bytes: programFromParams(p.params, p.name) })), warnings };
    }
    container = fx.fxMagic === 'FPCh' ? 'fxp' : 'fxb';
    chunk = fx.chunk;
    if (chunk.length < fx.chunkSize) warnings.push('file truncated: chunk has ' + chunk.length + ' of ' + fx.chunkSize + ' bytes');
  }
  const h = readNativeHeader(chunk);
  if (!h) throw new Error('Oops! Magic mismatch (not an Oatmeal chunk)');
  if (h.kind === 'program') {
    const r = programToV38(chunk, opts);
    return { kind: 'program', container, version: h.version, programs: [{ name: r.name, bytes: r.bytes }], warnings: warnings.concat(r.warnings) };
  }
  const b = bankToV38(chunk, { lenient });
  return { kind: 'bank', container, version: h.version, programs: b.programs, warnings: warnings.concat(b.warnings) };
}

// ---------------------------------------------------------------------------------------------------
// writers (always v38)

/** Native program file (.omp) = the v38 chunk itself. */
export function writeProgramChunk(prog) {
  const out = toU8(prog).slice(0, PROGRAM_SIZE);
  writeHeader(out, 'program', CURRENT_VERSION);
  return out;
}
/** Native bank (.omb): header + 64 programs (missing programs are filled with default programs named "Init <k>"). */
export function writeBankChunk(programs) {
  const out = new Uint8Array(BANK_SIZE);
  writeHeader(out, 'bank', CURRENT_VERSION);
  for (let k = 0; k < BANK_PROGRAMS; k++) {
    const p = programs[k] ? writeProgramChunk(programs[k].bytes || programs[k]) : makeDefaultProgram('Init ' + k);
    out.set(p, BANK_HEADER_SIZE + k * PROGRAM_SIZE);
  }
  return out;
}
function fxHeader(u, magic, count, fxVersion) {
  const d = dv(u);
  const put4 = (o, s) => { for (let i = 0; i < 4; i++) u[o + i] = s.charCodeAt(i); };
  put4(0, 'CcnK'); d.setInt32(4, u.length - 8, false); put4(8, magic); d.setInt32(12, 1, false);
  put4(16, 'FzOm'); d.setInt32(20, fxVersion, false); d.setInt32(24, count, false);
}
/** VST .fxp with opaque chunk.  numParams = 342, fxVersion 1 (as written by hosts for Oatmeal 38). */
export function writeFxp(prog, name) {
  const chunk = writeProgramChunk(prog);
  const u = new Uint8Array(60 + chunk.length);
  fxHeader(u, 'FPCh', PARAM_COUNT, 1);
  const nm = name !== undefined ? String(name) : getName(chunk);
  for (let i = 0; i < Math.min(nm.length, 27); i++) u[28 + i] = nm.charCodeAt(i) & 0xff;
  dv(u).setInt32(56, chunk.length, false);
  u.set(chunk, 60);
  return u;
}
/** VST .fxb with opaque bank chunk. */
export function writeFxb(programs, currentProgram = 0) {
  const chunk = writeBankChunk(programs);
  const u = new Uint8Array(160 + chunk.length);
  fxHeader(u, 'FBCh', BANK_PROGRAMS, 1);
  dv(u).setInt32(28, currentProgram, false);
  dv(u).setInt32(156, chunk.length, false);
  u.set(chunk, 160);
  return u;
}

/** Normalized parameter vector of a program (float32 inverse of setParameter, see oatmeal-params.js toNormalizedF32). */
export function programToParams(prog) {
  const out = new Float32Array(PARAM_COUNT);
  for (let i = 0; i < PARAM_COUNT; i++) out[i] = toNormalizedF32(i, readInternal(toU8(prog), i));
  return out;
}
function fxckBytes(prog, name) {
  const vals = programToParams(prog);
  const u = new Uint8Array(56 + 4 * PARAM_COUNT);
  fxHeader(u, 'FxCk', PARAM_COUNT, 1);
  const nm = name !== undefined ? String(name) : getName(toU8(prog));
  for (let i = 0; i < Math.min(nm.length, 27); i++) u[28 + i] = nm.charCodeAt(i) & 0xff;
  const d = dv(u);
  for (let i = 0; i < PARAM_COUNT; i++) d.setFloat32(56 + 4 * i, vals[i], false);
  return u;
}
/** VST .fxp as a plain parameter list (FxCk).  Lossy: user waveforms, LFO shapes, velocity/aftertouch curves
 *  and derived fields are not representable (a reader gets the Init tables). */
export function writeFxpParams(prog, name) { return fxckBytes(prog, name); }
/** VST .fxb as a list of FxCk programs (FxBk).  Lossy, see writeFxpParams. */
export function writeFxbParams(programs) {
  const parts = [];
  for (let k = 0; k < programs.length; k++) parts.push(fxckBytes(programs[k].bytes || programs[k], programs[k].name));
  const len = 156 + parts.reduce((a, b) => a + b.length, 0);
  const u = new Uint8Array(len);
  fxHeader(u, 'FxBk', programs.length, 1);
  let o = 156;
  for (const q of parts) { u.set(q, o); o += q.length; }
  return u;
}

// ---------------------------------------------------------------------------------------------------
// derived fields (what Oatmeal.dll recomputes in process(); handy for a re-implementation / for comparing)

const f32 = Math.fround;
/** Envelope sub-struct coefficient update: port of 0x100522a0(mask=0xffff, sampleRate).
 *  Sub-struct (16 dwords at base): +0 fade time ms, +4 attack ms, +8 hold ms, +0xc decay 1 ms, +0x10 decay 2 ms,
 *  +0x14 release ms, +0x18 (2nd release field), +0x1c 1000/(sr*fade), +0x20 1000/(sr*attack), +0x24 int hold samples,
 *  +0x28 decay-1 multiplier, +0x2c breakpoint (linear), +0x30 decay-2 multiplier, +0x34 sustain (linear),
 *  +0x38 release multiplier (-60 dB in release ms), +0x3c fast release multiplier (-60 dB in release/2 ms).
 *  NOTE: breakpoint / sustain values > 0.998 are clamped to exactly 1.0 in place.
 *  base = 8232 (amp), 8300 (filter), 8364 (filter 2), 9312 (mod 1), 9408 (mod 2). */
export function computeEnvelopeCoefficients(prog, base, sampleRate) {
  const d = dv(toU8(prog)), g = (o) => d.getFloat32(base + o, true), s = (o, v) => d.setFloat32(base + o, v, true);
  const sr = sampleRate | 0;
  s(0x1c, 1000 / (sr * g(0x00)));
  s(0x20, 1000 / (sr * g(0x04)));
  d.setInt32(base + 0x24, Math.trunc(g(0x08) * sr * 0.001 + 0.5), true);
  if (g(0x2c) > f32(0.998)) s(0x2c, 1);
  let bp = g(0x2c); if (bp < f32(1e-6)) bp = f32(1e-6);
  let n = f32(sr * g(0x0c) * f32(0.001)); if (n < 1) n = 1;
  s(0x28, Math.pow(bp, 1 / n));
  if (g(0x34) > f32(0.998)) s(0x34, 1);
  let b2 = g(0x2c); if (b2 < f32(1e-6)) b2 = f32(1e-6);
  let r = f32(g(0x34) / b2); if (r < f32(1e-6)) r = f32(1e-6);
  n = f32(sr * g(0x10) * f32(0.001)); if (n < 1) n = 1;
  s(0x30, Math.pow(r, 1 / n));
  n = f32(sr * g(0x14) * f32(0.001)); if (n < 1) n = 1;
  s(0x38, Math.pow(10, -3 / n));
  n = f32(sr * g(0x14) * f32(0.0005)); if (n < 1) n = 1;
  s(0x3c, Math.pow(10, -3 / n));
}

/** Recompute every derived field exactly in the order process() (0x10068040) does it on the live copy.
 *  sampleRate: host sample rate (the DLL uses round(float SR) for envelopes and the int SR for the pitch env). */
export function recomputeDerived(prog, sampleRate) {
  const p = toU8(prog), d = dv(p), g = (o) => d.getFloat32(o, true), s = (o, v) => d.setFloat32(o, v, true);
  const sr = Math.round(sampleRate) | 0;
  d.setUint32(8408, d.getUint32(8344, true), true);   // filter-2 env breakpoint = F breakpoint
  d.setUint32(8416, d.getUint32(8352, true), true);   // filter-2 env sustain = F sustain
  s(9068, Math.log(g(9064)));                          // ln(Octave)
  const es = g(8452);                                  // F envspeed
  s(8368, g(8304) * es); s(8376, g(8312) * es); s(8380, g(8316) * es);
  s(8372, g(8308) * es); s(8384, g(8320) * es); s(8388, g(8324) * es);
  computeEnvelopeCoefficients(p, 8232, sr);
  computeEnvelopeCoefficients(p, 8300, sr);
  computeEnvelopeCoefficients(p, 8364, sr);
  const oct = g(9064), inv12 = f32(1 / 12);
  s(8992, g(8988) > -48 ? Math.pow(2, g(8988) * inv12) : 0);                 // start ratio
  const peak = f32(Math.pow(oct, g(9004) * inv12)); s(9008, peak);
  const sus = f32(Math.pow(oct, g(9020) * inv12)); s(9024, sus);
  const srf = f32(sr);
  s(9000, (peak - g(8992)) / (srf * g(8996) * f32(0.001)));                // attack increment per sample
  s(9016, Math.pow(sus / peak, 1 / (srf * g(9012) * f32(0.001))));         // decay multiplier per sample
  s(9032, Math.pow(oct, g(9028) / (12 * sr)));                             // release multiplier per sample
  computeEnvelopeCoefficients(p, 9312, sr);
  computeEnvelopeCoefficients(p, 9408, sr);
  return p;
}
