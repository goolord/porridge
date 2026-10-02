// The sound matcher's predictor: a small network (two hidden layers) that has learned, from
// random patches rendered by the synth (tools/match-train.mjs), which genes make a sound like
// the target. Its guess, and a few of its next-best structures, are where the search starts
// (MatchSearch.makeMatch's starts), so the search refines a patch near the answer instead of
// finding its outline from scratch.
//
// Its input (`features`) is the target's measurements: the long spectra (48 mel bands) over 11
// stretches of time, the short ones (32 bands) over 7 in the first 150 ms, the loudness at 25
// points, all in dB under the loudest, and the key, whether it has a pitch, its brightness,
// length and pitch sweep (and how long it takes), how far its brightness falls (and how fast),
// how much lies between its harmonics (overall, and in each of the harmonic grid's bands) and
// how wide it is. Its output is a value for each continuous gene (through a sigmoid) and the
// options' scores for each choice gene, but the key EQ's, which are fitted to each candidate;
// the render genes (octave, tune) say how far the pitch found is from the sound's.
//
// The file (ui/match/match-model.bin, bundle/match-model.bin in the plugin): "PMM1", the
// header's length (u32), the header (JSON: inputs, layer sizes and the genes it was trained
// for), then float32s from a 4-byte boundary: the inputs' means and spreads, then each layer's
// weights (outputs × inputs) and biases.

@get_index external get32: (Float32Array.t, int) => float = ""
@set_index external set32: (Float32Array.t, int, float) => unit = ""
@get_index external get64: (Float64Array.t, int) => float = ""
@set_index external set64: (Float64Array.t, int, float) => unit = ""

//==============================================================================
// Features

let longStretches = [0., 30., 60., 100., 150., 220., 310., 430., 600., 820., 1100., 1600.]
let shortStretches = [0., 10., 20., 35., 50., 75., 100., 150.]
let loudnessSteps = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 22, 26, 31, 37, 44, 52, 61, 72, 85, 100, 118, 139, 159]
let scalars = 10 + Spectrum.gridBands

let longBands = (Spectrum.resolutions->Array.getUnsafe(0)).bands
let shortBands = (Spectrum.resolutions->Array.getUnsafe(2)).bands
let featureCount =
  (Array.length(longStretches) - 1) * longBands +
  (Array.length(shortStretches) - 1) * shortBands +
  Array.length(loudnessSteps) +
  scalars

// dB under the loudest, in 20 dB units, from -4 (80 dB under, or silence) to 0.5
let scaled = (db: float, ~top: float) => Math.max(-4., Math.min(0.5, (db - top) / 20.))

let features = (t: SoundTarget.t) => {
  let f = Spectrum.measure(t.samples, ~period=None)
  let out = Float32Array.fromLength(featureCount)
  let at = ref(0)
  let push = v => {
    out->set32(at.contents, v)
    at := at.contents + 1
  }
  // the loudest band of the long spectra, which everything is measured under
  let top = ref(neg_infinity)
  f.spectra->Array.getUnsafe(0)->TypedArray.forEach(v => top := Math.max(top.contents, Spectrum.db(v)))
  let top = top.contents
  // a resolution's bands, averaged by power over the frames centred in each stretch
  let stretches = (ri, edges: array<float>) => {
    let r = Spectrum.resolutions->Array.getUnsafe(ri)
    let levels = f.spectra->Array.getUnsafe(ri)
    let frames = TypedArray.length(levels) / r.bands
    for s in 0 to Array.length(edges) - 2 {
      let (a, b) = (edges->Array.getUnsafe(s), edges->Array.getUnsafe(s + 1))
      let power = Float64Array.fromLength(r.bands)
      let count = ref(0)
      for frame in 0 to frames - 1 {
        let ms = 1000. * Int.toFloat(frame * r.hop) / Spectrum.sampleRate
        if ms >= a && ms < b {
          count := count.contents + 1
          for band in 0 to r.bands - 1 {
            let v = levels->get64(frame * r.bands + band)
            power->set64(band, power->get64(band) + v * v)
          }
        }
      }
      for band in 0 to r.bands - 1 {
        push(
          count.contents == 0
            ? -4.
            : scaled(Spectrum.db(Math.sqrt(power->get64(band) / Int.toFloat(count.contents))), ~top),
        )
      }
    }
  }
  stretches(0, longStretches)
  stretches(2, shortStretches)
  let env = f.envelope
  let loudest = ref(neg_infinity)
  env->TypedArray.forEach(v => loudest := Math.max(loudest.contents, Spectrum.db(v)))
  loudnessSteps->Array.forEach(s =>
    push(s < TypedArray.length(env) ? scaled(Spectrum.db(env->get64(s)), ~top=loudest.contents) : -4.)
  )
  push((Int.toFloat(t.note) - 60.) / 24.)
  push(t.hz == None ? 0. : 1.)
  push(Math.log2(Math.max(50., t.brightness) / 1000.))
  push(SoundTarget.seconds(t) / 1.5)
  push(t.pitchDrop / 12.)
  push(t.pitchTime * 5.)
  push(t.brightnessDrop / 3.)
  push(t.brightnessTime * 5.)
  push(t.noise / 20.)
  push(t.width / 20.)
  let between =
    t.hz->Option.flatMap(hz => Spectrum.measureGrid(t.samples, ~hz))->Option.mapOr([], Spectrum.gridMeanRatio)
  for b in 0 to Spectrum.gridBands - 1 {
    push(between[b]->Option.mapOr(-3., r => Math.max(-3., 10. * Math.log10(Math.max(r, 1e-6)) / 20.)))
  }
  out
}

//==============================================================================
// Outputs: the genes it predicts, and where each one's values are

let predicted = Genome.genes->Array.filter(g => g.group != #eq)

// (gene index, first output, outputs)
let layout = {
  let at = ref(0)
  predicted->Array.map(g => {
    let width = g.options == 0 ? 1 : g.options
    let slot = (Genome.indexOf(g.key), at.contents, width)
    at := at.contents + width
    slot
  })
}

let outputCount = layout->Array.reduce(0, (n, (_, _, width)) => n + width)

//==============================================================================
// The network

type layer = {inputs: int, outputs: int, weights: Float32Array.t, biases: Float32Array.t}

type t = {
  mean: Float32Array.t,
  spread: Float32Array.t,
  layers: array<layer>,
}

type header = {inputs: int, layers: array<int>, genes: array<(string, int)>}

let readHeader: Uint8Array.t => option<(header, int)> = %raw(`bytes => {
  if (bytes.length < 8 || String.fromCharCode(...bytes.subarray(0, 4)) !== "PMM1") return undefined;
  const length = new DataView(bytes.buffer, bytes.byteOffset).getUint32(4, true);
  const header = JSON.parse(new TextDecoder().decode(bytes.subarray(8, 8 + length)));
  return [header, (8 + length + 3) & ~3];
}`)

let floatsAt: (Uint8Array.t, int, int) => Float32Array.t = %raw(`(bytes, offset, count) =>
  new Float32Array(bytes.slice(offset, offset + 4 * count).buffer)`)

// The model in a file, if it is one made for these features and genes.
let parse = (bytes: Uint8Array.t): option<t> =>
  switch readHeader(bytes) {
  | Some((header, start)) =>
    let sameGenes = header.genes == predicted->Array.map(g => (g.key, g.options))
    let sizes = [header.inputs, ...header.layers]
    if !sameGenes || header.inputs != featureCount || sizes->Array.at(-1) != Some(outputCount) {
      None
    } else {
      let at = ref(start)
      let take = count => {
        let floats = floatsAt(bytes, at.contents, count)
        at := at.contents + 4 * count
        floats
      }
      let mean = take(featureCount)
      let spread = take(featureCount)
      let layers = header.layers->Array.mapWithIndex((outputs, i) => {
        let inputs = sizes->Array.getUnsafe(i)
        let weights = take(inputs * outputs)
        let biases = take(outputs)
        {inputs, outputs, weights, biases}
      })
      at.contents <= TypedArray.length(bytes) ? Some({mean, spread, layers}) : None
    }
  | None => None
  }

// The raw outputs for a target's features (ReLU between the layers).
let run = (model: t, input: Float32Array.t) => {
  let x = ref(input->TypedArray.mapWithIndex((v, i) => (v - model.mean->get32(i)) / model.spread->get32(i)))
  let last = Array.length(model.layers) - 1
  model.layers->Array.forEachWithIndex((l, li) => {
    let y = Float32Array.fromLength(l.outputs)
    for o in 0 to l.outputs - 1 {
      let sum = ref(l.biases->get32(o))
      let row = o * l.inputs
      for i in 0 to l.inputs - 1 {
        sum := sum.contents + l.weights->get32(row + i) * x.contents->get32(i)
      }
      y->set32(o, li < last ? Math.max(0., sum.contents) : sum.contents)
    }
    x := y
  })
  x.contents
}

let sigmoid = v => 1. / (1. + Math.exp(-.v))

// each choice gene's options' probabilities (a softmax of its outputs)
let probabilities = (out: Float32Array.t, first, width) => {
  let top = ref(neg_infinity)
  for k in 0 to width - 1 {
    top := Math.max(top.contents, out->get32(first + k))
  }
  let e = Array.fromInitializer(~length=width, k => Math.exp(out->get32(first + k) - top.contents))
  let sum = e->Array.reduce(0., (s, v) => s + v)
  e->Array.map(v => v / sum)
}

// Where the search should start for a target: the predicted genes (the rest, the key EQ's, as
// the seed has them); the same with the amp envelope fitted to the sample (Genome.seed's); and
// the predicted genes with each of the next most likely combinations of first wave, filter type
// and mix mode.
let suggest = (model: t, target: SoundTarget.t) => {
  let out = run(model, features(target))
  let seed = Genome.seed(target)
  let x = TypedArray.copy(seed)
  let probs = Map.make()
  layout->Array.forEach(((i, first, width)) => {
    let g = Genome.gene(i)
    if g.options == 0 {
      x->set64(i, sigmoid(out->get32(first)))
    } else {
      let p = probabilities(out, first, width)
      // no fitted wave without a pitch
      let p = g.key == "o1Wave" && target.wave == None ? p->Array.mapWithIndex((v, k) => k == Genome.fittedWave ? 0. : v) : p
      probs->Map.set(g.key, p)
      let best = p->Array.reduceWithIndex(0, (b, v, k) => v > p->Array.getUnsafe(b) ? k : b)
      x->set64(i, Genome.valueOfChoice(best, g.options))
    }
  })
  let seeded = TypedArray.copy(x)
  Genome.envelopeKeys->Array.forEach(key => seeded->set64(Genome.indexOf(key), seed->get64(Genome.indexOf(key))))

  // the likeliest combinations after the best
  let keys = ["o1Wave", "filterType", "oscMix"]
  let combos = keys->Array.reduce([([], 1.)], (combos, key) => {
    let p = probs->Map.get(key)->Option.getOr([])
    combos
    ->Array.flatMap(((picks, q)) => p->Array.mapWithIndex((v, k) => (Array.concat(picks, [k]), q * v)))
    ->Array.toSorted(((_, a), (_, b)) => Float.compare(b, a))
    ->Array.slice(~start=0, ~end=8)
  })
  let others =
    combos
    ->Array.slice(~start=1, ~end=6)
    ->Array.map(((picks, _)) => {
      let y = TypedArray.copy(x)
      keys->Array.forEachWithIndex((key, j) => {
        let i = Genome.indexOf(key)
        y->set64(i, Genome.valueOfChoice(picks->Array.getUnsafe(j), Genome.gene(i).options))
      })
      y
    })
  [x, seeded, ...others]
}
