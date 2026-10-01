// The messages between the view (MatchPool.res) and the sound matcher's workers
// (MatchWorker.res). They go through postMessage, so they hold only plain data.

// What a match renders against: the target, and the patch the genes go on.
type setup = {
  target: SoundTarget.t,
  base: Bank.values,
  tables: OatmealFormat.tables,
}

@tag("type")
type request =
  | @as("init") Init({wasm: MatchEngine.wasmModule})
  // makes a sample ready to match (SoundTarget.prepare)
  | @as("prepare") Prepare({task: int, name: string, samples: Float32Array.t, sampleRate: float})
  // what the evaluations of a session render against, sent before its first one
  | @as("setup") Setup({session: int, setup: setup})
  // renders and scores genes (MatchSearch.evaluate)
  | @as("evaluate")
  Evaluate({task: int, genes: array<float>, weights: MatchLoss.weights, threshold: float})

@tag("type")
type response =
  | @as("ready") Ready
  | @as("failed") Failed({task: int, message: string})
  | @as("target")
  Target({task: int, target: SoundTarget.t, envelope: array<float>, spectrum: array<float>})
  | @as("evaluated") Evaluated({task: int, loss: float, candidate: option<MatchSearch.candidate>})
