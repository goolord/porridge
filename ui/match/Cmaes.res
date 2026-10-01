// The sound matcher's optimizer: a separable CMA-ES (Ros and Hansen, 2008: covariance matrix
// adaptation with a diagonal matrix, which learns quickly enough for the few hundred renders a
// match can afford) over the continuous genes, and for each choice gene a probability per
// option, moved each generation towards the options of the best candidates.
//
// Genes stay within bounds (lo .. hi, both within 0..1): a sample outside is moved to the
// edge, and the moved value is what the update learns from. A gene with lo = hi is held still;
// a choice gene can take the options whose middles are within its bounds.

@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

// mulberry32: a seeded generator, so a search can be repeated
let makeRandom: int => unit => float = %raw(`seed => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}`)

type choiceGene = {
  index: int,
  options: int,
  // the options it may take, and the probability of each
  allowed: array<int>,
  probs: Float64Array.t,
}

type t = {
  lo: Float64Array.t,
  hi: Float64Array.t,
  // all the genes: the free continuous ones are the distribution's mean, the others as they are held
  mean: Float64Array.t,
  // the free continuous genes
  free: array<int>,
  choices: array<choiceGene>,
  mutable sigma: float,
  diag: Float64Array.t,
  pc: Float64Array.t,
  ps: Float64Array.t,
  lambda: int,
  weights: array<float>,
  mueff: float,
  cc: float,
  cs: float,
  c1: float,
  cmu: float,
  damps: float,
  chiN: float,
  mutable generation: int,
  random: unit => float,
  mutable spare: option<float>,
}

type sample = {
  x: Float64Array.t,
  // the step that made it, in the distribution's own units (free genes only)
  z: Float64Array.t,
  // the option each choice gene took (an index into its allowed)
  picks: array<int>,
}

let gaussian = t =>
  switch t.spare {
  | Some(v) =>
    t.spare = None
    v
  | None =>
    let u = Math.max(t.random(), 1e-12)
    let v = t.random()
    let r = Math.sqrt(-2. * Math.log(u))
    t.spare = Some(r * Math.sin(2. * Math.Constants.pi * v))
    r * Math.cos(2. * Math.Constants.pi * v)
  }

let clampTo = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

// options: per gene, 0 for continuous or its number of choices
let make = (~start: Float64Array.t, ~lo: Float64Array.t, ~hi: Float64Array.t, ~options: array<int>, ~sigma, ~seed, ~lambda=?) => {
  let n = TypedArray.length(start)
  let mean = Float64Array.fromLength(n)
  for i in 0 to n - 1 {
    mean->set64(i, clampTo(start->get64(i), lo->get64(i), hi->get64(i)))
  }
  let free = []
  let choices = []
  for i in 0 to n - 1 {
    let k = options->Array.getUnsafe(i)
    let (a, b) = (lo->get64(i), hi->get64(i))
    if k == 0 {
      if b > a {
        free->Array.push(i)
      }
    } else {
      let allowed =
        Array.fromInitializer(~length=k, o => o)->Array.filter(o => {
          let c = Genome.valueOfChoice(o, k)
          c >= a - 1e-9 && c <= b + 1e-9
        })
      let current = Genome.choiceOf(mean->get64(i), k)
      switch allowed {
      | [] => ()
      | [only] => mean->set64(i, Genome.valueOfChoice(only, k))
      | _ =>
        let m = Array.length(allowed)
        let has = allowed->Array.includes(current)
        let probs = Float64Array.fromLength(m)
        allowed->Array.forEachWithIndex((o, j) =>
          probs->set64(j, has ? (o == current ? 0.5 : 0.) + 0.5 / Int.toFloat(m) : 1. / Int.toFloat(m))
        )
        choices->Array.push({index: i, options: k, allowed, probs})
      }
    }
  }
  let d = Array.length(free)
  let dim = Int.toFloat(Math.Int.max(1, d))
  let lambda = lambda->Option.getOr(4 + Float.toInt(3. * Math.log(dim)))
  let mu = lambda / 2
  let raw = Array.fromInitializer(~length=mu, i =>
    Math.log(Int.toFloat(mu) + 0.5) - Math.log(Int.toFloat(i + 1))
  )
  let sum = raw->Array.reduce(0., (s, w) => s + w)
  let weights = raw->Array.map(w => w / sum)
  let mueff = 1. / weights->Array.reduce(0., (s, w) => s + w * w)
  let cs = (mueff + 2.) / (dim + mueff + 5.)
  let damps = 1. + 2. * Math.max(0., Math.sqrt((mueff - 1.) / (dim + 1.)) - 1.) + cs
  let cc = (4. + mueff / dim) / (dim + 4. + 2. * mueff / dim)
  // the separable variant learns (n + 2) / 3 times as fast
  let speed = (dim + 2.) / 3.
  let c1 = Math.min(1., speed * 2. / ((dim + 1.3) * (dim + 1.3) + mueff))
  let cmu = Math.min(
    1. - c1,
    speed * 2. * (mueff - 2. + 1. / mueff) / ((dim + 2.) * (dim + 2.) + mueff),
  )
  let diag = Float64Array.fromLength(d)
  diag->TypedArray.fillAll(1.)->ignore
  {
    lo,
    hi,
    mean,
    free,
    choices,
    sigma,
    diag,
    pc: Float64Array.fromLength(d),
    ps: Float64Array.fromLength(d),
    lambda,
    weights,
    mueff,
    cc,
    cs,
    c1,
    cmu,
    damps,
    chiN: Math.sqrt(dim) * (1. - 1. / (4. * dim) + 1. / (21. * dim * dim)),
    generation: 0,
    random: makeRandom(seed),
    spare: None,
  }
}

let pick = (t, probs: Float64Array.t) => {
  let u = t.random()
  let acc = ref(0.)
  let chosen = ref(TypedArray.length(probs) - 1)
  let found = ref(false)
  probs->TypedArray.forEachWithIndex((p, j) => {
    acc := acc.contents + p
    if !found.contents && u < acc.contents {
      chosen := j
      found := true
    }
  })
  chosen.contents
}

let ask = t =>
  Array.fromInitializer(~length=t.lambda, _ => {
    let x = TypedArray.copy(t.mean)
    let z = Float64Array.fromLength(Array.length(t.free))
    t.free->Array.forEachWithIndex((i, j) => {
      let v = t.mean->get64(i) + t.sigma * Math.sqrt(t.diag->get64(j)) * gaussian(t)
      let v = clampTo(v, t.lo->get64(i), t.hi->get64(i))
      x->set64(i, v)
      // the step as it was taken, after the move back within bounds
      z->set64(j, (v - t.mean->get64(i)) / (t.sigma * Math.sqrt(t.diag->get64(j))))
    })
    let picks = t.choices->Array.map(c => {
      let j = pick(t, c.probs)
      x->set64(c.index, Genome.valueOfChoice(c.allowed->Array.getUnsafe(j), c.options))
      j
    })
    {x, z, picks}
  })

// Learns from a generation: its samples with their losses (lower is better).
let tell = (t, samples: array<sample>, losses: array<float>) => {
  let order =
    Array.fromInitializer(~length=Array.length(samples), i => i)->Array.toSorted((a, b) =>
      Float.compare(losses->Array.getUnsafe(a), losses->Array.getUnsafe(b))
    )
  let best = Array.fromInitializer(~length=Array.length(t.weights), r =>
    samples->Array.getUnsafe(order->Array.getUnsafe(Math.Int.min(r, Array.length(order) - 1)))
  )
  let d = Array.length(t.free)
  t.generation = t.generation + 1

  if d > 0 {
    // the new mean, and the weighted step (zw) in the distribution's units
    let zw = Float64Array.fromLength(d)
    t.free->Array.forEachWithIndex((i, j) => {
      let m = ref(0.)
      let z = ref(0.)
      best->Array.forEachWithIndex((s, r) => {
        let w = t.weights->Array.getUnsafe(r)
        m := m.contents + w * s.x->get64(i)
        z := z.contents + w * s.z->get64(j)
      })
      t.mean->set64(i, m.contents)
      zw->set64(j, z.contents)
    })
    let csFactor = Math.sqrt(t.cs * (2. - t.cs) * t.mueff)
    let psNorm = ref(0.)
    for j in 0 to d - 1 {
      let v = (1. - t.cs) * t.ps->get64(j) + csFactor * zw->get64(j)
      t.ps->set64(j, v)
      psNorm := psNorm.contents + v * v
    }
    let psNorm = Math.sqrt(psNorm.contents)
    let g = Int.toFloat(t.generation)
    let hsig =
      psNorm / Math.sqrt(1. - Math.pow(1. - t.cs, ~exp=2. * g)) <
        (1.4 + 2. / (Int.toFloat(d) + 1.)) * t.chiN
    let ccFactor = Math.sqrt(t.cc * (2. - t.cc) * t.mueff)
    for j in 0 to d - 1 {
      let yw = Math.sqrt(t.diag->get64(j)) * zw->get64(j)
      let pc = (1. - t.cc) * t.pc->get64(j) + (hsig ? ccFactor * yw : 0.)
      t.pc->set64(j, pc)
      let rankMu = ref(0.)
      best->Array.forEachWithIndex((s, r) => {
        let y = Math.sqrt(t.diag->get64(j)) * s.z->get64(j)
        rankMu := rankMu.contents + t.weights->Array.getUnsafe(r) * y * y
      })
      let c = t.diag->get64(j)
      let lost = hsig ? 0. : t.cc * (2. - t.cc) * c
      t.diag->set64(
        j,
        Math.max(1e-8, (1. - t.c1 - t.cmu) * c + t.c1 * (pc * pc + lost) + t.cmu * rankMu.contents),
      )
    }
    t.sigma = Math.min(0.6, t.sigma * Math.exp(t.cs / t.damps * (psNorm / t.chiN - 1.)))
  }

  // the choices: towards the best candidates' options, never quite giving one up
  t.choices->Array.forEachWithIndex((c, ci) => {
    let m = TypedArray.length(c.probs)
    let rate = 0.3
    let floor = 0.04
    let target = Float64Array.fromLength(m)
    best->Array.forEachWithIndex((s, r) => {
      let j = s.picks->Array.getUnsafe(ci)
      target->set64(j, target->get64(j) + t.weights->Array.getUnsafe(r))
    })
    let sum = ref(0.)
    for j in 0 to m - 1 {
      let p = Math.max(floor, (1. - rate) * c.probs->get64(j) + rate * target->get64(j))
      c.probs->set64(j, p)
      sum := sum.contents + p
    }
    let top = ref(0)
    for j in 0 to m - 1 {
      c.probs->set64(j, c.probs->get64(j) / sum.contents)
      if c.probs->get64(j) > c.probs->get64(top.contents) {
        top := j
      }
    }
    t.mean->set64(c.index, Genome.valueOfChoice(c.allowed->Array.getUnsafe(top.contents), c.options))
  })
}
