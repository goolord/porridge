// Trains the sound matcher's predictor (ui/match/MatchModel.res): a small network from a
// sample's features to the genes that make it.
//
//   node tools/match-train.mjs generate [--count n] [--jobs n] [--seed n]
//       renders random patches (Genome.random) at random keys, some cut short, through the
//       matcher's own engine, prepares each as a sample (SoundTarget.prepare: its onset, pitch
//       and fitted wave as a dropped sample gets them) and writes its features and genes to
//       build/match-train/<seed>.bin. The octave and tune genes are what would play it back at
//       its own pitch from the pitch found (left out when that's no octave and tuning away).
//   node tools/match-train.mjs train [--epochs n] [--hidden n] [--jobs n]
//       trains on everything in build/match-train/ (a twentieth held back to check it on) and
//       writes ui/match/match-model.bin, which tools/bundle.mjs puts in the bundle.
//
// The network: two hidden layers (ReLU), trained with Adam on mini-batches spread over worker
// threads. Each continuous gene is learned by squared error through a sigmoid, each choice by
// cross-entropy over its options, and only where the gene makes a difference to the patch
// (Genome.relevant): osc 2's wave means nothing while osc 2 is off.
//
// (needs `npx rescript` and bundle/match-engine.* from tools/match-engine.mjs)

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import { availableParallelism } from "node:os";
import * as Preset from "../ui/Preset.res.mjs";
import * as SoundTarget from "../ui/match/SoundTarget.res.mjs";
import * as Genome from "../ui/match/Genome.res.mjs";
import * as MatchEngine from "../ui/match/MatchEngine.res.mjs";
import * as MatchModel from "../ui/match/MatchModel.res.mjs";
import * as Cmaes from "../ui/match/Cmaes.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");
const dataDir = join (root, "build", "match-train");
const modelPath = join (root, "ui", "match", "match-model.bin");
const F = MatchModel.featureCount;
const G = Genome.count;
const O = MatchModel.outputCount;
const layout = MatchModel.layout;   // [gene index, first output, width]

//==============================================================================
// Generating

async function generator ({ seed, count })
{
    const glue = readFileSync (join (root, "bundle", "match-engine.js"), "utf8");
    const EngineClass = new Function (glue + "\nreturn PorridgeMatchEngine;") ();
    const wasm = await WebAssembly.compile (readFileSync (join (root, "bundle", "match-engine.wasm")));
    const engine = await MatchEngine.make (EngineClass, wasm);
    const init = Preset.make ("Init");
    const initValue = id => init.values.get (id) ?? 0;
    MatchEngine.setBase (engine, init.values, init.tables);
    const random = Cmaes.makeRandom (seed);
    const out = Buffer.alloc (count * 4 * (F + G));
    let written = 0, tries = 0;
    const octave = Genome.indexOf ("octave"), tune = Genome.indexOf ("tune");

    while (written < count && tries < 3 * count)
    {
        ++tries;
        const genes = Genome.random (random);
        const note = 36 + Math.floor (random () * 49);
        const seconds = random () < 0.3 ? 0.25 + 1.3 * random () : 1.6;
        const frames = Math.round (seconds * 44100);
        const [l, r] = MatchEngine.renderStereo (engine, Genome.decode (genes, note, initValue), note, 0, frames, frames);
        const prepared = SoundTarget.prepare ("x", { samples: l.map ((v, i) => 0.5 * (v + r[i])), sampleRate: 44100, frameSize: undefined });
        if (prepared.TAG !== "Ok") continue;
        const target = prepared._0;

        // the render genes that play it back at its own pitch from the pitch found
        const semis = note - target.note;
        const cents = -target.cents;
        const label = Float32Array.from (genes);
        if ((semis === 0 || Math.abs (semis) === 12) && Math.abs (cents) <= 50)
        {
            label[octave] = Genome.valueOfChoice ([0, -12, 12].indexOf (semis), 3);
            label[tune] = 0.5 + cents / 100;
        }
        else
        {
            label[octave] = NaN;
            label[tune] = NaN;
        }
        const features = MatchModel.features (target);
        const at = written * 4 * (F + G);
        Buffer.from (features.buffer).copy (out, at);
        Buffer.from (label.buffer).copy (out, at + 4 * F);
        ++written;
    }
    return out.subarray (0, written * 4 * (F + G));
}

//==============================================================================
// The network's arithmetic, shared by the trainer's threads

// params: one Float32Array: W1 (H×F) b1 (H) W2 (H×H) b2 (H) W3 (O×H) b3 (O)
const offsets = H =>
{
    const W1 = 0, b1 = W1 + H * F, W2 = b1 + H, b2 = W2 + H * H, W3 = b2 + H, b3 = W3 + O * H;
    return { W1, b1, W2, b2, W3, b3, size: b3 + O };
};

// which genes count for a sample's labels: Genome.relevant, and the render genes when known
const maskOf = label =>
{
    const genes = Float64Array.from (label, v => Number.isNaN (v) ? 0.5 : v);
    const relevant = Genome.relevant (genes);
    return relevant.map ((r, i) => r && ! Number.isNaN (label[i]));
};

// Adds a batch's gradients into grad and returns its summed loss. x: normalised features.
function backprop (params, grad, H, rows, X, Y, M)
{
    const o = offsets (H);
    const h1 = new Float32Array (H), h2 = new Float32Array (H), z = new Float32Array (O);
    const dz = new Float32Array (O), dh2 = new Float32Array (H), dh1 = new Float32Array (H);
    let total = 0;
    for (const n of rows)
    {
        const x = X.subarray (n * F, n * F + F), y = Y.subarray (n * G, n * G + G), mask = M.subarray (n * G, n * G + G);
        for (let j = 0; j < H; j++)
        {
            let s = params[o.b1 + j];
            const row = o.W1 + j * F;
            for (let i = 0; i < F; i++) s += params[row + i] * x[i];
            h1[j] = s > 0 ? s : 0;
        }
        for (let j = 0; j < H; j++)
        {
            let s = params[o.b2 + j];
            const row = o.W2 + j * H;
            for (let i = 0; i < H; i++) s += params[row + i] * h1[i];
            h2[j] = s > 0 ? s : 0;
        }
        for (let k = 0; k < O; k++)
        {
            let s = params[o.b3 + k];
            const row = o.W3 + k * H;
            for (let i = 0; i < H; i++) s += params[row + i] * h2[i];
            z[k] = s;
        }
        dz.fill (0);
        for (const [g, first, width] of layout)
        {
            if (! mask[g]) continue;
            if (width === 1)
            {
                const p = 1 / (1 + Math.exp (-z[first]));
                const d = p - y[g];
                total += d * d;
                dz[first] = 2 * d * p * (1 - p) * 4;
            }
            else
            {
                const target = Math.min (width - 1, Math.max (0, Math.floor (y[g] * width)));
                let top = -Infinity;
                for (let k = 0; k < width; k++) top = Math.max (top, z[first + k]);
                let sum = 0;
                for (let k = 0; k < width; k++) sum += Math.exp (z[first + k] - top);
                for (let k = 0; k < width; k++)
                {
                    const p = Math.exp (z[first + k] - top) / sum;
                    dz[first + k] = 0.25 * (p - (k === target ? 1 : 0));
                }
                total += 0.25 * -(z[first + target] - top - Math.log (sum));
            }
        }
        dh2.fill (0);
        for (let k = 0; k < O; k++)
        {
            const d = dz[k];
            if (d === 0) continue;
            grad[o.b3 + k] += d;
            const row = o.W3 + k * H;
            for (let i = 0; i < H; i++) { grad[row + i] += d * h2[i]; dh2[i] += d * params[row + i]; }
        }
        dh1.fill (0);
        for (let j = 0; j < H; j++)
        {
            if (h2[j] <= 0) continue;
            const d = dh2[j];
            grad[o.b2 + j] += d;
            const row = o.W2 + j * H;
            for (let i = 0; i < H; i++) { grad[row + i] += d * h1[i]; dh1[i] += d * params[row + i]; }
        }
        for (let j = 0; j < H; j++)
        {
            if (h1[j] <= 0) continue;
            const d = dh1[j];
            grad[o.b1 + j] += d;
            const row = o.W1 + j * F;
            for (let i = 0; i < F; i++) grad[row + i] += d * x[i];
        }
    }
    return total;
}

//==============================================================================
// Training

function readData ()
{
    const files = existsSync (dataDir) ? readdirSync (dataDir).filter (f => f.endsWith (".bin")) : [];
    const buffers = files.map (f => readFileSync (join (dataDir, f)));
    const rows = buffers.reduce ((n, b) => n + b.length / (4 * (F + G)), 0);
    const X = new Float32Array (new SharedArrayBuffer (4 * rows * F));
    const Y = new Float32Array (new SharedArrayBuffer (4 * rows * G));
    let n = 0;
    for (const b of buffers)
    {
        const all = new Float32Array (b.buffer, b.byteOffset, b.length / 4);
        for (let r = 0; r < b.length / (4 * (F + G)); r++, n++)
        {
            X.set (all.subarray (r * (F + G), r * (F + G) + F), n * F);
            Y.set (all.subarray (r * (F + G) + F, (r + 1) * (F + G)), n * G);
        }
    }
    return { X, Y, rows };
}

async function train ({ epochs, hidden: H, jobs, batch, rate })
{
    const { X, Y, rows } = readData ();
    if (rows < 1000) throw new Error (`only ${rows} examples in ${dataDir}: run generate first`);
    console.log (`${rows} examples, ${F} features, ${O} outputs, hidden ${H}×2`);

    // normalising the features
    const mean = new Float32Array (F), spread = new Float32Array (F);
    for (let n = 0; n < rows; n++) for (let i = 0; i < F; i++) mean[i] += X[n * F + i] / rows;
    for (let n = 0; n < rows; n++) for (let i = 0; i < F; i++) { const d = X[n * F + i] - mean[i]; spread[i] += d * d / rows; }
    for (let i = 0; i < F; i++) spread[i] = Math.max (0.05, Math.sqrt (spread[i]));
    for (let n = 0; n < rows; n++) for (let i = 0; i < F; i++) X[n * F + i] = (X[n * F + i] - mean[i]) / spread[i];
    const M = new Uint8Array (new SharedArrayBuffer (rows * G));
    for (let n = 0; n < rows; n++) maskOf (Y.subarray (n * G, n * G + G)).forEach ((m, g) => M[n * G + g] = m ? 1 : 0);
    for (let n = 0; n < rows; n++) for (let g = 0; g < G; g++) if (Number.isNaN (Y[n * G + g])) Y[n * G + g] = 0.5;

    // He initialisation
    const o = offsets (H);
    const params = new Float32Array (new SharedArrayBuffer (4 * o.size));
    const random = Cmaes.makeRandom (99);
    const gauss = () => Math.sqrt (-2 * Math.log (Math.max (random (), 1e-12))) * Math.cos (2 * Math.PI * random ());
    for (let i = 0; i < H * F; i++) params[o.W1 + i] = gauss () * Math.sqrt (2 / F);
    for (let i = 0; i < H * H; i++) params[o.W2 + i] = gauss () * Math.sqrt (2 / H);
    for (let i = 0; i < O * H; i++) params[o.W3 + i] = gauss () * Math.sqrt (1 / H);

    // a twentieth held back
    const order = Array.from ({ length: rows }, (_, i) => i);
    for (let i = rows - 1; i > 0; i--) { const j = Math.floor (random () * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
    const held = order.slice (0, Math.floor (rows / 20)), used = order.slice (held.length);

    const workers = Array.from ({ length: jobs }, () => new Worker (new URL (import.meta.url), { workerData: { role: "trainer", H, X, Y, M, params } }));
    const grads = workers.map (() => new Float32Array (new SharedArrayBuffer (4 * o.size)));
    const call = (w, message) => new Promise (resolve => { w.once ("message", resolve); w.postMessage (message); });
    // a batch's gradient (summed) and loss, spread over the threads
    const run = async (rowsOf, withGrad) =>
    {
        const per = Math.ceil (rowsOf.length / jobs);
        const losses = await Promise.all (workers.map ((w, k) =>
        {
            if (withGrad) grads[k].fill (0);
            return call (w, { rows: rowsOf.slice (k * per, (k + 1) * per), grad: withGrad ? grads[k] : null });
        }));
        return losses.reduce ((a, b) => a + b, 0);
    };

    const m1 = new Float32Array (o.size), m2 = new Float32Array (o.size);
    const steps = epochs * Math.floor (used.length / batch);
    let step = 0;
    for (let epoch = 1; epoch <= epochs; epoch++)
    {
        for (let i = used.length - 1; i > 0; i--) { const j = Math.floor (random () * (i + 1)); [used[i], used[j]] = [used[j], used[i]]; }
        let sum = 0;
        for (let b = 0; b + batch <= used.length; b += batch)
        {
            sum += await run (used.slice (b, b + batch), true);
            // Adam, the rate falling along a cosine to a hundredth
            ++step;
            const lr = rate * (0.01 + 0.99 * 0.5 * (1 + Math.cos (Math.PI * step / steps)));
            const c1 = 1 - Math.pow (0.9, step), c2 = 1 - Math.pow (0.999, step);
            for (let i = 0; i < o.size; i++)
            {
                let g = 0;
                for (const gr of grads) g += gr[i];
                g /= batch;
                m1[i] = 0.9 * m1[i] + 0.1 * g;
                m2[i] = 0.999 * m2[i] + 0.001 * g * g;
                params[i] -= lr * ((m1[i] / c1) / (Math.sqrt (m2[i] / c2) + 1e-8) + 1e-5 * params[i]);
            }
        }
        const check = await run (held, false);
        console.log (`epoch ${epoch}: training ${(sum / used.length).toFixed (4)}, held back ${(check / held.length).toFixed (4)}`);
    }
    workers.forEach (w => w.terminate ());

    // how often each choice comes out right on the held-back examples
    const model = { mean, spread, params, H };
    report (model, held, X, Y, M);
    write (model);
}

function forward ({ params, H }, x)
{
    const o = offsets (H);
    const h1 = new Float32Array (H), h2 = new Float32Array (H), z = new Float32Array (O);
    for (let j = 0; j < H; j++) { let s = params[o.b1 + j]; for (let i = 0; i < F; i++) s += params[o.W1 + j * F + i] * x[i]; h1[j] = Math.max (0, s); }
    for (let j = 0; j < H; j++) { let s = params[o.b2 + j]; for (let i = 0; i < H; i++) s += params[o.W2 + j * H + i] * h1[i]; h2[j] = Math.max (0, s); }
    for (let k = 0; k < O; k++) { let s = params[o.b3 + k]; for (let i = 0; i < H; i++) s += params[o.W3 + k * H + i] * h2[i]; z[k] = s; }
    return z;
}

function report (model, held, X, Y, M)
{
    const lines = [];
    for (const [g, first, width] of layout)
    {
        const key = Genome.genes[g].key;
        let right = 0, count = 0, err = 0;
        for (const n of held)
        {
            if (! M[n * G + g]) continue;
            const z = forward (model, X.subarray (n * F, n * F + F));
            ++count;
            if (width === 1) err += Math.abs (1 / (1 + Math.exp (-z[first])) - Y[n * G + g]);
            else
            {
                let best = 0;
                for (let k = 1; k < width; k++) if (z[first + k] > z[first + best]) best = k;
                if (best === Math.min (width - 1, Math.floor (Y[n * G + g] * width))) ++right;
            }
        }
        lines.push (width === 1 ? `${key} ±${(err / Math.max (1, count)).toFixed (3)}` : `${key} ${(100 * right / Math.max (1, count)).toFixed (0)}%`);
    }
    console.log ("held back: " + lines.join (", "));
}

function write ({ mean, spread, params, H })
{
    const o = offsets (H);
    const header = Buffer.from (JSON.stringify ({ inputs: F, layers: [H, H, O], genes: MatchModel.predicted.map (g => [g.key, g.options]) }));
    const start = (8 + header.length + 3) & ~3;
    // the file's order: means, spreads, then each layer's weights and biases
    const floats = [mean, spread, params.subarray (o.W1, o.b1), params.subarray (o.b1, o.W2), params.subarray (o.W2, o.b2),
                    params.subarray (o.b2, o.W3), params.subarray (o.W3, o.b3), params.subarray (o.b3, o.size)];
    const total = floats.reduce ((n, f) => n + f.length, 0);
    const out = Buffer.alloc (start + 4 * total);
    out.write ("PMM1", 0);
    out.writeUInt32LE (header.length, 4);
    header.copy (out, 8);
    let at = start;
    for (const f of floats) { Buffer.from (Float32Array.from (f).buffer).copy (out, at); at += 4 * f.length; }
    writeFileSync (modelPath, out);
    console.log (`wrote ${modelPath} (${(out.length / 1024).toFixed (0)} kB)`);
    if (! MatchModel.parse (new Uint8Array (out))) throw new Error ("the model written doesn't read back");
}

//==============================================================================

if (! isMainThread)
{
    if (workerData.role === "generator")
        parentPort.postMessage (await (await Promise.resolve (generator (workerData))));
    else
    {
        const { H, X, Y, M, params } = workerData;
        parentPort.on ("message", ({ rows, grad }) =>
            parentPort.postMessage (backprop (params, grad ?? new Float32Array (offsets (H).size), H, rows, X, Y, M)));
    }
}
else
{
    const args = process.argv.slice (2);
    const flag = (name, fallback) => { const i = args.indexOf (name); return i >= 0 ? Number (args[i + 1]) : fallback; };
    const jobs = flag ("--jobs", Math.max (1, availableParallelism () - 4));
    if (args[0] === "generate")
    {
        const count = flag ("--count", 20000), seed = flag ("--seed", 1);
        mkdirSync (dataDir, { recursive: true });
        const per = Math.ceil (count / jobs);
        const t0 = performance.now ();
        const parts = await Promise.all (Array.from ({ length: jobs }, (_, k) => new Promise ((resolve, reject) =>
        {
            const w = new Worker (new URL (import.meta.url), { workerData: { role: "generator", seed: seed * 1000 + k, count: per } });
            w.once ("message", resolve);
            w.once ("error", reject);
        })));
        const all = Buffer.concat (parts.map (p => Buffer.from (p)));
        const file = join (dataDir, `${seed}.bin`);
        writeFileSync (file, all);
        console.log (`${all.length / (4 * (F + G))} examples in ${((performance.now () - t0) / 1000).toFixed (0)} s -> ${file}`);
        process.exit (0);
    }
    else if (args[0] === "train")
    {
        await train ({ epochs: flag ("--epochs", 30), hidden: flag ("--hidden", 256), jobs, batch: flag ("--batch", 256), rate: flag ("--rate", 0.002) });
        process.exit (0);
    }
    else
        console.log ("node tools/match-train.mjs generate|train (see the top of the file)");
}
