# Oatmeal: modulation sources, pitch computation and modulation routing

Scope: the envelopes (amp, filter, filter-2, mod env 1/2 and the "phantom" global mod envelopes), the pitch envelope,
LFO 1/2 (per-voice and global), the XY pad / CC / mod-env routing with every target's exact scaling, note-to-frequency
and tuning, velocity and aftertouch, random pan/amp/freq, and freq->pan and freq->env-speed.
Code: voice manager `0x1000c2e0` (VM render), VM note-on `0x1000bc20`, note trigger `0x1000dd90`, voice note-on
`0x10063e20`, voice note-off `0x100645a0`, per-voice renderer `0x1005d560` (control part up to `0x10061000`),
envelope coefficients `0x100522a0`, amp envelope `0x100050c0` (per sample), block envelope `0x10005a00`, env trigger
`0x10005f80`, env release `0x10005e10`, LFO `0x10009470`, LFO phase reset `0x100093a0`, LFO tables `0x10009250`,
main-process pre-computation `0x10068040`, processEvents `0x10050480`.
Other specs cover how the resulting numbers are used inside the oscillators (voice_osc.md §7–8), the filter
(filter_dist.md §2) and the note/voice allocation (notes_arp.md). This file defines what feeds them.

Notation: `P[x]` = program-struct field at chunk offset x (float unless stated as int). `Oct` = P[9064] (Octave
param, 1.01..5), `lnOct` = P[9068] = ln(Oct) (recomputed every process call). `SR` = int sample rate
(`ftol(sampleRate+0.5)`). `n` = frames in the current sub-block (64 normally; see §0). `ftol` = truncation toward 0.
All maths is x87 (80-bit intermediate) with float storage unless stated. **[V]** = verified numerically against the
DLL with the harness (scripts in `OM/work_mod/`, see §12).

---------------------------------------------------------------------------------------------------------------------
## 0. Update rates and order of operations

* The host buffer is split into sub-blocks (64 frames; the last one of a host buffer can be longer, see the notes
  spec). Everything in this file is **block rate** (once per sub-block, using that sub-block's `n`) except the **amp
  envelope, which is per sample**. Per-sample smoothing/ramps happen in the consumers: pitch ratios are ramped inside
  the oscillators (voice_osc.md §4), pan gains and filter mix are linear ramps over the block (voice_osc.md §8),
  and the velocity gain is smoothed per sample (§9.2).
* Envelope coefficients (§2.1) and pitch-envelope constants (§3.1) are recomputed at the start of every host
  `process()` call from the program struct (so parameter changes take effect at the next host buffer).
* Per sub-block, the main process does: XY random walk -> smoothing of bend/pressure/X/Y/CCs (§8) -> `VM.render`
  (global part §7.1, then every voice §7.2) -> note object (arp / queued notes).
* Voice render order (per sub-block, `0x1005d560`):
  1. XY-depth factor for this voice (uses the voice's mod-env values of the **previous** block) -> X_v, Y_v (§6.3).
  2. Envelope speed factors (amp/filter/mod/pitch) from XY/CC (§6.6).
  3. Mod envelopes 1/2 advance (block env, speed = mod-env speed only; freq->env speed is **not** applied to them).
  4. Mod-env velocity scaling, "ME depth" factors from XY/CC.
  5. LFO speed/depth factors from mod envs and CCs; per-note LFOs advance; LFO pitch/pan/value contributions (§4).
  6. Amp envelope (per sample) for the block; if it has ended the voice dies (render returns false).
  7. Pitch envelope (§3).
  8. Per-voice target sums from mod envs, XY, CC (§6.4, §6.5).
  9. Unison ratios, pitch ratios, osc/noise setup, pan, filter, distortion, output (other specs).
  10. Store this block's M1/M2 values into the voice (+0x2a2c / +0x2a30) for step 1 of the next block.

---------------------------------------------------------------------------------------------------------------------
## 1. Pitch: note -> frequency

### 1.1 Note frequency (note trigger `0x1000dd90`, once per note-on)
```
r     = rand() * (1/16384.f) - 1                       // uniform [-1, 1)
semis = (key - 69) + transposeArg + r * P[8804] * 0.01 // P[8804] Random freq in cents; transposeArg = arp shift
f0    = P[9060] * Oct ^ (semis * (1/12.0))             // P[9060] Tune main (Hz); double precision
```
`f0` is passed (as double) to the voice note-on. It becomes the oscillator base frequency (with glide, notes spec) and
is the frequency used by freq->env speed at note-on (§9.4). The note tuning table and global transpose are **not**
in f0. [V: Tune 432/Octave 3 at keys 57/69/81, random-freq spread ±100 c]

### 1.2 Per-block pitch offset (semitones in "Oct" units), computed in the VM for each voice
```
semisArg = P[9080 + 4*(key % 12)] * 0.01         // Tune C .. Tune B, cents -> semitones (pitch class of the key)
         + P[9132] * 12                           // Global transpose, stored in octaves (-4..4, steps of 1/12)
         + globalPitch                            // = smoothed bend + XY/CC "pitch" targets, §6.2
```
Bend: `bendTarget = ((msb-64)*128 + lsb) * P[9128] * (1/8192)` (semitones, P[9128] Bend range). At the start of
each process call `if (|bendTarget| < 0.01) bendTarget = 0` and `if (|bendSmooth - bendTarget| < 0.001) bendSmooth =
bendTarget`. Per sub-block `bendSmooth += (bendTarget - bendSmooth) * k64`, `k64 = 1 - (10^(-2/(0.05*SR)))^64`.

### 1.3 Master pitch ratio (per voice, per block; voice_osc.md §7.4 calls it Rg)
```
Rg = Oct ^ ((lfo1Pitch * lfo1DepthF + lfo2Pitch * lfo2DepthF + semisArg) / 12) * penvRatio
```
`lfoNPitch` (semitones) and `lfoNDepthF` are from §4.7, `penvRatio` from §3 (1.0 when the pitch env is off).
Oscillator 1 uses `Rg * Oct^(pitch1/12) * afterpitch1` and oscillator 2 uses `Rg * afterpitch2` on top of its base
`f1base * Oct^(pitch2/12 + P[8516]) + P[8520]` (P[8516] Transpose in octaves, P[8520] Detune Hz; voice_osc.md §7.4).
`pitch1/pitch2/pitchN` are the per-voice target sums of §6.4/6.5. Afterpitch: `|P[8476]| > 0.01 ?
Oct^(at * P[8476] / 12) : 1` (osc 2: P[8480]); `at` is the voice's aftertouch value (§9.3).
The noise filter frequency is `f1base * Oct^((pitchN + P[8536])/12)`. It does **not** include Rg (no bend, LFO,
tuning table or pitch env).
[V: tuning table ±cents, global transpose with Octave 3, bend ±max with ranges 12 and 2 at Octave 2 and 3, osc2
transpose+detune at Octave 3, afterpitch: all within 1e-5 relative]

---------------------------------------------------------------------------------------------------------------------
## 2. Envelopes (amp, filter, filter 2, mod 1, mod 2, phantom mod 1/2)

### 2.1 Parameter block `E` (0x40 bytes) and derived coefficients (`0x100522a0(0xffff, SR)`, every process call)
Blocks: amp E=P[8232], filter E=P[8300], filter-2 E=P[8364], mod env 1 E=P[9312], mod env 2 E=P[9408].
| E+ | field | amp chunk offset (param) |
|---|---|---|
| 0x00 | kill time ms (always 4.0; not a parameter, stored in presets) | 8232 |
| 0x04 | attack ms | 8236 (p60) |
| 0x08 | hold ms | 8240 (p61) |
| 0x0c | decay 1 ms | 8244 (p62) |
| 0x10 | decay 2 ms | 8248 (p64) |
| 0x14 | release ms | 8252 (p66) |
| 0x18 | release/2 (written by setParameter, unused) | 8256 |
| 0x1c | killDec (derived) | 8260 |
| 0x20 | attInc (derived) | 8264 |
| 0x24 | holdSamples (derived, uint32) | 8268 |
| 0x28 | d1coef (derived) | 8272 |
| 0x2c | breakpoint (linear) | 8276 (p63) |
| 0x30 | d2coef (derived) | 8280 |
| 0x34 | sustain (linear) | 8284 (p65) |
| 0x38 | relCoef (derived) | 8288 |
| 0x3c | fastRelCoef (derived, never used) | 8292 |
Filter: attack 8304, hold 8308, d1 8312, d2 8316, rel 8320, bp 8344, sus 8352 (p45–51). Mod env 1: 9316, 9320,
9324, 9328, 9332, bp 9356, sus 9364 (p238–244). Mod env 2: 9412, 9416, 9420, 9424, 9428, bp 9452, sus 9460 (p254–260).
Filter-2 block (P[8364]) is rebuilt before the coefficients each process call: its kill/attack/hold/d1/d2/rel/rel2
= filter block × P[8452] (F envspeed ratio r; 5..0.2, see filter_dist.md), bp/sus copied from the filter block.
```
if (bp  > 0.998) bp  = 1.0     // stored back into E (so bp == 1 means "skip decay 1")
if (sus > 0.998) sus = 1.0
killDec  = 1000 / (SR * E.kill)                                // per-sample decrement, 4 ms full scale
attInc   = 1000 / (SR * E.attack)                              // attack is linear 0->1 in 'attack' ms
holdSamples = ftol(E.hold * SR * 0.001 + 0.5)
d1coef   = pow(max(bp, 1e-6),               1 / max(SR*E.d1*0.001f, 1))
d2coef   = pow(max(sus / max(bp,1e-6), 1e-6), 1 / max(SR*E.d2*0.001f, 1))
relCoef  = 10 ^ (-3 / max(SR*E.release*0.001f, 1))             // -60 dB in 'release' ms
fastRelCoef = 10 ^ (-3 / max(SR*E.release*0.0005f, 1))         // (stage 9 never entered)
```
Decays are exponential in the level `L`: decay 1 goes 1 -> bp in exactly `d1` ms, decay 2 goes bp -> sus in `d2`
ms (upward if sus > bp).

### 2.2 Envelope state (0x20 bytes) and stages
`+0` byte* sustain-pedal flag (plugin +0x1e5bf8), `+4` E*, `+8` stage, `+0xc` level L, `+0x10` smoothed output y
(amp only), `+0x14` release start value X (amp only), `+0x18` release scale k (amp only), `+0x1c` hold counter (int).
Stages: 0 off, 1 kill ramp (4 ms fade to 0, then attack), 2 attack, 3 hold, 4 decay 1, 5 decay 2 falling,
6 decay 2 rising, 7 sustain, 8 release, 9 fast release (dead code).
Voice objects: amp env +0x2970, mod env 1 +0x2990, mod env 2 +0x29b0; filter envs at +0xc of each of the four filter
objects (+0x1ca0/+0x20f0 filter 1, +0x1ec8/+0x2318 filter 2). Phantom (global) mod envs: VM +0x31c and +0x33c
(same E blocks as mod env 1/2).

### 2.3 Trigger (`0x10005f80(fade)`) and release (`0x10005e10(block)`)
```
trigger(fade):
  if (stage == 0) { y = 0; L = 0; }
  else if (stage == 4) L = cubic(L, bp, 1)            // convert level to the output value (see 2.4)
  else if (stage == 5 || stage == 6) L = cubic(L, sus, bp)
  if (stage not in {0,1,2}) L = (L < 1e-5) ? 0 : (L > 0.99999) ? 1 : 1 - sqrt(1 - L)  // inverse of attack shape
  holdCnt = 0;  stage = (fade && stage != 0) ? 1 : 2
release(block):                   // block = 1 for filter/mod/phantom envs, 0 for the amp env
  if (block && stage != 0) { stage = 8; return; }
  if (stage == 0 || stage >= 8) return;
  if (stage in {1,2}) L = (2 - L) * L;  else if (stage == 4) L = cubic(L, bp, 1);
  else if (stage in {5,6}) L = cubic(L, sus, bp);          // stages 3/7: L unchanged
  X = L;  if (X <= 0.001) { stage = 0; return; }           // voice ends at once
  k = X / (X - 0.001);  stage = 8
```
In `trigger` and `release` the cubic uses raw E.bp/E.sus (no 1e-4 clamp).
Who calls what: see §5 (note-on/off). The amp env is always triggered with fade=0 and so never uses stage 1.

### 2.4 Amp envelope, per sample (`0x100050c0(out[n], n, speed, SR)`) [V]
Per call:
```
if (speed < 0.01) speed = 0.01;   if (stage == 0) return false (voice dead)
c    = 1 - 10^(-1/(SR*0.0005))            // one-pole smoother, -20 dB per 0.5 ms (0.0992 at 44.1k)
att  = speed * E.attInc;  kill = speed * E.killDec
bp   = max(E.bp, 1e-4);   sus = max(E.sus, 1e-4)
d1   = E.d1coef ^ speed;  d2 = E.d2coef ^ speed
rel  = E.relCoef ^ (pedalDown ? speed * 0.0078125 : speed)    // sustain pedal: release 128x slower (dB/s) [V]
if (stage == 5) { if (bp < sus) stage = 6; else if (bp == sus) stage = 7; }
else if (stage == 6) { if (bp > sus) stage = 5; else if (bp == sus) stage = 7; }
if (stage == 5) { if (L > bp) L = bp; else if (L < sus) L = sus; }   // follow parameter changes
if (stage == 6) { if (L < bp) L = bp; else if (L > sus) L = sus; }
cubic(L, lo, hi) = (-2L^3 + 3(lo+hi)L^2 - 6*lo*hi*L + (lo+hi)*lo*hi) / max((hi-lo)^2, 1e-8)
                 = lo + (hi-lo)*smoothstep((L-lo)/(hi-lo))     // Hermite, zero slope at both ends
```
Sample loop (i = 0..n-1). **On every stage transition the same sample index is processed again in the new stage**
(the output written for i is overwritten, and the smoother and level advance one extra step):
```
stage 1: y += ((2-L)*L - y)*c; out[i]=y; L -= kill; if (L <= 0) { L = 0; stage = 2; redo i }
stage 2: y += ((2-L)*L - y)*c; out[i]=y; L += att;
         if (L >= 1) { L = 1; if (E.holdSamples > 0) { stage = 3; holdCnt = ftol(E.holdSamples * speed); }  // QUIRK *speed
                              else stage = (bp < 1) ? 4 : (sus < 1) ? 5 : 7;  redo i }
stage 3: y += (L - y)*c;  out[i]=y; if (--holdCnt < 0) { stage = (bp<1)?4:(sus<1)?5:7; redo i }
stage 4: y += (cubic(L,bp,1) - y)*c; out[i]=y; L *= d1;
         if (L <= bp) { L = bp; stage = (bp<sus)?6:(bp>sus)?5:7; redo i }
stage 5: y += (cubic(L,sus,bp) - y)*c; out[i]=y; L *= d2; if (L <= sus) { L = sus; stage = 7; redo i }
stage 6: same with "if (L >= sus)"
stage 7: y += (L - y)*c;  out[i]=y; L = sus;  if (y < 0.001) { L = 0; stage = 0; return true }   // rest of out = 0
stage 8: if (L > 0.001) { y += ((L - 0.001)*k - y)*c; L *= rel; } else { L = 0; y += (0 - y)*c; }
         out[i] = y; if (y < 1e-6) { L = 0; stage = 0; return true }                               // rest of out = 0
```
(`out` is zero-filled by the caller.) Shape summary: the attack output is `1-(1-t)^2` (t = elapsed/attack, parabolic,
fast start), decays are exponential in L but mapped through a smoothstep between the segment end points, and the
release is exponential towards -60 dB re-scaled so it reaches exactly 0 when L hits 0.001. Everything then passes
the 0.5 ms one-pole. The voice ends when the sustain level (smoothed) is below 0.001 or the release output is below
1e-6. Hold quirk: the per-sample amp env holds for `holdSamples*speed` samples, so a faster env (speed > 1) holds
**longer** [V]. The block envelopes hold for `holdSamples/speed`.
Speed for the amp env: `ampEnvSpeed(§6.6) * voice.envSpeed(+0x2a24, §9.4)`.

### 2.5 Block envelope (`0x10005a00(&out, n, speed)`), used by filter, filter-2, mod env 1/2 and phantom envs [V]
One update per block; the value used for the block is the level **after** advancing n samples:
```
if (speed < 0.01) speed = 0.01;  out = 0;  if (stage == 0) return false
bp = max(E.bp, 1e-6); sus = E.sus;  rel = pedalDown ? E.relCoef^(1/128) : E.relCoef;  s = n*speed (float)
(stage 5/6 direction switch and level clamp exactly as in 2.4)
if (stage==1) { L -= s*E.killDec; if (L <= 0) { L = 0; stage = 2; } }
if (stage==2) { L += s*E.attInc; if (L >= 1) { L = 1; if (E.holdSamples>0) { stage=3; holdCnt=E.holdSamples; }
                                                  else stage = (bp<1)?4:(sus<1)?5:7; } }
if (stage==3) { holdCnt -= max(ftol(n*speed), 1); if (holdCnt < 0) stage = (bp<1)?4:(sus<1)?5:7; }
if (stage==4) { L *= E.d1coef^s; if (L <= bp) stage = (bp<sus)?6:(bp>sus)?5:7; }      // L NOT clamped to bp here
if (stage==5) { L *= E.d2coef^s; if (L <= sus) { stage = 7; L = sus; } }
if (stage==6) { L *= E.d2coef^s; if (L >= sus) { stage = 7; L = sus; } }
if (stage==7) { L = sus; if (sus < 0.001) { L = 0; stage = 0; } }
if (stage==8) { L *= rel^s; if (L < 0.001) { L = 0; stage = 0; } }
out = L; return true
```
No output shaping and no smoothing: mod/filter envs are the raw level L (linear attack, exponential decays and
release, cut at 0.001). The stages cascade within one call (a block can finish the attack and start hold/decay).
Filter env speed = `filterEnvSpeed(§6.6) * voice.envSpeed`; the filter env is only advanced when the filter runs
(filter_dist.md). Mod env speed = `modEnvSpeed(§6.6)` only. Phantom env speed = global mod-env speed (§7.1).
Velocity scaling (applied to the block output, not stored): mod env 1 with P[9504] (p245), mod env 2 with P[9508]
(p261), filter env with P[9512] (p58):
```
velScale(vs) = vs > 0.001 ? pow(vel, 2*vs) : vs < -0.001 ? 1 + vel*vs : 1      // vel = voice +0x2a08 (§9.1)
```
The phantom envs get no velocity scaling.

---------------------------------------------------------------------------------------------------------------------
## 3. Pitch envelope (p164–171) [V]

### 3.1 Constants (every process call, `0x100682f1`)
```
S   = P[8988] <= -48 ? 0 : 2^(P[8988]/12)   -> P[8992]   // start ratio: QUIRK uses 2, not Oct; -48 st = ratio 0
Pk  = Oct^(P[9004]/12)                      -> P[9008]   // peak
Su  = Oct^(P[9020]/12)                      -> P[9024]   // sustain
att = (Pk - S) / (SR * P[8996] * 0.001f)    -> P[9000]   // per-sample linear step of the RATIO
dec = (Su / Pk) ^ (1 / (SR * P[9012] * 0.001f)) -> P[9016]
rel = Oct ^ (P[9028] / (12*SR))             -> P[9032]   // P[9028] release in st/sec (Oct units)
```
### 3.2 Per block (voice +0x2a34 = ratio R, +0x2a38 = stage), only if P[8984] (P env on) != 0
`x = n * pitchEnvSpeed(§6.6) * voice.envSpeed`.
```
stage 0: R = 0
stage 1: (retrigger glide) step = x / (SR*0.002):  R moves linearly toward S by 'step' (1 ratio unit per 2 ms);
         when it reaches S: R = S, stage = 2
stage 2 (attack), rising (Pk > S):
         R += (R >= S) ? x*att : (S - R + 1) * att * x / (Pk - S);
         if (R >= Pk) { R = Pk; stage = (Su <= Pk) ? 5 : 6 }
stage 2, falling (Pk <= S):
         R += (R <= S) ? x*att : (R - S + 1) * x * att / (S - Pk + 0.001);
         R += x*att;                                   // QUIRK: applied twice -> falling attack is 2x faster [V]
         if (R <= Pk) { R = Pk; stage = (Su <= Pk) ? 5 : 6 }
stage 5: R *= dec^x; if (R <= Su) { R = Su; stage = 7 }
stage 6: R *= dec^x; if (R >= Su) { R = Su; stage = 7 }
stage 7: R = Su
stage 8: R *= rel^x; if (R < 1e-4) { R = 0; stage = 0 } else if (R > 2^20) R = 2^20
(stages 3, 4: nothing)
```
Velocity (P[9516], p171), applied to the ratio each block (not stored):
`penvRatio = vs > 0.001 ? R^(1 + (vel-1)*vs) : vs < -0.001 ? R^(1 + vel*vs) : R` (depth scaling in the log domain).
If the pitch env is off, `penvRatio = 1` (the stage machine is not run).
Note-on: fresh voice -> R = S, stage 2. Retrigger of a sounding voice (poly/mono modes) -> stage 1 (glide from the
current R to S, then attack). Legato mode with a sounding voice -> stage kept if 2..7, else set to 2. Note-off ->
stage 8. Attack is linear in frequency ratio, decay exponential, release a constant rate in st/sec.

---------------------------------------------------------------------------------------------------------------------
## 4. LFO 1 / LFO 2

### 4.1 Parameters
| | LFO 1 | LFO 2 | notes |
|---|---|---|---|
| unit (int 0..17) | 8544 p19 | 8580 p30 | |
| shape (int 0..6) | 8548 p20 | 8584 p31 | sine, saw, square, triangle, smooth random, stepping random, user |
| mode (int) | 8552 p23 | 8588 p34 | 0 per note, 1 global reset on note, 2 global free |
| speed | 8556 p21 | 8592 p32 | v<=1/3: 1/(4-9v); else 382.5v-126.5 (0.25 .. 256 "units") |
| quantize (int) | 9520 p22 | 9524 p33 | |
| cut 1 / cut 2 | 8560 / 8564 | 8596 / 8600 | -1..1, x4 octaves (used in the filter, see 4.8) |
| res | 8568 | 8604 | 0..1 |
| pitch | 8572 | 8608 | 0..1; depth = 24*p^4 semitones |
| pan | 9224 p28 | 9228 p39 | 0..1 |
| rate mod by other LFO | 8612 p40 (LFO2->LFO1) | 8576 p29 (LFO1->LFO2) | 0..1 |
| user shape | float[512] @4136 | float[512] @6184 | |
Global: LFO phase P[8832] (p121), phase rand P[8836] (p122), retrigger P[8840] (p123, int).

### 4.2 LFO object (0x18 bytes): `+0` prog*, `+4` shared* (int SR at +4, double samplesPerBeat at +8), `+8` byte
isLFO2, `+0xc` uint32 phase, `+0x10` prev random, `+0x14` current random. Per-voice: +0x29d0 (LFO1), +0x29e8 (LFO2).
Global: VM +0x35c, +0x374.

### 4.3 Step `v = lfo.step(nAdv, X, Y)` (`0x10009470`), once per block, returns a value in 0..1 [V]
```
s = sum over the 4 X/Y slots of target 8 ("LFO 1 speed"): X*Xdepth + Y*Ydepth
if (isLFO2) s += same sum for target 9 ("LFO 2 speed")        // QUIRK: LFO2 also follows target 8 [V]
if (|s| > 0.01) nAdv = ftol(2^(2s) * nAdv + 0.5)
speed = (double) P[speed];  if (quantize) speed = (3*speed >= 2) ? floor(speed+0.5) : 1/floor(1/speed+0.5)
period (samples) = unit 0: SR*speed*0.001 | 1: SR*speed*0.01 | 2: SR*speed |
                   3..17: speed * samplesPerBeat * {0.2, 1/6, 0.25, 0.4, 1/3, 0.5, 0.8, 2/3, 1, 1.6, 4/3, 2, 3.2, 8/3, 4}[unit-3]
                   (units 3..17 = 4/5 16th, 2/3 16th, 16th, 4/5 8th, 2/3 8th, 8th, 4/5 quarter, 2/3 quarter, quarter,
                    4/5 half, 2/3 half, half, 4/5 whole, 2/3 whole, whole; samplesPerBeat = 60/tempo*SR, host tempo)
inc   = ftol(2^32 / period + 0.5)                                  // uint32
old = phase;  phase += inc * nAdv  (mod 2^32, nAdv may be 0 or negative)
shape 4 (smooth random): if (old > phase unsigned) { prev = cur; cur = rand()/32768 }
                         return prev + (cur - prev) * phase * 2^-32
shape 5 (stepping):      same update; return cur
shape 6 (user):          i = phase>>23; f = (phase & 0x7fffff)*2^-23; return t[i] + (t[(i+1)&511] - t[i])*f
shape 0..3:              i = phase>>17; f = (phase & 0x1ffff)*2^-17;  return T[i] + (T[i+1] - T[i])*f
tables (32769 floats, T[32768] = T[0]):   sine T[i] = (sin(pi*i/16384) + 1)/2      (starts at 0.5, rising)
    saw T[i] = i/32768     square T[i] = (i < 16384) ? 0 : 1     triangle T[i] = i<16384 ? i/16384 : 1-(i-16384)/16384
```
Note the table guard: in the last 1/32768 of the cycle the saw and square interpolate from T[32767] down to T[0]
(the DLL really outputs e.g. 0.063 there, [V]). Random values are MSVCRT `rand()` (LCG `s = s*214013 + 2531011;
return (s>>16) & 0x7fff`, per-thread seed 1, never seeded; shared with every other rand() user, so the sequence is
not reproducible in practice).

### 4.4 Phase reset (`0x100093a0`)
`phase = ftol(((rand()/16384.f - 1) * P[8836] * 0.5 + P[8832]) * 2^32 + 0.5)` (mod 2^32, i.e. uniform in
phase ± rand/2 cycles), then `prev = rand()/32768; cur = rand()/32768`.
* Per-voice LFOs: reset at every note-on of a fresh voice; on a retrigger of a sounding voice only if P[8840] != 0.
* Global LFOs: reset by the VM on every note-on (including legato) if their mode is 0 or 1. Mode 2 never resets.
* The first block after a reset reads the value at phase + inc*nAdv (the step happens before the read) [V].

### 4.5 Advance amounts (cross modulation and speed modulation), per block
Per voice, when LFO1 mode == 0:
```
n1 = ftol((P[8612] * lfo2Prev * lfo2DepthF * 3 + lfo1SpeedF) * n + 0.5);   v1 = LFO1.step(n1, X_v, Y_v)
```
LFO 2 per voice (mode 0), after LFO 1:
```
n2 = ftol((P[8576] * v1 * lfo1DepthF * 3 + lfo2SpeedF) * n + 0.5);          v2 = LFO2.step(n2, X_v, Y_v)
```
`v1` is the voice LFO1 value just computed (or, if LFO1 is global, the global LFO1 value passed in, after its XY-depth
scaling). `lfo2Prev` (voice +0x2a00, reset to 0 only by the voice reset) is the voice's LFO2 value of the previous
block after its XY-depth scaling (4.6), before `lfo2DepthF`. `lfoNSpeedF` and `lfoNDepthF` are from 4.7.
Cross modulation only speeds the target up (0..1 values): at 100 % the rate goes from 1x to 4x [V].
Global LFOs (VM, every block, also when their mode is 0):
```
g1 = ftol((P[8612] * gLfo2Prev * 3 + gSpeed1) * n + 0.5);   gv1 = gLFO1.step(g1, X', Y')
g2 = ftol((P[8576] * gv1 * 3 + gSpeed2) * n + 0.5);         gv2 = gLFO2.step(g2, X', Y');   gLfo2Prev = gv2
```
(gSpeedN from phantom envs and CCs, §7.1; X', Y' = VM-scaled XY. When no voice is playing the VM only does
`gLFOn.step(n, X, Y)` with the raw smoothed XY and n.)
So "a global LFO modulated by a per-note LFO" uses the global (phantom) instance of the other LFO, as the manual says.

### 4.6 Values, pitch and pan contributions
Per-voice LFO (mode 0). D1/D2 are the XY sums of targets 10/11 over the 4 X and 4 Y slots, using X_v/Y_v (CCs are
not included here):
```
pd1 = 24*P[8572]^4;  pd2 = 24*P[8608]^4                       // LFO pitch depth in semitones [V]
if both LFOs are per-note: kPitch = 2  else kPitch = 4       // QUIRK [V]
if (|D1| > 0.005) { pd1 *= Oct^(kPitch*D1); g1 = 2^(4*D1) } else g1 = 1
lfo1Pitch = (2*v1 - 1) * pd1
lfo1Pan   = (2*v1 - 1) * P[9224] * g1
v1 *= g1                                                      // value passed on (filter), and used for cross mod
(same for LFO 2 with D2, pd2, P[9228])
```
(In the one-per-note case the kPitch=4 path skips the pitch part when P[8572] <= 0, which is equivalent.)
Global LFO (mode 1/2), computed in the VM with X', Y' **and CCs** (targets 10/11 summed over X, Y and CC slots:
`X'*d + Y'*d + cc*d`):
```
if (|D1| > 0.005) { pd1 *= Oct^(4*D1); g1 = 2^(4*D1) } else g1 = 1
gLfo1Pitch = (2*gv1-1)*pd1;  gLfo1Pan = (2*gv1-1)*P[9224]*g1;  gv1 *= g1
```
If LFO N is per-note, the VM passes 0 for its pitch and pan contributions and the voice adds its own.
### 4.7 Depth and speed factors inside the voice
```
lfo1DepthF = |S1d| > 0.001 ? 2^(3*S1d) : 1     S1d = sum(ME1*d for ME1 target 20) + sum(ME2*d, target 20)
                                                    + sum(cc*d for CC target 10)
lfo2DepthF: same with ME target 21, CC target 11
lfo1SpeedF = |S1s| > 0.001 ? 2^(2*S1s) : 1     S1s = ME target 18 + CC target 8 sums
lfo2SpeedF: ME target 19, CC target 9
```
(ME = mod-env value after velocity and ME-depth scaling, §6.) These factors multiply the LFO pitch
(`lfoNPitch*lfoNDepthF` in Rg, §1.3), the LFO pan (§9.5) and the LFO value passed to the filter, for per-note **and**
global LFOs. With a global LFO a CC "LFO depth" target therefore acts twice: `2^(4*cc*d)` in the VM times
`2^(3*cc*d)` in the voice = `2^(7*cc*d)` (QUIRK, [V]). Mod-env "LFO depth" never uses the phantom env (always the
voice's mod env). Mod-env "LFO speed" of a **global** LFO uses the phantom env (§7.1); per-voice speed factors only
affect per-note LFOs.
### 4.8 What the filter receives
The filter gets `v1*lfo1DepthF` and `v2*lfo2DepthF` as **unipolar 0..1** values: cutoff octaves +=
`4*(v1*cut1 + v2*cut2)` and resonance += `(v1*res1 + v2*res2)*(1-R)` (filter_dist.md §2). A positive "cut" depth only
raises the cutoff (by up to 4*cut octaves); with LFO value 0 there is no change at all [V].

---------------------------------------------------------------------------------------------------------------------
## 5. Note-on / note-off (modulation-relevant parts)

### 5.1 processEvents (`0x10050480`)
* Note on (vel > 0): `pressure = AT(vel)` and `perKeyAT[key] = AT(vel)` (so note-on velocity sets both the channel
  pressure and the key's aftertouch), then the note object gets (key, vel).
* Poly AT: `perKeyAT[key] = AT(value)`. Channel pressure: `pressure = AT(value)`.
* CC (1..127; CC 0 ignored): `rawCC[cc] = value/127`; CC 64 sets the pedal byte (`value >= 64`) if P[9592]
  (Sustain pedal) != 0, else 0. If cc == P[9176] (X CC): `setParameter(196, value/127)` (X = 2v-1); same for Y
  (P[9212] -> param 197).
* AT(x) and VEL(x): 64-point curves with linear interpolation (touch curve P[9852], velocity curve P[9596]):
  `t = (x/127) * 64; i = ftol(t); f = t - i; i0 = min(i,63); i1 = min(i+1,63); c[i0]*(1-f) + c[i1]*f`
  (default curves are i/63).
### 5.2 Note trigger (`0x1000dd90`): velocity = VEL(vel); frequency per §1.1. Note-off: all voices with that key get
  `voice.noteOff()`; if afterwards no voice is held, both phantom envs are released (`release(1)`).
### 5.3 VM note-on (`0x1000bc20`)
* If a voice of the same key is still held: it is retriggered, and its **velocity becomes `VEL(vel) + ampEnv.L`**
  (the raw amp-env level of that voice; QUIRK [V]).
* Phantom envs: `trigger(1)` on both, unless voice mode (P[8760]) == 2 and some voice is still held.
* Global LFOs with mode < 2: phase reset (4.4).
* Voice allocation/stealing: notes spec. A stolen voice whose amp level L < 1e-4 is fully reset (voice reset
  `0x1005d3a0`: M values, LFO2 prev, pitch env R/stage cleared, new unison jitter randoms) and treated as fresh;
  a still-sounding stolen voice is "active" and takes the retrigger path.
### 5.4 Voice note-on (`0x10063e20`)
```
+0x2a04 = -1 (held); vel(+0x2a08) = velocity
randAmp(+0x2a0c) = 10^((rand()/16384 - 1) * P[8800] * 0.05)          // Random amp: uniform ±P[8800] dB
if (!active) {                                                        // fresh voice
   M1last = M2last = 0
   velGain(+0x2a10) = velGainSmooth(+0x2a14) = randAmp * velScaleAmp  // §9.2
   basePan(+0x2a18) = (rand()/32768 - 0.5) * P[8796] + 0.5           // Random pan
   p = clamp(basePan + (|P[8788]| > 0.001 ? P[8788]*(ln(f0/P[9060])/lnOct - P[9076]/12) : 0), 0, 1)
   panL/panR(+0x2a1c/+0x2a20) = gain(p)                               // §9.5, set directly (no ramp)
   osc/PWM phase init; LFO phase reset (both)
} else { osc/PWM phase re-init if P[8816]/P[8828]; LFO phase reset if P[8840] }
envSpeed(+0x2a24) = Oct^(2*P[8792] * (ln(f0/P[9060])/lnOct - P[9076]/12))       // §9.4
if (voice mode < 2) {
   if (active) penv.stage = 1  else { filterMix(+0x2a28) = P[8456]; R = S; penv.stage = 2 }
   ampEnv.trigger(0); filterEnv x4 .trigger(1); modEnv1.trigger(1); modEnv2.trigger(1)
} else {                                                              // legato
   if (!active) { same as the fresh branch above }
   else { if (penv.stage > 7 || penv.stage < 2) penv.stage = 2;
          for each env: if (stage in {0, 8, 9}) trigger(amp ? 0 : 1) }   // only released envs restart
}
glide / oscillator frequency setup: notes and osc specs.   active = 1; key(+0xc) = key
```
Consequences: a retriggered sounding voice continues its amp envelope from the current output level (attack from
`L' = 1-sqrt(1-out)`) [V], while its filter and mod envelopes fade to 0 in 4 ms and restart from 0.
### 5.5 Voice note-off (`0x100645a0`): `+0x2a04 = 0` (then counts samples since release, used by stealing);
`ampEnv.release(0)`, the four filter envs and both mod envs `release(1)`, `penv.stage = 8`.

---------------------------------------------------------------------------------------------------------------------
## 6. Modulation routing

### 6.1 Sources and target lists
Sources: mod env 1 and 2 (4 slots each: depth P[9376+4k]/P[9472+4k], target int P[9392+4k]/P[9488+4k]; depth -1..1),
X and Y (4 slots each: depth P[9144+4k]/P[9180+4k], target P[9160+4k]/P[9196+4k]; X,Y = P[9136]/P[9140] -1..1),
CC 1..6 (CC number int P[10108+36c], depth P[10112+36c+4k], target P[10128+36c+4k]; value = smoothed CC 0..1).
Mod-env target list (p250 etc.): 0 none, 1 cutoff 1, 2 cutoff 2, 3 resonance, 4 1 amp, 5 2 amp, 6 noise amp, 7 1 pitch,
8 2 pitch, 9 noise pitch, 10 1 pulsewidth, 11 1 PWM rate, 12 1 PWM depth, 13 2 pulsewidth, 14 2 PWM rate,
15 2 PWM depth, 16 pan, 17 noise resonance, 18 LFO 1 speed, 19 LFO 2 speed, 20 LFO 1 depth, 21 LFO 2 depth,
22 filter mix, 23 cutoff 1 (unipolar), 24 cutoff 2 (unipolar), 25 1 pitch (unipolar), 26 2 pitch (unipolar),
27 noise pitch (unipolar), 28 XY depth, 29 Unison detune, 30 Unison spread.
X/Y target list (p202 etc.): 0 none, 1 cutoff 1, 2 cutoff 2, 3 resonance, 4 filter env mod, 5 pitch, 6 pan,
7 distortion, 8 LFO 1 speed, 9 LFO 2 speed, 10 LFO 1 depth, 11 LFO 2 depth, 12 1 pulsewidth, 13 1 PWM rate,
14 1 PWM depth, 15 2 pulsewidth, 16 2 PWM rate, 17 2 PWM depth, 18 1 amp, 19 2 amp, 20 noise amp, 21 1 pitch,
22 2 pitch, 23 noise pitch, 24 filter mix, 25 noise resonance, 26 ME 1 depth, 27 ME 2 depth, 28 amp envelope speed,
29 filter envelope speed, 30 mod envelope speed, 31 pitch envelope speed, 32 Unison detune, 33 Unison spread.
CC target list (p292 etc.): same as X/Y for 0..27, then 28 XY depth, 29 amp env speed, 30 filter env speed,
31 mod env speed, 32 pitch env speed, 33 Unison detune, 34 Unison spread.

Value conventions: `me` = mod-env value of this voice for this block (after velocity scaling and ME-depth factor),
`sus` = that env's sustain parameter (P[9364] / P[9460]); `x` = X_v or Y_v (per voice) or X'/Y' (VM, global), range
±2 after scaling; `cc` = smoothed CC 0..1 (**unipolar** except where `(2cc-1)` is written).
"dB-type" factor used for amp and XY-depth targets:
```
dbF(v, d) = d > 0 ? a + (1-a)*v     with a = 10^(-3d)        // v = 0 -> -60 dB*d, v = 1 -> 0 dB
            d <= 0 ? a + (1-a)*(1-v) with a = 10^(3d)         // inverted
```

### 6.2 Global targets (summed once per block in the VM, same for all voices)
| target | formula (added to) |
|---|---|
| XY 5 / CC 5 pitch | globalPitch += `x*d*24` / `(2cc-1)*d*24` semitones (bipolar CC) [V] |
| XY 6 / CC 6 pan | globalPan += `x*d` / `(2cc-1)*d` (pan units, 0.5 = centre) [V] |
| XY 12/15, CC 12/15 pulsewidth 1/2 | pw offset += `ftol(sum * 2^32 + 0.5)` (sum of `x*d` / `cc*d`), u32 |
| XY 13/16, CC 13/16 PWM rate | += `x*d` / `cc*d` (voice_osc.md 7.5) |
| XY 14/17, CC 14/17 PWM depth | += `x*d` / `cc*d` |
| XY 8/9, CC 8/9 LFO speed | global LFOs: XY inside `step` (4.3); CC in gSpeedN (7.1); per-voice LFOs: XY in `step`, CC in lfoNSpeedF |
| XY 10/11, CC 10/11 LFO depth | global LFOs: D sums (4.6); per voice: XY in D (4.6), CC in lfoNDepthF (4.7) |
| XY 30 / CC 31 mod env speed | phantom envs only (7.1); per voice see 6.6 |
| XY 26/27, CC 26/27 ME depth | phantom env value *= `(1 + x*d)` / `(1 + cc*d)`; per voice the same factors (6.3) |
| CC 28 / ME 28 XY depth | 6.3 |
### 6.3 XY scaling ("XY depth") and ME depth
VM (global): `f = prod over ME1/ME2 slots with target 28 of dbF(phantomVal_prev, d) * prod over CC slots with target
28 of dbF(cc, d)`; `X' = clamp(f*X, -2, 2)`, `Y' = clamp(f*Y, -2, 2)`. `phantomVal_prev` = phantom env value of
the previous block (VM +0x598/+0x59c, after its ME-depth factor).
Voice: the same product using the voice's own M1/M2 values of the previous block (voice +0x2a2c/+0x2a30, 0 at a
fresh note) -> `X_v, Y_v` (clamped ±2). X, Y here are the smoothed values plus the random walk (§8). [V (CC path,
env path)]
ME depth: `me1 *= prod(1 + x*d)` over XY slots with target 26 and `prod(1 + cc*d)` over CC slots with target 26 (target
27 for ME 2), per voice with X_v/Y_v and in the VM with X'/Y' for the phantom env [V].
### 6.4 Per-voice targets from the mod envelopes (every block, 4 slots of ME1 then ME2 per slot index)
| ME target | formula |
|---|---|
| 1 / 2 cutoff 1/2 | cutSemis1/2 += `(me - sus)*d*48` (semitones in Oct units; bipolar around the sustain level) |
| 23 / 24 cutoff unipolar | cutSemis1/2 += `me*d*24` |
| 7 / 8 / 9 pitch 1/2/noise | pitch1/2/N += `(me - sus)*d*48` [V] |
| 25 / 26 / 27 pitch unipolar | pitch1/2/N += `me*d*24` [V] |
| 4 / 5 / 6 amp 1/2/noise | amp1/amp2/ampN *= `dbF(me, d)` [V] |
| 16 pan | pan offset += `(me - sus)*d*2` [V] |
| 3 resonance | resMod += `me*d` (filter: `res += resMod>0 ? (1-R)*resMod : R*resMod`) |
| 17 noise resonance | noiseResMod += `me*d` |
| 22 filter mix | mixMod += `me*d` (below) |
| 10 / 13 pulsewidth 1/2 | pw += `ftol(me*d*2^32 + 0.5)` (u32) |
| 11 / 14 PWM rate 1/2 | += `me*d` |
| 12 / 15 PWM depth 1/2 | += `me*d` |
| 18 / 19 LFO speed, 20 / 21 LFO depth | 4.7 (per voice; plus phantom env for global LFO speed) |
| 28 XY depth | 6.3 |
| 29 unison detune | D += `|d|*d*me*1200` cents |
| 30 unison spread | spread += `me*d` |
Display note: the GUI shows "2.000 octaves" for cutoff at depth 100 %, but the bipolar formula gives ±4 octaves times
(me - sus).
### 6.5 Per-voice targets from X/Y (x = X_v or Y_v) and CCs (cc unipolar)
| X/Y target (CC same number) | formula |
|---|---|
| 21 / 22 / 23 pitch 1/2/noise | += `x*d*24` / `cc*d*24` semitones [V] |
| 18 / 19 / 20 amp 1/2/noise | XY: `*= 10^(3*x*d)` (±60 dB at |x*d| = 1) [V]; CC: `*= dbF(cc, d)` |
| 24 filter mix | mixMod += `x*d` / `cc*d` |
| 25 noise resonance | noiseResMod += `x*d` / `cc*d` |
| 32 (CC 33) unison detune | D += `|d|*d*x*1200` / `|d|*d*cc*1200` cents |
| 33 (CC 34) unison spread | spread += `x*d` / `cc*d` |
| 1 / 2 cutoff, 3 resonance, 4 filter env mod | inside the filter from X_v, Y_v and CCs: cutoff octaves += `4*(x*d)` / `4*cc*d`; envmod += `x*d` / `cc*d`, clamped to ±1; resonance: sum, then `res += s>0 ? (1-R)*s : R*s` (filter_dist.md §2) |
| 7 distortion | per-voice distortion (and global with X/Y): `Ddb = 30*(sum x*d + sum cc*d)` lowers the limit by Ddb dB and compensates the gain (filter_dist.md) |
| 28..31 (CC 29..32) env speeds | 6.6 |
Filter mix: `mm = clamp(mixMod, -1, 1)`; `target = mm > 0 ? P[8456] + (1-P[8456])*mm : P[8456]*(1+mm)`, ramped from
voice +0x2a28 over the block (filter_dist.md).
### 6.6 Envelope speed factors (per voice)
```
Sa = sum X/Y target 28 (x*d) + CC target 29 (cc*d);  ampEnvSpeed    = Sa != 0 ? 2^(2*Sa) : 1    (4^S)
Sf = X/Y 29 + CC 30;                                filterEnvSpeed = Sf != 0 ? 2^(2*Sf) : 1
Sm = X/Y 30 + CC 31;                                modEnvSpeed    = Sm != 0 ? 2^(2*Sm) : 1
Sp = X/Y 31 + CC 32;                                pitchEnvSpeed  = Sp != 0 ? 2^(2*Sp) : 1
```
amp/filter/pitch env speeds are multiplied by `voice.envSpeed` (freq->env speed); mod env speed is not. [V amp, mod]

---------------------------------------------------------------------------------------------------------------------
## 7. Voice-manager render (`0x1000c2e0`, per sub-block)

### 7.1 Global part
```
if (no voices) { gLFO1.step(n, X, Y); gLFO2.step(n, X, Y); return }     // phantom envs are NOT advanced
f = XY depth (6.3) with the phantom env values of the previous block;  X' = clamp(f*X), Y' = clamp(f*Y)
Sm = sum X/Y target 30 (x'*d) + CC target 31 (cc*d);  phSpeed = Sm != 0 ? 2^(2*Sm) : 1
me1Fac = prod(1 + x'*d) [XY 26] * prod(1 + cc*d) [CC 26];  me2Fac: targets 27
ph1 = phantom1.run(n, phSpeed) * me1Fac;  ph2 = phantom2.run(n, phSpeed) * me2Fac;  store for next block
A = sum ME1 slots target 18 (ph1*d) + ME2 target 18 (ph2*d) + CC target 8 (cc*d);  gSpeed1 = |A|>0.001 ? 2^(2A) : 1
B = same with ME 19, CC 9;                                                         gSpeed2
global LFOs step (4.5), then (if the LFO mode > 0) pitch/pan/value contributions (4.6), else 0
globalPitch = bendSmooth + sum XY 5 (x'*d*24) + sum CC 5 ((2cc-1)*d*24)
globalPan   = sum XY 6 (x'*d) + sum CC 6 ((2cc-1)*d)
pwMods[6]   = {pw1 (u32, ftol(sum*2^32+0.5)), rate1, depth1, pw2, rate2, depth2} from XY/CC 12..17
for each voice in list order (count up to P[8764] max polyphony; the rest are deleted):
   at = mode P[8784]: 0 -> 1.0, 1 -> smoothed channel pressure, 2 -> perKeyAT[key] (not smoothed)
   voice.render(buf, cc[6], gv1, gv2, gLfo1Pitch, gLfo2Pitch,
                P[9080+4*(key%12)]*0.01 + P[9132]*12 + globalPitch,
                gLfo1Pan, gLfo2Pan, globalPan, pwMods, at, X, Y, n)        // raw X, Y (voice scales itself)
```
Phantom envs: triggered with `trigger(1)` by the VM note-on (5.3), released with `release(1)` when the last held key is
released (5.2). They are used only for global targets: XY depth (ME target 28 in the VM path) and the speed of global
LFOs (ME targets 18/19). [V: ME1 -> LFO1 speed with a global LFO]

---------------------------------------------------------------------------------------------------------------------
## 8. Controllers: smoothing and XY random walk (main process, per sub-block)
```
k64 = 1 - (10^(-2/(0.05*SR)))^64            // per sub-block (always the 64-sample value, even for longer tails)
at process start: bend snap (|b|<0.01 -> 0); for bend, pressure, X, Y: if |smooth - target| < 0.001: smooth = target
per sub-block: bend/pressure/X/Y smooth += (target - smooth)*k64
               ccSmooth[c] += (rawCC[P[10108+36c]] - ccSmooth[c])*k64 if the CC number > 0, else ccSmooth[c] = 0
XY random walk (4 control points px[0..3], py[0..3], position t; rateStep = P[9220]/SR):
   if (t >= 1) { t -= 1; r = sqrt(rand()/32768) * P[9216]; a = rand() * pi/16384;
                 shift px, py left; px[3] = r*cos(a); py[3] = r*sin(a) }
   wx = catmull(px, t), wy = catmull(py, t); t += 64*rateStep
   catmull(p, t) = ((( -0.5p0 + 1.5p1 - 1.5p2 + 0.5p3)*t + (p0 - 2.5p1 + 2p2 - 0.5p3))*t + 0.5(p2 - p0))*t + p1
X = Xsmooth + wx, Y = Ysmooth + wy  (no clamp before the XY-depth scaling)
```

---------------------------------------------------------------------------------------------------------------------
## 9. Velocity, aftertouch, random amp/pan, freq->pan, freq->env speed

### 9.1 Velocity value: `vel = VEL(midiVel)` (5.1), plus the amp level on a same-key retrigger (5.3). Used by amp
velocity (9.2), filter/mod env velocity (2.5), pitch env velocity (3.2) and the filter (filter_dist.md).
### 9.2 Amp velocity sensitivity P[8780] (p108, -1..1), recomputed every block [V]
```
velScaleAmp = s > 0 ? pow(vel, 2s) : 1 + s*vel          // s <= 0 uses the linear form (s = 0 -> 1)
velGain(+0x2a10) = randAmp * velScaleAmp
per block:  if (|velGain - g| < 1e-5) g = velGain (constant for the block)
            else per sample g = 0.002*velGain + 0.998*g          (g = +0x2a14; 0.002 = 1-0.998f; not SR-scaled)
output = signal * ampEnv[i] * g * panGain       (placement relative to filter/dist: filter_dist.md §4)
```
### 9.3 Aftertouch value `at` (voice arg): mode 0 -> 1.0; 1 -> channel pressure (smoothed, and set by every note-on
velocity); 2 -> per-key AT. Consumers: osc amp touch P[8524] (dB): `P>0.01: 10^((at-1)*P*0.05); P<-0.01:
10^(at*P*0.05)` [V]; noise touch P[8532] same form (osc spec); cutoff touch P[8460] semitones (filter); afterpitch
P[8476]/P[8480] (1.3) [V].
### 9.4 Freq -> env speed P[8792] (p111, -1..1 shown as ±200 %/octave), note-on only [V]
`envSpeed = Oct^(2*P[8792]*(ln(f0/P[9060])/lnOct - P[9076]/12))`; P[9076] = Pan reference (st from A, -9 = C4). At
P[8792] = 0.5 (100 %/oct) the envelopes run twice as fast per octave above the pan reference. It scales the amp,
filter and pitch envelopes, not the mod envelopes.
### 9.5 Pan, per block [V]
```
p = basePan + (|P[8788]| > 0.001 ? P[8788]*(ln(Rg*fGlide/P[9060])/lnOct - P[9076]/12) : 0)   // freq->pan, %/octave
  + lfo1Pan*lfo1DepthF + lfo2Pan*lfo2DepthF      // lfoNPan: 4.6 (per-note LFO) or the VM value (global LFO)
  + globalPan + sum(ME pan target 16: (me - sus)*d*2)   // globalPan from XY/CC (6.2)
p = clamp(p, 0, 1);  g = 2/sqrt(2 - 4p(1-p));  L = (1-p)g, R = p*g  (ramped linearly over the block)
```
`fGlide` = the voice's current (glided) note frequency; Rg includes bend, LFO pitch, tuning table and pitch env.
Random pan P[8796]: `basePan = 0.5 + (rand()/32768 - 0.5)*P[8796]`, set once at note-on of a fresh voice.
Random amp P[8800]: ±P[8800] dB uniform (5.4), fixed per note (set at every note-on).

---------------------------------------------------------------------------------------------------------------------
## 10. Voice-struct fields written/read by the modulation code (for the renderer)
| offset | meaning |
|---|---|
| +0x08 byte | stereo-unison latch (osc spec) ; +0x09 byte active ; +0x0c int key |
| +0x10/+0x14/+0x18/+0x1c | glide start freq, note freq f0, glide progress (2.0/1.0 = done), progress per sample |
| +0x1b60 [16] | unison pitch jitter randoms `(rand*2/32767-1)/1200` (voice reset only) |
| +0x1ba0 [16] | unison pan jitter randoms `rand*2/32767-1` |
| +0x1be0 [16] | unison detune ratios (voice_osc.md 7.3) |
| +0x2970 / +0x2990 / +0x29b0 | amp env, mod env 1, mod env 2 state (2.2) |
| +0x29d0 / +0x29e8 | LFO 1 / LFO 2 (4.2) |
| +0x2a00 | LFO2 value of the previous block (cross mod) |
| +0x2a04 | -1 while held; samples since release otherwise |
| +0x2a08 | velocity (curve value, + retrigger level) |
| +0x2a0c | random amp gain; +0x2a10 velocity gain target; +0x2a14 smoothed velocity gain |
| +0x2a18 | base pan (random pan) ; +0x2a1c/+0x2a20 current pan gains L/R |
| +0x2a24 | freq->env speed factor |
| +0x2a28 | current filter mix |
| +0x2a2c / +0x2a30 | M1 / M2 value of the previous block (for XY depth) |
| +0x2a34 / +0x2a38 | pitch env ratio R / stage |
VM (plugin +0x1e6858): +0x100 float[128] per-key AT, +0x300 prog*, +0x31c/+0x33c phantom envs, +0x35c/+0x374 global
LFOs, +0x594 global LFO2 previous value, +0x598/+0x59c phantom env values (after ME depth).

---------------------------------------------------------------------------------------------------------------------
## 11. Quirks to keep (all affect the sound)
1. Amp env: attack output `1-(1-t)^2`, decays mapped through smoothstep between their end points, release re-scaled to
   hit 0 at L = 0.001, 0.5 ms one-pole on everything, transition sample processed twice.
2. Amp env hold lasts `hold*speed` (speed > 1 lengthens it); block envs use `hold/speed`.
3. Sustain pedal (CC64 with "Sustain pedal" on) makes every release (amp, filter, mod, phantom) 128x slower in dB/s.
4. Pitch env start ratio uses 2^(st/12) regardless of the Octave param; start <= -48 st gives ratio 0 (silence/DC).
5. Pitch env attack with peak < start runs at double speed.
6. XY "LFO 1 speed" target also changes LFO 2's speed.
7. XY LFO-depth modulation of LFO pitch uses Oct^(2D) when both LFOs are per-note, Oct^(4D) otherwise.
8. CC "LFO depth" on a global LFO is applied twice (2^(7*cc*d) in total).
9. LFO -> cutoff and -> resonance use the unipolar (0..1) LFO value; LFO pitch and pan are bipolar.
10. Same-key retrigger adds the current raw amp level to the velocity (can exceed 1).
11. Phantom envs freeze while no voice is playing (VM early exit).
12. Mod envelopes ignore freq->env speed; amp/filter/pitch envs use it.
13. Unison: centre-voice jitter 1200x too small (voice_osc.md 7.3).
14. Filter env not advanced while the filter is off (filter_dist.md).
15. Saw/square LFO tables interpolate to T[0] in the last 1/32768 of the cycle.
16. Noise pitch ignores bend, LFO pitch, tuning table and pitch env.

---------------------------------------------------------------------------------------------------------------------
## 12. Verification (32-bit harness, 44.1 kHz, 64-frame blocks, scripts in OM/work_mod/)
Reference models: `envmodel.py` (EnvParams / AmpEnv / BlockEnv), `lfomodel.py` (LFO), `t_penv.py` (PEnv).
Helpers: `mc.py` (chunk editing, Teager amplitude, zero-crossing frequency).
* Amp env (`t_env1.py`): three ADSR sets (attack 5..100 ms, hold 0/50, bp 1/0.5/0.2 (rising decay 2), sus, release)
  compared per sample with the Teager envelope of a 440 Hz sine: |err| < 1e-4 except in 5 ms attacks, where the
  estimator itself is off (max 0.05). Note-off during attack and same-key retrigger (`t_retrig.py`) max err 0.005.
  Hold*speed quirk (`t_hold.py`): model err 0.002, hold/speed model err 0.7. Sustain pedal (`t_pedal.py`): -4.686
  dB/s measured vs -4.6875 expected.
* Pitch (`t_pitch.py`): Tune main, Octave, tuning table, global transpose, bend (range, Octave), osc2 transpose/
  detune: relative error < 3e-6.
* LFO (`t_lfo2.py`, `t_lfo3.py`, `t_lfo5.py`): via LFO -> pan (exact per-block observable): all 4 table shapes,
  units ms/10ms/sec/beat units, quantize, user shapes (LFO1/2), phase param, cross-mod both ways, global reset and
  free modes: max error 2e-6. Increment rounding confirmed by reading the global LFO phase from memory. Stepping/smooth
  random: new value exactly at the phase wrap.
* LFO pitch depth law and XY depth scaling (`t_lfop.py`, `t_lfo1.py`): square LFO gives exactly -3.1104 st for p = 0.6;
  XY depth factors 1.414 / 2.0 by mode as in quirk 7.
* Pitch env (`t_penv.py`, `t_penv2.py`): attack rising/falling (double speed), decay, sustain, velocity ±, release
  st/s, Octave 3: median error 0.6 cents (the ramp-aware estimator's resolution).
* Routing (`t_mod1..7.py`): velocity sens (±), osc touch ±12 dB, AT modes, XY -> amp dB, freq->pan, random pan,
  freq->env speed, ME1 -> pitch (bipolar/unipolar/negative, velocity ±), ME1 -> pan (err 3e-6), ME1 -> amp (dbF),
  CC -> pan (bipolar), X -> pan, CC -> XY depth, XY/CC -> LFO depth, XY -> LFO speed (+ LFO2 quirk), ME1 -> LFO1
  speed per-note and global (phantom), ME1 -> LFO depth, XY -> amp env speed, XY -> ME depth, CC -> mod env speed,
  ME2 with hold + decay 1 + velocity, ME -> XY depth (both paths), CC/XY pitch targets: all match (pan errors < 1e-5,
  pitch < 1e-4 st).
* LFO -> cutoff unipolar (`t_lfocut.py`): with a square LFO at 0, output identical to unmodulated (diff 0.0).

---------------------------------------------------------------------------------------------------------------------
## 13. Open questions / not verified
* Filter-env shape inside the filter, and XY/CC cutoff/res/env-mod scaling: from code (and filter_dist.md), not
  re-measured here.
* PW/PWM, noise and unison targets: formulas from code only (osc spec has the consumers).
* Sub-block lengths other than 64 (host buffers not a multiple of 64): all block-rate processes use the actual n,
  but the smoothing coefficient k64 is fixed. Not tested.
* Voice-mode numbering: P[8760] 0 = mono (retrigger; other voices released), 1 = poly, 2 = mono legato (checked with
  `t_legato.py`: in mode 2 the amp attack continues through the second note and the pitch changes; in mode 0 the first
  note is released and a new voice starts). The display strings are empty in this build. Allocation details:
  notes_arp.md.
* Exact rand() call order (needed only to reproduce random LFOs, random pan/amp/freq and XY walk bit-exactly).
