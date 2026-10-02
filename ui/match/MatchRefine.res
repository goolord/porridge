// Refining a match's card (the drawer's "refine"): additions on top of its patch, beyond what
// the genes can make, that bring it closer to the sample: an effect in the rack (a delay, an
// algo reverb, an ambience, a flanger, a phaser, a compressor, a filter, a distortion, a width,
// a frequency shifter, an air), or a new modulation in the mod matrix (mod env 2, LFO 2, the
// noise source, or the amp or filter envelope, on the pitch, the level, the cutoff, osc 2's
// level or the PM depth and so on).
//
// A round at a time: every addition the patch can still take is tried at its starting settings,
// the few that come closest are each tuned by a short CMA-ES over its knobs (as positions 0..1),
// and the best is kept if it is closer by more than an addition costs. Up to `maxAdditions`
// rounds, or until nothing helps. The card as it was and the patch after each kept addition are
// the cards of the drawer's row.
//
// The patch's own values stay as they are (its envelope and key EQ were fitted to it without
// these); each candidate is rendered whole (MatchSearch.evaluateValues), as it would play.

@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

// A knob an addition tunes: its parameters (several move together, as a delay's two sides do),
// as one position 0..1 between lo and hi of their range's knob positions; init is where it
// starts.
type knob = {ids: array<string>, lo: float, hi: float, init: float}

type addition = {
  key: string,
  // what the card's description adds
  label: string,
  fixed: array<(string, float)>,
  knobs: array<knob>,
}

let def = Genome.def
let knob = (~lo=0., ~hi=1., ~init=?, ids: array<string>) => {
  let d = def(ids->Array.getUnsafe(0))
  let start = init->Option.getOr(d.toNorm(d.init))
  {ids, lo, hi, init: Math.max(0., Math.min(1., (start - lo) / Math.max(hi - lo, 1e-9)))}
}
// a knob starting at a value of its own (in the parameter's units)
let knobAt = (~lo=0., ~hi=1., ids: array<string>, value) =>
  knob(~lo, ~hi, ~init=def(ids->Array.getUnsafe(0)).toNorm(value), ids)

let addCost = 0.01
let maxAdditions = 3
let tuneCount = 3
let tuneGenerations = 8

//==============================================================================
// What can be added

// The effects the matcher's engine has one of: every kind's first (the rack's distortions start
// at 2), and only while the rack has room and doesn't hold one of its kind already.
let effectAdditions = (rack: array<FxRack.effect>) => {
  let make = (kind, ~key, ~label, ~fixed: (string => string) => array<(string, float)>, ~knobs: (string => string) => array<knob>) =>
    switch FxRack.free(rack, kind) {
    | Some(e) if !(rack->Array.some(x => x.kind == kind)) =>
      let id = first => FxRack.id(e, first)
      Some({
        key,
        label,
        fixed: [FxRack.values(Array.concat(rack, [e])), [(FxRack.switchId(e), FxRack.onValue(e))], fixed(id)]->Array.flat,
        knobs: knobs(id),
      })
    | _ => None
    }
  [
    make(
      #delay,
      ~key="delay",
      ~label="delay",
      ~fixed=id => [
        (id("D_Unit"), 1.),
        (id("D_Quantize"), 0.),
        (id("D_ReverseL"), 0.),
        (id("D_ReverseR"), 0.),
        (id("D_Rotation"), 0.),
        (id("D_InputPan"), 0.5),
        (id("D_HP"), 0.),
        (id("D_Dry"), 1.),
      ],
      ~knobs=id => [
        knobAt([id("D_LengthL"), id("D_LengthR")], 12.),
        knobAt(~lo=0.5, [id("D_FeedbackL"), id("D_FeedbackR")], 0.3),
        knob([id("D_LP")]),
        knobAt(~hi=0.7, [id("D_Wet")], 0.3),
      ],
    ),
    make(
      #space,
      ~key="hall",
      ~label="algo reverb",
      ~fixed=id => [(id("Rv_Model"), 0.), (id("Rv_Predelay"), 0.)],
      ~knobs=id => [knob([id("Rv_Size")]), knob([id("Rv_Decay")]), knob([id("Rv_Damp")]), knobAt([id("Rv_Mix")], 0.2)],
    ),
    make(
      #ambience,
      ~key="ambience",
      ~label="ambience",
      ~fixed=id => [(id("Am_Model"), 0.), (id("Am_Predelay"), 0.)],
      ~knobs=id => [knob([id("Am_Size")]), knob([id("Am_Time")]), knobAt([id("Am_Mix")], 0.25)],
    ),
    make(
      #flanger,
      ~key="flanger",
      ~label="flanger",
      ~fixed=_ => [],
      ~knobs=id => [knob([id("Fl_Rate")]), knob([id("Fl_Depth")]), knob([id("Fl_Delay")]), knob([id("Fl_Feedback")]), knobAt([id("Fl_Mix")], 0.3)],
    ),
    make(
      #phaser,
      ~key="phaser",
      ~label="phaser",
      ~fixed=_ => [],
      ~knobs=id => [knob([id("Ph_Rate")]), knob([id("Ph_Depth")]), knob([id("Ph_Freq")]), knob([id("Ph_Feedback")]), knobAt([id("Ph_Mix")], 0.3)],
    ),
    make(
      #compressor,
      ~key="compressor",
      ~label="compressor",
      ~fixed=id => [(id("Cp_Bands"), 0.), (id("Cp_Mix"), 1.)],
      ~knobs=id => [knob([id("Cp_Depth")]), knob([id("Cp_Attack")]), knob([id("Cp_Release")]), knobAt([id("Cp_InGain")], 6.)],
    ),
    make(
      #filter,
      ~key="fx filter",
      ~label="filter",
      ~fixed=_ => [],
      ~knobs=id => [knob([id("Ff_Cutoff")]), knob([id("Ff_Morph")]), knob([id("Ff_Resonance")]), knobAt([id("Ff_Mix")], 0.6)],
    ),
    make(
      #distortion,
      ~key="distortion",
      ~label="distortion",
      ~fixed=_ => [],
      ~knobs=id => [knobAt([id("Sat_Pregain")], 12.), knobAt([id("Sat_Postgain")], -6.)],
    ),
    make(
      #utility,
      ~key="width",
      ~label="width",
      ~fixed=_ => [],
      ~knobs=id => [knobAt([id("Ut_Width")], 1.4)],
    ),
    make(
      #bode,
      ~key="shifter",
      ~label="freq shifter",
      ~fixed=_ => [],
      ~knobs=id => [knob([id("Bd_Shift")]), knob([id("Bd_Feedback")]), knobAt([id("Bd_Mix")], 0.3)],
    ),
    make(
      #air,
      ~key="air",
      ~label="air",
      ~fixed=_ => [],
      ~knobs=id => [knob([id("Ai_Air")]), knob([id("Ai_Body")])],
    ),
  ]->Array.filterMap(a => a)
}

// The modulations tried: (source, target), the source's key and the target's (ModMatrix).
let modPairs = [
  ("modEnv2", "finePitch"),
  ("modEnv2", "pitch"),
  ("modEnv2", "Cutoff"),
  ("modEnv2", "Resonance"),
  ("modEnv2", "O2_Amp"),
  ("modEnv2", "PM_Feedback"),
  ("modEnv2", "Transpose"),
  ("modEnv2", "Detune"),
  ("modEnv2", "N_Amp"),
  ("modEnv2", "volume"),
  ("lfo2", "volume"),
  ("lfo2", "pan"),
  ("lfo2", "O2_Amp"),
  ("lfo2", "PM_Feedback"),
  ("lfo2", "Detune"),
  ("lfo2", "finePitch"),
  ("noise", "finePitch"),
  ("noise", "Cutoff"),
  ("noise", "volume"),
  ("noise", "O2_Amp"),
  ("ampEnv", "Cutoff"),
  ("ampEnv", "O2_Amp"),
  ("ampEnv", "PM_Feedback"),
  ("ampEnv", "Resonance"),
  ("filterEnv", "O2_Amp"),
  ("filterEnv", "PM_Feedback"),
]

let sourceName = key => ModMatrix.sources->Array.find(s => s.key == key)->Option.mapOr(key, s => s.label)
let targetName = key => ModMatrix.targets->Array.find(t => t.key == key)->Option.mapOr(key, t => t.label)

// Each pair through the first free slot, its amount starting a little either way of nothing;
// mod env 2 with its attack, decay and (falling to nothing) the rest set, LFO 2 with its rate
// unless the patch's filter wobble has it.
let modAdditions = (get: string => float, ~taken: array<string>) =>
  switch ModMatrix.slotNumbers->Array.find(k => get(ModMatrix.sourceId(k)) == 0.) {
  | None => []
  | Some(k) =>
    let wobbles = get("LFO_2_Cutoff_1") != 0.
    modPairs
    ->Array.filter(((s, t)) => !(taken->Array.includes(s ++ ">" ++ t)))
    ->Array.flatMap(((source, target)) =>
      [-0.25, 0.25]->Array.map(amount => {
        let fixed = [
          (ModMatrix.sourceId(k), Int.toFloat(ModMatrix.sourceIndex(source))),
          (ModMatrix.targetId(k), Int.toFloat(ModMatrix.targetIndex(target))),
          (ModMatrix.viaId(k), 0.),
        ]
        let (sourceFixed, sourceKnobs) = switch source {
        | "modEnv2" => (
            [("M2_Hold", 0.), ("M2_Decay1", 10.), ("M2_Breakpoint", 1.), ("M2_Sustain", 0.), ("M2_Release", 200.), ("M2_VeloSens", 0.)],
            [knobAt(["M2_Attack"], 2.), knobAt(["M2_Decay2"], 200.)],
          )
        | "lfo2" if !wobbles => ([("LFO_2_Unit", 1.), ("LFO_2_Shape", 0.), ("LFO_2_Sync", 0.)], [knobAt(["LFO_2_Speed"], 20.)])
        | _ => ([], [])
        }
        {
          key: source ++ ">" ++ target,
          label: `${sourceName(source)} > ${targetName(target)}`,
          fixed: Array.concat(fixed, sourceFixed),
          knobs: Array.concat([knobAt([ModMatrix.amountId(k)], amount)], sourceKnobs),
        }
      })
    )
  }

//==============================================================================
// Searching

// The values a patch is with an addition at knob positions x (each 0..1 within its range).
let valuesWith = (current: array<(string, float)>, a: addition, x: Float64Array.t) => {
  let m = Map.fromArray(current)
  a.fixed->Array.forEach(((id, v)) => m->Map.set(id, v))
  a.knobs->Array.forEachWithIndex((k, i) => {
    let position = k.lo + (k.hi - k.lo) * Math.max(0., Math.min(1., x->get64(i)))
    k.ids->Array.forEach(id => m->Map.set(id, def(id).fromNorm(position)))
  })
  m->Map.entries->Array.fromIterator
}

let startOf = (a: addition) => Float64Array.fromArray(a.knobs->Array.map(k => k.init))

type run = {
  addition: addition,
  es: Cmaes.t,
  mutable best: (float, Float64Array.t, MatchSearch.valued),
}

type stage =
  | Base
  | Try(array<addition>)
  | Tune(array<run>, int)
  | Done

// a patch the refinement has: its additions, values and how it scored
type step = {additions: array<addition>, values: array<(string, float)>, valued: MatchSearch.valued}

type t = {
  note: int,
  // the base's value of whatever the patch doesn't set (Init's)
  base: string => float,
  mutable current: array<(string, float)>,
  mutable loss: float,
  mutable taken: array<addition>,
  mutable stage: stage,
  mutable evals: int,
  budget: int,
  mutable steps: array<step>,
  seed: int,
}

let make = (~values, ~note, ~base, ~budget, ~seed) => {
  note,
  base,
  current: values->Array.filter(((id, _)) => id != "Gain"),
  loss: infinity,
  taken: [],
  stage: Base,
  evals: 0,
  budget,
  steps: [],
  seed,
}

let getter = (t, values: array<(string, float)>) => {
  let m = Map.fromArray(values)
  id => m->Map.get(id)->Option.getOr(t.base(id))
}

let candidates = t => {
  let get = getter(t, t.current)
  Array.concat(
    effectAdditions(FxRack.read(get)),
    modAdditions(get, ~taken=t.taken->Array.map(a => a.key)),
  )
}

let isDone = t => t.stage == Done

// What to render next: patches as values, and the runs' samples they are (for `tell`).
type pending = {values: array<array<(string, float)>>, samples: array<(run, array<Cmaes.sample>)>}

let ask = t =>
  switch t.stage {
  | Base => {values: [t.current], samples: []}
  | Try(adds) => {values: adds->Array.map(a => valuesWith(t.current, a, startOf(a))), samples: []}
  | Tune(runs, _) =>
    let samples = runs->Array.map(r => (r, Cmaes.ask(r.es)))
    {
      values: samples->Array.flatMap(((r, xs)) => xs->Array.map(s => valuesWith(t.current, r.addition, s.x))),
      samples,
    }
  | Done => {values: [], samples: []}
  }

// Starts the next round, unless the patch has all it may have or the renders are spent.
let nextRound = t =>
  t.stage =
    Array.length(t.taken) >= maxAdditions || t.evals >= t.budget
      ? Done
      : switch candidates(t) {
        | [] => Done
        | adds => Try(adds)
        }

// Learns from the scores of what `ask` gave (in its order).
let tell = (t, pending, valued: array<MatchSearch.valued>) => {
  t.evals = t.evals + Array.length(valued)
  switch t.stage {
  | Base =>
    let v = valued->Array.getUnsafe(0)
    t.loss = v.loss
    t.steps = [{additions: [], values: t.current, valued: v}]
    nextRound(t)
  | Try(adds) =>
    let ranked =
      adds
      ->Array.mapWithIndex((a, i) => (a, valued->Array.getUnsafe(i)))
      ->Array.toSorted(((_, a), (_, b)) => Float.compare(a.loss, b.loss))
      ->Array.slice(~start=0, ~end=tuneCount)
    let runs = ranked->Array.mapWithIndex(((a, v), i) => {
      let start = startOf(a)
      let d = TypedArray.length(start)
      {
        addition: a,
        es: Cmaes.make(
          ~start,
          ~lo=Float64Array.fromLength(d),
          ~hi=Float64Array.fromLength(d)->TypedArray.fillAll(1.),
          ~options=Array.make(~length=d, 0),
          ~sigma=0.15,
          ~seed=t.seed + 31 * Array.length(t.taken) + i,
        ),
        best: (v.loss, start, v),
      }
    })
    t.stage = runs == [] ? Done : Tune(runs, tuneGenerations)
  | Tune(runs, generations) =>
    let at = ref(0)
    pending.samples->Array.forEach(((r, xs)) => {
      let scored = xs->Array.mapWithIndex((_, i) => valued->Array.getUnsafe(at.contents + i))
      xs->Array.forEachWithIndex((s, i) => {
        let v = scored->Array.getUnsafe(i)
        let (best, _, _) = r.best
        if v.loss < best {
          r.best = (v.loss, TypedArray.copy(s.x), v)
        }
      })
      Cmaes.tell(r.es, xs, scored->Array.map(v => v.loss))
      at := at.contents + Array.length(xs)
    })
    if generations > 1 && t.evals < t.budget {
      t.stage = Tune(runs, generations - 1)
    } else {
      // the best run's best, kept if it is closer by more than it costs
      let winner = runs->Array.reduce(None, (best, r) => {
        let (l, _, _) = r.best
        switch best {
        | Some(b) if {
            let (bl, _, _) = b.best
            bl <= l
          } => best
        | _ => Some(r)
        }
      })
      switch winner {
      | Some(r) =>
        let (l, x, v) = r.best
        if l + addCost < t.loss {
          t.current = valuesWith(t.current, r.addition, x)
          t.loss = l
          t.taken = Array.concat(t.taken, [r.addition])
          t.steps = Array.concat(t.steps, [{additions: t.taken, values: t.current, valued: v}])
          nextRound(t)
        } else {
          t.stage = Done
        }
      | None => t.stage = Done
      }
    }
  | Done => ()
  }
}
