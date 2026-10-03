// Measures what the random patches' level estimate needs (ui/random/PatchGen.res: `loudness`),
// rendering through the test host with the output gain at 1:
//
//   --tables   the levels of the waveforms, of the noise source by its resonance and its type, and what each
//              distortion type and each filter type (for a saw and for a sine, with the cutoff
//              from 2 octaves under the note to 5 over, and with resonance) do to a note's level;
//              written to ui/random/LevelTables.res
//   (default)  random patches of every kind at random wildnesses (seeded), each one's note at
//              the note it's auditioned at: its RMS over the loudest 300 ms and its peak, against
//              the estimate; then the estimate's weights fitted again by least squares (ridge),
//              printed to paste into PatchGen.res, with how far that fit is
//
// run: node tools/random-levels.mjs [--tables] [--count n] [--seed s] [--jobs j]
//      (build the host with tools/test/build.sh and run `npm run res` first)

import { writeFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import * as Lazy from "@rescript/runtime/lib/es6/Stdlib_Lazy.js";
import * as Preset from "../ui/Preset.res.mjs";
import * as FilterTypes from "../ui/FilterTypes.res.mjs";
import * as DistTypes from "../ui/DistTypes.res.mjs";
import * as FxRack from "../ui/FxRack.res.mjs";
import * as PorridgeParams from "../ui/PorridgeParams.res.mjs";
import * as PatchGen from "../ui/random/PatchGen.res.mjs";
import { root, outDir, host, kWeight, loudest } from "./test/lib.mjs";

const args = process.argv.slice (2);
const option = (name, fallback) => { const i = args.indexOf ("--" + name); return i < 0 ? fallback : Number (args[i + 1]); };
const count = option ("count", 400), seed = option ("seed", 1), jobs = option ("jobs", 8);

const dir = outDir ("random-levels");
const rate = 44100, hold = 2, length = 2.5;
const init = Preset.make ("Init").values;
const defs = Lazy.get (Preset.defsById);
const db = x => 20 * Math.log10 (Math.max (x, 1e-9));

// RMS over the loudest 300 ms, dB; the same K-weighted (as loud as a meter hears it); and the
// peak (dBFS)
const measure = ([l, r]) =>
{
    const peak = l.reduce ((m, x, i) => Math.max (m, Math.abs (x), Math.abs (r[i])), 0);
    return { rms: loudest ([l, r], rate), k: loudest ([kWeight (l, rate), kWeight (r, rate)], rate), peak: db (peak) };
};

// Renders a note of these values (and tables, Init's if not given) with the output gain at 1, and
// measures it.
let renders = 0;
const level = (values, note, tables) => new Promise ((done, fail) =>
{
    const name = "r" + (renders++ % (4 * jobs));
    const program = join (dir, name + ".bin"), events = join (dir, name + ".txt"), out = join (dir, name + ".f32");
    const made = Preset.make (name);
    writeFileSync (program, Preset.toOatmeal ({ ...made, values, tables: tables ?? made.tables }));
    writeFileSync (events, `0 144 ${note} 100\n${hold * rate} 128 ${note} 0\n`);
    // Oatmeal's export loses Porridge's values: set every one that isn't Init's, or isn't what
    // the DSP starts with (its rack holds Oatmeal's four, Init's is empty)
    const sets = [["Gain", 1], ...[...values].filter (([id, x]) => id !== "Gain" && (x !== init.get (id) || x !== defs.get (id).init))];
    const argv = ["--program", program, "--events", events, "--frames", String (length * rate), "--rate", String (rate),
                  ...sets.flatMap (([k, v]) => ["--set", `${k}=${v}`]), "--out", out];
    execFile (host, argv, async error =>
    {
        if (error) return fail (error);
        const b = await readFile (out);
        const channels = b.readInt32LE (0), n = b.readInt32LE (4);
        const data = new Float32Array (b.buffer.slice (b.byteOffset + 8, b.byteOffset + 8 + 4 * channels * n));
        done (measure (Array.from ({ length: channels }, (_, c) => data.subarray (c * n, (c + 1) * n))));
    });
});

// runs the tasks `jobs` at a time, in order
const pool = async (tasks, label) =>
{
    const results = new Array (tasks.length);
    let next = 0, finished = 0;
    await Promise.all (Array.from ({ length: jobs }, async () =>
    {
        while (next < tasks.length)
        {
            const i = next++;
            results[i] = await tasks[i] ();
            if (++finished % 200 === 0) console.log (`${label} ${finished}/${tasks.length}`);
        }
    }));
    return results;
};

const withValues = changes =>
{
    const values = new Map (init);
    for (const [k, v] of Object.entries (changes)) values.set (k, v);
    return values;
};

//==============================================================================
// The tables

if (args.includes ("--tables"))
{
    // the cutoffs, octaves above the note; the noise resonances; the distortion pregains
    const octaves = [-2, -1, 0, 1, 2, 3, 4, 5], resOctaves = [0, 2, 4];
    const noiseRes = [0, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95];
    const pregains = [-24, -12, -6, 0, 6, 12, 18, 24, 30, 36, 42];
    const types = FilterTypes.all.length, drives = 17, waves = 9;
    // (the sample is left out: what it plays is a file's)
    const noiseTypes = PorridgeParams.noiseTypes.length - 1;
    const hz60 = 440 * 2 ** (-9 / 12);
    const plain = { Filter: 0, Sustain: 1, Attack: 1, Decay2: 1000, Release: 100, F_EnvMod: 0, F_Track: 0 };
    const note = changes => () => level (withValues ({ ...plain, ...changes }), 60);
    const filter = (t, octave, res) => ({ Filter: t, Cutoff: FilterTypes.cutoffOfHz (t, hz60 * 2 ** octave), Resonance: res });
    const tasks = [
        ...Array.from ({ length: waves }, (_, w) => note ({ O1_Waveform: w })),
        ...noiseRes.map (res => note ({ O1_Amp: 0, N_Amp: 1, N_Resonance: res })),
        ...Array.from ({ length: noiseTypes }, (_, t) => note ({ O1_Amp: 0, N_Amp: 1, N_Type: t })),
        ...Array.from ({ length: drives }, (_, t) => pregains.map (pre =>
            note ({ O1_Waveform: 6, Sat_Type: t, Sat_Mode: 1, Sat_Pregain: pre, Sat_Postgain: 0 }))).flat (),
        ...Array.from ({ length: types }, (_, t) => [
            ...[6, 0].flatMap (wave => octaves.map (o => note ({ O1_Waveform: wave, ...filter (t, o, 0) }))),
            ...resOctaves.flatMap (o => [0.5, 0.85].map (res => note ({ O1_Waveform: 6, ...filter (t, o, res) }))),
            note ({ O1_Waveform: 6, ...filter (t, 2, 0), F_Drive: 0.5 }),
        ]).flat (),
    ];
    const results = (await pool (tasks, "rendered")).map (x => x.k);
    let at = 0;
    const take = n => { const r = results.slice (at, at + n); at += n; return r; };
    const waveLevels = take (waves);
    const noise = take (noiseRes.length);
    const noiseTypeLevels = take (noiseTypes);
    const [saw, sine] = [waveLevels[6], waveLevels[0]];
    // (the distortion's output level for each input level: the saw's, raised by the pregain)
    const drive = Array.from ({ length: drives }, () => take (pregains.length));
    const filters = Array.from ({ length: types }, () =>
    {
        const sawRow = take (octaves.length).map (x => x - saw);
        const sineRow = take (octaves.length).map (x => x - sine);
        const res = resOctaves.flatMap (o => take (2).map (x => x - saw - sawRow[octaves.indexOf (o)]));
        const drive = take (1)[0] - saw - sawRow[octaves.indexOf (2)];
        return { saw: sawRow, sine: sineRow, res, drive };
    });
    const num = x => { const s = (Math.round (Math.max (-60, x) * 10) / 10).toFixed (1); return s === "-0.0" ? "0.0" : s; };
    const list = xs => "[" + xs.map (num).join (", ") + "]";
    const axis = xs => "[" + xs.map (x => Number.isInteger (x) ? x.toFixed (1) : String (x)).join (", ") + "]";
    const rows = (name, xs, label) => `let ${name} = [\n${xs.map ((x, i) => `  ${list (x)}, // ${label (i)}`).join ("\n")}\n]`;
    const text = `// Generated by tools/random-levels.mjs --tables - do not edit by hand.
//
// What the random patches' level estimate (PatchGen.loudness) knows of the synth: levels in dB
// (K-weighted, as a loudness meter hears it: the mean power over the loudest 300 ms of a note
// at 60, velocity 100, with the output gain at 1).

// each waveform's level (O1_Waveform, at its 50% pulse width), alone at 0 dB
let waves = ${list (waveLevels)}

// the noise source's level alone at 0 dB, at these resonances
let noiseResonances = ${axis (noiseRes)}
let noise = ${list (noise)}

// each noise type's level alone at 0 dB, with no resonance (N_Type, the sample left out; the
// crackle at its default density)
let noiseTypes = ${list (noiseTypeLevels)}

// each distortion type's output level (Sat_Type, per voice after the filter, with no postgain)
// for a saw going in at these levels (its own, raised by the pregain)
let driveInputs = ${list (pregains.map (p => saw + p))}
${rows ("drive", drive, t => DistTypes.all[t].name)}

// each filter type's level against no filter (by FilterTypes index), for a saw and for a sine,
// with the cutoff at these octaves above the note (no key tracking, no resonance)
let octaves = ${axis (octaves)}
${rows ("saw", filters.map (f => f.saw), t => FilterTypes.all[t])}
${rows ("sine", filters.map (f => f.sine), t => FilterTypes.all[t])}

// what resonance 0.5 and 0.85 add to a saw with the cutoff at each of these octaves (in pairs)
let resonanceOctaves = ${axis (resOctaves)}
${rows ("resonance", filters.map (f => f.res), t => FilterTypes.all[t])}

// what the filter's drive at 0.5 adds to a saw with the cutoff two octaves up
let filterDrive = ${list (filters.map (f => f.drive))}
`;
    writeFileSync (join (root, "ui", "random", "LevelTables.res"), text);
    console.log (`a saw: ${saw.toFixed (1)} dB, a sine: ${sine.toFixed (1)} dB; wrote ui/random/LevelTables.res`);
    process.exit (0);
}

//==============================================================================
// Random patches against the estimate

// (--fx w holds the effects' wildness at w)
const fixedFx = option ("fx", -1);
const r = PatchGen.seeded (seed);
const patches = Array.from ({ length: count }, (_, i) =>
{
    const kind = PatchGen.kinds[i % PatchGen.kinds.length];
    const wild = { osc: r (), filter: r (), env: r (), mod: r (), fx: r () };
    if (fixedFx >= 0) wild.fx = fixedFx;
    const { values, tables } = PatchGen.generate (wild, kind, r);
    return { i, kind, wild, values, tables, note: PatchGen.profile (kind).note };
});

const measured = await pool (patches.map (p => () => level (p.values, p.note, p.tables)), "rendered");
const results = patches.map ((p, i) => ({ ...p, ...measured[i] }));

const silent = results.filter (x => x.rms < -70);
const heard = results.filter (x => x.rms >= -70);
for (const x of silent)
    console.log (`silent: ${x.kind} ${JSON.stringify (x.wild)}\n  ${PatchGen.describe (x.values, x.note).map (([a, t]) => a + ": " + t).join ("\n  ")}`);

const stats = errors =>
{
    const mean = errors.reduce ((a, b) => a + b, 0) / errors.length;
    const sd = Math.sqrt (errors.reduce ((a, b) => a + (b - mean) ** 2, 0) / errors.length);
    const sorted = errors.map (x => Math.abs (x - mean)).sort ((a, b) => a - b);
    return `mean ${mean.toFixed (2)} dB, sd ${sd.toFixed (2)} dB, 90% within ${sorted[Math.floor (0.9 * sorted.length)].toFixed (1)} dB of it`;
};
const levels = heard.map (x => x.k);
console.log (`\n${heard.length} heard (${silent.length} silent); their levels: ${stats (levels)}`);
// how loud they play with their output gains, driven or not (RMS, and K-weighted as a meter hears)
const driven = x => x.values.get ("Sat_Type") !== 0 || FxRack.read (id => x.values.get (id) ?? 0).some (e => e.kind === "distortion");
for (const [label, group] of [["driven", heard.filter (driven)], ["clean", heard.filter (x => ! driven (x))]])
    if (group.length > 1)
        console.log (`  ${label} (${group.length}): RMS ${stats (group.map (x => x.rms + db (x.values.get ("Gain"))))}; K-weighted ${stats (group.map (x => x.k + db (x.values.get ("Gain"))))}`);
console.log (`the estimate as it is: ${stats (heard.map (x => PatchGen.loudness (x.values, x.note, x.tables) - x.k))}`);
const gained = heard.map (x => x.k + db (x.values.get ("Gain")));
console.log (`with their output gains: ${stats (gained)} (aiming at ${PatchGen.targetDb} dB)`);
const peaks = heard.map (x => x.peak + db (x.values.get ("Gain")));
console.log (`their peaks with the gains: highest ${Math.max (...peaks).toFixed (1)} dBFS, ${peaks.filter (p => p > -1).length} above -1 dBFS`);
// how far a note's peak is above its loudest moment as simulated (with the estimate's correction)
const crests = heard.map (x => x.peak - PatchGen.loudestMoment (x.values, x.note, x.tables)).sort ((a, b) => a - b);
const at = q => crests[Math.floor (q * (crests.length - 1))].toFixed (1);
console.log (`peaks above the simulated loudest moment: median ${at (0.5)} dB, 90% ${at (0.9)}, 98% ${at (0.98)}, most ${at (1)}`);

// least squares with a little ridge (not on the constant): (X'X + λI) w = X'y, the estimate's
// simulated level taken as it is
const features = heard.map (x => PatchGen.loudnessFeatures (x.values));
const base = heard.map (x => PatchGen.simulatedLevel (x.values, x.note, undefined, x.tables));
const k = features[0].length + 1;
const rows = features.map (f => [...f, 1]);
const lambda = 1;
const y = heard.map ((x, i) => x.k - base[i]);
const a = Array.from ({ length: k }, (_, i) => Array.from ({ length: k }, (_, j) =>
    rows.reduce ((s, row) => s + row[i] * row[j], 0) + (i === j && i < k - 1 ? lambda : 0)));
const v = Array.from ({ length: k }, (_, i) => rows.reduce ((s, row, n) => s + row[i] * y[n], 0));
for (let c = 0; c < k; ++c)
{
    let p = c;
    for (let i = c + 1; i < k; ++i) if (Math.abs (a[i][c]) > Math.abs (a[p][c])) p = i;
    [a[c], a[p]] = [a[p], a[c]]; [v[c], v[p]] = [v[p], v[c]];
    for (let i = c + 1; i < k; ++i)
    {
        const f = a[i][c] / a[c][c];
        for (let j = c; j < k; ++j) a[i][j] -= f * a[c][j];
        v[i] -= f * v[c];
    }
}
const w = new Array (k).fill (0);
for (let i = k - 1; i >= 0; --i)
    w[i] = (v[i] - a[i].slice (i + 1).reduce ((s, x, j) => s + x * w[i + 1 + j], 0)) / a[i][i];

const fitted = rows.map ((row, n) => base[n] + row.reduce ((s, x, i) => s + x * w[i], 0));
console.log (`fitted: ${stats (fitted.map ((f, i) => f - heard[i].k))}`);
// how far the fit is for the tamer patches and the wilder (by their areas' mean wildness)
for (const [lo, hi] of [[0, 0.35], [0.35, 0.65], [0.65, 1]])
{
    const errors = heard.map ((x, i) => ({ x, e: fitted[i] - x.k })).filter (({ x }) =>
    {
        const mean = Object.values (x.wild).reduce ((a, b) => a + b, 0) / 5;
        return mean >= lo && mean < hi;
    }).map (({ e }) => e);
    if (errors.length > 1) console.log (`  mean wildness ${lo}..${hi} (${errors.length}): ${stats (errors)}`);
}
const num = x => { const s = (Math.round (x * 1000) / 1000).toString (); return s.includes (".") ? s : s + "."; };
console.log (`\nlet loudnessWeights = [${w.slice (0, -1).map (num).join (", ")}]`);
console.log (`let loudnessBias = ${num (w[k - 1])}`);

// the loudest as they play, with their output gains
console.log ("\nloudest with their gains:");
for (const x of [...heard].sort ((p, q) => (q.k + db (q.values.get ("Gain"))) - (p.k + db (p.values.get ("Gain")))).slice (0, 8))
    console.log (`${(x.k + db (x.values.get ("Gain"))).toFixed (1)} dB (RMS ${(x.rms + db (x.values.get ("Gain"))).toFixed (1)}, estimate ${(PatchGen.loudness (x.values, x.note, x.tables) - x.k).toFixed (1)} off)  ${x.kind} #${x.i}\n  ${PatchGen.describe (x.values, x.note).map (([a, t]) => a + ": " + t).join ("\n  ")}`);

// the furthest from the fit, to see what it misses
const worst = heard.map ((x, i) => ({ x, error: fitted[i] - x.k })).sort ((p, q) => Math.abs (q.error) - Math.abs (p.error)).slice (0, 10);
console.log ("\nfurthest from the fit:");
for (const { x, error } of worst)
    console.log (`${error > 0 ? "+" : ""}${error.toFixed (1)} dB  ${x.kind} #${x.i} (measured ${x.k.toFixed (1)}, peak ${x.peak.toFixed (1)})\n  ${PatchGen.describe (x.values, x.note).map (([a, t]) => a + ": " + t).join ("\n  ")}`);
