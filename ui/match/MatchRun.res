// Runs a match (MatchSearch.res) in the view: the outline first, then the four searches side
// by side, each keeping away from its rivals' best so far. Each search asks for a round of
// candidates, every one of them goes to the workers to be rendered and scored on its own (so
// that a round spreads over all of them), and the search learns from the scores and goes on.
// While the outline runs, its best shows on the first card. At the end each card's patch is
// rendered as it is, for what the card shows.
// Variations are rendered once.
//
// `evaluate` scores genes by weights, with the candidate if it scores under the threshold:
// the workers' (MatchPool.evaluate), or the engine itself in tools/test/match.mjs.
// `evaluateValues` renders and scores a patch given as values played at a note (a refinement's,
// MatchRefine.res): MatchPool.evaluateValues, or MatchSearch.evaluateValues.

// genes, weights, threshold, what to fit (the envelope, the key EQ), and whether to render only
// the start
type evaluate = (Float64Array.t, MatchLoss.weights, float, MatchSearch.fitting, bool) => promise<MatchSearch.result>
type evaluateValues = (array<(string, float)>, int) => promise<MatchSearch.valued>

type handlers = {
  onCandidate: MatchSearch.candidate => unit,
  onProgress: (~island: int, ~evals: int, ~budget: int) => unit,
  onDone: unit => unit,
}

type t = {mutable cancelled: bool}

let cancel = t => t.cancelled = true

let search = (evaluate: evaluate, m: MatchSearch.match_, handlers) => {
  let t = {cancelled: false}
  let islands = Array.length(MatchSearch.islands)
  let report = (s: MatchSearch.search) => s.best->Option.forEach(handlers.onCandidate)
  // each card's share of the outline, then its own search
  let progress = (~outline, ~own, ~island) =>
    handlers.onProgress(
      ~island,
      ~evals=outline / islands + own,
      ~budget=m.outline.budget / islands + m.islandBudget,
    )
  let step = async (s: MatchSearch.search) => {
    let pending = MatchSearch.ask(s)
    let threshold = MatchSearch.threshold(s)
    let results = await Promise.all(pending.genes->Array.map(x => evaluate(x, s.weights, threshold, s.fit, pending.short)))
    !t.cancelled && MatchSearch.tell(s, pending, results)
  }
  let run = async (s: MatchSearch.search) =>
    while !t.cancelled && !MatchSearch.isDone(s) {
      if await step(s) {
        report(s)
      }
      if !t.cancelled {
        progress(~outline=m.outline.evals, ~own=s.evals, ~island=s.islandIndex)
      }
    }
  (async () => {
    while !t.cancelled && !MatchSearch.isDone(m.outline) {
      if await step(m.outline) {
        report(m.outline)
      }
      for island in 0 to islands - 1 {
        progress(~outline=m.outline.evals, ~own=0, ~island)
      }
    }
    if !t.cancelled {
      let searches = MatchSearch.branchAll(m)
      let _ = await Promise.all(searches->Array.map(run))
      if !t.cancelled {
        // each against its rivals' final answers, those with fewer rivals first
        searches
        ->Array.toSorted((a, b) => Int.compare(Array.length(a.rivals), Array.length(b.rivals)))
        ->Array.forEach(s => MatchSearch.reselect(s)->ignore)
        // and each card's patch rendered as it is (its envelope may have been put on a flat
        // render's measurements), so that what a card shows is what it sounds like
        let confirmed = await Promise.all(
          searches->Array.map(s =>
            switch s.bestGenes {
            | Some(x) => evaluate(x, MatchLoss.standard, infinity, MatchSearch.noFitting, false)->Promise.thenResolve(r => (s, r.candidate))
            | None => Promise.resolve((s, None))
            }
          ),
        )
        if !t.cancelled {
          confirmed->Array.forEach(((s, candidate)) => {
            candidate->Option.forEach(c => s.best = Some({...c, island: s.islandIndex, slot: s.islandIndex}))
            report(s)
          })
          handlers.onDone()
        }
      }
    }
  })()->ignore
  t
}

// Renders each mutant once; a variation's card is its place among them.
let vary = (evaluate: evaluate, mutants: array<Float64Array.t>, handlers) => {
  let t = {cancelled: false}
  mutants
  ->Array.mapWithIndex((x, slot) =>
    evaluate(x, MatchLoss.standard, infinity, MatchSearch.noFitting, false)->Promise.thenResolve(r =>
      if !t.cancelled {
        r.candidate->Option.forEach(c => handlers.onCandidate({...c, slot}))
        handlers.onProgress(~island=slot, ~evals=1, ~budget=1)
      }
    )
  )
  ->Promise.all
  ->Promise.thenResolve(_ =>
    if !t.cancelled {
      handlers.onDone()
    }
  )
  ->ignore
  t
}

// Refines a card (MatchRefine.res): the card as it is, then with each addition kept, on cards
// 0 to 3 as they come; each round's renders all at once.
let refine = (evaluateValues: evaluateValues, card: MatchSearch.candidate, ~base, ~budget, ~seed, handlers) => {
  let t = {cancelled: false}
  let r = MatchRefine.make(~values=card.values, ~note=card.note, ~base, ~budget, ~seed)
  let report = () =>
    r.steps->Array.forEachWithIndex((step, slot) =>
      handlers.onCandidate({
        ...card,
        island: -1,
        slot,
        values: Array.concat(step.values, [("Gain", step.valued.gain)]),
        similarity: step.valued.similarity,
        description: Array.concat(
          [card.description],
          step.additions->Array.map(a => "+ " ++ a.label),
        )->Array.join(" · "),
        envelope: step.valued.envelope,
        spectrum: step.valued.spectrum,
      })
    )
  (async () => {
    while !t.cancelled && !MatchRefine.isDone(r) {
      let pending = MatchRefine.ask(r)
      let valued = await Promise.all(pending.values->Array.map(v => evaluateValues(v, card.note)))
      if !t.cancelled {
        let before = Array.length(r.steps)
        MatchRefine.tell(r, pending, valued)
        if Array.length(r.steps) != before {
          report()
        }
        // (the rows' bars: each card's share of the budget)
        let shown = Math.Int.max(1, Array.length(r.steps))
        for slot in 0 to MatchRefine.maxAdditions {
          handlers.onProgress(
            ~island=slot,
            ~evals=slot < shown ? r.budget : r.evals,
            ~budget=r.budget,
          )
        }
      }
    }
    if !t.cancelled {
      for slot in 0 to MatchRefine.maxAdditions {
        handlers.onProgress(~island=slot, ~evals=1, ~budget=1)
      }
      handlers.onDone()
    }
  })()->ignore
  t
}
