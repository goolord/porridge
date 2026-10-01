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
