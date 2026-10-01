// How fast the sound matcher is:
//  - candidates per second: workers rendering, measuring and scoring random patches against a
//    target (MatchSearch.evaluate, as a worker does) for a few seconds, 1, 6 and 12 at once;
//  - a whole match, as the drawer runs one (MatchRun.search in the main thread, every
//    candidate sent to the next free worker), with 6 and 12 workers: how long it takes and how
//    close it gets, for a few programs from the banks.
//
// run: node tools/test/match-speed.mjs [--seconds s] [--only rate|match]

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import * as Preset from "../../ui/Preset.res.mjs";
import * as SoundTarget from "../../ui/match/SoundTarget.res.mjs";
import * as Genome from "../../ui/match/Genome.res.mjs";
import * as MatchLoss from "../../ui/match/MatchLoss.res.mjs";
import * as MatchEngine from "../../ui/match/MatchEngine.res.mjs";
import * as MatchSearch from "../../ui/match/MatchSearch.res.mjs";
import * as MatchRun from "../../ui/match/MatchRun.res.mjs";
import * as MatchModel from "../../ui/match/MatchModel.res.mjs";
import * as Cmaes from "../../ui/match/Cmaes.res.mjs";
import { root, readBank } from "./lib.mjs";

const programIndices = [9, 25, 41, 58];
const budget = 1000;

// a bank program rendered as a sample, prepared
const targetOf = (engine, program) =>
{
    MatchEngine.setBase (engine, program.values, program.tables);
    const [l, r] = MatchEngine.renderStereo (engine, [], 57, 0, 66150, 66150);
    return SoundTarget.prepare ("x", { samples: l.map ((v, k) => 0.5 * (v + r[k])), sampleRate: 44100, frameSize: undefined })._0;
};

const makeEngine = async () =>
{
    const glue = readFileSync (join (root, "bundle", "match-engine.js"), "utf8");
    const EngineClass = new Function (glue + "\nreturn PorridgeMatchEngine;") ();
    const wasm = await WebAssembly.compile (readFileSync (join (root, "bundle", "match-engine.wasm")));
    return MatchEngine.make (EngineClass, wasm);
};

if (! isMainThread)
{
    const engine = await makeEngine ();
    const init = Preset.make ("Init");
    const programs = readBank ("presets/vanilla.porridge");
    if (workerData.role === "rate")
    {
        const ctx = MatchSearch.makeContext (engine, targetOf (engine, programs[25]), init.values, init.tables);
        const random = Cmaes.makeRandom (workerData.seed);
        parentPort.postMessage ("ready");
        parentPort.once ("message", () =>
        {
            const end = performance.now () + workerData.ms;
            let n = 0;
            while (performance.now () < end)
            {
                MatchSearch.evaluate (ctx, Genome.random (random), MatchLoss.standard, -1, workerData.fit, false);
                n++;
            }
            parentPort.postMessage (n);
        });
    }
    else
    {
        // a pool worker: set up for a program's target, then evaluate what it is sent (and say
        // how many it has, and how long they took)
        let ctx, count = 0, spent = 0;
        parentPort.postMessage ("ready");
        parentPort.on ("message", m =>
        {
            if (m.setup !== undefined)
            {
                ctx = MatchSearch.makeContext (engine, targetOf (engine, programs[m.setup]), init.values, init.tables);
                parentPort.postMessage ("set");
            }
            else if (m.stats)
                parentPort.postMessage ({ count, ms: spent });
            else
            {
                const t0 = performance.now ();
                const result = MatchSearch.evaluate (ctx, Float64Array.from (m.genes), m.weights, m.threshold, m.fit, m.short);
                spent += performance.now () - t0;
                count++;
                parentPort.postMessage (result);
            }
        });
    }
}
else
{
    const args = process.argv.slice (2);
    const flag = name => { const i = args.indexOf (name); return i >= 0 ? args[i + 1] : undefined; };
    const seconds = Number (flag ("--seconds") ?? 4);
    const only = flag ("--only");
    const start = (count, data) => Promise.all (Array.from ({ length: count }, (_, i) => new Promise (resolve =>
    {
        const w = new Worker (new URL (import.meta.url), { workerData: { ...data (i) } });
        w.once ("message", () => resolve (w));
    })));

    if (only !== "match")
        for (const count of [1, 6, 12])
        {
            const workers = await start (count, i => ({ role: "rate", seed: 100 + i, ms: seconds * 1000, fit: true }));
            const counts = await Promise.all (workers.map (w => new Promise (r => { w.once ("message", r); w.postMessage ("go"); })));
            workers.forEach (w => w.terminate ());
            const total = counts.reduce ((a, b) => a + b, 0);
            console.log (`${String (count).padStart (2)} workers: ${(total / seconds).toFixed (0).padStart (4)} candidates/s (${(1000 * seconds * count / total).toFixed (1)} ms each)`);
        }

    if (only !== "rate")
    {
        const engine = await makeEngine ();
        const programs = readBank ("presets/vanilla.porridge");
        const modelPath = join (root, "ui", "match", "match-model.bin");
        const model = existsSync (modelPath) ? MatchModel.parse (new Uint8Array (readFileSync (modelPath))) : undefined;
        for (const count of [6, 12])
        {
            const workers = await start (count, () => ({ role: "pool" }));
            const times = [], best = [];
            for (const index of programIndices)
            {
                await Promise.all (workers.map (w => new Promise (r => { w.once ("message", r); w.postMessage ({ setup: index }); })));
                const target = targetOf (engine, programs[index]);
                // the pool: each candidate to the next free worker
                const idle = [...workers], queue = [];
                const pump = () => { while (idle.length && queue.length) { const w = idle.shift (), job = queue.shift (); w.once ("message", r => { idle.push (w); job.resolve (r); pump (); }); w.postMessage (job.message); } };
                const evaluate = (x, weights, threshold, fit, short) => new Promise (resolve => { queue.push ({ message: { genes: Array.from (x), weights, threshold, fit, short }, resolve }); pump (); });
                const t0 = performance.now ();
                const starts = [Genome.seed (target), ...(model ? MatchModel.suggest (model, target) : [])];
                const m = MatchSearch.makeMatch (starts, target.wave !== undefined, [], undefined, budget, 0.25, 1234);
                await new Promise (done => MatchRun.search (evaluate, m, { onCandidate: () => {}, onProgress: () => {}, onDone: done }));
                times.push ((performance.now () - t0) / 1000);
                best.push (Math.max (...m.searches.map (s => s.best?.similarity ?? 0)));
            }
            const stats = await Promise.all (workers.map (w => new Promise (r => { w.once ("message", r); w.postMessage ({ stats: true }); })));
            workers.forEach (w => w.terminate ());
            const mean = xs => xs.reduce ((a, b) => a + b, 0) / xs.length;
            const evals = stats.reduce ((n, s) => n + s.count, 0), spent = stats.reduce ((n, s) => n + s.ms, 0);
            console.log (`a whole match, ${count} workers: ${mean (times).toFixed (2)} s (${times.map (t => t.toFixed (1)).join (", ")}); best card ${mean (best).toFixed (1)}%; ${(evals / times.length).toFixed (0)} candidates a match, ${(spent / evals).toFixed (1)} ms each in a worker`);
        }
    }
    process.exit (0);
}
