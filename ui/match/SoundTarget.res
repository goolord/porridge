// The sound to match: a sample, made ready for the matcher. It is mixed to mono (its side
// signal kept apart when it is stereo), resampled to 44.1 kHz, trimmed to start at its onset and
// cut to at most maxSeconds; then its pitch is found (the note the synth plays when rendering a
// candidate) and its shape described, which gives the search its starting point (Genome.seed):
// its envelope, brightness and how that falls, its pitch sweep (tracked every 2 ms through its
// start), how much lies between its harmonics (noise) and how wide it is. A pitched sample's
// harmonics also make a waveform (fitWave), which the first oscillator's "fitted" wave plays.

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
  // how far above its settled pitch it starts (semitones; negative: below), and how long it
  // takes to get within a tenth of that (seconds)
  pitchDrop: float,
  pitchTime: float,
  // how much its pitch wanders once settled (cents)
  wander: float,
  // a second series of partials beside the harmonics (secondSeries): its ratio, whether it has
  // only odd multiples, and its level (dB under the loudest partial)
  series: option<(float, bool, float)>,
  // how far its brightness falls from its brightest (octaves), and the time to fall halfway
  brightnessDrop: float,
  brightnessTime: float,
  // what lies between its harmonics against them, dB (-60: nothing; 0 or so when it has no
  // pitch), over its loud part
  noise: float,
  // its side signal against its mid, dB (-60 when mono), over its loud part
  width: float,
  // its side signal ((left - right) / 2, cut and scaled as the samples are), when stereo
  side: option<Float32Array.t>,
  // whether it was cut off still sounding (its file ends, or maxSeconds), so that its last
  // moments may be an editor's fade rather than the sound's
  truncated: bool,
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
// each agreeing point (a cent off shows at the high harmonics). Points in the first 150 ms,
// where a sweep may still be settling, count only when there are too few others.
let settleSeconds = 0.15

let findPitch = (x: Float32Array.t, env: Float64Array.t) => {
  let steps = TypedArray.length(env)
  let loudest = ref(0.)
  env->TypedArray.forEach(v => loudest := Math.max(loudest.contents, v))
  let loud = Array.fromInitializer(~length=steps, s => s)->Array.filter(s =>
    env->get64(s) > loudest.contents * 0.1 && s >= 2
  )
  let late = loud->Array.filter(s => Int.toFloat(s * Spectrum.envelopeStep) >= settleSeconds * sampleRate)
  let loud = Array.length(late) >= 3 ? late : loud
  let count = Math.Int.min(9, Array.length(loud))
  let points =
    Array.fromInitializer(~length=count, i => loud->Array.getUnsafe(i * Array.length(loud) / Math.Int.max(1, count)))
  let found = points->Array.filterMap(s => {
    let centre = s * Spectrum.envelopeStep + Spectrum.envelopeStep / 2
    WaveImport.findPeriod(x, ~center=centre, ~sampleRate)->Option.map(period => (centre, sampleRate / period))
  })
  switch found {
  | [] => None
  | _ =>
    let mid = median(found->Array.map(((_, hz)) => hz))->Option.getOr(0.)
    let agree = found->Array.filter(((_, hz)) => Math.abs(12. * Math.log2(hz / mid)) < 0.5)
    if 2 * Array.length(agree) < Array.length(found) || mid <= 0. {
      None
    } else {
      let period = sampleRate / mid
      let cycles = Math.Int.max(1, Math.Int.min(64, Float.toInt(0.1 * sampleRate / period)))
      let sharpened = agree->Array.map(((centre, _)) =>
        sampleRate / WaveImport.refinePeriod(x, ~start=centre, ~period, ~cycles)
      )
      Some(median(sharpened)->Option.getOr(mid))
    }
  }
}

// The periods a point might have by YIN over a short window: every dip of the cumulative mean
// normalized difference under 0.4 between minLag and maxLag samples (to a fraction of a sample),
// with its depth.
let periodDips = (x: Float32Array.t, ~centre, ~minLag, ~maxLag, ~window) => {
  let n = TypedArray.length(x)
  let s = centre - window / 2
  if s < 0 || s + window + maxLag + 1 >= n || minLag < 2 {
    []
  } else {
    let d = Float64Array.fromLength(maxLag + 2)
    for tau in 1 to maxLag + 1 {
      let sum = ref(0.)
      for j in 0 to window - 1 {
        let e = x->get32(s + j) - x->get32(s + j + tau)
        sum := sum.contents + e * e
      }
      d->set64(tau, sum.contents)
    }
    // normalized by the mean of those before it
    let cm = Float64Array.fromLength(maxLag + 2)
    let running = ref(0.)
    for tau in 1 to maxLag + 1 {
      running := running.contents + d->get64(tau)
      cm->set64(tau, running.contents > 0. ? d->get64(tau) * Int.toFloat(tau) / running.contents : 1.)
    }
    let found = []
    for t in Math.Int.max(minLag, 2) to maxLag {
      let (a, b, c) = (cm->get64(t - 1), cm->get64(t), cm->get64(t + 1))
      if b < 0.5 && b <= a && b <= c {
        let curve = a - 2. * b + c
        found->Array.push((Int.toFloat(t) + (curve > 0. ? 0.5 * (a - c) / curve : 0.), b))
      }
    }
    found
  }
}

// The pitch through the sound's start, every 2 ms for its first 300 ms, in semitones from
// `hz` (from three octaves above it to one below), followed back from where it settles: each
// point takes the period among its dips nearest the next point's (within 7 semitones; a deeper
// dip counts for a little more), so that a fast sweep isn't read an octave off. How far from
// `hz` the sound starts (the median of the first three points), and how long until it stays
// within a tenth of that (or a quarter of a semitone), (0, 0) when it starts at its pitch; and
// how much it wanders once settled (the spread of the points after that, in cents).
let trackSeconds = 0.3

let pitchSweep = (x: Float32Array.t, ~hz) => {
  let period = sampleRate / hz
  let minLag = Math.Int.max(2, Float.toInt(Math.floor(period / 8.)))
  let maxLag = Float.toInt(Math.ceil(period * 2.))
  let window = Math.Int.max(32, Float.toInt(Math.round(period * 0.7)))
  let step = 88
  let count = Float.toInt(trackSeconds * sampleRate) / step
  let dips = Array.fromInitializer(~length=count, i =>
    periodDips(x, ~centre=window / 2 + i * step, ~minLag, ~maxLag, ~window)->Array.map(((lag, depth)) => (
      12. * Math.log2(period / lag),
      depth,
    ))
  )
  let track = Array.make(~length=count, None)
  let later = ref(0.)
  for i in count - 1 downto 0 {
    let near = dips->Array.getUnsafe(i)->Array.filter(((st, _)) => Math.abs(st - later.contents) <= 7.)
    let best = near->Array.reduce(None, (best, (st, depth)) => {
      let cost = Math.abs(st - later.contents) + 4. * depth
      switch best {
      | Some((_, c)) if c <= cost => best
      | _ => Some((st, cost))
      }
    })
    best->Option.forEach(((st, _)) => {
      track->Array.setUnsafe(i, Some(st))
      later := st
    })
  }
  let track = track->Array.filterMap(v => v)
  // (robustly: the median distance from the median, as a deviation, leaving out slips of a
  // semitone or more that the tracking makes on a sound with partials of its own)
  let spread = (points: array<float>) => {
    let centre = median(points)->Option.getOr(0.)
    let near = points->Array.filter(v => Math.abs(v - centre) < 1.)
    Array.length(near) < 6 ? 0. : 148.26 * median(near->Array.map(v => Math.abs(v - centre)))->Option.getOr(0.)
  }
  if Array.length(track) < 6 {
    (0., 0., 0.)
  } else {
    let start = median(track->Array.slice(~start=0, ~end=3))->Option.getOr(0.)
    if Math.abs(start) < 0.25 || Math.abs(start) > 36. {
      (0., 0., spread(track))
    } else {
      let near = Math.max(0.25, 0.1 * Math.abs(start))
      // the last point still away from the pitch
      let last = ref(0)
      track->Array.forEachWithIndex((v, i) =>
        if Math.abs(v) > near {
          last := i
        }
      )
      let settled = track->Array.slice(~start=last.contents + 1, ~end=Array.length(track))
      (
        start,
        Int.toFloat((last.contents + 1) * step) / sampleRate,
        Array.length(settled) >= 6 ? spread(settled) : 0.,
      )
    }
  }
}

// A second series of partials beside the harmonics, as a second oscillator at an odd ratio
// makes (a bell's, a struck bar's, or Synplant's B oscillator a hair off an octave): the
// partials of the first twelve harmonics' neighbourhoods (a long Blackman window over the
// loud part, each peak placed between bins), those 30 cents or more off where most of them sit
// starting it. Its ratio to the main series' fundamental (the lowest such partial's), whether
// its odd multiples are there too (a square wave's series), and its level against the
// loudest partial (dB); and how far the main series sits from `hz` (cents, the median).
let secondSeries = (x: Float32Array.t, ~hz) => {
  let size = ref(8192)
  while Int.toFloat(size.contents) < 24. * sampleRate / hz && size.contents < 32768 {
    size := size.contents * 2
  }
  let r = Spectrum.gridResolution(size.contents)
  let half = r.size / 2
  let binHz = sampleRate / Int.toFloat(r.size)
  let n = TypedArray.length(x)
  let power = Float64Array.fromLength(half + 1)
  let centres = Array.fromInitializer(~length=Math.Int.max(1, n / (r.size / 2) + 1), i => i * (r.size / 2))
  centres->Array.forEach(c => {
    Spectrum.transform(r, x, c, -2 * r.size)
    for k in 0 to half {
      power->set64(k, power->get64(k) + r.powerA->get64(k))
    }
  })
  let level = k => 10. * Math.log10(Math.max(power->get64(k), 1e-30))
  // each neighbourhood's peak: (harmonic, frequency, dB)
  let peaks = Array.fromInitializer(~length=12, i => {
    let k = Int.toFloat(i + 1)
    let (a, b) = (Float.toInt(Math.ceil((k - 0.45) * hz / binHz)), Float.toInt(Math.floor((k + 0.45) * hz / binHz)))
    if b >= half || a < 1 {
      None
    } else {
      let best = ref(a)
      for j in a to b {
        if power->get64(j) > power->get64(best.contents) {
          best := j
        }
      }
      let j = best.contents
      let (l, m, u) = (level(j - 1), level(j), level(j + 1))
      let curve = l - 2. * m + u
      let offset = curve < 0. ? 0.5 * (l - u) / curve : 0.
      Some((k, (Int.toFloat(j) + offset) * binHz, m))
    }
  })->Array.filterMap(p => p)
  let loudest = peaks->Array.reduce(neg_infinity, (m, (_, _, l)) => Math.max(m, l))
  let heard = peaks->Array.filter(((_, _, l)) => l > loudest - 30.)
  let cents = ((k, f, _)) => 1200. * Math.log2(f / (k * hz))
  switch median(heard->Array.map(cents)) {
  | None => (None, 0.)
  | Some(main) =>
    let off = heard->Array.filter(p => Math.abs(cents(p) - main) >= 30.)
    let fundamental = hz * Math.pow(2., ~exp=main / 1200.)
    let series = switch off {
    | [] => None
    | _ =>
      let (_, f, l) = off->Array.getUnsafe(0)
      let ratio = f / fundamental
      let odd = off->Array.some(((_, g, _)) => Math.abs(1200. * Math.log2(g / (3. * f))) < 40.)
      // (two partials or more off the series, or one within 12 dB of the loudest)
      Array.length(off) >= 2 || l > loudest - 12. ? Some((ratio, odd, l - loudest)) : None
    }
    (series, Math.abs(main) <= 30. ? main : 0.)
  }
}

// What lies between the harmonics against them (Spectrum.measureGrid), dB: over the frames
// within 20 dB of the loudest that start `from` seconds on (after a sweep has settled, which
// smears the harmonics) and the bands within 30 dB of a frame's loudest, weighed by level; and
// each band's own mean (as a power ratio), for fitWave.
let gridSummary = (g: Spectrum.grid, ~from) => {
  let bands = Spectrum.gridBands
  let frameLevel = f => {
    let p = ref(0.)
    for b in 0 to bands - 1 {
      p := p.contents + Math.pow(10., ~exp=g.level->get64(f * bands + b) / 10.)
    }
    10. * Math.log10(Math.max(p.contents, 1e-30))
  }
  let levels = Array.fromInitializer(~length=g.frames, frameLevel)
  let top = levels->Array.reduce(neg_infinity, Math.max)
  let (sum, weight) = (ref(0.), ref(0.))
  let bandSum = Float64Array.fromLength(bands)
  let bandWeight = Float64Array.fromLength(bands)
  let first = Math.Int.min(g.frames - 1, Float.toInt(Math.ceil(from * sampleRate / Int.toFloat(g.hop))))
  for f in first to g.frames - 1 {
    if levels->Array.getUnsafe(f) > top - 20. {
      let loudestBand = ref(neg_infinity)
      for b in 0 to bands - 1 {
        loudestBand := Math.max(loudestBand.contents, g.level->get64(f * bands + b))
      }
      for b in 0 to bands - 1 {
        let r = g.ratio->get64(f * bands + b)
        let l = g.level->get64(f * bands + b)
        if !Float.isNaN(r) && l > loudestBand.contents - 30. {
          let w = Math.pow(10., ~exp=(l - loudestBand.contents) / 20.)
          sum := sum.contents + w * r
          weight := weight.contents + w
          bandSum->set64(b, bandSum->get64(b) + w * Math.pow(10., ~exp=r / 10.))
          bandWeight->set64(b, bandWeight->get64(b) + w)
        }
      }
    }
  }
  (
    weight.contents > 0. ? sum.contents / weight.contents : Spectrum.gridFloor,
    Array.fromInitializer(~length=bands, b => bandWeight->get64(b) > 0. ? bandSum->get64(b) / bandWeight->get64(b) : 0.),
  )
}

// How far the brightness (where the middle spectra fall 30 dB under their loudest band, in
// octaves: a lowpass's cutoff moves it as much as itself) falls from its brightest in the first
// half of the loud part to where it settles (the median of the last third), and how long it
// takes to fall halfway: a filter envelope's sweep, or a string's top dying first.
let brightnessFall = (f: Spectrum.features) => {
  let ri = 1
  let r = Spectrum.resolutions->Array.getUnsafe(ri)
  let levels = f.spectra->Array.getUnsafe(ri)
  let frames = TypedArray.length(levels) / r.bands
  let seconds = Int.toFloat(r.hop * f.pools->Array.getUnsafe(ri)) / sampleRate
  let power = Array.fromInitializer(~length=frames, t => {
    let p = ref(0.)
    for b in 0 to r.bands - 1 {
      let v = levels->get64(t * r.bands + b)
      p := p.contents + v * v
    }
    p.contents
  })
  let top = power->Array.reduce(0., Math.max)
  let valid = Array.fromInitializer(~length=frames, t => t)->Array.filter(t => power->Array.getUnsafe(t) > top * 0.003)
  let centre = t => {
    let loudest = ref(0.)
    for b in 0 to r.bands - 1 {
      loudest := Math.max(loudest.contents, levels->get64(t * r.bands + b))
    }
    let top = ref(0)
    for b in 0 to r.bands - 1 {
      if levels->get64(t * r.bands + b) > loudest.contents * 0.0316 {
        top := b
      }
    }
    Math.log2(r.centres->get64(top.contents))
  }
  let count = Array.length(valid)
  if count < 4 {
    (0., 0.)
  } else {
    let cs = valid->Array.map(centre)
    let (peakAt, peak) = cs->Array.slice(~start=0, ~end=Math.Int.max(1, count / 2))->Array.reduceWithIndex((0, neg_infinity), ((i, m), c, j) => c > m ? (j, c) : (i, m))
    let settled = median(cs->Array.slice(~start=count - Math.Int.max(1, count / 3), ~end=count))->Option.getOr(peak)
    let drop = peak - settled
    if drop <= 0. {
      (0., 0.)
    } else {
      let half = ref(None)
      cs->Array.forEachWithIndex((c, j) =>
        if j > peakAt && half.contents == None && c <= peak - drop / 2. {
          half := Some(j)
        }
      )
      let frames = Int.toFloat(half.contents->Option.getOr(count - 1) - peakAt)
      (drop, Math.max(seconds, frames * seconds))
    }
  }
}

// Side against mid over the loud part (10 ms steps within 20 dB of the loudest), dB.
let widthOf = (mid: Float64Array.t, side: Float64Array.t) => {
  let loudest = ref(0.)
  mid->TypedArray.forEach(v => loudest := Math.max(loudest.contents, v))
  let (m, s) = (ref(0.), ref(0.))
  for i in 0 to Math.Int.min(TypedArray.length(mid), TypedArray.length(side)) - 1 {
    if mid->get64(i) > loudest.contents * 0.1 {
      m := m.contents + mid->get64(i) * mid->get64(i)
      s := s.contents + side->get64(i) * side->get64(i)
    }
  }
  m.contents > 0. ? Math.max(-60., 10. * Math.log10(Math.max(s.contents / m.contents, 1e-6))) : -60.
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
// by power, with the phases of the loudest point. What lies between the harmonics lies on them
// too: each harmonic's power is cut by the share of its band that is that (`between`, per
// Spectrum grid band, as gridSummary gives it), so that a noisy sample's wave doesn't carry its
// noise as harmonics and leaves the noise to the noise source.
let fitWave = (x: Float32Array.t, env: Float64Array.t, ~hz, ~between: array<float>) => {
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
    let share = k => {
      let f = Int.toFloat(k + 1) * hz
      let b = ref(-1)
      Spectrum.gridEdges->Array.forEachWithIndex((edge, j) =>
        if j < Spectrum.gridBands && f >= edge {
          b := j
        }
      )
      let r = between[b.contents]->Option.getOr(0.)
      // (the lowest band's share holds below it, the highest's above)
      let r = b.contents < 0 ? between[0]->Option.getOr(0.) : r
      // the bins on a harmonic hold about three bins' worth of what lies between
      Math.max(0., 1. - r)
    }
    WaveImport.synthesise({
      amp: power->Array.mapWithIndex((p, k) => Math.sqrt(p / Int.toFloat(count) * share(k))),
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
    // the side signal of a stereo sample, resampled as the mid is
    let sideRaw = audio.sides->Option.map(((l, r)) =>
      resample(l->TypedArray.mapWithIndex((v, i) => 0.5 * (v - r->get32(i))), ~from=audio.sampleRate)
    )
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
      let side = sideRaw->Option.flatMap(s => {
        let out = Float32Array.fromLength(length)
        for i in 0 to length - 1 {
          out->set32(i, start + i < TypedArray.length(s) ? s->get32(start + i) * 0.5 / cutPeak : 0.)
        }
        // (a stereo file whose channels are the same is mono)
        peakOf(out) > 1e-4 ? Some(out) : None
      })
      let features = Spectrum.measure(samples, ~period=None, ~side=?side)
      let (hz, pitchDrop, pitchTime, wander) = switch findPitch(samples, features.envelope) {
      | None => (spectralPitch(samples, features.envelope), 0., 0., 0.)
      | Some(hz) =>
        let (drop, time, wander) = pitchSweep(samples, ~hz)
        (Some(hz), drop, time, wander)
      }
      // the main series' pitch, if it sits off the period found (a second series pulls YIN's
      // period towards it), and the second series
      let (series, offset) = hz->Option.mapOr((None, 0.), hz => secondSeries(samples, ~hz))
      let hz = hz->Option.map(hz => hz * Math.pow(2., ~exp=offset / 1200.))
      let (note, cents) = hz->Option.mapOr((60, 0.), noteOf)
      let (attack, decay, sustain) = describeEnvelope(features.envelope)
      // without a pitch there are no harmonics to stand over the rest: all of it is noise
      let (noise, between) =
        hz
        ->Option.flatMap(hz => Spectrum.measureGrid(samples, ~hz))
        ->Option.mapOr((0., []), g => gridSummary(g, ~from=pitchTime))
      let (brightnessDrop, brightnessTime) = brightnessFall(features)
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
        pitchTime,
        wander,
        series,
        brightnessDrop,
        brightnessTime,
        noise,
        width: features.side->Option.mapOr(-60., s => widthOf(features.envelope, s)),
        side,
        truncated: stop >= n || length < stop - start,
        overview: overviewOf(samples, ~points=160),
        loudness: Array.fromInitializer(~length=TypedArray.length(features.envelope), s =>
          Spectrum.db(features.envelope->get64(s))
        ),
        wave: hz->Option.flatMap(hz => fitWave(samples, features.envelope, ~hz, ~between)),
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
