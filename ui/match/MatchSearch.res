// The sound matcher's searches. A match first finds the sound's outline once, then four
// searches go on from it side by side, each after a different kind of match, so that the
// four cards differ in kind rather than being four takes on one answer:
//
//   Detailed  every gene free, the standard loss: the closest the match gets
//   Simple    one oscillator (and noise) through the filter, with its envelopes: a patch
//             that is easy to take further by hand
//   Punchy    the attack weighs most (the first 150 ms, the envelope, the short spectra), dry
//   Lush      the tone weighs most (the long spectra), with unison, chorus and reverb
//
// The outline (`outline`): the starting point (Genome.seed, or the patches the predictor
// suggests: MatchModel.res) with every first oscillator wave and filter type, played an octave
// either side too; then the best few structures each get a short CMA-ES (Cmaes.res) over the
// core genes, the better half of them going on each round (successive halving), until one is
// left, and its best is polished (as below) over every gene that makes a difference to it.
// Most of what the cards end up sharing is found once, with most of the renders.
//
// Then each search (`branch`) tries the outline's best few structures, held within its own
// bounds and scored its own way, and polishes the best of them: one gene at a time, either
// way, while that helps. Each but Detailed keeps away from the ones before it in `rivals`
// (niching: a candidate close to a rival's best is charged for it), so that no two cards end
// up the same patch. A search keeps its best few candidates of different structures, and picks
// its best from them against its rivals as they are now (`reselect`), so that a rival arriving
// at its answer later moves it to its next best rather than leaving two cards the same.
//
// A search only decides what to try (`ask`) and learns from the scores (`tell`); the rendering
// and scoring (`evaluate`) happen in the workers, each candidate on its own, so that one round
// spreads over all of them.
//
// A variation instead mutates a candidate's unlocked genes by an amount (`mutants`), and each
// mutant is rendered once.

@get_index external get32: (Float32Array.t, int) => float = ""
@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

type island = {
  key: string,
  title: string,
  // what it's after, for the card's tooltip
  blurb: string,
  weights: MatchLoss.weights,
  // genes it keeps within bounds: (key, lo, hi)
  bounds: array<(string, float, float)>,
  // the searches (indices into islands) whose best it keeps away from
  rivals: array<int>,
}

// a choice gene held to one option, or kept at or above one
let only = (key, option) => {
  let v = Genome.valueOfChoice(option, Genome.gene(Genome.indexOf(key)).options)
  (key, v, v)
}
let atLeast = (key, option) => (
  key,
  Genome.valueOfChoice(option, Genome.gene(Genome.indexOf(key)).options) - 1e-6,
  1.,
)
let off = key => (key, 0., 0.)

let islands = [
  {
    key: "detailed",
    title: "Detailed",
    blurb: "Everything free: the closest the search gets, with layers, modulation and effects where they help",
    weights: MatchLoss.standard,
    bounds: [],
    rivals: [],
  },
  {
    key: "simple",
    title: "Simple",
    blurb: "One oscillator (and noise) through the filter, with its envelopes: easy to take further by hand",
    weights: MatchLoss.standard,
    bounds: [
      off("o2Level"),
      only("oscMix", 0),
      only("unison", 0),
      ("pitchEnv", 0.5, 0.5),
      off("vibrato"),
      off("wobble"),
      off("drive"),
      off("chorus"),
      off("reverb"),
    ],
    rivals: [0],
  },
  {
    key: "punchy",
    title: "Punchy",
    blurb: "The attack matters most: tight envelopes, dry",
    weights: {envelope: 1.2, early: 3., treble: 1., resolutions: [0.6, 1., 1.6]},
    bounds: [off("chorus"), off("reverb")],
    rivals: [0, 1],
  },
  {
    key: "lush",
    title: "Lush",
    blurb: "The tone matters most, made wider with unison, chorus and reverb",
    weights: {envelope: 0.25, early: 1., treble: 1., resolutions: [1.6, 1., 0.4]},
    bounds: [atLeast("unison", 1), ("chorus", 0.3, 1.), ("reverb", 0.3, 1.)],
    rivals: [0, 1, 2],
  },
]

// what each optional part a candidate switches on costs it (Genome.parts), about 0.5% of match;
// noise over three times that (between the harmonics, a little noise can stand in for partials
// that modulation or a roughened oscillator would put there, which are the likelier sound, and a
// hiss the sample hasn't is heard more than the loss hears it)
let partCost = 0.008
let noiseCost = 0.018

//==============================================================================
// Rendering and scoring a candidate (in a worker)

// What an evaluation fits to the sample rather than taking from the genes: the amp envelope
// (unless the envelopes are locked) and the key EQ (unless it is).
type fitting = {envelope: bool, eq: bool}

let noFitting = {envelope: false, eq: false}

type context = {
  engine: MatchEngine.t,
  target: SoundTarget.t,
  measured: Spectrum.features,
  // the target's average spectrum (the long bands, dB) and how much each band counts, which the
  // key EQ is fitted to
  eqTarget: array<float>,
  eqWeights: array<float>,
  // the amp envelope that follows its loudness (Genome.seed's genes, in envelopeKeys' order),
  // where envelope fits start from as well as from the candidate's own
  seedEnvelope: Float64Array.t,
  base: Bank.values,
  // the base's output gain, which a candidate's level is set from
  baseGain: float,
}

// The base's waveforms with the first oscillator's user wave as the target's fitted one.
let tablesFor = (target: SoundTarget.t, tables: OatmealFormat.tables) =>
  switch target.wave {
  | Some(wave) => tables->OatmealFormat.setTable(Wave1, wave)
  | None => tables
  }

// rendered past the target's length, so that a render can start at its onset as the sample does
let onsetRoom = 4410

// A cut-off target's last 20 ms may be an editor's fade, not the sound: its loudness steps there
// are left out of the comparison.
let fadeSteps = 2

let trimEnd = (f: Spectrum.features, ~steps) => {
  let keep = a => a->TypedArray.slice(~start=0, ~end=Math.Int.max(1, TypedArray.length(a) - steps))
  {...f, envelope: keep(f.envelope), side: f.side->Option.map(keep)}
}

let eqWeightsOf = (levels: array<float>) => {
  let top = levels->Array.reduce(neg_infinity, Math.max)
  levels->Array.map(l => Math.max(0., Math.min(1., (l - (top - 50.)) / 50.)))
}

let makeContext = (engine, target: SoundTarget.t, ~base: Bank.values, ~tables) => {
  MatchEngine.setBase(engine, base, tablesFor(target, tables))
  let baseValue = id => base->Map.get(id)->Option.getOr(0.)
  MatchEngine.learnPages(
    engine,
    Genome.probes()->Array.map(x => Genome.decode(x, ~note=target.note, ~base=baseValue)),
    ~note=target.note,
    ~frames=TypedArray.length(target.samples) + onsetRoom,
  )
  let measured = Spectrum.measure(
    target.samples,
    ~period=SoundTarget.period(target),
    ~gridHz=?target.hz,
    ~side=?target.side,
  )
  let measured = target.truncated ? trimEnd(measured, ~steps=fadeSteps) : measured
  let eqTarget = Spectrum.averageSpectrum(measured)
  {
    engine,
    target,
    measured,
    eqTarget,
    eqWeights: eqWeightsOf(eqTarget),
    seedEnvelope: {
      let seed = Genome.seed(target)
      Float64Array.fromArray(Genome.envelopeKeys->Array.map(key => Genome.get(seed, key)))
    },
    base,
    baseGain: base->Map.get("Gain")->Option.getOr(0.1),
  }
}

let baseValue = (ctx, id) => ctx.base->Map.get(id)->Option.getOr(0.)

let frames = ctx => TypedArray.length(ctx.target.samples)

// The pitch x plays at, Hz (the harmonic grid is measured on it).
let playedHz = (ctx, x) => {
  let note = Genome.playedNote(x, ~note=ctx.target.note)
  let cents = Genome.playedCents(x, ~cents=ctx.target.cents)
  440. * Math.pow(2., ~exp=(Int.toFloat(note) + cents / 100. - 69.) / 12.)
}

// Renders x at the key and tuning its genes play it at, from its onset (SoundTarget.onsetOf),
// as long as the target (or only its first `frames`); with its side signal for a stereo target.
let renderSides = (ctx, ~frames as length=?, x) => {
  let note = Genome.playedNote(x, ~note=ctx.target.note)
  let values = Genome.decode(x, ~note, ~base=baseValue(ctx, _))
  let n = length->Option.getOr(frames(ctx))
  let cents = Genome.playedCents(x, ~cents=ctx.target.cents)
  let (y, side) = switch ctx.target.side {
  | Some(_) =>
    let (y, side) = MatchEngine.renderSides(ctx.engine, values, ~note, ~cents, ~frames=n + onsetRoom)
    (y, Some(side))
  | None => (MatchEngine.render(ctx.engine, values, ~note, ~cents, ~frames=n + onsetRoom), None)
  }
  let start = Math.Int.min(onsetRoom, SoundTarget.onsetOf(y))
  let cut = a => a->TypedArray.subarray(~start, ~end=start + n)
  (note, values, cut(y), side->Option.map(cut))
}

let renderGenes = (ctx, ~frames=?, x) => {
  let (note, values, y, _) = renderSides(ctx, ~frames?, x)
  (note, values, y)
}

// the level a single note is set to: -24 dB RMS over its loudest 300 ms (a four-note chord
// comes out near the Vanilla bank's -18 dB), with its peak at most -3 dBFS
let targetDb = -24.
let peakCeiling = -3.

// how much y changes to stand at that level
let levelChange = (y: Float32Array.t) => {
  let n = TypedArray.length(y)
  let window = Math.Int.min(n, 13230)
  let power = ref(0.)
  let peak = ref(0.)
  for i in 0 to window - 1 {
    power := power.contents + y->get32(i) * y->get32(i)
  }
  let loudest = ref(power.contents)
  for i in window to n - 1 {
    power := power.contents + y->get32(i) * y->get32(i) - y->get32(i - window) * y->get32(i - window)
    loudest := Math.max(loudest.contents, power.contents)
  }
  y->TypedArray.forEach(v => peak := Math.max(peak.contents, Math.abs(v)))
  let rmsDb = Spectrum.db(Math.sqrt(loudest.contents / Int.toFloat(Math.Int.max(1, window))))
  Math.pow(10., ~exp=Math.min(targetDb - rmsDb, peakCeiling - Spectrum.db(peak.contents)) / 20.)
}

let levelGain = (ctx, y: Float32Array.t) =>
  Math.max(0.001, Math.min(31.6, ctx.baseGain * levelChange(y)))

// A candidate, as the drawer shows it.
type candidate = {
  // its search (an index into islands), or -1 for a variation
  island: int,
  // its card
  slot: int,
  genes: array<float>,
  // the parameter values that make it, on the base (with its level and tuning set)
  values: array<(string, float)>,
  // the key it is played at to sound at the sample's pitch
  note: int,
  // whether it plays the fitted wave (the target's, as the first oscillator's user wave)
  fitted: bool,
  similarity: float,
  description: string,
  // its loudness envelope (64 steps) and average spectrum (48 bands) in dB, at the target's
  // overall loudness, for the card's picture
  envelope: array<float>,
  spectrum: array<float>,
}

let envelopePoints = 64

let candidateOf = (ctx, x, note, values, y, f: Spectrum.features) => {
  let gain = f.energy > 0. ? Math.sqrt(ctx.measured.energy / f.energy) : 1.
  {
    island: -1,
    slot: -1,
    genes: Array.fromInitializer(~length=TypedArray.length(x), i => x->get64(i)),
    // (with the tuning it was heard at: the sample's, moved by the tune gene, so that the card
    // plays at the sample's pitch as it was scored)
    values: values->Array.concat([
      ("Gain", levelGain(ctx, y)),
      ("Tune_Main", 440. * Math.pow(2., ~exp=Genome.playedCents(x, ~cents=ctx.target.cents) / 1200.)),
    ]),
    note,
    fitted: Genome.choice(x, "o1Wave") == Genome.fittedWave,
    similarity: MatchLoss.similarity(MatchLoss.compare(MatchLoss.standard, ctx.measured, f)),
    description: Genome.describe(x),
    envelope: Spectrum.envelopeOverview(f, ~points=envelopePoints, ~gain),
    spectrum: Spectrum.averageSpectrum(f, ~gain),
  }
}

let cost = x => partCost * Int.toFloat(Genome.parts(x)) + (Genome.get(x, "noise") >= Genome.noiseOff ? noiseCost : 0.)

// The amp envelope of x as power (its mean square) over [a, b) ms, from a table every ms.
let envelopePower = (x, ~ms) => {
  let stages = Genome.stagesOf(Float64Array.fromArray(Genome.envelopeKeys->Array.map(key => Genome.get(x, key))))
  let levels = EnvelopeFit.levels(stages, ~ms)
  let sums = Float64Array.fromLength(ms + 1)
  for t in 0 to ms - 1 {
    let a = levels->get64(t)
    sums->set64(t + 1, sums->get64(t) + a * a)
  }
  (a, b) => {
    let lo = Math.Int.max(0, Math.Int.min(ms, Float.toInt(Math.floor(a))))
    let hi = Math.Int.max(lo + 1, Math.Int.min(ms, Float.toInt(Math.ceil(b))))
    (sums->get64(hi) - sums->get64(lo)) / Int.toFloat(hi - lo)
  }
}

// A flat render's measurements with an envelope put on them: each frame's levels scaled by the
// envelope as its window weighs it (averaged over the frames pooled into it), each
// 10 ms step's loudness by the envelope over the step. Within a tenth of a point of measuring a
// render with the envelope (tools/test/match.mjs checks it), at a twentieth of the cost.
let shaped = (f: Spectrum.features, power) => {
  let spectra = Spectrum.resolutions->Array.mapWithIndex((r, ri) => {
    let pool = f.pools->Array.getUnsafe(ri)
    let levels = f.spectra->Array.getUnsafe(ri)
    let groups = TypedArray.length(levels) / r.bands
    let frames = Spectrum.frameCount(r, f.length)
    let out = Float64Array.fromLength(TypedArray.length(levels))
    for g in 0 to groups - 1 {
      let (p, count) = (ref(0.), ref(0))
      for frame in g * pool to Math.Int.min(frames, (g + 1) * pool) - 1 {
        let centre = 1000. * Int.toFloat(frame * r.hop) / Spectrum.sampleRate
        p := p.contents + Spectrum.windowPower(power, ~centreMs=centre, ~size=r.size)
        count := count.contents + 1
      }
      let a = Math.sqrt(p.contents / Int.toFloat(Math.Int.max(1, count.contents)))
      for b in 0 to r.bands - 1 {
        out->set64(g * r.bands + b, levels->get64(g * r.bands + b) * a)
      }
    }
    out
  })
  let step = 1000. * Int.toFloat(Spectrum.envelopeStep) / Spectrum.sampleRate
  let energy = ref(0.)
  let gain = s => Math.sqrt(power(Int.toFloat(s) * step, Int.toFloat(s + 1) * step))
  let envelope = f.envelope->TypedArray.mapWithIndex((v, s) => {
    let e = v * gain(s)
    energy := energy.contents + e * e * Int.toFloat(Spectrum.envelopeStep)
    e
  })
  // (the harmonic grid, whose windows are long and whose fine spectrum an envelope moves within
  // them, is measured on the shaped samples: evaluate)
  {
    ...f,
    spectra,
    envelope,
    energy: energy.contents,
    side: f.side->Option.map(side => side->TypedArray.mapWithIndex((v, s) => v * gain(s))),
  }
}

// Where a flat render with the envelope put on it would start, as SoundTarget.onsetOf finds
// it (2 ms before it first reaches 1% of its peak), to the millisecond: from the render's peak
// in each millisecond and the envelope's level there.
let onsetMs = (y: Float32Array.t, power) => {
  let perMs = Float.toInt(Spectrum.sampleRate / 1000.)
  let ms = TypedArray.length(y) / perMs
  let peaks = Float64Array.fromLength(ms)
  let top = ref(0.)
  for t in 0 to ms - 1 {
    let gain = Math.sqrt(power(Int.toFloat(t), Int.toFloat(t + 1)))
    let m = ref(0.)
    for i in t * perMs to (t + 1) * perMs - 1 {
      m := Math.max(m.contents, Math.abs(y->get32(i)))
    }
    peaks->set64(t, m.contents * gain)
    top := Math.max(top.contents, m.contents * gain)
  }
  let first = ref(0)
  while first.contents < ms && peaks->get64(first.contents) < 0.01 * top.contents {
    first := first.contents + 1
  }
  Math.max(0., Int.toFloat(first.contents) - 2.)
}

// A flat render with the envelope put on it, sample by sample: its level each millisecond, at
// the millisecond's middle, and between them a line (a level held for each millisecond would
// step, and its steps' splatter would stand over a quiet tail).
let shapedSamples = (y: Float32Array.t, power) => {
  let ms = Float.toInt(1000. * Int.toFloat(TypedArray.length(y)) / Spectrum.sampleRate) + 2
  let gains = Float64Array.fromLength(ms)
  for t in 0 to ms - 1 {
    gains->set64(t, Math.sqrt(power(Int.toFloat(t), Int.toFloat(t + 1))))
  }
  let perMs = Spectrum.sampleRate / 1000.
  y->TypedArray.mapWithIndex((v, i) => {
    let at = Math.max(0., Int.toFloat(i) / perMs - 0.5)
    let t = Float.toInt(at)
    let u = at - Int.toFloat(t)
    v * ((1. - u) * gains->get64(t) + u * gains->get64(Math.Int.min(ms - 1, t + 1)))
  })
}

// x with the amp envelope that suits a flat render of it best by these weights: where the
// loss itself is least (MatchLoss.envelopeObjective, on the flat render's measurements), found
// from x's own envelope (in a search, one already fitted to a sound near it) or the one that
// follows the sample's loudness, whichever is closer. With `quick`, just the closer of the two.
let fitEnvelope = (ctx, x, flat: Spectrum.features, ~weights, ~quick) => {
  let objective = MatchLoss.envelopeObjective(weights, ctx.measured, flat)
  let ms = Float.toInt(1000. * Int.toFloat(frames(ctx)) / Spectrum.sampleRate) + 60
  let keys = Genome.envelopeKeys->Array.map(Genome.indexOf)
  let trial = e => objective(EnvelopeFit.levels(Genome.stagesOf(e), ~ms)->TypedArray.map(a => a * a))
  let own = Float64Array.fromArray(keys->Array.map(k => x->get64(k)))
  let start = trial(own) <= trial(ctx.seedEnvelope) ? own : ctx.seedEnvelope
  let best = quick ? start : Pair.first(EnvelopeFit.minimize(trial, start, ~step=0.08, ~iterations=20))
  let y = TypedArray.copy(x)
  keys->Array.forEachWithIndex((k, j) => y->set64(k, best->get64(j)))
  y
}

// What an evaluation gives: the score, the genes scored (with their envelope fitted, if it
// was), and the candidate if it scored under the threshold.
type result = {loss: float, genes: array<float>, candidate: option<candidate>}

let measureOf = (ctx, y, ~side=?, ~hz) =>
  Spectrum.measure(
    y,
    ~period=SoundTarget.period(ctx.target),
    ~gridHz=?ctx.target.hz->Option.map(_ => hz),
    ~axisHz=?ctx.target.hz,
    ~side?,
  )

// A short render (`short` evaluations) is the first this many seconds of the note.
let shortSeconds = 0.45

// A short render's measurements made as long as the target's, holding its last whole frames
// (those whose windows fit in it) and its last whole loudness step to the end: the sound as
// it has settled, which ranks candidates much as their whole notes do.
let extend = (f: Spectrum.features, ~like: Spectrum.features) => {
  let spectra = Spectrum.resolutions->Array.mapWithIndex((r, ri) => {
    let levels = f.spectra->Array.getUnsafe(ri)
    let pool = f.pools->Array.getUnsafe(ri)
    let groups = TypedArray.length(levels) / r.bands
    let want = TypedArray.length(like.spectra->Array.getUnsafe(ri)) / r.bands
    // the last group all of whose frames' windows are in the render
    let whole = Math.Int.max(0, Math.Int.min(groups - 1, (f.length - r.size / 2) / r.hop / pool - 1))
    let out = Float64Array.fromLength(want * r.bands)
    for g in 0 to want - 1 {
      let from = Math.Int.min(g, whole)
      for b in 0 to r.bands - 1 {
        out->set64(g * r.bands + b, levels->get64(from * r.bands + b))
      }
    }
    out
  })
  let steps = TypedArray.length(like.envelope)
  let last = Math.Int.max(0, TypedArray.length(f.envelope) - 2)
  let held = (a: Float64Array.t) => {
    let out = Float64Array.fromLength(steps)
    for s in 0 to steps - 1 {
      out->set64(s, a->get64(Math.Int.min(s, last)))
    }
    out
  }
  let envelope = held(f.envelope)
  let energy = ref(0.)
  envelope->TypedArray.forEach(v => energy := energy.contents + v * v * Int.toFloat(Spectrum.envelopeStep))
  {...f, length: like.length, spectra, envelope, energy: energy.contents, side: f.side->Option.map(held)}
}

//==============================================================================
// The key EQ, fitted

// Band k's response in dB at f for gain g dB on a note at hz, as the DSP has it (dsp/Voice.cmajor
// setKeyEqBand: RBJ peaking, Q = sqrt 2, or for the first a low shelf half an octave under the
// note; sitting at 18 kHz and fading out past it).
let eqBandDb = (~k, ~g, ~hz, ~f) => {
  let centre = hz * PorridgeParams.keyEqHarmonic(k + 1)
  let over = centre > 18000. ? Math.log2(centre / 18000.) : 0.
  let gain = g * Math.max(0., 1. - over)
  if Math.abs(gain) <= 0.01 {
    0.
  } else {
    let fc = Math.min(Math.min(k == 0 ? centre * 0.70710678 : centre, 18000.), 0.45 * Spectrum.sampleRate)
    let w = Spectrum.twoPi * fc / Spectrum.sampleRate
    let a = Math.pow(10., ~exp=gain / 40.)
    let c = Math.cos(w)
    let ((b0, b1, b2), (a0, a1, a2)) = if k == 0 {
      let beta = 2. * Math.sqrt(a) * Math.sin(w) / Math.sqrt(2.)
      (
        (a * ((a + 1.) - (a - 1.) * c + beta), 2. * a * ((a - 1.) - (a + 1.) * c), a * ((a + 1.) - (a - 1.) * c - beta)),
        ((a + 1.) + (a - 1.) * c + beta, -2. * ((a - 1.) + (a + 1.) * c), (a + 1.) + (a - 1.) * c - beta),
      )
    } else {
      let alpha = Math.sin(w) / (2. * Math.sqrt(2.))
      ((1. + alpha * a, -2. * c, 1. - alpha * a), (1. + alpha / a, -2. * c, 1. - alpha / a))
    }
    let v = Spectrum.twoPi * Math.min(f, 0.5 * Spectrum.sampleRate) / Spectrum.sampleRate
    let (c1, s1, c2, s2) = (Math.cos(v), Math.sin(v), Math.cos(2. * v), Math.sin(2. * v))
    let num = Math.pow(b0 + b1 * c1 + b2 * c2, ~exp=2.) + Math.pow(b1 * s1 + b2 * s2, ~exp=2.)
    let den = Math.pow(a0 + a1 * c1 + a2 * c2, ~exp=2.) + Math.pow(a1 * s1 + a2 * s2, ~exp=2.)
    10. * Math.log10(num / den)
  }
}

let eqResponse = (gains: array<float>, ~hz, ~f) =>
  gains->Array.reduceWithIndex(0., (sum, g, k) => sum + eqBandDb(~k, ~g, ~hz, ~f))

// Where a band's level comes from, for a note at hz, as (frequency, power) points: with the
// render's harmonic grid, the harmonics in it, each by the band's weight there times its power (a
// low band can hold a loud harmonic and a quiet one, and its level is theirs, not its centre's),
// and what lies between them (five points across the band, at the grid's ratio to the nearest
// harmonic); in a band with no harmonic, the harmonic nearest it, which leaks into it. Without a
// grid, five points across the band, as its weights have them.
let spreadPoints = 5

let bandPoints = (r: Spectrum.resolution, ~hz, ~grid: option<Spectrum.grid>) => {
  let binHz = Spectrum.sampleRate / Int.toFloat(r.size)
  let between = grid->Option.map(Spectrum.gridMeanRatio)
  Array.fromInitializer(~length=r.bands, b => {
    let (first, last) = (r.first->Spectrum.getInt(b), r.last->Spectrum.getInt(b))
    let offset = r.offset->Spectrum.getInt(b)
    let weightAt = f => {
      let k = Float.toInt(Math.round(f / binHz))
      k >= first && k <= last ? r.weights->get64(offset + k - first) : 0.
    }
    let spread = Array.fromInitializer(~length=spreadPoints, i => {
      let f = (Int.toFloat(first) + (Int.toFloat(last - first) * (Int.toFloat(i) + 0.5)) / Int.toFloat(spreadPoints)) * binHz
      (f, weightAt(f))
    })->Array.filter(((_, w)) => w > 0.)
    let harmonics = grid->Option.map(g => g.harmonics)
    let power = m =>
      switch harmonics {
      | Some(h) if m >= 1 && m <= TypedArray.length(h) => h->get64(m - 1)
      | Some(h) if TypedArray.length(h) > 0 => h->get64(TypedArray.length(h) - 1)
      | _ => 1.
      }
    let points = []
    let m = ref(Math.Int.max(1, Float.toInt(Math.ceil(Int.toFloat(first) * binHz / hz))))
    while Int.toFloat(m.contents) * hz <= Int.toFloat(last) * binHz {
      let f = Int.toFloat(m.contents) * hz
      let k = Math.Int.max(first, Math.Int.min(last, Float.toInt(Math.round(f / binHz))))
      let w = r.weights->get64(offset + k - first) * power(m.contents)
      if w > 0. {
        points->Array.push((f, w))
      }
      m := m.contents + 1
    }
    // (a band wholly under the note holds what lies under it, as its weights spread it)
    let under = Int.toFloat(last) * binHz < 0.75 * hz
    switch between {
    | _ if under => spread == [] ? [(r.centres->get64(b), 1.)] : spread
    | None => spread == [] ? [(r.centres->get64(b), 1.)] : spread
    | Some(ratios) =>
      let nearest = Math.max(1., Math.round(r.centres->get64(b) / hz))
      let harmonicPoints = points == [] ? [(nearest * hz, power(Float.toInt(nearest)))] : points
      // (the grid's ratio is of mean powers per bin; a harmonic's power is about three bins')
      let ratio = Spectrum.gridRatioAt(ratios, r.centres->get64(b))
      let noise = spread->Array.map(((f, w)) => (f, w * ratio * power(Float.toInt(Math.max(1., Math.round(f / hz)))) / 3.))
      Array.concat(harmonicPoints, noise)
    }
  })
}

// The EQ's response on each band (dB), from its points.
let bandResponse = (points: array<array<(float, float)>>, gains, ~hz) =>
  points->Array.map(ps => {
    let (sum, weight) = ps->Array.reduce((0., 0.), ((s, w), (f, pw)) => (
      s + pw * Math.pow(10., ~exp=eqResponse(gains, ~hz, ~f) / 10.),
      w + pw,
    ))
    10. * Math.log10(Math.max(sum / weight, 1e-30))
  })

// Solves the small symmetric system m x = v (Gaussian elimination with pivoting).
let solve = (m: array<array<float>>, v: array<float>) => {
  let n = Array.length(v)
  let a = m->Array.mapWithIndex((row, i) => Array.concat(row, [v->Array.getUnsafe(i)]))
  for col in 0 to n - 1 {
    let pivot = ref(col)
    for r in col + 1 to n - 1 {
      if Math.abs(a->Array.getUnsafe(r)->Array.getUnsafe(col)) > Math.abs(a->Array.getUnsafe(pivot.contents)->Array.getUnsafe(col)) {
        pivot := r
      }
    }
    let tmp = a->Array.getUnsafe(col)
    a->Array.setUnsafe(col, a->Array.getUnsafe(pivot.contents))
    a->Array.setUnsafe(pivot.contents, tmp)
    let p = a->Array.getUnsafe(col)->Array.getUnsafe(col)
    if Math.abs(p) > 1e-12 {
      for r in 0 to n - 1 {
        if r != col {
          let row = a->Array.getUnsafe(r)
          let factor = row->Array.getUnsafe(col) / p
          if factor != 0. {
            for c in col to n {
              row->Array.setUnsafe(c, row->Array.getUnsafe(c) - factor * a->Array.getUnsafe(col)->Array.getUnsafe(c))
            }
          }
        }
      }
    }
  }
  Array.fromInitializer(~length=n, i => {
    let p = a->Array.getUnsafe(i)->Array.getUnsafe(i)
    Math.abs(p) > 1e-12 ? a->Array.getUnsafe(i)->Array.getUnsafe(n) / p : 0.
  })
}

// how hard the fit holds the gains near flat, against the bands' weights
let eqRidge = 0.03
let eqLimit = 18.

// The gains (dB) that best turn a render's average spectrum (with the EQ flat) into the
// target's, with a free overall level: weighted least squares over the long bands, each band's
// response taken as linear in its gain (its response at 6 dB, per dB), then once more on what
// is left with the response as it really is.
let fitEqGains = (ctx, f: Spectrum.features, ~hz) => {
  let r = Spectrum.resolutions->Array.getUnsafe(0)
  let bands = PorridgeParams.keyEqBands
  let own = Spectrum.averageSpectrum(f)
  let points = bandPoints(r, ~hz, ~grid=f.grid)
  let unit = Array.fromInitializer(~length=bands, k =>
    bandResponse(points, Array.fromInitializer(~length=bands, j => j == k ? 6. : 0.), ~hz)->Array.map(d => d / 6.)
  )
  let weights = ctx.eqWeights
  let total = weights->Array.reduce(0., (s, w) => s + w)
  let step = (residual: array<float>) => {
    // unknowns: the gains, then the level
    let n = bands + 1
    let column = (j, b) => j < bands ? unit->Array.getUnsafe(j)->Array.getUnsafe(b) : 1.
    let m = Array.fromInitializer(~length=n, i =>
      Array.fromInitializer(~length=n, j => {
        let s = ref(i == j && i < bands ? eqRidge * total : 0.)
        for b in 0 to r.bands - 1 {
          s := s.contents + weights->Array.getUnsafe(b) * column(i, b) * column(j, b)
        }
        s.contents
      })
    )
    let v = Array.fromInitializer(~length=n, i => {
      let s = ref(0.)
      for b in 0 to r.bands - 1 {
        s := s.contents + weights->Array.getUnsafe(b) * column(i, b) * residual->Array.getUnsafe(b)
      }
      s.contents
    })
    solve(m, v)->Array.slice(~start=0, ~end=bands)
  }
  let clampGain = g => Math.max(-.eqLimit, Math.min(eqLimit, g))
  let diff = Array.fromInitializer(~length=r.bands, b => ctx.eqTarget->Array.getUnsafe(b) - own->Array.getUnsafe(b))
  let first = step(diff)->Array.map(clampGain)
  let response = bandResponse(points, first, ~hz)
  let left = diff->Array.mapWithIndex((d, b) => d - response->Array.getUnsafe(b))
  let more = step(left)
  first->Array.mapWithIndex((g, k) => clampGain(g + more->Array.getUnsafe(k)))
}

// The key EQ on a render, as the DSP runs it at the end of the voice (dsp/Voice.cmajor: the same
// bands, in double precision): for a single note it is the same as rendering with it, as the
// EQ is the last thing on the voice and what follows it is linear.
let applyEq: (Float32Array.t, array<float>, float) => Float32Array.t = %raw(`(x, gains, hz) => {
  const sr = 44100, out = Float32Array.from(x);
  gains.forEach((g, k) => {
    const centre = hz * Math.pow(2, k);
    const over = centre > 18000 ? Math.log2(centre / 18000) : 0;
    const gain = g * Math.max(0, 1 - over);
    if (Math.abs(gain) <= 0.01) return;
    const f = Math.min(k === 0 ? centre * 0.70710678 : centre, 18000, 0.45 * sr);
    const w = 2 * Math.PI * f / sr, A = Math.pow(10, gain / 40), c = Math.cos(w);
    let b0, b1, b2, a1, a2;
    if (k === 0) {
      const beta = 2 * Math.sqrt(A) * Math.sin(w) / Math.SQRT2, s0 = (A + 1) + (A - 1) * c + beta;
      b0 = A * ((A + 1) - (A - 1) * c + beta) / s0; b1 = 2 * A * ((A - 1) - (A + 1) * c) / s0;
      b2 = A * ((A + 1) - (A - 1) * c - beta) / s0; a1 = -2 * ((A - 1) + (A + 1) * c) / s0;
      a2 = ((A + 1) + (A - 1) * c - beta) / s0;
    } else {
      const alpha = Math.sin(w) / (2 * Math.SQRT2), a0 = 1 + alpha / A;
      b0 = (1 + alpha * A) / a0; b1 = -2 * c / a0; b2 = (1 - alpha * A) / a0; a1 = -2 * c / a0; a2 = (1 - alpha / A) / a0;
    }
    let s1 = 0, s2 = 0;
    for (let i = 0; i < out.length; i++) {
      const v = out[i], y = b0 * v + s1;
      s1 = b1 * v - a1 * y + s2;
      s2 = b2 * v - a2 * y;
      out[i] = y;
    }
  });
  return out;
}`)

// x with its key EQ flat, as rendered before the EQ is fitted
let withFlatEq = (x: Float64Array.t) => {
  let y = TypedArray.copy(x)
  Genome.eqKeys->Array.forEach(key => y->set64(Genome.indexOf(key), 0.5))
  y
}

// The gains fitted to a render's measurements (to a tenth of a dB, as the parameter keeps them),
// and x with them.
let fitEq = (ctx, x: Float64Array.t, f: Spectrum.features) => {
  let gains = fitEqGains(ctx, f, ~hz=playedHz(ctx, x))->Array.map(g => Math.round(g * 10.) / 10.)
  let y = TypedArray.copy(x)
  Genome.eqKeys->Array.forEachWithIndex((key, k) => y->set64(Genome.indexOf(key), Genome.eqGene(gains->Array.getUnsafe(k))))
  (y, gains)
}

// Renders x and scores it by these weights (with its parts' cost); the candidate too if it
// scores under `threshold` (the search's best so far: only a new best is shown).
//
// With `fit`, x's amp envelope is first fitted to the sample: x is rendered with a flat
// envelope (Genome.flatOf), the envelope that best turns that render's loudness into the
// sample's is found (Genome.fitEnvelope), and it is put on the render's measurements (`shaped`)
// rather than rendered again; so the search never has to look for the envelope, and every
// sound it tries is heard with the envelope that suits it best. Drive, chorus and reverb come
// after the envelope or depend on its level, so x with any of them is rendered as it is, with
// the envelope it has (from the dry sound it was found from, in the searches).
//
// A `short` evaluation renders only the first shortSeconds and measures the rest as that
// settled (`extend`): for ranking many candidates cheaply, never shown (it has no candidate).
let evaluate = (ctx, x, ~weights, ~threshold, ~fit: fitting, ~short) => {
  let length = short ? Math.Int.min(frames(ctx), Float.toInt(shortSeconds * Spectrum.sampleRate)) : frames(ctx)
  // (with the EQ fitted, x is rendered with it flat and the fit put on the render)
  let x = fit.eq ? withFlatEq(x) : x
  let measure = (y, side) => {
    let f = measureOf(ctx, y, ~side?, ~hz=playedHz(ctx, x))
    short ? extend(f, ~like=ctx.measured) : f
  }
  let finish = (x, note, y, side, f) => {
    // the EQ fitted to the render, then put on it and measured again
    let (x, y, f) = if fit.eq {
      let (x, gains) = fitEq(ctx, x, f)
      let hz = playedHz(ctx, x)
      let y = applyEq(y(), gains, hz)
      (x, () => y, measure(y, side()->Option.map(s => applyEq(s, gains, hz))))
    } else {
      (x, y, f)
    }
    let loss = MatchLoss.compare(weights, ctx.measured, f) + cost(x)
    {
      loss,
      genes: Array.fromInitializer(~length=TypedArray.length(x), i => x->get64(i)),
      candidate: loss < threshold && !short
        ? Some(candidateOf(ctx, x, note, Genome.decode(x, ~note, ~base=baseValue(ctx, _)), y(), f))
        : None,
    }
  }
  if !fit.envelope || Genome.wet(x) {
    let (note, _, y, side) = renderSides(ctx, ~frames=length, x)
    finish(x, note, () => y, () => side, measure(y, side))
  } else {
    let (note, _, flatY, flatSide) = renderSides(ctx, ~frames=length, Genome.flatOf(x))
    let flatF = measure(flatY, flatSide)
    // (a short evaluation, which only ranks, takes the quick fit)
    let x = fitEnvelope(ctx, x, flatF, ~weights, ~quick=short)
    let ms = Float.toInt(1000. * Int.toFloat(frames(ctx)) / Spectrum.sampleRate) + 20
    let power = envelopePower(x, ~ms=ms + 120)
    // a render with the envelope would start where it first reaches -40 dB (SoundTarget.onsetOf),
    // later than the flat one with a slow attack: the envelope moves on by as much
    let onset = onsetMs(flatY, power)
    let power = onset > 0. ? (a, b) => power(a +. onset, b +. onset) : power
    let y = shapedSamples(flatY, power)
    let side = flatSide->Option.map(s => shapedSamples(s, power))
    // (the spectra as `shaped` puts the envelope on them; the rest measured on the shaped
    // samples, as a level that falls within a 10 ms step or a long window can't be put on a
    // measurement: a whole evaluation's energy, loudness and side, and the harmonic grid)
    // (with the EQ fitted, all of it is measured again on the render with the EQ: finish)
    let f = shaped(flatF, power)
    let grid = fit.eq
      ? None
      : ctx.target.hz->Option.flatMap(target => Spectrum.measureGrid(y, ~hz=playedHz(ctx, x), ~axisHz=target))
    let f = fit.eq || short
      ? {...f, grid}
      : {
          let energy = ref(0.)
          y->TypedArray.forEach(v => energy := energy.contents + v * v)
          {...f, grid, energy: energy.contents, envelope: Spectrum.envelope(y), side: side->Option.map(Spectrum.envelope)}
        }
    finish(x, note, () => y, () => side, f)
  }
}

// What a refinement's evaluation gives (MatchRefine): the loss, the similarity, the pictures, and
// the output gain that sets the patch's level (as candidateOf's).
type valued = {
  loss: float,
  similarity: float,
  envelope: array<float>,
  spectrum: array<float>,
  gain: float,
}

// Renders a patch given as parameter values (a card's, with what a refinement adds), played at
// `note` and the tuning in its Tune_Main, as the drawer plays it; its own Gain is left out of the
// render (the level is measured, and set again, from the base's).
let evaluateValues = (ctx, values: array<(string, float)>, ~note) => {
  let values = values->Array.filter(((id, _)) => id != "Gain")
  let tune = values->Array.find(((id, _)) => id == "Tune_Main")->Option.mapOr(440., ((_, v)) => v)
  let cents = 1200. * Math.log2(tune / 440.)
  let n = frames(ctx)
  let (y, side) = switch ctx.target.side {
  | Some(_) =>
    let (y, side) = MatchEngine.renderSides(ctx.engine, values, ~note, ~cents, ~frames=n + onsetRoom)
    (y, Some(side))
  | None => (MatchEngine.render(ctx.engine, values, ~note, ~cents, ~frames=n + onsetRoom), None)
  }
  let start = Math.Int.min(onsetRoom, SoundTarget.onsetOf(y))
  let cut = a => a->TypedArray.subarray(~start, ~end=start + n)
  let (y, side) = (cut(y), side->Option.map(cut))
  let hz = 440. * Math.pow(2., ~exp=(Int.toFloat(note) + cents / 100. - 69.) / 12.)
  let f = measureOf(ctx, y, ~side?, ~hz)
  let loss = MatchLoss.compare(MatchLoss.standard, ctx.measured, f)
  let gain = f.energy > 0. ? Math.sqrt(ctx.measured.energy / f.energy) : 1.
  {
    loss,
    similarity: MatchLoss.similarity(loss),
    envelope: Spectrum.envelopeOverview(f, ~points=envelopePoints, ~gain),
    spectrum: Spectrum.averageSpectrum(f, ~gain),
    gain: levelGain(ctx, y),
  }
}

// The target's picture, in the candidates' terms.
let targetPicture = (measured: Spectrum.features) => (
  Spectrum.envelopeOverview(measured, ~points=envelopePoints),
  Spectrum.averageSpectrum(measured),
)

//==============================================================================
// Searching (in the view)

// Bounds for a search: its island's (none for the outline), the fitted wave left out when the
// target has none, and the locked groups held at `reference`'s values.
let boundsFor = (island: option<island>, ~fitted, ~locks: array<Genome.group>, ~reference: option<Float64Array.t>) => {
  let lo = Float64Array.fromLength(Genome.count)
  let hi = Float64Array.fromLength(Genome.count)
  hi->TypedArray.fillAll(1.)->ignore
  island->Option.forEach(island =>
    island.bounds->Array.forEach(((key, a, b)) => {
      let i = Genome.indexOf(key)
      lo->set64(i, a)
      hi->set64(i, b)
    })
  )
  if !fitted {
    let i = Genome.indexOf("o1Wave")
    hi->set64(i, Math.min(hi->get64(i), Genome.valueOfChoice(Genome.fittedWave - 1, Genome.gene(i).options) + 1e-6))
  }
  reference->Option.forEach(r =>
    Genome.genes->Array.forEachWithIndex((g, i) =>
      if locks->Array.includes(g.group) {
        lo->set64(i, r->get64(i))
        hi->set64(i, r->get64(i))
      }
    )
  )
  (lo, hi)
}

let clampInto = (x: Float64Array.t, lo, hi) => {
  let y = TypedArray.copy(x)
  for i in 0 to TypedArray.length(y) - 1 {
    y->set64(i, Math.max(lo->get64(i), Math.min(hi->get64(i), y->get64(i))))
  }
  y
}

// How far apart two patches are: the root mean square of their continuous genes' differences,
// with a different choice counting as 0.5 (the render genes, octave and tuning, left out).
let distance = (x: Float64Array.t, y: Float64Array.t) => {
  let sum = ref(0.)
  Genome.genes->Array.forEachWithIndex((g, i) =>
    if g.key != "octave" && g.key != "tune" {
      let (a, b) = (x->get64(i), y->get64(i))
      let d = g.options == 0 ? a -. b : Genome.choiceOf(a, g.options) == Genome.choiceOf(b, g.options) ? 0. : 0.5
      sum := sum.contents + d * d
    }
  )
  Math.sqrt(sum.contents / Int.toFloat(Genome.count - 2))
}

// distinct points: none within a hair of another (at the same octave)
let distinct = (xs: array<Float64Array.t>) =>
  xs->Array.reduce([], (kept, x) =>
    kept->Array.some(y => distance(x, y) < 1e-6 && Genome.get(x, "octave") == Genome.get(y, "octave"))
      ? kept
      : Array.concat(kept, [x])
  )

// what a candidate on top of a rival's best is charged (about 14% of match), less the further
// away it is, nothing from this far; and what having the same structure (Genome.structure) as
// a rival's best costs (about 8%), so that cards differ in what they are made of, not just in
// their knobs
let nicheCost = 0.2
let nicheReach = 0.1
let structureCost = 0.1

// A gene-at-a-time polish of a point: each free continuous gene tried a step either side;
// a gene's step halves when neither side helps. Each round also tries all of the last round's
// helpful moves at once.
type polish = {
  mutable at: Float64Array.t,
  mutable loss: float,
  // the free continuous genes and their steps
  genes: array<int>,
  steps: Float64Array.t,
  // the last round's helpful moves, put together
  mutable together: option<Float64Array.t>,
}

// The stages of a search (see the top).
type stage =
  // short evaluations of many structures (level 1: waves, filters and octaves; level 2: the
  // second oscillator and mix modes on the best of those), the best then evaluated in full
  | Screen(array<Float64Array.t>, int)
  | Grid(array<Float64Array.t>)
  // CMA-ES runs side by side, each over one structure, and the generations left in this round
  | Rounds(array<Cmaes.t>, int)
  | Polish(polish)
  | Finished

// A candidate a search keeps: its score without the niche charges, and its structure.
type entry = {raw: float, genes: Float64Array.t, candidate: candidate, shape: array<int>}

type rec search = {
  // its island (an index into islands), or -1 for the outline
  islandIndex: int,
  weights: MatchLoss.weights,
  lo: Float64Array.t,
  hi: Float64Array.t,
  start: Float64Array.t,
  budget: int,
  sigma: float,
  seed: int,
  // what is fitted to each candidate (evaluate's fit), not searched
  fit: fitting,
  mutable stage: stage,
  mutable evals: int,
  mutable bestLoss: float,
  mutable best: option<candidate>,
  mutable bestGenes: option<Float64Array.t>,
  // the searches running beside it that it keeps away from (MatchRun sets them)
  mutable rivals: array<search>,
  // its best candidates, one per structure, best first
  mutable archive: array<entry>,
  // what its screens found: short evaluations' scores and genes
  mutable screened: array<(float, Float64Array.t)>,
  // osc 2's pitches (semitones) the screens try besides the intervals: those the starts play
  // it at off them (a second series of partials the sample was heard to have)
  o2Pitches: array<float>,
  // the best that the screens found playing osc 2 at one of those: it goes on to the grid and a
  // run of the outline's own, whatever the screens think of it (in a short render, a second
  // series seldom beats a patch on the intervals, though tuned it ends up closer)
  mutable held: option<Float64Array.t>,
}

let apart = (s, x) => {
  let shape = Genome.structure(x)
  s.rivals->Array.reduce(0., (charge, rival) =>
    switch rival.bestGenes {
    | Some(y) => {
        let near = Math.max(0., 1. - distance(x, y) / nicheReach)
        let same = Genome.structure(y) == shape ? structureCost : 0.
        charge + nicheCost * near * near + same
      }
    | None => charge
    }
  )
}

let options = Genome.genes->Array.map(g => g.options)

// the choices a gene may take within bounds, as gene values
let allowed = (key, lo, hi) => {
  let i = Genome.indexOf(key)
  let k = Genome.gene(i).options
  Array.fromInitializer(~length=k, o => Genome.valueOfChoice(o, k))->Array.filter(v =>
    v >= lo->get64(i) - 1e-9 && v <= hi->get64(i) + 1e-9
  )
}

// The outline's grid: the starting points, then the first with each allowed first wave and
// filter type, and played an octave either side; and for the first pitch in o2Pitches (a second
// series of partials the sample was heard to have), the first with osc 2 sounding there
// (roughened, as a second series is often a waveform wavering on its own, and without noise),
// with each wave it may take, beside osc 1 as it is, the fitted wave or a pulse, through the
// plainest filter types; mixed beside osc 1, and phase-modulating it while heard beside it.
let gridOf = (starts: array<Float64Array.t>, lo, hi, ~o2Pitches) => {
  let first = starts->Array.getUnsafe(0)
  let variant = changes => {
    let x = TypedArray.copy(first)
    changes->Array.forEach(((key, v)) => x->set64(Genome.indexOf(key), v))
    x
  }
  let waves = allowed("o1Wave", lo, hi)
  let filters = allowed("filterType", lo, hi)
  let structures =
    Array.length(waves) * Array.length(filters) <= 1
      ? []
      : waves->Array.flatMap(w => filters->Array.map(f => variant([("o1Wave", w), ("filterType", f)])))
  let octaves = allowed("octave", lo, hi)->Array.filter(v => Genome.choiceOf(v, 3) != 0)->Array.map(v => variant([("octave", v)]))
  // (osc 1 as it is, the fitted wave, which leaves the second series' partials to osc 2, or a
  // pulse, which has no even harmonics to beat against it; through the four plainest filters)
  let firstWave = Genome.get(first, "o1Wave")
  let seriesWaves =
    waves->Array.filter(w =>
      w == firstWave || [Genome.fittedWave, 2]->Array.includes(Genome.choiceOf(w, Genome.gene(Genome.indexOf("o1Wave")).options))
    )
  let series = o2Pitches->Array.slice(~start=0, ~end=1)->Array.flatMap(st =>
    seriesWaves->Array.flatMap(w1 =>
      allowed("o2Wave", lo, hi)->Array.flatMap(w =>
        filters->Array.slice(~start=0, ~end=4)->Array.map(f =>
          variant([
            ("o1Wave", w1),
            ("o2Pitch", Genome.o2PitchGene(st)),
            ("o2Wave", w),
            ("o2Level", 0.6),
            ("o2Rough", Genome.roughGeneOf(0.5)),
            ("noise", 0.),
            ("oscMix", Genome.valueOfChoice(0, 7)),
            ("width", 0.),
            ("filterType", f),
          ])
        )
      )
    )
  )
  // (and osc 2 phase-modulating osc 1 while heard beside it, as Synplant's B does)
  let heard = series->Array.map(x => {
    let y = TypedArray.copy(x)
    y->set64(Genome.indexOf("oscMix"), Genome.valueOfChoice(3, 7))
    y->set64(Genome.indexOf("o2Heard"), 0.6)
    y->set64(Genome.indexOf("feedback"), 0.)
    y
  })
  [starts, structures, octaves, series, heard]->Array.flat->Array.map(x => clampInto(x, lo, hi))
}

// The outline: `starts` (the seed, or what the predictor suggests, best guess first) within
// the bounds the locks leave.
let offInterval = x => Genome.secondOscSounds(x) && !Genome.o2OnAnchor(Genome.get(x, "o2Pitch"))
let o2PitchesOf = (starts: array<Float64Array.t>) =>
  starts
  ->Array.filter(offInterval)
  ->Array.map(x => Genome.o2Semitones(Genome.get(x, "o2Pitch")))
  ->Array.reduce([], (kept, st) => kept->Array.some(k => Math.abs(k - st) < 0.1) ? kept : Array.concat(kept, [st]))

let outline = (~starts, ~fitted, ~fit, ~locks, ~reference, ~budget, ~sigma, ~seed) => {
  let (lo, hi) = boundsFor(None, ~fitted, ~locks, ~reference)
  {
    islandIndex: -1,
    weights: MatchLoss.standard,
    lo,
    hi,
    start: clampInto(starts->Array.getUnsafe(0), lo, hi),
    budget,
    sigma,
    seed,
    fit,
    stage: Screen(gridOf(starts, lo, hi, ~o2Pitches=o2PitchesOf(starts)), 1),
    evals: 0,
    bestLoss: infinity,
    best: None,
    bestGenes: None,
    rivals: [],
    archive: [],
    screened: [],
    o2Pitches: o2PitchesOf(starts),
    held: None,
  }
}

// how many of the outline's screened structures that are within a search's bounds it tries
let branchScreened = 6

// One of the four searches, from the outline's best few held within its bounds, and the best
// of what its screens found that is within them already (a search that keeps to one
// oscillator would otherwise see only patches with two, cut down).
let branch = (outline: search, islandIndex, ~fitted, ~locks, ~reference, ~budget) => {
  let island = islands->Array.getUnsafe(islandIndex)
  let (lo, hi) = boundsFor(Some(island), ~fitted, ~locks, ~reference)
  let start = clampInto(outline.bestGenes->Option.getOr(outline.start), lo, hi)
  let within = x => distance(x, clampInto(x, lo, hi)) < 1e-9 && Genome.get(x, "octave") == clampInto(x, lo, hi)->Genome.get("octave")
  let screened =
    outline.screened
    ->Array.toSorted(((a, _), (b, _)) => Float.compare(a, b))
    ->Array.filterMap(((_, x)) => within(x) ? Some(x) : None)
    ->distinct
    ->Array.slice(~start=0, ~end=branchScreened)
  // (and the outline's own start, the sample's seed: in a narrow island the outline's best,
  // squeezed into it, can be further off than the seed squeezed into it)
  let starts = distinct([
    start,
    clampInto(outline.start, lo, hi),
    ...outline.archive->Array.map(e => clampInto(e.genes, lo, hi)),
    ...screened,
  ])
  let sigma = 0.6 * outline.sigma
  {
    islandIndex,
    weights: island.weights,
    lo,
    hi,
    start,
    budget,
    sigma,
    seed: outline.seed + 1 + islandIndex,
    fit: outline.fit,
    stage: Grid(starts),
    evals: 0,
    bestLoss: infinity,
    best: None,
    bestGenes: None,
    rivals: [],
    archive: [],
    screened: [],
    o2Pitches: outline.o2Pitches,
    held: None,
  }
}

let isDone = s =>
  switch s.stage {
  | Finished => true
  | Screen(_) | Grid(_) | Rounds(_) | Polish(_) => false
  }

// The second screen's structures on a first-screen winner: osc 2 at a middle level with each
// wave it may take at each interval (and at the pitches the starts play it at off them), each
// mix mode with a sine or saw osc 2 in unison, a fifth or an octave up (and at those pitches:
// the sidebands of modulation at an odd ratio, which noise would otherwise stand in for),
// unison (two and four voices, a little and much detuned), noise (none, some and much), osc 1
// roughened (a little and much), and the second filter (beside and after the first, a little and well above it); all within the
// bounds.
let secondScreen = (x: Float64Array.t, lo, hi, ~o2Pitches) => {
  let set = (y, key, v) => y->set64(Genome.indexOf(key), v)
  let choice = (key, o) => Genome.valueOfChoice(o, Genome.gene(Genome.indexOf(key)).options)
  let anchor = st => Genome.o2PitchGene(st)
  let plain =
    allowed("o2Wave", lo, hi)->Array.flatMap(w =>
      Array.concat(Genome.o2Anchors, o2Pitches)->Array.map(st => {
        let y = TypedArray.copy(x)
        set(y, "oscMix", choice("oscMix", 0))
        set(y, "o2Level", 0.55)
        set(y, "o2Wave", w)
        set(y, "o2Pitch", anchor(st))
        y
      })
    )
  let variant = changes => {
    let y = TypedArray.copy(x)
    changes->Array.forEach(((key, v)) => set(y, key, v))
    y
  }
  let unison =
    allowed("unison", lo, hi)
    ->Array.filter(v => Genome.choiceOf(v, 4) == 1 || Genome.choiceOf(v, 4) == 3)
    ->Array.flatMap(u => [0.35, 0.7]->Array.map(d => variant([("unison", u), ("unisonDetune", d)])))
  let noise = [0., 0.45, 0.75]->Array.map(n => variant([("noise", n), ("noiseColour", 0.1)]))
  // (and osc 1 roughened by its own noise, which a noise floor would otherwise stand in for)
  let rough = [0.35, 0.6]->Array.map(d => variant([("o1Rough", Genome.roughGeneOf(d)), ("roughColour", 0.7)]))
  let doubled =
    allowed("filterDouble", lo, hi)
    ->Array.filter(v => Genome.choiceOf(v, 3) != 0)
    ->Array.flatMap(d => [0.25, 0.6]->Array.map(split => variant([("filterDouble", d), ("filterSplit", split), ("filterMix", 0.5)])))
  let extras = [unison, noise, rough, doubled]->Array.flat
  let mixes =
    allowed("oscMix", lo, hi)
    ->Array.filter(v => Genome.choiceOf(v, 7) != 0)
    ->Array.flatMap(m =>
      [0, 1]->Array.flatMap(w =>
        Array.concat([0., 7., 12.], o2Pitches)->Array.flatMap(i => {
          let y = TypedArray.copy(x)
          set(y, "oscMix", m)
          set(y, "o2Level", 0.55)
          set(y, "feedback", 0.3)
          set(y, "o2Wave", choice("o2Wave", w))
          set(y, "o2Pitch", anchor(i))
          // (at a second series' pitch, with osc 2 heard beside osc 1 too)
          if o2Pitches->Array.includes(i) {
            let z = TypedArray.copy(y)
            set(z, "o2Heard", 0.6)
            [y, z]
          } else {
            [y]
          }
        })
      )
    )
  Array.concat(Array.concat(plain, mixes), extras)->Array.map(y => clampInto(y, lo, hi))
}

// how many first-screen winners the second screen builds on, and how many of all screened go
// on to be evaluated in full
let screenBases = 4
let screenKept = 12

// how small the step gets before a stage has nothing more to find
let settled = 0.004

// What a search tries next: the genes, and the samples they came from (for `tell`).
type pending = {
  genes: array<Float64Array.t>,
  samples: array<(Cmaes.t, array<Cmaes.sample>)>,
  // short evaluations (a screen's)
  short: bool,
}

// The parts a polish may switch off outright, by the value that does (a small step of their
// level gains nothing until it crosses the threshold, so a part that no longer helps would
// otherwise stay, its cost unpaid): those on in x that the bounds let off.
let switches = [
  ("noise", 0.),
  ("o2Level", 0.),
  ("o2Rough", 0.),
  ("o1Rough", 0.),
  ("o2Heard", 0.),
  ("vibrato", 0.),
  ("wobble", 0.),
  ("drive", 0.),
  ("chorus", 0.),
  ("reverb", 0.),
  ("modEnvPitch", 0.5),
  ("modEnvDepth", 0.5),
]
let offMoves = (x: Float64Array.t, lo, hi) =>
  switches->Array.filterMap(((key, off)) => {
    let i = Genome.indexOf(key)
    Math.abs(x->get64(i) - off) > 0.05 && lo->get64(i) <= off && hi->get64(i) >= off
      ? {
          let y = TypedArray.copy(x)
          y->set64(i, off)
          Some(y)
        }
      : None
  })

let polishMoves = (p: polish, lo, hi) => {
  let moves = p.genes->Array.flatMap(i =>
    [-1., 1.]->Array.map(sign => {
      let x = TypedArray.copy(p.at)
      x->set64(i, x->get64(i) + sign * p.steps->get64(Array.indexOf(p.genes, i)))
      x
    })
  )
  let moves = Array.concat(moves, offMoves(p.at, lo, hi))
  switch p.together {
  | Some(x) => [x, ...moves]
  | None => moves
  }
}

let ask = s =>
  switch s.stage {
  | Finished => {genes: [], samples: [], short: false}
  | Screen(points, _) => {genes: points, samples: [], short: true}
  | Grid(points) => {genes: points, samples: [], short: false}
  | Rounds(runs, _) =>
    let samples = runs->Array.map(es => (es, Cmaes.ask(es)))
    {genes: samples->Array.flatMap(((_, xs)) => xs->Array.map(sample => sample.x)), samples, short: false}
  | Polish(p) => {genes: polishMoves(p, s.lo, s.hi)->Array.map(x => clampInto(x, s.lo, s.hi)), samples: [], short: false}
  }

let archiveSize = 8

// Keeps a candidate if it is the best of its structure so far and among the best few (or the
// best playing a second series of partials, kept after them whatever its place, so that the
// searches after the outline see it).
let remember = (s, raw, x, c: candidate) => {
  let shape = Genome.structure(x)
  let entry = {raw, genes: TypedArray.copy(x), candidate: c, shape}
  let others = s.archive->Array.filter(e => e.shape != shape)
  let same = s.archive->Array.find(e => e.shape == shape)
  if same->Option.mapOr(true, e => raw < e.raw) {
    let all = [entry, ...others]->Array.toSorted((a, b) => Float.compare(a.raw, b.raw))
    let kept = all->Array.slice(~start=0, ~end=archiveSize)
    s.archive = switch all->Array.find(e => offInterval(e.genes)) {
    | Some(e) if !(kept->Array.includes(e)) => Array.concat(kept, [e])
    | _ => kept
    }
  }
}

// The score under which the workers send a candidate back with its picture: whatever could
// still enter the archive.
let threshold = s =>
  Array.length(s.archive) < archiveSize ? infinity : s.archive[archiveSize - 1]->Option.mapOr(infinity, e => e.raw)

// Picks the best of the archive against the rivals as they are now, never one on top of a
// rival's best if it has another; true if it changed.
let reselect = s => {
  let taken = x => s.rivals->Array.some(r => r.bestGenes->Option.mapOr(false, y => distance(x, y) <= 0.01))
  let free = s.archive->Array.filter(e => !taken(e.genes))
  switch (free == [] ? s.archive : free)->Array.reduce(None, (best, e) => {
    let loss = e.raw + apart(s, e.genes)
    switch best {
    | Some((_, l)) if l <= loss => best
    | _ => Some((e, loss))
    }
  }) {
  | Some((e, loss)) =>
    let changed = s.bestGenes->Option.mapOr(true, g => g !== e.genes)
    s.bestLoss = loss
    s.bestGenes = Some(e.genes)
    s.best = Some({...e.candidate, island: s.islandIndex, slot: Math.Int.max(0, s.islandIndex)})
    changed
  | None => false
  }
}

// the outline's rounds: how many structures go into the first, and generations per round
let roundRuns = 4
let roundGenerations = [5, 7]

// the genes fitted to each candidate rather than searched, when the envelope is fitted
let fittedGenes = s => Array.concat(s.fit.envelope ? Genome.envelopeKeys : [], s.fit.eq ? Genome.eqKeys : [])

// CMA-ES over the core genes of an entry's structure (the rest held where the entry has them).
// (and `extra` genes)
let coreRun = (s, x, ~seed, ~extra=[]) => {
  let lo = TypedArray.copy(s.lo)
  let hi = TypedArray.copy(s.hi)
  Genome.genes->Array.forEachWithIndex((g, i) =>
    if !(Genome.core->Array.includes(g.key) || extra->Array.includes(g.key)) || fittedGenes(s)->Array.includes(g.key) {
      lo->set64(i, x->get64(i))
      hi->set64(i, x->get64(i))
    }
  )
  Cmaes.make(~start=x, ~lo, ~hi, ~options, ~sigma=s.sigma, ~seed)
}

// the runs of held structures, which halving keeps
let heldRuns: WeakMap.t<Cmaes.t, bool> = WeakMap.make()

// the best loss a run has had (its samples' are told to it; Cmaes keeps no record)
let runBests: WeakMap.t<Cmaes.t, float> = WeakMap.make()
let runBest = es => runBests->WeakMap.get(es)->Option.getOr(infinity)

// the genes a polish of x moves: the free continuous ones that make a difference to it
let polishGenes = (s, x) => {
  let relevant = Genome.relevant(x)
  Genome.genes
  ->Array.mapWithIndex((g, i) => (g, i))
  ->Array.filter(((g, i)) =>
    g.options == 0 &&
    s.hi->get64(i) > s.lo->get64(i) &&
    relevant->Array.getUnsafe(i) &&
    (Genome.wet(x) || !(fittedGenes(s)->Array.includes(g.key)))
  )
  ->Array.map(((_, i)) => i)
}

let startPolish = s => {
  let x = s.bestGenes->Option.getOr(s.start)
  let genes = polishGenes(s, x)
  Polish({
    at: TypedArray.copy(x),
    loss: s.bestLoss,
    genes,
    steps: Float64Array.fromLength(Array.length(genes))->TypedArray.fillAll(0.06),
    together: None,
  })
}

// Learns from the scores of what `ask` gave (with what keeping away from its rivals costs);
// true if the best changed.
let tell = (s, pending, results: array<result>) => {
  // the genes as scored (their envelope fitted, if it was)
  let scored = results->Array.map(r => Float64Array.fromArray(r.genes))
  let losses = results->Array.mapWithIndex((r, i) => r.loss + apart(s, scored->Array.getUnsafe(i)))
  results->Array.forEachWithIndex((r, i) => r.candidate->Option.forEach(c => remember(s, r.loss, scored->Array.getUnsafe(i), c)))
  let improved = reselect(s)
  // a short evaluation costs about a third of a whole one
  s.evals = s.evals + (pending.short ? (Array.length(results) + 2) / 3 : Array.length(results))
  let left = s.budget - s.evals
  // the samples' losses, run by run
  let offset = ref(0)
  pending.samples->Array.forEach(((es, xs)) => {
    let ls = losses->Array.slice(~start=offset.contents, ~end=offset.contents + Array.length(xs))
    offset := offset.contents + Array.length(xs)
    Cmaes.tell(es, xs, ls)
    runBests->WeakMap.set(es, ls->Array.reduce(runBest(es), Math.min))->ignore
  })
  switch s.stage {
  | Screen(_, level) =>
    s.screened = Array.concat(s.screened, scored->Array.mapWithIndex((x, i) => (losses->Array.getUnsafe(i), x)))
    let ranked = s.screened->Array.toSorted(((a, _), (b, _)) => Float.compare(a, b))
    // the best of each structure, best first
    let best = (key, count) =>
      ranked
      ->Array.reduce([], (kept, (_, x)) =>
        kept->Array.length >= count || kept->Array.some(y => key(y) == key(x)) ? kept : Array.concat(kept, [x])
      )
    let bases = best(x => [Genome.choice(x, "o1Wave"), Genome.choice(x, "filterType"), Genome.choice(x, "octave")], screenBases)
    let second = level == 1 ? distinct(bases->Array.flatMap(x => secondScreen(x, s.lo, s.hi, ~o2Pitches=s.o2Pitches))) : []
    s.stage =
      second == []
        ? {
            s.held = ranked->Array.find(((_, x)) => offInterval(x))->Option.map(((_, x)) => x)
            let kept = best(x => Array.concat(Genome.structure(x), [Genome.choice(x, "octave")]), screenKept)
            Grid(distinct(Array.concat(kept, s.held->Option.mapOr([], x => [x]))))
          }
        : Screen(second, 2)
  | Grid(_) if s.islandIndex < 0 =>
    // the best few structures of the grid, each run over its core genes (the held one's in the
    // last place, from its best so far)
    let held = s.held->Option.map(x => {
      let shape = Genome.structure(x)
      s.archive->Array.find(e => e.shape == shape)->Option.mapOr(x, e => e.genes)
    })
    let heldShape = held->Option.map(Genome.structure)
    let others = s.archive->Array.filter(e => Some(e.shape) != heldShape)->Array.map(e => e.genes)
    let picked = switch held {
    | Some(x) => Array.concat(others->Array.slice(~start=0, ~end=roundRuns - 1), [x])
    | None => others->Array.slice(~start=0, ~end=roundRuns)
    }
    let runs = picked->Array.mapWithIndex((x, k) =>
      if Some(Genome.structure(x)) == heldShape {
        // (with osc 2's level and pitch, the noise and the second filter free too: a series
        // found on its own needs them set around it)
        let es = coreRun(s, x, ~seed=s.seed + k, ~extra=["o2Level", "o2Pitch", "o2Rough", "roughColour", "o2Heard", "feedback", "noise", "filterSplit", "filterMix"])
        heldRuns->WeakMap.set(es, true)->ignore
        es
      } else {
        coreRun(s, x, ~seed=s.seed + k)
      }
    )
    s.stage = runs == [] ? Finished : Rounds(runs, roundGenerations[0]->Option.getOr(5))
  | Grid(_) => s.stage = startPolish(s)
  | Rounds(runs, generations) =>
    if left <= s.budget / 5 {
      // the rest polishes the best over every gene that makes a difference to it
      s.stage = startPolish(s)
    } else if generations > 1 && runs->Array.some(es => es.sigma >= settled) {
      s.stage = Rounds(runs, generations - 1)
    } else if Array.length(runs) > 2 {
      // the better half goes on, down to two (which between them keep the workers busy)
      // (and the held structure's run)
      let ranked = runs->Array.toSorted((a, b) => Float.compare(runBest(a), runBest(b)))
      let isHeld = es => heldRuns->WeakMap.has(es)
      let held = ranked->Array.filter(isHeld)
      let free = Math.Int.max(1, Array.length(runs) / 2 - Array.length(held))
      let kept = Array.concat(ranked->Array.filter(es => !isHeld(es))->Array.slice(~start=0, ~end=free), held)
      let round = roundRuns / Array.length(runs)
      s.stage = Rounds(kept, roundGenerations[round]->Option.getOr(1000))
    } else {
      s.stage = runs->Array.every(es => es.sigma < settled) ? startPolish(s) : Rounds(runs, 1000)
    }
  | Polish(p) =>
    if left <= 0 {
      s.stage = Finished
    } else {
      // each gene's better side, and the round's best (the moves switching parts off after
      // the genes', as polishMoves made them)
      let offs = Array.length(offMoves(p.at, s.lo, s.hi))
      let k = ref(p.together == None ? 0 : 1)
      let gains = []
      let bestMove = ref(None)
      if p.together != None {
        let l = losses->Array.getUnsafe(0)
        if l < p.loss {
          bestMove := Some((scored->Array.getUnsafe(0), l))
        }
      }
      p.genes->Array.forEachWithIndex((i, j) => {
        let (down, up) = (losses->Array.getUnsafe(k.contents), losses->Array.getUnsafe(k.contents + 1))
        let (l, x) = down < up ? (down, scored->Array.getUnsafe(k.contents)) : (up, scored->Array.getUnsafe(k.contents + 1))
        k := k.contents + 2
        if l < p.loss {
          gains->Array.push((i, x->get64(i)))
          switch bestMove.contents {
          | Some((_, b)) if b <= l => ()
          | _ => bestMove := Some((x, l))
          }
        } else {
          p.steps->set64(j, 0.5 * p.steps->get64(j))
        }
      })
      for o in 0 to offs - 1 {
        let l = losses->Array.getUnsafe(k.contents + o)
        if l < p.loss {
          switch bestMove.contents {
          | Some((_, b)) if b <= l => ()
          | _ => bestMove := Some((scored->Array.getUnsafe(k.contents + o), l))
          }
        }
      }
      switch bestMove.contents {
      | Some((x, l)) =>
        p.at = TypedArray.copy(x)
        p.loss = l
      | None => ()
      }
      p.together =
        Array.length(gains) > 1
          ? {
              let x = TypedArray.copy(p.at)
              gains->Array.forEach(((i, v)) => x->set64(i, v))
              Some(x)
            }
          : None
      if p.steps->TypedArray.every(step => step < 0.004) || 2 * Array.length(p.genes) > left {
        s.stage = Finished
      }
    }
  | Finished => ()
  }
  improved
}

//==============================================================================
// A whole match

type match_ = {
  outline: search,
  // the four searches, once the outline is done
  mutable searches: array<search>,
  fitted: bool,
  // what is fitted to each candidate: the envelope and the key EQ, unless they are locked
  fit: fitting,
  locks: array<Genome.group>,
  reference: option<Float64Array.t>,
  // each search's renders
  islandBudget: int,
}

// the outline's share of the renders
let outlineShare = 0.75

// The renders a match of a sample this long gets: `base` for 1.2 s or longer, and more for a
// shorter one (a render costs about as much as it is long), up to five times as many.
let budgetFor = (~base, ~seconds) =>
  Float.toInt(Int.toFloat(base) * Math.max(1., Math.min(5., Math.pow(1.2 / Math.max(seconds, 0.01), ~exp=0.8))))

let makeMatch = (~starts, ~fitted, ~locks, ~reference, ~budget, ~sigma, ~seed) => {
  let outlineBudget = Float.toInt(outlineShare * Int.toFloat(budget))
  let fit = {envelope: !(locks->Array.includes(#env)), eq: !(locks->Array.includes(#eq))}
  {
    outline: outline(~starts, ~fitted, ~fit, ~locks, ~reference, ~budget=outlineBudget, ~sigma, ~seed),
    searches: [],
    fitted,
    fit,
    locks,
    reference,
    islandBudget: (budget - outlineBudget) / Array.length(islands),
  }
}

// The four searches from the finished outline, each keeping away from its rivals.
let branchAll = m => {
  let searches = islands->Array.mapWithIndex((_, i) =>
    branch(m.outline, i, ~fitted=m.fitted, ~locks=m.locks, ~reference=m.reference, ~budget=m.islandBudget)
  )
  searches->Array.forEach(s => {
    let island: island = islands->Array.getUnsafe(s.islandIndex)
    s.rivals = searches->Array.filter(r => island.rivals->Array.includes(r.islandIndex))
  })
  m.searches = searches
  searches
}

//==============================================================================
// Variations

// `count` mutants of x: each unlocked continuous gene moved by about amount × 0.35, each
// unlocked choice changed with probability amount / 2 (the render genes left as they are, and
// the fitted wave only taken when there is one).
let mutants = (x: Float64Array.t, ~fitted, ~locks: array<Genome.group>, ~amount, ~count, ~seed) => {
  let random = Cmaes.makeRandom(seed)
  let gaussian = () => {
    let u = Math.max(random(), 1e-12)
    Math.sqrt(-2. * Math.log(u)) * Math.cos(2. * Math.Constants.pi * random())
  }
  Array.fromInitializer(~length=count, _ => {
    let y = TypedArray.copy(x)
    Genome.genes->Array.forEachWithIndex((g, i) =>
      if !(locks->Array.includes(g.group)) && g.key != "octave" && g.key != "tune" {
        if g.options == 0 {
          y->set64(i, Genome.clamp01(x->get64(i) + amount * 0.35 * gaussian()))
        } else if random() < amount * 0.5 {
          let options = g.key == "o1Wave" && !fitted ? Genome.fittedWave : g.options
          y->set64(i, Genome.valueOfChoice(Float.toInt(random() * Int.toFloat(options)), g.options))
        }
      }
    )
    y
  })
}
