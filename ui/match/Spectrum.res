// The sound matcher's measurements: short-time spectra at three resolutions, each summed into
// mel-spaced bands, and a 10 ms loudness envelope. The target sample and every candidate
// patch's render are measured the same way, and MatchLoss.res compares them. Everything is at
// 44.1 kHz (SoundTarget.res resamples the sample).

@get_index external get32: (Float32Array.t, int) => float = ""
@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""
@get_index external getInt: (Int32Array.t, int) => int = ""
@set_index external setInt: (Int32Array.t, int, int) => unit = ""

let sampleRate = 44100.
let twoPi = 2. * Math.Constants.pi

// the envelope's step: 10 ms
let envelopeStep = 441

let mel = hz => 2595. * Math.log10(1. + hz / 700.)
let hzOfMel = m => 700. * (Math.pow(10., ~exp=m / 2595.) - 1.)

// One resolution: a Hann-windowed FFT of `size` every `hop` samples, its power summed into
// `bands` triangular mel bands (each band's weights add up to 1, so a band's level is an
// average bin's and bands of every width compare).
type resolution = {
  size: int,
  hop: int,
  bands: int,
  window: Float64Array.t,
  twCos: Float64Array.t,
  twSin: Float64Array.t,
  // bit-reversed positions, where each windowed sample goes before the butterflies
  rev: Int32Array.t,
  re: Float64Array.t,
  im: Float64Array.t,
  // each bin's power in the two frames of the last transform
  powerA: Float64Array.t,
  powerB: Float64Array.t,
  // band b sums bins first[b] .. last[b], with weights from weights[offset[b]]
  first: Int32Array.t,
  last: Int32Array.t,
  offset: Int32Array.t,
  weights: Float64Array.t,
  // each band's centre in Hz
  centres: Float64Array.t,
  // the cepstrum kept (coefficients 1 .. cepstra of the bands' DCT: the shape of the spectrum
  // without its fine detail), and its cosines, coefficient-major
  cepstra: int,
  cosines: Float64Array.t,
}

let makeResolution = (~size, ~hop, ~bands, ~lowest) => {
  let bits = Float.toInt(Math.round(Math.log2(Int.toFloat(size))))
  let rev = Int32Array.fromLength(size)
  for i in 0 to size - 1 {
    let r = ref(0)
    for b in 0 to bits - 1 {
      if ((i >> b) &&& 1) != 0 {
        r := r.contents ||| (1 << (bits - 1 - b))
      }
    }
    rev->setInt(i, r.contents)
  }
  let half = size / 2
  let twCos = Float64Array.fromLength(half)
  let twSin = Float64Array.fromLength(half)
  for k in 0 to half - 1 {
    let a = twoPi * Int.toFloat(k) / Int.toFloat(size)
    twCos->set64(k, Math.cos(a))
    twSin->set64(k, Math.sin(a))
  }
  let window = Float64Array.fromLength(size)
  for i in 0 to size - 1 {
    window->set64(i, 0.5 - 0.5 * Math.cos(twoPi * Int.toFloat(i) / Int.toFloat(size)))
  }

  let binHz = sampleRate / Int.toFloat(size)
  let (lo, hi) = (mel(lowest), mel(16000.))
  let edge = i => hzOfMel(lo + (hi - lo) * Int.toFloat(i) / Int.toFloat(bands + 1))
  let first = Int32Array.fromLength(bands)
  let last = Int32Array.fromLength(bands)
  let offset = Int32Array.fromLength(bands)
  let centres = Float64Array.fromLength(bands)
  let cepstra = Math.Int.min(20, Float.toInt(Math.round(Int.toFloat(bands) / 2.5)))
  let cosines = Float64Array.fromLength(cepstra * bands)
  for k in 1 to cepstra {
    for b in 0 to bands - 1 {
      cosines->set64(
        (k - 1) * bands + b,
        Math.cos(Math.Constants.pi * Int.toFloat(k) * (Int.toFloat(b) + 0.5) / Int.toFloat(bands)),
      )
    }
  }
  let weights = []
  for b in 0 to bands - 1 {
    let (f0, f1, f2) = (edge(b), edge(b + 1), edge(b + 2))
    let a = Math.Int.max(1, Float.toInt(Math.ceil(f0 / binHz)))
    let z = Math.Int.min(half, Float.toInt(Math.floor(f2 / binHz)))
    let tri = k => {
      let f = Int.toFloat(k) * binHz
      Math.max(0., f < f1 ? (f - f0) / (f1 - f0) : (f2 - f) / (f2 - f1))
    }
    let ws = z >= a ? Array.fromInitializer(~length=z - a + 1, i => tri(a + i)) : []
    let sum = ws->Array.reduce(0., (s, w) => s + w)
    // a band narrower than a bin takes the bin nearest its centre
    let (a, ws, sum) = if sum > 0. {
      (a, ws, sum)
    } else {
      let k = Math.Int.max(1, Math.Int.min(half, Float.toInt(Math.round(f1 / binHz))))
      (k, [1.], 1.)
    }
    first->setInt(b, a)
    last->setInt(b, a + Array.length(ws) - 1)
    offset->setInt(b, Array.length(weights))
    centres->set64(b, f1)
    ws->Array.forEach(w => weights->Array.push(w / sum))
  }
  {
    size,
    hop,
    bands,
    window,
    twCos,
    twSin,
    rev,
    re: Float64Array.fromLength(size),
    im: Float64Array.fromLength(size),
    powerA: Float64Array.fromLength(half + 1),
    powerB: Float64Array.fromLength(half + 1),
    first,
    last,
    offset,
    weights: Float64Array.fromArray(weights),
    centres,
    cepstra,
    cosines,
  }
}

// long windows for the tone, shorter ones for how it moves (the 10 ms envelope has the
// attack: windows much shorter than these measure the waveform's phase more than its tone)
let resolutions = [
  makeResolution(~size=2048, ~hop=1024, ~bands=48, ~lowest=30.),
  makeResolution(~size=1024, ~hop=512, ~bands=40, ~lowest=50.),
  makeResolution(~size=512, ~hop=256, ~bands=32, ~lowest=80.),
]

// the frames a signal of n samples has: the first centred on sample 0
let frameCount = (r, n) => n / r.hop + 1

// How many frames of a resolution are pooled into one: enough that together they span three
// periods of the sound's pitch (a window shorter than that measures where in the cycle it
// falls, which a hair of detuning changes, rather than the tone).
let poolFor = (r, ~period) =>
  switch period {
  | Some(p) =>
    Math.Int.max(1, Math.Int.min(16, Float.toInt(Math.ceil((3. * p - Int.toFloat(r.size)) / Int.toFloat(r.hop))) + 1))
  | None => 1
  }

// The spectra of the frames centred on samples `a` and `b` (zero outside the signal) at once,
// one as the real part and one as the imaginary part of a complex FFT; then each bin's power
// in each frame, in r.powerA and r.powerB: with Z the transform and W = Z[size - k],
// A = (Z + conj W) / 2 and B = (Z - conj W) / 2j.
let transform = (r, x: Float32Array.t, a, b) => {
  let (re, im, size) = (r.re, r.im, r.size)
  let n = TypedArray.length(x)
  let (startA, startB) = (a - size / 2, b - size / 2)
  for i in 0 to size - 1 {
    let k = r.rev->getInt(i)
    let w = r.window->get64(i)
    let ja = startA + i
    let jb = startB + i
    re->set64(k, ja >= 0 && ja < n ? x->get32(ja) * w : 0.)
    im->set64(k, jb >= 0 && jb < n ? x->get32(jb) * w : 0.)
  }
  let (twCos, twSin) = (r.twCos, r.twSin)
  let len = ref(2)
  while len.contents <= size {
    let l = len.contents
    let h = l / 2
    let step = size / l
    let i = ref(0)
    while i.contents < size {
      let base = i.contents
      for k in 0 to h - 1 {
        let wr = twCos->get64(k * step)
        let wi = -.(twSin->get64(k * step))
        let a = base + k
        let b = a + h
        let br = re->get64(b)
        let bi = im->get64(b)
        let xr = br * wr - bi * wi
        let xi = br * wi + bi * wr
        let ar = re->get64(a)
        let ai = im->get64(a)
        re->set64(b, ar - xr)
        im->set64(b, ai - xi)
        re->set64(a, ar + xr)
        im->set64(a, ai + xi)
      }
      i := base + l
    }
    len := l * 2
  }
  let (pa, pb) = (r.powerA, r.powerB)
  for k in 0 to size / 2 {
    let k2 = (size - k) &&& (size - 1)
    let (zr, zi, wr, wi) = (re->get64(k), im->get64(k), re->get64(k2), im->get64(k2))
    pa->set64(k, ((zr + wr) * (zr + wr) + (zi - wi) * (zi - wi)) * 0.25)
    pb->set64(k, ((zi + wi) * (zi + wi) + (zr - wr) * (zr - wr)) * 0.25)
  }
}

// Band levels (magnitudes) with `pool` frames at a time pooled (their powers averaged):
// pooled frames × bands, frame-major.
let bandLevels = (r, x: Float32Array.t, ~pool) => {
  let frames = frameCount(r, TypedArray.length(x))
  let groups = (frames + pool - 1) / pool
  let power = Float64Array.fromLength(groups * r.bands)
  let (first, last, offset, weights) = (r.first, r.last, r.offset, r.weights)
  let add = (t, bins: Float64Array.t) => {
    let row = t / pool * r.bands
    for b in 0 to r.bands - 1 {
      let p = ref(0.)
      let o = offset->getInt(b) - first->getInt(b)
      for k in first->getInt(b) to last->getInt(b) {
        p := p.contents + weights->get64(o + k) * bins->get64(k)
      }
      power->set64(row + b, power->get64(row + b) + p.contents)
    }
  }
  let t = ref(0)
  while t.contents < frames {
    let pair = t.contents + 1 < frames
    // without a second frame, the imaginary part is a frame wholly outside the signal
    transform(r, x, t.contents * r.hop, pair ? (t.contents + 1) * r.hop : -2 * r.size)
    add(t.contents, r.powerA)
    if pair {
      add(t.contents + 1, r.powerB)
    }
    t := t.contents + 2
  }
  for g in 0 to groups - 1 {
    let n = Int.toFloat(Math.Int.min(pool, frames - g * pool))
    for b in 0 to r.bands - 1 {
      power->set64(g * r.bands + b, Math.sqrt(power->get64(g * r.bands + b) / n))
    }
  }
  power
}

// RMS of every 10 ms step.
let envelope = (x: Float32Array.t) => {
  let n = TypedArray.length(x)
  let steps = (n + envelopeStep - 1) / envelopeStep
  let out = Float64Array.fromLength(steps)
  for s in 0 to steps - 1 {
    let a = s * envelopeStep
    let z = Math.Int.min(n, a + envelopeStep)
    let sum = ref(0.)
    for i in a to z - 1 {
      sum := sum.contents + x->get32(i) * x->get32(i)
    }
    out->set64(s, Math.sqrt(sum.contents / Int.toFloat(Math.Int.max(1, z - a))))
  }
  out
}

type features = {
  length: int,
  energy: float,
  // per resolution: band levels, pooled frames × bands, and how many frames each pools
  spectra: array<Float64Array.t>,
  pools: array<int>,
  envelope: Float64Array.t,
}

// `period` is the target's pitch period in samples, which sets the pooling (the same for the
// target and every candidate).
let measure = (x: Float32Array.t, ~period): features => {
  let energy = ref(0.)
  x->TypedArray.forEach(v => energy := energy.contents + v * v)
  let pools = resolutions->Array.map(poolFor(_, ~period))
  {
    length: TypedArray.length(x),
    energy: energy.contents,
    spectra: resolutions->Array.mapWithIndex((r, i) => bandLevels(r, x, ~pool=pools->Array.getUnsafe(i))),
    pools,
    envelope: envelope(x),
  }
}

let db = x => 20. * Math.log10(Math.max(x, 1e-9))

// The long resolution's bands averaged over the frames (power), in dB: the tone's colour.
let averageSpectrum = (f: features, ~gain=1.) => {
  let r = resolutions->Array.getUnsafe(0)
  let levels = f.spectra->Array.getUnsafe(0)
  let frames = TypedArray.length(levels) / r.bands
  Array.fromInitializer(~length=r.bands, b => {
    let p = ref(0.)
    for t in 0 to frames - 1 {
      let v = levels->get64(t * r.bands + b)
      p := p.contents + v * v
    }
    db(gain * Math.sqrt(p.contents / Int.toFloat(Math.Int.max(1, frames))))
  })
}

// The envelope in `points` steps (the loudest 10 ms step in each), in dB.
let envelopeOverview = (f: features, ~points, ~gain=1.) => {
  let n = TypedArray.length(f.envelope)
  Array.fromInitializer(~length=points, i => {
    let a = i * n / points
    let z = Math.Int.max(a + 1, (i + 1) * n / points)
    let m = ref(0.)
    for s in a to Math.Int.min(n, z) - 1 {
      m := Math.max(m.contents, f.envelope->get64(s))
    }
    db(gain * m.contents)
  })
}
