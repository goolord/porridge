// Runs the sound matcher's searches (MatchSearch.res) in the view: each asks for a generation,
// every candidate of it goes to the workers to be rendered and scored on its own (so that a
// generation spreads over all of them), and the search learns from the scores and goes on.
// The searches run side by side, each keeping away from its rivals' best so far.
// Variations are rendered once.
//
// `evaluate` scores genes by weights, with the candidate if it scores under the threshold:
// the workers' (MatchPool.evaluate), or the engine itself in tools/test/match.mjs.

type evaluate = (Float64Array.t, MatchLoss.weights, float) => promise<(float, option<MatchSearch.candidate>)>

type handlers = {
  onCandidate: MatchSearch.candidate => unit,
  onProgress: (~island: int, ~evals: int, ~budget: int) => unit,
  onDone: unit => unit,
}

type t = {mutable cancelled: bool}

let cancel = t => t.cancelled = true

let search = (evaluate: evaluate, searches: array<MatchSearch.search>, handlers) => {
  let t = {cancelled: false}
  searches->Array.forEach(s =>
    s.rivals = searches->Array.filter(r => s.island.rivals->Array.includes(r.islandIndex))
  )
  let report = (s: MatchSearch.search) => s.best->Option.forEach(handlers.onCandidate)
  let run = async (s: MatchSearch.search) => {
    while !t.cancelled && !MatchSearch.isDone(s) {
      let pending = MatchSearch.ask(s)
      let threshold = MatchSearch.threshold(s)
      let results = await Promise.all(pending.genes->Array.map(x => evaluate(x, s.island.weights, threshold)))
      if !t.cancelled {
        if MatchSearch.tell(s, pending, results) {
          report(s)
        }
        handlers.onProgress(~island=s.islandIndex, ~evals=s.evals, ~budget=s.budget)
      }
    }
  }
  Promise.all(searches->Array.map(run))
  ->Promise.thenResolve(_ =>
    if !t.cancelled {
      // each against its rivals' final answers, those with fewer rivals first
      searches
      ->Array.toSorted((a, b) => Int.compare(Array.length(a.rivals), Array.length(b.rivals)))
      ->Array.forEach(s =>
        if MatchSearch.reselect(s) {
          report(s)
        }
      )
      handlers.onDone()
    }
  )
  ->ignore
  t
}

// Renders each mutant once; a variation's card is its place among them.
let vary = (evaluate: evaluate, mutants: array<Float64Array.t>, handlers) => {
  let t = {cancelled: false}
  mutants
  ->Array.mapWithIndex((x, slot) =>
    evaluate(x, MatchLoss.standard, infinity)->Promise.thenResolve(((_, candidate)) =>
      if !t.cancelled {
        candidate->Option.forEach(c => handlers.onCandidate({...c, slot}))
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
