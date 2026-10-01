// The sound matcher's searches. A match first finds the sound's outline once, then four
// searches go on from it side by side, each after a different kind of match, so that the
// four cards differ in kind rather than being four takes on one answer:
//
//   Detailed  every gene free, the standard loss: the closest the match gets
//   Simple    one oscillator through the filter, with its envelopes: a patch that is easy to
//             take further by hand
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
    blurb: "One oscillator through the filter, with its envelopes: easy to take further by hand",
    weights: MatchLoss.standard,
    bounds: [
      off("o2Level"),
      only("oscMix", 0),
      off("noise"),
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

// what each optional part a candidate switches on costs it (Genome.parts), about 0.5% of match
let partCost = 0.006

//==============================================================================
// Rendering and scoring a candidate (in a worker)

type context = {
  engine: MatchEngine.t,
  target: SoundTarget.t,
  measured: Spectrum.features,
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

let makeContext = (engine, target: SoundTarget.t, ~base: Bank.values, ~tables) => {
  MatchEngine.setBase(engine, base, tablesFor(target, tables))
  let baseValue = id => base->Map.get(id)->Option.getOr(0.)
  MatchEngine.learnPages(
    engine,
    Genome.probes()->Array.map(x => Genome.decode(x, ~note=target.note, ~base=baseValue)),
    ~note=target.note,
    ~frames=TypedArray.length(target.samples) + onsetRoom,
  )
  {
    engine,
    target,
    measured: Spectrum.measure(target.samples, ~period=SoundTarget.period(target)),
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

// Renders x at the key and tuning its genes play it at, from its onset (SoundTarget.onsetOf),
// as long as the target (or only its first `frames`).
let renderGenes = (ctx, ~frames as length=?, x) => {
  let note = Genome.playedNote(x, ~note=ctx.target.note)
  let values = Genome.decode(x, ~note, ~base=baseValue(ctx, _))
  let n = length->Option.getOr(frames(ctx))
  let y = MatchEngine.render(
    ctx.engine,
    values,
    ~note,
    ~cents=Genome.playedCents(x, ~cents=ctx.target.cents),
    ~frames=n + onsetRoom,
  )
  let start = Math.Int.min(onsetRoom, SoundTarget.onsetOf(y))
  (note, values, y->TypedArray.subarray(~start, ~end=start + n))
}

// the level a single note is set to: -24 dB RMS over its loudest 300 ms (a four-note chord
// comes out near the Vanilla bank's -18 dB), with its peak at most -3 dBFS
let targetDb = -24.
let peakCeiling = -3.

let levelGain = (ctx, y: Float32Array.t) => {
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
  let change = Math.min(targetDb - rmsDb, peakCeiling - Spectrum.db(peak.contents))
  Math.max(0.001, Math.min(31.6, ctx.baseGain * Math.pow(10., ~exp=change / 20.)))
}

// A candidate, as the drawer shows it.
type candidate = {
  // its search (an index into islands), or -1 for a variation
  island: int,
  // its card
  slot: int,
  genes: array<float>,
  // the parameter values that make it, on the base (with its level set)
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
    values: values->Array.concat([("Gain", levelGain(ctx, y))]),
    note,
    fitted: Genome.choice(x, "o1Wave") == Genome.fittedWave,
    similarity: MatchLoss.similarity(MatchLoss.compare(MatchLoss.standard, ctx.measured, f)),
    description: Genome.describe(x),
    envelope: Spectrum.envelopeOverview(f, ~points=envelopePoints, ~gain),
    spectrum: Spectrum.averageSpectrum(f, ~gain),
  }
}

let cost = x => partCost * Int.toFloat(Genome.parts(x))

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
  let envelope = f.envelope->TypedArray.mapWithIndex((v, s) => {
    let e = v * Math.sqrt(power(Int.toFloat(s) * step, Int.toFloat(s + 1) * step))
    energy := energy.contents + e * e * Int.toFloat(Spectrum.envelopeStep)
    e
  })
  {...f, spectra, envelope, energy: energy.contents}
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

// A flat render with the envelope put on it, sample by sample (its level each millisecond).
let shapedSamples = (y: Float32Array.t, power) => {
  let ms = Float.toInt(1000. * Int.toFloat(TypedArray.length(y)) / Spectrum.sampleRate) + 1
  let gains = Float64Array.fromLength(ms)
  for t in 0 to ms - 1 {
    gains->set64(t, Math.sqrt(power(Int.toFloat(t), Int.toFloat(t + 1))))
  }
  let perMs = Spectrum.sampleRate / 1000.
  y->TypedArray.mapWithIndex((v, i) => v * gains->get64(Float.toInt(Int.toFloat(i) / perMs)))
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

let measureOf = (ctx, y) => Spectrum.measure(y, ~period=SoundTarget.period(ctx.target))

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
  let envelope = Float64Array.fromLength(steps)
  let energy = ref(0.)
  for s in 0 to steps - 1 {
    let v = f.envelope->get64(Math.Int.min(s, last))
    envelope->set64(s, v)
    energy := energy.contents + v * v * Int.toFloat(Spectrum.envelopeStep)
  }
  {...f, length: like.length, spectra, envelope, energy: energy.contents}
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
let evaluate = (ctx, x, ~weights, ~threshold, ~fit, ~short) => {
  let length = short ? Math.Int.min(frames(ctx), Float.toInt(shortSeconds * Spectrum.sampleRate)) : frames(ctx)
  let measure = y => {
    let f = measureOf(ctx, y)
    short ? extend(f, ~like=ctx.measured) : f
  }
  let finish = (x, note, values, y, f) => {
    let loss = MatchLoss.compare(weights, ctx.measured, f) + cost(x)
    {
      loss,
      genes: Array.fromInitializer(~length=TypedArray.length(x), i => x->get64(i)),
      candidate: loss < threshold && !short ? Some(candidateOf(ctx, x, note, values, y(), f)) : None,
    }
  }
  if !fit || Genome.wet(x) {
    let (note, values, y) = renderGenes(ctx, ~frames=length, x)
    finish(x, note, values, () => y, measure(y))
  } else {
    let (note, _, flatY) = renderGenes(ctx, ~frames=length, Genome.flatOf(x))
    let flatF = measure(flatY)
    // (a short evaluation, which only ranks, takes the quick fit)
    let x = fitEnvelope(ctx, x, flatF, ~weights, ~quick=short)
    {
      let values = Genome.decode(x, ~note, ~base=baseValue(ctx, _))
      let ms = Float.toInt(1000. * Int.toFloat(frames(ctx)) / Spectrum.sampleRate) + 20
      let power = envelopePower(x, ~ms=ms + 120)
      // a render with the envelope would start where it first reaches -40 dB (SoundTarget.onsetOf),
      // later than the flat one with a slow attack: the envelope moves on by as much
      let onset = onsetMs(flatY, power)
      let power = onset > 0. ? (a, b) => power(a +. onset, b +. onset) : power
      finish(x, note, values, () => shapedSamples(flatY, power), shaped(flatF, power))
    }
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
let nicheCost = 0.15
let nicheReach = 0.1
let structureCost = 0.08

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
  // whether the amp envelope is fitted to each candidate (evaluate's fit), not searched
  fit: bool,
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
// filter type, and played an octave either side.
let gridOf = (starts: array<Float64Array.t>, lo, hi) => {
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
  Array.concat(starts, Array.concat(structures, octaves))->Array.map(x => clampInto(x, lo, hi))
}

// The outline: `starts` (the seed, or what the predictor suggests, best guess first) within
// the bounds the locks leave.
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
    stage: Screen(gridOf(starts, lo, hi), 1),
    evals: 0,
    bestLoss: infinity,
    best: None,
    bestGenes: None,
    rivals: [],
    archive: [],
    screened: [],
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
  let starts = distinct([start, ...outline.archive->Array.map(e => clampInto(e.genes, lo, hi)), ...screened])
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
  }
}

let isDone = s =>
  switch s.stage {
  | Finished => true
  | Screen(_) | Grid(_) | Rounds(_) | Polish(_) => false
  }

// The second screen's structures on a first-screen winner: osc 2 at a middle level with each
// wave and interval it may take, and each mix mode with a sine or saw osc 2 in unison, a fifth
// or an octave up (within the bounds).
let secondScreen = (x: Float64Array.t, lo, hi) => {
  let set = (y, key, v) => y->set64(Genome.indexOf(key), v)
  let choice = (key, o) => Genome.valueOfChoice(o, Genome.gene(Genome.indexOf(key)).options)
  let plain =
    allowed("o2Wave", lo, hi)->Array.flatMap(w =>
      allowed("o2Interval", lo, hi)->Array.map(i => {
        let y = TypedArray.copy(x)
        set(y, "oscMix", choice("oscMix", 0))
        set(y, "o2Level", 0.55)
        set(y, "o2Fine", 0.5)
        set(y, "o2Wave", w)
        set(y, "o2Interval", i)
        y
      })
    )
  let mixes =
    allowed("oscMix", lo, hi)
    ->Array.filter(v => Genome.choiceOf(v, 7) != 0)
    ->Array.flatMap(m =>
      [0, 1]->Array.flatMap(w =>
        [0, 3, 1]->Array.map(i => {
          let y = TypedArray.copy(x)
          set(y, "oscMix", m)
          set(y, "o2Level", 0.55)
          set(y, "o2Fine", 0.5)
          set(y, "feedback", 0.3)
          set(y, "o2Wave", choice("o2Wave", w))
          set(y, "o2Interval", choice("o2Interval", i))
          y
        })
      )
    )
  Array.concat(plain, mixes)->Array.map(y => clampInto(y, lo, hi))
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

let polishMoves = (p: polish) => {
  let moves = p.genes->Array.flatMap(i =>
    [-1., 1.]->Array.map(sign => {
      let x = TypedArray.copy(p.at)
      x->set64(i, x->get64(i) + sign * p.steps->get64(Array.indexOf(p.genes, i)))
      x
    })
  )
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
  | Polish(p) => {genes: polishMoves(p)->Array.map(x => clampInto(x, s.lo, s.hi)), samples: [], short: false}
  }

let archiveSize = 8

// Keeps a candidate if it is the best of its structure so far and among the best few.
let remember = (s, raw, x, c: candidate) => {
  let shape = Genome.structure(x)
  let entry = {raw, genes: TypedArray.copy(x), candidate: c, shape}
  let others = s.archive->Array.filter(e => e.shape != shape)
  let same = s.archive->Array.find(e => e.shape == shape)
  if same->Option.mapOr(true, e => raw < e.raw) {
    s.archive = [entry, ...others]->Array.toSorted((a, b) => Float.compare(a.raw, b.raw))->Array.slice(~start=0, ~end=archiveSize)
  }
}

// The score under which the workers send a candidate back with its picture: whatever could
// still enter the archive.
let threshold = s =>
  Array.length(s.archive) < archiveSize ? infinity : s.archive->Array.at(-1)->Option.mapOr(infinity, e => e.raw)

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
let fittedGenes = s => s.fit ? Genome.envelopeKeys : []

// CMA-ES over the core genes of an entry's structure (the rest held where the entry has them).
let coreRun = (s, x, ~seed) => {
  let lo = TypedArray.copy(s.lo)
  let hi = TypedArray.copy(s.hi)
  Genome.genes->Array.forEachWithIndex((g, i) =>
    if !(Genome.core->Array.includes(g.key)) || fittedGenes(s)->Array.includes(g.key) {
      lo->set64(i, x->get64(i))
      hi->set64(i, x->get64(i))
    }
  )
  Cmaes.make(~start=x, ~lo, ~hi, ~options, ~sigma=s.sigma, ~seed)
}

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
    let second = level == 1 ? distinct(bases->Array.flatMap(x => secondScreen(x, s.lo, s.hi))) : []
    s.stage =
      second == []
        ? Grid(best(x => Array.concat(Genome.structure(x), [Genome.choice(x, "octave")]), screenKept))
        : Screen(second, 2)
  | Grid(_) if s.islandIndex < 0 =>
    // the best few structures of the grid, each run over its core genes
    let runs = s.archive->Array.slice(~start=0, ~end=roundRuns)->Array.mapWithIndex((e, k) => coreRun(s, e.genes, ~seed=s.seed + k))
    s.stage = runs == [] ? Finished : Rounds(runs, roundGenerations[0]->Option.getOr(5))
  | Grid(_) => s.stage = startPolish(s)
  | Rounds(runs, generations) =>
    if left <= s.budget / 5 {
      // the rest polishes the best over every gene that makes a difference to it
      s.stage = startPolish(s)
    } else if generations > 1 && runs->Array.some(es => es.sigma >= settled) {
      s.stage = Rounds(runs, generations - 1)
    } else if Array.length(runs) > 1 {
      // the better half goes on
      let kept =
        runs->Array.toSorted((a, b) => Float.compare(runBest(a), runBest(b)))->Array.slice(~start=0, ~end=Math.Int.max(1, Array.length(runs) / 2))
      let round = roundRuns / Array.length(runs)
      s.stage = Rounds(kept, roundGenerations[round]->Option.getOr(1000))
    } else {
      s.stage = runs->Array.every(es => es.sigma < settled) ? startPolish(s) : Rounds(runs, 1000)
    }
  | Polish(p) =>
    if left <= 0 {
      s.stage = Finished
    } else {
      // each gene's better side, and the round's best
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
  // whether each candidate's envelope is fitted (unless the envelopes are locked)
  fit: bool,
  locks: array<Genome.group>,
  reference: option<Float64Array.t>,
  // each search's renders
  islandBudget: int,
}

// the outline's share of the renders
let outlineShare = 0.75

let makeMatch = (~starts, ~fitted, ~locks, ~reference, ~budget, ~sigma, ~seed) => {
  let outlineBudget = Float.toInt(outlineShare * Int.toFloat(budget))
  let fit = !(locks->Array.includes(#env))
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
