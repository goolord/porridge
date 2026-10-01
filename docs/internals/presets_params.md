# Oatmeal 38-1: preset/bank formats, version conversion, parameter mapping and display text

Scope: everything needed to load every Oatmeal preset/bank file into a re-implementation bit-exactly like
Oatmeal.dll does, to map the 342 VST parameters (normalized 0..1 <-> program struct) exactly like the DLL,
and to reproduce the DLL's parameter texts. In this repository:

| file | what |
|---|---|
| `ui/oatmeal/OatmealFormat.res` | file parsing/conversion to v38 (`parseFile`, `programToV38`, `bankToV38`), writers (.omp/.omb/.fxp/.fxb, FxCk/FxBk), field helpers, tables (waves, LFO shapes, curves), `makeDefaultProgram` (exact 0x10052d70), `recomputeDerived` (exact port of what process() derives) |
| `ui/oatmeal/OatmealParams.res` | the 342-parameter table (`params`, `describeParams`), `toInternal`, `toNormalized`, `toNormalizedF32`, `dllGetParameter`, `statusText`, `displayText`, `hostDisplay`, all value-name enumerations |
| `tools/re/vsthost.py` | a minimal 32-bit VST2 host (32-bit Python) that drives the real DLL |
| `tools/re/check-params.mjs`, `tools/re/param_samples.json` | checks the parameter texts against display strings sampled from the DLL |
| `tools/re/check-presets.mjs` | parses every program/bank file under a folder with the loader |

The original research scripts named below (`work_presets/*`: the oracle dump scripts and their Node
tests, and the generated JSON parameter table) are not part of this repository; their results are
recorded here. The ReScript modules compile to dependency-free ES modules (browser + Node >= 18).
Conventions in this document: *chunk offset* = byte offset in the 10376-byte v38 program chunk (the program
struct lives at chunk offsets 16..10352, i.e. at plugin `this+0x1e3388+offset`). `f32` = IEEE float32,
`i32` = int32, all little-endian. `v` = normalized VST value (a float32), `x` = stored value.

---------------------------------------------------------------------------------------------------------

## 1. File formats

### 1.1 Native program chunk ("Oatmeal.prgm"), `.omp`
```
0   u32 0x4f61746d  ('Oatm' as a LE dword -> file bytes "mtaO")
4   u32 0x65616c2e  ('eal.' -> file bytes ".lae")
8   u32 0x7072676d  ('prgm' -> bytes "mgrp")
12  i32 version     (31..38; current 38 = 0x26)
16  program struct, length VERSION_LAYOUT[version].copy
..  name: 24 bytes Latin-1, NUL terminated, at VERSION_LAYOUT[version].name
```
A `.omp` file is exactly this chunk (what `effGetChunk(isPreset=1)` returns). v38 = 10376 bytes.

### 1.2 Native bank chunk ("Oatmeal.bank"), `.omb`, and `oatmealprs.dat`
```
0   'Oatm' 'eal.' 'bank'(0x62616e6b, file bytes "mtaO.laeknab")  i32 version
16  64 program chunks of VERSION_LAYOUT[version].size bytes each (each with its own 16-byte program header)
```
v38 bank = 16 + 64*10376 = 664080 bytes (= `oatmealprs.dat`, the factory bank the DLL loads from its
directory at startup). The DLL converts by the **bank** version only; the per-program headers inside a bank
are ignored (in all surveyed files they equal the bank version anyway).

### 1.3 VST containers (big-endian headers)
`.fxp` opaque: `'CcnK', i32 byteSize, 'FPCh', i32 fxpVersion(1), 'FzOm', i32 fxVersion(1), i32 numParams,
char name[28], i32 chunkSize, chunk[chunkSize]` (header 60 bytes).
`.fxb` opaque: `'CcnK', byteSize, 'FBCh', version, 'FzOm', fxVersion(1), numPrograms, future[128] (VST 2.4 v2:
first 4 = currentProgram), i32 chunkSize, chunk` (header 160 bytes).
`FxCk` (.fxp param list): after the name, `float32 BE params[numParams]` (header 56). `FxBk`: 156-byte header
then numPrograms FxCk records. No FxCk/FxBk files exist in the collection; the importer applies
`setParameter(i, value)` in index order to the Init program (exactly what a host does), verified against the DLL
(36/36 synthetic FxCk programs byte-identical, see 5).

Observed header junk to ignore: `byteSize` = 0 in many files, `numParams/numPrograms` = 64, 264 or 342 in fxp
files and 64 or 264 in fxb files, `future[]` containing stack garbage (e.g. `Oatmeal_Emdot1.fxb`).
`fxb/Oatmeal_Emdot1.fxb` is **truncated** (286368 bytes, header claims byteSize 662704 / chunkSize 662544 = a v37
bank): only 27 complete programs (+ part of the 28th) are present. The DLL cannot load it (a host would pass
286208 bytes -> "Not enough data!"); `parseFile` (lenient default) returns the 27 complete programs + a warning.

### 1.4 Survey of `F:\VST32\oatmeal banks` (+ oatmealprs.dat)
| kind | count | versions |
|---|---|---|
| .omp | 1 | v36 (clav.omp, 10352 bytes) |
| .omb | 33 | v37 x29, v35 x2 (Klangmanipulation, speccyteccy), v38 x2 (core_oatmeal_01_32, _02_64) |
| .fxp (FPCh) | 86 | v35 x85 (9552-byte chunk), v38 x1 ("Oatmeal - Clav.fxp") |
| .fxb (FBCh) | 40 | v37 x21 (one truncated), v35 x15, v36 x4 |
| oatmealprs.dat | 1 | v38 bank |

---------------------------------------------------------------------------------------------------------

## 2. setChunk (0x1004f880) and version conversion

### 2.1 Version layouts
All versions use the v38 field offsets; newer versions only **appended** fields. Old chunks are shorter:

| ver | min chunk size | struct bytes copied (from chunk offset 16) | name offset | fields added in this version (chunk offsets) |
|---|---|---|---|---|
| 31 | 9248 | 9208 (0x8fe dwords) -> 16..9224 | 9224 | base |
| 32 | 9256 | 9216 (0x900) -> ..9232 | 9232 | 9224 LFO 1 pan, 9228 LFO 2 pan |
| 33 | 9528 | 9488 (0x944) -> ..9504 | 9504 | 9232..9312 EQ 1-5; 9312..9408 mod env 1 (+depths/targets); 9408..9504 mod env 2 |
| 34 | 9544 | 9504 (0x948) -> ..9520 | 9520 | 9504 M1 velo sens, 9508 M2 velo sens, 9512 F env velo sens, 9516 P env velo sens |
| 35 | 9552 | 9512 (0x94a) -> ..9528 | 9528 | 9520/9524 LFO 1/2 quantize; M1/M2 target list gets "1 pitch" at index 7 |
| 36 | 10352 | 10312 (0xa12) -> ..10328 | 10328 | 9528 MIDI channels 1-16, 9592 sustain pedal, 9596 velocity curve[64], 9852 aftertouch curve[64], 10108 CC 1-6 blocks, 10324 Osc mix |
| 37 | 10352 | 10312 | 10328 | none (same layout as 36, handled identically) |
| 38 | 10376 | 10336 (raw copy of the whole chunk) | 10352 | 10328 U voices, 10332 U detune, 10336 U spread, 10340 U pitch jitter, 10344 U pan jitter, 10348 unused dword |

### 2.2 Program load (`effSetChunk`, isPreset = 1), exact algorithm
```
size = min(byteSize, 10376)
check magic 'Oatm','eal.','prgm' else MessageBox "Oops! Magic mismatch. Couldn't load program." -> return 0
v = chunk.version
if v > 38: MessageBox(MB_YESNO) "Oops! Version mismatch. Try loading the program anyway?\nMay cause problems!"
           -> No: return 0; Yes: treated like v38 (raw copy)
if v < 31: MessageBox "Oops! Version mismatch. Couldn't load program." -> return 0
slot = bank + 16 + currentProgram*10376          (the program is loaded into the current bank slot)
if v >= 38 (or accepted newer): memcpy(slot, chunk, size)      // incl. the 16-byte header; short chunks leave the rest of the slot as it was
else:
   if byteSize < layout.size: MessageBox "Not enough data! This can't possibly be a program." (slot unchanged)
   else:
      memcpy(slot+10352, chunk+layout.name, 24)                  // name
      defaults(slot+16)                                          // 0x10052d70, see 2.4
      memcpy(slot+16, chunk+16, layout.copy)                     // old struct over the defaults
      if v <= 34: remap M1/M2 targets (and X/Y targets, identity)  // 0x10052b70, see 2.5
   // the slot's 16-byte header is NOT rewritten (stays whatever it was, normally 'Oatmeal.prgm' 38)
live program (this+0x1e3398, chunk offsets 16..10352) = copy of slot[16..10352]
rebuild osc wavetables from wave1/wave2; this+0x1e56f4 (chunk 9068) = ln(Octave); notify editor; resume
```
### 2.3 Bank load (`effSetChunk`, isPreset = 0)
```
size = min(byteSize, 664080); magic 'Oatm','eal.','bank' else "Oops! Magic mismatch. Couldn't load bank."
v not in 31..38 -> "Oops! Version mismatch. Couldn't load bank." (no "load anyway" prompt for banks)
v == 38: memcpy(bank, chunk, size)       // everything incl. bank header and program headers; a short v38 bank only overwrites the beginning
else: if size < 16 + 64*layout.size -> "Not enough data! This can't possibly be a bank." (nothing loaded)
      for k in 0..63: src = chunk + 16 + k*layout.size ; dst = bank + 16 + k*10376
          name, defaults(dst+16), memcpy(dst+16, src+16, layout.copy), remap if v<=34  (as for programs)
      // neither the bank header nor the program headers are rewritten
then the current program is copied to the live struct as in 2.2 (currentProgram index is kept)
```
The JS converter (`programToV38`, `bankToV38`, `parseFile`) does the same but always writes a clean v38 header
and starts from the default program instead of the slot's previous contents. Differences to the DLL are only
possible in bytes the DLL leaves stale: the 16-byte header, chunk 10348..10352 (never written by the
converter or defaults, so it keeps the previous slot's value; 0 in the factory bank; JS writes 0), and the
unlikely short-v38 case (JS fills the rest from the default program).

### 2.4 Default program (0x10052d70)
`makeDefaultProgram()` reproduces it bit-exactly (verified against a direct call of the DLL function, all bytes
16..10348): wave1 = wave2 = `(float)sin(k*pi_f/256)`, LFO shapes 1/2 = `(float)((sin+1)*0.5)` (computed from
the 80-bit sine; only k=384 differs from double math: stored bits 0x279ae3c0), velocity and aftertouch curves
`k*(float)(1/63)` (k = 0..63), MIDI channels 1..16 = 1, sustain pedal = 1, and the parameter defaults listed in
the table in Appendix B ("default" column). Envelope sub-structs get fade 4 ms, attack 5, hold 0, decay1 40,
decay2 1000, release 50 (+20 in the second release field), breakpoint 1, sustain 0.5 and coefficients computed
with sample rate 44100 (for all five envelopes incl. the derived filter-2 envelope). Bytes never written:
chunk 16..32, 4128..4136, 8296..8300, 10348..10352 (and the name). The DLL's "Init" program
(`default_prog.bin`) is identical to it except the name and the padding at 8296.

### 2.5 Old mod-target remap (versions <= 34), 0x10052b70
For each of M1 target 1-4 (9392..9404) and M2 target 1-4 (9488..9500): if 0 <= t < 22, t = map[t] with
`map = [0,1,2,3,4,5,6,8,9,10,11,12,13,14,15,16,17,18,19,20,21,21]` (FourCC table 0x1007dc10 ->
0x10052860: the new target "1 pitch" (PCH1) was inserted at index 7). X/Y targets 1-4 (9160..9172,
9196..9208), 0 <= t < 18, go through FourCC table 0x1007db40 -> 0x10052660, which maps every old index to
itself. No other field is changed by any conversion (v36 -> v37 -> v38 conversions are pure copies).

### 2.6 getChunk (0x1004f740)
Before copying, the six table regions (wave1, wave2, LFO shape 1/2, velocity curve, aftertouch curve) are copied
from the live struct back into the current bank slot (the GUI edits them live). Program chunk = the 10376 bytes
of the current bank slot (including its possibly stale header!). Bank chunk = the whole 664080-byte bank.
Parameters are written by setParameter into the bank slot *and* the live struct, so the slot is always current
for parameters; derived fields are only computed in the live struct (so a saved chunk contains whatever derived
values the slot had, normally from the last load, i.e. from the file).

### 2.7 Program struct regions that are not parameters
| chunk offsets | content | notes |
|---|---|---|
| 16..32 | runtime scratch | files typically contain int 44100, 0, double 21000.0 (samples/beat at 126 BPM) - stale values of an older design; nothing reads them; copied verbatim |
| 32..2080 / 2080..4128 | wave1 / wave2 float[512] | user osc waveforms -1..1 (`OFFSETS.wave1/wave2`) |
| 4128..4136 | padding | stale memory |
| 4136..6184 / 6184..8232 | LFO 1 / LFO 2 user shape float[512] | 0..1 |
| 8232..8296 | amp envelope sub-struct (16 dwords) | layout below |
| 8296..8300 | **runtime pointer** in the live struct | stale heap pointer in files; ignore |
| 8300..8364 | filter envelope | |
| 8364..8428 | filter-2 envelope | fully derived (see 2.8) |
| 8428..9312 | parameters | see Appendix B |
| 8992, 9000, 9008, 9016, 9024, 9032 | pitch envelope derived values | see 2.8 |
| 9068 | ln(Octave) | derived |
| 9312..9376, 9408..9472 | mod env 1 / 2 sub-structs | |
| 9596..9852 / 9852..10108 | velocity / aftertouch curve float[64] | |
| 10348..10352 | unused | |
| 10352..10376 | name | 24 bytes |

Envelope sub-struct (base = 8232 amp, 8300 filter, 8364 filter 2, 9312 mod 1, 9408 mod 2):
`+0 fade ms (4.0)`, `+4 attack ms`, `+8 hold ms`, `+0xc decay 1 ms`, `+0x10 decay 2 ms`, `+0x14 release ms`,
`+0x18 second release field (= release*0.5, written by setParameter, not used by the coefficient code)`,
`+0x1c 1000/(sr*fade)`, `+0x20 1000/(sr*attack)`, `+0x24 i32 hold samples`, `+0x28 decay-1 multiplier`,
`+0x2c breakpoint (linear)`, `+0x30 decay-2 multiplier`, `+0x34 sustain (linear)`, `+0x38 release multiplier`,
`+0x3c fast-release multiplier`.

### 2.8 Derived fields (recomputed by the DLL at the start of every process() call, live struct only)
Exact order (process 0x10068040), implemented as `recomputeDerived(prog, sampleRate)` and verified bit-exact
against the DLL's live struct for 256 programs at 44.1, 48 and 96 kHz:
```
[8408] = [8344] (F breakpoint) ; [8416] = [8352] (F sustain)
[9068] = (float) ln(Octave)
[8368]=[8304]*es ; [8376]=[8312]*es ; [8380]=[8316]*es ; [8372]=[8308]*es ; [8384]=[8320]*es ; [8388]=[8324]*es   (es = F envspeed [8452]; [8364] fade not scaled)
envCoefs(8232), envCoefs(8300), envCoefs(8364)        with sr = round(host float sample rate)
[8992] = start > -48 ? 2^(start*(float)(1/12)) : 0     (start = [8988]; NB base 2, not Octave)
[9008] = Octave^(peak*(1/12)f) ; [9024] = Octave^(sustain*(1/12)f)       (both rounded to float)
[9000] = ([9008] - [8992]) / (srf*attack*0.001f)       (srf = (float)int SR)
[9016] = ([9024]/[9008]) ^ (1/(srf*decay*0.001f))
[9032] = Octave ^ (release / (12*SR_int))
envCoefs(9312), envCoefs(9408)
envCoefs(base, sr)  (0x100522a0, mask 0xffff):
  +0x1c = 1000/(sr*fade) ; +0x20 = 1000/(sr*attack) ; +0x24 = (int)(hold*sr*0.001 + 0.5)
  if +0x2c > 0.998f: +0x2c = 1.0          <- modifies the breakpoint PARAMETER in the live copy
  n = (float)(sr*decay1*0.001f), n<1 -> 1 ; +0x28 = max(bp,1e-6f)^(1/n)
  if +0x34 > 0.998f: +0x34 = 1.0          <- modifies the sustain PARAMETER in the live copy
  r = (float)(sustain/max(bp,1e-6f)), r<1e-6 -> 1e-6 ; n = (float)(sr*decay2*0.001f), n<1 -> 1 ; +0x30 = r^(1/n)
  n = (float)(sr*release*0.001f), n<1 -> 1 ; +0x38 = 10^(-3/n)
  n = (float)(sr*release*0.0005f), n<1 -> 1 ; +0x3c = 10^(-3/n)
```
setParameter additionally updates some of these in the live struct immediately (envelope coefficients with the
int sample rate, pitch-envelope values, ln(Octave)); process() overwrites them anyway. Stored derived values in
files are therefore irrelevant for sound (they reflect the saving machine's sample rate); a re-implementation
should recompute them (or ignore them and compute its own coefficients). All derived values are SR-dependent
except [8364..8392] times, [8408], [8416] and [9068].

---------------------------------------------------------------------------------------------------------

## 3. Parameter mapping (setParameter 0x10048260, getParameter 0x1004c890)

General rules
* The value is a float32; all arithmetic is x87 extended precision, the stored float is rounded once at the
  end. `toInternal` does the same math in double and rounds with `Math.fround`; the result matched the DLL
  bit-for-bit for every tested value (see 5).
* Switches: `x = _ftol(N*v + 0.5)` (truncation toward zero, i.e. round-half-up) (+1 for voices/polyphony
  counts). No clamping anywhere: v outside [0,1] produces out-of-range values exactly like the DLL.
* setParameter writes the bank slot and copies the value into the live struct. Envelope time/level params also
  recompute that envelope's coefficients in the live struct (with the int sample rate); Octave also updates
  [9068]; P start/attack/peak/decay/sustain/release update the pitch-env derived values (P start uses
  Octave^(start/12) here, process() then uses 2^(start/12)).
* getParameter reads the **live** struct. Consequence: breakpoint/sustain values > 0.998 read back as exactly
  1.0 (the envelope code snapped them in the live copy); `dllGetParameter` emulates this.
* Packed field 8428 (`Filter`/`Filter 2`): low 16 bits = Filter 1 type (param 41), high 16 bits = Filter 2 type
  (param 42), both `_ftol(15v+0.5)` (valid 0..12). Param 41 keeps the high half (read from the live copy),
  param 42 clears the live high half then ORs `x<<16`. getParameter(42) reads the high half as a *signed*
  word. `readInternal`/`writeInternal` handle this (`type: 'lo16'/'hi16'`).
* Pulsewidth (3, 9): `uint32 = _ftol(2^32*v + 0.5)` taken modulo 2^32, i.e. the phase fraction *2^32 (0.5 =
  0x80000000). v = 1.0 wraps to 0 (0 %) - DLL quirk, reproduced. Stored as the raw dword (reading it as float
  gives nonsense).
* Envelope releases (51, 66, 244, 260) write two floats: `x` and `x*0.5` at offset+4.
* int fields: all switches (waveform, units, shapes, quantize, modes, filter double, chorus, delay/reverb
  switches, voice/glide/aftertouch modes, retriggers, voices, polyphony, arp mode/unit/quantize/steps/length/
  note-on, P env on, dist type/mode/oversample, X/Y targets and CCs, EQ types, M1/M2 targets, MIDI channels,
  sustain pedal, CC numbers/targets, Osc mix, U voices). Everything else is float32.

Notation below: `b(s) = (2v-1)*s` (bipolar), `f(c)` = the float32 constant c as stored in the DLL.

| params | stored x (`toInternal`) | DLL getParameter (`dllGetParameter`) | mathematical inverse (`toNormalized`) |
|---|---|---|---|
| 0,6 waveform | ftol(5v+.5) 0..5 | x*f(1/5) | x/5 |
| 1,7,15,88,89,95,96,107 amp/dry/wet/gain | v>0 ? 10^((90v-60)*f(0.05)) : 0 (linear) | x>0 ? (20*log10 x+60)*f(1/90) : 0 | (log10 x/f(0.05)+60)/90 |
| 2,8,18,59,165,167,169,170 | b(48) semitones | (x*f(1/48)+1)/2 | (x/48+1)/2 |
| 3,9 pulsewidth | uint32 ftol(2^32 v+.5) | x*2^-32 | x/2^32 |
| 4,10 PWM rate | 8v Hz | **x*0.0625 = v/2 (quirk)** | x/8 |
| 5,11,24,25,35,36,57,58,73,108,110,111,171,196,197,198-201,207-210,245,246-249,261,262-265, CC depths | 2v-1 | (x+1)/2 | (x+1)/2 |
| 12 Transpose | b(4) octaves (display 12x st) | (x/4+1)/2 | |
| 13 Detune | b(50) Hz | (x*f(1/50)+1)/2 | |
| 14,16,175,176 | b(60) dB | (x*f(1/60)+1)/2 | |
| 17,26-29,37-40,43,44,54,55,74,84,86,87,93,94,102,112,115,116,118,119,121,122,126-128,216 | v | x | x |
| 19,30,130 LFO/arp unit | ftol(17v+.5) 0..17 | x*f(1/17) | |
| 20,31 LFO shape, 106 glide mode | ftol(6v+.5) | x*f(1/6) | |
| 21,32 LFO speed | 3v<1 ? 1/(4-9v) : (1.5v-.5)*255+1  (0.25..256) | x<=1 ? (4-1/x)*f(1/9) : ((x-1)*f(1/255)+.5)*f(2/3) | |
| 22,33,75,77,90,117,120,123,131,150-156,164,270-285,286 on/off | ftol(v+.5) 0/1 | x | x |
| 23,34,53,68,78,79,103,109,341 3-way | ftol(2v+.5) 0..2 | x*0.5 | x/2 |
| 41 Filter / 42 Filter 2 | ftol(15v+.5) in low/high word of 8428 | (x&0xffff)*f(1/15) / (int16)(x>>16)*f(1/15) | x/15 |
| 45,60,166,238,254 attack | v^2*f(9999.8)+f(0.2) ms | sqrt((x-f(.2))*f(1/9999.8)) | |
| 46,61,239,255 hold | v^2*10000 ms | sqrt(x*f(1e-4)) | |
| 47,49,51,62,64,66,168,240,242,244,256,258,260 decay/release | v^2*19990+10 ms | sqrt((x-10)*f(1/19990)) | |
| 48,50,63,65,241,243,257,259 breakpoint/sustain | v!=0 ? 10^((v-1)*3) : 0 (linear, -60..0 dB) | (x>0.998f?1:x)!=0 ? log10*f(1/3)+1 : 0 | log10(x)/3+1 |
| 52 keytrack | 4v-2, then snapped: \|x-1\|<f(.001) ->1, \|x+1\|<.001 -> -1, \|x\|<.001 -> 0 | (x/2+1)/2 | (x+2)/4 |
| 56 F envspeed | v>.5 ? 1/((v-.5)*8+1) : (.5-v)*8+1  (0.2..5) | **x<1 ? (1/x-1)/8-0.5 (= v-1, bug) : 0.5-(x-1)/8** | x<1 ? (1/x-1)/8+.5 : .5-(x-1)/8 |
| 67 chorus mode, 172 dist type | ftol(4v+.5) | x*0.25 | |
| 69 C voices, 124 U voices | ftol(15v+.5)+1 (1..16) | (x-1)*f(1/15) | (x-1)/15 |
| 70 C speed | v^2*f(3.999)+f(.001) Hz | sqrt((x-.001f)*f(1/3.999)) | |
| 71,72 C delay/depth | v*f(99.9)+f(.1) ms | (x-.1f)*f(1/99.9) | |
| 76 D unit | ftol(14v+.5) 0..14 | x*f(1/14) | |
| 80,81 D length | 99v+1 units | (x-1)*f(1/99) | |
| 82,83 D feedback | 4v-2 (linear) | (x+2)/4 | |
| 85,97,98,99,100 rotations | b(pi_f) rad | (x/pi_f+1)/2 | |
| 91 R size | v^3*240+10 | ((x-10)/240)^(1/3) (double consts) | cbrt |
| 92 R length | v==1 ? 120 : v^2*f(29.9)+f(.1) s | x<30 ? sqrt((x-.1f)*0x3d08fd6f) : 1 | |
| 101 R predelay | b(500) ms | (x*f(1/500)+1)/2 | |
| 104 Max polyphony | ftol(31v+.5)+1 (1..32) | (x-1)*f(1/31) | |
| 105 Glide | v^2*500 ms | sqrt(x*f(1/500)) | |
| 113 Random amp | v^2*20 dB | sqrt(x*f(.05)) | |
| 114 Random freq | v^2*1200 cents | sqrt(x*f(1/1200)) | |
| 125 U detune | v^2*4800 cents | sqrt(x*f(1/4800)) | |
| 129 arp mode | ftol(5v+.5) | x*f(.2) | |
| 132 Arp step | v<=.25 ? 1/((1-4v)*7+1) : (v-.25)*f(41.3333)+1 (1/8..32) | x<1 ? (x<=0?0:(1-(1/x-1)*f(1/7))/4) : (x-1)*f(.75/31)+.25 | |
| 133-148 arp steps, 149 pattern length | ftol(15v+.5) | x*f(1/15) | |
| 157-163 arp note shift | b(36) st | (x*f(1/36)+1)/2 | |
| 173 dist mode, 177 oversample, 233-237 EQ type | ftol(3v+.5) | x*f(1/3) | |
| 174 dist limit | b(30) dB | (x*f(1/30)+1)/2 | |
| 178 Tune main | b(80)+440 Hz | ((x-440)*f(1/80)+1)/2 | |
| 179 Octave | o=4v+1; o<f(1.01) -> f(1.01); \|2-o\|<f(.01) -> 2 | (x-1)/4 | |
| 180,181 cut/pan reference | b(24) st | (x*f(1/24)+1)/2 | |
| 182-193 Tune C..B | b(200) cents | (x*f(1/200)+1)/2 | |
| 194 Bend range | v^2*24 st | sqrt(x*f(1/24)) | |
| 195 Global transpose | floor(b(48)+0.5)*f(1/12) octaves | (x/4+1)/2 | |
| 202-205,211-214 X/Y targets | ftol(33v+.5) 0..33 | x*f(1/33) | |
| 206,215,287,296,305,314,323,332 CC numbers | ftol(127v+.5) (0 = none) | x*f(1/127) | |
| 217 XY var rate | 16v Hz | x/16 | |
| 218-222 EQ freq | v^3*19985+15 Hz | ((x-15)/19985)^(1/3) (double) | |
| 223-227 EQ amp | b(60) dB | (x*f(1/60)+1)/2 | |
| 228-232 EQ slope | v>.5 ? (v-.5)*30+1 : v<.5 ? 1/((.5-v)*30+1) : 1 | x>1 ? (x-1)*f(1/30)+.5 : x<1 ? .5-(1/x-1)*f(1/30) : .5 | |
| 250-253,266-269 M1/M2 targets | ftol(30v+.5) 0..30 | x*f(1/30) | |
| CC targets (292-295, ...) | ftol(34v+.5) 0..34 | x*f(1/34) | |

Offsets of every parameter: Appendix B (and `PARAMS[i].offset`). Groups follow simple strides: arp step k
(133..148), arp note on/shift (150..163): offset = 4*i + 8328; Tune C..B, X/Y depths/targets (182..214):
4*i + 8352; EQ (218..237): 4*i + 8360; CC block c (1..6): number at 10108+36(c-1), depth k at +4k,
target k at +16+4k; MIDI channel ch: 9524 + 4*ch.

### 3.1 DLL getParameter quirks (documented, emulated by `dllGetParameter`, NOT used by `toNormalized`)
1. PWM rate (4, 10): returns x/16 = v/2 (setParameter uses x = 8v). The status text is written against the
   getParameter scale (16*V Hz), so host displays are right but a host-side knob shows half the range.
2. F envspeed (56): for x < 1 (v > 0.5) returns v-1 (negative). The host display for those values is wrong
   (e.g. v = 0.75, "*3.000" is shown as "/7.000").
3. Breakpoint/sustain (48, 50, 63, 65, 241, 243, 257, 259): values > 0.998 read back as 1.0 (live-copy snap).
4. getParameter reads the live copy: after setChunk it reflects the loaded program immediately.
Other DLL oddities kept as-is: pulsewidth v=1 wraps to 0; `Filter` 13..15 are invalid types (empty text);
param 30 is named "LFO 1 unit" by the DLL although it is LFO 2's unit; params 67/68 are both named "Chorus",
78/79 both "D reverse"; params 124..128 (unison) have empty names.

### 3.2 Round-trip notes
`toNormalized(i, x)` is the exact algebraic inverse of the setParameter formula (same float constants),
clamped to [0,1]; for all 173052 test values `toInternal(i, toNormalized(i, toInternal(i, v)))` reproduced the
stored value exactly. `toNormalizedF32` additionally searches neighbouring float32 values so that the returned
float maps back bit-exactly when possible. Many values found in real presets (e.g. the defaults 1.0 dB-gain,
40/1000 ms decays, LFO speeds 20/25) are NOT reachable by any float32 v (they come from the defaults
function, not from setParameter), so a program -> FxCk -> program round trip changes ~10 % of float fields by
1-2 ulp (19798/21888 fields identical over 64 real programs). Opaque chunks (FPCh/FBCh) are lossless.

---------------------------------------------------------------------------------------------------------

## 4. Parameter text

### 4.1 Where the texts come from
* `0x100405f0(this = {prog*}, char *out, int index, float V)` builds the long **status-bar text**
  `"<label>: <value>"` from a normalized value V and, for some params, other fields of the program.
* `effGetParamDisplay` (0x1004f5b0) calls `getParameter(i)` (live struct), passes the result as V, keeps the text
  after the first `':'` (including the following space) and truncates it to 23 characters. Texts without
  `':'` (Voice mode: "Monophonic", "Polyphonic", "Monophonic, legato") give an empty host display.
* effGetParamLabel returns "" for all params; effGetParamName returns the DLL names (Appendix B).

JS: `statusText(i, V, prog)` = the long text (bit-exact), `hostDisplay(prog, i)` = the host string,
`displayText(i, x, prog, opts)` = value part without the leading space for an internal value x
(uses `textNormalized(i,x)`: the DLL getParameter value, except the proper inverse for F envspeed; `{dll:true}`
reproduces the host bug too; `{v}` uses a given normalized value, e.g. a GUI knob position).

Number formatting is MSVC `sprintf` (`%.Nf` rounds half away from zero, "-0.00" for negative values that round
to zero, `%03i`); `OatmealParams.res` reproduces it for all formats used. All intermediate math is done
on the float32 V in extended precision and passed to sprintf as double; where the DLL first stores an
intermediate to a float local (Cutoff Hz, the `t = 2V-1` of the transposition/reference/tune texts, the
`V-1` of the amp breakpoint/sustain dB text, `c` of the tune cents) the JS code rounds with `Math.fround` too.

### 4.2 Status text formulas (V = float32 normalized value; `%` means "%.2f %%" unless noted)
| params | text |
|---|---|
| 0/6 | `"1 Waveform: "` + WAVEFORMS[ftol(5V+.5)] (out of range -> "") |
| 1/7/15/107 | V>0 ? `"1 Amp: %.2f dB"` (90V-60) : `"1 Amp: -inf dB"` (labels "1 Amp", "2 Amp", "N Amp", "Gain") |
| 2/8 | `"Aftertouch -> 1 pitch: %.2f semitones"` (2V-1)*48 |
| 3/9 | `"1 Pulsewidth: %.2f %%"` 100V |
| 4/10 | `"1 PWM rate: %.3f Hz"` 16V |
| 5/11 | `"1 PWM depth: %.2f %%"` (2V-1)*100 |
| 12 / 18 | t=f32(2V-1), oct=[9064]: V<0.5 ? `"Transpose: %.2f st (/%.4f)"` (48t, oct^(-4t)) : `"... (*%.4f)"` (48t, oct^(4t)); 18 = "Noise transpose" same |
| 13 | `"Detune: %.3f Hz"` (2V-1)*50 |
| 14 / 16 | `"Aftertouch -> osc: %.2f dB"` / `"Aftertouch -> noise: %.2f dB"` (2V-1)*60 |
| 17 | V>0 ? `"Noise resonance: %.2f %%"` 100V : `"Noise resonance: no filtering"` |
| 19/30 | `"LFO 1 unit: "`+LFO_UNITS[ftol(17V+.5)] / "LFO 2 unit: " |
| 20/31 | `"L1 shape: "`+LFO_SHAPES[ftol(6V+.5)] |
| 21/32 | s = 3V<1 ? 1/(4-9V) : (1.5V-.5)*255+1; if LFO quantize [9520/9524] != 0: 3s<2 ? `"L1 speed: 1/%i units"` ftol(1/s+.5) : `"L1 speed: %i units"` ftol(s+.5); else s<1 ? `"L1 speed: 1/%.3f units"` 1/s : `"L1 speed: %.3f units"` s |
| 22/33 | `"L1: "` + ["free speed","quantize period"][ftol(V+.5)] |
| 23/34 | `"L1 mode: "` + ["per note","global, reset on note","global, free"][ftol(2V+.5)] |
| 24/25 (35/36) | `"L1 -> cutoff 1: %.4f octaves"` (2V-1)*4 |
| 26/37, 28/39 | `"L1 -> resonance: %.2f %%"`, `"L1 -> pan: %.2f %%"` 100V |
| 27/38 | `"L1 -> pitch: %.3f st"` 24V^4 |
| 29/40 | `"L1 -> L2 speed: %.2f %%"` / `"L2 -> L1 speed: %.2f %%"` 100V |
| 41 | `"Filter: "`+FILTER_TYPES[ftol(15V+.5)] (13..15 -> "") |
| 42 | ([8428]&0xffff)==0 or F double [8464]==0 ? `"Filter 2: off (filter 1 and doubling needs to be on)"` : `"Filter 2: "`+FILTER2_TYPES[ftol(15V+.5)] |
| 43 | hz=f32(V^3*10980+20), ref=Octave^(CutRef*f(1/12))*Tune; hz<ref ? `"Cutoff: %.2f Hz (/%.4f)"` (hz, ref/hz) : `"Cutoff: %.2f Hz (*%.4f)"` (hz, hz/ref) |
| 44, 54 | `"Resonance: %.2f %%"`, `"Filter mix: %.2f %%"` 100V |
| 45,60,166,238,254 | `"Attack: %.2f ms"` V^2*f(9999.8)+f(0.2) |
| 46,61,239,255 | `"Hold: %.2f ms"` V^2*10000 |
| 47,62,240,256 | own breakpoint field > f(0.998) ? `"Decay 1: skip (breakpoint is 0 dB)"` : `"Decay 1: %.2f ms"` V^2*19990+10 |
| 48,241,257 | V==0 ? `"Breakpoint: 0.00 %"` : b=10^((V-1)*3): b>f(0.998) ? `"Breakpoint: skip decay 1"` : `"Breakpoint: %.2f %%"` 100b |
| 50,243,259 | same with `"Sustain: 100.00 %"` / `"Sustain: %.2f %%"` |
| 63 / 65 (amp) | V!=0 and 10^((V-1)*3)>f(.998) ? `"Breakpoint: skip decay 1"` / `"Sustain: 0.00 dB (100.00 %)"`; else V<=0 ? `"Breakpoint: -inf dB (0.00 %)"`; else t=f32(V-1): `"Breakpoint: %.2f dB (%.2f %%)"` (60t, 100*10^(3t)) |
| 49,64,242,258 / 51,66,244,260 | `"Decay 2: %.2f ms"` / `"Release: %.2f ms"` V^2*19990+10 |
| 52 | `"Keytrack: %.4f"` snapped 4V-2 |
| 53 | `"Double filter: "`+["off","parallel","serial"][ftol(2V+.5)] |
| 55 | `"Split: %.2f st"` 24V |
| 56 | V<0.5 ? `"Env ratio: /%.3f"` (.5-V)*8+1 : `"Env ratio: *%.3f"` (V-.5)*8+1 |
| 57 | `"Env Mod: %.3f octaves"` (2V-1)*8 |
| 58,171,245,261 | `"Env velocity sensitivity: %.2f %%"` (2V-1)*100 |
| 59 | `"Aftertouch -> cutoff: %.2f semitones"` (2V-1)*48 |
| 67 / 68 | `"Chorus mode: "`+CHORUS_MODES[ftol(4V+.5)] / +CHORUS_STEREO[ftol(2V+.5)] |
| 69 | `"Chorus: %i voices"` ftol(15V+.5)+1 |
| 70 | `"Chorus speed: %.4f Hz"` V^2*f(3.999)+f(.001) |
| 71 / 72 | `"Chorus min delay: %.2f ms"` / `"Chorus depth: %.2f ms"` V*f(99.9)+f(.1) |
| 73 | `"Chorus feedback: %.2f %%"` 200V-100 ; 74 `"Chorus mix: %.2f %% wet"` 100V |
| 75,77,90 | `"Delay: "`+["off","on"], `"Delay: "`+["free length","quantize length"], `"Reverb: "`+["off","on"] |
| 76 | `"Delay unit: "`+DELAY_UNITS[ftol(14V+.5)] |
| 78/79 | `"Delay, left: "` / `"Delay, right: "` + ["normal","reverse output","reverse feedback"] |
| 80/81 | L=99V+1: D quantize [8656] ? `"Left length: %i units"` ftol(L+.5) : `"Left length: %.3f units"` L ("Right length") |
| 82/83 | x=4V-2; "small" = (V<.5 ? x > -f(.001) : x < f(.001)); small ? `"Left feedback: %.1f %% (-60.00+ dB)"` 100x : `"Left feedback: %.1f %% (%.2f dB)"` (100x, 20log10\|x\|) |
| 84 | `"Input pan: %.1f %% %s"` (\|200V-100\|, V>0.5 ? "right" : "left") |
| 85,100 / 97,98,99 | `"Rotation: %.3f Pi"` / `"1: %.3f Pi"`,`"2: ..."`,`"3: ..."` 2V-1 |
| 86/87/93/94 | `"Lowpass: %.1f %%"`, `"Highpass: %.1f %%"`, `"Dullness: %.1f %%"`, `"Brightness: %.1f %%"` 100V |
| 88,95 / 89,96 | V!=0 ? `"Dry: %.2f dB"` (90V-60) : `"Dry: -inf dB"` ("Wet") |
| 91 | `"Size: %.1f"` V^3*240+10 |
| 92 | V<1 ? `"Length: %.2f sec"` V^2*f(29.9)+f(.1) : `"Length: ETERNITY."` |
| 101 | `"Predelay: %.1f ms"` (2V-1)*500 ; 102 `"Early reflections mix: %.1f %%"` 100V |
| 103 | ["Monophonic","Polyphonic","Monophonic, legato"][ftol(2V+.5)] (no label, no ':') |
| 104 | `"Voices: %i"` ftol(31V+.5)+1 ; 105 `"Glide: %.2f ms"` 500V^2 ; 106 `"Glide mode: "`+GLIDE_MODES[ftol(6V+.5)] |
| 108 | `"Velocity: %.1f %%"` 200V-100 ; 109 `"Aftertouch mode: "`+AFTERTOUCH_MODES[ftol(2V+.5)] |
| 110 / 111 | `"Frequency pan: %.2f %%/octave"` (2V-1)*100 / `"Frequency env scale: %.2f %%/octave"` (2V-1)*200 |
| 112,115,116,118,119,121,122 | `"Random pan: %.2f %%"`, `"Osc phase: "`, `"Osc phase random: "`, `"PWM phase: "`, `"PWM phase random: "`, `"LFO phase: "`, `"LFO phase random: "` 100V |
| 113 / 114 | `"Random amp: %.2f dB"` 20V^2 / `"Random frequency: %.2f cents"` 1200V^2 |
| 117,120,123 | `"Osc retrigger: "`/`"PWM retrigger: "`/`"LFO retrigger: "` + (ftol(V+.5)!=0 ? "on" : "off") |
| 124 | `"U voices: %i"` ftol(15V+.5)+1 ; 125 `"U detune: %.2f cents"` 4800V^2 ; 126 `"U stereo spread: %.2f %%"` ; 127 `"U pitch jitter: %.2f %%"` ; 128 `"U pan jitter: %.2f %%"` |
| 129 / 130 / 131 | `"Arp mode: "`+ARP_MODES[ftol(5V+.5)] / `"Arp unit: "`+ARP_UNITS[ftol(17V+.5)] / `"Quantize: "`+["off","on"][ftol(V+.5)] |
| 132 | like 21 with s = V<=.25 ? 1/((1-4V)*7+1) : (V-.25)*f(41.3333)+1, label "Arp step", switch = Arp quantize [8852] |
| 133..148 | `"Arp step %i: "`+ARP_STEP_COMMANDS[ftol(15V+.5)] (%i = 1..16) |
| 149 | n=ftol(15V+.5): n==0 ? `"Arp pattern length: 1 step"` : `"Arp pattern length: %i steps"` n+1 |
| 150..156 | `"Arp note %i: %s"` (V>0.5 ? "on" : "off")  (NB: setParameter turns on at v>=0.5) |
| 157..163 | t=f32(2V-1): V<.5 ? `"Arp note %i: %.3f st (/%.4f)"` (36t, oct^(-3t)) : `"... (*%.4f)"` (36t, oct^(3t)) |
| 164 | V>0.5 ? `"Pitch envelope: on"` : `"Pitch envelope: off"` |
| 165 | V!=0 ? `"Start: %.2f st"` (2V-1)*48 : `"Start: -inf st"` ; 167 `"Peak: %.2f st"` ; 169 `"Sustain: %.2f st"` ; 170 `"Release: %.2f st/sec"` (all (2V-1)*48) ; 168 `"Decay: %.2f ms"` |
| 172/173/177 | `"Distortion: "`+DIST_TYPES[ftol(4V+.5)] / `"Distortion: "`+DIST_MODES[ftol(3V+.5)] / `"Distortion oversample: "`+DIST_OVERSAMPLE[ftol(3V+.5)] |
| 174/175/176 | `"Distortion limit: %.2f dB"` (2V-1)*30 / `"Distortion pregain: %.2f dB"` (2V-1)*60 / `"Distortion postgain: %.2f dB"` |
| 178 | `"Tune: %.2f Hz"` (2V-1)*80+440 |
| 179 | o = octave snap of 4V+1, s = 12*ln2/ln(o): s>96 ? `"Octave: %.6f (x2 > 96.0000 semitones)"` o : `"Octave: %.6f (x2 = %.4f semitones)"` (o, s) |
| 180 / 181 | t=f32(2V-1): `"Cutoff reference frequency: %.2f st (%.2f Hz)"` / `"Pan center frequency: ..."` (24t, Octave^(2t)*Tune) |
| 182..193 | c=f32((2V-1)*200): `"Tune C: %.2f cents (*%.4f)"` (c, Octave^((c+100k)*f(1/1200))), k = 0 (C) .. 11 (B); names C, C#/Db, D, D#/Eb, E, F, F#/Gb, G, G#/Ab, A, A#/Bb, B |
| 194 | `"Pitch bend range: %.2f st"` 24V^2 ; 195 `"Global transpose: %.0f st"` floor((2V-1)*48+.5) |
| 196/197 | `"X: %.4f"` / `"Y: %.4f"` 2V-1 |
| 198..201 / 207..210 | `"X mod depth %i: "` + unit text chosen by the matching X/Y target (4.3), x = 2V-1 |
| 202..205 / 211..214 | `"X mod target %i: "`+XY_TARGETS[ftol(33V+.5)] ("Y mod target", but index 26 is printed `"y mod target %i: ME 1 depth"` - DLL typo) |
| 206/215 | V>0 ? `"X CC: %03i"` ftol(127V+.5) : `"X CC: ---"` ("Y CC") |
| 216 / 217 | `"XY random radius: %.4f"` V / `"XY random rate: %.4f Hz"` 16V |
| 218..222 / 223..227 | `"EQ %i frequency: %.2f Hz"` V^3*19985+15 / `"EQ %i amp: %.2f dB"` (2V-1)*60 |
| 228..232 / 233..237 | `"EQ %i slope: %.3f"` (slope formula) / `"EQ %i type: "`+EQ_TYPES[ftol(3V+.5)] |
| 246..249 / 262..265 | `"M1 mod depth %i: "`/`"M2 mod depth %i: "` + unit text by target (4.3) |
| 250..253 / 266..269 | `"M1 mod target %i: "`+MOD_ENV_TARGETS[ftol(30V+.5)] |
| 270..285 | `"MIDI channel %i: %s"` (ftol(V+.5)!=0 ? "receive" : "ignore") ; 286 `"Sustain pedal: %s"` ("use"/"ignore") |
| CC c number | n=ftol(127V+.5): n>0 ? `"CC %i: %i"` (c, n) : `"CC %i: ---"` |
| CC c depth k | `"CC %i depth %i: "` + unit text by CC target k (cents: `"CC %i mod depth %i: %.2f cents"`) |
| CC c target k | t=ftol(34V+.5): t<=32 `"CC %i target %i: "`+CC_TARGETS[t]; t=33,34 `"CC %i mod target %i: "`+name; else `"CC %i target %i: ??? mystery value! Something is broken."` |
| 341 | `"Osc mix: "` + (t==1 ? "hardsync" : t==2 ? "FM (1 -> 2, 1 silent)" : "normal"), t=ftol(2V+.5) |

### 4.3 Mod-depth unit selection (byte tables in the DLL)
x = 2V-1; units: dB -> `"%.2f dB"` 60x; st -> `"%.2f semitones"` 24x; oct -> `"%.3f octaves"` (4x for X/Y and CC,
2x for M1/M2); cents -> `"%.2f cents"` 1200*x*\|x\|; otherwise `"%.2f %%"` 100x.

| depth of | target -> unit (all other targets, incl. 0 = none: percent) |
|---|---|
| X/Y (XY_TARGETS) | 1,2 oct; 5 st; 18,19,20 dB; 21,22,23 st; 32 cents |
| M1/M2 (MOD_ENV_TARGETS) | 1,2 oct; 7,8,9 st; 23,24 oct; 25,26,27 st; 29 cents |
| CC (CC_TARGETS) | 1,2 oct; 21,22,23 st; 33 cents |

### 4.4 Enumerations (value index = stored value)
* WAVEFORMS (0, 6): Sine, Saw, Pulse, Triangle, User, User PWM
* LFO_UNITS (19, 30): ms, 10 ms, sec, 4/5 16ths, 2/3 16ths, 16ths, 4/5 8ths, 2/3 8ths, 8ths, 4/5 quarter notes, 2/3 quarter notes, quarter notes, 4/5 half notes, 2/3 half notes, half notes, 4/5 whole notes, 2/3 whole notes, whole notes
* ARP_UNITS (130): ms, 10 ms, sec, 4/5 32nds, 2/3 32nds, 32nds, 4/5 16ths, 2/3 16ths, 16ths, 4/5 8ths, 2/3 8ths, 8ths, 4/5 quarter notes, 2/3 quarter notes, quarter notes, 4/5 half notes, 2/3 half notes, half notes
* DELAY_UNITS (76): ms, 10 ms, sec, 4/5 16ths, 2/3 16ths, 16ths, 4/5 8ths, 2/3 8ths, 8ths, 4/5 quarter notes, 2/3 quarter notes, quarter notes, 4/5 half notes, 2/3 half notes, half notes
* LFO_SHAPES (20, 31): Sine, Saw, Square, Triangle, Smooth random, Stepping random, User
* LFO_QUANTIZE (22, 33): free speed, quantize period; LFO_MODES (23, 34): per note, global, reset on note, global, free
* FILTER_TYPES (41): Off, 1P lowpass, 2P lowpass, 4P lowpass, 1P highpass, 2P highpass, 4P highpass, 2P wide bandpass, 2P narrow bandpass, 4P bandpass, 2P notch, nonlinear 2P lowpass, nonlinear 4P lowpass (13..15 invalid)
* FILTER2_TYPES (42): same list with 0 = "same as filter 1"
* FILTER_DOUBLE (53): off, parallel, serial
* CHORUS_MODES (67): off, sine, ramp, FM, irregular; CHORUS_STEREO (68): mono, stereo 1, stereo 2
* DELAY_REVERSE (78, 79): normal, reverse output, reverse feedback
* VOICE_MODES (103): Monophonic, Polyphonic, Monophonic, legato
* GLIDE_MODES (106): Param, P * octaves, P / octaves, P * (o + 1/o), P * (1 + o), P * (1 + 1/o), P * (1 + o + 1/o)
* AFTERTOUCH_MODES (109): ignore all, channel, polyphonic
* ARP_MODES (129): off, pattern, pattern (global subseq), chord pattern, chord, transposed chords
* ARP_STEP_COMMANDS (133..148): off, up, up, no wrap, down, down, no wrap, up or down, up or down, no wrap, continue, continue direction, continue direction, bounce, return, return, up, return, down, top, bottom, random
* DIST_TYPES (172): off, hard clip, soft clip, sine, asymmetric; DIST_MODES (173): global, per voice, after filter, per voice, before filter, double (before filter and global); DIST_OVERSAMPLE (177): off, 2x, 4x, 8x
* EQ_TYPES (233..237): off, peak/notch, low shelf, high shelf
* OSC_MIX (341): normal, hardsync, FM (1 -> 2, 1 silent)
* MIDI channel: ignore, receive; sustain pedal: ignore, use; on/off switches: off, on
* XY_TARGETS (34 entries, 202-205, 211-214): none, cutoff 1, cutoff 2, resonance, filter env mod, pitch, pan, distortion, LFO 1 speed, LFO 2 speed, LFO 1 depth, LFO 2 depth, 1 pulsewidth, 1 PWM rate, 1 PWM depth, 2 pulsewidth, 2 PWM rate, 2 PWM depth, 1 amp, 2 amp, noise amp, 1 pitch, 2 pitch, noise pitch, filter mix, noise resonance, ME 1 depth, ME 2 depth, amp envelope speed, filter envelope speed, mod envelope speed, pitch envelope speed, Unison detune, Unison spread
* MOD_ENV_TARGETS (31 entries, M1/M2): none, cutoff 1, cutoff 2, resonance, 1 amp, 2 amp, noise amp, 1 pitch, 2 pitch, noise pitch, 1 pulsewidth, 1 PWM rate, 1 PWM depth, 2 pulsewidth, 2 PWM rate, 2 PWM depth, pan, noise resonance, LFO 1 speed, LFO 2 speed, LFO 1 depth, LFO 2 depth, filter mix, cutoff 1 (unipolar), cutoff 2 (unipolar), 1 pitch (unipolar), 2 pitch (unipolar), noise pitch (unipolar), XY depth, Unison detune, Unison spread
* CC_TARGETS (35 entries): none, cutoff 1, cutoff 2, resonance, filter env mod, pitch, pan, distortion, LFO 1 speed, LFO 2 speed, LFO 1 depth, LFO 2 depth, 1 pulsewidth, 1 PWM rate, 1 PWM depth, 2 pulsewidth, 2 PWM rate, 2 PWM depth, 1 amp, 2 amp, noise amp, 1 pitch, 2 pitch, noise pitch, filter mix, noise resonance, ME 1 depth, ME 2 depth, XY depth, amp envelope speed, filter envelope speed, mod envelope speed, pitch envelope speed, Unison detune, Unison spread

### 4.5 Skin action names
The DLL maps `action=` names of `.oms` skins to parameter indices with a strcmp chain (0x100367bb); all 342
names were read off that function (e.g. O1_Waveform, O1_PWM_W = Pulsewidth, LFO_1_Sync = LFO 1 mode,
F_Speed = F envspeed, Sat_* = Dist *, XY_H_* = X, XY_V_* = Y, Arp_P0..Arp_PF = arp steps 1..16,
Arp_End = pattern length, Arp_Add_k_On/Shift = arp notes, U_Voices..U_PanJitter = unison). The string
table at 0x83254 lists them in index order except that "X" and "Y" share one 4-byte slot. Appendix B lists all.

---------------------------------------------------------------------------------------------------------

## 5. Verification (DLL as oracle)

All oracle data come from the real Oatmeal.dll driven by a 32-bit Python VST host (now `tools/re/vsthost.py`) plus direct calls of
internal functions (`work_presets/oracle.py`: a 10-byte stdcall->thiscall thunk lets ctypes call
0x100405f0 (status text, with an arbitrary program buffer), 0x1004c890 (getParameter), 0x10052d70 (defaults),
0x10052860/0x10052660 (target remap)). Commands (from OM): `PY32 work_presets/<dump>.py` then
`node work_presets/<test>.mjs`; full output in `work_presets/test_results.txt`.

| test | method | result |
|---|---|---|
| file conversion | `dump_dll_loads.py`: every file set_chunk'ed into the DLL (factory bank reloaded before each file; banks: effSetProgram 0..63 + get_chunk), compared with `parseFile` over chunk bytes 16..10376 (struct + name) | **4759 / 4759 programs byte-identical** in 160 files (1 omp, 33 omb, 86 fxp, 39 fxb, oatmealprs.dat); per-file table in Appendix A. Only exclusion: dword 10348 (stale slot content, 0 in practice). Oatmeal_Emdot1.fxb not loadable by the DLL (truncated). |
| all converter paths | `make_synth.mjs` builds v31..v37 programs and banks (real data, all old target indices incl. out-of-range), `dump_synth.py`, `test_synth.mjs` | 7 programs + 448 bank programs byte-identical (covers the v<=34 remap) |
| default program | direct call of 0x10052d70 on a zeroed buffer vs `makeDefaultProgram` | identical in all written bytes 16..10348 |
| derived fields | `dump_live.py`: live struct after process() for 256 programs at 44.1/48/96 kHz vs `recomputeDerived` | bit-identical (except the live runtime pointer at 8296) |
| setParameter | `dump_params.py`: 506 values per param (0..1 step 1/200, 300 random, edge values) through the real setParameter, chunk read back | **173052 / 173052 exact** (bit-identical words incl. packed filter word, second release field) |
| switch boundaries | `dump_bounds.py`: v = (k+0.5)/N and +-1,2 ulp for every switch | 4915 / 4915 exact (set, get, host display, status text) |
| getParameter | DLL getParameter after each setParameter | 173052 / 173052 exact (with the live-snap emulation) |
| host display | DLL effGetParamDisplay after each setParameter | 173052 / 173052 exact; Init program 342/342 = params.txt |
| status text | direct 0x100405f0 calls, 605 V values (incl. -0.25, 1.25) x 342 params x 4 program contexts (Init; Octave 3/Tune 460/CutRef 7/quantize on/breakpoints/filter 2 on/all kinds of depth targets; Octave 1.01; Octave 5) | **826272 / 826272 exact strings** |
| diffmap.json | the 41-sample DLL recording from the shared context | 14022 / 14022 exact (set, getParameter, display) |
| FxCk import | 36 real programs exported as FxCk, applied to the DLL with setParameter vs `parseFile` | 36 / 36 byte-identical |

---------------------------------------------------------------------------------------------------------

## 6. Open questions / not done
* 16..32 of the struct: no reader found (grep of the live struct base); treated as scratch. If another agent
  finds a reader, note that loaded values are the saving session's (typically 44100 / 21000.0).
* The GUI's own status-bar code path (editor) was not traced: it may pass its knob value directly to 0x100405f0
  (then the PWM rate status would show 2x the real rate) or the getParameter value (then the envspeed text is
  wrong above 0.5). `statusText` reproduces 0x100405f0 exactly for any V either way.
* MSVC prints NaN/inf as "-1.#IND00"/"1.#INF00" (with odd rounding for short precisions); `cfmt` only
  approximates these. They cannot occur for values in [0,1] except via NaN inputs.
* Version > 38 chunks trigger a Yes/No message box in the DLL; not exercised (JS: `{allowNewer:true}` loads
  them raw like the DLL's "Yes").
* The DLL's short-v38 and truncated-bank behaviour (keeps previous slot data) cannot be reproduced without the
  previous state; JS uses the default program for the missing part.

---------------------------------------------------------------------------------------------------------

## Appendix A. Per-file conversion results (JS `parseFile` vs Oatmeal.dll)

| file | container | version | programs byte-exact / total |
|---|---|---|---|
| Echopark_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| Klangmanipulation.omb | native | 35 | 64 / 64 |
| MokitaMadness_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| Oatmeal-bkjf1-vf.omb | native | 37 | 64 / 64 |
| Oatmeal36-1-burnie-arp.omb | native | 37 | 64 / 64 |
| Oatmeal36-1-burnie-leads.omb | native | 37 | 64 / 64 |
| Oatmeal36-1-burnie-pads.omb | native | 37 | 64 / 64 |
| Oatmeal_Cygnus-X1.omb | native | 37 | 64 / 64 |
| Oatmeal_Emdot1.omb | native | 37 | 64 / 64 |
| Oatmeal_Storyboard_01.omb | native | 37 | 64 / 64 |
| Oatmealv37-3_Ann_(24 more presets).omb | native | 37 | 64 / 64 |
| Oatmealv37-3_Ann_24_presets2.omb | native | 37 | 64 / 64 |
| Oatmealv37-3_Ann_Bank01.omb | native | 37 | 64 / 64 |
| Ourobros_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| ReverseEngineer_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| ReverseEngineer_Oatmeal_Bank_02.omb | native | 37 | 64 / 64 |
| SampleScience_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| TheControlCentre_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| TimConrardy_Oatmeal_Bank_01.omb | native | 37 | 64 / 64 |
| Zvon_oatmeal.omb | native | 37 | 64 / 64 |
| clav.omp | native | 36 | 1 / 1 |
| core_oatmeal_01_32.omb | native | 38 | 64 / 64 |
| core_oatmeal_02_64.omb | native | 38 | 64 / 64 |
| core_oatmeal_04_20.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_24D_.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_First_Timers_.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Four_Coverta_Meet.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Oatmeal_Favourites_Variations.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Second_Coming_.omb | native | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Third_Raieck.omb | native | 37 | 64 / 64 |
| Echopark Bank.fxb | fxb | 35 | 64 / 64 |
| Echopark_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| Klangmanipulation.fxb | fxb | 37 | 64 / 64 |
| MokitaMadness.fxb | fxb | 35 | 64 / 64 |
| MokitaMadness_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| Oatmeal-bkjf1-vf.fxb | fxb | 37 | 64 / 64 |
| Oatmeal36-1-burnie-arp.fxb | fxb | 36 | 64 / 64 |
| Oatmeal36-1-burnie-leads.fxb | fxb | 36 | 64 / 64 |
| Oatmeal36-1-burnie-pads.fxb | fxb | 36 | 64 / 64 |
| Oatmeal_Cygnus-X1.fxb | fxb | 37 | 64 / 64 |
| Oatmeal_Storyboard_01.fxb | fxb | 37 | 64 / 64 |
| Oatmealv37-3_Ann_(24 more presets).fxb | fxb | 37 | 64 / 64 |
| Oatmealv37-3_Ann_24_presets2.fxb | fxb | 37 | 64 / 64 |
| Oatmealv37-3_Ann_Bank01.fxb | fxb | 37 | 64 / 64 |
| Ourobros_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| RE_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| ReverseEngineer_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| ReverseEngineer_Oatmeal_Bank_02.fxb | fxb | 35 | 64 / 64 |
| SampleScience_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| TCC_Oatmeal_bank_1.fxb | fxb | 35 | 64 / 64 |
| TC_Oatmeal_1.fxb | fxb | 35 | 64 / 64 |
| TheControlCentre_Oatmeal_Bank_01.fxb | fxb | 35 | 64 / 64 |
| TimConrardy_Oatmeal_Bank_01.fxb | fxb | 37 | 64 / 64 |
| Zvon_oatmeal.fxb | fxb | 36 | 64 / 64 |
| core_oatmeal_01_32.fxb | fxb | 35 | 64 / 64 |
| core_oatmeal_02_64.fxb | fxb | 37 | 64 / 64 |
| core_oatmeal_04_20.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_First_Timers.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_First_Timers_.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Four_Coverta_Meet.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Oatmeal_Favourites_Variations.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Second_Coming.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Second_Coming_.fxb | fxb | 37 | 64 / 64 |
| djtuBIGMaliceX_-_Third_Raieck.fxb | fxb | 37 | 64 / 64 |
| oatmeal_alxstewart.fxb | fxb | 37 | 64 / 64 |
| oromeal1.fxb | fxb | 35 | 64 / 64 |
| rsmus7-bank-1.fxb | fxb | 37 | 64 / 64 |
| speccyteccy_oatmeal_1.fxb | fxb | 37 | 64 / 64 |
| ss_oatmeal_15pbank.fxb | fxb | 35 | 64 / 64 |
| Oatmeal - Clav.fxp | fxp | 38 | 1 / 1 |
| oatmeal_alxstewart.omb | native | 37 | 64 / 64 |
| oatmeal_tinga_soundz.omb | native | 37 | 64 / 64 |
| rsmus7-bank-1.omb | native | 37 | 64 / 64 |
| speccyteccy_oatmeal_1.omb | native | 35 | 64 / 64 |
| oatmealprs.dat | native | 38 | 64 / 64 |
| 84 x `fxp/Oatmeal <name>.fxp` + `Paul_Eye_-_Psybass.fxp` (all FPCh v35) | fxp | 35 | 85 / 85 |
| fxb/Oatmeal_Emdot1.fxb (truncated: 286208 of 662544 chunk bytes) | fxb | 37 | DLL refuses ("Not enough data!"); JS salvages 27 complete programs (lenient mode) |

## Appendix B. Parameter table

Generated by `work_presets/gen_param_table.mjs` (also `js/oatmeal-param-table.json`). offset = chunk offset (`+n` = second field written); type f32/i32/u32/lo16/hi16 (see 3); min/max = internal range over v in [0,1]; default = value in the Init program (= DLL defaults 0x10052d70); default text = DLL status text of the Init program; for switches the value names (index = stored value, minus `add` for voice counts).

| # | DLL name | action | offset | type | min | max | default (Init) | default text | states / unit |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 Waveform | O1_Waveform | 8468 | i32 | 0 | 5 | 0 | 1 Waveform: Sine | 6: Sine / Saw / Pulse / Triangle / User / User PWM |
| 1 | 1 Amp | O1_Amp | 8508 | f32 | 0 | 31.62278 | 1 | 1 Amp: 0.00 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 2 | 1 Afterpitch | O1_Afterpitch | 8476 | f32 | -48 | 48 | 0 | Aftertouch -> 1 pitch: 0.00 semitones | semitones |
| 3 | 1 Pulsewidth | O1_PWM_W | 8484 | u32 | 0 | 4294967295 | 2147483648 | 1 Pulsewidth: 50.00 % | % (uint32 fraction of 2^32) |
| 4 | 1 PWM rate | O1_PWM_R | 8500 | f32 | 0 | 8 | 0 | 1 PWM rate: 0.000 Hz | Hz |
| 5 | 1 PWM depth | O1_PWM_D | 8492 | f32 | -1 | 1 | 0 | 1 PWM depth: 0.00 % | bipolar -1..1 |
| 6 | 2 Waveform | O2_Waveform | 8472 | i32 | 0 | 5 | 0 | 2 Waveform: Sine | 6: Sine / Saw / Pulse / Triangle / User / User PWM |
| 7 | 2 Amp | O2_Amp | 8512 | f32 | 0 | 31.62278 | 0 | 2 Amp: -inf dB | linear gain (-60..+30 dB, 0 = -inf) |
| 8 | 2 Afterpitch | O2_Afterpitch | 8480 | f32 | -48 | 48 | 0 | Aftertouch -> 2 pitch: 0.00 semitones | semitones |
| 9 | 2 Pulsewidth | O2_PWM_W | 8488 | u32 | 0 | 4294967295 | 2147483648 | 2 Pulsewidth: 50.00 % | % (uint32 fraction of 2^32) |
| 10 | 2 PWM rate | O2_PWM_R | 8504 | f32 | 0 | 8 | 0 | 2 PWM rate: 0.000 Hz | Hz |
| 11 | 2 PWM depth | O2_PWM_D | 8496 | f32 | -1 | 1 | 0 | 2 PWM depth: 0.00 % | bipolar -1..1 |
| 12 | Transpose | Transpose | 8516 | f32 | -4 | 4 | 1 | Transpose: 12.00 st (*2.0000) | octaves (display: semitones = 12*x) |
| 13 | Detune | Detune | 8520 | f32 | -50 | 50 | 0 | Detune: 0.000 Hz | Hz |
| 14 | Osc aftertouch | OscAftertouch | 8524 | f32 | -60 | 60 | 0 | Aftertouch -> osc: 0.00 dB | dB |
| 15 | N amp | N_Amp | 8528 | f32 | 0 | 31.62278 | 0 | N Amp: -inf dB | linear gain (-60..+30 dB, 0 = -inf) |
| 16 | N aftertouch | N_Aftertouch | 8532 | f32 | -60 | 60 | 0 | Aftertouch -> noise: 0.00 dB | dB |
| 17 | N resonance | N_Resonance | 8540 | f32 | 0 | 1 | 0 | Noise resonance: no filtering | unipolar 0..1 |
| 18 | N transpose | N_Transpose | 8536 | f32 | -48 | 48 | 0 | Noise transpose: 0.00 st (*1.0000) | semitones |
| 19 | LFO 1 unit | LFO_1_Unit | 8544 | i32 | 0 | 17 | 1 | LFO 1 unit: 10 ms | 18: ms / 10 ms / sec / 4/5 16ths / 2/3 16ths / 16ths / 4/5 8ths / 2/3 8ths / 8ths / 4/5 quarter notes / 2/3 quarter notes / quarter notes / 4/5 half notes / 2/3 half notes / half notes / 4/5 whole notes / 2/3 whole notes / whole notes |
| 20 | LFO 1 shape | LFO_1_Shape | 8548 | i32 | 0 | 6 | 0 | L1 shape: Sine | 7: Sine / Saw / Square / Triangle / Smooth random / Stepping random / User |
| 21 | LFO 1 speed | LFO_1_Speed | 8556 | f32 | 0.25 | 256 | 20 | L1 speed: 20.000 units | units (periods per unit, see LFO unit) |
| 22 | LFO 1 quantize | LFO_1_Quantize | 9520 | i32 | 0 | 1 | 0 | L1: free speed | 2: free speed / quantize period |
| 23 | LFO 1 mode | LFO_1_Sync | 8552 | i32 | 0 | 2 | 2 | L1 mode: global, free | 3: per note / global, reset on note / global, free |
| 24 | LFO 1 cut 1 | LFO_1_Cutoff_1 | 8560 | f32 | -1 | 1 | 0 | L1 -> cutoff 1: 0.0000 octaves | x4 octaves |
| 25 | LFO 1 cut 2 | LFO_1_Cutoff_2 | 8564 | f32 | -1 | 1 | 0 | L1 -> cutoff 2: 0.0000 octaves | x4 octaves |
| 26 | LFO 1 res | LFO_1_Resonance | 8568 | f32 | 0 | 1 | 0 | L1 -> resonance: 0.00 % | unipolar 0..1 |
| 27 | LFO 1 pitch | LFO_1_Pitch | 8572 | f32 | 0 | 1 | 0 | L1 -> pitch: 0.000 st | st = 24*x^4 |
| 28 | LFO 1 pan | LFO_1_Pan | 9224 | f32 | 0 | 1 | 0 | L1 -> pan: 0.00 % | unipolar 0..1 |
| 29 | LFO 1 2 | LFO_1_2 | 8576 | f32 | 0 | 1 | 0 | L1 -> L2 speed: 0.00 % | unipolar 0..1 |
| 30 | LFO 1 unit | LFO_2_Unit | 8580 | i32 | 0 | 17 | 1 | LFO 2 unit: 10 ms | 18: ms / 10 ms / sec / 4/5 16ths / 2/3 16ths / 16ths / 4/5 8ths / 2/3 8ths / 8ths / 4/5 quarter notes / 2/3 quarter notes / quarter notes / 4/5 half notes / 2/3 half notes / half notes / 4/5 whole notes / 2/3 whole notes / whole notes |
| 31 | LFO 2 shape | LFO_2_Shape | 8584 | i32 | 0 | 6 | 0 | L2 shape: Sine | 7: Sine / Saw / Square / Triangle / Smooth random / Stepping random / User |
| 32 | LFO 2 speed | LFO_2_Speed | 8592 | f32 | 0.25 | 256 | 25 | L2 speed: 25.000 units | units (periods per unit, see LFO unit) |
| 33 | LFO 2 quantize | LFO_2_Quantize | 9524 | i32 | 0 | 1 | 0 | L2: free speed | 2: free speed / quantize period |
| 34 | LFO 2 mode | LFO_2_Sync | 8588 | i32 | 0 | 2 | 2 | L2 mode: global, free | 3: per note / global, reset on note / global, free |
| 35 | LFO 2 cut 1 | LFO_2_Cutoff_1 | 8596 | f32 | -1 | 1 | 0 | L2 -> cutoff 1: 0.0000 octaves | x4 octaves |
| 36 | LFO 2 cut 2 | LFO_2_Cutoff_2 | 8600 | f32 | -1 | 1 | 0 | L2 -> cutoff 2: 0.0000 octaves | x4 octaves |
| 37 | LFO 2 res | LFO_2_Resonance | 8604 | f32 | 0 | 1 | 0 | L2 -> resonance: 0.00 % | unipolar 0..1 |
| 38 | LFO 2 pitch | LFO_2_Pitch | 8608 | f32 | 0 | 1 | 0 | L2 -> pitch: 0.000 st | st = 24*x^4 |
| 39 | LFO 2 pan | LFO_2_Pan | 9228 | f32 | 0 | 1 | 0 | L2 -> pan: 0.00 % | unipolar 0..1 |
| 40 | LFO 2 1 | LFO_2_1 | 8612 | f32 | 0 | 1 | 0 | L2 -> L1 speed: 0.00 % | unipolar 0..1 |
| 41 | Filter | Filter | 8428 | lo16 | 0 | 12 | 0 | Filter: Off | 13: Off / 1P lowpass / 2P lowpass / 4P lowpass / 1P highpass / 2P highpass / 4P highpass / 2P wide bandpass / 2P narrow bandpass / 4P bandpass / 2P notch / nonlinear 2P lowpass / nonlinear 4P lowpass |
| 42 | Filter 2 | Filter2 | 8428 | hi16 | 0 | 12 | 0 | Filter 2: off (filter 1 and doubling needs to be on) | 13: same as filter 1 / 1P lowpass / 2P lowpass / 4P lowpass / 1P highpass / 2P highpass / 4P highpass / 2P wide bandpass / 2P narrow bandpass / 4P bandpass / 2P notch / nonlinear 2P lowpass / nonlinear 4P lowpass |
| 43 | Cutoff | Cutoff | 8432 | f32 | 0 | 1 | 0.5 | Cutoff: 1392.50 Hz (*3.1648) | normalized (Hz = v^3*10980+20) |
| 44 | Resonance | Resonance | 8436 | f32 | 0 | 1 | 0 | Resonance: 0.00 % | unipolar 0..1 |
| 45 | F attack | F_Attack | 8304 | f32 | 0.2 | 10000 | 5 | Attack: 5.00 ms | ms |
| 46 | F hold | F_Hold | 8308 | f32 | 0 | 10000 | 0 | Hold: 0.00 ms | ms |
| 47 | F decay 1 | F_Decay1 | 8312 | f32 | 10 | 20000 | 40 | Decay 1: skip (breakpoint is 0 dB) | ms |
| 48 | F breakpoint | F_Breakpoint | 8344 | f32 | 0 | 1 | 1 | Breakpoint: skip decay 1 |  |
| 49 | F decay 2 | F_Decay2 | 8316 | f32 | 10 | 20000 | 1000 | Decay 2: 1000.00 ms | ms |
| 50 | F sustain | F_Sustain | 8352 | f32 | 0 | 1 | 0.5 | Sustain: 50.00 % |  |
| 51 | F release | F_Release | 8320+8324 | f32 | 10 | 20000 | 50 | Release: 50.00 ms | ms |
| 52 | F keytrack | F_Track | 8444 | f32 | -2 | 2 | 0 | Keytrack: 0.0000 | keytrack factor (snapped to -1/0/1 within 0.001) |
| 53 | F double | F_Double | 8464 | i32 | 0 | 2 | 0 | Double filter: off | 3: off / parallel / serial |
| 54 | F mix | F_Mix | 8456 | f32 | 0 | 1 | 0.5 | Filter mix: 50.00 % | unipolar 0..1 |
| 55 | F split | F_Split | 8448 | f32 | 0 | 1 | 0.2916667 | Split: 7.00 st | x24 semitones |
| 56 | F envspeed | F_Speed | 8452 | f32 | 0.2 | 5 | 2 | Env ratio: /2.000 | filter-2 env time factor |
| 57 | F envmod | F_EnvMod | 8440 | f32 | -1 | 1 | 0 | Env Mod: 0.000 octaves | x8 octaves |
| 58 | F env velo sens | F_VeloSens | 9512 | f32 | -1 | 1 | 0 | Env velocity sensitivity: 0.00 % | bipolar -1..1 |
| 59 | F aftertouch | F_Aftertouch | 8460 | f32 | -48 | 48 | 0 | Aftertouch -> cutoff: 0.00 semitones | semitones |
| 60 | Attack | Attack | 8236 | f32 | 0.2 | 10000 | 5 | Attack: 5.00 ms | ms |
| 61 | Hold | Hold | 8240 | f32 | 0 | 10000 | 0 | Hold: 0.00 ms | ms |
| 62 | Decay 1 | Decay1 | 8244 | f32 | 10 | 20000 | 40 | Decay 1: skip (breakpoint is 0 dB) | ms |
| 63 | Breakpoint | Breakpoint | 8276 | f32 | 0 | 1 | 1 | Breakpoint: skip decay 1 |  |
| 64 | Decay 2 | Decay2 | 8248 | f32 | 10 | 20000 | 1000 | Decay 2: 1000.00 ms | ms |
| 65 | Sustain | Sustain | 8284 | f32 | 0 | 1 | 0.5 | Sustain: -6.02 dB (50.00 %) |  |
| 66 | Release | Release | 8252+8256 | f32 | 10 | 20000 | 50 | Release: 50.00 ms | ms |
| 67 | Chorus | C_Mode | 8616 | i32 | 0 | 4 | 0 | Chorus mode: off | 5: off / sine / ramp / FM / irregular |
| 68 | Chorus | C_Stereo | 8620 | i32 | 0 | 2 | 0 | Chorus mode: mono | 3: mono / stereo 1 / stereo 2 |
| 69 | C voices | C_Voices | 8624 | i32 | 1 | 16 | 4 | Chorus: 4 voices | 16 (voices) |
| 70 | C speed | C_Rate | 8628 | f32 | 0.001 | 4 | 0.02 | Chorus speed: 0.0200 Hz | Hz |
| 71 | C delay | C_MinDelay | 8632 | f32 | 0.1 | 100 | 4 | Chorus min delay: 4.00 ms | ms |
| 72 | C depth | C_Depth | 8636 | f32 | 0.1 | 100 | 8 | Chorus depth: 8.00 ms | ms |
| 73 | C feedback | C_Feedback | 8644 | f32 | -1 | 1 | 0 | Chorus feedback: 0.00 % | bipolar -1..1 |
| 74 | C mix | C_Mix | 8640 | f32 | 0 | 1 | 0.8 | Chorus mix: 80.00 % wet | unipolar 0..1 |
| 75 | Delay | D_On | 8648 | i32 | 0 | 1 | 0 | Delay: off | 2: off / on |
| 76 | D unit | D_Unit | 8652 | i32 | 0 | 14 | 5 | Delay unit: 16ths | 15: ms / 10 ms / sec / 4/5 16ths / 2/3 16ths / 16ths / 4/5 8ths / 2/3 8ths / 8ths / 4/5 quarter notes / 2/3 quarter notes / quarter notes / 4/5 half notes / 2/3 half notes / half notes |
| 77 | D quantize | D_Quantize | 8656 | i32 | 0 | 1 | 0 | Delay: free length | 2: free length / quantize length |
| 78 | D reverse | D_ReverseL | 8660 | i32 | 0 | 2 | 0 | Delay, left: normal | 3: normal / reverse output / reverse feedback |
| 79 | D reverse | D_ReverseR | 8664 | i32 | 0 | 2 | 0 | Delay, right: normal | 3: normal / reverse output / reverse feedback |
| 80 | D length L | D_LengthL | 8676 | f32 | 1 | 100 | 3 | Left length: 3.000 units | delay units |
| 81 | D length R | D_LengthR | 8684 | f32 | 1 | 100 | 3 | Right length: 3.000 units | delay units |
| 82 | D feedbk L | D_FeedbackL | 8680 | f32 | -2 | 2 | 0.7 | Left feedback: 70.0 % (-3.10 dB) | linear feedback gain |
| 83 | D feedbk R | D_FeedbackR | 8688 | f32 | -2 | 2 | 0.7 | Right feedback: 70.0 % (-3.10 dB) | linear feedback gain |
| 84 | D input pan | D_InputPan | 8668 | f32 | 0 | 1 | 0.5 | Input pan: 0.0 % left | unipolar 0..1 |
| 85 | D rotation | D_Rotation | 8672 | f32 | -3.141593 | 3.141593 | 0 | Rotation: 0.000 Pi | radians |
| 86 | D lowpass | D_LP | 8692 | f32 | 0 | 1 | 0.7 | Lowpass: 70.0 % | unipolar 0..1 |
| 87 | D highpass | D_HP | 8696 | f32 | 0 | 1 | 0 | Highpass: 0.0 % | unipolar 0..1 |
| 88 | D dry out | D_Dry | 8700 | f32 | 0 | 31.62278 | 1 | Dry: 0.00 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 89 | D wet out | D_Wet | 8704 | f32 | 0 | 31.62278 | 0.8 | Wet: -1.94 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 90 | Reverb | R_On | 8708 | i32 | 0 | 1 | 0 | Reverb: off | 2: off / on |
| 91 | R size | R_Size | 8712 | f32 | 10 | 250 | 30 | Size: 30.0 | size |
| 92 | R length | R_Length | 8716 | f32 | 0.1 | 120 | 1.2 | Length: 1.20 sec | sec (120 = infinite) |
| 93 | R dullness | R_Dullness | 8720 | f32 | 0 | 1 | 0.8 | Dullness: 80.0 % | unipolar 0..1 |
| 94 | R brightness | R_Brightness | 8724 | f32 | 0 | 1 | 0.2 | Brightness: 20.0 % | unipolar 0..1 |
| 95 | R dry out | R_Dry | 8728 | f32 | 0 | 31.62278 | 1 | Dry: 0.00 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 96 | R wet out | R_Wet | 8732 | f32 | 0 | 31.62278 | 0.2 | Wet: -13.98 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 97 | R 1 | R_1 | 8736 | f32 | -3.141593 | 3.141593 | -0.7225664 | 1: -0.230 Pi | radians |
| 98 | R 2 | R_2 | 8740 | f32 | -3.141593 | 3.141593 | -2.356194 | 2: -0.750 Pi | radians |
| 99 | R 3 | R_3 | 8744 | f32 | -3.141593 | 3.141593 | 0.8482301 | 3: 0.270 Pi | radians |
| 100 | R rotation | R_Rotation | 8748 | f32 | -3.141593 | 3.141593 | 2.261947 | Rotation: 0.720 Pi | radians |
| 101 | R predelay | R_Predelay | 8752 | f32 | -500 | 500 | 0 | Predelay: 0.0 ms | ms |
| 102 | R early mix | R_EarlyMix | 8756 | f32 | 0 | 1 | 0.5 | Early reflections mix: 50.0 % | unipolar 0..1 |
| 103 | Voice mode | PolyMode | 8760 | i32 | 0 | 2 | 1 | Polyphonic | 3: Monophonic / Polyphonic / Monophonic, legato |
| 104 | Max polyphony | Voices | 8764 | i32 | 1 | 32 | 8 | Voices: 8 | 32 (voices) |
| 105 | Glide | Glide | 8768 | f32 | 0 | 500 | 0 | Glide: 0.00 ms | ms |
| 106 | Glide mode | GlideMode | 8772 | i32 | 0 | 6 | 1 | Glide mode: P * octaves | 7: Param / P * octaves / P / octaves / P * (o + 1/o) / P * (1 + o) / P * (1 + 1/o) / P * (1 + o + 1/o) |
| 107 | Output gain | Gain | 8776 | f32 | 0 | 31.62278 | 0.1 | Gain: -20.00 dB | linear gain (-60..+30 dB, 0 = -inf) |
| 108 | Velocity sensitivity | VeloSens | 8780 | f32 | -1 | 1 | 0.65 | Velocity: 65.0 % | bipolar -1..1 |
| 109 | Aftertouch mode | AftertouchMode | 8784 | i32 | 0 | 2 | 2 | Aftertouch mode: polyphonic | 3: ignore all / channel / polyphonic |
| 110 | Frequency pan | FreqPan | 8788 | f32 | -1 | 1 | 0 | Frequency pan: 0.00 %/octave | bipolar -1..1 |
| 111 | Frequency env | FreqEnv | 8792 | f32 | -1 | 1 | 0 | Frequency env scale: 0.00 %/octave | bipolar -1..1 |
| 112 | Random pan | RandomPan | 8796 | f32 | 0 | 1 | 0 | Random pan: 0.00 % | unipolar 0..1 |
| 113 | Random amp | RandomAmp | 8800 | f32 | 0 | 20 | 1 | Random amp: 1.00 dB | dB |
| 114 | Random freq | RandomFreq | 8804 | f32 | 0 | 1200 | 1 | Random frequency: 1.00 cents | cents |
| 115 | Osc phase | OscPhase | 8808 | f32 | 0 | 1 | 0 | Osc phase: 0.00 % | unipolar 0..1 |
| 116 | Osc phase rand | OscPhaseRand | 8812 | f32 | 0 | 1 | 1 | Osc phase random: 100.00 % | unipolar 0..1 |
| 117 | Osc retrigger | OscRetrig | 8816 | i32 | 0 | 1 | 0 | Osc retrigger: off | 2: off / on |
| 118 | PWM phase | PWMPhase | 8820 | f32 | 0 | 1 | 0 | PWM phase: 0.00 % | unipolar 0..1 |
| 119 | PWM phase rand | PWMPhaseRand | 8824 | f32 | 0 | 1 | 1 | PWM phase random: 100.00 % | unipolar 0..1 |
| 120 | PWM retrigger | PWMRetrig | 8828 | i32 | 0 | 1 | 0 | PWM retrigger: off | 2: off / on |
| 121 | LFO phase | LFOPhase | 8832 | f32 | 0 | 1 | 0 | LFO phase: 0.00 % | unipolar 0..1 |
| 122 | LFO phase rand | LFOPhaseRand | 8836 | f32 | 0 | 1 | 0 | LFO phase random: 0.00 % | unipolar 0..1 |
| 123 | LFO retrigger | LFORetrig | 8840 | i32 | 0 | 1 | 1 | LFO retrigger: on | 2: off / on |
| 124 | (empty) | U_Voices | 10328 | i32 | 1 | 16 | 1 | U voices: 1 | 16 (voices) |
| 125 | (empty) | U_Detune | 10332 | f32 | 0 | 4800 | 1 | U detune: 1.00 cents | cents |
| 126 | (empty) | U_Spread | 10336 | f32 | 0 | 1 | 0.25 | U stereo spread: 25.00 % | unipolar 0..1 |
| 127 | (empty) | U_PitchJitter | 10340 | f32 | 0 | 1 | 0 | U pitch jitter: 0.00 % | unipolar 0..1 |
| 128 | (empty) | U_PanJitter | 10344 | f32 | 0 | 1 | 0 | U pan jitter: 0.00 % | unipolar 0..1 |
| 129 | Arp mode | Arp_Mode | 8844 | i32 | 0 | 5 | 0 | Arp mode: off | 6: off / pattern / pattern (global subseq) / chord pattern / chord / transposed chords |
| 130 | Arp unit | Arp_Unit | 8848 | i32 | 0 | 17 | 8 | Arp unit: 16ths | 18: ms / 10 ms / sec / 4/5 32nds / 2/3 32nds / 32nds / 4/5 16ths / 2/3 16ths / 16ths / 4/5 8ths / 2/3 8ths / 8ths / 4/5 quarter notes / 2/3 quarter notes / quarter notes / 4/5 half notes / 2/3 half notes / half notes |
| 131 | Arp quantize | Arp_Quantize | 8852 | i32 | 0 | 1 | 1 | Quantize: on | 2: off / on |
| 132 | Arp step | Arp_Step | 8856 | f32 | 0.125 | 32 | 1 | Arp step: 1 units | arp units per step |
| 133 | Arp step 1 | Arp_P0 | 8860 | i32 | 0 | 15 | 1 | Arp step 1: up | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 134 | Arp step 2 | Arp_P1 | 8864 | i32 | 0 | 15 | 0 | Arp step 2: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 135 | Arp step 3 | Arp_P2 | 8868 | i32 | 0 | 15 | 0 | Arp step 3: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 136 | Arp step 4 | Arp_P3 | 8872 | i32 | 0 | 15 | 1 | Arp step 4: up | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 137 | Arp step 5 | Arp_P4 | 8876 | i32 | 0 | 15 | 0 | Arp step 5: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 138 | Arp step 6 | Arp_P5 | 8880 | i32 | 0 | 15 | 0 | Arp step 6: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 139 | Arp step 7 | Arp_P6 | 8884 | i32 | 0 | 15 | 1 | Arp step 7: up | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 140 | Arp step 8 | Arp_P7 | 8888 | i32 | 0 | 15 | 0 | Arp step 8: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 141 | Arp step 9 | Arp_P8 | 8892 | i32 | 0 | 15 | 0 | Arp step 9: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 142 | Arp step 10 | Arp_P9 | 8896 | i32 | 0 | 15 | 0 | Arp step 10: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 143 | Arp step 11 | Arp_PA | 8900 | i32 | 0 | 15 | 0 | Arp step 11: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 144 | Arp step 12 | Arp_PB | 8904 | i32 | 0 | 15 | 0 | Arp step 12: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 145 | Arp step 13 | Arp_PC | 8908 | i32 | 0 | 15 | 0 | Arp step 13: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 146 | Arp step 14 | Arp_PD | 8912 | i32 | 0 | 15 | 0 | Arp step 14: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 147 | Arp step 15 | Arp_PE | 8916 | i32 | 0 | 15 | 0 | Arp step 15: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 148 | Arp step 16 | Arp_PF | 8920 | i32 | 0 | 15 | 0 | Arp step 16: off | 16: off / up / up, no wrap / down / down, no wrap / up or down / up or down, no wrap / continue / continue direction / continue direction, bounce / return / return, up / return, down / top / bottom / random |
| 149 | Arp pattern length | Arp_End | 8924 | i32 | 0 | 15 | 7 | Arp pattern length: 8 steps | 16 (steps-1) |
| 150 | Arp note 1 on | Arp_Add_1_On | 8928 | i32 | 0 | 1 | 0 | Arp note 1: off | 2: off / on |
| 151 | Arp note 2 on | Arp_Add_2_On | 8932 | i32 | 0 | 1 | 0 | Arp note 2: off | 2: off / on |
| 152 | Arp note 3 on | Arp_Add_3_On | 8936 | i32 | 0 | 1 | 0 | Arp note 3: off | 2: off / on |
| 153 | Arp note 4 on | Arp_Add_4_On | 8940 | i32 | 0 | 1 | 0 | Arp note 4: off | 2: off / on |
| 154 | Arp note 5 on | Arp_Add_5_On | 8944 | i32 | 0 | 1 | 0 | Arp note 5: off | 2: off / on |
| 155 | Arp note 6 on | Arp_Add_6_On | 8948 | i32 | 0 | 1 | 0 | Arp note 6: off | 2: off / on |
| 156 | Arp note 7 on | Arp_Add_7_On | 8952 | i32 | 0 | 1 | 0 | Arp note 7: off | 2: off / on |
| 157 | Arp note 1 shift | Arp_Add_1_Shift | 8956 | f32 | -36 | 36 | 0 | Arp note 1: 0.000 st (*1.0000) | semitones |
| 158 | Arp note 2 shift | Arp_Add_2_Shift | 8960 | f32 | -36 | 36 | 0 | Arp note 2: 0.000 st (*1.0000) | semitones |
| 159 | Arp note 3 shift | Arp_Add_3_Shift | 8964 | f32 | -36 | 36 | 0 | Arp note 3: 0.000 st (*1.0000) | semitones |
| 160 | Arp note 4 shift | Arp_Add_4_Shift | 8968 | f32 | -36 | 36 | 0 | Arp note 4: 0.000 st (*1.0000) | semitones |
| 161 | Arp note 5 shift | Arp_Add_5_Shift | 8972 | f32 | -36 | 36 | 0 | Arp note 5: 0.000 st (*1.0000) | semitones |
| 162 | Arp note 6 shift | Arp_Add_6_Shift | 8976 | f32 | -36 | 36 | 0 | Arp note 6: 0.000 st (*1.0000) | semitones |
| 163 | Arp note 7 shift | Arp_Add_7_Shift | 8980 | f32 | -36 | 36 | 0 | Arp note 7: 0.000 st (*1.0000) | semitones |
| 164 | P env on | PEnv_On | 8984 | i32 | 0 | 1 | 0 | Pitch envelope: off | 2: off / on |
| 165 | P start | PEnv_Start | 8988 | f32 | -48 | 48 | -12 | Start: -12.00 st | semitones (<= -48: no start offset) |
| 166 | P attack | PEnv_Attack | 8996 | f32 | 0.2 | 10000 | 20 | Attack: 20.00 ms | ms |
| 167 | P peak | PEnv_Peak | 9004 | f32 | -48 | 48 | 12 | Peak: 12.00 st | semitones |
| 168 | P decay | PEnv_Decay | 9012 | f32 | 10 | 20000 | 100 | Decay: 100.00 ms | ms |
| 169 | P sustain | PEnv_Sustain | 9020 | f32 | -48 | 48 | 0 | Sustain: 0.00 st | semitones |
| 170 | P release | PEnv_Release | 9028 | f32 | -48 | 48 | 0 | Release: 0.00 st/sec | semitones/sec |
| 171 | P env velo sens | PEnv_VeloSens | 9516 | f32 | -1 | 1 | 0 | Env velocity sensitivity: 0.00 % | bipolar -1..1 |
| 172 | Dist type | Sat_Type | 9036 | i32 | 0 | 4 | 0 | Distortion: off | 5: off / hard clip / soft clip / sine / asymmetric |
| 173 | Dist mode | Sat_Mode | 9040 | i32 | 0 | 3 | 0 | Distortion: global | 4: global / per voice, after filter / per voice, before filter / double (before filter and global) |
| 174 | Dist limit | Sat_Limit | 9044 | f32 | -30 | 30 | 0 | Distortion limit: 0.00 dB | dB |
| 175 | Dist pregain | Sat_Pregain | 9048 | f32 | -60 | 60 | 0 | Distortion pregain: 0.00 dB | dB |
| 176 | Dist postgain | Sat_Postgain | 9052 | f32 | -60 | 60 | 0 | Distortion postgain: 0.00 dB | dB |
| 177 | Dist oversample | Sat_Oversample | 9056 | i32 | 0 | 3 | 0 | Distortion oversample: off | 4: off / 2x / 4x / 8x |
| 178 | Tune main | Tune_Main | 9060 | f32 | 360 | 520 | 440 | Tune: 440.00 Hz | Hz |
| 179 | Octave | Tune_Octave | 9064 | f32 | 1.01 | 5 | 2 | Octave: 2.000000 (x2 = 12.0000 semitones) | frequency ratio of an "octave" (2 = normal) |
| 180 | Cut reference | Tune_CutReference | 9072 | f32 | -24 | 24 | 0 | Cutoff reference frequency: 0.00 st (440.00 Hz) | semitones |
| 181 | Pan reference | Tune_PanReference | 9076 | f32 | -24 | 24 | -9 | Pan center frequency: -9.00 st (261.63 Hz) | semitones |
| 182 | Tune C | Tune_C | 9080 | f32 | -200 | 200 | 0 | Tune C: 0.00 cents (*1.0000) | cents |
| 183 | Tune C#/Db | Tune_Db | 9084 | f32 | -200 | 200 | 0 | Tune C#/Db: 0.00 cents (*1.0595) | cents |
| 184 | Tune D | Tune_D | 9088 | f32 | -200 | 200 | 0 | Tune D: 0.00 cents (*1.1225) | cents |
| 185 | Tune D#/Eb | Tune_Eb | 9092 | f32 | -200 | 200 | 0 | Tune D#/Eb: 0.00 cents (*1.1892) | cents |
| 186 | Tune E | Tune_E | 9096 | f32 | -200 | 200 | 0 | Tune E: 0.00 cents (*1.2599) | cents |
| 187 | Tune F | Tune_F | 9100 | f32 | -200 | 200 | 0 | Tune F: 0.00 cents (*1.3348) | cents |
| 188 | Tune F#/Gb | Tune_Gb | 9104 | f32 | -200 | 200 | 0 | Tune F#/Gb: 0.00 cents (*1.4142) | cents |
| 189 | Tune G | Tune_G | 9108 | f32 | -200 | 200 | 0 | Tune G: 0.00 cents (*1.4983) | cents |
| 190 | Tune G#/Ab | Tune_Ab | 9112 | f32 | -200 | 200 | 0 | Tune G#/Ab: 0.00 cents (*1.5874) | cents |
| 191 | Tune A | Tune_A | 9116 | f32 | -200 | 200 | 0 | Tune A: 0.00 cents (*1.6818) | cents |
| 192 | Tune A#/Bb | Tune_Bb | 9120 | f32 | -200 | 200 | 0 | Tune A#/Bb: 0.00 cents (*1.7818) | cents |
| 193 | Tune B | Tune_B | 9124 | f32 | -200 | 200 | 0 | Tune B: 0.00 cents (*1.8877) | cents |
| 194 | Bend range | BendRange | 9128 | f32 | 0 | 24 | 12 | Pitch bend range: 12.00 st | semitones |
| 195 | Global transpose | GlobalTranspose | 9132 | f32 | -4 | 4 | 0 | Global transpose: 0 st | octaves (quantized to semitones) |
| 196 | X | X | 9136 | f32 | -1 | 1 | 0 | X: 0.0000 | bipolar -1..1 |
| 197 | Y | Y | 9140 | f32 | -1 | 1 | 0 | Y: 0.0000 | bipolar -1..1 |
| 198 | X depth 1 | XY_H_Depth_1 | 9144 | f32 | -1 | 1 | 0 | X mod depth 1: 0.00 % | bipolar -1..1 |
| 199 | X depth 2 | XY_H_Depth_2 | 9148 | f32 | -1 | 1 | 0 | X mod depth 2: 0.00 % | bipolar -1..1 |
| 200 | X depth 3 | XY_H_Depth_3 | 9152 | f32 | -1 | 1 | 0 | X mod depth 3: 0.00 % | bipolar -1..1 |
| 201 | X depth 4 | XY_H_Depth_4 | 9156 | f32 | -1 | 1 | 0 | X mod depth 4: 0.00 % | bipolar -1..1 |
| 202 | X target 1 | XY_H_Target_1 | 9160 | i32 | 0 | 33 | 0 | X mod target 1: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 203 | X target 2 | XY_H_Target_2 | 9164 | i32 | 0 | 33 | 0 | X mod target 2: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 204 | X target 3 | XY_H_Target_3 | 9168 | i32 | 0 | 33 | 0 | X mod target 3: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 205 | X target 4 | XY_H_Target_4 | 9172 | i32 | 0 | 33 | 0 | X mod target 4: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 206 | X CC | XY_H_CC | 9176 | i32 | 0 | 127 | 0 | X CC: --- | 128 (MIDI CC number (0 = none)) |
| 207 | Y depth 1 | XY_V_Depth_1 | 9180 | f32 | -1 | 1 | 0 | Y mod depth 1: 0.00 % | bipolar -1..1 |
| 208 | Y depth 2 | XY_V_Depth_2 | 9184 | f32 | -1 | 1 | 0 | Y mod depth 2: 0.00 % | bipolar -1..1 |
| 209 | Y depth 3 | XY_V_Depth_3 | 9188 | f32 | -1 | 1 | 0 | Y mod depth 3: 0.00 % | bipolar -1..1 |
| 210 | Y depth 4 | XY_V_Depth_4 | 9192 | f32 | -1 | 1 | 0 | Y mod depth 4: 0.00 % | bipolar -1..1 |
| 211 | Y target 1 | XY_V_Target_1 | 9196 | i32 | 0 | 33 | 0 | Y mod target 1: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 212 | Y target 2 | XY_V_Target_2 | 9200 | i32 | 0 | 33 | 0 | Y mod target 2: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 213 | Y target 3 | XY_V_Target_3 | 9204 | i32 | 0 | 33 | 0 | Y mod target 3: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 214 | Y target 4 | XY_V_Target_4 | 9208 | i32 | 0 | 33 | 0 | Y mod target 4: none | 34: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 215 | Y CC | XY_V_CC | 9212 | i32 | 0 | 127 | 0 | Y CC: --- | 128 (MIDI CC number (0 = none)) |
| 216 | XY var radius | XY_Var_Radius | 9216 | f32 | 0 | 1 | 0 | XY random radius: 0.0000 | unipolar 0..1 |
| 217 | XY var rate | XY_Var_Rate | 9220 | f32 | 0 | 16 | 0 | XY random rate: 0.0000 Hz | Hz |
| 218 | EQ 1 freq | EQ_1_Freq | 9232 | f32 | 15 | 20000 | 1000 | EQ 1 frequency: 1000.00 Hz | Hz |
| 219 | EQ 2 freq | EQ_2_Freq | 9236 | f32 | 15 | 20000 | 1000 | EQ 2 frequency: 1000.00 Hz | Hz |
| 220 | EQ 3 freq | EQ_3_Freq | 9240 | f32 | 15 | 20000 | 1000 | EQ 3 frequency: 1000.00 Hz | Hz |
| 221 | EQ 4 freq | EQ_4_Freq | 9244 | f32 | 15 | 20000 | 1000 | EQ 4 frequency: 1000.00 Hz | Hz |
| 222 | EQ 5 freq | EQ_5_Freq | 9248 | f32 | 15 | 20000 | 1000 | EQ 5 frequency: 1000.00 Hz | Hz |
| 223 | EQ 1 amp | EQ_1_Amp | 9252 | f32 | -60 | 60 | 0 | EQ 1 amp: 0.00 dB | dB |
| 224 | EQ 2 amp | EQ_2_Amp | 9256 | f32 | -60 | 60 | 0 | EQ 2 amp: 0.00 dB | dB |
| 225 | EQ 3 amp | EQ_3_Amp | 9260 | f32 | -60 | 60 | 0 | EQ 3 amp: 0.00 dB | dB |
| 226 | EQ 4 amp | EQ_4_Amp | 9264 | f32 | -60 | 60 | 0 | EQ 4 amp: 0.00 dB | dB |
| 227 | EQ 5 amp | EQ_5_Amp | 9268 | f32 | -60 | 60 | 0 | EQ 5 amp: 0.00 dB | dB |
| 228 | EQ 1 slope | EQ_1_Slope | 9272 | f32 | 0.0625 | 16 | 1 | EQ 1 slope: 1.000 | slope factor |
| 229 | EQ 2 slope | EQ_2_Slope | 9276 | f32 | 0.0625 | 16 | 1 | EQ 2 slope: 1.000 | slope factor |
| 230 | EQ 3 slope | EQ_3_Slope | 9280 | f32 | 0.0625 | 16 | 1 | EQ 3 slope: 1.000 | slope factor |
| 231 | EQ 4 slope | EQ_4_Slope | 9284 | f32 | 0.0625 | 16 | 1 | EQ 4 slope: 1.000 | slope factor |
| 232 | EQ 5 slope | EQ_5_Slope | 9288 | f32 | 0.0625 | 16 | 1 | EQ 5 slope: 1.000 | slope factor |
| 233 | EQ 1 type | EQ_1_Type | 9292 | i32 | 0 | 3 | 0 | EQ 1 type: off | 4: off / peak/notch / low shelf / high shelf |
| 234 | EQ 2 type | EQ_2_Type | 9296 | i32 | 0 | 3 | 0 | EQ 2 type: off | 4: off / peak/notch / low shelf / high shelf |
| 235 | EQ 3 type | EQ_3_Type | 9300 | i32 | 0 | 3 | 0 | EQ 3 type: off | 4: off / peak/notch / low shelf / high shelf |
| 236 | EQ 4 type | EQ_4_Type | 9304 | i32 | 0 | 3 | 0 | EQ 4 type: off | 4: off / peak/notch / low shelf / high shelf |
| 237 | EQ 5 type | EQ_5_Type | 9308 | i32 | 0 | 3 | 0 | EQ 5 type: off | 4: off / peak/notch / low shelf / high shelf |
| 238 | M1 attack | M1_Attack | 9316 | f32 | 0.2 | 10000 | 5 | Attack: 5.00 ms | ms |
| 239 | M1 hold | M1_Hold | 9320 | f32 | 0 | 10000 | 0 | Hold: 0.00 ms | ms |
| 240 | M1 decay 1 | M1_Decay1 | 9324 | f32 | 10 | 20000 | 40 | Decay 1: skip (breakpoint is 0 dB) | ms |
| 241 | M1 breakpoint | M1_Breakpoint | 9356 | f32 | 0 | 1 | 1 | Breakpoint: skip decay 1 |  |
| 242 | M1 decay 2 | M1_Decay2 | 9328 | f32 | 10 | 20000 | 1000 | Decay 2: 1000.00 ms | ms |
| 243 | M1 sustain | M1_Sustain | 9364 | f32 | 0 | 1 | 0.5 | Sustain: 50.00 % |  |
| 244 | M1 release | M1_Release | 9332+9336 | f32 | 10 | 20000 | 50 | Release: 50.00 ms | ms |
| 245 | M1 velo sens | M1_VeloSens | 9504 | f32 | -1 | 1 | 0 | Env velocity sensitivity: 0.00 % | bipolar -1..1 |
| 246 | M1 depth 1 | M1_Depth_1 | 9376 | f32 | -1 | 1 | 0 | M1 mod depth 1: 0.00 % | bipolar -1..1 |
| 247 | M1 depth 2 | M1_Depth_2 | 9380 | f32 | -1 | 1 | 0 | M1 mod depth 2: 0.00 % | bipolar -1..1 |
| 248 | M1 depth 3 | M1_Depth_3 | 9384 | f32 | -1 | 1 | 0 | M1 mod depth 3: 0.00 % | bipolar -1..1 |
| 249 | M1 depth 4 | M1_Depth_4 | 9388 | f32 | -1 | 1 | 0 | M1 mod depth 4: 0.00 % | bipolar -1..1 |
| 250 | M1 target 1 | M1_Target_1 | 9392 | i32 | 0 | 30 | 0 | M1 mod target 1: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 251 | M1 target 2 | M1_Target_2 | 9396 | i32 | 0 | 30 | 0 | M1 mod target 2: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 252 | M1 target 3 | M1_Target_3 | 9400 | i32 | 0 | 30 | 0 | M1 mod target 3: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 253 | M1 target 4 | M1_Target_4 | 9404 | i32 | 0 | 30 | 0 | M1 mod target 4: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 254 | M2 attack | M2_Attack | 9412 | f32 | 0.2 | 10000 | 5 | Attack: 5.00 ms | ms |
| 255 | M2 hold | M2_Hold | 9416 | f32 | 0 | 10000 | 0 | Hold: 0.00 ms | ms |
| 256 | M2 decay 1 | M2_Decay1 | 9420 | f32 | 10 | 20000 | 40 | Decay 1: skip (breakpoint is 0 dB) | ms |
| 257 | M2 breakpoint | M2_Breakpoint | 9452 | f32 | 0 | 1 | 1 | Breakpoint: skip decay 1 |  |
| 258 | M2 decay 2 | M2_Decay2 | 9424 | f32 | 10 | 20000 | 1000 | Decay 2: 1000.00 ms | ms |
| 259 | M2 sustain | M2_Sustain | 9460 | f32 | 0 | 1 | 0.5 | Sustain: 50.00 % |  |
| 260 | M2 release | M2_Release | 9428+9432 | f32 | 10 | 20000 | 50 | Release: 50.00 ms | ms |
| 261 | M2 velo sens | M2_VeloSens | 9508 | f32 | -1 | 1 | 0 | Env velocity sensitivity: 0.00 % | bipolar -1..1 |
| 262 | M2 depth 1 | M2_Depth_1 | 9472 | f32 | -1 | 1 | 0 | M2 mod depth 1: 0.00 % | bipolar -1..1 |
| 263 | M2 depth 2 | M2_Depth_2 | 9476 | f32 | -1 | 1 | 0 | M2 mod depth 2: 0.00 % | bipolar -1..1 |
| 264 | M2 depth 3 | M2_Depth_3 | 9480 | f32 | -1 | 1 | 0 | M2 mod depth 3: 0.00 % | bipolar -1..1 |
| 265 | M2 depth 4 | M2_Depth_4 | 9484 | f32 | -1 | 1 | 0 | M2 mod depth 4: 0.00 % | bipolar -1..1 |
| 266 | M2 target 1 | M2_Target_1 | 9488 | i32 | 0 | 30 | 0 | M2 mod target 1: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 267 | M2 target 2 | M2_Target_2 | 9492 | i32 | 0 | 30 | 0 | M2 mod target 2: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 268 | M2 target 3 | M2_Target_3 | 9496 | i32 | 0 | 30 | 0 | M2 mod target 3: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 269 | M2 target 4 | M2_Target_4 | 9500 | i32 | 0 | 30 | 0 | M2 mod target 4: none | 31: none / cutoff 1 / cutoff 2 / resonance / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / pan / noise resonance / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / filter mix / cutoff 1 (unipolar) / cutoff 2 (unipolar) / 1 pitch (unipolar) / 2 pitch (unipolar) / noise pitch (unipolar) / XY depth / Unison detune / Unison spread |
| 270 | MIDI channel 1 | MIDI_Channel_1 | 9528 | i32 | 0 | 1 | 1 | MIDI channel 1: receive | 2: ignore / receive |
| 271 | MIDI channel 2 | MIDI_Channel_2 | 9532 | i32 | 0 | 1 | 1 | MIDI channel 2: receive | 2: ignore / receive |
| 272 | MIDI channel 3 | MIDI_Channel_3 | 9536 | i32 | 0 | 1 | 1 | MIDI channel 3: receive | 2: ignore / receive |
| 273 | MIDI channel 4 | MIDI_Channel_4 | 9540 | i32 | 0 | 1 | 1 | MIDI channel 4: receive | 2: ignore / receive |
| 274 | MIDI channel 5 | MIDI_Channel_5 | 9544 | i32 | 0 | 1 | 1 | MIDI channel 5: receive | 2: ignore / receive |
| 275 | MIDI channel 6 | MIDI_Channel_6 | 9548 | i32 | 0 | 1 | 1 | MIDI channel 6: receive | 2: ignore / receive |
| 276 | MIDI channel 7 | MIDI_Channel_7 | 9552 | i32 | 0 | 1 | 1 | MIDI channel 7: receive | 2: ignore / receive |
| 277 | MIDI channel 8 | MIDI_Channel_8 | 9556 | i32 | 0 | 1 | 1 | MIDI channel 8: receive | 2: ignore / receive |
| 278 | MIDI channel 9 | MIDI_Channel_9 | 9560 | i32 | 0 | 1 | 1 | MIDI channel 9: receive | 2: ignore / receive |
| 279 | MIDI channel 10 | MIDI_Channel_10 | 9564 | i32 | 0 | 1 | 1 | MIDI channel 10: receive | 2: ignore / receive |
| 280 | MIDI channel 11 | MIDI_Channel_11 | 9568 | i32 | 0 | 1 | 1 | MIDI channel 11: receive | 2: ignore / receive |
| 281 | MIDI channel 12 | MIDI_Channel_12 | 9572 | i32 | 0 | 1 | 1 | MIDI channel 12: receive | 2: ignore / receive |
| 282 | MIDI channel 13 | MIDI_Channel_13 | 9576 | i32 | 0 | 1 | 1 | MIDI channel 13: receive | 2: ignore / receive |
| 283 | MIDI channel 14 | MIDI_Channel_14 | 9580 | i32 | 0 | 1 | 1 | MIDI channel 14: receive | 2: ignore / receive |
| 284 | MIDI channel 15 | MIDI_Channel_15 | 9584 | i32 | 0 | 1 | 1 | MIDI channel 15: receive | 2: ignore / receive |
| 285 | MIDI channel 16 | MIDI_Channel_16 | 9588 | i32 | 0 | 1 | 1 | MIDI channel 16: receive | 2: ignore / receive |
| 286 | Sustain pedal | SustainPedal | 9592 | i32 | 0 | 1 | 1 | Sustain pedal: use | 2: ignore / use |
| 287 | CC 1 | CC1 | 10108 | i32 | 0 | 127 | 0 | CC 1: --- | 128 (MIDI CC number (0 = none)) |
| 288 | CC 1 depth 1 | CC1_Depth_1 | 10112 | f32 | -1 | 1 | 0 | CC 1 depth 1: 0.00 % | bipolar -1..1 |
| 289 | CC 1 depth 2 | CC1_Depth_2 | 10116 | f32 | -1 | 1 | 0 | CC 1 depth 2: 0.00 % | bipolar -1..1 |
| 290 | CC 1 depth 3 | CC1_Depth_3 | 10120 | f32 | -1 | 1 | 0 | CC 1 depth 3: 0.00 % | bipolar -1..1 |
| 291 | CC 1 depth 4 | CC1_Depth_4 | 10124 | f32 | -1 | 1 | 0 | CC 1 depth 4: 0.00 % | bipolar -1..1 |
| 292 | CC 1 target 1 | CC1_Target_1 | 10128 | i32 | 0 | 34 | 0 | CC 1 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 293 | CC 1 target 2 | CC1_Target_2 | 10132 | i32 | 0 | 34 | 0 | CC 1 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 294 | CC 1 target 3 | CC1_Target_3 | 10136 | i32 | 0 | 34 | 0 | CC 1 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 295 | CC 1 target 4 | CC1_Target_4 | 10140 | i32 | 0 | 34 | 0 | CC 1 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 296 | CC 2 | CC2 | 10144 | i32 | 0 | 127 | 0 | CC 2: --- | 128 (MIDI CC number (0 = none)) |
| 297 | CC 2 depth 1 | CC2_Depth_1 | 10148 | f32 | -1 | 1 | 0 | CC 2 depth 1: 0.00 % | bipolar -1..1 |
| 298 | CC 2 depth 2 | CC2_Depth_2 | 10152 | f32 | -1 | 1 | 0 | CC 2 depth 2: 0.00 % | bipolar -1..1 |
| 299 | CC 2 depth 3 | CC2_Depth_3 | 10156 | f32 | -1 | 1 | 0 | CC 2 depth 3: 0.00 % | bipolar -1..1 |
| 300 | CC 2 depth 4 | CC2_Depth_4 | 10160 | f32 | -1 | 1 | 0 | CC 2 depth 4: 0.00 % | bipolar -1..1 |
| 301 | CC 2 target 1 | CC2_Target_1 | 10164 | i32 | 0 | 34 | 0 | CC 2 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 302 | CC 2 target 2 | CC2_Target_2 | 10168 | i32 | 0 | 34 | 0 | CC 2 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 303 | CC 2 target 3 | CC2_Target_3 | 10172 | i32 | 0 | 34 | 0 | CC 2 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 304 | CC 2 target 4 | CC2_Target_4 | 10176 | i32 | 0 | 34 | 0 | CC 2 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 305 | CC 3 | CC3 | 10180 | i32 | 0 | 127 | 0 | CC 3: --- | 128 (MIDI CC number (0 = none)) |
| 306 | CC 3 depth 1 | CC3_Depth_1 | 10184 | f32 | -1 | 1 | 0 | CC 3 depth 1: 0.00 % | bipolar -1..1 |
| 307 | CC 3 depth 2 | CC3_Depth_2 | 10188 | f32 | -1 | 1 | 0 | CC 3 depth 2: 0.00 % | bipolar -1..1 |
| 308 | CC 3 depth 3 | CC3_Depth_3 | 10192 | f32 | -1 | 1 | 0 | CC 3 depth 3: 0.00 % | bipolar -1..1 |
| 309 | CC 3 depth 4 | CC3_Depth_4 | 10196 | f32 | -1 | 1 | 0 | CC 3 depth 4: 0.00 % | bipolar -1..1 |
| 310 | CC 3 target 1 | CC3_Target_1 | 10200 | i32 | 0 | 34 | 0 | CC 3 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 311 | CC 3 target 2 | CC3_Target_2 | 10204 | i32 | 0 | 34 | 0 | CC 3 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 312 | CC 3 target 3 | CC3_Target_3 | 10208 | i32 | 0 | 34 | 0 | CC 3 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 313 | CC 3 target 4 | CC3_Target_4 | 10212 | i32 | 0 | 34 | 0 | CC 3 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 314 | CC 4 | CC4 | 10216 | i32 | 0 | 127 | 0 | CC 4: --- | 128 (MIDI CC number (0 = none)) |
| 315 | CC 4 depth 1 | CC4_Depth_1 | 10220 | f32 | -1 | 1 | 0 | CC 4 depth 1: 0.00 % | bipolar -1..1 |
| 316 | CC 4 depth 2 | CC4_Depth_2 | 10224 | f32 | -1 | 1 | 0 | CC 4 depth 2: 0.00 % | bipolar -1..1 |
| 317 | CC 4 depth 3 | CC4_Depth_3 | 10228 | f32 | -1 | 1 | 0 | CC 4 depth 3: 0.00 % | bipolar -1..1 |
| 318 | CC 4 depth 4 | CC4_Depth_4 | 10232 | f32 | -1 | 1 | 0 | CC 4 depth 4: 0.00 % | bipolar -1..1 |
| 319 | CC 4 target 1 | CC4_Target_1 | 10236 | i32 | 0 | 34 | 0 | CC 4 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 320 | CC 4 target 2 | CC4_Target_2 | 10240 | i32 | 0 | 34 | 0 | CC 4 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 321 | CC 4 target 3 | CC4_Target_3 | 10244 | i32 | 0 | 34 | 0 | CC 4 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 322 | CC 4 target 4 | CC4_Target_4 | 10248 | i32 | 0 | 34 | 0 | CC 4 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 323 | CC 5 | CC5 | 10252 | i32 | 0 | 127 | 0 | CC 5: --- | 128 (MIDI CC number (0 = none)) |
| 324 | CC 5 depth 1 | CC5_Depth_1 | 10256 | f32 | -1 | 1 | 0 | CC 5 depth 1: 0.00 % | bipolar -1..1 |
| 325 | CC 5 depth 2 | CC5_Depth_2 | 10260 | f32 | -1 | 1 | 0 | CC 5 depth 2: 0.00 % | bipolar -1..1 |
| 326 | CC 5 depth 3 | CC5_Depth_3 | 10264 | f32 | -1 | 1 | 0 | CC 5 depth 3: 0.00 % | bipolar -1..1 |
| 327 | CC 5 depth 4 | CC5_Depth_4 | 10268 | f32 | -1 | 1 | 0 | CC 5 depth 4: 0.00 % | bipolar -1..1 |
| 328 | CC 5 target 1 | CC5_Target_1 | 10272 | i32 | 0 | 34 | 0 | CC 5 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 329 | CC 5 target 2 | CC5_Target_2 | 10276 | i32 | 0 | 34 | 0 | CC 5 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 330 | CC 5 target 3 | CC5_Target_3 | 10280 | i32 | 0 | 34 | 0 | CC 5 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 331 | CC 5 target 4 | CC5_Target_4 | 10284 | i32 | 0 | 34 | 0 | CC 5 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 332 | CC 6 | CC6 | 10288 | i32 | 0 | 127 | 0 | CC 6: --- | 128 (MIDI CC number (0 = none)) |
| 333 | CC 6 depth 1 | CC6_Depth_1 | 10292 | f32 | -1 | 1 | 0 | CC 6 depth 1: 0.00 % | bipolar -1..1 |
| 334 | CC 6 depth 2 | CC6_Depth_2 | 10296 | f32 | -1 | 1 | 0 | CC 6 depth 2: 0.00 % | bipolar -1..1 |
| 335 | CC 6 depth 3 | CC6_Depth_3 | 10300 | f32 | -1 | 1 | 0 | CC 6 depth 3: 0.00 % | bipolar -1..1 |
| 336 | CC 6 depth 4 | CC6_Depth_4 | 10304 | f32 | -1 | 1 | 0 | CC 6 depth 4: 0.00 % | bipolar -1..1 |
| 337 | CC 6 target 1 | CC6_Target_1 | 10308 | i32 | 0 | 34 | 0 | CC 6 target 1: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 338 | CC 6 target 2 | CC6_Target_2 | 10312 | i32 | 0 | 34 | 0 | CC 6 target 2: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 339 | CC 6 target 3 | CC6_Target_3 | 10316 | i32 | 0 | 34 | 0 | CC 6 target 3: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 340 | CC 6 target 4 | CC6_Target_4 | 10320 | i32 | 0 | 34 | 0 | CC 6 target 4: none | 35: none / cutoff 1 / cutoff 2 / resonance / filter env mod / pitch / pan / distortion / LFO 1 speed / LFO 2 speed / LFO 1 depth / LFO 2 depth / 1 pulsewidth / 1 PWM rate / 1 PWM depth / 2 pulsewidth / 2 PWM rate / 2 PWM depth / 1 amp / 2 amp / noise amp / 1 pitch / 2 pitch / noise pitch / filter mix / noise resonance / ME 1 depth / ME 2 depth / XY depth / amp envelope speed / filter envelope speed / mod envelope speed / pitch envelope speed / Unison detune / Unison spread |
| 341 | Osc mix | OscMix | 10324 | i32 | 0 | 2 | 0 | Osc mix: normal | 3: normal / hardsync / FM (1 -> 2, 1 silent) |
