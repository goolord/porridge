// The amp envelope that best follows a sample's loudness, for the sound matcher's starting
// point (Genome.seed). The synth's envelope (dsp/Modulation.cmajor, renderAmp) is worked out
// here at each 10 ms step instead of rendered: a linear attack shaped (2 - L) L, an exponential
// decay 1 to the breakpoint, an exponential decay 2 from there to the sustain level, each
// level through the envelope's cubic. Its stages are moved (Nelder-Mead, in the genes' own
// 0..1 terms) until its level in dB is as near the sample's as it gets.

@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

type stages = {attackMs: float, decay1Ms: float, breakpoint: float, decay2Ms: float, sustain: float}

let envCubic = (l: float, lo: float, hi: float) =>
  (-2. * l * l * l + 3. * (lo + hi) * l * l - 6. * lo * hi * l + (lo + hi) * lo * hi) /
    Math.max((hi - lo) * (hi - lo), 1e-8)

// The envelope's level at t ms after the note starts.
let level = (s: stages, t) => {
  let bp = s.breakpoint > 0.998 ? 1. : Math.max(s.breakpoint, 1e-4)
  let sus = Math.max(s.sustain, 1e-4)
  if t < s.attackMs {
    let l = t / s.attackMs
    (2. - l) * l
  } else {
    let t = t - s.attackMs
    let (t, after1) = if bp < 1. {
      t < s.decay1Ms ? (t, false) : (t - s.decay1Ms, true)
    } else {
      (t, true)
    }
    if !after1 {
      envCubic(Math.pow(bp, ~exp=t / s.decay1Ms), bp, 1.)
    } else if t < s.decay2Ms && Math.abs(sus - bp) > 1e-6 {
      envCubic(bp * Math.pow(sus / bp, ~exp=t / s.decay2Ms), Math.min(sus, bp), Math.max(sus, bp))
    } else {
      s.sustain < 0.001 ? 0. : sus
    }
  }
}

// How far the envelope is from a loudness curve (dB at each 10 ms step, the loudest 0): the
// mean distance in dB once the envelope is brought to the level that suits it best, with
// both held above `floor`.
let distance = (s: stages, target: array<float>, ~floor) => {
  let n = Array.length(target)
  let diffs = Array.fromInitializer(~length=n, i => {
    let y = level(s, (Int.toFloat(i) + 0.5) * 10.)
    20. * Math.log10(Math.max(y, 1e-6))
  })
  // the gain: the mean difference over the steps the sample is loud in
  let (sum, count) = (ref(0.), ref(0))
  target->Array.forEachWithIndex((a, i) =>
    if a > floor + 20. {
      sum := sum.contents + a - diffs->Array.getUnsafe(i)
      count := count.contents + 1
    }
  )
  let gain = count.contents > 0 ? sum.contents / Int.toFloat(count.contents) : 0.
  let total = ref(0.)
  target->Array.forEachWithIndex((a, i) => {
    let z = Math.max(floor, diffs->Array.getUnsafe(i) + gain)
    total := total.contents + Math.abs(Math.max(floor, a) - z)
  })
  total.contents / Int.toFloat(Math.Int.max(1, n))
}

// Nelder-Mead over points in 0..1 (each coordinate clamped): the best point found.
let minimize = (f: Float64Array.t => float, start: Float64Array.t, ~step, ~iterations) => {
  let n = TypedArray.length(start)
  let clamp = (x: Float64Array.t) => {
    for i in 0 to n - 1 {
      x->set64(i, Math.max(0., Math.min(1., x->get64(i))))
    }
    x
  }
  let points = Array.fromInitializer(~length=n + 1, k => {
    let x = TypedArray.copy(start)
    if k > 0 {
      let i = k - 1
      x->set64(i, x->get64(i) > 0.5 ? x->get64(i) - step : x->get64(i) + step)
    }
    let x = clamp(x)
    (x, f(x))
  })
  let along = (a: Float64Array.t, b: Float64Array.t, t) =>
    clamp(Float64Array.fromLength(n)->TypedArray.mapWithIndex((_, i) => a->get64(i) + t * (b->get64(i) - a->get64(i))))
  for _ in 1 to iterations {
    points->Array.sort(((_, a), (_, b)) => Float.compare(a, b))
    let (worst, fw) = points->Array.getUnsafe(n)
    let (_, fb) = points->Array.getUnsafe(0)
    let (_, fs) = points->Array.getUnsafe(n - 1)
    let centre = Float64Array.fromLength(n)
    for k in 0 to n - 1 {
      let (x, _) = points->Array.getUnsafe(k)
      for i in 0 to n - 1 {
        centre->set64(i, centre->get64(i) + x->get64(i) / Int.toFloat(n))
      }
    }
    let reflected = along(worst, centre, 2.)
    let fr = f(reflected)
    if fr < fb {
      let expanded = along(worst, centre, 3.)
      let fe = f(expanded)
      points->Array.setUnsafe(n, fe < fr ? (expanded, fe) : (reflected, fr))
    } else if fr < fs {
      points->Array.setUnsafe(n, (reflected, fr))
    } else {
      let contracted = along(worst, centre, fr < fw ? 1.5 : 0.5)
      let fc = f(contracted)
      if fc < Math.min(fr, fw) {
        points->Array.setUnsafe(n, (contracted, fc))
      } else {
        // shrink towards the best
        let (best, _) = points->Array.getUnsafe(0)
        for k in 1 to n {
          let (x, _) = points->Array.getUnsafe(k)
          let y = along(best, x, 0.5)
          points->Array.setUnsafe(k, (y, f(y)))
        }
      }
    }
  }
  points->Array.sort(((_, a), (_, b)) => Float.compare(a, b))
  points->Array.getUnsafe(0)
}
