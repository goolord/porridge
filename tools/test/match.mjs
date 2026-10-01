// The sound matcher (ui/match/) without the view: renders programs from the banks as target
// samples, matches each from Init with every search (MatchSearch.islands), and reports how
// close the seed (the search's starting point) and each search got, and how long it took.
// Programs the synth made itself can be matched exactly, so the scores show how much of the
// way the search gets; --wav writes the targets and the matches to tools/test/build/match/
// to listen to.
//
// It checks that every search finds a patch at least as close as the seed, that the four
// differ, that every value they set is within its parameter's range, and that Init's own
// sound is matched nearly exactly.
//
// run: node tools/test/match.mjs [--wav] [--budget n] [--seconds s] [name ...]
//      (needs `npm run build` and bundle/match-engine.* from `node tools/match-engine.mjs`)

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as Preset from "../../ui/Preset.res.mjs";
import * as SoundTarget from "../../ui/match/SoundTarget.res.mjs";
import * as Genome from "../../ui/match/Genome.res.mjs";
import * as Spectrum from "../../ui/match/Spectrum.res.mjs";
import * as MatchLoss from "../../ui/match/MatchLoss.res.mjs";
import * as MatchEngine from "../../ui/match/MatchEngine.res.mjs";
import * as MatchSearch from "../../ui/match/MatchSearch.res.mjs";
import * as MatchRun from "../../ui/match/MatchRun.res.mjs";
import * as ParamDefs from "../../ui/ParamDefs.res.mjs";
import { root, outDir, readBank, checker } from "./lib.mjs";

const args = process.argv.slice (2);
const flag = name => { const i = args.indexOf (name); return i >= 0 ? args.splice (i, 2)[1] : undefined; };
const wav = args.includes ("--wav");
const budget = Number (flag ("--budget") ?? 360);
const seconds = Number (flag ("--seconds") ?? 1.5);
const only = args.filter (a => ! a.startsWith ("--"));
const dir = outDir ("match");
const { check, done } = checker ();
const defs = new Map (ParamDefs.makeDefs ().map (d => [d.id, d]));

const glue = readFileSync (join (root, "bundle", "match-engine.js"), "utf8");
const EngineClass = new Function (glue + "\nreturn PorridgeMatchEngine;") ();
const wasm = await WebAssembly.compile (readFileSync (join (root, "bundle", "match-engine.wasm")));
const engine = await MatchEngine.make (EngineClass, wasm);

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
const init = Preset.make ("Init");
const initValue = id => init.values.get (id) ?? 0;

// A program's note as a sample: its own patch as the base, nothing on top.
const renderProgram = (p, note) =>
{
    MatchEngine.setBase (engine, p.values, p.tables);
    const frames = Math.round (seconds * 44100);
    const [l, r] = MatchEngine.renderStereo (engine, [], note, 0, frames, frames);
    return { samples: l.map ((v, i) => 0.5 * (v + r[i])), sampleRate: 44100, frameSize: undefined, sides: [l, r] };
};

const factory = Preset.factoryBank (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
const vanilla = readBank ("presets/vanilla.porridge");
// a spread: bass, bell, kick, snare, organ, Init itself, then piano, choir, saw, bass, acid,
// pluck, bells and a kick of Porridge's own
const defaults = [
    ...[0, 1, 3, 4, 10, 17].map (i => factory[i]),
    ...[0, 9, 23, 25, 29, 38, 41, 58].map (i => vanilla[i]),
].filter (Boolean);
const programs = only.length
    ? [...factory, ...vanilla].filter (p => only.some (o => Preset.name (p).toLowerCase ().includes (o.toLowerCase ())))
    : defaults;

const results = [];
for (const p of programs)
{
    const name = Preset.name (p);
    const prepared = SoundTarget.prepare (name, renderProgram (p, 57));
    if (prepared.TAG !== "Ok") { console.log (`${name}: ${prepared._0}`); continue; }
    const target = prepared._0;

    const t0 = performance.now ();
    const ctx = MatchSearch.makeContext (engine, target, init.values, init.tables);
    const start = Genome.seed (target);
    const seedRender = MatchEngine.render (engine, Genome.decode (start, target.note, initValue), target.note, target.cents, target.samples.length);
    const seed = MatchLoss.similarity (MatchLoss.compare (MatchLoss.standard, ctx.measured, Spectrum.measure (seedRender, SoundTarget.period (target))));
    const searches = MatchSearch.islands.map ((_, i) => MatchSearch.makeSearch (i, start, [], undefined, budget, 0.25, 1234 + i));
    // as the view runs them, with the engine here instead of the workers
    const evaluate = (x, weights, threshold) => Promise.resolve (MatchSearch.evaluate (ctx, x, weights, threshold));
    await new Promise (done => MatchRun.search (evaluate, searches, { onCandidate: () => {}, onProgress: () => {}, onDone: done }));
    const ms = performance.now () - t0;
    const evals = searches.reduce ((n, s) => n + s.evals, 0);

    console.log (`\n${name}  (${SoundTarget.pitchText (target)}, ${SoundTarget.seconds (target).toFixed (2)} s, attack ${(target.attack * 1000).toFixed (0)} ms, decay ${(target.decay * 1000).toFixed (0)} ms, sustain ${target.sustain.toFixed (2)}, centroid ${target.brightness.toFixed (0)} Hz)`);
    console.log (`  seed ${seed.toFixed (1)}%; ${evals} renders in ${(ms / 1000).toFixed (1)} s (${(ms / evals).toFixed (1)} ms each)`);
    const row = { name, seed };
    for (const s of searches)
    {
        const c = s.best;
        console.log (`  ${s.island.title.padEnd (8)} ${c.similarity.toFixed (1).padStart (5)}%  ${c.description}`);
        row[s.island.key] = c.similarity;
        if (wav)
        {
            MatchEngine.setBase (engine, init.values, init.tables);
            const [l, r] = MatchEngine.renderStereo (engine, c.values, target.note, 0, Math.round (seconds * 44100), Math.round ((seconds + 1) * 44100));
            writeWav (join (dir, `${safe (name)}-${s.island.key}.wav`), [l, r]);
        }
    }
    if (wav) writeWav (join (dir, `${safe (name)}-target.wav`), [target.samples]);

    const found = searches.map (s => s.best).filter (Boolean);
    check (found.length === searches.length, `${name}: every search found a patch`);
    for (const s of searches)
        if (s.best) check (s.best.similarity >= seed - 1, `${name}: ${s.island.title} (${s.best.similarity.toFixed (1)}%) is no further than the seed (${seed.toFixed (1)}%)`);
    for (let i = 0; i < found.length; i++)
        for (let j = i + 1; j < found.length; j++)
            check (MatchSearch.distance (Float64Array.from (found[i].genes), Float64Array.from (found[j].genes)) > 0.01,
                   `${name}: ${searches[i].island.title} and ${searches[j].island.title} differ`);
    for (const c of found)
        for (const [id, v] of c.values)
        {
            const d = defs.get (id);
            check (d !== undefined && Number.isFinite (v) && Math.abs (d.clamp (v) - v) <= 1e-6 * Math.max (1, Math.abs (v)),
                   `${name}: ${id} = ${v} is within its range`);
        }
    if (name.startsWith ("Init"))
        check (Math.max (...found.map (c => c.similarity)) >= 90, `${name}: Init's own sound is matched (${Math.max (...found.map (c => c.similarity)).toFixed (1)}%)`);
    results.push (row);
}

const mean = key => results.reduce ((s, r) => s + r[key], 0) / Math.max (1, results.length);
done (`\nmean: seed ${mean ("seed").toFixed (1)}%  ` + MatchSearch.islands.map (i => `${i.title} ${mean (i.key).toFixed (1)}%`).join ("  "));
