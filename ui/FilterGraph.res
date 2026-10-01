// A picture of a filter type at its cutoff, resonance and morph, with a point to drag as in
// FabFilter's: across for the cutoff, up and down for the resonance. The voice filter (synth
// page) and the rack's filter (FX page) both show one.
//
// Most types are drawn as their frequency response, from analog prototypes of what
// dsp/Filter.cmajor runs; the ring modulator as the partials of a note moved to the sidebands;
// the diffusor and the reverb as their impulse responses, run here on the same networks. The
// pictures show what the knobs do; they are not measurements (drive and saturation aren't
// drawn).

open! Web
open! Complex

let pi = Math.Constants.pi
let sr = 48000.
let (clamp, db) = (FxDsp.clamp, FxDsp.db)

type view =
  // the gain at a frequency
  | Magnitude(float => float)
  // spectral lines: frequency, level (dB), and whether it is the input's
  | Lines(array<(float, float, bool)>)
  // an impulse response at `sr`, worked out when it is drawn
  | Impulse(unit => array<float>)

//==============================================================================
// responses

// The 2-pole state-variable responses at s = jf/fc: lowpass, bandpass (unity peak), highpass.
let svf = (hz: float, fc: float, q: float) => {
  let s = make(0., hz / fc)
  let den = add(add(mul(s, s), scale(s, 1. / q)), one)
  (div(one, den), div(scale(s, 1. / q), den), div(mul(s, s), den))
}

let onePole = (hz: float, fc: float) => div(one, make(1., hz / fc))

let morphMix = (lp, bp, hp, m: float) => {
  let lw = Math.max(0., 1. - 2. * m)
  let hw = Math.max(0., 2. * m - 1.)
  add(add(scale(lp, lw), scale(bp, 1. - lw - hw)), scale(hp, hw))
}

// A ladder of four one-pole stages with feedback k from the last, tapped after stage `tap`,
// with its level at DC put back to 1.
let ladder = (hz: float, fc: float, k: float, tap) => {
  let g = onePole(hz, fc)
  let h = div(pow(g, tap), add(one, scale(pow(g, 4), k)))
  scale(h, 1. +. k)
}

// A delay of d seconds at hz.
let delay = (hz: float, d: float) => expj(-2. * pi * hz * d)

// first-order allpasses at these frequencies
let allpasses = (hz: float, freqs: array<float>) =>
  expj(freqs->Array.reduce(0., (phase, f) => phase - 2. * Math.atan(hz / f)))

// Oatmeal's and Porridge's vowel formants (F1..F3 and levels) for A, E, I, O, U
let vowelF = [800., 1150., 2900., 400., 1600., 2700., 270., 2140., 2950., 450., 800., 2830., 325., 700., 2530.]
let vowelA = [1., 0.5, 0.1, 1., 0.35, 0.25, 1., 0.25, 0.12, 1., 0.4, 0.04, 1., 0.2, 0.03]
let femaleF = [850., 1220., 2810., 610., 2330., 2990., 310., 2790., 3310., 470., 1160., 2680., 370., 950., 2670.]
let femaleA = [1., 0.7, 0.35, 1., 0.6, 0.4, 1., 0.45, 0.4, 1., 0.5, 0.2, 1., 0.3, 0.15]

let formants = (hz: float, ~fc, ~morph, ~bands, ~female, ~q: float) => {
  let shift = clamp(fc / 1000., 0.25, 4.)
  let v = clamp(morph, 0., 1.) * 4.
  let vi = Math.Int.min(Float.toInt(v), 3)
  let vf = v - Int.toFloat(vi)
  let (fs, amps) = female ? (femaleF, femaleA) : (vowelF, vowelA)
  let at = (table, b) =>
    table->Array.getUnsafe(vi * 3 + b) * (1. - vf) + table->Array.getUnsafe(vi * 3 + 3 + b) * vf
  let sum = ref(female ? make(0.3, 0.) : make(0., 0.))
  for b in 0 to bands - 1 {
    let (_, bp, _) = svf(hz, at(fs, b) * shift, q)
    sum := add(sum.contents, scale(bp, at(amps, b)))
  }
  sum.contents
}

//==============================================================================
// the networks run here

// a fractional delay line read
let readAt = (line: array<float>, pos: int, d: float) => {
  let n = Array.length(line)
  let p = Int.toFloat(pos) - d
  let i = Float.toInt(Math.floor(p))
  let f = p - Int.toFloat(i)
  let at = k => line->Array.getUnsafe(mod(mod(k, n) + n, n))
  at(i) + f * (at(i + 1) - at(i))
}

// 58: six allpasses in series, from one cutoff period down
let diffusorImpulse = (~fc, ~res, ~morph) => {
  let period = clamp(sr / fc, 14., 428.)
  let g = 0.3 + 0.6 * res
  let n = 3000
  let ratios = [1., 0.77, 0.59, 0.43, 0.31, 0.23]
  let lines = ratios->Array.map(_ => Array.make(~length=1024, 0.))
  Array.fromInitializer(~length=n, i => {
    let x = i == 0 ? 1. : 0.
    let v = ref(x)
    ratios->Array.forEachWithIndex((r, k) => {
      let line = lines->Array.getUnsafe(k)
      let d = readAt(line, i, period * r)
      let w = v.contents + g * d
      line->Array.setUnsafe(mod(i, 1024), w)
      v := d - g * w
    })
    (1. - morph) * v.contents + morph * x
  })
}

// 59: four lines with a Hadamard matrix, damped, feeding back
let reverbImpulse = (~fc, ~res, ~morph) => {
  let period = clamp(sr / fc, 2., 302.)
  let fb = 0.97 * res
  let a = Math.exp(-2. * pi * 6000. / sr)
  let wetGain = 1.4 * Math.sqrt(1. - fb * fb)
  let ratios = [1., 1.187, 1.413, 1.677]
  // long enough for the tail to fall 60 dB, at most half a second
  let passes = fb > 0.01 ? Math.log(0.001) / Math.log(fb) : 2.
  let n = Float.toInt(clamp(passes * period * 1.4, 600., sr * 0.5))
  let lines = ratios->Array.map(_ => Array.make(~length=512, 0.))
  let lp = [0., 0., 0., 0.]
  Array.fromInitializer(~length=n, i => {
    let x = i == 0 ? 1. : 0.
    let d = ratios->Array.mapWithIndex((r, k) => readAt(lines->Array.getUnsafe(k), i, period * r))
    d->Array.forEachWithIndex((v, k) => lp->Array.setUnsafe(k, v + a * (lp->Array.getUnsafe(k) - v)))
    let l = Array.getUnsafe(lp, ...)
    let g = fb * 0.5
    let w = mod(i, 512)
    lines->Array.getUnsafe(0)->Array.setUnsafe(w, 0.5 * x + g * (l(0) + l(1) + l(2) + l(3)))
    lines->Array.getUnsafe(1)->Array.setUnsafe(w, -0.5 * x + g * (l(0) - l(1) + l(2) - l(3)))
    lines->Array.getUnsafe(2)->Array.setUnsafe(w, 0.5 * x + g * (l(0) + l(1) - l(2) - l(3)))
    lines->Array.getUnsafe(3)->Array.setUnsafe(w, -0.5 * x + g * (l(0) - l(1) - l(2) + l(3)))
    let dd = Array.getUnsafe(d, ...)
    let wet = (dd(0) - dd(1) + dd(2) - dd(3)) * 0.5 * wetGain
    (1. - morph) * wet + morph * x
  })
}

//==============================================================================

// Type t's picture at this cutoff (Hz), resonance and morph.
let view = (t, ~fc: float, ~res: float, ~morph: float): view => {
  let q = 0.5 + res * res * 20.
  let q4 = 0.5 + res * res * 6.
  let mag = f => Magnitude(hz => abs(f(hz)))
  let gain = Math.pow(10., ~exp=24. * res * (1. - 2. * morph) / 20.)
  let lp2 = (hz, q) => {
    let (l, _, _) = svf(hz, fc, q)
    l
  }
  let bp2 = (hz, q) => {
    let (_, b, _) = svf(hz, fc, q)
    b
  }
  let hp2 = (hz, q) => {
    let (_, _, h) = svf(hz, fc, q)
    h
  }
  let notch2 = (hz, q) => {
    let (l, _, h) = svf(hz, fc, q)
    add(l, h)
  }
  switch t {
  | 0 => Magnitude(_ => 1.)
  | 1 => mag(hz => onePole(hz, fc))
  | 4 => mag(hz => div(make(0., hz / fc), make(1., hz / fc)))
  | 2 | 11 => mag(hz => lp2(hz, q))
  | 19 => mag(hz => lp2(hz, 1. / (2. - 1.98 * res)))
  | 3 | 12 => mag(hz => mul(lp2(hz, q), lp2(hz, q)))
  | 5 => mag(hz => hp2(hz, q))
  | 6 => mag(hz => mul(hp2(hz, q), hp2(hz, q)))
  | 7 => mag(hz => bp2(hz, 0.5 + res))
  | 8 | 22 => mag(hz => bp2(hz, q))
  | 9 | 23 => mag(hz => mul(bp2(hz, q), bp2(hz, q)))
  | 10 | 26 => mag(hz => notch2(hz, 0.5 + res * 4.))
  | 27 => mag(hz => mul(notch2(hz, 0.5 + res * 4.), notch2(hz, 0.5 + res * 4.)))
  | 13 | 14 | 15 =>
    // Oatmeal's phasers: the allpass chain alone, its feedback the resonance
    let stages = t == 13 ? 4 : t == 14 ? 12 : 36
    let f90 = sr / pi * Math.atan(Int.toFloat(stages) * fc / sr)
    let freqs = Array.make(~length=stages, f90)
    mag(hz => {
      let a = allpasses(hz, freqs)
      div(a, add(one, scale(a, res)))
    })
  | 16 | 38 | 40 | 41 =>
    mag(hz => {
      let (l, b, h) = svf(hz, fc, q)
      morphMix(l, b, h, morph)
    })
  | 17 => mag(hz => ladder(hz, fc, 4.2 * res, 4))
  | 18 | 37 => mag(hz => ladder(hz, fc, 3.6 * res, 4))
  | 32 | 33 | 34 | 35 | 36 => mag(hz => ladder(hz, fc, 4.1 * res, t == 36 ? 4 : t - 31))
  | 39 => mag(hz => lp2(hz, 0.5 + res * res * 30.))
  | 20 =>
    let fb = res * 0.98 * (1. - 2. * morph)
    mag(hz => scale(div(one, add(one, scale(delay(hz, 1. / fc), -.fb))), 1. - 0.9 * Math.abs(fb)))
  | 42 | 43 =>
    let sign = t == 43 ? -1. : 1.
    let fb = 0.99 * res
    let a = Math.exp(-2. * pi * 500. * Math.pow(100., ~exp=1. - morph) / sr)
    let level = Math.sqrt(1. - fb * fb) * (1. + fb * a)
    mag(hz => {
      let damp = div(make(1. - a, 0.), add(one, scale(delay(hz, 1. / sr), -.a)))
      scale(div(one, add(one, scale(mul(damp, delay(hz, 1. / fc)), -.sign * fb))), level)
    })
  | 44 | 45 | 46 =>
    let sign = t == 46 ? -1. : 1.
    let fb = t == 44 ? 0. : 0.97 * res
    let g = t == 44 ? 0.25 + 0.75 * res : 1.
    let notched = (1. - morph) / Math.sqrt(1. + g * g / (1. - fb * fb))
    let wet = sign * morph * Math.sqrt(1. - fb * fb)
    mag(hz => {
      let e = delay(hz, 1. / fc)
      let d = div(e, add(one, scale(e, -.sign * fb)))
      add(scale(add(one, scale(d, sign * g)), notched), scale(d, wet))
    })
  | 47 | 48 | 49 =>
    let stages = t == 47 ? 4 : 8
    let fb = t == 47 ? 0.9 * res : t == 48 ? 0.97 * res : -0.97 * res
    let freqs = Array.fromInitializer(~length=stages, k => {
      let place = 2. * Int.toFloat(k) / Int.toFloat(stages - 1) - 1.
      fc * Math.pow(2., ~exp=morph * 2. * place)
    })
    mag(hz => {
      let a = allpasses(hz, freqs)
      scale(add(one, div(a, add(one, scale(a, -.fb)))), 0.5)
    })
  | 21 => mag(hz => formants(hz, ~fc, ~morph, ~bands=3, ~female=false, ~q=4. + 20. * res))
  | 50 => mag(hz => formants(hz, ~fc, ~morph, ~bands=2, ~female=false, ~q=5. + 15. * res))
  | 51 => mag(hz => formants(hz, ~fc, ~morph, ~bands=3, ~female=true, ~q=4. + 12. * res))
  | 52 => mag(hz => formants(hz, ~fc, ~morph, ~bands=3, ~female=false, ~q=8. + 32. * res))
  | 24 | 25 =>
    let boost = Math.pow(10., ~exp=24. * res / 20.) - 1.
    mag(hz => {
      let b = bp2(hz, q)
      add(one, scale(t == 25 ? mul(b, b) : b, boost))
    })
  | 28 =>
    mag(hz => {
      let (l, b, h) = svf(hz, fc, q4)
      let m = morphMix(l, b, h, morph)
      mul(m, m)
    })
  | 29 =>
    mag(hz => {
      let (l, _, h) = svf(hz, fc, q)
      add(scale(l, Math.min(1., 2. * (1. - morph))), scale(h, Math.min(1., 2. * morph)))
    })
  | 30 | 31 =>
    // the band slides from an octave below to an octave above, and peaks in the middle
    let centre = fc * Math.pow(2., ~exp=2. * morph - 1.)
    let peakness = 1. - Math.abs(2. * morph - 1.)
    mag(hz => {
      let (l, b, h) = svf(hz, centre, q)
      let edge = t == 30 ? b : add(l, h)
      let peak = add(one, scale(b, Math.pow(10., ~exp=12. * Math.max(res, 0.3) / 20.) - 1.))
      add(scale(edge, 1. - peakness), scale(peak, peakness))
    })
  | 53 => mag(hz => div(make(gain, hz / fc), make(1., hz / fc)))
  | 55 => mag(hz => div(make(1., gain * hz / fc), make(1., hz / fc)))
  | 54 => mag(hz => add(one, scale(bp2(hz, 1.4), gain - 1.)))
  | 56 =>
    // a 220 Hz note's partials, moved to the sum and difference with the carrier (and kept,
    // toward AM); a square carrier adds its third harmonic's sidebands
    let partials = Array.fromInitializer(~length=6, k => (220. * Int.toFloat(k + 1), -6. * Int.toFloat(k)))
    let ring = db(1. - res * 0.5) - 6.
    let third = db(morph) - 9.5
    let out = ((f: float, l: float)) => {
      let lines = [(f + fc, l + ring, false), (Math.abs(f - fc), l + ring, false)]
      let squares = morph > 0.05 ? [(f + 3. * fc, l + ring + third, false), (Math.abs(f - 3. * fc), l + ring + third, false)] : []
      let kept = res > 0.05 ? [(f, l + db(res * 0.5), false)] : []
      Array.concat(lines, Array.concat(squares, kept))
    }
    Lines(Array.concat(partials->Array.map(((f, l)) => (f, l, true)), partials->Array.flatMap(out)))
  | 57 =>
    // holding each sample for 1 / cutoff seconds: a sinc, and the smoothing lowpass
    let smooth = morph > 0. ? Some(fc * Math.pow(0.25, ~exp=morph)) : None
    Magnitude(
      hz => {
        let x = pi * hz / fc
        let sinc = x < 1e-6 ? 1. : Math.abs(Math.sin(x) / x)
        sinc * smooth->Option.mapOr(1., s => abs(onePole(hz, s)))
      },
    )
  | 58 => Impulse(() => diffusorImpulse(~fc, ~res, ~morph))
  | 59 => Impulse(() => reverbImpulse(~fc, ~res, ~morph))
  | _ => Magnitude(_ => 1.)
  }
}

// What it shows besides the curve.
let caption = t =>
  switch t {
  | 56 => "a 220 Hz note (dim) and what comes out: its partials moved by the carrier"
  | 57 => "holding samples at the cutoff rate; above half of it, the sound folds back down"
  | 58 => "the impulse response: one click smeared into many"
  | 59 => "the impulse response: a small space ringing"
  | t if t >= 20 && t <= 21 || t >= 42 && t <= 52 => "the response at the cutoff (the peaks follow the note with keytrack)"
  | _ => ""
  }

//==============================================================================
// the graph

type source = {
  typeOf: unit => int,
  // the cutoff parameter, and its value in Hz and back
  cutoff: string,
  toHz: float => float,
  ofHz: float => float,
  res: string,
  morph: string,
  drive: string,
  // the dry/wet mix, if any
  mix: option<string>,
  // L and R cutoffs apart, in semitones, if any
  spread: option<string>,
  // a second filter drawn dim (filter 2 when doubling): its type and cutoff
  second: unit => option<(int, float)>,
  // the parameters its picture also depends on
  alsoIds: array<string>,
}

let make = (ctx: Ctx.t, parent, box: box, src: source) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let g = FxGraph.make(ctx, parent, box)
  let layer = FxGraph.group(g.under)
  let (left, right, top) = (34., g.w - 10., 8.)
  let bottom = g.h - 16.
  let p: FxGraph.plot = {layer, left, right, top, bottom}
  let (lo, hi) = (-36., 24.)
  let xOfHz = FxGraph.xOfHz(p, _)
  let hzAt = FxGraph.hzAt(p, _)
  let yOfDb = v => FxGraph.yOf(p, v, lo, hi)
  let yOfRes = r => bottom - r * (bottom - top - 12.)
  let f1 = Float.toFixed(_, ~digits=1)

  let curve = (~cls, magnitude: float => float) => {
    let n = Float.toInt(right - left)
    let points = Array.fromInitializer(~length=n + 1, k => {
      let x = left + Int.toFloat(k)
      (x, yOfDb(db(magnitude(hzAt(x)))))
    })
    FxGraph.path(layer, ~cls)->FxGraph.setPath(Plots.pathFrom(points))
  }

  let drawView = (t, fc, ~cls, ~withMix) => {
    let res = get(src.res)
    let morph = get(src.morph)
    let mix = src.mix->Option.mapOr(1., get)
    let wet = (f, hz) => withMix ? mix * f(hz) + (1. - mix) : f(hz)
    switch view(t, ~fc, ~res, ~morph) {
    | Magnitude(f) => curve(~cls, wet(f, _))
    | Lines(lines) =>
      lines->Array.forEach(((hz, level, input)) =>
        if hz >= 20. && hz <= 20000. {
          let x = xOfHz(hz)
          FxGraph.line(layer, ~cls=input ? "mark" : "curve", x, bottom, x, yOfDb(level))
        }
      )
    | Impulse(h) =>
      // time across the whole graph, the amplitude up and down from the middle
      let h = h()
      let n = Array.length(h)
      let peak = h->Array.reduce(1e-9, (m, v) => Math.max(m, Math.abs(v)))
      let mid = (top + bottom) / 2.
      let half = (bottom - top) / 2. - 4.
      let columns = Float.toInt(right - left)
      let d = Array.fromInitializer(~length=columns, c => {
        let (a, b) = (c * n / columns, Math.Int.max((c + 1) * n / columns, c * n / columns + 1))
        let (mn, mx) = (ref(0.), ref(0.))
        for i in a to Math.Int.min(b, n) - 1 {
          let v = h->Array.getUnsafe(i) / peak
          mn := Math.min(mn.contents, v)
          mx := Math.max(mx.contents, v)
        }
        let x = left + Int.toFloat(c)
        `M${f1(x)} ${f1(mid - Math.sqrt(mx.contents) * half)}V${f1(mid + Math.sqrt(-.mn.contents) * half)}`
      })->Array.join("")
      FxGraph.path(layer, ~cls="impulse")->FxGraph.setPath(d)
      FxGraph.line(layer, ~cls="axis", left, mid, right, mid)
      let ms = Int.toFloat(n) / sr * 1000.
      FxGraph.text(layer, ~anchor="end", right, top + 10., `${f1(ms)} ms`)
      FxGraph.text(layer, left + 2., top + 10., "0")
    }
  }

  let draw = () => {
    layer->setTextContent("")
    let t = src.typeOf()
    let fc = src.toHz(get(src.cutoff))
    let impulse = switch view(t, ~fc, ~res=0., ~morph=0.) {
    | Impulse(_) => true
    | _ => false
    }
    p->FxGraph.frequencyLines(~labelY=g.h - 3., ~labels=!impulse, FxGraph.frequencies)
    if !impulse {
      p->FxGraph.levelLines(~lo, ~hi, [12., 0., -12., -24.])
    }
    src.second()->Option.forEach(((t2, fc2)) => drawView(t2, fc2, ~cls="curve dim", ~withMix=false))
    src.spread->Option.forEach(id => {
      let spread = get(id)
      if spread != 0. && !impulse {
        [-1., 1.]->Array.forEach(side =>
          drawView(t, fc * Math.pow(2., ~exp=side * spread / 24.), ~cls="curve dim", ~withMix=true)
        )
      }
    })
    drawView(t, fc, ~cls="curve", ~withMix=true)
    let x = xOfHz(fc)
    FxGraph.line(layer, ~cls="mark", x, top, x, bottom)
    let text = caption(t)
    if text != "" {
      FxGraph.text(layer, ~cls="tick", left + 6., impulse ? bottom - 6. : top + 10., text)
    }
  }

  // the point: across for the cutoff, up for the resonance. Where the resonance steadily raises
  // (or, for an EQ cutting, lowers) the response near the cutoff, the point sits on the curve
  // there: on a lowpass's resonant peak, and dragging it up finds the resonance that puts the
  // peak at the pointer. Elsewhere (notches, ring mod, the impulse responses) it uses a plain
  // resonance scale.
  let level = (fc, res) => {
    let t = src.typeOf()
    let morph = get(src.morph)
    switch view(t, ~fc, ~res, ~morph) {
    | Magnitude(f) =>
      let mix = src.mix->Option.mapOr(1., get)
      let cut = t >= 53 && t <= 55 && morph > 0.5
      let best = ref(cut ? 1000. : -1000.)
      for k in 0 to 40 {
        let hz = fc * Math.pow(2., ~exp=(Int.toFloat(k) / 40. - 0.5) * 1.2)
        let v = db(mix * f(hz) + (1. - mix))
        best := (cut ? Math.min(best.contents, v) : Math.max(best.contents, v))
      }
      Some(best.contents)
    | _ => None
    }
  }
  // whether the level moves one way as the resonance goes from 0 to 1, and which
  let direction = fc => {
    let levels = [0., 0.25, 0.5, 0.75, 1.]->Array.map(r => level(fc, r))
    switch (levels[0]->Option.flatMap(x => x), levels[4]->Option.flatMap(x => x)) {
    | (Some(a), Some(b)) if Math.abs(b - a) > 1. =>
      let up = b > a
      let steady = ref(true)
      for k in 1 to 4 {
        switch (levels[k - 1]->Option.flatMap(x => x), levels[k]->Option.flatMap(x => x)) {
        | (Some(x), Some(y)) if up ? y >= x - 0.05 : y <= x + 0.05 => ()
        | _ => steady := false
        }
      }
      steady.contents ? Some(up) : None
    | _ => None
    }
  }
  // the resonance that puts the level at `want` (dB)
  let resonanceFor = (fc, want, up) => {
    let rec bisect = (k, a: float, b: float) =>
      if k == 24 {
        (a + b) / 2.
      } else {
        let m = (a + b) / 2.
        let v = level(fc, m)->Option.getOr(0.)
        (up ? v < want : v > want) ? bisect(k + 1, m, b) : bisect(k + 1, a, m)
      }
    bisect(0, 0., 1.)
  }
  // on the curve, the point may rise past the scale's top to the graph's edge (half of it
  // clipped there), where the resonance is at its end: steep peaks go higher than the scale
  let yOfLevel = v => clamp(bottom - (v - lo) / (hi - lo) * (bottom - top), 0., bottom)
  let levelAt = y => lo + (bottom - y) / (bottom - top) * (hi - lo)
  let pointY = fc =>
    switch (direction(fc), level(fc, get(src.res))) {
    | (Some(_), Some(v)) => yOfLevel(v)
    | _ => yOfRes(get(src.res))
    }
  let hint = "Drag the point: across for the cutoff, up and down for the resonance; scroll for fine resonance, shift for fine steps, right-click to reset"
  let ids = [src.cutoff, src.res]
  // the resonance when the drag started
  let res0 = ref(0.)
  let point = FxGraph.handle(
    g,
    ~r=7.,
    ~ids,
    ~hot=false,
    ~start=() => res0 := get(src.res),
    ~drag=({x, y, dy}) => {
      model->ParamModel.set(src.cutoff, src.ofHz(hzAt(x)))
      let fc = src.toHz(get(src.cutoff))
      let res = switch direction(fc) {
      | Some(up) =>
        let y = clamp(y, 0., bottom)
        // at the edges, the resonance's end
        if y <= 0.5 {
          up ? 1. : 0.
        } else if y >= bottom - 0.5 {
          up ? 0. : 1.
        } else {
          resonanceFor(fc, levelAt(y), up)
        }
      | None => clamp(res0.contents - dy / (bottom - top - 12.), 0., 1.)
      }
      model->ParamModel.set(src.res, res)
    },
    ~wheel=src.res,
    ~hover=on => ctx.status->Status.show(on ? model->ParamModel.statusText(ids) : hint),
  )
  let place = () => {
    let fc = src.toHz(get(src.cutoff))
    let x = xOfHz(fc)
    let y = pointY(fc)
    point->FxGraph.place(x, y)
    g->FxGraph.readout(~x, ~y, `${FxGraph.hzText(src.toHz(get(src.cutoff)))} · ${FxGraph.short(g, src.res)}`)
  }

  let redraw = FxGraph.redraw(g, () => {
    draw()
    place()
  })
  model->ParamModel.listenEach(
    [src.cutoff, src.res, src.morph, src.drive, ...src.alsoIds]
    ->Array.concat(src.mix->Option.mapOr([], m => [m]))
    ->Array.concat(src.spread->Option.mapOr([], s => [s])),
    redraw.request,
  )
  redraw.now
}
