# Oatmeal global effects chain: Chorus -> Delay -> Reverb -> EQ -> output gain

Reverse-engineered from Oatmeal.dll (release 38-1). Every algorithm below was checked against DLL renders using
pure-Python models (scripts in `OM/work_fx/`). Delay, EQ, all chorus modes (including "irregular", with the CRT
`rand()` seeded from outside) and the reverb match the DLL **sample by sample**, with errors at float32 rounding level
(see section 8).

Notation: `f32(x)` means rounding to IEEE float. The DLL uses x87 code. Intermediates are held in 80-bit registers
(53-bit mantissa under the usual control word) and are rounded to float only when stored. All persistent state is
float32. `P.xxx` means the live program struct field (chunk offset given). The live struct sits at
`this + 0x1e3388 + chunkOffset`. The effect objects hold a pointer to chunk offset 16, so they read
`[prog + (chunkOffset-16)]`. `SR` is the integer sample rate (`this+0x1e5bfc`). `spb` is the double samples-per-beat
(`this+0x1e5c00`, = 60/tempo*SR). `n` is the host block length: the whole `processReplacing` call, not the
64-sample voice sub-block.

---------------------------------------------------------------------------------------------------------------------
## 0. Integration in the main process (0x10068040)

```
active = voices.render(...)                      // true if any voice produced output
if (active && distType != 0 && (distMode == 0 /*global*/ || distMode == 3 /*double*/)) globalDist(...)
if (P.chorusMode  (8616) != 0) active = chorus.process(mix, n, active)   // this+0x1e7010, 0x10002a60
if (P.delayOn     (8648) != 0) active = delay .process(mix, n, active)   // this+0x227144, 0x10004560
if (P.reverbOn    (8708) != 0) active = reverb.process(mix, n, active)   // this+0x227190, 0x1002ccb0
bool out = eq.process(mix, n, active)            // this+0x229300, 0x100061a0 -- ALWAYS called
if (out)  outL[i] = f32(mix[2i]*P.outGain(8776)), outR[i] = f32(mix[2i+1]*P.outGain)   (or += for accumulating process)
else      outputs are zero-filled (replacing) / left untouched (accumulating)
```
* `mix` is the interleaved stereo float buffer (`this+0x2293a8`), `mix[2i]` = L and `mix[2i+1]` = R.
* The "active" flag is threaded through the chain. When an effect is idle and receives `active=false`, it returns
  false **without touching the buffer**.
* **The EQ's return value gates the whole output.** When all EQ bands are off, the EQ returns its input flag, which
  is the reverb's (or delay's, chorus's, voices') flag. A false flag means the block is output as digital silence.
* Output gain p107: internal = `v<=0 ? 0 : 10^((90v-60)*0.05)` (linear). The multiply is the last step.
* Coefficients are **not** computed in setParameter, which only stores internal values. Every effect reads the
  program fields and recomputes all coefficients at the start of every process call (per host block). There is no
  parameter smoothing, except delay feedback-rotation (see 1.4).

### 0.1 Reset ("suspend" = vtable slot 21, 0x10047b80)
The reset is called on effMainsChanged(0) (suspend), setProgram, setChunk (patch/bank load), plugin construction,
and the GUI **Panic** button ("kills all notes and resets the effects"). It sends all-notes-off, resets the global
distortion, and then calls:
* chorus reset 0x10002810, delay reset 0x100044f0, reverb reset 0x1002ca00, and EQ reset 0x10006130 (details in each
  section).

Buffers are cleared, not freed. **Changing the program therefore kills all effect tails.**

### 0.2 Shared saturator table (used by delay and chorus feedback writes)
```
TANH[i] = f32(tanh((i*(1.0/2048) - 1.0) * 8.0)),  i = 0..4096        // static table at 0x100ef4f8
sat10(v):  u   = v * 0.1f                        // 0.1f = 0.100000001
           idx = (|u+8| - |u-8|) * 128 + 2048   // = 2048 + 256*clamp(u,-8,8), in [0,4096]
           i = (int)idx (trunc); f = idx - i
           return 10 * (TANH[i] + (TANH[i+1]-TANH[i]) * f)      // ~= 10*tanh(v/10), limited at +-10*tanh(8)
```
(At idx = 4096, TANH[4097] is read out of bounds but multiplied by f=0. Treat it as 0.)

### 0.3 One-pole filter coefficient used by delay and reverb (bilinear one-pole)
```
k(w)  = f32(0.5 * (sin w + cos w - 1) / cos w)     // = (1-p)/2 with p = (1-sin w)/cos w = (1-tan(w/2))/(1+tan(w/2))
lowpass : y = k*(x + x1) + (1-2k)*y1              // H = k(1+z^-1)/(1-p z^-1), prewarped cutoff w
highpass: kh = 1 - k(w);  y = kh*(x - x1) + (2kh-1)*y1   // H = (1+p)/2 (1-z^-1)/(1-p z^-1)
```

---------------------------------------------------------------------------------------------------------------------
## 1. Delay (0x10004560, object at this+0x227144)

### 1.1 Parameters (internal values; chunk offset; normalized->internal mapping from setParameter)
| p | name | chunk | internal | mapping |
|---|------|-------|----------|---------|
| 75 | on | 8648 | int 0/1 | (int)(v+0.5) |
| 76 | unit | 8652 | int 0..14 | (int)(v*14+0.5) |
| 77 | quantize | 8656 | int 0/1 | (int)(v+0.5) |
| 78/79 | reverse L/R | 8660/8664 | 0 normal, 1 reverse output, 2 reverse feedback | (int)(2v+0.5) |
| 80/81 | length L/R | 8676/8684 | units 1..100 | v*99+1 |
| 82/83 | feedback L/R | 8680/8688 | -2..2 | 4v-2 |
| 84 | input pan | 8668 | 0..1 | v |
| 85 | rotation | 8672 | rad | (2v-1)*pi_f |
| 86/87 | lowpass/highpass | 8692/8696 | 0..1 | v |
| 88/89 | dry/wet | 8700/8704 | linear | v<=0?0:10^((90v-60)/20) |

Unit (samples per unit, double):

| unit | name | samples |
|---|---|---|
| 0 | ms | SR*0.001 |
| 1 | 10 ms | SR*0.01 |
| 2 | sec | SR |
| 3 | 4/5 16ths | spb*0.2 |
| 4 | 2/3 16ths | spb/6 |
| 5 | 16ths | spb*0.25 |
| 6 | 4/5 8ths | spb*0.4 |
| 7 | 2/3 8ths | spb/3 |
| 8 | 8ths | spb*0.5 |
| 9 | 4/5 quarter notes | spb*0.8 |
| 10 | 2/3 quarter notes | spb*2/3 |
| 11 | quarter notes | spb |
| 12 | 4/5 half notes | spb*1.6 |
| 13 | 2/3 half notes | spb*4/3 |
| 14 | half notes | spb*2 |

Out-of-range unit values leave 1.0.

### 1.2 State (object offsets)
`+0` prog ptr, `+4` ptr to {int SR @+4, double spb @+8} (= this+0x1e5bf8), `+8 bufL*`, `+0xc bufR*`,
`+0x10 lenL`, `+0x14 lenR` (init -1), `+0x18 posL`, `+0x1c posR`,
`+0x20 lpxL, +0x24 lpyL, +0x28 lpxR, +0x2c lpyR, +0x30 hpxL, +0x34 hpyL, +0x38 hpxR, +0x3c hpyR` (floats),
`+0x40 idle` (byte, init 1), `+0x44 silentCount`, `+0x48 rotCur` (float, init 0).

Reset (0x100044f0): idle=1, silentCount=0, pos=0, all filter states=0, rotCur=0, both buffers zeroed (lengths
kept).

### 1.3 Static window table (reverse modes), 0x100ed440
```
W[i] = f32(1 - h^32),  h = (cos(i * pi_f * (1/512)) + 1) * 0.5,   i = 0..2047;   W[2048] = W[0]   (W[2049] = ln2, x0)
win(pos, inv): t = pos*inv;  x = (|t| - |t-1| + 1) * 1024  (= 2048 t for t in [0,1]);  j=(int)x; f=x-j
               return (1-f)*W[j] + f*W[j+1]
```
In closed form `win(t) = 1 - cos^64(2*pi*t)`. It is zero at t = 0, 1/2 and 1: at the wrap point and where the
reversed read head crosses the write head. `pi_f` = 3.14159274 (float pi).

### 1.4 Process
```
bool Delay::process(float* buf, int n, bool active) {
  if (idle && !active) return false;
  double unit = UNIT[P.unit];                       // table above
  double lL = P.lenL, lR = P.lenR;                  // float -> double
  if (P.quantize) { lL = floor(lL + 0.5); lR = floor(lR + 0.5); }   // lengths rounded to whole units
  int nL = (int)(lL*unit + 0.5), nR = (int)(lR*unit + 0.5);
  nL = clamp(nL, 2, 1323000); nR = clamp(nR, 2, 1323000);          // 1323000 = 30 s @ 44.1k, fixed sample count
  if (nL != lenL) { delete bufL; bufL = new float[nL] (zeroed); lenL = nL; posL = 0; }   // any length change
  if (nR != lenR) { ...same for R... }                               // => buffer CLEARED (echoes lost)
  // (return `active` if a buffer is missing or len<2 -- cannot happen after the clamps)

  // feedback matrix = rotation(rot) * diag(fbL, fbR), ramped linearly over the block if rot changed
  float target = P.rot;  bool ramp = (target != rotCur);
  float inc = ramp ? f32((target - rotCur)/n) : 0;
  r = ramp ? rotCur : target;
  a = f32(cos r * fbL);  b = f32(-sin r * fbR);  c = f32(sin r * fbL);  d = cos r * fbR  /*kept in FPU*/
  panR = f32(2*P.pan);  panL = f32(2 - panR);            // centre: both 1.0; hard left: L*2, R*0
  kl = k(wLP), wLP = (lp^3 * 10980 + 20) * pi_f * 2 / SR;   pl = f32(1 - 2kl)     // 20 Hz .. 11 kHz, cubic
  kh = f32(1 - k(wHP)), wHP = (hp^3 * 10980 + 20) * pi_f * 2 / SR;   ph = f32(2kh - 1)
  if (posL<0 || posL>=lenL) posL = 0;  (same R)
  invL = f32(1.0/(lenL-1)); invR = f32(1.0/(lenR-1));
  if (lenL == lenR) posR = posL;                    // equal lengths => channels forced in sync every block
  for i in 0..n-1:
    inL = buf[2i]; inR = buf[2i+1];
    rL = (revL==2) ? f32(win(posL,invL) * bufL[lenL-1-posL]) : bufL[posL];     // read BEFORE write
    rR = (revR==2) ?     win(posR,invR) * bufR[lenR-1-posR]  : bufR[posR];
    // lowpass then highpass, per channel ("+1e-15" = f32(1e-15) denormal guard)
    yL = f32(kl*(rL + lpxL) + pl*lpyL + 1e-15); lpxL = rL; lpyL = yL;
    hL = f32(kh*(yL - hpxL) + ph*hpyL + 1e-15); hpxL = yL; hpyL = hL;
    yR = f32(kl*(rR + lpxR) + pl*lpyR + 1e-15); lpxR = f32(rR); lpyR = yR;
    hR =     kh*(yR - hpxR) + ph*hpyR + 1e-15 ; hpxR = yR; hpyR = f32(hR);
    bufL[posL] = f32(sat10(inL*panL + b*hR + a*hL) + 1e-15);     // write at the same index => delay = lenL
    bufR[posR] = f32(sat10(inR*panR + d*hR + c*hL) + 1e-15);
    oL = (revL==1) ? f32(win(posL,invL) * bufL[lenL-1-posL]) : hL;   // reverse OUTPUT: read AFTER the write,
    oR = (revR==1) ?     win(posR,invR) * bufR[lenR-1-posR]  : hR;   //   UNFILTERED
    buf[2i]   = f32(oL*P.wet + inL*P.dry);
    buf[2i+1] = f32(oR*P.wet + inR*P.dry);
    if (++posL >= lenL) posL = 0;  if (++posR >= lenR) posR = 0;
    if (ramp) { rotCur = f32(inc + rotCur); recompute a,b,c,d from rotCur (fbL,fbR current) }
  rotCur = target;
  // tail logic
  if (any |buf[k]| > 1e-9 for k < 2n) { silentCount = 0; idle = false; return true; }
  silentCount += n;  if (silentCount >= lenL + lenR) idle = true;
  return false;
}
```
Semantics:
* Normal mode: echo = delayed signal -> LP -> HP. The same filtered signal goes to the output (x wet) and into the
  feedback, so the filters sit **inside the loop** and are applied again on every repeat.
* The feedback vector (hL, hR) is rotated by `rot` and scaled per source channel:
  `newL = inL*panL + fbL*cos(r)*hL - fbR*sin(r)*hR`, `newR = inR*panR + fbL*sin(r)*hL + fbR*cos(r)*hR`.
  The tanh saturator (`10*tanh(x/10)`) keeps |feedback| up to 2 bounded.
* Reverse feedback (2): the line is read mirrored (`buf[len-1-pos]`) and windowed. The result is filtered and used
  for both output and feedback.
* Reverse output (1): the feedback uses the normal read. The output is the mirrored, windowed read of the line after
  this sample's write, and it is **not** filtered.
* Delay resolution is whole samples (no interpolation). With lenL==lenR the two positions are kept identical.
* After a reset the first processed block ramps the rotation from 0 to the target.

---------------------------------------------------------------------------------------------------------------------
## 2. EQ (0x100061a0, object at this+0x229300), 5 cascaded biquads

### 2.1 Parameters
| p | name | chunk | internal | mapping |
|---|---|---|---|---|
| 218-222 | freq 1-5 | 9232+4k | Hz 15..20000 | v^3*19985 + 15 |
| 223-227 | amp 1-5 | 9252+4k | dB +-60 | (2v-1)*60 |
| 228-232 | slope 1-5 | 9272+4k | 1/16..16 | v>0.5: (v-0.5)*30+1; v<0.5: 1/((0.5-v)*30+1); v==0.5: 1 |
| 233-237 | type 1-5 | 9292+4k | 0 off, 1 peak/notch, 2 low shelf, 3 high shelf | (int)(3v+0.5) |

### 2.2 State
`+0` prog, `+4` SR ptr; band k (0..4): `+8+16k s1L, +0xc+16k s2L, +0x10+16k s1R, +0x14+16k s2R`;
`+0x58 dc` (float, init f32(1e-15) = 0x26901d7d); `+0x5c tailCount` (int, init -1).
Reset: dc = 1e-15, tailCount = -1, all states 0. A band that is switched off keeps its state (it is simply
skipped).

### 2.3 Coefficients: RBJ cookbook with "slope" = Q for all three types
Recomputed each block, for each band with type != 0 (float rounding shown where the DLL stores):
```
A     = f32(10^(amp * 0.025f))          // 10^(dB/40)
invA  = f32(1/A)
w     = pi_f * freq * 2 / SR;  w = min(w, f32(pi_f*0.98f))       // clamp at 0.98*pi
sn = f32(sin w);  cs = f32(cos w)
alpha = f32(sn / (2*slope))
beta  = f32(sqrt(A)/slope * sn)          // = 2*sqrt(A)*alpha  (shelves)
peak (1):  b0 = 1 + alpha*A;  b1 = -2cs;  b2 = 1 - alpha*A;  a0 = 1 + alpha/A;  a1 = -2cs;  a2 = 1 - alpha/A
lowshelf (2):
  b0 = A*((A+1) - (A-1)cs + beta);  b1 = 2A*((A-1) - (A+1)cs);  b2 = A*((A+1) - (A-1)cs - beta)
  a0 =    (A+1) + (A-1)cs + beta;   a1 = -2*((A-1) + (A+1)cs);  a2 =    (A+1) + (A-1)cs - beta
highshelf (3):
  b0 = A*((A+1) + (A-1)cs + beta);  b1 = -2A*((A-1) + (A+1)cs); b2 = A*((A+1) + (A-1)cs - beta)
  a0 =    (A+1) - (A-1)cs + beta;   a1 = 2*((A-1) - (A+1)cs);   a2 =    (A+1) - (A-1)cs - beta
inv = f32(1/a0);  B0=f32(b0*inv) B1=f32(b1*inv) B2=f32(b2*inv) A1=f32(-a1*inv) A2=f32(-a2*inv)
```
So for peaks the slope is Q (bandwidth ~ 1/Q). For shelves the slope is also used as a Q in the "Q form" of the
RBJ shelf, not as RBJ's shelf-slope S. Values above ~0.707 produce the overshoot/undershoot bump at the shelf edge
that the manual warns about.

### 2.4 Process
```
bool EQ::process(float* buf, int n, bool active) {
  if (!active && tailCount < 0) return false;          // buffer untouched
  tailCount -= n;
  if (all five types == 0) return active;              // pass-through, no processing
  dc = -dc;                                            // alternating +-1e-15 per block
  for band k in 0..4 with type != 0:                   // whole block per band (cascade)
    compute B0..A2
    for i in 0..n-1, ch in {L,R}:
      x = buf[2i+ch] + (ch==L ? dc : -dc)
      y = B0*x + s1                                    // transposed direct form II
      s1 = f32(A1*y + B1*x + s2)
      s2 = f32(A2*y + B2*x)
      buf[2i+ch] = f32(y)
  if (any |buf| > 1e-9) { tailCount = (int)(SR*0.05 + 0.5); return true; }   // keeps running 50 ms after input stops
  return false;
}
```

---------------------------------------------------------------------------------------------------------------------
## 3. Chorus (0x10002a60, object at this+0x1e7010)

### 3.1 Parameters
| p | name | chunk | internal | mapping |
|---|---|---|---|---|
| 67 | mode | 8616 | 0 off, 1 sine, 2 ramp, 3 FM, 4 irregular | (int)(4v+0.5) |
| 68 | stereo | 8620 | 0 mono, 1 stereo 1, 2 stereo 2 | (int)(2v+0.5) |
| 69 | voices | 8624 | 1..16 (clamped 1..16 in DSP) | (int)(15v+0.5)+1 |
| 70 | speed | 8628 | Hz | v^2*3.999 + 0.001 |
| 71 | delay (min) | 8632 | ms | v*99.9 + 0.1 |
| 72 | depth (range) | 8636 | ms | v*99.9 + 0.1 |
| 73 | feedback | 8644 | -1..1 | 2v-1 |
| 74 | mix | 8640 | wet fraction | v |

### 3.2 State
`+0` prog, `+4` SR ptr, `+8 bufL[32769]`, `+0x2000c bufR[32769]` (32768-sample circular lines plus a guard),
`+0x40010 wpos` (0..32767), `+0x40014 lastSpeed` (float; set to P.speed when the object is attached),
`+0x40018 idle` (byte), `+0x4001c tailCount`, `+0x40020 phase` (uint32 LFO phase),
irregular only: `+0x40024 dposL[16]`, `+0x40064 dposR[16]` (uint32 delay, 15.17 fixed point = samples*2^17),
`+0x400a4 velL[16]`, `+0x400e4 velR[16]` (int32, 2^-17 samples per sample),
`+0x40124 x1L, +0x40128 y1L, +0x4012c x1R, +0x40130 y1R` (DC blocker in the feedback path).

Reset (0x10002810): DC states 0, idle=1, tailCount=0, wpos=0, phase=0, both buffers zeroed. Then, with SR and the
current params:
```
minD = f32(SR*delay*0.001f) (<=32766);  maxD = min((depth+delay)*SR*0.001f, 32766);  range = f32(maxD-minD)
r    = f32(speed*8190/SR) (<=8190)
for k in 0..15:  dposL[k] = (int)(rand()*range/32768 + minD + 0.5) << 17
                 dposR[k] = (int)(rand()*range/32768 + minD + 0.5) << 17
                 velL[k]  = (int)((rand()-16384)*r*8 + 0.5)
                 velR[k]  = (int)((rand()-16384)*r*8 + 0.5)          // 64 rand() calls, in this order
```
`rand()` is MSVCRT's LCG (`x = x*214013+2531011; return (x>>16)&0x7fff`). It shares its global state with the
voices, so its exact values are not reproducible. Any uniform [0,32767] source will do.

### 3.3 Static LFO tables (float[32769], index = phase>>17)
```
x = i/32768, i = 0..32767;   s = sin(2*pi_f*x)
SINE[i] = f32((1 + s)/2)                                   // 0x1008d330
RAMP[i] = f32(sin((x + x^16) * pi_f/2))                     // 0x100cd368: slow rise 0->~1, fast fall at the end
FM[i]   = f32((1 + sin(2*pi_f*(x + 0.7f*s)))/2)            // 0x100ad360: phase-modulated sine
T[32768] = T[0]
```

### 3.4 Process
```
bool Chorus::process(float* buf, int n, bool active) {
  uint32 inc = (uint32)(int64)(P.speed/SR * 2^32 + 0.5);
  if (P.mode == 0) { phase += inc*n; return active; }
  if (idle) { if (!active) { phase += inc*n; return false; } }     // LFO keeps running while idle
  if (active) { tailCount = 0x8000; idle = false; }
  nv = clamp(P.voices,1,16);  mix = P.mix
  bufL[32768] = bufL[0]; bufR[32768] = bufR[0];     // guard (unused by the masked reads)
  norm = f32(1/sqrt(nv));  fb3 = f32(fb*fb*fb)      // feedback is CUBED
  minD = f32(SR*P.delay*0.001f)                      // samples
  if (mode != 4) regular() else irregular();
  tail: if (any |buf|>1e-9) { tailCount = 0x8000; idle=false; return true; }
        tailCount -= n; if (tailCount <= 0) idle = true; return false;
}
```
**Regular modes (sine/ramp/FM):**
```
minD = min(minD, 32766);  maxD = min((P.depth + P.delay)*SR*0.001f, 32766);  range = f32(maxD - minD)
T = ramp?RAMP : FM?FM : SINE
off(x) = (uint32)(int64)(2^32 * x * x + 0.5)          // NB: phase offset is quadratic in x (original quirk)
mono     : offL[v] = off(v/nv)
stereo 1 : offL[v] = off(v/(2nv)),   offR[v] = off((nv+v)/(2nv))
stereo 2 : offL[v] = off(2v/(2nv)),  offR[v] = off((2v+1)/(2nv))
tap(buf, o): ph = o + phase (uint32);  j = ph>>17;  f = (ph & 0x1ffff) * 2^-17
             lfo = T[j] + (T[j+1]-T[j])*f                      // 0..1
             pos = (wpos - minD) - lfo*range + 65536            // double
             ip = (int)pos; fr = pos - ip
             return (1-fr)*buf[ip & 0x7fff] + fr*buf[(ip+1) & 0x7fff]     // linear interpolation
per sample i:
  inL, inR
  mono:   acc = sum_v tap(bufL, offL[v])                                  (double sum)
          outL = f32((norm*acc - inL)*mix + inL);  outR = f32((norm*acc - inR)*mix + inR)
  stereo: aL = sum_v tap(bufL, offL[v]);  aR = sum_v tap(bufR, offR[v])
          outL = f32((norm*aL - inL)*mix + inL);   outR = f32((norm*aR - inR)*mix + inR)
  phase += inc;  wpos = (wpos+1) & 0x7fff (wraps at 32768)
  // feedback: DC blocker on the voice sum, then cubed feedback, saturator, write at the NEW wpos
  y = f32(0.999f*(acc - x1) + 0.998f*y1); y1 = y; x1 = f32(acc)       // 0.998f = f32(2*0.999f-1); per channel in stereo
  mono:   bufR[wpos] = f32(sat10(y*fb3*norm + (inL+inR)*0.5));  bufL[wpos] = bufR[wpos]
  stereo: bufL[wpos] = f32(sat10(yL*fb3*norm + inL));  bufR[wpos] = f32(sat10(yR*fb3*norm + inR))
```
The delay of a voice is `minD + lfo*range + 1` samples (+1 because the write goes to wpos+1). All voices share one
LFO phase and differ only by the quadratic offsets above. For example, stereo 1/2 with one voice puts R at +90
degrees. Output = `(1-mix)*dry + mix*sum/sqrt(nv)`. In mono mode the wet part is identical on L and R, so panning
survives only in the dry part.

**Irregular mode (4)** (random-walk delay times, 2 bounded integrators per voice):
```
minD = clamp(minD, 2, 32766); maxD = clamp((depth+delay)*SR*0.001f, 2, 32766)
minF = (int)(minD+0.5) << 17;  maxF = (int)(maxD+0.5) << 17        (uint32)
r = min(f32(speed*8190/SR), 8190)       // max slope in samples/sample (speed 1 Hz @44.1k -> 0.186 = 18.6% pitch dev.)
if (P.speed != lastSpeed) { lastSpeed = P.speed; for k<16: velL[k] = (int)((rand()-16384)*r*8+0.5); velR[k] = same }
phaseOld = phase;  wF = wpos << 17
step(k): d = dpos[k] + vel[k] (uint32);  dpos[k] = d
         if (d < minF)      { dpos[k] = minF; vel[k] =  (int)((rand()+1)*r*131072/32768 + 0.5) }   // bounce, speed in (0,r]
         else if (d > maxF) { dpos[k] = maxF; vel[k] = -(int)((rand()+1)*r*131072/32768 + 0.5) }
rd(buf, rp): rp uint32; fr = (rp & 0x1ffff)*2^-17; j = rp>>17; return (1-fr)*buf[j] + fr*buf[(j+1)&0x7fff]
per sample:
  aL = aR = 0 (float accumulators, f32 after each add)
  for v < nv: step(L,v); aL += rd(bufL, wF - dposL[v])
              stereo1: step(R,v); aR += rd(bufR, wF - dposR[v])
              stereo2: aR += rd(bufR, wF + dposL[v] - maxF - 1)     // R delay = maxD - dL (mirror about 0, not about
                                                                    //  the range centre: original quirk)
  outputs as in regular mode (mono uses aL for both channels)
  DC blockers as above; wpos++ (wrap 32768); wF += 1<<17
  mono:   bufR[wpos] = f32(sat10(y*fb3 + f32((inL+inR)*0.5)));  bufL[wpos] = bufR[wpos]    // NB no *norm here
  stereo: bufL[wpos] = f32(sat10(yL*fb3*norm + inL)); bufR[wpos] = f32(sat10(yR*fb3*norm + inR))
  phase += inc
after the block: if (phaseOld > phase)   // LFO phase wrapped (once per 1/speed s): new random velocities
  for k<16: velL[k] = (int)((rand()-16384)*r*8+0.5); velR[k] = (int)((rand()-16384)*r*8+0.5)
```
Each voice's delay moves linearly at a random velocity, bounces off minD and maxD with a new random speed, and gets
new random velocities every 1/speed seconds. `(int)` is `_ftol`, which truncates toward zero, so the `+0.5` is not
a symmetric round for negative values.

---------------------------------------------------------------------------------------------------------------------
## 4. Reverb (0x1002ccb0, object at this+0x227190): 8-line feedback delay network

### 4.1 Parameters
| p | name | chunk | internal | mapping |
|---|---|---|---|---|
| 90 | on | 8708 | int | (int)(v+0.5) |
| 91 | size | 8712 | **ms** 10..250 | v^3*240 + 10 |
| 92 | length | 8716 | T60 s | v==1 ? 120 ("ETERNITY") : v^2*29.9 + 0.1 ; >=30 => infinite |
| 93 | dullness | 8720 | 0..1 | v |
| 94 | brightness | 8724 | 0..1 | v |
| 95/96 | dry/wet | 8728/8732 | linear | v<=0?0:10^((90v-60)/20) |
| 97/98/99 | "1","2","3" | 8736/8740/8744 | rad | (2v-1)*pi_f |
| 100 | rotation | 8748 | rad | (2v-1)*pi_f |
| 101 | predelay | 8752 | ms +-500 | (2v-1)*500 |
| 102 | early mix | 8756 | 0..1 | v |

### 4.2 State
`+8 dc` (float, reset to f32(1e-12) = 0x2b8cbccc, sign flipped every processed block);
line j = 0..7: LP `lpx = +0x0c+8j, lpy = +0x10+8j`; HP `hpx = +0x4c+8j, hpy = +0x50+8j`;
allpass `apx = +0x8c+12j, apy = +0x90+12j, apc (coef) = +0x94+12j`;
ER buffers `+0xec erL[1024]`, `+0x10ec erR[1024]`, `+0x20ec erPos`;
predelay buffers `+0x20f0 pdL*`, `+0x20f4 pdR*`, `+0x215c pdSize`, `+0x2160 pdW`, `+0x2164 pdR`;
line buffers `+0x20f8.. +0x2114` (8 ptrs), lengths `len[0..3] @+0x2118`, `pos[0..3] @+0x2128`,
`len[4..7] @+0x2138`, `pos[4..7] @+0x2148`; `+0x2158 lastSize` (float, constructor -1.0);
`+0x2168 idle` (byte), `+0x216c silentCount`.

Reset (0x1002ca00): dc = 1e-12, **idle = 0** (so it runs right after a reset), silentCount = 0, all positions (lines,
ER, predelay) = 0, all LP/HP/allpass states = 0, ER, line and predelay buffers zeroed. lastSize is not reset.

### 4.3 Topology
```
 in L --(1-e)--+--> aL --> [A0] ; ER taps L (8, from erL) --e--^
 in R --(1-e)--+--> aR --> [B2] ; ER taps R (8, from erR) --e--^
 8 delay lines (integer lengths) -> LP(dull) -> HP(bright) -> h_j
     h_j -> first-order allpass (fractional part of the line length) -> ap_j -> wetL = sum ap_0..3, wetR = sum ap_4..7
     h_j * g_j (decay) -> u_j -> 4x4 orthogonal matrix M (angles R1,R2,R3) per group -> rotation (angle `rot`)
     between the groups -> line inputs
```
Lines 0-3 form group A (they feed the left output). Lines 4-7 form group B (they feed the right output).
Delay-line lengths (samples):
```
sizeS = f32(SR * size * 0.001f)
mult  = {1.03, 0.92, 0.73, 0.638,  1.0689, 0.883, 0.747, 0.677}  (float)
Lj = sizeS*mult[j];  len[j] = max((int)Lj, 2);  fr = Lj - (int)Lj;  fr = clamp(fr, 0.1, 1.1)
apc[j] = f32((1-fr)/(1+fr))            // Thiran allpass for the fractional part (output taps only)
```
Lines are reallocated and zeroed (positions set to 0) only when `|sizeS - lastSize| > 0.1`. Filter states survive
the reallocation. At the default size 30 ms and 44.1k: len = {1362,1217,965,844, 1414,1168,988,895}.

Decay: `T60 >= 30` gives `g_j = 1` (infinite). Otherwise `inv = f32(1/(f32(SR)*T60))` and
`g_j = f32(10^(-3*len[j]*inv))`, i.e. -60 dB per T60 per pass, from the **integer** length. M and the rotation are
orthogonal (checked numerically: `F^T F = I` to 1e-7), so the decay is set only by the g_j and the filters.
Measured on the DLL (dull=1, bright=0): nominal 0.5/1.2/3.0 s gave 0.47/1.19/3.06 s (size 30/30/100 ms).

Filters (both per line, inside the loop):
```
wd = (dull*16980f + 20) * pi_f * 2 / f32(SR)   (LINEAR 20..17000 Hz), clamp <= f32(pi_f*0.99f);  kLP = k(wd); pLP = 1 - 2kLP (kept double)
wb = (bright^3*10980f + 20) * pi_f * 2 / f32(SR) (cubic 20..11000 Hz), clamp same;  kHP = f32(1 - k(wb)); pHP = f32(2kHP - 1)
```
Matrix M (from R1,R2,R3; `s1=f32(sin R1)`, `c1=cos R1`, `s2=sin R2`, `c2=f32(cos R2)`, `s3=sin R3`, `c3=f32(cos R3)`;
every element stored as float, and so is each named temporary):
```
M00 = c2*c1*c1          M01 = -c2*c1*s1                M02 = -s2*c1       M03 = s1
t2c = c3*s1 - s3*s2*c1
M10 = t2c*c2 - c2*s2*c1*s1
M11 = (s2*s1*s1 + (c3*c1 + s3*s2*s1))*c2
t24 = s3*c2
M12 = s2*s2*s1 - t24*c2  M13 = s2*c1
t48 = -(t2c*s2) - c2*c2*c1*s1 ;  u2c = c3*s2 ;  t4c = s3*s1 + u2c*c1
t1c = c2*c2*s1*s1 - (c3*c1 + s3*s2*s1)*s2 ;  v2c = (s3 + s1)*c2*s2
M20 = t4c*c3 + t48*s3    M21 = c3*(s3*c1 - u2c*s1) + t1c*s3    M22 = c3*c3*c2 + v2c*s3    M23 = t24*c1
M30 = t48*c3 - t4c*s3    M31 = t1c*c3 - (s3*c1 - u2c*s1)*s3    M32 = (v2c - t24)*c3       M33 = c3*c2*c1
```
(All angles 0 give M = I. The matrix is orthogonal for any angles. It is not a product of <=4 plane rotations
in any order I tried, so implement the formulas as written.)

Early-reflection taps (samples; the table is picked by SR):

| SR range | tapL[0..7] | tapR[0..7] |
|---|---|---|
| SR < 46050 | 7,79,103,137,241,349,379,421 | 17,29,67,151,179,229,277,307 |
| < 68100 | 8,86,112,149,262,380,413,458 | 19,32,73,164,195,249,301,334 |
| < 92100 | 14,158,206,274,482,698,758,842 | 34,58,132,302,358,458,554,614 |
| >= 92100 | 15,172,224,298,525,760,825,916 | 37,63,146,329,390,499,603,668 |

Tap gains:
```
gL = {0.48482826, -0.35969245, -0.3163195, 0.25308281, -0.50701547, -0.3154127, 0.14677593, -0.30555025}
gR = {0.060517289, -0.24290182, -0.34840450, -0.42788872, 0.074636072, -0.40043476, 0.51584524, 0.44815964}
```

### 4.4 Process
```
bool Reverb::process(float* buf, int n, bool active) {
  if (!active && idle) return false;
  sizeS = ...; dc = -dc; (realloc lines if needed, see above)
  pdSize = (int)(SR*0.5 + 4.5); (re)alloc+zero pdL/pdR and pdW=pdR=0 if pdSize changed
  d = (int)(|P.predelay| * SR * 0.001 + 0.5);  pdW = (pdR + d) wrapped into [0,pdSize)    // re-derived every block
  wetDelay = P.predelay > 0.1f;  dryDelay = P.predelay < -0.1f
  g[], kLP,pLP,kHP,pHP, M, c = f32(cos rot), s = f32(sin rot), taps by SR, e = P.early, ome = f32(1-e)
  for i in 0..n-1:
    xL = buf[2i] + dc;  xR = f32(dc + buf[2i+1])
    aL = ome*xL + e*sum_k gL[k]*erL[(erPos - tapL[k]) & 1023]
    aR = ome*xR + e*sum_k gR[k]*erR[(erPos - tapR[k]) & 1023]
    erL[erPos] = f32(xL); erR[erPos] = xR; erPos = (erPos+1) & 1023
    for j in 0..7:
      r = line[j][pos[j]]                                    // delay = len[j] (read before write, same index)
      y = f32((r + lpx[j] + dc)*kLP + pLP*lpy[j]); lpy[j] = y; lpx[j] = r
      h =     (y + dc - hpx[j])*kHP + pHP*hpy[j];  hpx[j] = y; hpy[j] = f32(h)
      ap[j] = f32((h + dc - apy[j])*apc[j] + apx[j]); apy[j] = ap[j]; apx[j] = f32(h)
      u[j] = h * g[j]
    // group A: A = M^T * uA (columns), group B: B = M * uB (rows), permuted as follows
    A0 = aL + M02 u0 + M12 u1 + M22 u2 + M32 u3        A1 = M03 u0 + M13 u1 + M23 u2 + M33 u3
    A2 =      M00 u0 + M10 u1 + M20 u2 + M30 u3        A3 = M01 u0 + M11 u1 + M21 u2 + M31 u3
    B0 =      M30 u4 + M31 u5 + M32 u6 + M33 u7        B1 = M00 u4 + M01 u5 + M02 u6 + M03 u7
    B2 = aR + M10 u4 + M11 u5 + M12 u6 + M13 u7        B3 = M20 u4 + M21 u5 + M22 u6 + M23 u7
      (each A0,A1,A2,B0,B1,B2 partial sum is stored as float; A3 and B3 stay double until the final use;
       +1e-15 is added to the first term of A1,A2,A3,B0,B1,B3 -- negligible)
    line[0][pos0] = f32(c*A0 - s*B1 + 1e-15)     line[4][pos4] = f32(s*A3 + c*B0 + 1e-15)
    line[1][pos1] = f32(c*A1 + s*B2 - 1e-15)     line[5][pos5] = f32(c*B1 + s*A0 + 1e-15)
    line[2][pos2] = f32(s*B3 + c*A2 - 1e-15)     line[6][pos6] = f32(c*B2 - s*A1 - 1e-15)
    line[3][pos3] = f32(c*A3 - s*B0 - 1e-15)     line[7][pos7] = f32(c*B3 - s*A2 - 1e-15)
    wL = f32(ap0+ap1+ap2+ap3);  wR = f32(ap4+ap5+ap6+ap7);  dL = xL; dR = xR
    if (wetDelay)      { pdL[pdW] = wL; pdR[pdW] = wR; wL = pdL[pdR]; wR = pdR[pdR]; }
    else if (dryDelay) { pdL[pdW] = f32(xL); pdR[pdW] = xR; dL = pdL[pdR]; dR = pdR[pdR]; }
    if (wetDelay||dryDelay) { pdW = (pdW+1)%pdSize; pdR = (pdR+1)%pdSize; }   // positions frozen when |pd|<=0.1 ms
    buf[2i] = f32(wL*P.wet + dL*P.dry);  buf[2i+1] = f32(wR*P.wet + dR*P.dry)
    all pos[j]++ wrap at len[j]
  if (active || any |buf| > 1e-8) { silentCount = 0; idle = false; return true; }
  silentCount += n;  if (silentCount >= |P.predelay|*SR*0.001f + 4*len[4]) idle = true;
  return false;
}
```
Notes:
* The wet output has no direct path. It is the sum of the 4 lines of each group, taken after the filters and the
  fractional allpass. The input enters line 0 (x cos rot) and line 5 (x sin rot) for L, and line 6 (x cos rot) and
  line 1 (x sin rot) for R. With `rot = 0` and M = I, L and R are completely separate (lines 0<->2, 1<->3 and cycle
  4->5->6->7->4).
* "Early" is a crossfade of the **FDN input** between the raw signal and an 8-tap sparse FIR (<= 421 samples at 44.1k).
  It is not an output tap, so it only diffuses and softens the attack.
* The fractional-delay allpass is only on the output taps. The loop delays are integers.
* The dry path (with `dc` added) is delayed instead when predelay < -0.1 ms.

---------------------------------------------------------------------------------------------------------------------
## 5. Sample-rate dependencies (summary)
* Delay: unit-to-samples conversion uses SR/spb. The max length is a fixed 1323000 samples (30 s at 44.1k,
  ~13.8 s at 96k). Filter cutoffs are true Hz via w = 2*pi*f/SR.
* EQ: w = 2*pi*f/SR clamped to 0.98*pi. The tail hold is 50 ms.
* Chorus: the line is a fixed 32768 samples, so min and max delay are clamped to 32766 samples (0.74 s at 44.1k,
  0.17 s at 192k). The LFO increment and the irregular max slope (speed*8190/SR) are in real time. The tail counter
  is a fixed 32768 samples.
* Reverb: line lengths scale with SR and the predelay buffer is SR/2+4. ER taps use 4 bracketed tables (not
  scaled continuously). The ER buffer is 1024 samples. The tail threshold is 4*len[4] samples plus the predelay.

## 6. Quirks to keep (they are part of the sound)
1. Chorus phase offsets are quadratic in the voice fraction, `2^32*(v/(2nv))^2`, not linear.
2. Chorus feedback is cubed (`fb^3`), passes through a DC blocker (0.999/0.998) and a 10*tanh(x/10) saturator, and
   is scaled by 1/sqrt(nv). Irregular mono omits the 1/sqrt(nv).
3. Chorus stereo 2 irregular: the R delay is `maxD - dL` (can go down to ~1 sample), not `minD + maxD - dL`.
4. Delay: any length change (including tempo changes in note units) reallocates and clears the line. Equal L/R
   lengths force the R position onto the L position every block.
5. Delay reverse-output mode: the output is not filtered (the filters are only in the feedback path of that channel).
6. Delay feedback of up to +-2 is kept stable by the saturator (echoes grow up to ~+-10 and then compress).
7. EQ shelves use slope as Q (resonant shelves above 0.707).
8. Reverb dullness is linear in Hz while brightness and the delay filters are cubic. Reverb allpasses are on the
   output only.
9. The EQ return value decides whether the block is output at all. The effects' 1e-9/1e-8 silence thresholds
   therefore truncate tails to digital silence.

## 7. Where things are computed
All coefficients are computed inside the effect process functions, once per host block (see 0). The static tables
(tanh table 0x10007230, chorus LFO tables 0x100026f0, reverse window 0x10004410) are built at plugin construction
(calls at 0x10047543..0x1004754d). setParameter (0x10048260) only maps normalized values to the internal
values listed in the tables above. The effects read the live program struct directly.

## 8. Verification (scripts in OM/work_fx/)
Method: render a deterministic dry signal (saw or sine notes, all voice randomisation off, output gain patched to
exactly 1.0 through the chunk) with all effects off. Then render the same MIDI with one effect enabled; exact
internal parameter values are written through the chunk (`fxh.set_fields`). Finally run the Python model on the
dry signal and compare.

| effect | configs | result |
|---|---|---|
| Delay (`r_delay.py`, `m_delay.py`) | A: ms units, rot 0.4, fb 0.7/-0.5, pan 0.3, LP/HP. B: reverse output L + reverse feedback R. C: tempo unit + quantize + rot pi/2, fb 0.9/1.2 | max abs error 0, 2e-19, 6e-10 (bit-exact up to extended-precision residue) |
| EQ (`r_eq.py`, `m_eq.py`) | A: peak/low shelf/high shelf/notch mix. B: extreme (22 kHz clamp, Q=16, -60 dB, +30 dB Q=10) | A: 0 (bit-exact). B: 1.4e-5 relative (float rounding at extreme Q) |
| Chorus regular (`r_chorus.py`, `m_chorus.py`) | sine stereo1 4v; ramp mono 3v fb -0.7; FM stereo2 16v fb 0.9; sine mono fb -1 | relative error <= 1.8e-9, and the LFO phase matches after 1 s |
| Chorus irregular (`r_chorus_irr.py`, `m_chorus_irr.py`) | state snapshot plus `msvcrt.srand(4242)`, 16000 samples, mono / stereo1 / stereo2, 5 voices, 3 Hz, fb 0.95 | bit-exact, including the number of rand() calls consumed |
| Reverb (`r_reverb.py`, `m_reverb.py`) | A: defaults (30 ms, 1.2 s). B: 100 ms, 5 s, predelay +50 ms, early 0.9. C: 250 ms, infinite, predelay -30 ms | relative error <= 6.5e-8. Line lengths and allpass coefficients equal the DLL's |
| Reverb T60 (`t4_decay.py`) | energy decay fit on DLL renders | 0.5 -> 0.47 s, 1.2 -> 1.19 s, 3.0 -> 3.06 s (size 100 ms), 3.46 s (size 250 ms, coarse fit) |

`x87sym.py` is a small symbolic x87 interpreter that I used to derive the reverb matrix and loop expressions
(`python work_fx/x87sym.py <start> <end> esi=R edi=P -q`).

## 9. Open questions / not covered
* The Panic button handler itself was not traced. The manual says it resets the effects, and the reset-all
  function (vtable slot 21) does that.
* `rand()` is the shared MSVCRT generator. The irregular chorus random sequence depends on everything else that calls
  `rand()` (voices), so it cannot be reproduced bit-exactly. A private LCG is fine.
* Only 44.1 kHz was verified numerically. The SR-dependent branches (ER table selection, clamps) were read from the
  code but not rendered.
* Denormal-guard constants (+-1e-15, +-1e-12 alternating dc) are specified but inaudible. They can be dropped.
