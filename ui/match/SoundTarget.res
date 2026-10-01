// The sound to match: a sample, made ready for the matcher. It is mixed to mono, resampled to
// 44.1 kHz, trimmed to start at its onset and cut to at most maxSeconds; then its pitch is
// found (the note the synth plays when rendering a candidate) and its shape described, which
// gives the search its starting point (Genome.seed). A pitched sample's harmonics also make a
// waveform (fitWave), which the first oscillator's "fitted" wave plays.

@get_index external get32: (Float32Array.t, int) => float = ""
@set_index external set32: (Float32Array.t, int, float) => unit = ""
@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

let sampleRate = Spectrum.sampleRate
let maxSeconds = 1.6
let minSeconds = 0.05

type t = {
  name: string,
  // mono, 44.1 kHz, from the onset, peak 0.5
  samples: Float32Array.t,
  // how long the original runs past the part that is matched, in seconds
  cutOff: float,
  // the pitch found, if any
  hz: option<float>,
  // the key the synth plays, and the sample's tuning against it (cents)
  note: int,
  cents: float,
  // seconds: to the peak, and from the peak to most of the way down to the sustain level
  attack: float,
  decay: float,
  // the level it holds at the end, against its peak (0 when it dies away)
  sustain: float,
  // the spectral centroid, Hz
  brightness: float,
  // how much the pitch falls during the first 100 ms (semitones; negative: rises)
  pitchDrop: float,
  // peak levels of 160 stretches, for the drawer's picture of it
  overview: array<float>,
  // its loudness every 10 ms, dB
  loudness: array<float>,
  // its harmonics as a waveform of 512 points (peak 1), when it has a pitch
  wave: option<Float32Array.t>,
}

let seconds = t => Int.toFloat(TypedArray.length(t.samples)) / sampleRate

// the pitch the synth plays, Hz, and its period in samples (Spectrum.measure pools by it)
let playedHz = t => 440. * Math.pow(2., ~exp=(Int.toFloat(t.note) + t.cents / 100. - 69.) / 12.)
let period = t => Some(sampleRate / playedHz(t))

// Resamples to 44.1 kHz with a Lanczos-windowed sinc (8 lobes), its cutoff lowered when going
// down so that nothing folds back.
let resample = (x: Float32Array.t, ~from) =>
  if Math.abs(from - sampleRate) < 0.5 {
    x
  } else {
    let n = TypedArray.length(x)
    let ratio = from / sampleRate
    let stretch = Math.max(1., ratio)
    let lobes = 8.
    let reach = Float.toInt(Math.ceil(lobes * stretch))
    let m = Float.toInt(Math.floor(Int.toFloat(n) / ratio))
    let out = Float32Array.fromLength(m)
    let sinc = v => Math.abs(v) < 1e-9 ? 1. : Math.sin(Math.Constants.pi * v) / (Math.Constants.pi * v)
    for i in 0 to m - 1 {
      let t = Int.toFloat(i) * ratio
      let c = Float.toInt(Math.floor(t))
      let sum = ref(0.)
      let weight = ref(0.)
      for k in c - reach + 1 to c + reach {
        if k >= 0 && k < n {
          let d = (t - Int.toFloat(k)) / stretch
          let w = Math.abs(d) < lobes ? sinc(d) * sinc(d / lobes) : 0.
          sum := sum.contents + w * x->get32(k)
          weight := weight.contents + w
        }
      }
      out->set32(i, weight.contents != 0. ? sum.contents / weight.contents : 0.)
    }
    out
  }

let peakOf = (x: Float32Array.t) => {
  let p = ref(0.)
  x->TypedArray.forEach(v => p := Math.max(p.contents, Math.abs(v)))
  p.contents
}

let median = (xs: array<float>) => {
  let s = xs->Array.toSorted(Float.compare)
  s[Array.length(s) / 2]
}

// The pitch at each of several points through the loud part (WaveImport's YIN): their median,
// if at least half of them agree with it, sharpened by matching about 100 ms of cycles at
// each agreeing point (a cent off shows at the high harmonics); and how much higher the first
// is than that.
let findPitch = (x: Float32Array.t, env: Float64Array.t) => {
  let steps = TypedArray.length(env)
  let loudest = ref(0.)
  env->TypedArray.forEach(v => loudest := Math.max(loudest.contents, v))
  let loud = Array.fromInitializer(~length=steps, s => s)->Array.filter(s =>
    env->get64(s) > loudest.contents * 0.1 && s >= 2
  )
  let count = Math.Int.min(9, Array.length(loud))
  let points =
    Array.fromInitializer(~length=count, i => loud->Array.getUnsafe(i * Array.length(loud) / Math.Int.max(1, count)))
  let found = points->Array.filterMap(s => {
    let centre = s * Spectrum.envelopeStep + Spectrum.envelopeStep / 2
    WaveImport.findPeriod(x, ~center=centre, ~sampleRate)->Option.map(period => (centre, sampleRate / period))
  })
  switch found {
  | [] => (None, 0.)
  | _ =>
    let mid = median(found->Array.map(((_, hz)) => hz))->Option.getOr(0.)
    let agree = found->Array.filter(((_, hz)) => Math.abs(12. * Math.log2(hz / mid)) < 0.5)
    if 2 * Array.length(agree) < Array.length(found) || mid <= 0. {
      (None, 0.)
    } else {
      let period = sampleRate / mid
      let cycles = Math.Int.max(1, Math.Int.min(64, Float.toInt(0.1 * sampleRate / period)))
      let sharpened = agree->Array.map(((centre, _)) =>
        sampleRate / WaveImport.refinePeriod(x, ~start=centre, ~period, ~cycles)
      )
      let refined = median(sharpened)->Option.getOr(mid)
      let (_, first) = found->Array.getUnsafe(0)
      let drop = 12. * Math.log2(first / refined)
      (Some(refined), Math.abs(drop) < 0.5 || Math.abs(drop) > 36. ? 0. : drop)
    }
  }
}

// The pitch from the spectrum, when YIN finds none (a pitched sound with noise in it, or one
// whose pitch wavers): the fundamental whose harmonics stand highest over the spectrum's
// median, summed with less weight further up, over long spectra of the loud part. None if no
// fundamental stands out from the rest.
let pitchResolution = Lazy.make(() => Spectrum.makeResolution(~size=8192, ~hop=4096, ~bands=8, ~lowest=30.))

let spectralPitch = (x: Float32Array.t, env: Float64Array.t) => {
  let r = Lazy.get(pitchResolution)
  let half = r.size / 2
  let steps = TypedArray.length(env)
  let loudest = ref(0.)
  env->TypedArray.forEach(v => loudest := Math.max(loudest.contents, v))
  let loud = Array.fromInitializer(~length=steps, s => s)->Array.filter(s => env->get64(s) > loudest.contents * 0.25)
  let count = Math.Int.min(6, Array.length(loud))
  let centres =
    Array.fromInitializer(~length=count, i => loud->Array.getUnsafe(i * Array.length(loud) / Math.Int.max(1, count)))
    ->Array.map(s => s * Spectrum.envelopeStep + Spectrum.envelopeStep / 2)
  // the frames' power, two at a time
  let power = Float64Array.fromLength(half + 1)
  let i = ref(0)
  while i.contents < count {
    let pair = i.contents + 1 < count
    Spectrum.transform(r, x, centres->Array.getUnsafe(i.contents), pair ? centres->Array.getUnsafe(i.contents + 1) : -2 * r.size)
    for k in 0 to half {
      power->set64(k, power->get64(k) + r.powerA->get64(k) + (pair ? r.powerB->get64(k) : 0.))
    }
    i := i.contents + 2
  }
  let binHz = sampleRate / Int.toFloat(r.size)
  let mag = power->TypedArray.map(p => Math.sqrt(p))
  let top = Math.Int.min(half, Float.toInt(8000. / binHz))
  let low = Float.toInt(50. / binHz)
  let noise = Math.max(1e-12, median(Array.fromInitializer(~length=top - low, k => mag->get64(low + k)))->Option.getOr(0.))
  // a harmonic's level: the highest of the three bins nearest it
  let level = hz => {
    let k = Float.toInt(Math.round(hz / binHz))
    let m = ref(0.)
    for j in Math.Int.max(1, k - 1) to Math.Int.min(half, k + 1) {
      m := Math.max(m.contents, mag->get64(j))
    }
    m.contents
  }
  let score = f0 => {
    let s = ref(0.)
    let k = ref(1)
    while k.contents <= 12 && Int.toFloat(k.contents) * f0 < 8000. {
      let weight = Math.pow(0.85, ~exp=Int.toFloat(k.contents - 1))
      s := s.contents + weight * Math.log(1. + level(Int.toFloat(k.contents) * f0) / noise)
      k := k.contents + 1
    }
    s.contents
  }
  // 40 Hz to 2.5 kHz, in sixteenths of a semitone
  let steps = 16 * 12
  let hzOf = i => 40. * Math.pow(2., ~exp=i / Int.toFloat(steps))
  let scores = Array.fromInitializer(~length=steps * 6, i => score(hzOf(Int.toFloat(i))))
  let (best, bestScore) = scores->Array.reduceWithIndex((0, neg_infinity), ((b, bs), s, i) => s > bs ? (i, s) : (b, bs))
  let typical = median(scores)->Option.getOr(0.)
  if count == 0 || bestScore < 1.8 * typical || bestScore < 4. {
    None
  } else {
    // between grid points: the parabola through the best and its neighbours
    let at = i => scores[i]->Option.getOr(bestScore)
    let (a, b, c) = (at(best - 1), bestScore, at(best + 1))
    let curve = a - 2. * b + c
    let offset = curve < 0. ? 0.5 * (a - c) / curve : 0.
    Some(hzOf(Int.toFloat(best) + offset))
  }
}

// The key that plays hz (kept within the keyboard's middle), and the cents left over.
let noteOf = hz => {
  let midi = 69. + 12. * Math.log2(hz / 440.)
  let note = Math.round(midi)
  let shifted = ref(note)
  while shifted.contents < 24. {
    shifted := shifted.contents + 12.
  }
  while shifted.contents > 96. {
    shifted := shifted.contents - 12.
  }
  (Float.toInt(shifted.contents), (midi - note) * 100.)
}

let describeEnvelope = (env: Float64Array.t) => {
  let steps = TypedArray.length(env)
  let step = Int.toFloat(Spectrum.envelopeStep) / sampleRate
  let peakAt = ref(0)
  for s in 0 to steps - 1 {
    if env->get64(s) > env->get64(peakAt.contents) {
      peakAt := s
    }
  }
  let peak = Math.max(env->get64(peakAt.contents), 1e-9)
  // the level at the end: the median of the last fifth, unless it is dying away
  let tail = Array.fromInitializer(~length=Math.Int.max(1, steps / 5), i => env->get64(steps - 1 - i) / peak)
  let endLevel = median(tail)->Option.getOr(0.)
  let sustain = endLevel < 0.03 ? 0. : endLevel
  // the decay: from the peak until 90% of the way down to the sustain level
  let threshold = sustain + (1. - sustain) * 0.1
  let fallen = ref(None)
  for s in peakAt.contents to steps - 1 {
    if fallen.contents == None && env->get64(s) / peak <= threshold {
      fallen := Some(s)
    }
  }
  let decay = switch fallen.contents {
  | Some(s) => Int.toFloat(s - peakAt.contents) * step
  | None => Int.toFloat(steps - peakAt.contents) * step * 1.5
  }
  (Int.toFloat(peakAt.contents) * step + step / 2., Math.max(decay, step), sustain)
}

// The power-weighted centroid of the long resolution's average spectrum.
let centroid = (f: Spectrum.features) => {
  let r = Spectrum.resolutions->Array.getUnsafe(0)
  let levels = f.spectra->Array.getUnsafe(0)
  let frames = TypedArray.length(levels) / r.bands
  let (sum, weight) = (ref(0.), ref(0.))
  for t in 0 to frames - 1 {
    for b in 0 to r.bands - 1 {
      let v = levels->get64(t * r.bands + b)
      sum := sum.contents + v * v * r.centres->get64(b)
      weight := weight.contents + v * v
    }
  }
  weight.contents > 0. ? sum.contents / weight.contents : 1000.
}

let overviewOf = (x: Float32Array.t, ~points) => {
  let n = TypedArray.length(x)
  Array.fromInitializer(~length=points, i => {
    let a = i * n / points
    let z = Math.Int.max(a + 1, (i + 1) * n / points)
    let m = ref(0.)
    for k in a to Math.Int.min(n, z) - 1 {
      m := Math.max(m.contents, Math.abs(x->get32(k)))
    }
    m.contents
  })
}

// The sample's harmonics at its pitch, as a waveform: their levels over up to eight points in
// its loud part (whole periods under a window, as WaveImport measures a recording), averaged
// by power, with the phases of the loudest point.
let fitWave = (x: Float32Array.t, env: Float64Array.t, ~hz) => {
  let n = TypedArray.length(x)
  let period = sampleRate / hz
  let cycles = Math.Int.max(2, Math.Int.min(24, Float.toInt(Math.round(0.06 * sampleRate / period))))
  let span = period * Int.toFloat(cycles)
  let steps = TypedArray.length(env)
  let loudest = ref(0)
  for s in 0 to steps - 1 {
    if env->get64(s) > env->get64(loudest.contents) {
      loudest := s
    }
  }
  let peak = env->get64(loudest.contents)
  let loud = Array.fromInitializer(~length=steps, s => s)->Array.filter(s => env->get64(s) > peak * 0.25)
  let count = Math.Int.min(8, Array.length(loud))
  let points = Array.fromInitializer(~length=count, i => loud->Array.getUnsafe(i * Array.length(loud) / Math.Int.max(1, count)))
  let spectrumAt = s => {
    let centre = Int.toFloat(s * Spectrum.envelopeStep + Spectrum.envelopeStep / 2)
    let start = Math.max(0., Math.min(centre - span / 2., Int.toFloat(n - 1) - span))
    WaveImport.spectrumOfPeriods(x, ~start, ~period, ~cycles)
  }
  if Int.toFloat(n) < span + 2. || count == 0 {
    None
  } else {
    let shape = spectrumAt(loudest.contents)
    WaveImport.align(shape)
    let power = Array.make(~length=WaveImport.harmonics, 0.)
    points->Array.forEach(s =>
      spectrumAt(s).amp->Array.forEachWithIndex((a, k) => power->Array.setUnsafe(k, power->Array.getUnsafe(k) + a * a))
    )
    WaveImport.synthesise({
      amp: power->Array.map(p => Math.sqrt(p / Int.toFloat(count))),
      phase: shape.phase,
    })
  }
}

// Where a sound starts: 2 ms before it first reaches -40 dB of its peak. The sample is cut
// there, and so is each candidate's render (MatchSearch.renderGenes), so that they line up.
let onsetOf = (x: Float32Array.t) => {
  let n = TypedArray.length(x)
  let peak = peakOf(x)
  let onset = ref(0)
  while onset.contents < n && Math.abs(x->get32(onset.contents)) < peak * 0.01 {
    onset := onset.contents + 1
  }
  Math.Int.max(0, Math.Int.min(n, onset.contents) - 88)
}

let prepare = (~name, audio: AudioFile.t): result<t, string> => {
  let x = resample(audio.samples, ~from=audio.sampleRate)
  let n = TypedArray.length(x)
  let peak = peakOf(x)
  if n == 0 || peak < 1e-6 {
    Error(`${name} is silent`)
  } else {
    // from its onset to 20 ms after it last passes -60 dB
    let start = onsetOf(x)
    let ending = ref(n - 1)
    while ending.contents > start && Math.abs(x->get32(ending.contents)) < peak * 0.001 {
      ending := ending.contents - 1
    }
    let stop = Math.Int.min(n, ending.contents + 882)
    let length = Math.Int.min(stop - start, Float.toInt(maxSeconds * sampleRate))
    if Int.toFloat(length) < minSeconds * sampleRate {
      Error(`${name} is too short to match`)
    } else {
      let samples = Float32Array.fromLength(length)
      // its own peak at 0.5, after the cut
      let cutPeak = peakOf(x->TypedArray.subarray(~start, ~end=start + length))
      for i in 0 to length - 1 {
        samples->set32(i, x->get32(start + i) * 0.5 / cutPeak)
      }
      let features = Spectrum.measure(samples, ~period=None)
      let (hz, pitchDrop) = switch findPitch(samples, features.envelope) {
      | (None, _) => (spectralPitch(samples, features.envelope), 0.)
      | found => found
      }
      let (note, cents) = hz->Option.mapOr((60, 0.), noteOf)
      let (attack, decay, sustain) = describeEnvelope(features.envelope)
      Ok({
        name,
        samples,
        cutOff: Int.toFloat(stop - start - length) / sampleRate,
        hz,
        note,
        cents,
        attack,
        decay,
        sustain,
        brightness: centroid(features),
        pitchDrop,
        overview: overviewOf(samples, ~points=160),
        loudness: Array.fromInitializer(~length=TypedArray.length(features.envelope), s =>
          Spectrum.db(features.envelope->get64(s))
        ),
        wave: hz->Option.flatMap(hz => fitWave(samples, features.envelope, ~hz)),
      })
    }
  }
}

// "A3 +4 cents" (the key played, which is octaves from the sample's own pitch if that is off
// the keyboard's middle), or "no clear pitch"
let pitchText = t =>
  t.hz->Option.mapOr("no clear pitch", _ =>
    WaveImport.noteName(playedHz(t))
  )
