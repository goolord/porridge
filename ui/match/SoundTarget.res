// The sound to match: a sample, made ready for the matcher. It is mixed to mono, resampled to
// 44.1 kHz, trimmed to start at its onset and cut to at most maxSeconds; then its pitch is
// found (the note the synth plays when rendering a candidate) and its shape described, which
// gives the search its starting point (Genome.seed).

@get_index external get32: (Float32Array.t, int) => float = ""
@set_index external set32: (Float32Array.t, int, float) => unit = ""
@get_index external get64: (Float64Array.t, int) => float = ""

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

let prepare = (~name, audio: AudioFile.t): result<t, string> => {
  let x = resample(audio.samples, ~from=audio.sampleRate)
  let n = TypedArray.length(x)
  let peak = peakOf(x)
  if n == 0 || peak < 1e-6 {
    Error(`${name} is silent`)
  } else {
    // from 2 ms before it first reaches -40 dB to 20 ms after it last passes -60 dB
    let onset = ref(0)
    while onset.contents < n && Math.abs(x->get32(onset.contents)) < peak * 0.01 {
      onset := onset.contents + 1
    }
    let ending = ref(n - 1)
    while ending.contents > onset.contents && Math.abs(x->get32(ending.contents)) < peak * 0.001 {
      ending := ending.contents - 1
    }
    let start = Math.Int.max(0, onset.contents - 88)
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
      let (hz, pitchDrop) = findPitch(samples, features.envelope)
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
