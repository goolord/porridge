# Oatmeal per-voice sound generation: oscillators, noise, unison, voice output stage

Reverse-engineered from Oatmeal.dll (release 38-1): the per-voice renderer `0x1005d560`, the oscillator code
(`0x10010060`, `0x10010650`, `0x100111a0`, `0x10012870`, `0x10013ad0`, `0x10010600`, `0x100103b0/0x10010440/0x100104d0`),
the wavetable builders (`0x1000f9e0`, `0x1000fc20`, `0x1000fcd0`), the noise source (`0x1000f250..0x1000f310`), the voice
note-on (`0x10063e20`) and the voice reset (`0x1005d3a0`).

Function map: `0x10010650` plain oscillator block · `0x100111a0` oscillator with hard-sync in/out and BLEP ·
`0x10012870` oscillator with FM in/out · `0x10010060` wavetable/mip selection · `0x10013ac0` osc setBase ·
`0x10013ad0` osc glideTo · `0x10010600` unison parameter copy · `0x100103b0` / `0x10010440` / `0x100104d0` osc
phase / PWM-phase / full reset · `0x10010330` osc constructor · `0x1000f310` noise block · `0x1000f2a0` / `0x1000f2b0`
noise setFreq / glideTo · `0x1000f280` noise reset · `0x1000f9e0` builds the sine, saw and triangle tables (once) ·
`0x1000fc20` user wave -> set · `0x1000fcd0` set from a 32768-point table. Black boxes called by the renderer:
`0x100050c0` amp envelope (fills E[], returns alive) · `0x10005a00` mod envelopes · `0x10009470` LFOs ·
`0x10007450` filter · `0x1002e820` distortion.

**Verification.** Every numbered algorithm below was checked sample by sample against DLL renders. The pure-Python models
are in `OM/work_osc/`, and section 13 lists the errors (float32 rounding level, typically < 1e-6 absolute on
full-scale signals). The DLL's wavetables were dumped from process memory and match the construction in section 2 to
<= 6e-7.

Notation: `f32(x)` = round to IEEE float. The DLL uses x87 code, so intermediates are 64-bit-mantissa and are rounded only
when stored. All persistent state is float32 or uint32. `P[x]` = program field at **chunk offset x** (live struct at
`plugin+0x1e3388+x`; the voice holds a pointer to chunk offset 16, so the code reads `[P16 + x-16]`). `pN` = VM
parameter index N. `ftol(x)` = x87 `_ftol` = **truncation toward zero** to int64, and callers keep only the low 32 bits
(so `ftol(x)&0xffffffff` wraps modulo 2^32). `SR` = integer sample rate. `n` = voice sub-block length, which is always 64
(the voice manager renders in 64-sample sub-blocks; the renderer clamps `n` to 128 and zero-fills the rest).
`Oct` = `P[9064]` ("Octave", normally 2.0). Every `Oct^(x/12)` below is `pow(P[9064], x*f32(1/12))`.

---------------------------------------------------------------------------------------------------------------------
## 0. Overview: what one voice does per 64-sample block (renderer 0x1005d560)

```
voice.render(out[2n], ccs, lfoArgs..., semis, ..., panOffset, modSums*, at, X, Y, n)  -> bool alive
 1. modulation: CC->"XY depth", mod-envelope 1/2 (0x10005a00), per-voice LFOs (0x10009470)        [modulation spec]
 2. amp envelope E[0..n) = 0x100050c0(...)   -- if it returns false: voice.active=0, return false [envelope spec]
 3. pitch envelope ratio, sums of all mod sources per target (osc1/2/noise amp & pitch, PW, PWM   [modulation spec]
    rate/depth, pan, noise resonance, unison detune/spread, filter...)
 4. unison detune ratios ratio[k]                                                      (section 7.3)
 5. global pitch ratio Rg, osc1/osc2 pitch ratios                                      (section 7.4)
 6. noise: set frequency, render into M (mono) or NZ (stereo-unison)                   (section 6)
 7. oscillator parameters: amp targets, PW/PWM (osc1, osc2)                            (section 7.5)
 8. oscillators: unison voice 0 into M, voices 1..U-1 into M or into their own buffers (section 7.6)
 9. pan target; for stereo unison, mix the voices to M(L)/R with per-voice pan gains    (section 8)
10. velocity x random-amp gain target                                                  (section 9)
11. dist mode 2/3 (pre-filter): M(,R) *= E*s ; per-voice distortion                    (section 10)
12. filter(s)  [filter spec]
13. dist mode 1: M(,R) *= E*s ; distortion ; tail fix     | dist mode 2/3: tail fix
    no dist / global dist: nothing here
14. write out[2i], out[2i+1] (mono path: M*E*s*panL/panR; stereo path: M, R)            (section 10)
```
The voice manager adds `out` (written, not accumulated) into the interleaved mix buffer.

---------------------------------------------------------------------------------------------------------------------
## 1. Objects and state

### 1.1 Oscillator object (0xd8 bytes; voice has osc1[16] at +0x60 and osc2[16] at +0xde0, one per unison voice)
| off | type | meaning |
|---|---|---|
| +0x00 | int | waveform 0 sine, 1 saw, 2 pulse, 3 triangle, 4 user, 5 user PWM (copied each block from P[8468]/P[8472]) |
| +0x04 | float | amplitude target (set each block) |
| +0x08 | float | amplitude, current (ramped) |
| +0x0c | int | "first block" flag: when set, amp = target without a ramp, then cleared |
| +0x10 | u32 | phase (2^32 = one cycle) |
| +0x14 | u32 | pitch offset added to the increment (ramped, see 3.1) |
| +0x18 | u32 | base increment (note frequency: 2^32*f/SR) |
| +0x1c | u32 | glide target increment |
| +0x20 | int | glide samples remaining |
| +0x24 | int32 | glide step per sample |
| +0x28 | byte | glide active |
| +0x2c | u32 | pulse width (phase units, P[8484]/P[8488] + modulation) |
| +0x30 | u32 | current pulse width (ramped) |
| +0x34 | u32 | PWM LFO phase |
| +0x38 | u32 | PWM LFO increment per sample |
| +0x3c | float | PWM depth (already halved, see 7.5) |
| +0x44 | float[32] | BLEP residual ring (hard sync) |
| +0xc4 | int | ring index |
| +0xc8,+0xcc | float | FM-out lowpass states s1, s2 |
| +0xd0,+0xd4 | float | FM-out highpass x1, y1 |

Constructor `0x10010330`: ampTarget=1.0, amp=0, first=1, `+0x2c = +0x30 = 0x80000000`, `phase = rand()<<17`,
`pwmPhase = rand()<<17`, everything else 0. (The voice constructor then runs the voice reset, which re-sets the phases.)
Reset `0x100104d0(P)` (at voice reset): zeroes +0x08, +0x14, +0x18..+0x28, +0x38, +0x40, the ring and its index, and
the FM states. It sets first=1 and sets both phases (11.2). The reset does **not** touch +0x2c/+0x30/+0x3c.

### 1.2 Noise object (voice+0x20, 0x40 bytes)
`+0 P, +4 ctx, +8 first(int), +0xc freq(Hz,float), +0x10 glideTarget, +0x14 glideOn(byte), +0x18 glideRemaining(int),
+0x1c glideStep(float/sample), +0x20 l1, +0x24 l2, +0x28 b1, +0x2c b2, +0x30 h2a, +0x34 F, +0x38 q, +0x3c g`.
Reset `0x1000f280` (voice reset): first=1 and l1..h2a, g are set to 0. F and q are not reset.

### 1.3 Voice object (relevant fields)
| off | meaning |
|---|---|
| +0x0 / +0x4 | program ptr (chunk offset 16) / context ctx (`[ctx+4]` = SR int, `[ctx+0x10]` / `[ctx+0x14]` = osc1 / osc2 user wavetable set = plugin+0xa4b54 / plugin+0x143f6c) |
| +0x8 | byte "stereo latch" (set once the stereo-unison path has run, cleared only by voice reset) |
| +0x9 | byte active |
| +0xc | note number |
| +0x10,+0x14,+0x18,+0x1c | frequency glide for freq->pan: start Hz, target Hz, progress (0..1; 2.0 = none), progress per sample |
| +0x20 | noise object |
| +0x60 / +0xde0 | osc1[16] / osc2[16] |
| +0x1b60 | float jit[16]: `(rand()*f32(2^-14+2^-29) - 1) * f32(1/1200)` (unison pitch jitter) |
| +0x1ba0 | float panr[16]: `rand()*f32(2^-14+2^-29) - 1` (unison pan jitter) |
| +0x1be0 | float ratio[16]: unison detune ratios (recomputed every block) |
| +0x1c20 / +0x1c60 | float uniL[16] / uniR[16]: per-unison-voice pan gain states (init 1.0) |
| +0x1ca0, +0x1ec8 / +0x20f0, +0x2318 | filter 1, filter 2 for M(left/mono) / for R |
| +0x2540 / +0x2758 | per-voice distortion for M / for R |
| +0x2970, +0x2990, +0x29b0, +0x29d0, +0x29e8 | amp env, mod env 1, mod env 2, LFO 1, LFO 2 |
| +0x2a08 | velocity after the velocity curve (0..1) |
| +0x2a0c | random-amp gain |
| +0x2a10 / +0x2a14 | velocity x random gain: target / smoothed value s |
| +0x2a18 | base pan (0.5 + random pan) |
| +0x2a1c / +0x2a20 | main pan gain state L / R (mono path and stereo-path noise) |
| +0x2a24 | freq->env-speed factor |

Voice reset `0x1005d3a0`: runs at construction, on program-pointer change, and from the voice manager when it
(re)allocates a voice whose amp-env level is < 1e-4 (a silent voice). It sets
`+0x2a04=-1, note=-1, +8=+9=0, +0x2a2c=+0x2a30=0, basepan=0.5, +0x10=+0x14=P[9060] (440), +0x18=2.0, +0x1c=0`
and resets the noise. Then for k=0..15, in this order: `osc1[k].reset(P); osc2[k].reset(P); ratio[k]=uniL[k]=uniR[k]=1.0;
jit[k]=(rand()*c-1)*f32(1/1200); panr[k]=rand()*c-1` with `c = f32(6.10370189e-05)` (= 2^-14+2^-29). Then it
resets the LFOs, filters and envelopes and sets `+0x2a08=+0x2a0c=+0x2a10=+0x2a14=1.0`.
A voice that is stolen while it still sounds is **not** reset. Its oscillator pitch offsets, amplitudes, filters,
BLEP rings and noise filter continue from their old state.

---------------------------------------------------------------------------------------------------------------------
## 2. Wavetables (verified bit-for-bit against memory dumps; `OM/work_osc/tables.py`)

### 2.1 Sine table (global, 0x10174078): 32768 + 1 floats
`sine[i] = f32(sin(f32(pi) * i / 16384))` for i = 0..32767. This uses the float constant 3.14159274 and x87 `fsin`, so
double `sin` gives identical floats. The guard `sine[32768] = 0.0`.
Sine oscillators read this table directly (no mip levels) with shift 17, mask 0x1ffff, frac scale 2^-17, and linear
interpolation. The PWM LFO reads it without interpolation.

### 2.2 The built-in "saw" source (32768 floats)
`S[i] = f32(1.5*sqrt(i/32768) - 1)`, i = 0..32767. **The saw is not a linear ramp.** It is a rising square-root curve
from -1 up to +0.5 followed by the drop. It has zero mean. Its harmonics fall more slowly than 1/k: relative to h1,
h2 = -5.4 dB, h3 = -8.6, h4 = -10.9, h8 = -16.6, h32 = -28.1, h128 = -38.9. Its fundamental amplitude is 0.371
(512-sample version).

### 2.3 The built-in "triangle" source (from S)
```
A = 0; B = 0                               // x87 extended accumulators
for i in 0..32767:
    A += S[i] - S[(i - 16384) & 32767]     // integral of S(phi) - S(phi - 1/2)  (a "pulse" of the curved saw)
    B += A
    U[i] = f32(A)
mean = f32(B / 32768)
M = 1e-12
for i: U[i] = f32(U[i] - mean);  M = max(M, |U[i]|)
for i: U[i] = f32(U[i] * (1/M))            // peak normalized to 1
```
The result has only odd harmonics (h3 -18.1 dB, h5 -26.7, h7 -32.4, h9 -36.7, h15 -45.4). Its fundamental amplitude
is 0.804.

### 2.4 User waveforms -> T0 (`0x1000fc20(wave512)`, per oscillator, plugin+0xa4b54 / +0x143f6c)
The source is `P[32..]` (osc1) or `P[2080..]` (osc2), float[512]. The builder takes a 512-point real FFT, scales it by
1/512, zero-pads the half-complex spectrum to 32768 points (bins 0..256 kept), and applies an inverse 32768-point FFT.
The result is the band-limited periodic interpolation:
```
c_k = (1/512) * sum_n w[n] e^{-2 pi i k n/512}      (k = 0..256)
T0[m] = c_0 + sum_{k=1..256} 2 Re(c_k e^{2 pi i k m/32768}),  m = 0..32767
```
Quirk: bin 256 was the 512-point Nyquist bin, but here it becomes an ordinary bin, so its amplitude is **doubled**
(`2 c_256 cos(...)` instead of `c_256 cos(...)`). Everything below then runs on T0. The DLL uses float FFTs; a double
computation rounded to f32 agrees to <= 6e-7. The two user sets are rebuilt whenever a program is loaded or selected
and whenever the waveform editor changes them.

### 2.5 Table set layout (`0x1000fcd0(T0)`): 0x9f418 bytes = 163078 floats per set
The global saw set (0x10194090) is built from `S`, the global triangle set (0x102334b0) from `U`, and the user sets from
their T0. Each table stores its length N plus one guard sample `t[N] = t[0]`. Offsets are in bytes from the set start:

| byte offset | contents |
|---|---|
| 0x7f414 | T0: 32768 (+1) = the input exactly |
| 0x6f410 | T1: 16384 (+1), `T1[i] = T0[2i]` |
| 0x6740c | T2: 8192 (+1), `T2[i] = T1[2i]` |
| 0x63408 | T3: 4096 (+1) |
| 0x61404 | T4: 2048 (+1) |
| 0x60400 | T5: 1024 (+1) |
| 0x20200 | T6: 512 (+1), `T6[i] = T0[64 i]` (plain decimation, **no** anti-alias filtering) |
| 0x20a04 + j*0x804, j = 0..126 | M512[j]: 512 (+1) samples, harmonics **0..255-j** of T6 |
| 0x0 | M256top: 256 (+1): harmonics 0..128 of T6 (as a 512 table), then decimated by 2 |
| 0x404 + j*0x404, j = 0..126 | M256[j]: 256 (+1), harmonics **0..127-j** of M256top |

Construction details:
* `C = FFT512(T6)/512`. `M512[j]` = inverse transform of C with bins 256-j..256 set to zero (real and imaginary parts),
  so it keeps bins 0..255-j. DC is always kept.
* M256top: take C with bins 129..256 zeroed (harmonics 0..128), apply the inverse transform to 512 samples, then keep
  every 2nd sample. Harmonic 128 then lies on the 256-point Nyquist: its cosine part survives and its sine part is lost.
* `C2 = FFT256(M256top)/256`. `M256[j]` keeps bins 0..127-j of C2.
* The saw/triangle T0..T6 therefore contain the **naive** (aliased) curves. All M tables are exact truncated Fourier
  series of the naive 512-sample decimation T6.

A Fourier-series construction in double precision reproduces the DLL's float-FFT tables to <= 4e-7 (reference:
`tables.py: build_set, set_to_flat`). The tables can be precomputed offline for saw and triangle. User tables must be
built at runtime (or at preset load) from the 512 wave samples.

### 2.6 Table selection (`0x10010060(inc)`), done once per block from `inc = base + offset (+ FM extra)`
```
inc < 2^17 : T0,  shift 17        inc < 2^18 : T1, shift 18       inc < 2^19 : T2, shift 19
inc < 2^20 : T3,  shift 20        inc < 2^21 : T4, shift 21       inc < 2^22 : T5, shift 22
inc < 2^23 : T6,  shift 23
inc < 2^24 : j = ftol(257 - 256/(inc * f32(2^-23)))
             j > 127 ? (M256top, shift 24) : (j == 0 ? T6 : M512[j-1], shift 23)   // j clamped >= 0
inc < 2^25 : M256top, shift 24
else       : j = clamp(ftol(129 - 128/(inc * f32(2^-24))), 0, 127)
             j == 0 ? M256top : M256[j-1], shift 24
mask = 2^shift - 1,  fracScale = f32(2^-shift)
```
The table used contains exactly the harmonics h < SR/(2 f) (`hmax = ceil(0.5/f_norm) - 1`). Below `SR/512`
(inc < 2^23, e.g. < 86 Hz at 44.1 kHz) the full (naive for saw/tri) table of the smallest length with a step of at
most 1 sample is used. Above SR/4 only the fundamental is left, which aliases once f > SR/2. Sine never uses mip
levels.

### 2.7 Lookup (every oscillator, every read)
```
lerp(T, ph) = (1 - fr) * T[ph >> shift] + fr * T[(ph >> shift) + 1],   fr = (ph & mask) * fracScale
```
(ph is uint32, `fr` is computed exactly in x87.)

---------------------------------------------------------------------------------------------------------------------
## 3. Plain oscillator render (`0x10010650(out, userSet, n, mult)`, `out[i] +=`), used in "normal" mix mode

### 3.1 Block prologue (identical in all three oscillator functions)
```
if (step == 0) { glideRem = 0; if (glideOn) base = glideTarget; glideOn = 0; }
tgtOff = ftol((mult - 1.0) * (int32)base + 0.5)     // base read as SIGNED int32 (fimul)
q      = (int32)(tgtOff - offset) / n               // 32-bit wrapping sub, idiv truncates
slope  = ftol(q + 0.5)                              // => q if q >= 0, q+1 if q < 0  (quirk)
if (first) { amp = ampTarget; first = 0; }
astep  = f32((ampTarget - amp) / n)
table  = select(waveform, (offset + base) & 0xffffffff [+ FM extra])  // sine: fixed sine table
if (glideOn) { if (glideRem <= n) { glideRem = 0; step = 0; base = glideTarget; glideOn = 0; }  // jumps to the end
               else glideRem -= n; }
glideUp = glideTarget > base                        // unsigned; picks the clamp direction for this block
if (waveform in {2,5}) pwmBlock()                   // 3.3
```
`mult` is the block's pitch ratio (1.0 = base pitch). The offset ramps linearly toward `(mult-1)*base` within the
block, and pitch modulation is block-rate with that ramp. Because `slope` is truncated, the offset only reaches
`n*q` (the remainder is never applied): a static detune ends a few increment units short, below 1e-7 of the frequency.

### 3.2 Per sample
```
for i in 0..n-1:
    amp = amp + astep                         (used unrounded; stored as f32)
    if (waveform in {2,5} && pwmActive) pwCur += pwStep            (u32 wrap)
    if (glideOn at block start) {             // otherwise base is constant
        b2 = base + step
        if (glideUp ? b2 > glideTarget : b2 < glideTarget) { b2 = glideTarget; step = 0; glideRem = 0; glideOn = 0; }
        base = b2 }
    if (waveform in {2,5}) { out[i] = f32(out[i] + amp*lerp(T,phase)); out[i] = f32(out[i] - amp*lerp(T,(phase+pwCur)&M)); }
    else                    out[i] = f32(out[i] + amp*lerp(T,phase))
    phase += base + offset                     (u32 wrap)
    offset += slope                            (u32 wrap)
```
Waveform to table: 0 = sine table; 1 saw and 2 pulse = saw set; 3 = triangle set; 4 user and 5 user-PWM = that
oscillator's user set. **Pulse = saw(phi) - saw(phi + pw)** (a difference of the curved saws, so the top and bottom are
not flat). It has zero mean for every pw, is ±1 at pw = 50 %, and is silent at 0 %/100 %. User PWM applies the same
difference to the user wave. The output sample uses the phase before the increment. A new note starts at phase0 exactly
(sample 0 = lerp(T, phase0)).

### 3.3 PWM (pulse and user PWM only), once per block
```
if (|pwmDepth| > 1e-4) {                       // pwmDepth = osc+0x3c
    pwmActive = 1
    pwmPhase += pwmInc * n                      (u32)
    s   = sine[pwmPhase >> 17]                  (no interpolation)
    tgt = (pw * 2^-32 + (s + 1) * pwmDepth) * 2^32            // pw = osc+0x2c
    d = tgt - pwCur;  if (d > 2^31) d -= 2^32; else if (d < -2^31) d += 2^32
    d /= n;  if (d < 0) d += 2^32
    pwStep = ftol(d + 0.5)                      (low 32 bits)
} else { pwmActive = 0; pwCur = pw }            // PWM LFO phase does not advance
```
So the pulse width moves linearly within each block toward `pw + (1+sin)*depth` (modulo 1). The LFO is a unipolar
sine that adds 0..2*depth to the width (and `depth` stored = (P_depth+mod)/2, see 7.5).

---------------------------------------------------------------------------------------------------------------------
## 4. Hard sync (`0x100111a0(out, userSet, n, mult, syncIn, syncOut)`), mix mode 1

osc1 (master) runs with `syncIn = null, syncOut = S[n]` and osc2 (slave) with `syncIn = S, syncOut = null`, both adding
into the same buffer. The prologue and PWM are as in 3.1/3.3. The loop per sample (glide and PWM updates as in 3.2):
```
y = (waveform in {2,5}) ? lerp(T,phase) - lerp(T,phase+pwCur) : lerp(T,phase)     // f32 temp
out[i] = f32(out[i] + (y + ring[idx]) * amp);   ring[idx] = 0;   idx = (idx+1) & 31
inc = base + offset;   phase += inc
if (syncIn && syncIn[i] != 0) {                         // slave reset
    v = syncIn[i]
    phase = (v - 1) * (inc >> 5)                        (u32)
    d = y(phase) - y                                    // new value minus the value just output (no amp)
    K = BLEP[(v - 1) & 31]                              // 16 floats, specs/voice_osc_blep.txt
    for k in 0..15: ring[(idx + k) & 31] = f32(ring[(idx + k) & 31] + d * K[k])
}
if (syncOut) {                                          // master wrap detection
    if (phase < prevPhase) {                            // unsigned
        st = inc >> 5;  v = 1;  t = phase
        loop { t -= st;  if (t >= phase) break;  if (++v >= 32) break; }   // v = min(32, floor(phase/st) + 1)
        syncOut[i] = v
    } else syncOut[i] = 0
}
offset += slope;  prevPhase = phase                     // prevPhase starts as the phase at block start
```
The BLEP is a 16-tap residual (kernel row r is for a reset r/32..(r+1)/32 of a sample before sample time i+1). It is
added to the next 16 output samples and starts at about -1: the step is faded in band-limited. The master's own ring
stays 0. The slave's reset phase `(v-1)*(inc>>5)` accounts for the sub-sample time elapsed since the master wrap in
1/32-sample steps. In sync mode osc1 is audible (its amp works normally).

---------------------------------------------------------------------------------------------------------------------
## 5. FM (`0x10012870(out, userSet, n, mult, ctx, fmIn, fmOut)`), mix mode 2 "FM (1 -> 2, 1 silent)"

osc1 runs with `out = null` (**silent**), `fmIn = null, fmOut = F[129]`. osc2 runs with `out = M, fmIn = F, fmOut = null`.
```
if (fmOut) { c1 = f32(1 - 10^(-3 / f32(SR*f32(0.002))));  c2 = f32(10^(-2 / f32(SR*f32(0.01)))); }
else       { c1 = 1; c2 = 0.5 }
c3 = f32(2*c2 - 1)
extra = fmIn ? ftol((uint64)(base+offset) * fmIn[128]) : 0        // table selection uses inc + extra
prologue (3.1) with inc = base+offset+extra;  pwm (3.3)
mx = 0
per sample:
    amp, pw, glide updates as 3.2
    if (fmIn) phase += ftol((uint64)(base+offset) * fmIn[i])           (u32 wrap; through-zero possible)
    y = lerp-value(phase) * amp                        (pulse: difference as usual)
    if (out) out[i] = f32(out[i] + y)
    if (fmOut) {
        h  = c2*(y - x1) + c3*h1;   h1 = f32(h);  x1 = f32(y)       // 1-pole DC blocker / highpass
        s1 = f32(s1 + (h1 - s1)*c1)                                   // 2 one-pole lowpasses
        s2 = f32(s2 + (s1 - s2)*c1)
        fmOut[i] = s2;  mx = max(mx, s2)
    }
    phase += base + offset;  offset += slope
if (fmOut) fmOut[128] = mx          // signed max, starts at 0 (never negative)
```
So the carrier's instantaneous increment is `inc2 * (1 + F[i])`: linear FM whose index is set by osc1's amplitude
(osc1 amp P[8508] x modulation x aftertouch gain, linear, up to +30 dB = 31.6). **The modulator is filtered** by a
1st-order highpass (pole c3 = 0.9792 at 44.1 kHz, about 147 Hz) and two 1st-order lowpasses (pole 1-c1 = 0.9247, about
550 Hz each). |H| is -17.4 dB at 20 Hz, -5.3 dB at 100 Hz, peaks at -3.0 dB near 200 Hz, then -4.8 dB at 440 Hz,
-12.8 dB at 1 kHz and -23 dB at 2 kHz. The response is nearly SR-independent. As a result the FM depth depends
strongly on the modulator frequency, and higher modulator harmonics are suppressed. The carrier's table is selected
for the maximum instantaneous increment `inc*(1+max(0,maxF))`.

---------------------------------------------------------------------------------------------------------------------
## 6. Noise (`0x1000f310(buf, Rg, at, ampMod, resMod, n)`, **writes** buf)

Per block, in the renderer and only if `P[8528]` (N amp) > 0:
```
ratioN = Oct^((pitchN + P[8536]) / 12)                 // pitchN: sum of "noise pitch" mods (semitones), P[8536] = N transpose
noise.freq = osc1[0].base * SR * 2^-32 * ratioN         (Hz, float; osc1 base at block START, before its glide steps)
if (osc1[0].glideOn) noise.glideTo(osc1[0].glideTarget*SR*2^-32*ratioN, osc1[0].glideRem)
      // glideTo(t, m): target=t; if m > 64 {on=1; rem=m; step=f32((t-freq)/m)} else {on=0; step=0; freq=t; rem=0}
noise.render(buf, Rg, at, ampMod=noiseAmpMod, resMod=noiseResMod, n)
```
The noise pitch is tied to the note (osc1 base, including glide) and to the global pitch ratio Rg. It does not follow the
osc1-only pitch modulation, afterpitch or unison detune.

render:
```
amp = ampMod * P[8528]
if (P[8532] > 0.01)  amp *= 10^((at - 1) * P[8532] * 0.05)       // N aftertouch (dB), same law as osc AT (7.5)
if (P[8532] < -0.01) amp *= 10^(at * P[8532] * 0.05)
if (glideOn) { if (glideRem > n) { glideRem -= n; freq += n*glideStep; } else { glideOn=0; step=0; rem=0; freq=target; } }
if (P[8540] <= 0) {                                   // N resonance 0 -> raw white noise
    for i: buf[i] = f32(rand()*f32(2^-14) - 1) * amp            (writes; rand() = MSVCRT LCG, section 12)
    return }
for i: buf[i] = f32(rand()*f32(2^-14) - 1)            // raw noise first
w = min(Rg * freq * 0.5 / SR * f32(pi) * 2,  f32(f32(pi)*f32(0.98)))       // = pi*f/SR
F = f32(2*sin(w/2));  if (F > f32(1.2)) F = 1.2
m = clamp(resMod, -1, 1);  r = P[8540]
r' = m > 0 ? r + (1-r)*m : r*(1+m)
q = f32(1 - clamp(1 - (1-r')^2, 0, 1) * f32(0.995))                // damping, 1 .. 0.005
g = f32(amp * f32(0.05) / (q * F))                                  // peak normalization
if (first) { first = 0; Fs = F; qs = q; gs = g;
             repeat ftol((SR + 1.0)*0.5) times: x = f32(rand()*2^-14 - 1); svf(x); svf(x)  // warm-up, ~0.5 s of noise
}
dF = f32((F-Fs)/n), dq = f32((q-qs)/n), dg = f32((g-gs)/n)    // per-block linear ramps
for i: Fs += dF; qs += dq; gs += dg                              (stored f32; increment before use)
       a = svf(buf[i]);  b = svf(buf[i]);   buf[i] = f32((a + b) * gs)
svf(x):  // two Chamberlin SVFs in series, run twice per sample (2x oversampled, same input); returns h2
    l1 = f32(l1 + Fs*b1);  h1 = qs*x - l1 - qs*b1;   b1 = f32(b1 + Fs*h1)
    l2 = f32(l2 + Fs*b2);  h2 = qs*l1 - l2 - qs*b2;  b2 = f32(b2 + Fs*h2)
```
(In the second call the DLL keeps the first h2 in `+0x30` as a float. The output is the **sum of the two 2x-rate highpass
outputs of SVF2**, whose input is `q * lowpass(SVF1)`, which gives a resonant bandpass around `f`.) The warm-up runs
only on the first resonant block after a voice reset (not on every note). The filter state otherwise carries over
between notes of the same voice.

---------------------------------------------------------------------------------------------------------------------
## 7. Renderer: oscillator section in detail

### 7.1 Arguments of `0x1005d560` (thiscall on the voice; 15 stack args)
1 `out` float[2n] written (interleaved) · 2 `ccs` float[6] smoothed CCs · 3,4 global LFO values · 5,6 LFO1/LFO2 pitch
depths · 7 semitone offset (= `tune[note%12]*0.01 + P[9132]*12 + VM pitch sum`, which includes bend) · 8,9 LFO pan
depths · 10 pan offset · 11 `modSums*` = {int pw1, float pwmRate1, float pwmDepth1, int pw2, float pwmRate2,
float pwmDepth2} from XY/CC (may be null) · 12 `at` aftertouch value (1.0 in AT mode "ignore", channel pressure in
mode 1, per-key AT in mode 2; note-on velocity through the AT curve) · 13 X · 14 Y · 15 n.
(Args 3..10 are modified by the per-voice LFO code before use. Their exact semantics are in the modulation spec.
At the very start, X and Y are multiplied by the "XY depth" factor from the CC targets (`CC target 28`) and clamped to
[-2, 2]. They then drive the per-voice XY modulation targets and are passed to the per-voice distortion.)
Entry checks: returns false immediately if P, ctx or `active` is 0. If n > 128, the output beyond 128 frames is zeroed
and n is set to 128.

### 7.2 Per-block modulation sums consumed here (produced by step 3 of section 0; initial values)
`amp1 = amp2 = (U>1 ? sqrt(1/U) : 1)` and `ampN = 1` (multiplicative); `pitch1 = pitch2 = pitchN = 0` (semitones);
`pw1 = pw2 = 0` (u32 phase offsets); `pwmRate1/2 = 0`, `pwmDepth1/2 = 0`, `noiseResMod = 0`;
`D = P[10332]` (unison detune, cents) + mods; `spread = P[10336]` + mods, then clamped to [-1,1]. The mod sources
add or multiply into these (see the modulation spec). Unison normalization: **each oscillator of each unison voice is
at 1/sqrt(U)**. Noise is not normalized.

### 7.3 Unison detune ratios (per block; U = P[10328] int 1..16, J = P[10340] pitch jitter 0..1)
```
if (U <= 1) ratio[0] = 1
else if (U odd) {
    ratio[0] = J > 0 ? Oct^(J * jit[0] * D * f32(1/1200)) : 1      // QUIRK: jit[0] already has /1200 -> ~1200x too small
    h = (U-1)/2;  inv = f32(1/(h*1200))
    for k = 1..U-1: m = (k+1)>>1;  sg = (k odd) ? -D : +D
                    ratio[k] = Oct^((m*inv*f32(1-J) + J*jit[k]) * sg)
} else {
    h = U/2;  inv = f32(1/(h*1200))
    for k = 0..U-1: m = (k>>1)+1;  sg = (k odd) ? -D : +D
                    ratio[k] = Oct^((m*inv*f32(1-J) + J*jit[k]) * sg)
}
```
The voices are spread evenly over ±D cents: odd U gives k0 = 0, k1 = -D/h, k2 = +D/h, k3 = -2D/h, ...; even U gives
k0 = +D/h, k1 = -D/h, k2 = +2D/h, and so on. Jitter J replaces the fraction J of the regular position with the
per-voice random value `jit[k]*1200` in [-1, 1] (times D).

### 7.4 Pitch ratios
```
Rg     = Oct^((lfo1*arg5 + lfo2*arg6 + arg7) / 12) * pitchEnvRatio        (stored back into arg7)
AP1    = |P[8476]| > 0.01 ? Oct^(at * P[8476] / 12) : 1                   // 1 Afterpitch (semitones)
AP2    = |P[8480]| > 0.01 ? Oct^(at * P[8480] / 12) : 1
r1     = |pitch1| > 0.001 ? Oct^(pitch1/12) : 1
mult1  = r1 * AP1 * Rg           (f32)        -> osc1 unison k uses mult1 * ratio[k] (see 7.6)
mult2  = AP2 * Rg                (f32)        -> osc2 unison k uses mult2 * ratio[k]
osc2 base (every block, from the osc1 base of the same unison voice AFTER osc1 rendered):
  osc2[k].base = ftol(((double)osc1[k].base * SR * 2^-32 * Oct^(pitch2/12 + P[8516]) + P[8520]) * 2^32 / SR + 0.5)
  if (osc1[0].glideOn) osc2[0].glideTo(same formula with osc1[0].glideTarget, osc1[0].glideRem)   (only k = 0)
  else osc2[0].glideOn = 0
```
`P[8516]` (Transpose, p12) is stored **in octaves** (-4..4). `P[8520]` (Detune, p13) is Hz, added before Rg, AP2 and
unison are applied, so the Hz detune scales with pitch modulation. All of osc2's pitch follows osc1's base (note and
glide). Because osc2's base is computed after osc1 has advanced one block of glide, osc2 leads osc1's glide by one
block.
`glideTo(t, m)` = `0x10013ad0`:
```
target = t; d = (double)t - (double)base
if (|d| > 1000) { s = d/m; step = ftol(s > 0 ? s+0.5 : s-0.5); glideOn = 1; glideRem = ftol(|d/step| + 0.5) }
else            { base = t; step = 0; glideRem = 0; glideOn = 0 }
```

### 7.5 Oscillator parameters set each block (osc1 shown, osc2 identical with its fields)
```
atGain = 1
if (P[8524] >  0.01) atGain = 10^((at - 1) * P[8524] * 0.05)    // Osc aftertouch, dB (both oscillators)
if (P[8524] < -0.01) atGain = 10^( at      * P[8524] * 0.05)
osc1[0].waveform  = P[8468]
osc1[0].ampTarget = amp1 * P[8508] * atGain                      // "1 Amp" linear gain (osc2: amp2 * P[8512])
if (waveform in {2,5}) {
    osc1[0].pw       = P[8484] (u32) + pw1 (+ modSums.pw1)      // Pulsewidth as fraction*2^32
    osc1[0].pwmDepth = (pwmDepth1 (+modSums) + P[8492]) * 0.5
    rm = pwmRate1 (+modSums)
    rate = rm > 0 ? P[8500] + (16 - P[8500]) * rm : (rm + 1) * P[8500]        // Hz
    osc1[0].pwmInc   = ftol(rate * 2^32 / SR + 0.5)
}
```
Quirk: in AT mode "ignore" `at` = 1. A positive Osc-AT or N-AT then gives gain 1 (no effect), but a **negative Osc-AT or
N-AT attenuates by its full dB amount**. **Afterpitch 1 and 2 are applied in full** (for example, afterpitch +12 st
always raises the pitch an octave). In the other modes `at` comes from pressure or from note velocity through the AT
curve (the voice manager's job).

### 7.6 Oscillator dispatch and unison
```
for k = 1..U-1: osc1[k].copyFrom(osc1[0])     // 0x10010600: copies waveform, ampTarget, base, glideTarget,
                                              //   glideRem, step, glideOn, pw, pwmDepth, pwmInc (NOT phase,
                                              //   amp, offset, pwCur, pwmPhase, ring, FM state)
osc1[0]: mix 1: render_sync(M, set1, n, mult1*ratio[0], null, SYNC)
         mix 2: render_fm(null, set1, n, mult1*ratio[0], ctx, null, F)
         else : render(M, set1, n, mult1*ratio[0])
osc2[0].base = ...(7.4); glide; for k = 1..U-1: osc2[k].copyFrom(osc2[0])
osc2[0]: mix 1: render_sync(M, set2, n, mult2*ratio[0], SYNC, null)
         mix 2: render_fm(M, set2, n, mult2*ratio[0], ctx, F, null)
         else : render(M, set2, n, mult2*ratio[0])
for k = 1..U-1:                                // buffer B_k = M (mono path) or V_k zeroed (stereo path, 8.2)
    osc1[k] as above into B_k with mult = (mix == 0) ? mult1*ratio[k] : mult1        // QUIRK
    osc2[k].base = formula(osc1[k].base)       // no glideTo for k >= 1 (the glide state was copied)
    osc2[k] into B_k with mult = (mix == 0) ? mult2*ratio[k] : mult2                 // QUIRK
```
**Quirk:** in hardsync and FM modes, unison voices 1..U-1 are **not detuned**. Only voice 0 gets `ratio[0]` (which is 1,
or nearly 1, for odd U). With odd U all voices then have the same pitch and differ only by phase. With random phase 0
they are identical, which gives a plain gain of sqrt(U). With even U, voice 0 is at +D/h and all the others are at 0.
Verified against the DLL (the dump shows all offsets 0).
The unison voices share the SYNC / F buffers sequentially (osc1[k] writes, osc2[k] reads).
In the mono path, noise is written to M first and the oscillators add to it. If N amp <= 0, M is cleared instead.

---------------------------------------------------------------------------------------------------------------------
## 8. Pan and stereo unison

### 8.1 Pan target (every block)
```
if (voice.glideProgress(+0x18) < 1) { prog = min(1, prog + n*perSample(+0x1c)); f = f0 + (f1 - f0)*prog }
else { f0(+0x10) = f1(+0x14); prog = 1; f = f1 }                     // f1 = note frequency (Hz)
p = basePan(+0x2a18)
if (|P[8788]| > 0.001) p += P[8788] * (ln(Rg * f / P[9060]) / P[9068] - P[9076]/12)   // freq->pan, %/octave;
                                                                    // P[9068] = ln(Oct), P[9076] = Pan reference (st)
p += lfo1*arg8 + lfo2*arg9 + arg10;   p = clamp(p, 0, 1)
gain(p): g = 2/sqrt(2 - 4p(1-p));  L = (1-p)*g;  R = p*g               // constant power, L^2+R^2 = 2, centre = (1,1)
stepL = (L - panL(+0x2a1c)) * (1/n);  stepR = (R - panR(+0x2a20)) * (1/n)   // linear ramp over the block
```
basePan (note-on) = `0.5 + (rand()*f32(2^-15) - 0.5) * P[8796]` (random pan, uniform in ±RandomPan/2).
For a new voice the note-on also sets `panL/panR = gain(clamp(basePan + freqpan(f), 0, 1))` directly, with no
LFO/offset terms and no ramp. After that the renderer ramps every block (increment first, then use).

### 8.2 Stereo-unison path. Active when `U > 1 && (spread != 0 || voice.stereoLatch)`; sets the latch
```
if (P[8528] <= 0) { panL = L; panR = R }                   // snap noise pan state when noise is off
W = min(p, 1-p) * spread                                     // uses the clamped p of 8.1
for k = 0..U-1: pan[k] = f32( ((k*f32(2/(U-1)) - 1) * f32(1 - pj) + pj*panr[k]) * W + p )     // pj = P[10344]
swap(pan[0], pan[U>>1])                                      // unison voice 0 sits in the middle
for k: (Lk, Rk) = gain(pan[k]);  sLk = f32((Lk - uniL[k])/n), sRk = f32((Rk - uniR[k])/n)
voice 0:  for i: uniL[0] += sL0; uniR[0] += sR0;  R[i] = uniR[0]*M[i];  M[i] = uniL[0]*M[i]
k >= 1:   for i: uniL[k] += sLk; uniR[k] += sRk;  M[i] += uniL[k]*V_k[i];  R[i] += uniR[k]*V_k[i]
noise (if N amp > 0, rendered into its own buffer NZ): for i: panL += stepL; panR += stepR;
          M[i] += panL*NZ[i];  R[i] += panR*NZ[i]
```
From here on M is the left channel and R is the right channel. Both go through their own filters and distortions,
and the output writes them unchanged (the pan has already been applied). uniL/uniR start at 1.0 after a voice reset
(not reset at note-on).
The pitch detune mapping (7.3) and the pan mapping are not monotonic in the same order. For U = 5: voice k0 is at
pitch 0 and pan 0; k1 at -D/2 and -W/2; k2 at +D/2 and -W; k3 at -D and +W/2; k4 at +D and +W.

---------------------------------------------------------------------------------------------------------------------
## 9. Velocity and random amplitude
```
note-on: randAmp(+0x2a0c) = 10^((rand()*f32(2^-14) - 1) * P[8800] * 0.05)       // Random amp, ±P dB uniform
every block: vg = P[8780] > 0 ? pow(vel, 2*P[8780]) : 1 + P[8780]*vel               // Velocity sensitivity -1..1
             target(+0x2a10) = vg * randAmp          // vel = +0x2a08 = velocity through the velocity curve (0..1)
new voice at note-on: s(+0x2a14) = target (no smoothing)
when applied (section 10), per block:
   if (|target - s| > 1e-5)  per sample: s = f32(f32(1-0.998f)*target + 0.998f*s)     // one-pole, SR-dependent
   else                      s = target (constant)
```

---------------------------------------------------------------------------------------------------------------------
## 10. Envelope, distortion and filter placement, and the output write
`E[i]` is the amp envelope buffer for the block. `dist` is the per-voice distortion (`0x1002e820`, args
`(buf, ccs, X, Y, n, 0)`; objects voice+0x2540 for M and +0x2758 for R) and `filter` is the filter chain; both are
black boxes here. `stereo` is the 8.2 condition.
```
distOn = P[9036] != 0;  mode = P[9040]    // 0 global, 1 per voice after filter, 2 per voice before, 3 double
tail = false
if (distOn && mode in {2,3}) {            // pre-filter distortion
    for i: s-update (9);  M[i] *= s*E[i];  (R[i] *= s*E[i]);  if (E[i] < 1/16) tail = true
    dist(M); if (stereo) dist(R)
}
filter(M) (and filter(R) if stereo)
if (distOn && mode == 1) {                // post-filter distortion
    for i: s-update;  M[i] *= s*E[i];  (R[i] *= s*E[i]);  if (E[i] < 1/16) tail = true
    dist(M); if (stereo) dist(R)
}
if (distOn && mode != 0) {                // modes 1,2,3
    for i: if (tail && E[i] < 0.0625) { M[i] = E[i]*M[i]*16; R[i] = E[i]*R[i]*16 }   // fades the distorted tail
    stereo : out[2i] = M[i], out[2i+1] = R[i]
    mono   : panL += stepL; panR += stepR; out[2i] = M[i]*panL; out[2i+1] = M[i]*panR
} else {                                  // no distortion, or global distortion only
    for i: s-update;  x = M[i]*E[i]*s
    stereo : out[2i] = x;  out[2i+1] = R[i]*E[i]*s
    mono   : panL += stepL; panR += stepR; out[2i] = x*panL; out[2i+1] = x*panR
}
```
The amp envelope and velocity gain are always applied **before any per-voice distortion**, so the distortion is driven
by the enveloped signal. In dist modes 2 and 3 they are also applied before the filter. With no dist, or global dist
only, they are applied after the filter. In dist modes 1-3, samples whose envelope is below 1/16 get an extra `16*E`
gain after distortion (the `tail` flag is only an optimization: the effect is per sample). The global distortion (modes 0 and 3) lives in the main process (effects spec). The
mono path filters only M (filters voice+0x1ca0/+0x1ec8). The stereo path also filters R (+0x20f0/+0x2318) with the same
parameters.

---------------------------------------------------------------------------------------------------------------------
## 11. Note-on and initial phases (voice note-on `0x10063e20(prevVoice, double freq, note, vel)`)
### 11.1 Order of operations and rand() calls
```
+0x2a04 = -1;  vel(+0x2a08) = vel
randAmp = 10^((rand()*2^-14 - 1) * P[8800] * 0.05)                              // rand #1
if (!active) {                                                                  // new (not sounding) voice
    +0x2a2c = +0x2a30 = 0
    s = target = vg(vel) * randAmp                                              // section 9
    basePan = 0.5 + (rand()*2^-15 - 0.5) * P[8796]                              // rand #2
    panL/panR = gain(clamp(basePan + freqpan, 0, 1))                            // 8.1 without LFO/offset
    for k = 0..15: osc1[k].setPhase(P); osc2[k].setPhase(P);                    // 4 rand() per k, this order
                   osc1[k].setPwmPhase(P); osc2[k].setPwmPhase(P)
    reset per-voice LFOs
} else {                                                                        // retrigger of a sounding voice
    if (P[8816]) for k: osc1[k].setPhase(P); osc2[k].setPhase(P)                // Osc retrigger
    if (P[8828]) for k: osc1[k].setPwmPhase(P); osc2[k].setPwmPhase(P)          // PWM retrigger
    if (P[8840]) reset LFOs
}
freqEnv(+0x2a24) = Oct^(2*P[8792]*(ln(freq/P[9060])/P[9068] - P[9076]/12))       // envelope speed (uses Pan ref!)
envelope triggers ... [envelope spec]
glide (11.3) or: osc1[0].base = ftol(2^32*freq/SR + 0.5); osc1 glideOn = 0; noise freq = freq*Oct^(P[8536]/12);
                 +0x18 = 2.0; +0x10 = freq
+0x14 = freq; active = 1; note = note
```
Only `osc1[0]`, `osc2[0]` and the noise get their base set at note-on. The other unison slots receive osc1[0]'s state by
copy (7.6) every block. The note-on also sets `osc2[0].base = ftol((P[8516]*freq + P[8520])*2^32/SR + 0.5)`. This
**multiplies** the octave-valued Transpose by freq, which is a bug, but it is harmless: the renderer overwrites osc2's
base before osc2 is first rendered. Offsets, amplitudes, pwCur, rings, filters and so on are **not** reset at note-on,
only at voice reset. A new note on a voice that has not been reset therefore ramps its pitch offset and amplitude from
the previous note's values during the first block. A voice fresh from reset starts with offset 0, amp = target and pwCur
= previous.

### 11.2 Phase formulas
```
setPhase(P):    phase    = ftol((P[8808] + (rand()*f32(2^-14) - 1) * P[8812] * 0.5) * 2^32 + 0.5)   (low 32 bits)
setPwmPhase(P): pwmPhase = ftol((P[8820] + (rand()*f32(2^-14) - 1) * P[8824] * 0.5) * 2^32 + 0.5)
setPhase(null): phase = ((rand()<<15) + rand())*4 + (rand()>>13)      (full 32-bit random; the null-program
                case, which is never reached in normal use)
```
Osc phase P[8808], Osc phase rand P[8812], PWM phase P[8820] and PWM phase rand P[8824] are all fractions 0..1.
The random part is uniform in `phase ± rand/2`. The phase shifts **all** waveforms, so for pulse it shifts both saws.
The voice reset uses the same formulas (with P).

### 11.3 Glide (portamento) at note-on (taken if `N = ftol(P[8768]*SR*0.001 + 0.5) > 10` and prevVoice != null and
(voice not active, or prevVoice == this voice))
```
tgt = ftol(2^32*freq/SR + 0.5);  start = prev.osc1[0].base (1 if 0)
o = |ln(tgt/start)/P[9068]|          (octaves)
m = [1, o, 1/max(o,0.001), o+1/max(o,0.001), 1+o, 1+1/max(o,.001), 1+o+1/max(o,.001)][P[8772]]   // Glide mode
M = ftol(N*m + 0.5)
osc1[0].base = start; osc1[0].glideTo(tgt, M)
osc2[0].base = prev.osc2[0].base; osc2[0].glideTo(<buggy formula above>, M)   (re-targeted by the renderer)
noise.freq = prev.noise.freq; noise.glideTo(freq*Oct^(P[8536]/12), M)
+0x1c = 1/M;  +0x10 = prev's current pan frequency;  +0x18 = 0
```
The glide is linear in frequency (a constant increment step per sample). The osc glide ends up to one block early with
a jump (see 3.1).

---------------------------------------------------------------------------------------------------------------------
## 12. Random numbers
All randomness uses MSVCRT `rand()`: `state = state*214013 + 2531011; return (state>>16) & 0x7fff` (per thread; the
host thread's state, never seeded by the plugin). White noise consumes one call per sample (per voice with N amp > 0).
The resonant noise warm-up consumes `SR/2` calls. The other consumers are note-on (2 + 64 calls), voice reset
(16*(2+2) osc/PWM phase calls + 32 jitter calls), LFOs and random freq. Exact matching needs the same call order. A
re-implementation should use independent generators, but must keep the value mapping (`r*2^-14 - 1` in [-1,1),
`r*2^-15` in [0,1)).

---------------------------------------------------------------------------------------------------------------------
## 13. Verification (scripts in OM/work_osc; DLL renders via `render_tests.py`, 32-bit Python)
Test patch: Init with random amp/freq 0, osc/PWM phase rand 0, velocity sensitivity 0, filter off, attack min, sustain
0 dB, output gain 0 dB (P = 1.0000033). Comparison runs from sample 512 (after the attack). The error is max
|DLL - model*outGain|, where the signal RMS is 0.3-1.2.

| test | what | max error |
|---|---|---|
| tables.py | sine / saw set / triangle set / user set vs memory dumps | 0 / 2.4e-7 / 4.2e-7 / 6.0e-7 |
| saw440 at keys 0,20,45,69,100,120,127 | all table-selection regimes (T3 .. M256 with only h1 left) | <= 4.9e-7 |
| sine440, tri440, pulse440 (pw 30 %), user440 | waveforms | <= 8.3e-7 |
| cuser (keys 30, 69, 100, 118), cuser2 | custom 512-pt wave with strong Nyquist content loaded via chunk (P[32..]), user set in memory vs model (4.8e-7), T6-wave = exactly c256 (the Nyquist doubling), user->user osc1+osc2 | <= 1.0e-6 |
| pwm (pulse, 4 Hz, 80 %), upwm (user PWM, 2.4 Hz, -60 %) | PWM | 7.7e-7, 1.4e-6 |
| o2saw, o2mix | osc2 transpose (octaves) + detune Hz, mixed waves | <= 8.7e-7 |
| sync, syncpulse | hard sync with BLEP, saw and pulse slave | 4.4e-7, 7.6e-7 |
| fm (sine->sine, amp 0 dB), fmsaw (saw->saw +12 st, +5.1 dB) | FM with filtered modulator | 5.6e-7, 1.7e-4 (slow phase drift from ftol rounding of FM increments) |
| noisew, noiser5, noiser9 | white noise (exact rand sequence), resonant bandpass 50 %, 95 % + transpose | 3.6e-7, 1.1e-6, 8.8e-6 (gain 106) |
| uni3, uni4s, uni5j, uni2sync | unison mono, stereo spread, pitch+pan jitter, sync quirk | <= 3.0e-6; ratios & pan gains = memory dump |
| panfreq, panrand | freq->pan, random pan law | 1.6e-8 / 2.9e-7 (fitted gains = model) |
| vel1, vel2, oscat, oscatn, randamp, ap1 | vel^(2S), 1+S*vel, AT dB laws, random amp, afterpitch | gains exact to 1e-6; ap1 3.9e-7 |
| glide (legato, 100 ms) | osc1 glide + osc2 following, noise off | 5.3e-7 |
| phases | osc/PWM phase formulas and rand order (4 calls per unison slot) | exact |
| dnone/dpost/dpre/dglob | hard clip -18 dB, sustain -12 dB: every per-voice mode clips E*x (not x), so E is applied before the distortion | clip level exact |
| tnone/tpost/tpre | release tail with hard clip: `out = clip(E*x) * (E<1/16 ? 16E : 1)` (E measured from the no-dist render) | 9.3e-9 |

Models: `tables.py` (tables), `oscmodel.py` + `voicemodel.py` (plain/sync/FM oscillators), `noisemodel2.py` (noise),
`unimodel.py` (unison + pan), `glidemodel.py`, `phasecheck.py`. Runs: `python cmp_voice.py <test>`,
`python unimodel.py <test>` and so on.

---------------------------------------------------------------------------------------------------------------------
## 14. Sample-rate and block-size dependencies
* Increments are 2^32*f/SR. Table choice depends on f/SR, so the band-limiting scales with SR.
* The FM modulator filter coefficients are derived from SR, so the response in Hz is the same at every SR.
* The noise SVF uses `pi*f/SR` and runs 2x oversampled. The warm-up is SR/2 samples.
* The velocity-gain smoother uses 0.998 per sample, which is SR-dependent (tau = 500 samples).
* All parameter updates are per 64-sample block with linear ramps: osc amp, pitch offset (inc), pulse width, noise F/q/g,
  and pan gains. The PWM LFO, table selection and unison ratios are block-rate.

## 15. Quirks (keep them)
1. The saw is `1.5*sqrt(x) - 1` (curved). Pulse = difference of curved saws. Triangle = normalized integral of that pulse.
2. The saw/triangle tables below SR/512 are the naive curves (aliased). Above that they are Fourier-truncated naive
   512-sample tables.
3. The user-wave T0 doubles the 256th harmonic.
4. The FM modulator is band-passed (~150-550 Hz) and osc1 is silent in FM mode.
5. Hard sync/FM with unison: voices 1..U-1 are not detuned.
6. Odd-U centre voice: the pitch jitter is 1/1200 of the intended amount.
7. The pitch-offset slope truncation (`q+1` for negative q) and the offset ending short of its target.
8. AT mode "ignore" gives at = 1: negative Osc/N-aftertouch dB and any afterpitch apply in full.
9. The glide ends early by up to one block with a jump. osc2 follows osc1's glide one block ahead.
10. The noise frequency is taken from osc1's base (note + glide) at block start and ignores the osc-specific pitch
    modulation.
11. The unison pan order is swapped (voice 0 in the middle) and is not aligned with the detune order.
12. Dist modes 2/3 apply the amp envelope before distortion and filter. In dist modes 1-3 the tail below 1/16 of the
    envelope gets an extra 16*E fade.

## 16. Open questions / not covered here
* How each modulation source (mod envs, LFOs, XY, CC) is scaled into pitch1/2/N, amp1/2/N, pw, PWM rate/depth, pan,
  unison detune/spread (modulation spec). This spec only defines how the sums are consumed.
* The filter internals/doubling routing and the distortion transfer (their specs). The amp envelope `E` generator.
* The exact voice-manager rules for when a voice is reset versus reused (they decide whether noise warm-up and
  jitter re-randomization happen on a new note), and when `prevVoice` is passed to note-on.
* PW modulation arrives as a u32 phase offset. The conversion from the modulation depths is in the modulation code
  (not traced here).
