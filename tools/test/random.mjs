// Checks the random patches (ui/random/PatchGen.res; run `npm run res` first):
//   - patches of every kind, with each area anywhere from tame to wild, hold only values their
//     parameters can take (in range, list values whole), a rack and a voice lane whose effects
//     are switched on, routings and XY routes to targets that exist, drawn waves that are
//     sound (a cycle at a peak of 1, no offset), and a sound output gain;
//   - at 0 an area adds nothing optional (no routings or XY routes, no effects in the rack or
//     the voices, no mix mode but a bell's), and the wilder it is, the more it does; drawn waves
//     come at every wildness, more often wild;
//   - locked areas keep the values of the patch they come from (the oscillators their drawn
//     waves too), when making patches and when varying them;
//   - varying every program of the factory and Vanilla banks a lot keeps them sound and leaves
//     their locked areas as they were;
//   - with the test host built (tools/test/build.sh): patches at a middling wildness sound (none
//     silent) and come out near the level their output gain aims at (K-weighted, as the drawer
//     meters them), and with the wildest effects (heavy distortion) none comes out much louder.
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
import { root, host, outDir, render, readBank, checker, kWeight, loudest } from "./lib.mjs";

const { check, fail, done } = checker ({ verbose: process.argv.includes ("-v") });
const defs = Lazy.get (Preset.defsById);
const init = Preset.make ("Init").values;
const r = PatchGen.seeded (31);
const wildAt = w => ({ osc: w, filter: w, env: w, mod: w, fx: w });
const randomWild = () => ({ osc: r (), filter: r (), env: r (), mod: r (), fx: r () });

// what's wrong with a patch's values, if anything (its rack, lane, routings and drawn waves too,
// unless `only` the values are to be checked)
const problems = (m, { only = false, tables } = {}) =>
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
    const lane = FxRack.readLane (get);
    for (const e of lane)
    {
        if (! FxRack.isOn (e, get)) found.push (`the voice lane's ${FxRack.kindName (e.kind)} is off`);
        if (FxRack.holds (FxRack.read (get), e)) found.push (`the ${FxRack.kindName (e.kind)} is in the rack and the lane`);
    }
    for (const k of PatchGen.usedSlots (m))
        if (get (ModMatrix.targetId (k)) <= 0 || get (ModMatrix.targetId (k)) >= ModMatrix.targets.length)
            found.push (`routing ${k} has no target`);
    for (const axis of ["H", "V"])
        for (const n of [1, 2, 3, 4])
            if (get (`XY_${axis}_Target_${n}`) !== 0 && get (`XY_${axis}_Depth_${n}`) === 0)
                found.push (`XY route ${axis} ${n} has no depth`);
    // a drawn wave an oscillator plays: 512 points at a peak of 1, without an offset
    for (const [osc, table] of [[1, "wave1"], [2, "wave2"]])
        if (tables && [4, 5].includes (get (`O${osc}_Waveform`)))
        {
            const w = tables[table];
            const peak = w.reduce ((p, x) => Math.max (p, Math.abs (x)), 0);
            const mean = w.reduce ((a, x) => a + x, 0) / w.length;
            if (w.length !== 512 || ! w.every (Number.isFinite) || Math.abs (peak - 1) > 1e-3 || Math.abs (mean) > 0.02)
                found.push (`osc ${osc}'s drawn wave isn't sound (peak ${peak}, offset ${mean})`);
        }
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
        const t = PatchGen.generate (wild, kind, r);
        const p = problems (t.values, { tables: t.tables });
        if (p.length) fail (`${kind} ${JSON.stringify (wild)}: ${p.slice (0, 3).join ("; ")}`);
        ++made;
    }
check (true, `${made} patches made`);

//==============================================================================
// tame and wild

const average = (wild, kind, measure, n = 150) =>
{
    let s = 0;
    for (let i = 0; i < n; ++i) s += measure (PatchGen.generate (wild, kind, r).values);
    return s / n;
};
const effects = m => FxRack.read (id => m.get (id) ?? 0).length + (m.get ("Sat_Type") ? 1 : 0);
const voiceEffects = m => FxRack.readLane (id => m.get (id) ?? 0).length;
const routings = m => PatchGen.usedSlots (m).length;
const xyRoutes = m => ["H", "V"].flatMap (a => [1, 2, 3, 4].filter (n => m.get (`XY_${a}_Target_${n}`))).length;
const moded = m => m.get ("OscMix") !== 0 ? 1 : 0;
const drawn = m => [4, 5].includes (m.get ("O1_Waveform")) ? 1 : 0;

for (const kind of PatchGen.kinds)
{
    const tame = PatchGen.defaultWildness;
    check (average ({ ...tame, fx: 0 }, kind, m => effects (m) + voiceEffects (m)) === 0, `${kind}: no effects at 0`);
    check (average ({ ...tame, mod: 0 }, kind, m => routings (m) + xyRoutes (m)) === 0, `${kind}: no routings at 0`);
    if (kind !== "bell") check (average ({ ...tame, osc: 0 }, kind, moded) === 0, `${kind}: no mix mode at 0`);
    const [fx3, fx10] = [0.3, 1].map (w => average ({ ...tame, fx: w }, kind, effects));
    const [mod3, mod10] = [0.3, 1].map (w => average ({ ...tame, mod: w }, kind, routings));
    check (fx10 > fx3 + 0.8, `${kind}: more effects when wild (${fx3.toFixed (2)} at 0.3, ${fx10.toFixed (2)} at 1)`);
    check (mod10 > mod3 + 1, `${kind}: more routings when wild (${mod3.toFixed (2)} at 0.3, ${mod10.toFixed (2)} at 1)`);
}
check (average ({ ...PatchGen.defaultWildness, osc: 1 }, "lead", moded) > 0.5, "a wild lead mostly has a mix mode");
// the XY pad, the voice lane and drawn waves, by how wild their areas are (over every kind)
const overKinds = (wild, measure) => PatchGen.kinds.reduce ((s, kind) => s + average (wild, kind, measure, 100), 0) / PatchGen.kinds.length;
{
    const tame = PatchGen.defaultWildness;
    const [xy3, xy10] = [0.3, 1].map (w => overKinds ({ ...tame, mod: w }, m => xyRoutes (m) > 0 ? 1 : 0));
    check (xy3 > 0.3 && xy3 < 0.65 && xy10 > xy3 + 0.15, `the XY pad routed in ${Math.round (100 * xy3)}% at 0.3, ${Math.round (100 * xy10)}% at 1`);
    const [lane3, lane10] = [0.3, 1].map (w => overKinds ({ ...tame, fx: w }, m => voiceEffects (m) > 0 ? 1 : 0));
    check (lane3 > 0.05 && lane3 < 0.35 && lane10 > lane3 + 0.25, `an effect in every voice in ${Math.round (100 * lane3)}% at 0.3, ${Math.round (100 * lane10)}% at 1`);
    const [drawn0, drawn10] = [0, 1].map (w => overKinds ({ ...tame, osc: w }, drawn));
    check (drawn0 > 0.25 && drawn10 > drawn0 + 0.15, `osc 1 drawn in ${Math.round (100 * drawn0)}% at 0, ${Math.round (100 * drawn10)}% at 1`);
}

//==============================================================================
// locks

const owned = (m, areas) => [...m].filter (([id]) => areas.includes (PatchGen.owner (id)));
// (the oscillators' drawn waves are theirs)
const same = (a, b, areas) => owned (a.values, areas).every (([id, x]) => b.values.get (id) === x)
    && (! areas.includes ("osc") || (a.tables.wave1 === b.tables.wave1 && a.tables.wave2 === b.tables.wave2));

for (const areas of [["osc"], ["filter", "env"], ["mod"], ["fx"], ["osc", "fx", "mod"]])
    for (let i = 0; i < 20; ++i)
    {
        const kind = PatchGen.kinds[i % PatchGen.kinds.length];
        const from = PatchGen.generate (randomWild (), kind, r);
        const m = PatchGen.generate (randomWild (), kind, r, [from, areas]);
        if (! same (from, m, areas)) fail (`${kind}: making a patch didn't keep the locked ${areas.join (", ")}`);
        const p = problems (m.values, { tables: m.tables });
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
        const v = PatchGen.vary ({ values: p.values, tables: p.tables }, amount, PatchGen.withWild (PatchGen.defaultWildness, "fx", 0.8), locks, kind, r);
        // (a program's own values may be outside Porridge's ranges: Oatmeal kept what older
        // versions wrote; only what varying set is checked)
        const changed = new Map ([...v.values].filter (([id, x]) => p.values.get (id) !== x));
        const found = problems (changed, { only: true });
        const gain = v.values.get ("Gain");
        if (! (gain > 0 && gain <= 2)) found.push (`the output gain is ${gain}`);
        if (found.length) fail (`${Preset.name (p)} varied ${amount}: ${found.slice (0, 3).join ("; ")}`);
        if (! same (p, v, locks)) fail (`${Preset.name (p)}: varying changed the locked ${locks.join (", ")}`);
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
    // how far from their level patches made at this wildness come out, dB, in order
    const levelsAt = (wild, label) =>
    {
        const levels = [];
        for (let i = 0; i < 70; ++i)
        {
            const kind = PatchGen.kinds[i % PatchGen.kinds.length];
            const { values: m, tables } = PatchGen.generate (wild, kind, r);
            const note = PatchGen.profile (kind).note;
            const program = join (dir, "p.bin"), events = join (dir, "p.txt");
            writeFileSync (program, Preset.toOatmeal ({ ...Preset.make ("p"), values: m, tables }));
            writeFileSync (events, `0 144 ${note} 100\n${2 * rate} 128 ${note} 0\n`);
            // (every value that isn't Init's, or isn't what the DSP starts with: its rack holds
            // Oatmeal's four, Init's is empty)
            const sets = Object.fromEntries ([...m].filter (([id, x]) => x !== init.get (id) || x !== defs.get (id).init));
            const [left, right] = render ({ program, events, frames: 2.5 * rate, rate, sets, out: join (dir, "p.f32") });
            // the loudest 300 ms, K-weighted (as the drawer's meter measures), with the patch's own
            // output gain
            const db = loudest ([kWeight (left, rate), kWeight (right, rate)], rate);
            if (db < -60) fail (`${kind} ${label} is silent (${db.toFixed (1)} dB): ${PatchGen.describe (m, note).map (([, t]) => t).join ("; ")}`);
            levels.push (db - PatchGen.targetDb);
        }
        return levels.sort ((a, b) => a - b);
    };
    const tame = levelsAt (wildAt (0.3), "at 0.3");
    const median = tame[tame.length >> 1];
    const within = tame.filter (d => Math.abs (d - median) < 6).length / tame.length;
    check (Math.abs (median) < 3, `patches at 0.3 come out near their level (median ${median.toFixed (1)} dB from it)`);
    check (within >= 0.85, `most of them within 6 dB of each other (${Math.round (100 * within)}%)`);
    // with the effects at their wildest (heavy distortion among them), few far louder: at most two
    // of the 70 more than 9 dB over, none more than 18. (The loudest is one draw: over seeds 31 ..
    // 42 it ranged from 6 to 17 dB before the noise types, the third loudest from 4 to 9, so a
    // new draw in the generator, which moves every patch after it, mustn't decide it: when the
    // noise types came, the loudest became a bell with AM and a resonator in each voice, and no
    // noise, at 12.8 dB.)
    const wild = levelsAt ({ ...wildAt (0.3), fx: 1 }, "with wild effects");
    const [third, , top] = wild.slice (-3);
    check (Math.abs (wild[wild.length >> 1]) < 3, `patches with wild effects come out near their level too (median ${wild[wild.length >> 1].toFixed (1)} dB from it)`);
    check (third < 9 && top < 18, `few of them much louder (the loudest ${top.toFixed (1)} dB over, the third ${third.toFixed (1)})`);
}
else
    console.log ("(no test host: tools/test/build.sh builds it; the levels weren't checked)");

done ("random patches ok");
