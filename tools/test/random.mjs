// Checks the random patches (ui/random/PatchGen.res; run `npm run res` first):
//   - patches of every kind, with each area anywhere from tame to wild, hold only values their
//     parameters can take (in range, list values whole), a rack whose effects are switched on,
//     routings to targets that exist, and a sound output gain;
//   - at 0 an area adds nothing optional (no routings, no effects, no mix mode but a bell's),
//     and the wilder it is, the more it does;
//   - locked areas keep the values of the patch they come from, when making patches and when
//     varying them;
//   - varying every program of the factory and Vanilla banks a lot keeps them sound and leaves
//     their locked areas as they were;
//   - with the test host built (tools/test/build.sh): patches at a middling wildness sound (none
//     silent) and come out near the level their output gain aims at.
//
// run: node tools/test/random.mjs [-v]

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import * as Lazy from "@rescript/runtime/lib/es6/Stdlib_Lazy.js";
import * as Preset from "../../ui/Preset.res.mjs";
import * as FxRack from "../../ui/FxRack.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as OatmealFormat from "../../ui/oatmeal/OatmealFormat.res.mjs";
import * as PatchGen from "../../ui/random/PatchGen.res.mjs";
import { root, host, outDir, render, readBank, checker } from "./lib.mjs";

const { check, fail, done } = checker ({ verbose: process.argv.includes ("-v") });
const defs = Lazy.get (Preset.defsById);
const init = Preset.make ("Init").values;
const r = PatchGen.seeded (31);
const wildAt = w => ({ osc: w, filter: w, env: w, mod: w, fx: w });
const randomWild = () => ({ osc: r (), filter: r (), env: r (), mod: r (), fx: r () });

// what's wrong with a patch's values, if anything (its rack and routings too, unless `only` the
// values are to be checked)
const problems = (m, { only = false } = {}) =>
{
    const found = [];
    for (const [id, x] of m)
    {
        const d = defs.get (id);
        if (! d) { found.push (`unknown parameter ${id}`); continue; }
        if (! Number.isFinite (x)) found.push (`${id} is ${x}`);
        else if (d.clamp (x) !== x) found.push (`${id} ${x} is out of its range`);
        else if (d.names && (! Number.isInteger (x) || x >= d.names.length)) found.push (`${id} ${x} isn't one of its values`);
    }
    const get = id => m.get (id) ?? 0;
    if (only) return found;
    for (const e of FxRack.read (get))
        if (! FxRack.isOn (e, get)) found.push (`the rack's ${FxRack.kindName (e.kind)} is off`);
    for (const k of PatchGen.usedSlots (m))
        if (get (ModMatrix.targetId (k)) <= 0 || get (ModMatrix.targetId (k)) >= ModMatrix.targets.length)
            found.push (`routing ${k} has no target`);
    const gain = get ("Gain");
    if (! (gain > 0.001 && gain <= 2)) found.push (`the output gain is ${gain}`);
    return found;
};

//==============================================================================
// sound values

let made = 0;
for (const kind of PatchGen.kinds)
    for (let i = 0; i < 120; ++i)
    {
        const wild = i < 10 ? wildAt (i / 9) : randomWild ();
        const m = PatchGen.generate (wild, kind, r);
        const p = problems (m);
        if (p.length) fail (`${kind} ${JSON.stringify (wild)}: ${p.slice (0, 3).join ("; ")}`);
        ++made;
    }
check (true, `${made} patches made`);

//==============================================================================
// tame and wild

const average = (wild, kind, measure, n = 150) =>
{
    let s = 0;
    for (let i = 0; i < n; ++i) s += measure (PatchGen.generate (wild, kind, r));
    return s / n;
};
const effects = m => FxRack.read (id => m.get (id) ?? 0).length + (m.get ("Sat_Type") ? 1 : 0);
const routings = m => PatchGen.usedSlots (m).length;
const moded = m => m.get ("OscMix") !== 0 ? 1 : 0;

for (const kind of PatchGen.kinds)
{
    const tame = PatchGen.defaultWildness;
    check (average ({ ...tame, fx: 0 }, kind, effects) === 0, `${kind}: no effects at 0`);
    check (average ({ ...tame, mod: 0 }, kind, routings) === 0, `${kind}: no routings at 0`);
    if (kind !== "bell") check (average ({ ...tame, osc: 0 }, kind, moded) === 0, `${kind}: no mix mode at 0`);
    const [fx3, fx10] = [0.3, 1].map (w => average ({ ...tame, fx: w }, kind, effects));
    const [mod3, mod10] = [0.3, 1].map (w => average ({ ...tame, mod: w }, kind, routings));
    check (fx10 > fx3 + 0.8, `${kind}: more effects when wild (${fx3.toFixed (2)} at 0.3, ${fx10.toFixed (2)} at 1)`);
    check (mod10 > mod3 + 1, `${kind}: more routings when wild (${mod3.toFixed (2)} at 0.3, ${mod10.toFixed (2)} at 1)`);
}
check (average ({ ...PatchGen.defaultWildness, osc: 1 }, "lead", moded) > 0.5, "a wild lead mostly has a mix mode");

//==============================================================================
// locks

const owned = (m, areas) => [...m].filter (([id]) => areas.includes (PatchGen.owner (id)));
const same = (a, b, areas) => owned (a, areas).every (([id, x]) => b.get (id) === x);

for (const areas of [["osc"], ["filter", "env"], ["mod"], ["fx"], ["osc", "fx", "mod"]])
    for (let i = 0; i < 20; ++i)
    {
        const kind = PatchGen.kinds[i % PatchGen.kinds.length];
        const from = PatchGen.generate (randomWild (), kind, r);
        const m = PatchGen.generate (randomWild (), kind, r, [from, areas]);
        if (! same (from, m, areas)) fail (`${kind}: making a patch didn't keep the locked ${areas.join (", ")}`);
        const p = problems (m);
        if (p.length) fail (`${kind}, keeping ${areas.join (", ")}: ${p.slice (0, 3).join ("; ")}`);
        const v = PatchGen.vary (m, 0.7, randomWild (), areas, kind, r);
        if (! same (m, v, areas)) fail (`${kind}: varying didn't keep the locked ${areas.join (", ")}`);
    }

//==============================================================================
// varying the banks

const factory = OatmealFormat.parseFile (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
if (factory.TAG !== "Ok") throw new Error ("factory bank didn't parse");
const banks = [
    ...factory._0.programs.map (p => Preset.fromOatmeal (p.bytes)),
    ...readBank ("presets/vanilla.porridge"),
];
let varied = 0;
for (const p of banks)
{
    const kind = PatchGen.kindOf (p.values);
    for (const [amount, locks] of [[0.15, []], [0.7, ["env"]], [0.7, ["osc", "mod"]]])
    {
        const v = PatchGen.vary (p.values, amount, PatchGen.withWild (PatchGen.defaultWildness, "fx", 0.8), locks, kind, r);
        // (a program's own values may be outside Porridge's ranges: Oatmeal kept what older
        // versions wrote; only what varying set is checked)
        const changed = new Map ([...v].filter (([id, x]) => p.values.get (id) !== x));
        const found = problems (changed, { only: true });
        const gain = v.get ("Gain");
        if (! (gain > 0 && gain <= 2)) found.push (`the output gain is ${gain}`);
        if (found.length) fail (`${Preset.name (p)} varied ${amount}: ${found.slice (0, 3).join ("; ")}`);
        if (! same (p.values, v, locks)) fail (`${Preset.name (p)}: varying changed the locked ${locks.join (", ")}`);
        ++varied;
    }
}
check (true, `${banks.length} programs varied ${varied} times`);

//==============================================================================
// levels, through the test host

if (existsSync (host))
{
    const dir = outDir ("random");
    const rate = 44100;
    const levels = [];
    for (let i = 0; i < 70; ++i)
    {
        const kind = PatchGen.kinds[i % PatchGen.kinds.length];
        const m = PatchGen.generate (wildAt (0.3), kind, r);
        const note = PatchGen.profile (kind).note;
        const program = join (dir, "p.bin"), events = join (dir, "p.txt");
        writeFileSync (program, Preset.toOatmeal ({ ...Preset.make ("p"), values: m }));
        writeFileSync (events, `0 144 ${note} 100\n${2 * rate} 128 ${note} 0\n`);
        // (every value that isn't Init's, or isn't what the DSP starts with: its rack holds
        // Oatmeal's four, Init's is empty)
        const sets = Object.fromEntries ([...m].filter (([id, x]) => x !== init.get (id) || x !== defs.get (id).init));
        const [left, right] = render ({ program, events, frames: 2.5 * rate, rate, sets, out: join (dir, "p.f32") });
        // RMS over the loudest 300 ms
        const step = rate / 100, power = [];
        for (let a = 0; a + step <= left.length; a += step)
        {
            let s = 0;
            for (let j = a; j < a + step; ++j) s += left[j] * left[j] + right[j] * right[j];
            power.push (s / (2 * step));
        }
        let best = 0;
        for (let k = 0; k + 30 <= power.length; ++k) best = Math.max (best, power.slice (k, k + 30).reduce ((a, b) => a + b, 0) / 30);
        const db = 10 * Math.log10 (Math.max (best, 1e-18));
        if (db < -60) fail (`${kind} at 0.3 is silent (${db.toFixed (1)} dB): ${PatchGen.describe (m, note).map (([, t]) => t).join ("; ")}`);
        levels.push (db - PatchGen.targetDb);
    }
    levels.sort ((a, b) => a - b);
    const median = levels[levels.length >> 1];
    const within = levels.filter (d => Math.abs (d - median) < 6).length / levels.length;
    check (Math.abs (median) < 3, `patches at 0.3 come out near their level (median ${median.toFixed (1)} dB from it)`);
    check (within >= 0.85, `most of them within 6 dB of each other (${Math.round (100 * within)}%)`);
}
else
    console.log ("(no test host: tools/test/build.sh builds it; the levels weren't checked)");

done ("random patches ok");
