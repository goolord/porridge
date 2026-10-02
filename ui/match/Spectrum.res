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
  // The butterflies, two stages at a time (radix 2²: each element is read and written once
  // for both), after a single stage of 2 when there is an odd number of them.
  let (twCos, twSin) = (r.twCos, r.twSin)
  let m = ref(1)
  if mod(Float.toInt(Math.round(Math.log2(Int.toFloat(size)))), 2) == 1 {
    let i = ref(0)
    while i.contents < size {
      let (a, b) = (i.contents, i.contents + 1)
      let (ar, ai, br, bi) = (re->get64(a), im->get64(a), re->get64(b), im->get64(b))
      re->set64(a, ar + br)
      im->set64(a, ai + bi)
      re->set64(b, ar - br)
      im->set64(b, ai - bi)
      i := i.contents + 2
    }
    m := 2
  }
  while 4 * m.contents <= size {
    let q = m.contents
    let block = 4 * q
    // W(4q)^k is the table's entry k * step
    let step = size / block
    let base = ref(0)
    while base.contents < size {
      for k in 0 to q - 1 {
        let i0 = base.contents + k
        let (i1, i2, i3) = (i0 + q, i0 + 2 * q, i0 + 3 * q)
        // the first stage's twiddle, W(4q)^2k, on x1 and x3
        let (w1r, w1i) = (twCos->get64(2 * k * step), -.(twSin->get64(2 * k * step)))
        let (x1r, x1i, x3r, x3i) = (re->get64(i1), im->get64(i1), re->get64(i3), im->get64(i3))
        let (t1r, t1i) = (x1r * w1r - x1i * w1i, x1r * w1i + x1i * w1r)
        let (t3r, t3i) = (x3r * w1r - x3i * w1i, x3r * w1i + x3i * w1r)
        let (x0r, x0i, x2r, x2i) = (re->get64(i0), im->get64(i0), re->get64(i2), im->get64(i2))
        let (a0r, a0i, a1r, a1i) = (x0r + t1r, x0i + t1i, x0r - t1r, x0i - t1i)
        let (a2r, a2i, a3r, a3i) = (x2r + t3r, x2i + t3i, x2r - t3r, x2i - t3i)
        // the second's, W(4q)^k on a2, and -j W(4q)^k on a3
        let (w2r, w2i) = (twCos->get64(k * step), -.(twSin->get64(k * step)))
        let (u2r, u2i) = (a2r * w2r - a2i * w2i, a2r * w2i + a2i * w2r)
        let (u3r, u3i) = (a3r * w2r - a3i * w2i, a3r * w2i + a3i * w2r)
        re->set64(i0, a0r + u2r)
        im->set64(i0, a0i + u2i)
        re->set64(i2, a0r - u2r)
        im->set64(i2, a0i - u2i)
        re->set64(i1, a1r + u3i)
        im->set64(i1, a1i - u3r)
        re->set64(i3, a1r - u3i)
        im->set64(i3, a1i + u3r)
      }
      base := base.contents + block
    }
    m := block
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

//==============================================================================
// The harmonic grid: for a sound whose pitch is known, how loud what lies between its
// harmonics is against the harmonics themselves, in each of `gridBands` octave-wide bands,
// frame by frame. A plain oscillator has next to nothing between its harmonics; noise,
// detuned unison, vibrato or a rough recording fill the gaps, which the mel bands above a
// kilohertz or so (wider than the harmonics' spacing) can't tell from more harmonic level.
//
// Each frame is a Blackman window (its leakage is under -58 dB from 3 bins on) of at least
// gridPeriods periods, so that a harmonic's lobe stays well inside its own neighbourhood; the
// bins within a bin of a harmonic are "on", those at least 0.3 of the pitch from every
// harmonic "off", and the ratio is of the off bins' median power to the on bins' mean: the
// floor between the harmonics, which noise raises and partials of their own there (a second
// series, modulation's sidebands) don't; where those sit, the fine spectrum hears.
//
// The same frames give the fine spectrum: the power at every sixteenth of a harmonic of the
// target's pitch (`axisHz`, for the target and every candidate alike), up to the 24th or 16 kHz.
// Where its partials sit, a hair sharp or flat, and whether what lies between them hugs them
// (a wavering pitch) or fills the gaps evenly (noise): the mel bands are tens of cents wide
// above a few hundred hertz and see none of it. The frames' size follows axisHz, so that a
// candidate's frames are the target's.

let gridPeriods = 16.
let gridEdges = [400., 800., 1600., 3200., 6400., 12800.]
let gridBands = Array.length(gridEdges) - 1
// a band with nothing between its harmonics reads this (the window's leakage is about -60)
let gridFloor = -60.

type grid = {
  frames: int,
  // samples between frames
  hop: int,
  // frames × bands, dB: off against on (NaN where a band has no bins of either)
  ratio: Float64Array.t,
  // frames × bands, dB: the band's whole level (for weighing it)
  level: Float64Array.t,
  // each harmonic's mean power over the frames, up to 8 kHz (the key EQ's fit weighs a band's
  // harmonics by them)
  harmonics: Float64Array.t,
  // frames × fineCells: the power at cell c's frequency, (c + 1) / 16 of axisHz
  fine: Float64Array.t,
  fineCells: int,
}

let fineSteps = 16.

let gridResolutions: Map.t<int, resolution> = Map.make()

let gridResolution = size =>
  switch gridResolutions->Map.get(size) {
  | Some(r) => r
  | None =>
    let r = makeResolution(~size, ~hop=size / 2, ~bands=1, ~lowest=30.)
    for i in 0 to size - 1 {
      let t = twoPi * Int.toFloat(i) / Int.toFloat(size)
      r.window->set64(i, 0.42 - 0.5 * Math.cos(t) + 0.08 * Math.cos(2. * t))
    }
    gridResolutions->Map.set(size, r)
    r
  }

// None when the pitch is too low for a window of the longest size to hold its periods
let measureGrid = (x: Float32Array.t, ~hz, ~axisHz=?) =>
  if hz < 30. || hz > 4000. {
    None
  } else {
    let axisHz = axisHz->Option.getOr(hz)
    let want = gridPeriods * sampleRate / axisHz
    let size = ref(2048)
    while Int.toFloat(size.contents) < want && size.contents < 32768 {
      size := size.contents * 2
    }
    let r = gridResolution(size.contents)
    let half = r.size / 2
    let binHz = sampleRate / Int.toFloat(r.size)
    // each bin's band (or -1) and whether it is on (1) or off (2) the harmonics (or neither)
    let band = Int32Array.fromLength(half + 1)
    let kind = Int32Array.fromLength(half + 1)
    for k in 0 to half {
      let f = Int.toFloat(k) * binHz
      let b = ref(-1)
      for j in 0 to gridBands - 1 {
        if f >= gridEdges->Array.getUnsafe(j) && f < gridEdges->Array.getUnsafe(j + 1) {
          b := j
        }
      }
      band->setInt(k, b.contents)
      let m = Math.max(1., Math.round(f / hz))
      let d = Math.abs(f - m * hz)
      kind->setInt(k, d <= binHz ? 1 : d >= 0.3 * hz && d >= 3. * binHz ? 2 : 0)
    }
    let n = TypedArray.length(x)
    let frames = n / r.hop + 1
    let ratio = Float64Array.fromLength(frames * gridBands)
    let level = Float64Array.fromLength(frames * gridBands)
    let sums = Float64Array.fromLength(4 * gridBands)
    // each band's off bins, and room to sort their powers
    let offBins = Array.fromInitializer(~length=gridBands, b => {
      let bins = []
      for k in 0 to half {
        if band->getInt(k) == b && kind->getInt(k) == 2 {
          bins->Array.push(k)
        }
      }
      Int32Array.fromArray(bins)
    })
    let scratch = Float64Array.fromLength(half + 1)
    let offMedian = (bins: Float64Array.t, b) => {
      let ks = offBins->Array.getUnsafe(b)
      let n = TypedArray.length(ks)
      for i in 0 to n - 1 {
        scratch->set64(i, bins->get64(ks->getInt(i)))
      }
      let sorted = scratch->TypedArray.subarray(~start=0, ~end=n)
      sorted->TypedArray.sort((a, b) => a < b ? -1. : a > b ? 1. : 0.)
      sorted->get64(n / 2)
    }
    let count = Math.Int.max(1, Math.Int.min(256, Float.toInt(8000. / hz)))
    let harmonics = Float64Array.fromLength(count)
    let fineCells = Math.Int.max(1, Float.toInt(Math.min(24., 16000. / axisHz) * fineSteps) - 1)
    let fine = Float64Array.fromLength(frames * fineCells)
    let gather = (t, bins: Float64Array.t) => {
      for c in 0 to fineCells - 1 {
        let at = (Int.toFloat(c + 1) / fineSteps) * axisHz / binHz
        let k = Math.Int.min(half - 1, Float.toInt(Math.floor(at)))
        let u = at - Int.toFloat(k)
        fine->set64(t * fineCells + c, (1. - u) * bins->get64(k) + u * bins->get64(k + 1))
      }
      for k in 0 to half {
        if kind->getInt(k) == 1 {
          let m = Float.toInt(Math.round(Int.toFloat(k) * binHz / hz))
          if m >= 1 && m <= count {
            harmonics->set64(m - 1, harmonics->get64(m - 1) + bins->get64(k) / Int.toFloat(frames))
          }
        }
      }
      sums->TypedArray.fillAll(0.)->ignore
      for k in 0 to half {
        let b = band->getInt(k)
        let c = kind->getInt(k)
        if b >= 0 && c > 0 {
          let o = 4 * b + 2 * (c - 1)
          sums->set64(o, sums->get64(o) + bins->get64(k))
          sums->set64(o + 1, sums->get64(o + 1) + 1.)
        }
      }
      for b in 0 to gridBands - 1 {
        let (on, onCount, off, offCount) = (sums->get64(4 * b), sums->get64(4 * b + 1), sums->get64(4 * b + 2), sums->get64(4 * b + 3))
        ratio->set64(
          t * gridBands + b,
          onCount > 0. && offCount > 0.
            ? Math.max(gridFloor, 10. * Math.log10(Math.max(offMedian(bins, b), 1e-30) / Math.max(on / onCount, 1e-30)))
            : Float.Constants.nan,
        )
        level->set64(t * gridBands + b, 10. * Math.log10(Math.max(on + off, 1e-30)))
      }
    }
    let t = ref(0)
    while t.contents < frames {
      let pair = t.contents + 1 < frames
      transform(r, x, t.contents * r.hop, pair ? (t.contents + 1) * r.hop : -2 * r.size)
      gather(t.contents, r.powerA)
      if pair {
        gather(t.contents + 1, r.powerB)
      }
      t := t.contents + 2
    }
    Some({frames, hop: r.hop, ratio, level, harmonics, fine, fineCells})
  }

// The grid's ratio in each band over all its frames (power ratio, by the bands' levels), and
// the one for a frequency (the bands' lowest below them, highest above).
let gridMeanRatio = (g: grid) =>
  Array.fromInitializer(~length=gridBands, b => {
    let (sum, weight) = (ref(0.), ref(0.))
    for f in 0 to g.frames - 1 {
      let r = g.ratio->get64(f * gridBands + b)
      if !Float.isNaN(r) {
        let w = Math.pow(10., ~exp=g.level->get64(f * gridBands + b) / 10.)
        sum := sum.contents + w * Math.pow(10., ~exp=r / 10.)
        weight := weight.contents + w
      }
    }
    weight.contents > 0. ? sum.contents / weight.contents : 0.
  })

let gridRatioAt = (ratios: array<float>, f) => {
  let b = ref(0)
  gridEdges->Array.forEachWithIndex((edge, j) =>
    if j < gridBands && f >= edge {
      b := j
    }
  )
  ratios[b.contents]->Option.getOr(0.)
}

type features = {
  length: int,
  energy: float,
  // per resolution: band levels, pooled frames × bands, and how many frames each pools
  spectra: array<Float64Array.t>,
  pools: array<int>,
  envelope: Float64Array.t,
  // the harmonic grid (with a pitch to measure it on)
  grid: option<grid>,
  // the side signal's RMS every 10 ms step, as `envelope` is the mid's (for a stereo sound)
  side: option<Float64Array.t>,
}

// `period` is the target's pitch period in samples, which sets the pooling (the same for the
// target and every candidate).
// `gridHz`: the pitch to measure the harmonic grid on (the sound's own), and `axisHz` the fine
// spectrum's (the target's); `side`: the side signal of a stereo sound (x being its mid).
let measure = (x: Float32Array.t, ~period, ~gridHz=?, ~axisHz=?, ~side=?): features => {
  let energy = ref(0.)
  x->TypedArray.forEach(v => energy := energy.contents + v * v)
  let pools = resolutions->Array.map(poolFor(_, ~period))
  {
    length: TypedArray.length(x),
    energy: energy.contents,
    spectra: resolutions->Array.mapWithIndex((r, i) => bandLevels(r, x, ~pool=pools->Array.getUnsafe(i))),
    pools,
    envelope: envelope(x),
    grid: gridHz->Option.flatMap(hz => measureGrid(x, ~hz, ~axisHz?)),
    side: side->Option.map(envelope),
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

// How much of a level that changes over time reaches a frame: the frame's window squared
// weights it (a Hann window's power), here in eight stretches. `power(a, b)` is the mean square
// over [a, b) ms; the frame is `size` samples centred at `centreMs`.
let windowSegments = 8
let windowWeights = {
  // the integral of sin⁴(πx)
  let integral = x =>
    3. * x / 8. - Math.sin(twoPi * x) / (4. * Math.Constants.pi) + Math.sin(2. * twoPi * x) / (32. * Math.Constants.pi)
  let raw = Array.fromInitializer(~length=windowSegments, k =>
    integral(Int.toFloat(k + 1) / Int.toFloat(windowSegments)) - integral(Int.toFloat(k) / Int.toFloat(windowSegments))
  )
  let sum = raw->Array.reduce(0., (s, v) => s + v)
  raw->Array.map(v => v / sum)
}
let windowPower = (power: (float, float) => float, ~centreMs, ~size) => {
  let span = 1000. * Int.toFloat(size) / sampleRate
  let step = span / Int.toFloat(windowSegments)
  let start = centreMs - span / 2.
  let p = ref(0.)
  windowWeights->Array.forEachWithIndex((w, k) => {
    let a = start + Int.toFloat(k) * step
    p := p.contents + w * power(a, a + step)
  })
  p.contents
}
