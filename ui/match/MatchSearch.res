// The sound matcher's searches. Four run side by side, each after a different kind of match,
// so that the four cards differ in kind rather than being four takes on one answer:
//
//   Detailed  every gene free, the standard loss
//   Simple    one oscillator through the filter, with its envelopes: a patch that is easy to
//             take further by hand
//   Punchy    the attack weighs most (the first 150 ms, the envelope, the short spectra), dry
//   Lush      the tone weighs most (the long spectra), with unison, chorus and reverb
//
// and each keeps away from the ones before it in `rivals` (niching: a candidate close to a
// rival's best is charged for it), so that no two cards end up the same patch; a simple sound's
// Detailed card is then a different take on it rather than the Simple one again. A search
// keeps its best few candidates of different structures, and picks its best from them against
// its rivals as they are now (`reselect`), so that a rival arriving at its answer later moves
// it to its next best rather than leaving two cards the same.
//
// Each starts from the target's seed (Genome.seed), tries every first oscillator wave with
// every filter type there, then refines the best with CMA-ES (Cmaes.res) in two stages (see
// `phase`). A search only decides what to try (`ask`) and learns from the scores (`tell`);
// the rendering and scoring (`evaluate`) happen in the workers, each candidate on its own, so
// that one generation spreads over all of them.
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
    blurb: "Everything free, and a different take from the other three: layers, modulation and effects where they help",
    weights: MatchLoss.standard,
    bounds: [],
    rivals: [1, 2, 3],
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
    rivals: [],
  },
  {
    key: "punchy",
    title: "Punchy",
    blurb: "The attack matters most: tight envelopes, dry",
    weights: {envelope: 1.2, early: 3., treble: 1., resolutions: [0.6, 1., 1.6]},
    bounds: [off("chorus"), off("reverb")],
    rivals: [1],
  },
  {
    key: "lush",
    title: "Lush",
    blurb: "The tone matters most, made wider with unison, chorus and reverb",
    weights: {envelope: 0.25, early: 1., treble: 1., resolutions: [1.6, 1., 0.4]},
    bounds: [atLeast("unison", 1), ("chorus", 0.3, 1.), ("reverb", 0.3, 1.)],
    rivals: [1, 2],
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
  base: Bank.values,
  // the base's output gain, which a candidate's level is set from
  baseGain: float,
}

let makeContext = (engine, target: SoundTarget.t, ~base: Bank.values, ~tables) => {
  MatchEngine.setBase(engine, base, tables)
  {
    engine,
    target,
    measured: Spectrum.measure(target.samples, ~period=SoundTarget.period(target)),
    base,
    baseGain: base->Map.get("Gain")->Option.getOr(0.1),
  }
}

let baseValue = (ctx, id) => ctx.base->Map.get(id)->Option.getOr(0.)

let frames = ctx => TypedArray.length(ctx.target.samples)

let renderGenes = (ctx, x) => {
  let values = Genome.decode(x, ~note=ctx.target.note, ~base=baseValue(ctx, _))
  let y = MatchEngine.render(ctx.engine, values, ~note=ctx.target.note, ~cents=ctx.target.cents, ~frames=frames(ctx))
  (values, y)
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
  similarity: float,
  description: string,
  // its loudness envelope (64 steps) and average spectrum (48 bands) in dB, at the target's
  // overall loudness, for the card's picture
  envelope: array<float>,
  spectrum: array<float>,
}

let envelopePoints = 64

let candidateOf = (ctx, x, values, y, f: Spectrum.features) => {
  let gain = f.energy > 0. ? Math.sqrt(ctx.measured.energy / f.energy) : 1.
  {
    island: -1,
    slot: -1,
    genes: Array.fromInitializer(~length=TypedArray.length(x), i => x->get64(i)),
    values: values->Array.concat([("Gain", levelGain(ctx, y))]),
    similarity: MatchLoss.similarity(MatchLoss.compare(MatchLoss.standard, ctx.measured, f)),
    description: Genome.describe(x),
    envelope: Spectrum.envelopeOverview(f, ~points=envelopePoints, ~gain),
    spectrum: Spectrum.averageSpectrum(f, ~gain),
  }
}

let cost = x => partCost * Int.toFloat(Genome.parts(x))

// Renders x and scores it by these weights (with its parts' cost); the candidate too if it
// scores under `threshold` (the search's best so far: only a new best is shown).
let evaluate = (ctx, x, ~weights, ~threshold) => {
  let (values, y) = renderGenes(ctx, x)
  let f = Spectrum.measure(y, ~period=SoundTarget.period(ctx.target))
  let loss = MatchLoss.compare(weights, ctx.measured, f) + cost(x)
  (loss, loss < threshold ? Some(candidateOf(ctx, x, values, y, f)) : None)
}

// The target's picture, in the candidates' terms.
let targetPicture = (measured: Spectrum.features) => (
  Spectrum.envelopeOverview(measured, ~points=envelopePoints),
  Spectrum.averageSpectrum(measured),
)

//==============================================================================
// A search (in the view)

// Bounds for a search: its island's, and the locked groups held at `reference`'s values.
let boundsFor = (island, ~locks: array<Genome.group>, ~reference: option<Float64Array.t>) => {
  let lo = Float64Array.fromLength(Genome.count)
  let hi = Float64Array.fromLength(Genome.count)
  hi->TypedArray.fillAll(1.)->ignore
  island.bounds->Array.forEach(((key, a, b)) => {
    let i = Genome.indexOf(key)
    lo->set64(i, a)
    hi->set64(i, b)
  })
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

// A search goes in two stages: the core genes (the first oscillator, the filter and the
// envelopes) with the rest held where they start, then every gene its island leaves free, from
// the best of the first. Fewer genes at first get the sound's outline right sooner than all
// of them at once, and the parts on top are then tried against a good outline.
type phase =
  | Grid(array<Float64Array.t>)
  | Core(Cmaes.t)
  | Full(Cmaes.t)
  | Finished

// A candidate a search keeps: its score without the niche charges, and its structure.
type entry = {raw: float, genes: Float64Array.t, candidate: candidate, shape: array<int>}

type rec search = {
  islandIndex: int,
  island: island,
  lo: Float64Array.t,
  hi: Float64Array.t,
  // the first stage's bounds: the others held at the start
  coreLo: Float64Array.t,
  coreHi: Float64Array.t,
  start: Float64Array.t,
  budget: int,
  // evaluations for the first stage (all of them when the second would free nothing more)
  coreBudget: int,
  sigma: float,
  seed: int,
  mutable phase: phase,
  mutable evals: int,
  mutable bestLoss: float,
  mutable best: option<candidate>,
  mutable bestGenes: option<Float64Array.t>,
  // the searches running beside it that it keeps away from (MatchRun sets them)
  mutable rivals: array<search>,
  // its best candidates, one per structure, best first
  mutable archive: array<entry>,
}

let clampInto = (x: Float64Array.t, lo, hi) => {
  let y = TypedArray.copy(x)
  for i in 0 to TypedArray.length(y) - 1 {
    y->set64(i, Math.max(lo->get64(i), Math.min(hi->get64(i), y->get64(i))))
  }
  y
}

// How far apart two patches are: the root mean square of their continuous genes' differences,
// with a different choice counting as 0.5.
let distance = (x: Float64Array.t, y: Float64Array.t) => {
  let sum = ref(0.)
  Genome.genes->Array.forEachWithIndex((g, i) => {
    let (a, b) = (x->get64(i), y->get64(i))
    let d = g.options == 0 ? a -. b : Genome.choiceOf(a, g.options) == Genome.choiceOf(b, g.options) ? 0. : 0.5
    sum := sum.contents + d * d
  })
  Math.sqrt(sum.contents / Int.toFloat(Genome.count))
}

// what a candidate on top of a rival's best is charged (about 14% of match), less the further
// away it is, nothing from this far; and what having the same structure (Genome.structure) as
// a rival's best costs (about 8%), so that cards differ in what they are made of, not just in
// their knobs
let nicheCost = 0.15
let nicheReach = 0.1
let structureCost = 0.08

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

// The starting grid: the start with each allowed first wave and filter type.
let gridOf = (start, lo, hi) => {
  let options = key => {
    let i = Genome.indexOf(key)
    let k = Genome.gene(i).options
    Array.fromInitializer(~length=k, o => Genome.valueOfChoice(o, k))->Array.filter(v =>
      v >= lo->get64(i) - 1e-9 && v <= hi->get64(i) + 1e-9
    )
  }
  let waves = options("o1Wave")
  let filters = options("filterType")
  if Array.length(waves) * Array.length(filters) <= 1 {
    []
  } else {
    waves->Array.flatMap(w =>
      filters->Array.map(f => {
        let x = TypedArray.copy(start)
        x->set64(Genome.indexOf("o1Wave"), w)
        x->set64(Genome.indexOf("filterType"), f)
        x
      })
    )
  }
}

let makeSearch = (islandIndex, ~start, ~locks, ~reference, ~budget, ~sigma, ~seed) => {
  let island = islands->Array.getUnsafe(islandIndex)
  let (lo, hi) = boundsFor(island, ~locks, ~reference)
  let start = clampInto(start, lo, hi)
  let coreLo = TypedArray.copy(lo)
  let coreHi = TypedArray.copy(hi)
  let more = ref(false)
  Genome.genes->Array.forEachWithIndex((g, i) =>
    if !(Genome.core->Array.includes(g.key)) {
      more := more.contents || hi->get64(i) > lo->get64(i)
      coreLo->set64(i, start->get64(i))
      coreHi->set64(i, start->get64(i))
    }
  )
  {
    islandIndex,
    island,
    lo,
    hi,
    coreLo,
    coreHi,
    start,
    budget,
    coreBudget: more.contents ? budget * 9 / 20 : budget,
    sigma,
    seed,
    // the start itself first, so a re-match never does worse than what it began from
    phase: Grid([start, ...gridOf(start, coreLo, coreHi)]),
    evals: 0,
    bestLoss: infinity,
    best: None,
    bestGenes: None,
    rivals: [],
    archive: [],
  }
}

let options = Genome.genes->Array.map(g => g.options)

let evolve = (s, ~lo, ~hi, ~sigma, ~seed) =>
  Cmaes.make(~start=s.bestGenes->Option.getOr(s.start), ~lo, ~hi, ~options, ~sigma, ~seed)

let isDone = s =>
  switch s.phase {
  | Finished => true
  | Grid(_) | Core(_) | Full(_) => false
  }

// how small the step gets before a stage has nothing more to find
let settled = 0.004

// What a search tries next: the genes, and the samples they came from (for `tell`).
type pending = {genes: array<Float64Array.t>, samples: option<(Cmaes.t, array<Cmaes.sample>)>}

let ask = s =>
  switch s.phase {
  | Finished => {genes: [], samples: None}
  | Grid(points) => {genes: points, samples: None}
  | Core(es) | Full(es) =>
    let samples = Cmaes.ask(es)
    {genes: samples->Array.map(sample => sample.x), samples: Some((es, samples))}
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

// Picks the best of the archive against the rivals as they are now; true if it changed.
let reselect = s =>
  switch s.archive->Array.reduce(None, (best, e) => {
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
    s.best = Some({...e.candidate, island: s.islandIndex, slot: s.islandIndex})
    changed
  | None => false
  }

// Learns from the scores of what `ask` gave (with what keeping away from its rivals costs);
// true if the best changed.
let tell = (s, pending, results: array<(float, option<candidate>)>) => {
  let losses = results->Array.mapWithIndex(((loss, _), i) => loss + apart(s, pending.genes->Array.getUnsafe(i)))
  results->Array.forEachWithIndex(((raw, candidate), i) =>
    candidate->Option.forEach(c => remember(s, raw, pending.genes->Array.getUnsafe(i), c))
  )
  let improved = reselect(s)
  s.evals = s.evals + Array.length(results)
  switch (s.phase, pending.samples) {
  | (Grid(_), _) => s.phase = Core(evolve(s, ~lo=s.coreLo, ~hi=s.coreHi, ~sigma=s.sigma, ~seed=s.seed))
  | (Core(es), Some((asked, samples))) if es === asked =>
    Cmaes.tell(es, samples, losses)
    if s.evals >= s.coreBudget || es.sigma < settled {
      s.phase =
        s.evals >= s.budget
          ? Finished
          : Full(evolve(s, ~lo=s.lo, ~hi=s.hi, ~sigma=0.6 * s.sigma, ~seed=s.seed + 1))
    }
  | (Full(es), Some((asked, samples))) if es === asked =>
    Cmaes.tell(es, samples, losses)
    if s.evals >= s.budget || es.sigma < settled {
      s.phase = Finished
    }
  | _ => ()
  }
  improved
}

//==============================================================================
// Variations

// `count` mutants of x: each unlocked continuous gene moved by about amount × 0.35, each
// unlocked choice changed with probability amount / 2.
let mutants = (x: Float64Array.t, ~locks: array<Genome.group>, ~amount, ~count, ~seed) => {
  let random = Cmaes.makeRandom(seed)
  let gaussian = () => {
    let u = Math.max(random(), 1e-12)
    Math.sqrt(-2. * Math.log(u)) * Math.cos(2. * Math.Constants.pi * random())
  }
  Array.fromInitializer(~length=count, _ => {
    let y = TypedArray.copy(x)
    Genome.genes->Array.forEachWithIndex((g, i) =>
      if !(locks->Array.includes(g.group)) {
        if g.options == 0 {
          y->set64(i, Genome.clamp01(x->get64(i) + amount * 0.35 * gaussian()))
        } else if random() < amount * 0.5 {
          y->set64(i, Genome.valueOfChoice(Float.toInt(random() * Int.toFloat(g.options)), g.options))
        }
      }
    )
    y
  })
}
