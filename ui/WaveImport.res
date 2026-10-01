// Turns a sample into an oscillator waveform, as Sytrus does: the sample's harmonics are
// measured and the 512-point waveform is built from them. The engine band-limits the
// waveform through the same spectrum, so it plays as measured. Three kinds of file:
//
// - one cycle (up to 4096 samples, as single-cycle libraries are): the whole file is the
//   period, and its spectrum is exact;
// - a wavetable (frames of the length the file declares, or of 2048 samples): one frame;
// - anything longer, a recording: the pitch is found around a position (YIN), then the
//   harmonics are measured over a whole number of periods there, under a Hann window, which
//   keeps each harmonic clear of its neighbours. The cycle is turned to start where the
//   fundamental rises through zero, so that it holds still while the position moves.
//
// An LFO shape takes the sample's volume envelope instead.

let points = 512
// harmonics 1 .. 255: the table's Nyquist bin stays empty
let harmonics = 255
let maxCycle = 4096
let lowestPitch = 25.
let highestPitch = 3000.

let twoPi = 2. * Math.Constants.pi
let at = ByteView.getUnsafe
@get_index external get64: (Float64Array.t, int) => float = ""

type kind =
  | Cycle
  | Frames({size: int, count: int})
  | Recording

type t = {
  name: string,
  audio: AudioFile.t,
  kind: kind,
  // the RMS of the sample in 512 stretches, peak 1: its overview, and the LFO envelope
  envelope: Float32Array.t,
}

type analysis = {
  wave: Float32Array.t,
  // where it came from, e.g. "frame 3 of 64" or "A3 +4 cents at 0.42 s"
  detail: string,
  // the part of the sample measured, in samples
  from: float,
  length: float,
}

let length = t => TypedArray.length(t.audio.samples)

let classify = (audio: AudioFile.t) => {
  let n = TypedArray.length(audio.samples)
  switch audio.frameSize {
  | Some(size) if size >= 16 && size <= 65536 && n >= 2 * size =>
    Frames({size, count: n / size})
  | Some(size) if size >= 16 && n <= size => Cycle
  | _ if n <= maxCycle => Cycle
  | _ if mod(n, 2048) == 0 && n / 2048 <= 256 => Frames({size: 2048, count: n / 2048})
  | _ => Recording
  }
}

// The RMS of x around 'points' even steps, scaled to a peak of 1. Each step is measured
// under a Hann window of two steps, and at least 50 ms, so that the envelope doesn't ripple
// with the waveform.
let envelopeOf = (x: Float32Array.t, ~sampleRate) => {
  let n = TypedArray.length(x)
  let env = Float32Array.fromLength(points)
  let step = Int.toFloat(n) / Int.toFloat(points)
  let width = Math.max(2. * step, 0.05 * sampleRate)
  let peak = ref(0.)
  for j in 0 to points - 1 {
    let centre = (Int.toFloat(j) + 0.5) * step
    let a = Math.Int.max(0, Math.Int.min(n - 1, Float.toInt(Math.ceil(centre - width / 2.))))
    let b = Math.Int.max(a + 1, Math.Int.min(n, Float.toInt(Math.floor(centre + width / 2.)) + 1))
    let sum = ref(0.)
    let weight = ref(1e-12)
    for i in a to b - 1 {
      let w = 0.5 + 0.5 * Math.cos(twoPi * (Int.toFloat(i) - centre) / width)
      sum := sum.contents + w * x->at(i) * x->at(i)
      weight := weight.contents + w
    }
    let rms = Math.sqrt(sum.contents / weight.contents)
    env->ByteView.setUnsafe(j, rms)
    peak := Math.max(peak.contents, rms)
  }
  if peak.contents > 0. {
    env->TypedArray.forEachWithIndex((v, j) => env->ByteView.setUnsafe(j, v / peak.contents))
  }
  env
}

let make = (name, audio: AudioFile.t) =>
  if TypedArray.length(audio.samples) < 8 {
    Error(`${name} is too short to measure`)
  } else {
    Ok({
      name,
      audio,
      kind: classify(audio),
      envelope: envelopeOf(audio.samples, ~sampleRate=audio.sampleRate),
    })
  }

//==============================================================================
// Spectra. Levels and phases of harmonics 1 .. 255 (index k - 1), phases relative to a sine,
// as the harmonic editor shows them.

type spectrum = {amp: array<float>, phase: array<float>}

let emptySpectrum = count => {
  amp: Array.make(~length=count, 0.),
  phase: Array.make(~length=count, 0.),
}

let setHarmonic = (s, k, re, im, scale) => {
  s.amp->Array.setUnsafe(k - 1, scale * Math.hypot(re, im))
  s.phase->Array.setUnsafe(k - 1, Math.atan2(~y=re, ~x=-.im))
}

// n samples from 'start' taken as one period: exact. Its first `count` harmonics.
let spectrumOfCycle = (x, ~start, ~n, ~count=harmonics) => {
  let s = emptySpectrum(count)
  let cos = Float64Array.fromLength(n)
  let sin = Float64Array.fromLength(n)
  for i in 0 to n - 1 {
    let a = twoPi * Int.toFloat(i) / Int.toFloat(n)
    cos->TypedArray.set(i, Math.cos(a))
    sin->TypedArray.set(i, Math.sin(a))
  }
  for k in 1 to Math.Int.min(count, (n - 1) / 2) {
    let re = ref(0.)
    let im = ref(0.)
    for i in 0 to n - 1 {
      let v = x->at(start + i)
      let m = mod(k * i, n)
      re := re.contents + v * cos->get64(m)
      im := im.contents - v * sin->get64(m)
    }
    s->setHarmonic(k, re.contents, im.contents, 2. / Int.toFloat(n))
  }
  s
}

// A whole number of periods from 'start' (a fractional sample position) under a Hann window.
// With two periods or more, the window's zeros fall on the neighbouring harmonics.
let spectrumOfPeriods = (x, ~start, ~period, ~cycles) => {
  let s = emptySpectrum(harmonics)
  let n = TypedArray.length(x)
  let span = period * Int.toFloat(cycles)
  let i0 = Math.Int.max(0, Float.toInt(Math.ceil(start)))
  let i1 = Math.Int.min(n - 1, Float.toInt(Math.floor(start + span)))
  let count = i1 - i0 + 1
  let windowed = Float64Array.fromLength(count)
  let weight = ref(0.)
  for i in 0 to count - 1 {
    let w = 0.5 - 0.5 * Math.cos(twoPi * (Int.toFloat(i0 + i) - start) / span)
    windowed->TypedArray.set(i, w * x->at(i0 + i))
    weight := weight.contents + w
  }
  // harmonics at or above Nyquist aren't in the sample
  let top = Math.Int.min(harmonics, Float.toInt(Math.ceil(period / 2.)) - 1)
  for k in 1 to top {
    // a phasor turning one harmonic per period, from the window's start
    let step = twoPi * Int.toFloat(k) / period
    let (dc, ds) = (Math.cos(step), Math.sin(step))
    let a0 = step * (Int.toFloat(i0) - start)
    let c = ref(Math.cos(a0))
    let sn = ref(Math.sin(a0))
    let re = ref(0.)
    let im = ref(0.)
    for i in 0 to count - 1 {
      let v = windowed->get64(i)
      re := re.contents + v * c.contents
      im := im.contents - v * sn.contents
      let c1 = c.contents * dc - sn.contents * ds
      sn := sn.contents * dc + c.contents * ds
      c := c1
    }
    s->setHarmonic(k, re.contents, im.contents, 2. / weight.contents)
  }
  s
}

// Turns the cycle to start where the fundamental rises through zero (the strongest harmonic,
// when the fundamental is missing).
let align = s => {
  let peak = s.amp->Array.reduce(0., Math.max)
  let reference =
    s.amp->Array.getUnsafe(0) > 0.001 * peak
      ? 1
      : s.amp->Array.reduceWithIndex(1, (best, a, i) =>
          a > s.amp->Array.getUnsafe(best - 1) ? i + 1 : best
        )
  let turn = s.phase->Array.getUnsafe(reference - 1) / Int.toFloat(reference)
  s.phase->Array.forEachWithIndex((p, i) => {
    let q = p - Int.toFloat(i + 1) * turn
    s.phase->Array.setUnsafe(i, q - twoPi * Math.round(q / twoPi))
  })
}

// The 512-point waveform, peak 1 (None when it's silent).
let synthesise = s => {
  let wave = Float64Array.fromLength(points)
  for k in 1 to harmonics {
    let a = s.amp->Array.getUnsafe(k - 1)
    if a > 0. {
      let p = s.phase->Array.getUnsafe(k - 1)
      for j in 0 to points - 1 {
        let v = wave->get64(j) + a * Math.sin(twoPi * Int.toFloat(mod(k * j, points)) / Int.toFloat(points) + p)
        wave->TypedArray.set(j, v)
      }
    }
  }
  let peak = ref(0.)
  wave->TypedArray.forEach(v => peak := Math.max(peak.contents, Math.abs(v)))
  peak.contents < 1e-6
    ? None
    : Some(Float32Array.fromLength(points)->TypedArray.mapWithIndex((_, j) => wave->get64(j) / peak.contents))
}

//==============================================================================
// Pitch

// Where the parabola through (tau - 1, a), (tau, b) and (tau + 1, c) bottoms out.
let vertex = (tau, a, b, c) => {
  let curve = a - 2. * b + c
  Int.toFloat(tau) + (curve > 0. ? 0.5 * (a - c) / curve : 0.)
}

// The period at 'center' (in samples, fractional) by YIN: the lag where the sample best
// matches itself, measured over a window as long as the longest period looked for.
let findPeriod = (x, ~center, ~sampleRate) => {
  let n = TypedArray.length(x)
  let maxLag = Math.Int.min(Float.toInt(sampleRate / lowestPitch), n / 2 - 2)
  let minLag = Math.Int.max(2, Float.toInt(sampleRate / highestPitch))
  if maxLag < minLag + 4 {
    None
  } else {
    let w = maxLag
    let s = Math.Int.max(0, Math.Int.min(center - w, n - 2 * w - 2))
    let energy = ref(0.)
    for j in 0 to w - 1 {
      energy := energy.contents + x->at(s + j) * x->at(s + j)
    }
    if energy.contents < 1e-9 * Int.toFloat(w) {
      None
    } else {
      // cumulative mean normalised difference
      let d = Float64Array.fromLength(maxLag + 2)
      d->TypedArray.set(0, 1.)
      let total = ref(0.)
      for tau in 1 to maxLag + 1 {
        let sum = ref(0.)
        for j in 0 to w - 1 {
          let e = x->at(s + j) - x->at(s + j + tau)
          sum := sum.contents + e * e
        }
        total := total.contents + sum.contents
        d->TypedArray.set(tau, total.contents > 0. ? sum.contents * Int.toFloat(tau) / total.contents : 1.)
      }
      // the first dip under the threshold, followed to its bottom; else the deepest dip
      let found = ref(None)
      let tau = ref(minLag)
      while found.contents == None && tau.contents <= maxLag {
        if d->get64(tau.contents) < 0.15 {
          while tau.contents < maxLag && d->get64(tau.contents + 1) < d->get64(tau.contents) {
            tau := tau.contents + 1
          }
          found := Some(tau.contents)
        }
        tau := tau.contents + 1
      }
      let best = switch found.contents {
      | Some(tau) => Some(tau)
      | None =>
        let deepest = ref(minLag)
        for tau in minLag to maxLag {
          if d->get64(tau) < d->get64(deepest.contents) {
            deepest := tau
          }
        }
        d->get64(deepest.contents) < 0.4 ? Some(deepest.contents) : None
      }
      best->Option.map(tau => vertex(tau, d->get64(tau - 1), d->get64(tau), d->get64(tau + 1)))
    }
  }
}

// Sharpens a period by finding where the sample matches itself 'cycles' periods later, which
// is that many times as precise as the match one period on.
let refinePeriod = (x, ~start, ~period, ~cycles) => {
  let n = TypedArray.length(x)
  let lag = period * Int.toFloat(cycles)
  let w = Math.Int.max(16, Float.toInt(period))
  let reach = Math.Int.max(2, Math.Int.min(Float.toInt(Math.ceil(lag * 0.01)), Float.toInt(period / 3.)))
  let centre = Float.toInt(Math.round(lag))
  let (lo, hi) = (centre - reach - 1, centre + reach + 1)
  if start < 0 || start + w + hi >= n || lo < 1 {
    period
  } else {
    let diff = tau => {
      let sum = ref(0.)
      for j in 0 to w - 1 {
        let e = x->at(start + j) - x->at(start + j + tau)
        sum := sum.contents + e * e
      }
      sum.contents
    }
    let ds = Array.fromInitializer(~length=hi - lo + 1, i => diff(lo + i))
    let best = ref(1)
    for i in 1 to hi - lo - 1 {
      if ds->Array.getUnsafe(i) < ds->Array.getUnsafe(best.contents) {
        best := i
      }
    }
    let i = best.contents
    if i == 1 || i == hi - lo - 1 {
      // the bottom is at the edge of the search: keep the first estimate
      period
    } else {
      let d = Array.getUnsafe(ds, ...)
      vertex(lo + i, d(i - 1), d(i), d(i + 1)) / Int.toFloat(cycles)
    }
  }
}

let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

let noteName = hz => {
  let midi = 69. + 12. * Math.log2(hz / 440.)
  let m = Float.toInt(Math.round(midi))
  let cents = Float.toInt(Math.round((midi - Int.toFloat(m)) * 100.))
  let name = noteNames->Array.getUnsafe(mod(m, 12)) ++ Int.toString(m / 12 - 1)
  cents == 0 ? name : `${name} ${cents > 0 ? "+" : "−"}${Int.toString(Math.Int.abs(cents))} cents`
}

let seconds = (t, sample) => Float.toFixed(sample / t.audio.sampleRate, ~digits=2) ++ " s"

//==============================================================================
// Positions run from 0 to 1 over the sample: a wavetable's frames, or the middle of the part
// of a recording that's measured.

let frameAt = (count, position) =>
  Math.Int.max(0, Math.Int.min(count - 1, Float.toInt(Math.floor(position * Int.toFloat(count)))))

// Past the attack (the first 50 ms, or quarter of the sample), the first moment the sound is
// nearly at its loudest.
let defaultPosition = t =>
  switch t.kind {
  | Recording =>
    let attack = Math.Int.min(
      points / 4,
      Float.toInt(Math.ceil(0.05 * t.audio.sampleRate / Int.toFloat(length(t)) * Int.toFloat(points))),
    )
    let loudest = ref(0.)
    for j in attack to points - 1 {
      loudest := Math.max(loudest.contents, t.envelope->at(j))
    }
    let best = ref(attack)
    while t.envelope->at(best.contents) < 0.9 * loudest.contents {
      best := best.contents + 1
    }
    (Int.toFloat(best.contents) + 0.5) / Int.toFloat(points)
  | Cycle | Frames(_) => 0.
  }

let fromCycle = (t, ~start, ~n, ~detail) =>
  switch synthesise(spectrumOfCycle(t.audio.samples, ~start, ~n)) {
  | Some(wave) => Ok({wave, detail, from: Int.toFloat(start), length: Int.toFloat(n)})
  | None => Error(`${t.name} is silent there`)
  }

let analyse = (t, position) => {
  let x = t.audio.samples
  let n = length(t)
  switch t.kind {
  | Cycle => fromCycle(t, ~start=0, ~n, ~detail=`one cycle of ${Int.toString(n)} samples`)
  | Frames({size, count}) =>
    let f = frameAt(count, position)
    fromCycle(
      t,
      ~start=f * size,
      ~n=size,
      ~detail=`frame ${Int.toString(f + 1)} of ${Int.toString(count)}`,
    )
  | Recording =>
    let centre = Math.Int.max(0, Math.Int.min(n - 1, Float.toInt(position * Int.toFloat(n))))
    switch findPeriod(x, ~center=centre, ~sampleRate=t.audio.sampleRate) {
    | None =>
      // nothing periodic: a slice of about 23 ms, as one cycle
      let size = Math.Int.min(n, Float.toInt(t.audio.sampleRate / 43.))
      let start = Math.Int.max(0, Math.Int.min(centre - size / 2, n - size))
      fromCycle(t, ~start, ~n=size, ~detail=`no pitch at ${t->seconds(Int.toFloat(centre))}, a slice`)
    | Some(period) =>
      // about 60 ms of the sound, and at least two periods
      let fit = Float.toInt(Int.toFloat(n - 2) / period) - 1
      let cycles = Math.Int.max(
        2,
        Math.Int.min(
          Math.Int.min(24, fit),
          Float.toInt(Math.round(0.06 * t.audio.sampleRate / period)),
        ),
      )
      let span = period * Int.toFloat(cycles)
      let first = Math.max(0., Math.min(Int.toFloat(centre) - span / 2., Int.toFloat(n - 1) - span))
      let period = refinePeriod(x, ~start=Float.toInt(first), ~period, ~cycles)
      let span = period * Int.toFloat(cycles)
      let first = Math.max(0., Math.min(Int.toFloat(centre) - span / 2., Int.toFloat(n - 1) - span))
      let s = spectrumOfPeriods(x, ~start=first, ~period, ~cycles)
      align(s)
      let hz = t.audio.sampleRate / period
      switch synthesise(s) {
      | Some(wave) =>
        Ok({
          wave,
          detail: `${noteName(hz)} at ${t->seconds(Int.toFloat(centre))}`,
          from: first,
          length: span,
        })
      | None => Error(`${t.name} is silent there`)
      }
    }
  }
}

// An LFO shape: the volume envelope.
let envelope = t =>
  if t.envelope->TypedArray.some(v => v > 0.) {
    Ok({
      wave: TypedArray.copy(t.envelope),
      detail: `volume over ${t->seconds(Int.toFloat(length(t)))}`,
      from: 0.,
      length: Int.toFloat(length(t)),
    })
  } else {
    Error(`${t.name} is silent`)
  }
