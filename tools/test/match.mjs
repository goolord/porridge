// The sound matcher (ui/match/) without the view: matches two kinds of target with every
// search (MatchSearch.makeMatch, as the drawer runs it) and reports how close the seed (the
// starting point) and each search got, and how long it took.
//
//  - programs from the banks, rendered as samples: things the synth can make, though not
//    always with the genes (user waves, other filters, modulation the genes don't set);
//  - random patches the genes can make (Genome.random), whose answer is known: "true" is how
//    close their own genes score, so a search that falls short of it fell short as a search.
//
// It checks that every search finds a patch at least as close as the seed, that the four
// differ, that every value they set is within its parameter's range, and that Init's own
// sound is matched nearly exactly. --wav writes the targets and the matches to
// tools/test/build/match/ to listen to.
//
// run: node tools/test/match.mjs [--wav] [--budget n] [--genomes n] [--jobs n] [--no-model] [name ...]
//      (needs `npm run build` and bundle/match-engine.* from `node tools/match-engine.mjs`;
//       the predictor's suggestions come from ui/match/match-model.bin when it's there)

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import { availableParallelism } from "node:os";
import * as Preset from "../../ui/Preset.res.mjs";
import * as SoundTarget from "../../ui/match/SoundTarget.res.mjs";
import * as Genome from "../../ui/match/Genome.res.mjs";
import * as Spectrum from "../../ui/match/Spectrum.res.mjs";
import * as MatchLoss from "../../ui/match/MatchLoss.res.mjs";
import * as MatchEngine from "../../ui/match/MatchEngine.res.mjs";
import * as MatchSearch from "../../ui/match/MatchSearch.res.mjs";
import * as MatchRun from "../../ui/match/MatchRun.res.mjs";
import * as MatchModel from "../../ui/match/MatchModel.res.mjs";
import * as Cmaes from "../../ui/match/Cmaes.res.mjs";
import * as ParamDefs from "../../ui/ParamDefs.res.mjs";
import { root, outDir, readBank, checker } from "./lib.mjs";

const seconds = 1.5;
const note = 57;
const modelPath = join (root, "ui", "match", "match-model.bin");

const factory = () => Preset.factoryBank (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
// a spread: bass, bell, kick, snare, organ, Init itself, then piano, choir, saw, bass, acid,
// pluck, bells and a kick of Porridge's own
const bankPrograms = () =>
{
    const f = factory (), vanilla = readBank ("presets/vanilla.porridge");
    return [...[0, 1, 3, 4, 10, 17].map (i => f[i]), ...[0, 9, 23, 25, 29, 38, 41, 58].map (i => vanilla[i])].filter (Boolean);
};

const writeWav = (path, channels, rate = 44100) =>
{
    const n = channels[0].length, c = channels.length;
    const b = Buffer.alloc (44 + n * c * 2);
    b.write ("RIFF", 0); b.writeUInt32LE (36 + n * c * 2, 4); b.write ("WAVEfmt ", 8);
    b.writeUInt32LE (16, 16); b.writeUInt16LE (1, 20); b.writeUInt16LE (c, 22); b.writeUInt32LE (rate, 24);
    b.writeUInt32LE (rate * c * 2, 28); b.writeUInt16LE (c * 2, 32); b.writeUInt16LE (16, 34);
    b.write ("data", 36); b.writeUInt32LE (n * c * 2, 40);
    for (let i = 0; i < n; i++)
        for (let k = 0; k < c; k++)
            b.writeInt16LE (Math.max (-32767, Math.min (32767, Math.round (channels[k][i] * 32767))), 44 + 2 * (i * c + k));
    writeFileSync (path, b);
};

const safe = s => s.replace (/[^A-Za-z0-9_-]+/g, "_");

//==============================================================================
// One target, matched (in a worker thread, each with an engine of its own)

async function matcher ({ budget, wav, useModel })
{
    const glue = readFileSync (join (root, "bundle", "match-engine.js"), "utf8");
    const EngineClass = new Function (glue + "\nreturn PorridgeMatchEngine;") ();
    const wasm = await WebAssembly.compile (readFileSync (join (root, "bundle", "match-engine.wasm")));
    const engine = await MatchEngine.make (EngineClass, wasm);
    const model = useModel && existsSync (modelPath) ? MatchModel.parse (new Uint8Array (readFileSync (modelPath))) : undefined;
    const init = Preset.make ("Init");
    const initValue = id => init.values.get (id) ?? 0;
    const programs = bankPrograms ();
    const frames = Math.round (seconds * 44100);
    const dir = wav ? outDir ("match") : undefined;
    const asSample = (l, r) => ({ samples: l.map ((v, i) => 0.5 * (v + r[i])), sampleRate: 44100, frameSize: undefined });

    return async job =>
    {
        let name, genes, sample;
        if (job.kind === "bank")
        {
            const p = programs[job.index];
            name = Preset.name (p);
            MatchEngine.setBase (engine, p.values, p.tables);
            const [l, r] = MatchEngine.renderStereo (engine, [], note, 0, frames, frames);
            sample = asSample (l, r);
        }
        else
        {
            genes = Genome.random (Cmaes.makeRandom (7717 * (job.index + 1)));
            name = `random ${job.index}: ${Genome.describe (genes)}`;
            MatchEngine.setBase (engine, init.values, init.tables);
            const [l, r] = MatchEngine.renderStereo (engine, Genome.decode (genes, note, initValue), note, 0, frames, frames);
            sample = asSample (l, r);
        }
        const prepared = SoundTarget.prepare (name, sample);
        if (prepared.TAG !== "Ok") return { job, name, error: prepared._0 };
        const target = prepared._0;

        const t0 = performance.now ();
        const ctx = MatchSearch.makeContext (engine, target, init.values, init.tables);
        const score = x => MatchSearch.evaluate (ctx, x, MatchLoss.standard, -1)[0] - MatchSearch.cost (x);
        const similarity = loss => MatchLoss.similarity (loss);
        const seedGenes = Genome.seed (target);
        const suggestions = model ? MatchModel.suggest (model, target) : [];
        const seed = similarity (score (seedGenes));
        const predicted = suggestions.length ? similarity (score (suggestions[0])) : undefined;
        // the true genes, played as a candidate would be from the pitch found: at the octave and
        // tuning (to 5 cents) that suit them best, as the search's render genes would
        const truth = genes ? similarity (Math.min (...[0, 1, 2].flatMap (octave => Array.from ({ length: 21 }, (_, k) =>
        {
            const x = Float64Array.from (genes);
            x[Genome.indexOf ("octave")] = Genome.valueOfChoice (octave, 3);
            x[Genome.indexOf ("tune")] = k / 20;
            return score (x);
        })))) : undefined;
        const m = MatchSearch.makeMatch ([seedGenes, ...suggestions], target.wave !== undefined, [], undefined, budget, 0.25, 1234);
        const evaluate = (x, weights, threshold) => Promise.resolve (MatchSearch.evaluate (ctx, x, weights, threshold));
        await new Promise (done => MatchRun.search (evaluate, m, { onCandidate: () => {}, onProgress: () => {}, onDone: done }));
        const ms = performance.now () - t0;
        const searches = m.searches;
        const evals = m.outline.evals + searches.reduce ((n, s) => n + s.evals, 0);

        if (wav)
        {
            writeWav (join (dir, `${safe (name)}-target.wav`), [target.samples]);
            for (const s of searches)
            {
                MatchEngine.setBase (engine, init.values, MatchSearch.tablesFor (target, init.tables));
                const [l, r] = MatchEngine.renderStereo (engine, s.best.values, s.best.note, 0, frames, frames + 44100);
                writeWav (join (dir, `${safe (name)}-${MatchSearch.islands[s.islandIndex].key}.wav`), [l, r]);
            }
        }
        return {
            job, name, seed, predicted, truth, evals, ms,
            pitch: SoundTarget.pitchText (target),
            shape: `${SoundTarget.seconds (target).toFixed (2)} s, attack ${(target.attack * 1000).toFixed (0)} ms, decay ${(target.decay * 1000).toFixed (0)} ms, sustain ${target.sustain.toFixed (2)}`,
            outline: m.outline.best?.similarity,
            cards: searches.map (s => s.best && { island: MatchSearch.islands[s.islandIndex].key, title: MatchSearch.islands[s.islandIndex].title,
                                                  similarity: s.best.similarity, description: s.best.description,
                                                  genes: s.best.genes, values: s.best.values }),
        };
    };
}

if (! isMainThread)
{
    const match = await matcher (workerData);
    parentPort.on ("message", async job => parentPort.postMessage (await match (job)));
}
else
{
    const args = process.argv.slice (2);
    const flag = name => { const i = args.indexOf (name); return i >= 0 ? args.splice (i, 2)[1] : undefined; };
    const wav = args.includes ("--wav");
    const useModel = ! args.includes ("--no-model");
    const budget = Number (flag ("--budget") ?? 1400);
    const genomes = Number (flag ("--genomes") ?? 12);
    const jobs = Number (flag ("--jobs") ?? Math.max (1, Math.min (12, availableParallelism () - 2)));
    const only = args.filter (a => ! a.startsWith ("--"));
    const { check, done } = checker ();
    const defs = new Map (ParamDefs.makeDefs ().map (d => [d.id, d]));

    const programs = bankPrograms ();
    const all = [
        ...programs.map ((p, index) => ({ kind: "bank", index, name: Preset.name (p) })),
        ...Array.from ({ length: genomes }, (_, index) => ({ kind: "genome", index, name: `random ${index}` })),
    ];
    const todo = only.length ? all.filter (j => only.some (o => j.name.toLowerCase ().includes (o.toLowerCase ()))) : all;
    console.log (`${todo.length} targets, ${budget} renders each, ${Math.min (jobs, todo.length)} at a time${useModel && existsSync (modelPath) ? ", with the predictor" : ""}`);

    // the jobs, handed to the workers as they come free
    const results = new Array (todo.length);
    let next = 0;
    await Promise.all (Array.from ({ length: Math.min (jobs, todo.length) }, () => new Promise ((resolve, reject) =>
    {
        const worker = new Worker (new URL (import.meta.url), { workerData: { budget, wav, useModel } });
        const give = () =>
        {
            if (next >= todo.length) { worker.terminate (); resolve (); return; }
            const k = next++;
            worker.once ("message", r => { results[k] = r; report (r); give (); });
            worker.postMessage (todo[k]);
        };
        worker.on ("error", reject);
        give ();
    })));

    function report (r)
    {
        if (r.error) { console.log (`\n${r.name}: ${r.error}`); return; }
        const pct = v => v === undefined ? "  -  " : v.toFixed (1).padStart (5) + "%";
        console.log (`\n${r.name}  (${r.pitch}, ${r.shape})`);
        console.log (`  seed ${pct (r.seed)}${r.predicted !== undefined ? `  predicted ${pct (r.predicted)}` : ""}${r.truth !== undefined ? `  true genes ${pct (r.truth)}` : ""}` +
                     `  outline ${pct (r.outline)}; ${r.evals} renders in ${(r.ms / 1000).toFixed (1)} s (${(r.ms / r.evals).toFixed (1)} ms each)`);
        for (const c of r.cards)
            if (c) console.log (`  ${c.title.padEnd (8)} ${pct (c.similarity)}  ${c.description}`);
    }

    for (const r of results)
    {
        if (! r || r.error) continue;
        const name = r.name;
        const found = r.cards.filter (Boolean);
        check (found.length === r.cards.length, `${name}: every search found a patch`);
        for (const c of found)
            check (c.similarity >= r.seed - 1, `${name}: ${c.title} (${c.similarity.toFixed (1)}%) is no further than the seed (${r.seed.toFixed (1)}%)`);
        for (let i = 0; i < found.length; i++)
            for (let j = i + 1; j < found.length; j++)
                check (MatchSearch.distance (Float64Array.from (found[i].genes), Float64Array.from (found[j].genes)) > 0.01,
                       `${name}: ${found[i].title} and ${found[j].title} differ`);
        for (const c of found)
            for (const [id, v] of c.values)
            {
                const d = defs.get (id);
                check (d !== undefined && Number.isFinite (v) && Math.abs (d.clamp (v) - v) <= 1e-6 * Math.max (1, Math.abs (v)),
                       `${name}: ${id} = ${v} is within its range`);
            }
        if (name.startsWith ("Init"))
            check (Math.max (...found.map (c => c.similarity)) >= 90, `${name}: Init's own sound is matched (${Math.max (...found.map (c => c.similarity)).toFixed (1)}%)`);
    }

    const ok = results.filter (r => r && ! r.error);
    const summary = kind =>
    {
        const rs = ok.filter (r => r.job.kind === kind);
        if (! rs.length) return "";
        const mean = f => (rs.reduce ((s, r) => s + f (r), 0) / rs.length).toFixed (1);
        const best = r => Math.max (...r.cards.filter (Boolean).map (c => c.similarity));
        const cards = MatchSearch.islands.map ((isl, i) => `${isl.title} ${mean (r => r.cards[i]?.similarity ?? 0)}%`).join ("  ");
        return `\n${kind === "bank" ? "bank programs" : "random patches"} (${rs.length}): seed ${mean (r => r.seed)}%` +
               (rs[0].predicted !== undefined ? `  predicted ${mean (r => r.predicted)}%` : "") +
               (kind === "genome" ? `  true genes ${mean (r => r.truth)}%` : "") +
               `  best card ${mean (best)}%\n  ${cards}`;
    };
    done (summary ("bank") + summary ("genome") + `\n${(ok.reduce ((s, r) => s + r.ms / r.evals, 0) / Math.max (1, ok.length)).toFixed (1)} ms per render`);
}
