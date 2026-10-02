// How far a candidate's render is from the target, from their measurements (Spectrum.res).
// At each resolution, frame by frame:
//
//   timbre  the difference between the log band levels, taken as a cepstrum (its DCT) and kept
//           to the first coefficients: the shape of the spectrum, without the fine detail
//           that two takes of one instrument differ in (two plucks of a string with different
//           noise in them differ by 0.15, a string and a filtered saw by 0.45); its mean, in
//           units of 6 dB, over frames weighted by how loud the target is in them;
//   detail  the band levels as they are: spectral convergence (the relative size of their
//           difference) plus the mean distance between their logs (in units of 4 nepers),
//           which only a patch the synth can make exactly brings to nothing; it counts a tenth;
//
// then the 10 ms loudness envelopes' mean distance in dB, in units of 20 dB, each step weighed by
// how loud the louder of the two is there (a step 60 dB under the target's loudest counts a
// tenth: a tail's last whisper is heard less than its body);
//
//   grid    (with a pitch) what lies between the harmonics against them, band by band
//           (Spectrum.measureGrid): the mean distance in dB, in units of 20 dB, over frames
//           weighted by how loud the target is in them and bands by how loud they are in it;
//           noise, unison's detuning and a rough recording show here where the bands can't
//           tell them from more harmonic level;
//   fine    (with a pitch) the fine spectrum (Spectrum.measureGrid): the power at every sixteenth
//           of a harmonic of the target's pitch, frame by frame, in dB (smoothed over three
//           sixteenths, floored 60 dB under the target's loudest), the mean distance in units of
//           20 dB, weighted by how loud the target is there: a candidate out of tune, with its
//           partials a hair off the sample's, or with noise where the sample's pitch wavers,
//           is heard here;
//   width   (for a stereo target) side against mid every 10 ms (as a ratio of their levels: a
//           little width, 20 dB under, counts little against none; unison's, a few dB under,
//           much), the mean distance over the steps weighted as the timbre's frames are.
//
// The candidate is first brought to the target's overall loudness, so only the shape of the
// sound counts, not how loud the patch is. Levels more than 70 dB under the target's loudest
// band (60 dB for the envelope) count as that floor, so silence doesn't weigh like sound.
// The weights let each search (MatchSearch.islands) care more about the attack, the tone or
// the treble; `standard` is what every card's match percentage is worked out with.

@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external setInt: (Int32Array.t, int, int) => unit = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

type weights = {
  // the envelope term against the spectral ones
  envelope: float,
  // how much more the first 150 ms count
  early: float,
  // how much more bands above 2 kHz count in the detail
  treble: float,
  // per resolution (Spectrum.resolutions: long, middle, short)
  resolutions: array<float>,
}

let standard = {envelope: 0.5, early: 1., treble: 1., resolutions: [1., 1., 1.]}

let earlySeconds = 0.15
let detailWeight = 0.1
// The broad spectrum counts for half, and the harmonics' grid and fine structure for more:
// the key EQ fitted to every candidate makes the broad balance easy to get right, so that a
// patch with the wrong partials (a second oscillator's, or the sidebands that blend two) could
// otherwise win on it; ears hear the partials first. (Synplant's own patch for a two-oscillator
// sample, against matches that got its balance closer and its partials less so, ranks as heard
// only with these.)
let spectralWeight = 0.5
let gridWeight = 0.6
let fineWeight = 1.2
let widthWeight = 0.4
// a difference in the grid counts at most this many dB
let gridCap = 30.
// the envelope's steps: how far under the loudest one counts least, and how little
let envelopeRange = 60.
let envelopeLeast = 0.1
let silence = 10.
// a frame this far under the target's loudest counts least
let quietRange = 50.
// dB per neper (20 / ln 10)
let dbPerNeper = 8.685889638065035

let maxOf = (a: Float64Array.t) => {
  let m = ref(0.)
  a->TypedArray.forEach(v => m := Math.max(m.contents, v))
  m.contents
}

// The loss's terms, each weighted: (spectral, envelope, grid, fine, width).
let terms = (w, target: Spectrum.features, c: Spectrum.features) =>
  if c.energy <= 1e-12 || target.energy <= 0. {
    (silence, 0., 0., 0., 0.)
  } else {
    let gain = Math.sqrt(target.energy / c.energy)
    let total = ref(0.)
    let weightSum = ref(0.)
    Spectrum.resolutions->Array.forEachWithIndex((r, ri) => {
      let rw = w.resolutions[ri]->Option.getOr(1.)
      let t = target.spectra->Array.getUnsafe(ri)
      let cs = c.spectra->Array.getUnsafe(ri)
      let frames = Math.Int.min(TypedArray.length(t), TypedArray.length(cs)) / r.bands
      let floor = Math.max(1e-9, maxOf(t) * 3e-4)
      let logFloor = Math.log(floor)
      let earlyFrames = Float.toInt(earlySeconds * Spectrum.sampleRate) / (r.hop * target.pools->Array.getUnsafe(ri))

      // each target frame's loudness, dB, and the loudest
      let loudness = Float64Array.fromLength(frames)
      let loudest = ref(neg_infinity)
      for f in 0 to frames - 1 {
        let p = ref(0.)
        for b in 0 to r.bands - 1 {
          let a = t->get64(f * r.bands + b)
          p := p.contents + a * a
        }
        let l = 10. * Math.log10(Math.max(p.contents / Int.toFloat(r.bands), 1e-30))
        loudness->set64(f, l)
        loudest := Math.max(loudest.contents, l)
      }

      let diff = Float64Array.fromLength(r.bands)
      let (timbre, timbreWeight) = (ref(0.), ref(0.))
      let (num, den, logSum, logWeight) = (ref(0.), ref(0.), ref(0.), ref(0.))
      for f in 0 to frames - 1 {
        let fw = f <= earlyFrames ? w.early : 1.
        for b in 0 to r.bands - 1 {
          let bw = r.centres->get64(b) > 2000. ? fw * w.treble : fw
          let a = t->get64(f * r.bands + b)
          let z = gain * cs->get64(f * r.bands + b)
          let d = a - z
          num := num.contents + bw * d * d
          den := den.contents + bw * a * a
          let la = a > floor ? Math.log(a) : logFloor
          let lz = z > floor ? Math.log(z) : logFloor
          logSum := logSum.contents + bw * Math.abs(la - lz)
          logWeight := logWeight.contents + bw
          diff->set64(b, (la - lz) * dbPerNeper)
        }
        // the difference's cepstrum, dB
        let sum = ref(0.)
        for k in 0 to r.cepstra - 1 {
          let ck = ref(0.)
          for b in 0 to r.bands - 1 {
            ck := ck.contents + diff->get64(b) * r.cosines->get64(k * r.bands + b)
          }
          sum := sum.contents + Math.abs(ck.contents)
        }
        let distance = sum.contents * 2. / Int.toFloat(r.bands * r.cepstra)
        let lw =
          fw *
          Math.max(0.02, Math.min(1., (loudness->get64(f) - (loudest.contents - quietRange)) / quietRange))
        timbre := timbre.contents + lw * distance
        timbreWeight := timbreWeight.contents + lw
      }
      let convergence = Math.sqrt(num.contents / Math.max(den.contents, 1e-30))
      let logDistance = logSum.contents / Math.max(logWeight.contents, 1e-30) / 4.
      let timbre = timbre.contents / Math.max(timbreWeight.contents, 1e-30) / 6.
      total := total.contents + rw * (timbre + detailWeight * (convergence + logDistance))
      weightSum := weightSum.contents + rw
    })
    let spectral = total.contents / Math.max(weightSum.contents, 1e-30)

    let te = target.envelope
    let ce = c.envelope
    let steps = Math.Int.min(TypedArray.length(te), TypedArray.length(ce))
    let topDb = Spectrum.db(maxOf(te))
    let floorDb = topDb - 60.
    let earlySteps = Float.toInt(earlySeconds * 100.)
    let (envSum, envWeight) = (ref(0.), ref(0.))
    for s in 0 to steps - 1 {
      let sw = s <= earlySteps ? w.early : 1.
      let a = Math.max(floorDb, Spectrum.db(te->get64(s)))
      let z = Math.max(floorDb, Spectrum.db(gain * ce->get64(s)))
      let lw = Math.max(envelopeLeast, Math.min(1., (Math.max(a, z) - (topDb - envelopeRange)) / envelopeRange))
      envSum := envSum.contents + sw * lw * Math.abs(a - z)
      envWeight := envWeight.contents + sw * lw
    }
    let envelope = envSum.contents / Math.max(envWeight.contents, 1e-30) / 20.

    // the harmonic grid
    let grid = switch (target.grid, c.grid) {
    | (Some(tg), Some(cg)) =>
      let bands = Spectrum.gridBands
      let frames = Math.Int.min(tg.frames, cg.frames)
      let frameLevel = f => {
        let p = ref(0.)
        for b in 0 to bands - 1 {
          p := p.contents + Math.pow(10., ~exp=tg.level->get64(f * bands + b) / 10.)
        }
        10. * Math.log10(Math.max(p.contents, 1e-30))
      }
      let levels = Array.fromInitializer(~length=frames, frameLevel)
      let top = levels->Array.reduce(neg_infinity, Math.max)
      let (sum, weight) = (ref(0.), ref(0.))
      for f in 0 to frames - 1 {
        let fw = Math.max(0.02, Math.min(1., (levels->Array.getUnsafe(f) - (top - quietRange)) / quietRange))
        let loudest = ref(neg_infinity)
        for b in 0 to bands - 1 {
          loudest := Math.max(loudest.contents, tg.level->get64(f * bands + b))
        }
        for b in 0 to bands - 1 {
          let (a, z) = (tg.ratio->get64(f * bands + b), cg.ratio->get64(f * bands + b))
          let bw = fw * Math.max(0., Math.min(1., (tg.level->get64(f * bands + b) - (loudest.contents - 40.)) / 40.))
          if !Float.isNaN(a) && !Float.isNaN(z) && bw > 0. {
            sum := sum.contents + bw * Math.min(gridCap, Math.abs(a - z))
            weight := weight.contents + bw
          }
        }
      }
      weight.contents > 0. ? sum.contents / weight.contents / 20. : 0.
    | _ => 0.
    }

    // the fine spectrum
    let fine = switch (target.grid, c.grid) {
    | (Some(tg), Some(cg)) if tg.fineCells == cg.fineCells =>
      let cells = tg.fineCells
      let frames = Math.Int.min(tg.frames, cg.frames)
      let power = gain * gain
      let rows = (g: Spectrum.grid, scale) =>
        Float64Array.fromLength(frames * cells)->TypedArray.mapWithIndex((_, i) =>
          10. * Math.log10(Math.max(scale * g.fine->get64(i), 1e-30))
        )
      let (a, z) = (rows(tg, 1.), rows(cg, power))
      let top = maxOf(a)
      let smooth = (m: Float64Array.t, f, k) => {
        let at = j => Math.max(top - 60., m->get64(f * cells + Math.Int.max(0, Math.Int.min(cells - 1, j))))
        0.25 * at(k - 1) + 0.5 * at(k) + 0.25 * at(k + 1)
      }
      let (sum, weight) = (ref(0.), ref(0.))
      for f in 0 to frames - 1 {
        for k in 0 to cells - 1 {
          let (x, y) = (smooth(a, f, k), smooth(z, f, k))
          let w = Math.max(0., Math.min(1., (x - (top - 50.)) / 50.))
          sum := sum.contents + w * Math.abs(x - y)
          weight := weight.contents + w
        }
      }
      weight.contents > 0. ? sum.contents / weight.contents / 20. : 0.
    | _ => 0.
    }

    // the width
    let width = switch (target.side, c.side) {
    | (Some(ts), side) =>
      let n = Math.Int.min(steps, TypedArray.length(ts))
      let (sum, weight) = (ref(0.), ref(0.))
      for s in 0 to n - 1 {
        let m = te->get64(s)
        let ratio = (side, mid) => mid > 1e-9 ? Math.min(1., side / mid) : 0.
        let a = ratio(ts->get64(s), m)
        let z = side->Option.mapOr(0., cs => ratio(cs->get64(s), ce->get64(s)))
        let lw = Math.max(0.02, Math.min(1., (Spectrum.db(m) - (topDb - quietRange)) / quietRange))
        sum := sum.contents + lw * Math.abs(a - z)
        weight := weight.contents + lw
      }
      weight.contents > 0. ? sum.contents / weight.contents : 0.
    | (None, _) => 0.
    }
    (spectralWeight * spectral, w.envelope * envelope, gridWeight * grid, fineWeight * fine, widthWeight * width)
  }

let compare = (w, target, c) => {
  let (spectral, envelope, grid, fine, width) = terms(w, target, c)
  spectral + envelope + grid + fine + width
}

// A loss as the percentage the cards show: two takes of one plucked string come out near 85%,
// a string against a filtered saw near 60%, a string against a noise burst near 35%.
let scale = 1.3

let similarity = loss => 100. * Math.exp(-.loss / scale)

// The loss as a function of an amp envelope put on a flat render's measurements
// (MatchSearch.shaped), for fitting the envelope. The envelope comes as its power (square) at
// the middle of each millisecond. The parts the envelope moves are worked out from sums kept
// per frame, and each frame's share of the envelope from weights kept per millisecond (its
// window squared, as Spectrum.windowPower weighs it), so a trial costs a few thousand
// operations rather than a comparison: the envelope term, and the detail terms (the band
// levels' difference, and their logs' with the floor, from the long spectra only, which move
// with the envelope much as the others' do). The timbre term (the cepstrum of the log levels'
// difference) barely moves with a level that is the same across a frame's bands, and is left
// out. For choosing between envelopes, not for scoring.

// What a trial needs, in flat arrays: per resolution, each pooled frame's first millisecond,
// its shares (from sharesAt), its level sums (target², target × flat, flat², band-weighted);
// the long spectra's logs and band weights; and the steps' loudness.
type objectiveData = {
  resolutions: array<{
    "first": Int32Array.t,
    "sharesAt": Int32Array.t,
    "shares": Float64Array.t,
    "tt": Float64Array.t,
    "tz": Float64Array.t,
    "zz": Float64Array.t,
    "den": float,
    "rw": float,
  }>,
  bands: int,
  la: Float64Array.t,
  lz: Float64Array.t,
  bws: Float64Array.t,
  logFloor: float,
  logWeight: float,
  rwSum: float,
  targetEnergy: float,
  te: Float64Array.t,
  fe: Float64Array.t,
  stepMs: int,
  earlySteps: int,
  early: float,
  envelope: float,
  floorDb: float,
  detail: float,
  stepSamples: float,
  envelopeRange: float,
  envelopeLeast: float,
}

// One trial (plain JavaScript: this runs some fifty times a candidate).
let objectiveTrial: (objectiveData, Float64Array.t) => float = %raw(`(d, power) => {
  const last = power.length - 1;
  const steps = Math.min(d.te.length, d.fe.length), stepMs = d.stepMs, fe = d.fe;
  const stepPower = new Float64Array(steps);
  let energy = 0;
  for (let s = 0; s < steps; s++) {
    let p = 0;
    const end = Math.min((s + 1) * stepMs, last + 1);
    for (let j = s * stepMs; j < end; j++) p += power[j];
    for (let j = Math.max(end, s * stepMs); j < (s + 1) * stepMs; j++) p += power[last];
    p /= stepMs;
    stepPower[s] = p;
    energy += fe[s] * fe[s] * p;
  }
  const gain = Math.sqrt(d.targetEnergy / Math.max(energy * d.stepSamples, 1e-30));
  let spectral = 0;
  const resolutions = d.resolutions;
  for (let ri = 0; ri < resolutions.length; ri++) {
    const r = resolutions[ri];
    const firsts = r.first, at = r.sharesAt, shares = r.shares, tt = r.tt, tz = r.tz, zz = r.zz;
    const groups = firsts.length;
    let num = 0, logSum = 0;
    for (let g = 0; g < groups; g++) {
      let p = 0;
      const a = at[g], b = at[g + 1], offset = firsts[g] - a;
      const whole = Math.min(b, last - offset + 1);
      for (let k = a; k < whole; k++) p += shares[k] * power[offset + k];
      for (let k = Math.max(a, whole); k < b; k++) p += shares[k] * power[last];
      const s = gain * Math.sqrt(p);
      num += tt[g] - 2 * s * tz[g] + s * s * zz[g];
      if (ri === 0) {
        const ls = Math.log(Math.max(s, 1e-30)), la = d.la, lz = d.lz, bws = d.bws, floor = d.logFloor;
        for (let k = g * d.bands, end = (g + 1) * d.bands; k < end; k++) {
          const z = ls + lz[k];
          const diff = la[k] - (z > floor ? z : floor);
          logSum += bws[k] * (diff < 0 ? -diff : diff);
        }
      }
    }
    spectral += r.rw * d.detail * Math.sqrt(Math.max(0, num) / Math.max(r.den, 1e-30));
    if (ri === 0) spectral += d.rwSum * d.detail * logSum / Math.max(d.logWeight, 1e-30) / 4;
  }
  let envSum = 0, envWeight = 0;
  const topDb = d.floorDb + 60, range = d.envelopeRange, least = d.envelopeLeast;
  for (let s = 0; s < steps; s++) {
    const sw = s <= d.earlySteps ? d.early : 1;
    const a = Math.max(d.floorDb, 20 * Math.log10(Math.max(d.te[s], 1e-9)));
    const z = Math.max(d.floorDb, 20 * Math.log10(Math.max(gain * d.fe[s] * Math.sqrt(stepPower[s]), 1e-9)));
    const lw = Math.max(least, Math.min(1, ((a > z ? a : z) - (topDb - range)) / range));
    envSum += sw * lw * Math.abs(a - z);
    envWeight += sw * lw;
  }
  return spectral / Math.max(d.rwSum, 1e-30) + d.envelope * envSum / Math.max(envWeight, 1e-30) / 20;
}`)

// Each pooled frame's shares of the envelope's milliseconds: the frames' windows squared
// (sin⁴), each frame's adding to 1, averaged over the frames pooled; as (first millisecond per
// frame, where each frame's shares start, the shares).
let frameShares: (int, int, int, int, float) => (Int32Array.t, Int32Array.t, Float64Array.t) = %raw(`(groups, pool, frames, hop, span) => {
  const msPerSample = 1000 / 44100;
  const first = new Int32Array(groups), at = new Int32Array(groups + 1);
  const out = [];
  for (let g = 0; g < groups; g++) {
    const count = Math.max(0, Math.min(frames, (g + 1) * pool) - g * pool);
    const c0 = g * pool * hop * msPerSample, c1 = (g * pool + Math.max(0, count - 1)) * hop * msPerSample;
    const from = Math.max(0, Math.floor(c0 - span / 2)), upto = Math.ceil(c1 + span / 2);
    const n = Math.max(1, upto - from + 1);
    const these = new Float64Array(n);
    for (let m = 0; m < count; m++) {
      const start = (g * pool + m) * hop * msPerSample - span / 2;
      let sum = 0;
      const w = new Float64Array(n);
      for (let k = 0; k < n; k++) {
        const x = (from + k + 0.5 - start) / span;
        if (x > 0 && x < 1) { const s = Math.sin(Math.PI * x); w[k] = s * s * s * s; sum += w[k]; }
      }
      if (sum > 0) for (let k = 0; k < n; k++) these[k] += w[k] / sum / count;
    }
    first[g] = from;
    for (let k = 0; k < n; k++) out.push(these[k]);
    at[g + 1] = out.length;
  }
  return [first, at, Float64Array.from(out)];
}`)

let envelopeObjective = (w: weights, target: Spectrum.features, flat: Spectrum.features) => {
  let msPerSample = 1000. / Spectrum.sampleRate
  let longBands = ref(0)
  let (la, lz, bws, logFloor, logWeight) = (ref(Float64Array.fromLength(0)), ref(Float64Array.fromLength(0)), ref(Float64Array.fromLength(0)), ref(0.), ref(0.))
  let resolutions = Spectrum.resolutions->Array.mapWithIndex((r, ri) => {
    let t = target.spectra->Array.getUnsafe(ri)
    let z = flat.spectra->Array.getUnsafe(ri)
    let pool = flat.pools->Array.getUnsafe(ri)
    let groups = Math.Int.min(TypedArray.length(t), TypedArray.length(z)) / r.bands
    let frames = Spectrum.frameCount(r, flat.length)
    let floor = Math.max(1e-9, maxOf(t) * 3e-4)
    let earlyFrames = Float.toInt(earlySeconds * Spectrum.sampleRate) / (r.hop * target.pools->Array.getUnsafe(ri))
    let span = Int.toFloat(r.size) * msPerSample
    let (first, sharesAt, shares) = frameShares(groups, pool, frames, r.hop, span)
    let (tt, tz, zz) = (Float64Array.fromLength(groups), Float64Array.fromLength(groups), Float64Array.fromLength(groups))
    let den = ref(0.)
    if ri == 0 {
      longBands := r.bands
      la := Float64Array.fromLength(groups * r.bands)
      lz := Float64Array.fromLength(groups * r.bands)
      bws := Float64Array.fromLength(groups * r.bands)
      logFloor := Math.log(floor)
    }
    for g in 0 to groups - 1 {
      let fw = g <= earlyFrames ? w.early : 1.
      for b in 0 to r.bands - 1 {
        let bw = r.centres->get64(b) > 2000. ? fw * w.treble : fw
        let (a, c) = (t->get64(g * r.bands + b), z->get64(g * r.bands + b))
        tt->set64(g, tt->get64(g) + bw * a * a)
        tz->set64(g, tz->get64(g) + bw * a * c)
        zz->set64(g, zz->get64(g) + bw * c * c)
        den := den.contents + bw * a * a
        if ri == 0 {
          let k = g * r.bands + b
          la.contents->set64(k, a > floor ? Math.log(a) : Math.log(floor))
          lz.contents->set64(k, Math.log(Math.max(c, 1e-30)))
          bws.contents->set64(k, bw)
          logWeight := logWeight.contents + bw
        }
      }
    }
    {
      "first": first,
      "sharesAt": sharesAt,
      "shares": shares,
      "tt": tt,
      "tz": tz,
      "zz": zz,
      "den": den.contents,
      "rw": w.resolutions[ri]->Option.getOr(1.),
    }
  })
  let data = {
    resolutions,
    bands: longBands.contents,
    la: la.contents,
    lz: lz.contents,
    bws: bws.contents,
    logFloor: logFloor.contents,
    logWeight: logWeight.contents,
    rwSum: resolutions->Array.reduce(0., (s, r) => s + r["rw"]),
    targetEnergy: target.energy,
    te: target.envelope,
    fe: flat.envelope,
    stepMs: Float.toInt(Math.round(Int.toFloat(Spectrum.envelopeStep) * msPerSample)),
    earlySteps: Float.toInt(earlySeconds * 100.),
    early: w.early,
    envelope: w.envelope,
    floorDb: Spectrum.db(maxOf(target.envelope)) - 60.,
    detail: detailWeight,
    stepSamples: Int.toFloat(Spectrum.envelopeStep),
    envelopeRange,
    envelopeLeast,
  }
  power => objectiveTrial(data, power)
}
