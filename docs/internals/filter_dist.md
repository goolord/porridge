# Oatmeal voice filter section + distortion — implementation spec

Scope: `0x10007450` (voice filter, 16 types), `0x10005a00` usage (filter envelope hook), the filter part of the voice
renderer `0x1005d560` (doubling / mix / split / where amp-env and distortion sit), and `0x1002e820` (distortion,
per voice and global). All statements marked **[V]** were verified sample-by-sample against the real DLL
(see §8); the rest is from the disassembly.

Reference Python models (bit-level faithful, float32 stores): `OM/work_filter/fmodel.py` (filter core +
cutoff/resonance header `block_cutoff_res`), `OM/work_filter/dmodel.py` (distortion). Test drivers are in the same
folder (see §8).

Conventions: `f32(x)` = round to IEEE float (all state variables and most intermediates are stored as float;
arithmetic is x87 extended — doing arithmetic in double and rounding at stores reproduces the DLL to ~1e-7).
"Oct" = the **Octave** parameter value (p179, chunk 9064, default 2.0); every "octave/semitone" modulation in
the filter uses `pow(Oct, …)`, not `pow(2, …)`. `lnOct` = chunk 9068 (= ln Oct, derived each process call).
`n` = number of samples in the current control block (always 64 in normal operation; the main process runs
the voices in 64-sample sub-blocks).

---------------------------------------------------------------------------------------------------------------

## 1. Parameters and storage

| param | name | chunk | internal value | notes |
|---|---|---|---|---|
| 41 | Filter | 8428 lo16 | `int(v*15+0.5)` 0..15 | type index, table below |
| 42 | Filter 2 | 8428 hi16 | `int(v*15+0.5)` 0..15 | 0 = "same as filter 1", 1..15 = type (no separate "off") |
| 43 | Cutoff | 8432 | v (0..1) | Hz = `f32(v³·10980 + 20)` (20 … 11000 Hz) |
| 44 | Resonance | 8436 | 0..1 | |
| 57 | F envmod | 8440 | −1..1 | ×8 → ±8 "octaves" |
| 52 | F keytrack | 8444 | −2..2 | octaves/octave |
| 55 | F split | 8448 | 0..1 | ×24 st (2·split "octaves") added to filter 2 only |
| 56 | F envspeed | 8452 | r = 5−8v (v≤0.5); 1/(1+8(v−0.5)) (v>0.5) | filter-2 env time multiplier (display for v>0.5 is buggy) |
| 54 | F mix | 8456 | 0..1 | |
| 59 | F aftertouch | 8460 | −48..48 semitones | |
| 53 | F double | 8464 | 0 off / 1 parallel / 2 serial | |
| 58 | F env velo sens | 9512 | −1..1 | |
| 24/35 | LFO1/LFO2 cut 1 | 8560/8596 | −1..1 (×4 oct) | |
| 25/36 | LFO1/LFO2 cut 2 | 8564/8600 | −1..1 (×4 oct) | |
| 26/37 | LFO1/LFO2 res | 8568/8604 | 0..1 | |
| 178 | Tune main | 9060 | Hz | |
| 179 | Octave | 9064 | 1.01..5 | 9068 = ln(Oct) |
| 180 | Cut reference | 9072 | −24..24 st | see §2 quirk |
| 172 | Dist type | 9036 | 0 off, 1 hard, 2 soft(tanh), 3 sine, 4 asym | |
| 173 | Dist mode | 9040 | 0 global, 1 voice-after-filter, 2 voice-before-filter, 3 double | |
| 174 | Dist limit | 9044 | −30..30 dB | |
| 175 | Dist pregain | 9048 | −60..60 dB | |
| 176 | Dist postgain | 9052 | −60..60 dB | |
| 177 | Dist oversample | 9056 | 0 off, 1 2x, 2 4x, 3 8x | |

Filter type index (p41 / p42, strings at 0x88ffc.. / menu strings 0x81370..):
`0 Off, 1 1P lowpass, 2 2P lowpass, 3 4P lowpass, 4 1P highpass, 5 2P highpass, 6 4P highpass,
7 2P wide bandpass ("2P bandpass (weak)" in the menu), 8 2P narrow bandpass, 9 4P bandpass, 10 2P notch,
11 nonlinear 2P lowpass, 12 nonlinear 4P lowpass, 13 Phaser 4 stages, 14 Phaser 12 stages, 15 Phaser 36 stages`
(display strings for 13–15 are empty in this build; the phaser names only exist in the right-click menu).
Filter-2 effective type: `t2 = (int32(packed) >> 16) != 0 ? packed >> 16 : packed & 0xffff`.

Filter-2 envelope (derived struct at P+8364, recomputed at the start of every process call, 0x10068228):
attack, hold, decay1, decay2, release = the filter-envelope (P+8300) times × r (p56); breakpoint and sustain
copied unchanged. **[V]** (F2 with ratio r ≡ F1 with all times ×r, residual 1e-4 from time rounding).

---------------------------------------------------------------------------------------------------------------

## 2. Per-block cutoff and resonance (header of 0x10007450)

Filter object layout (0x228 bytes; voice has 4: F1L +0x1ca0, F2L +0x1ec8, F1R +0x20f0, F2R +0x2318):
`+0` ptr to program at chunk 8296 (so `[+0]+0x84` = packed types, `+0x88` cutoff, …), `+4` ptr to an object whose
`+4` is the int sample rate, `+8` byte isF2, `+0xc` envelope generator (0x20 bytes; F1 uses the filter env
P+8300, F2 uses the derived filter-2 env P+8364), `+0x30` byte reset flag, `+0x34..+0x228` coefficient/state
fields (listed with each type in §3).

Call (thiscall, `ret 0x38`): `filter(buf*, cc[6]*, semisMod, resMod, lfo1, lfo2, n, a8, vel, a10, at, X, Y, envSpeed)`
(values supplied by the voice renderer; see "inputs" below).

```
if (!prog || !srobj) return;  type = (isF2 && (packed>>16)) ? packed>>16 : packed & 0xffff;
if (type == 0 || n < 1 || !buf) return;            // NOTE: envelope is NOT advanced when type==0
SR = (float)srobj->sr;  if (SR < 44100) SR = 44100; // quirk, [V] at 22050 Hz
env = envGen.render(n, max(envSpeed,0.01))          // level at the END of this block (0x10005a00)
vs = p58;  if (vs > 0.001) env *= pow(vel, 2*vs);  else if (vs < -0.001) env *= 1 + vel*vs;      [V]
Hz = f32(c*c*c*10980 + 20)                                          (c = p43)                   [V]
if (|ft| > 1e-4)  Hz *= pow(Oct, at*ft/12)                           (ft = p59 semitones)        [V]
if (|kt| > 1e-6) {                                                   (kt = p52)
    Hz *= exp( kt*ln(a8/Tune*max(a10,0.0625)) + CutRef*lnOct/12 )   (Tune=p178, CutRef=p180)    [V]
}
// modulation-matrix sums (X/Y targets p202-205/p211-214, depths p198-201/p207-210;
// CC c=0..5 targets/depths at chunk 10128+36c / 10112+36c; cc[c] = smoothed CC values 0..1)
envmod = p57; resX=resY=resCC=0; cutX=cutY=cutCC=0;  tgt = isF2 ? 2 : 1;
for k in 0..3:
   X-slot:  target 4 → envmod += X*Xdepth[k];  target 3 → resX += Xdepth[k];  target tgt → cutX += Xdepth[k]
   Y-slot:  same with Y (resY, cutY)
   CC c:    target 4 → envmod += cc[c]*d;      target 3 → resCC += cc[c]*d;    target tgt → cutCC += cc[c]*d
envmod = clamp(envmod, -1, 1)
oct = (lfo1*LFO1cut + lfo2*LFO2cut + cutX*X + cutY*Y + cutCC) * 4      (cut1 params for F1, cut2 for F2)
if (isF2) oct += 2*split                                                (split = p55 internal 0..1)  [V]
oct += envmod * env * 8
Hz = f32(Hz * pow(Oct, oct))                                                                     [V]
if (|semisMod| > 1e-4) Hz *= pow(Oct, semisMod/12)
Hz = max(Hz, 5.0)                                                                                [V]
// resonance
r0 = p44
res = (lfo1*LFO1res + lfo2*LFO2res) * (1-r0) + r0
for m in (resX*X, resY*Y, resCC, resMod):  res += (m > 0) ? (1-r0)*m : r0*m                      [V]
res = clamp(f32(res), 0, 1)
```
Target numbering used here is the XY/CC list (1 cutoff 1, 2 cutoff 2, 3 resonance, 4 filter env mod,
7 distortion, 24 filter mix, 29/30 filter envelope speed).

Inputs (from the voice renderer 0x1005d560; other specs own their exact derivation):
* `a8·a10/Tune` = the voice's current frequency relative to Tune main. Measured **[V]**: includes pitch bend
  (smoothed), global transpose, pitch envelope and the key (tracking is exact `(F/440)^kt` for key changes);
  Tune main cancels; osc-2 Transpose (p12) does not enter. `a8` is the glide-interpolated base value
  (voice +0x10/+0x14/+0x18), `a10` the pitch-modulation ratio (LFO pitch, tuning table, bend …); a10 is clamped
  to ≥ 1/16 before the log.
* `vel` = voice velocity value (voice +0x2a08); `at` = per-key aftertouch value (voice arg 12). With the default
  curves both measured as `min(1, vel/125)` (vel 127→1.0, 100→0.8, 64→0.512, 1→0.008).
* `lfo1/lfo2` = LFO outputs as passed to the voice, already multiplied by the "LFO depth" mod factors.
* `semisMod` (F1: voice local +0x58, F2: +0x2c) = mod-envelope cutoff sums in semitones:
  target cutoff 1/2 (bipolar): `(ME − ME_sustain)·depth·48`; target cutoff 1/2 unipolar (23/24): `ME·depth·24`.
  `resMod` (+0x6c) = Σ `ME·depth` for target resonance. (ME = mod-env level incl. its velocity scaling.)
* `envSpeed` = `4^(Σ XY/CC "filter envelope speed" mods) · voice freq-env scale (+0x2a24)`; passed to the env.
* X, Y: smoothed XY values (−1..1) incl. random walk; cc[6]: smoothed CCs (see CONTEXT.md smoothing).

Quirk — **Cut reference** is not a reference: `CutRef·lnOct/12` is added outside the `kt·` product and only
when keytrack ≠ 0. With kt = 1 and CutRef = +12, the cutoff equals the knob value at F = 220 Hz, not the displayed
880 Hz; with kt = 0.5 it is simply a +12 st cutoff offset. **[V]** (4 combinations).

---------------------------------------------------------------------------------------------------------------

## 3. Filter core (per block, after §2)

Common setup:
```
w = f32(2/SR * PI_F * Hz)                      PI_F = 3.14159274 (float pi)
if type in {2,3,8,9,11,12}: w = f32(w*0.5)      // these run a 2x-oversampled SVF (two iterations per sample)
if w > PI_F*0.98f: w = f32(PI_F*0.98f)          // 0.98f = 0.980000019
ksm  = f32(1 - 10^(-1.5*n/(SR*0.02f)))          // per-block coefficient smoothing; 0.2218 at 44.1k, n=64
inv_n = f32(1/n)
first = resetFlag;  (resetFlag cleared at the end of any processed block)
```
Coefficient smoothing pattern "S" (types 1,2,3,4,5,6,8,9,11,12 — every smoothed coefficient `c` with state `cs`):
```
if first: cs = f32(target); tgt = target          // (plus a negligible target−f32(target) residual ramp)
else:     tgt = (target - cs)*ksm + cs            // one-pole per block
dc = f32((tgt - cs) * inv_n)                     // then linear per-sample ramp from cs to tgt
per sample:  c = cs + dc; cs = f32(c)            // c (unrounded) is what the sample uses
```
Output gains `G` of the SVF types are also ramped: `G` starts at `g(q_state_before)` and gets
`dG = f32((g(q_new) − g(q_old))·inv_n)` added each sample (G itself is never stored; recomputed each block from
the stored states).

SVF coefficients (all SVF types): `f = 2·sin(w/2)`, clamped `f ≤ 1.2f` (1.20000005); `q = 1 − 0.995f·res`
(q ∈ [0.005, 1], q is the damping). One SVF step with input `u` (the input is scaled by q):
```
low  = f32(low + f*band)
high = q*u - low - q*band
band = f32(band + f*high)
```
Consequence of the f ≤ 1.2 clamp: single-rate SVF types (5, 6, 10) cannot exceed ≈ 0.2048·SR (9.03 kHz at 44.1k);
2x types saturate at ≈ 0.41·SR.

| type | rate | per-sample processing (x = input sample) | output gain G(f,q) | state fields |
|---|---|---|---|---|
| 1 1P LP | 1x | `c = t/(1+t)` computed as `(sin w + cos w − 1)/(2cos w)`, `t=tan(w/2)`, S-smoothed; `y = (1−2c)·y1 + c·(x + x1)` | 1 | c +0x34, x1 +0x38, y1 +0x3c |
| 4 1P HP | 1x | `c = 1 − (sin w+cos w−1)/(2cos w) = 1/(1+t)`, S; `y = (2c−1)·y1 + c·(x − x1)` | 1 | c +0x40, x1 +0x44, y1 +0x48 |
| 2 2P LP | 2x | twice: SVF(u=x); out = G·low | `sqrt(1/q)` | f +0x4c, q +0x50, low +0x54, band +0x58 |
| 11 NL 2P LP | 2x | twice: `low = T(low + f·band)` (instead of the plain update), then `band += f·(q·x − low − q·band)`; out = G·low | `sqrt(1/q)` | shares type-2 fields |
| 5 2P HP | 1x | SVF(u=x); `out = (high + high_prev)·G`; high_prev = f32(high) | `0.5·sqrt(1/q)` | f +0x5c, q +0x60, low +0x64, band +0x68, hp +0x6c |
| 3 4P LP | 2x | twice: SVF1(u=x); SVF2(u=low1 (stored)); out = G·low2 | `1/q` | f +0x70, q +0x74, l1 +0x78, b1 +0x7c, l2 +0x80, b2 +0x84 |
| 12 NL 4P LP | 2x | as type 3 but SVF2 uses `low2 = T(low2 + f·band2)`; SVF1 linear | `1/q` | shares type-3 fields |
| 6 4P HP | 1x | SVF1(u=x) → h1 (unrounded); SVF2(u=h1); `out = (h2 + h2_prev)·G`; h2_prev = f32(h2) | `0.5/q` | f +0x88, q +0x8c, l1 +0x90, b1 +0x94, l2 +0x98, b2 +0x9c, hp +0xa0 |
| 8 2P narrow BP | 2x | it1: SVF(u=x) → b_mid = band; it2: SVF(u=x); `out = (band + b_mid)·G` | `0.5·sqrt(0.01f/(f·q))` | f +0xc0 (reset 1e-4), q +0xc4, low +0xc8, band +0xcc |
| 9 4P BP | 2x | each of 2 iterations: SVF1(u=x); SVF2(u=low1) → h2 (it1 value stored f32 at +0xe8); `out = (h2_it2 + h2_it1)·G` | `0.005f/(f·q)` | f +0xd0 (reset 1e-4), q +0xd4, l1 +0xd8, b1 +0xdc, l2 +0xe0, b2 +0xe4, h +0xe8 |
| 10 2P notch | 1x | **no smoothing, no interpolation** (f, q set every block): SVF(u=x); `out = (high + low)·G` | `1/q` | f +0xec, q +0xf0, low +0xf4, band +0xf8 |
| 7 2P wide BP | 1x | **no smoothing**: `c = (sin w+cos w−1)/(2cos w)` (tan-form LP coef); `r1 = f32(1−res)`; `a1 = f32(r1(1−c)+c)`, `a2 = (1−c)+r1·c`; LP: `y = f32((1−2a1)·y1 + a1·(x+x1))`; HP: `o = f32((2a2−1)·o1 + a2·(y − y1))` | 1 | c +0xa4, a1 +0xa8, a2 +0xac, x1 +0xb0, y +0xb4, y1 +0xb8, o +0xbc |
| 13/14/15 phaser | 1x | `p = 2/w·PI_F·(2/N)` (N = 4, 12, 36 → factor 0.5, 0.166666672, 0.055555556), `a = (1−p)/(1+p)`; smoothing variant "P" (below); `v = x − pr·T(fb)`; for k in 0..N−1: `y = f32(v·a + X[k] − Y[k]·a); X[k] = f32(v); Y[k] = y; v = y`; `fb = v; out = v` (no dry mix) | 1 | pr +0xfc, a +0x100, X[36] +0x104, Y[36] +0x194, fb +0x224 |

Notes on the table:
* In type 7 at res = 0 the LP coefficient is 1 and the HP coefficient is 1 ⇒ identity (flat). At res = 1 it is a
  bilinear 1-pole LP at fc followed by a 1-pole HP at fc. **[V]** (exact 0 error at res 0).
* Phaser smoothing "P" (differs from S): `if first {as=f32(a); rs=res} else {as=f32(as+(a−as)·ksm); rs=f32(rs+(res−rs)·ksm)}`
  — the state itself jumps at block start — then `da=f32((a−as)·inv_n)`, `dr=f32((res−rs)·inv_n)` and per sample
  `as=f32(as+da)`, `pr = rs+dr` (unrounded, used) / `rs=f32(pr)`. I.e. the phaser coefficient always reaches the
  *unsmoothed* target at the end of the block. Phaser feedback = resonance (0..1) through `T()`.
* Phaser allpass `y = a·v + x₁ − a·y₁` = `(a + z⁻¹)/(1 + a z⁻¹)`; `p = 2π/(w·N) = SR_eff/(N·Hz)`, so each stage's
  −90° frequency is `f90 = SR/π · atan(N·Hz/SR)` (≈ N·Hz/π at low Hz; e.g. 4 stages @ 1 kHz cutoff → 1270 Hz).
  Output is the wet allpass chain only, so the audible effect comes from the resonance feedback (and from
  modulation of the cutoff).
* `T(v)` (nonlinear types and phaser feedback): table `NL[i] = f32(tanh(8·(f32(i·(1/2048)) − 1)))`, i = 0..4096
  (built at 0x10007230, global 0x100ef4f8); `u = (|v+8| − |v−8|)·128 + 2048` (= 256·clamp(v,±8)+2048);
  `i = trunc(u)`, `fr = u − i`; `T = (1−fr)·NL[i] + fr·NL[i+1]` (NL[4097] = 0, only ever read with weight 0).
  Regenerated table is bit-identical to the DLL's.
* Reset (0x10007310, called from voice reset 0x1005d3a0): resetFlag = 1; envelope reset; `+0x34,+0x40,+0x50,+0x60,
  +0x74,+0x8c,+0xa4,+0xa8,+0xac,+0xc4,+0xd4,+0xf0 = 1.0`; `+0xc0,+0xd0 = 1e-4`; everything else 0 (all 36+36
  phaser states, fb). The voice reset runs when a voice whose amp-env level is < 1e-4 is (re)allocated
  (0x1000bed3); a still-sounding voice that is retriggered/stolen keeps its filter state. Types sharing fields:
  2/11 and 3/12. Switching type mid-note continues with whatever state that type last had.
* No denormal handling anywhere (x87). Flushing denormals in a port is harmless.
* All filters are mono per call; a "stereo" voice (unison spread, voice flag +0x13) runs independent L/R instances
  with identical parameters.

---------------------------------------------------------------------------------------------------------------

## 4. Voice-level routing (0x1005d560, 0x100620dd … 0x10063c6d)

Let `x[i]` = osc+noise mix of the voice (noise amplitude is pre-filter **[V]**), `env[i]` = amp envelope (per
sample), `g` = voice gain (+0x2a14, smoothed per sample `g = 0.998g + k·target`, snaps when |Δ|<1e-5; voice spec),
`E[i] = env[i]·g`, `low[i] = env[i] < 1/16`.

### 4.1 Filter doubling (p53) and mix (p54)
Mix target per block: `mm = clamp(Σ "filter mix" mods (XY/CC target 24, ME target 22), −1, 1)`;
`M = mm > 0 ? mix + (1−mix)·mm : mix·(1+mm)`. Mix state `m` (voice +0x2a28) ramps linearly per sample:
`dm = (M − m)/n; per sample m += dm` (measured: at note start m already equals M — no ramp **[V]**; mid-note
changes ramp over one block **[V]**).

* **off**: `y = F1(x)` (F2 not run; F2 envelope not advanced).
* **parallel** **[V]**: `a = F1(x)`, `b = F2(x)` (same input); `y[i] = (1−m_i)·a[i] + m_i·b[i]`.
* **serial** **[V]** (including mid-block crossing of 0.5):
  ```
  a[i]  = F1(x)[i] + 8·max(m_i − 0.5, 0)·x[i]        // "higher values mix the input into filter 2"
  y[i]  = F2(a)[i] + 8·max(0.5 − m_i, 0)·a[i]        // "lower values pass filter-1 output around filter 2"
  ```
  (At exactly 0.5 plain series. Implementation detail: the DLL branches on m/M vs 0.5 and runs the two injection
  loops only when needed; the result equals the formula above. Up to +4·x / +4·a are injected at the extremes.)
* Filter 2 cutoff = filter-1 cutoff law with `+2·split` octaves, cut-2 LFO/XY/CC/ME targets instead of cut-1,
  its own envelope (times ×r). F2 type "same" = F1 type.
* Quirk (contradicts the manual) **[V]**: with Filter = Off and doubling on, F1 passes the signal through
  unchanged and **F2 still filters** (explicit F2 type) — parallel: `(1−m)·x + m·F2(x)`; serial: `F2(x)` (+
  injections). With F2 "same" it is also off.

### 4.2 Amp envelope, distortion placement (p173)
```
mode 0 (global) or dist off:  v = Y(x) · E                      (Y = filter/doubling block above)
mode 1 (after filter):        v = D(Y(x) · E);   if low[i]: v *= 16·env[i]
mode 2 (before filter):       v = Y(D(x · E));   if low[i]: v *= 16·env[i]
mode 3 (double):              v = Y(D'(x · E));  if low[i]: v *= 16·env[i]   (D' = per-voice stage without post gain)
then pan / output (global stage of mode 0 and 3 runs on the summed stereo mix, before chorus)
```
The `16·env` correction (0x1038b210 = 1/0.0625) re-applies the envelope at the very end of the release so the
distorted tail fades out. Note in modes 2/3 the filter input is already envelope-scaled (matters for the
nonlinear filter types). All **[V]** at sustain (env = 1); the `<1/16` rule is from code only.
Stereo voices use a second distortion instance (+0x2758) for R. Per-voice distortion objects (+0x2540/+0x2758) are
**never reset** after construction (FIR histories and pre/post ramps persist across notes); the global one
(this+0x1e6df8) is reset by 0x1002e7d0 (panic/resume).

Bug worth knowing (not recommended to replicate): stereo voice + parallel doubling + dist mode 2/3 + a block with
env < 1/16 writes R to `out + 8*i + 0x200` instead of `+4` (0x100627bf), leaving R stale for that block.

---------------------------------------------------------------------------------------------------------------

## 5. Distortion 0x1002e820

Call: `dist(buf, cc[6], X, Y, n, isGlobal)`; per voice `buf` is mono, global `buf` is interleaved stereo.
Object (0x218): `+0` prog ptr (chunk 16), `+4` SR holder, `+8` reset flag, `+0xc` pre state, `+0x10` post state,
`+0x14` h_L[32], `+0x94` h_R[32], `+0x114` u_L[32], `+0x194` u_R[32], `+0x214` index. Constructor: reset=1, pre=post=1,
buffers 0, idx 0.

Per block **[V]**:
```
if type == 0 return
dm   = (Σ_k Xdepth[k]·[Xtarget==7] · X + Σ_k Ydepth·[..]·Y + Σ_{c,k} ccdepth·[cctarget==7]·cc[c]) · 30   // dB
lim  = f32(limit − dm)
pre  = f32(10^((pregain − lim)·0.05f))           // = drive, normalised so that "limit" maps to ±1
post = 10^((lim + postgain + dm)·0.05f)          // = 10^((limit+postgain)/20): mod does not change output level
if (mode == 3 && !isGlobal) post = 1             // double mode: no limit/post scaling in the per-voice stage
if (reset) { reset = 0; preS = pre; postS = post }
dpre = f32((pre − preS)/n);  dpost = f32((post − postS)/n)
per sample: preS = f32(preS + dpre); postS = f32(postS + dpost);  out = OS_shape(in·preS)·postS
```
Shapers `S(v)` (tables built at 0x1002e690, all regenerate bit-exactly):
1. hard: `(|v+1| − |v−1|)·0.5` = clamp(v, −1, 1)
2. soft: `u = (|v+8|−|v−8|)·64 + 1024`; `i=trunc(u), fr=u−i`; lerp of `TS[i] = f32(tanh((i−1024)/128))`, i=0..2048
3. sine: `u = v·2048; i = trunc(u) − (u<0 ? 1 : 0); fr = u − i; k = i & 2047`; lerp of `TSIN[k], TSIN[k+1]`,
   `TSIN[j] = f32(sin(j·PI_F/1024))`, j = 0..2048  ⇒ `S(v) ≈ sin(2π·v)` (periodic, no clamp)
4. asym: `u = (|v+2| − |v−14| + 16)·64` (= 128·clamp(v,−2,14)+256); lerp of
   `TA[i] = f32(2·exp(−c·exp((2 − i/128)·f32(1/c))) − 1)`, c = f32(ln 2), i = 0..2048
   ⇒ `S(v) = 2·2^(−e^(−v/ln2)) − 1` (Gompertz curve: S(0)=0, S'(0)=1, → +1 slowly for v>0, ≈ −1 at v ≤ −2)

Oversampling (OS = 2, 4, 8; `full[32]` = FIR from the table set selected by SR, see below), per input sample
(both channels share `idx`):
```
h[idx] = f32(x·preS·OS)
for p in 0..OS-1:  u[(idx+p)&31] = f32( S( Σ_{k=0}^{32/OS-1} h[(idx − OS·k)&31] · full[p + OS·k] ) )
y = Σ_{j=0}^{31} u[(idx+OS−1−j)&31] · full[j]
out = f32(y·postS);   idx = (idx + OS) & 31
```
i.e. zero-stuffing interpolation with gain OS through the 32-tap FIR, shaping at OS·SR, then the same 32-tap FIR
and plain decimation. The FIRs are **not** normalised: small-signal gain into the shaper = Σfull, overall linear
gain = (Σfull)² — set 0 (44.1k): 2x 0.949 / 0.901, 4x 0.804 / 0.647, 8x 1.481 / 2.193 (i.e. 8x drives the shaper
+3.4 dB harder and is ~+6.8 dB louder in the linear region). Part of the sound — keep it.
Changing OS mid-stream keeps `idx` (can misalign the stuffed samples) — edge case.

FIR set selection by integer SR: set0 SR ≤ 46050; set1 46050 < SR < 68100; set2 68100 ≤ SR < 92100; set3 ≥ 92100.
Coefficients (all 32-tap filters are symmetric: full[31−j] = full[j]; first 16 listed; exact float32 values;
also in `OM/work_filter/dist_fir_coeffs.json`; tables live at 0x1007cbe8 + 0x300·set: 2x @+0, 4x @+0x100, 8x @+0x200,
followed by their polyphase copies):
```
set0 2x: -0.000729989493,-0.00555753848,-0.0135504249,-0.0143905282,0.000386684609,0.0167762768,0.00824460667,-0.0202910695,-0.0231291335,0.0191786028,0.0465012304,-0.00685944688,-0.0845687762,-0.0353548639,0.18493399,0.403144836
set0 4x: 0.00228226185,0.00480223121,0.00746307708,0.00804945454,0.00416513346,-0.00574596785,-0.0210167337,-0.0378923528,-0.0498275124,-0.049202431,-0.0300765261,0.0089996662,0.0633200333,0.12243297,0.172769383,0.201722875
set0 8x: -0.00126208563,0.00125461002,0.00302423304,0.00612585992,0.0107180299,0.0169317331,0.0247897096,0.0341765583,0.0448106974,0.0562515445,0.0679231808,0.0791568011,0.0892457813,0.0975145027,0.10338439,0.106431723
set1 2x: 0.000714151189,-0.00125134375,-0.00747857848,-0.0104524232,-0.000276158709,0.0139544671,0.00755497254,-0.0184321608,-0.0220366362,0.0179940108,0.0452956632,-0.00627887435,-0.0835914835,-0.0355942063,0.184358627,0.403412551
set1 4x: 0.00247393968,0.0061032814,0.0109078949,0.014646356,0.0142715573,0.0070925178,-0.00744477613,-0.0263193566,-0.0427714661,-0.0479419455,-0.0340422653,0.00206159172,0.0564177334,0.118026756,0.171712026,0.202969193
set1 8x: -0.00048500151,0.00175015407,0.00355905085,0.00673236372,0.0113371983,0.0174944773,0.0252285432,0.0344263613,0.0448159948,0.0559733957,0.0673417822,0.0782737806,0.0880862474,0.0961255729,0.101831101,0.104792438
set2 2x: -8.14509986e-06,9.24569977e-05,0.000587028393,0.00122850994,0.000364132313,-0.00336672971,-0.00652577681,-0.00105146074,0.0140335029,0.021008132,-0.00296973437,-0.0477030799,-0.0543041788,0.0357576273,0.203174561,0.339860767
set2 4x: -0.000300386106,-0.00118230062,-0.00311021344,-0.00642000791,-0.011059328,-0.0162817892,-0.0204799268,-0.0212996192,-0.0161117539,-0.00278419117,0.0194502231,0.0493300371,0.083398141,0.116492212,0.142835826,0.157448113
set2 8x: 0.00134671666,0.00268536387,0.00467012962,0.00789050199,0.0118392212,0.0171235856,0.0232114885,0.0304225404,0.0381408744,0.0463988259,0.0545141101,0.0623074323,0.0691312104,0.0747342333,0.0786433592,0.080684796
set3 2x: 9.73037022e-05,0.0004424449,0.00076496962,-4.90614002e-05,-0.00284952507,-0.00555029465,-0.00273392769,0.0082663605,0.018835647,0.0113155199,-0.0211239662,-0.0533956215,-0.0361708924,0.0606655888,0.205781683,0.315010279
set3 4x: -2.69251996e-05,-0.000427582389,-0.00140781177,-0.00328214234,-0.00603572885,-0.00911144633,-0.0112158516,-0.0103724524,-0.00429987488,0.00891248137,0.0300055742,0.0579071864,0.0895308927,0.120188653,0.144581854,0.158112839
set3 8x: -8.04110969e-05,0.00123617996,0.00255127507,0.00489620725,0.00833775289,0.013011775,0.0189716332,0.0261534825,0.0343611389,0.0432637222,0.0524119735,0.0612719581,0.0692703873,0.0758528337,0.0805388168,0.0829754695
```
Global stage: called from the main process when type ≠ 0 and mode ∈ {0, 3}, on the summed interleaved stereo
buffer, with the global smoothed X, Y and CCs, `isGlobal = 1` (post gain applied). **[V]**

---------------------------------------------------------------------------------------------------------------

## 6. Sample-rate dependencies
* Filter: SR is clamped to ≥ 44100 inside the filter (below 44.1 kHz all cutoffs are too low by SR/44100 and the
  smoothing is slower) **[V]**. w, ksm depend on SR (and on n = 64). Nothing else in the filter depends on SR.
* Distortion: only the FIR set (4 SR ranges) **[V]** at 44.1/48/88.2/96 kHz.
* Envelope timing: filter/filter-2 envelopes via 0x10005a00 (envelope spec).

## 7. Quirks to keep (summary)
1. Cut reference sign/scaling (§2). 2. SR < 44.1k clamp in the filter. 3. SVF f ≤ 1.2 ⇒ HP2/HP4/notch max
≈ 0.205·SR. 4. Notch and wide-BP coefficients jump per block (no smoothing); phaser coefficient reaches target
each block; others one-pole smoothed (ksm) + per-sample ramp. 5. Per-type fixed output gains (sqrt(1/q), 1/q,
0.5·sqrt(0.01/(fq)), 0.005/(fq) …) — e.g. the 4P BP is very quiet at high cutoff and loud at low cutoff.
6. Filter env not advanced while the filter type is Off / F2 not running. 7. F2 works with F1 off. 8. Serial mix
injection gains up to 4×. 9. Distortion oversampling FIR gains (8x louder). 10. Per-voice dist never reset.
11. `16·env` tail correction for per-voice distortion. 12. Filter 2 envspeed display wrong for v > 0.5.

## 8. Verification (DLL vs model)
Harness: `harness.py` + `render_cases.py` (32-bit, drives Oatmeal.dll), `compare.py`, `fithz.py`, `cmpdist.py`,
`cmpdist2.py`, `cmpdbl.py` (64-bit models). Test signal = the voice's white noise (osc amps 0, N amp 0 dB,
N reso 0, sustain 100 %, attack 0.2 ms, vel-sens 0, random amp/freq 0). The noise is
`rand()/16384 − 1` from MSVCRT `rand()` (holdrand·214013+2531011, >>16 & 0x7fff); `msvcrt.srand(12345)` before
each note makes renders reproducible and the model regenerates the identical sequence (the voice consumes 471
rand() values at note-on before the first noise sample). Filter input is therefore known exactly; the post-filter
gain chain is taken from a filter-off render.
* All 15 filter types × 3 cutoff/res settings: rel. RMS error 1e-7 … 3e-6 (nonlinear types ≤ 5e-5) — i.e.
  float rounding. Also at +12/+24 dB input for 11, 12, 13, 15, 2 (≤ 2e-5), at SR 22050 (clamp), 48000, 96000.
* Coefficient smoothing: block-aligned cutoff/res jumps for types 1,2,3,5,7,9,10,11,13: ≤ 8e-6.
* Cutoff law: fitted effective Hz vs formula for keytrack (4 keys, ±kt, cut-ref), aftertouch, env mod ±,
  env velocity sensitivity ±, X→cutoff/env-mod, 5 Hz floor, bend/transpose/pitch-env/tune: ratio 1.000000
  (bend 0.99983 = 8191/8192 of the range, as expected).
* X→resonance ±: ≤ 5e-7. Doubling parallel/serial (mix 0.2/0.5/0.8/1.0, split 0/5/7/12/24, mixed types,
  mid-note mix ramps): ≤ 1e-6. F2 envspeed ratio 2 and 1/3: equivalent to scaled F1 env (1e-4).
* Distortion: 4 types × 4 OS × 2 gain settings (per voice, mode 1): ≤ 3e-6 (sine ≤ 5e-5); global mode (hard/soft
  4x/asym 8x), pre-filter mode, double mode, X→distortion mod: ≤ 7e-6; FIR sets at 48k/88.2k/96k: ≤ 5e-5.

## 9. Open questions / not covered
* Exact definitions of the voice-supplied inputs (a8/a10 split, vel/at curves, LFO output scaling, mod-env
  levels, freq-env speed factor) — owned by the voice/LFO/envelope specs; the filter formulas above take them as
  given. LFO→cutoff/res paths were read from code but not measured.
* Where the voice mix state (+0x2a28) gets initialised to the target at note start (only constructor writes 0
  were found; behaviour measured).
* The `16·env` release correction and the mode-2/3 envelope ordering were verified only at env = 1.
* Behaviour for host block sizes that are not multiples of 64 (n < 64 blocks change ksm/ramps) — use 64.
