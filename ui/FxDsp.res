// What the effects do, for the FX page's graphs: the delay's echoes, the reverb's network run
// on an impulse, the chorus voices' delay times and the distortion's curves. Each follows
// dsp/Effects.cmajor and dsp/Filter.cmajor (docs/internals/effects.md), in internal values.

let pi = Math.Constants.pi
let clamp = (x: float, lo, hi) => Math.max(lo, Math.min(hi, x))
let sq = (x: float) => x * x
// a gain in dB, down to -180
let db = (x: float) => x <= 1e-9 ? -180. : 20. * Math.log10(x)

// A deterministic scatter: 0..1 for each k and seed.
let hash = (k: float, seed: float) => {
  let x = Math.sin(k * 12.9898 + seed * 78.233) * 43758.5453
  x - Math.floor(x)
}

//==============================================================================
// The one-pole filters of the delay and reverb loops (bilinear, prewarped)

let bilinearK = (w: float) => 0.5 * (Math.sin(w) + Math.cos(w) - 1.) / Math.cos(w)

// The magnitude of the lowpass (or highpass) with this cutoff, at f, at sample rate sr.
let onePole = (~highpass, cutoff: float, f: float, sr: float) => {
  let w = Math.min(cutoff * 2. * pi / sr, pi * 0.99)
  let k = bilinearK(w)
  let p = 1. - 2. * k
  let theta = 2. * pi * f / sr
  // |1 ± e^-jθ| / |1 - p e^-jθ|
  let (c, s) = (Math.cos(theta), Math.sin(theta))
  let den = Math.sqrt(sq(1. - p * c) + sq(p * s))
  if highpass {
    let kh = 1. - k
    kh * Math.sqrt(sq(1. - c) + sq(s)) / den
  } else {
    k * Math.sqrt(sq(1. + c) + sq(s)) / den
  }
}

// The loop's two filters at f.
let loopGain = (~lp: float, ~hp: float, f: float) => {
  let sr = 48000.
  onePole(~highpass=false, lp, f, sr) * onePole(~highpass=true, hp, f, sr)
}

// What one pass through the loop leaves of a broadband sound: the RMS of the response over
// 50 Hz..10 kHz with every octave weighted alike (pink noise).
let broadbandGain = (~lp, ~hp) => {
  let n = 24
  let sum = ref(0.)
  for i in 0 to n - 1 {
    let f = 50. * Math.pow(200., ~exp=(Int.toFloat(i) + 0.5) / Int.toFloat(n))
    sum := sum.contents + sq(loopGain(~lp, ~hp, f))
  }
  Math.sqrt(sum.contents / Int.toFloat(n))
}

//==============================================================================
// Delay

// cutoffs: 20 Hz .. 11 kHz, cubic
let delayCutoff = (v: float) => v * v * v * 10980. + 20.
let delayCutoffValue = (hz: float) => Math.cbrt(clamp((hz - 20.) / 10980., 0., 1.))

// A unit's length: in milliseconds for the first three, in beats (quarter notes) for the others.
type unitLength = Ms(float) | Beats(float)
let unitLength = unit =>
  switch unit {
  | 0 => Ms(1.)
  | 1 => Ms(10.)
  | 2 => Ms(1000.)
  | 3 => Beats(0.2)
  | 4 => Beats(1. /. 6.)
  | 5 => Beats(0.25)
  | 6 => Beats(0.4)
  | 7 => Beats(1. /. 3.)
  | 8 => Beats(0.5)
  | 9 => Beats(0.8)
  | 10 => Beats(2. /. 3.)
  | 11 => Beats(1.)
  | 12 => Beats(1.6)
  | 13 => Beats(4. /. 3.)
  | _ => Beats(2.)
  }

let sat10 = (v: float) => 10. * Math.tanh(v / 10.)

type delaySettings = {
  lengthL: float, // units, as heard (rounded when quantized)
  lengthR: float,
  feedbackL: float,
  feedbackR: float,
  rotation: float,
  inputPan: float,
  lp: float, // Hz
  hp: float,
  wet: float,
  reverseL: int,
  reverseR: int,
}

// side: 0 left, 1 right; passes: how many times it has been through the loop's filters
// (reversed output skips them)
type echo = {time: float, side: int, amp: float, passes: int}

// The echoes of an impulse into both inputs: when each comes out of either side, how loud, and
// through the filters how often. Each pass through a line takes its length and goes through the
// loop's filters, here as their broadband gain; the feedback then rotates between the sides and
// saturates.
let echoes = (s: delaySettings, ~until: float) => {
  let g = broadbandGain(~lp=s.lp, ~hp=s.hp)
  let (c, si) = (Math.cos(s.rotation), Math.sin(s.rotation))
  let (a, b, cc, d) = (c * s.feedbackL, -.si * s.feedbackR, si * s.feedbackL, c * s.feedbackR)
  // what each line holds by the time it comes out, and the passes of its loudest part
  let pending: Map.t<float, (float, float, int, int)> = Map.make()
  let key = t => Math.round(t * 1e6) / 1e6
  let add = (t, l, r, passes) =>
    if t <= until {
      let k = key(t)
      let (pl, pr, nl, nr) = pending->Map.get(k)->Option.getOr((0., 0., passes, passes))
      pending->Map.set(
        k,
        (pl + l, pr + r, Math.abs(l) > Math.abs(pl) ? passes : nl, Math.abs(r) > Math.abs(pr) ? passes : nr),
      )
    }
  let panR = 2. * s.inputPan
  add(s.lengthL, 2. - panR, 0., 0)
  add(s.lengthR, 0., panR, 0)
  let out = []
  let rec step = count =>
    if count < 600 && pending->Map.size > 0 {
      let t = pending->Map.keys->Iterator.toArray->Math.minMany
      let (l, r, passesL, passesR) = pending->Map.get(t)->Option.getOr((0., 0., 0, 0))
      pending->Map.delete(t)->ignore
      // reversed output is read straight from the line, without the filters
      let (hl, hr) = (l * g, r * g)
      if l != 0. {
        let reversed = s.reverseL == 1
        out->Array.push({time: t, side: 0, amp: (reversed ? l : hl) * s.wet, passes: reversed ? passesL : passesL + 1})
      }
      if r != 0. {
        let reversed = s.reverseR == 1
        out->Array.push({time: t, side: 1, amp: (reversed ? r : hr) * s.wet, passes: reversed ? passesR : passesR + 1})
      }
      let nl = sat10(a * hl + b * hr)
      let nr = sat10(cc * hl + d * hr)
      if Math.abs(nl) > 2e-3 {
        add(t + s.lengthL, nl, 0., Math.abs(a * hl) >= Math.abs(b * hr) ? passesL + 1 : passesR + 1)
      }
      if Math.abs(nr) > 2e-3 {
        add(t + s.lengthR, 0., nr, Math.abs(d * hr) >= Math.abs(cc * hl) ? passesR + 1 : passesL + 1)
      }
      step(count + 1)
    }
  step(0)
  out
}

//==============================================================================
// Reverb

// the loop's lowpass is linear in Hz (20 Hz .. 17 kHz), its highpass cubic (20 Hz .. 11 kHz)
let reverbLowpass = (dullness: float) => dullness * 16980. + 20.
let reverbLowpassValue = (hz: float) => clamp((hz - 20.) / 16980., 0., 1.)
let reverbHighpass = delayCutoff
let reverbHighpassValue = delayCutoffValue

let infinite = 30.

type reverbSettings = {
  size: float, // ms
  length: float, // T60 in seconds (30 and up: infinite)
  dullness: float,
  brightness: float,
  angles: (float, float, float),
  rotation: float,
  earlyMix: float,
}

let lineScale = [1.03, 0.92, 0.73, 0.638, 1.0689, 0.883, 0.747, 0.677]
let erGainL = [0.48482826, -0.35969245, -0.3163195, 0.25308281, -0.50701547, -0.3154127, 0.14677593, -0.30555025]
let erGainR = [0.060517289, -0.24290182, -0.34840450, -0.42788872, 0.074636072, -0.40043476, 0.51584524, 0.44815964]
// early reflection taps at 44.1 kHz, in samples
let erTapsL = [7., 79., 103., 137., 241., 349., 379., 421.]
let erTapsR = [17., 29., 67., 151., 179., 229., 277., 307.]

// The 4x4 orthogonal matrix of each group of four lines, from the three angles.
let mixMatrix = ((r1, r2, r3)) => {
  let (s1, c1) = (Math.sin(r1), Math.cos(r1))
  let (s2, c2) = (Math.sin(r2), Math.cos(r2))
  let (s3, c3) = (Math.sin(r3), Math.cos(r3))
  let t2c = c3 * s1 - s3 * s2 * c1
  let t24 = s3 * c2
  let t48 = -.(t2c * s2) - c2 * c2 * c1 * s1
  let u2c = c3 * s2
  let t4c = s3 * s1 + u2c * c1
  let t1c = c2 * c2 * s1 * s1 - (c3 * c1 + s3 * s2 * s1) * s2
  let v2c = (s3 + s1) * c2 * s2
  [
    [c2 * c1 * c1, -.c2 * c1 * s1, -.s2 * c1, s1],
    [t2c * c2 - c2 * s2 * c1 * s1, (s2 * s1 * s1 + (c3 * c1 + s3 * s2 * s1)) * c2, s2 * s2 * s1 - t24 * c2, s2 * c1],
    [t4c * c3 + t48 * s3, c3 * (s3 * c1 - u2c * s1) + t1c * s3, c3 * c3 * c2 + v2c * s3, t24 * c1],
    [t48 * c3 - t4c * s3, t1c * c3 - (s3 * c1 - u2c * s1) * s3, (v2c - t24) * c3, c3 * c2 * c1],
  ]
}

// The wet output for an impulse into both inputs, at sample rate sr for `seconds`: the 8-line
// network of the patch, without the predelay (left, right).
let reverbImpulse = (s: reverbSettings, ~sr: float, ~seconds: float) => {
  let n = Math.Int.max(1, Float.toInt(sr * seconds))
  let outL = Float32Array.fromLength(n)
  let outR = Float32Array.fromLength(n)
  let sizeS = sr * s.size * 0.001
  let len = lineScale->Array.map(m => Math.Int.max(2, Float.toInt(sizeS * m)))
  let apc = lineScale->Array.mapWithIndex((m, j) => {
    let l = sizeS * m
    let fr = clamp(l - Int.toFloat(len->Array.getUnsafe(j)), 0.1, 1.1)
    (1. - fr) / (1. + fr)
  })
  let lines = len->Array.map(l => Float32Array.fromLength(l))
  let pos = Array.make(~length=8, 0)
  let g =
    len->Array.map(l => s.length >= infinite ? 1. : Math.pow(10., ~exp=-3. * Int.toFloat(l) / (sr * s.length)))
  let kLP = bilinearK(Math.min(reverbLowpass(s.dullness) * 2. * pi / sr, pi * 0.99))
  let pLP = 1. - 2. * kLP
  let kHP = 1. - bilinearK(Math.min(reverbHighpass(s.brightness) * 2. * pi / sr, pi * 0.99))
  let pHP = 2. * kHP - 1.
  let (lpx, lpy, hpx, hpy, apx, apy) = (
    Array.make(~length=8, 0.),
    Array.make(~length=8, 0.),
    Array.make(~length=8, 0.),
    Array.make(~length=8, 0.),
    Array.make(~length=8, 0.),
    Array.make(~length=8, 0.),
  )
  let m = mixMatrix(s.angles)
  let mm = (i, j) => m->Array.getUnsafe(i)->Array.getUnsafe(j)
  let (c, si) = (Math.cos(s.rotation), Math.sin(s.rotation))
  let e = s.earlyMix
  let erScale = sr / 44100.
  let tapsL = erTapsL->Array.map(t => Float.toInt(Math.round(t * erScale)))
  let tapsR = erTapsR->Array.map(t => Float.toInt(Math.round(t * erScale)))
  let lastTap = Math.Int.maxMany(Array.concat(tapsL, tapsR))
  let ap = Array.make(~length=8, 0.)
  let u = Array.make(~length=8, 0.)
  // the early reflections' taps on the impulse, at sample i
  let er = (taps, gains, i) =>
    i > lastTap ? 0. : taps->Array.reduceWithIndex(0., (acc, t, k) => t == i ? acc + gains->Array.getUnsafe(k) : acc)
  let uu = Array.getUnsafe(u, ...)
  let apu = Array.getUnsafe(ap, ...)
  let write = (j, v) => lines->Array.getUnsafe(j)->ByteView.setUnsafe(pos->Array.getUnsafe(j), v)
  for i in 0 to n - 1 {
    let x = i == 0 ? 1. : 0.
    let aL = (1. - e) * x + e * er(tapsL, erGainL, i)
    let aR = (1. - e) * x + e * er(tapsR, erGainR, i)
    for j in 0 to 7 {
      let line = lines->Array.getUnsafe(j)
      let r = line->ByteView.getUnsafe(pos->Array.getUnsafe(j))
      let y = (r + lpx->Array.getUnsafe(j)) * kLP + pLP * lpy->Array.getUnsafe(j)
      lpy->Array.setUnsafe(j, y)
      lpx->Array.setUnsafe(j, r)
      let h = (y - hpx->Array.getUnsafe(j)) * kHP + pHP * hpy->Array.getUnsafe(j)
      hpx->Array.setUnsafe(j, y)
      hpy->Array.setUnsafe(j, h)
      let a = (h - apy->Array.getUnsafe(j)) * apc->Array.getUnsafe(j) + apx->Array.getUnsafe(j)
      apy->Array.setUnsafe(j, a)
      apx->Array.setUnsafe(j, h)
      ap->Array.setUnsafe(j, a)
      u->Array.setUnsafe(j, h * g->Array.getUnsafe(j))
    }
    let a0 = aL + mm(0, 2) * uu(0) + mm(1, 2) * uu(1) + mm(2, 2) * uu(2) + mm(3, 2) * uu(3)
    let a1 = mm(0, 3) * uu(0) + mm(1, 3) * uu(1) + mm(2, 3) * uu(2) + mm(3, 3) * uu(3)
    let a2 = mm(0, 0) * uu(0) + mm(1, 0) * uu(1) + mm(2, 0) * uu(2) + mm(3, 0) * uu(3)
    let a3 = mm(0, 1) * uu(0) + mm(1, 1) * uu(1) + mm(2, 1) * uu(2) + mm(3, 1) * uu(3)
    let b0 = mm(3, 0) * uu(4) + mm(3, 1) * uu(5) + mm(3, 2) * uu(6) + mm(3, 3) * uu(7)
    let b1 = mm(0, 0) * uu(4) + mm(0, 1) * uu(5) + mm(0, 2) * uu(6) + mm(0, 3) * uu(7)
    let b2 = aR + mm(1, 0) * uu(4) + mm(1, 1) * uu(5) + mm(1, 2) * uu(6) + mm(1, 3) * uu(7)
    let b3 = mm(2, 0) * uu(4) + mm(2, 1) * uu(5) + mm(2, 2) * uu(6) + mm(2, 3) * uu(7)
    write(0, c * a0 - si * b1)
    write(1, c * a1 + si * b2)
    write(2, si * b3 + c * a2)
    write(3, c * a3 - si * b0)
    write(4, si * a3 + c * b0)
    write(5, c * b1 + si * a0)
    write(6, c * b2 - si * a1)
    write(7, c * b3 - si * a2)
    outL->ByteView.setUnsafe(i, apu(0) + apu(1) + apu(2) + apu(3))
    outR->ByteView.setUnsafe(i, apu(4) + apu(5) + apu(6) + apu(7))
    for j in 0 to 7 {
      let next = pos->Array.getUnsafe(j) + 1
      pos->Array.setUnsafe(j, next >= len->Array.getUnsafe(j) ? 0 : next)
    }
  }
  (outL, outR)
}

//==============================================================================
// Chorus

let chorusLfo = (mode, x: float) =>
  switch mode {
  | 2 => Math.sin((x + Math.pow(x, ~exp=16.)) * pi * 0.5)
  | 3 =>
    let s = Math.sin(2. * pi * x)
    (1. + Math.sin(2. * pi * (x + 0.7 * s))) * 0.5
  | _ => (1. + Math.sin(2. * pi * x)) * 0.5
  }

// Each voice's LFO phase offset (a fraction of a cycle) on the left and the right; quadratic
// in the voice's place, as in the original.
let chorusOffsets = (~stereo, ~voices) => {
  let nv = Int.toFloat(voices)
  Array.fromInitializer(~length=voices, v => {
    let v = Int.toFloat(v)
    switch stereo {
    | 1 => (sq(v / (2. * nv)), sq((nv + v) / (2. * nv)))
    | 2 => (sq(2. * v / (2. * nv)), sq((2. * v + 1.) / (2. * nv)))
    | _ => (sq(v / nv), sq(v / nv))
    }
  })
}

// A deterministic stand-in for the irregular mode's random walk: the delay moves at a random
// speed, bounces off both ends, and gets new speeds every period. t and the result in periods
// and 0..1 of the range.
let chorusWalk = (seed: float, t: float) => {
  let random = hash(_, seed)
  let pos = ref(random(0.5))
  let cycles = Float.toInt(Math.floor(t))
  let steps = 24
  for cycle in 0 to cycles {
    let speed = ref((random(Int.toFloat(cycle) + 1.) - 0.5) * 6.)
    let until = cycle == cycles ? t - Int.toFloat(cycle) : 1.
    let dt = 1. / Int.toFloat(steps)
    let tt = ref(0.)
    while tt.contents < until {
      let step = Math.min(dt, until - tt.contents)
      pos := pos.contents + speed.contents * step
      if pos.contents > 1. {
        pos := 2. - pos.contents
        speed := -.Math.abs(speed.contents)
      } else if pos.contents < 0. {
        pos := -.pos.contents
        speed := Math.abs(speed.contents)
      }
      tt := tt.contents + step
    }
  }
  clamp(pos.contents, 0., 1.)
}

//==============================================================================
// Distortion

// A custom shape (PorridgeParams.shaperSpecs) at v in -1..1: its points (input, output, bend
// of the segment ending there), as the DSP renders it.
let customShape = (points: array<(float, float, float)>, v: float) => {
  let x = clamp(v, -1., 1.)
  let n = Array.length(points)
  let k = ref(1)
  while k.contents < n - 1 && points->Array.getUnsafe(k.contents)->(((px, _, _)) => px) < x {
    k := k.contents + 1
  }
  switch (points[k.contents - 1], points[k.contents]) {
  | (Some((x0, y0, _)), Some((x1, y1, bend))) =>
    let t = x1 > x0 ? clamp((x - x0) / (x1 - x0), 0., 1.) : 1.
    let s = bend == 0. ? t : Math.pow(t, ~exp=Math.pow(8., ~exp=bend))
    y0 + (y1 - y0) * s
  | _ => x
  }
}

// The shaper, at its input v (types 1 hard clip, 2 soft clip, 3 sine, 4 asymmetric, 5 custom).
let shape = (~custom=[], kind, v: float) =>
  switch kind {
  | 5 => customShape(custom, v)
  | 1 => clamp(v, -1., 1.)
  | 2 => Math.tanh(clamp(v, -8., 8.))
  | 3 => Math.sin(2. * pi * v)
  | 4 =>
    let v = clamp(v, -2., 14.)
    2. * Math.pow(2., ~exp=-.Math.exp(-.v / Math.log(2.))) - 1.
  | _ => v
  }

// The oversampling filters' gain (44.1 kHz set): the shaper sees the input this much louder,
// and the output comes out this much louder again.
let oversampleGain = os =>
  switch os {
  | 1 => 0.949
  | 2 => 0.804
  | 3 => 1.481
  | _ => 1.
  }

// The distortion of input x: drive, shaper, output gain, and the mix with the dry input (for
// Oatmeal's types and the custom shape: the models keep state, see AirwindowsSim).
let distort = (~kind, ~oversample, ~pregain: float, ~limit: float, ~postgain: float, ~mix=1., ~custom=[], x: float) => {
  let pre = Math.pow(10., ~exp=(pregain - limit) / 20.)
  let post = Math.pow(10., ~exp=(limit + postgain) / 20.)
  let os = oversampleGain(oversample)
  kind == 0 ? x : mix * os * shape(~custom, kind, x * pre * os) * post + (1. - mix) * x
}
