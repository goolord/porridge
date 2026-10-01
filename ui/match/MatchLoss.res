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
// then the 10 ms loudness envelopes' mean distance in dB, in units of 20 dB.
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

let compare = (w, target: Spectrum.features, c: Spectrum.features) =>
  if c.energy <= 1e-12 || target.energy <= 0. {
    silence
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
    let floorDb = Spectrum.db(maxOf(te)) - 60.
    let earlySteps = Float.toInt(earlySeconds * 100.)
    let (envSum, envWeight) = (ref(0.), ref(0.))
    for s in 0 to steps - 1 {
      let sw = s <= earlySteps ? w.early : 1.
      let a = Math.max(floorDb, Spectrum.db(te->get64(s)))
      let z = Math.max(floorDb, Spectrum.db(gain * ce->get64(s)))
      envSum := envSum.contents + sw * Math.abs(a - z)
      envWeight := envWeight.contents + sw
    }
    let envelope = envSum.contents / Math.max(envWeight.contents, 1e-30) / 20.
    spectral + w.envelope * envelope
  }

// A loss as the percentage the cards show: two takes of one plucked string come out near 85%,
// a string against a filtered saw near 60%, a string against a noise burst near 35%.
let scale = 1.

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
}

// One trial (plain JavaScript: this runs some fifty times a candidate).
let objectiveTrial: (objectiveData, Float64Array.t) => float = %raw(`(d, power) => {
  const last = power.length - 1;
  const at = j => power[j < last ? j : last];
  const steps = Math.min(d.te.length, d.fe.length);
  const stepPower = new Float64Array(steps);
  let energy = 0;
  for (let s = 0; s < steps; s++) {
    let p = 0;
    for (let j = s * d.stepMs; j < (s + 1) * d.stepMs; j++) p += at(j);
    p /= d.stepMs;
    stepPower[s] = p;
    energy += d.fe[s] * d.fe[s] * p;
  }
  const gain = Math.sqrt(d.targetEnergy / Math.max(energy * d.stepSamples, 1e-30));
  let spectral = 0;
  d.resolutions.forEach((r, ri) => {
    let num = 0, logSum = 0;
    const groups = r.first.length;
    for (let g = 0; g < groups; g++) {
      let p = 0;
      const first = r.first[g], a = r.sharesAt[g], b = r.sharesAt[g + 1];
      for (let k = a; k < b; k++) p += r.shares[k] * at(first + k - a);
      const s = gain * Math.sqrt(p);
      num += r.tt[g] - 2 * s * r.tz[g] + s * s * r.zz[g];
      if (ri === 0) {
        const ls = Math.log(Math.max(s, 1e-30));
        for (let k = g * d.bands; k < (g + 1) * d.bands; k++) {
          const z = ls + d.lz[k];
          logSum += d.bws[k] * Math.abs(d.la[k] - (z > d.logFloor ? z : d.logFloor));
        }
      }
    }
    spectral += r.rw * d.detail * Math.sqrt(Math.max(0, num) / Math.max(r.den, 1e-30));
    if (ri === 0) spectral += d.rwSum * d.detail * logSum / Math.max(d.logWeight, 1e-30) / 4;
  });
  let envSum = 0, envWeight = 0;
  for (let s = 0; s < steps; s++) {
    const sw = s <= d.earlySteps ? d.early : 1;
    const a = Math.max(d.floorDb, 20 * Math.log10(Math.max(d.te[s], 1e-9)));
    const z = Math.max(d.floorDb, 20 * Math.log10(Math.max(gain * d.fe[s] * Math.sqrt(stepPower[s]), 1e-9)));
    envSum += sw * Math.abs(a - z);
    envWeight += sw;
  }
  return spectral / Math.max(d.rwSum, 1e-30) + d.envelope * envSum / Math.max(envWeight, 1e-30) / 20;
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
    let first = Int32Array.fromLength(groups)
    let sharesAt = Int32Array.fromLength(groups + 1)
    let shares = []
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
      let members = Array.fromInitializer(~length=Math.Int.max(0, Math.Int.min(frames, (g + 1) * pool) - g * pool), k =>
        Int.toFloat((g * pool + k) * r.hop) * msPerSample
      )
      let from = Math.Int.max(0, Float.toInt(Math.floor(members[0]->Option.getOr(0.) - span / 2.)))
      let upto = Float.toInt(Math.ceil(members->Array.at(-1)->Option.getOr(0.) + span / 2.))
      let these = Array.make(~length=Math.Int.max(1, upto - from + 1), 0.)
      members->Array.forEach(centre => {
        let weights = these->Array.mapWithIndex((_, k) => {
          let x = (Int.toFloat(from + k) + 0.5 - (centre - span / 2.)) / span
          x <= 0. || x >= 1. ? 0. : Math.pow(Math.sin(Math.Constants.pi * x), ~exp=4.)
        })
        let sum = weights->Array.reduce(0., (s, v) => s + v)
        weights->Array.forEachWithIndex((v, k) =>
          these->Array.setUnsafe(k, these->Array.getUnsafe(k) + (sum > 0. ? v / sum : 0.) / Int.toFloat(Array.length(members)))
        )
      })
      first->setInt(g, from)
      these->Array.forEach(v => shares->Array.push(v))
      sharesAt->setInt(g + 1, Array.length(shares))
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
      "shares": Float64Array.fromArray(shares),
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
  }
  power => objectiveTrial(data, power)
}
