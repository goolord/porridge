// Round-trip checks for the preset format (run `npm run res` first):
//   - every factory program survives Oatmeal -> Porridge JSON -> Oatmeal with identical
//     parameters, tables and name;
//   - the stored-state bank encoding reads back to the same presets;
//   - the factory bank a new instance starts with reads back, its first preset on its own
//     too, and bundle/factory-bank.json (from npm run build) is up to date;
//   - a preset missing parameters and tables reads back with their defaults;
//   - modulations, macro names and microtunings survive a round trip;
//   - Porridge's extra list values export as Oatmeal's nearest, and are reported;
//   - the retired fourth copies keep their numbers, and programs that used one load it onto a
//     free copy, or without it and a warning.
//
// run: node tools/test/presets.mjs

import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as Preset from "../../ui/Preset.res.mjs";
import * as Bank from "../../ui/Bank.res.mjs";
import * as OatmealFormat from "../../ui/oatmeal/OatmealFormat.res.mjs";
import * as Scala from "../../ui/Scala.res.mjs";
import * as FxRack from "../../ui/FxRack.res.mjs";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as ParamDefs from "../../ui/ParamDefs.res.mjs";
import { root, checker } from "./lib.mjs";

const { fail, done } = checker ();

const factoryFile = new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat")));
const factory = OatmealFormat.parseFile (factoryFile);
if (factory.TAG !== "Ok") throw new Error ("factory bank didn't parse");
const programs = factory._0.programs;

const sameValues = (a, b) => [...a].every (([id, x]) => b.get (id) === x);
const sameBytes = (a, b, from, to) => { for (let i = from; i < to; ++i) if (a[i] !== b[i]) return false; return true; };

const presets = programs.map (p => Preset.fromOatmeal (p.bytes));
const json = new TextDecoder().decode (Preset.writeBank (presets, undefined));
const parsed = Preset.parseFile (new TextEncoder().encode (json));
if (parsed.TAG !== "Ok" || parsed._0.presets.length !== programs.length) fail ("bank didn't read back");

programs.forEach ((orig, i) =>
{
    const back = Preset.toOatmeal (parsed._0.presets[i]);
    const name = OatmealFormat.getName (orig.bytes);
    if (! sameValues (Bank.programValues (orig.bytes), Bank.programValues (back))) fail (`${i} ${name}: parameters differ`);
    for (const t of OatmealFormat.allTables)
    {
        const off = OatmealFormat.tableOffset (t), len = 4 * OatmealFormat.tableLength (t);
        if (! sameBytes (orig.bytes, back, off, off + len)) fail (`${i} ${name}: table ${t} differs`);
    }
    if (OatmealFormat.getName (back) !== name) fail (`${i}: name "${OatmealFormat.getName (back)}" != "${name}"`);
});

// stored-state encoding, and the legacy base64 Oatmeal bank
const decoded = Preset.decodeBank (Preset.encodeBank (presets));
if (! decoded || ! decoded.every ((p, i) => sameValues (presets[i].values, p.values))) fail ("stored bank differs");
const legacy = Preset.decodeBank (Bank.encodeBank (programs.map (p => p.bytes)));
if (! legacy || ! legacy.every ((p, i) => sameValues (presets[i].values, p.values))) fail ("legacy stored bank differs");

// the factory bank the worker installs, which it decodes only the first preset of
{
    const bank = Preset.factoryBank (factoryFile);
    const encoded = Preset.encodeBank (bank);
    const all = Preset.decodeBank (encoded);
    const first = Preset.decodeFirst (encoded);
    if (bank.length !== OatmealFormat.bankPrograms) fail ("the factory bank isn't a full bank");
    if (! all || ! all.every ((p, i) => sameValues (bank[i].values, p.values))) fail ("the factory bank differs");
    if (! first || ! all || ! sameValues (all[0].values, first.values)
         || Bank.encodeShapes (all[0].tables) !== Bank.encodeShapes (first.tables))
        fail ("decodeFirst differs from decodeBank");
    let file = null;
    try { file = readFileSync (join (root, "bundle", "factory-bank.json"), "utf8"); } catch {}
    if (file !== null && file !== encoded) fail ("bundle/factory-bank.json is out of date (npm run build)");
}

// values older versions of Oatmeal wrote outside a knob's range (an F envspeed of 8.78, in the
// Ann banks) are kept, as Oatmeal plays them, through a Porridge file and back
{
    const bytes = OatmealFormat.makeDefaultProgram ("wide");
    new DataView (bytes.buffer, bytes.byteOffset).setFloat32 (8452, 8.777605, true);   // F envspeed
    const want = Math.fround (8.777605);
    const p = Preset.fromOatmeal (bytes);
    const back = Preset.parseFile (Preset.writePreset (p))._0.presets[0];
    if (p.values.get ("F_Speed") !== want || back.values.get ("F_Speed") !== want
        || Bank.programValues (Preset.toOatmeal (back)).get ("F_Speed") !== want)
        fail (`an F envspeed of 8.78 reads back as ${back.values.get ("F_Speed")}`);
}

// missing fields take their defaults
const sparse = Preset.parseFile (new TextEncoder().encode (`{"porridge":"preset","version":1,"name":"x","params":{"Cutoff":0.25}}`));
if (sparse.TAG !== "Ok") fail ("sparse preset didn't parse");
else
{
    const p = sparse._0.presets[0];
    if (p.values.get ("Cutoff") !== 0.25) fail ("sparse: Cutoff");
    if (! [...Preset.defaultValues()].every (([id, x]) => id === "Cutoff" || p.values.get (id) === x)) fail ("sparse: defaults");
}

// Init's rack is empty, and Oatmeal programs leave their idle effects out of it (but keep their
// settings, and export as they were)
{
    const init = Preset.make ("Init");
    if (! [1, 2, 3, 4, 5, 6, 7, 8].every (k => init.values.get ("FX_Rack_" + k) === 0)) fail ("Init's rack isn't empty");
    if (! programs.every ((p, i) =>
    {
        const preset = Preset.fromOatmeal (p.bytes);
        const rack = FxRack.read (id => preset.values.get (id) ?? 0);
        return rack.every (e => ! FxRack.isFirst (e) || FxRack.isOn (e, id => preset.values.get (id) ?? 0));
    })) fail ("an Oatmeal program keeps an idle effect in the rack");
}

// modulations are written by key and fill the matrix slots in order
{
    const p = Preset.make ("mods");
    const set = (id, x) => p.values.set (id, x);
    set ("Mod3_Source", 1); set ("Mod3_Target", 20); set ("Mod3_Amount", 0.3); set ("Mod3_Via", 10);
    set ("Mod7_Source", 15); set ("Mod7_Target", 3); set ("Mod7_Amount", -1);
    set ("Macro_1", 0.5);
    const text = new TextDecoder().decode (Preset.writePreset ({ ...p, meta: { ...p.meta, macroNames: ["tone", "", "", ""] } }));
    const doc = JSON.parse (text);
    if (JSON.stringify (doc.modulations) !== JSON.stringify ([
            { source: "lfo1", target: "Cutoff", amount: 0.3, via: "modWheel" },
            { source: "macro1", target: "volume", amount: -1 } ]))
        fail ("modulations written as " + JSON.stringify (doc.modulations));
    if ("Mod3_Source" in doc.params) fail ("slot parameters written as parameters");
    const back = Preset.parseFile (new TextEncoder().encode (text))._0.presets[0];
    const want = { Mod1_Source: 1, Mod1_Target: 20, Mod1_Amount: Math.fround (0.3), Mod1_Via: 10,
                   Mod2_Source: 15, Mod2_Target: 3, Mod2_Amount: -1, Mod2_Via: 0, Mod3_Source: 0, Macro_1: 0.5 };
    for (const [id, x] of Object.entries (want))
        if (back.values.get (id) !== x) fail (`modulations: ${id} = ${back.values.get (id)}, want ${x}`);
    if (back.meta.macroNames[0] !== "tone") fail ("macro names");
    if (Preset.porridgeOnly (back).join () !== "modulations,macros") fail ("porridgeOnly: " + Preset.porridgeOnly (back));
    if (Preset.porridgeOnly (presets[0]).length !== 0) fail ("factory program reported as Porridge-only");
}

// list values Porridge added become Oatmeal's nearest on export, and are reported
{
    const p = Preset.make ("extended");
    [1, 2, 3, 4].forEach (k => p.values.set ("FX_Rack_" + k, k));   // Oatmeal's four, in FX_Order's order
    p.values.set ("O1_Waveform", 7); p.values.set ("Filter", 21); p.values.set ("OscMix", 5); p.values.set ("FX_Order", 3);
    const v = Bank.programValues (Preset.toOatmeal (p));
    if (v.get ("O1_Waveform") !== 2 || v.get ("Filter") !== 9 || v.get ("OscMix") !== 0)
        fail (`extended values exported as ${v.get ("O1_Waveform")}, ${v.get ("Filter")}, ${v.get ("OscMix")}`);
    const lost = Preset.porridgeOnly (p).join ();
    for (const what of ["HQ waveforms", "osc mix", "filter types", "effects order"])
        if (! lost.includes (what)) fail ("porridgeOnly misses " + what + ": " + lost);
}

// a microtuning keeps its Scala text, and the Scala table follows the files
{
    const scl = "! 19edo.scl\n19 equal\n 19\n" + Array.from ({ length: 19 }, (_, i) => ((i + 1) * 1200 / 19).toFixed (6)).join ("\n") + "\n";
    const kbm = "! 19-EDO on the white keys\n12\n0\n127\n60\n69\n432.0\n19\n0\nx\n3\nx\n6\n8\nx\n11\nx\n14\nx\n17\n";
    const p = { ...Preset.make ("tuned"), tuning: { scl, kbm } };
    const back = Preset.parseFile (Preset.writePreset (p))._0.presets[0];
    if (back.tuning?.scl !== scl || back.tuning?.kbm !== kbm) fail ("tuning text");
    if (! Preset.porridgeOnly (back).includes ("the microtuning")) fail ("porridgeOnly: tuning");
    const t = Scala.table ({ scl, kbm })._0.semitones;
    const near = (a, b) => Math.abs (a - b) < 1e-6;
    if (! near (t[69], 12 * Math.log2 (432 / 440))) fail ("tuning: reference key " + t[69]);
    if (! near (t[67] - t[60], 11 * 12 / 19)) fail ("tuning: G is degree 11");
    if (! near (t[72] - t[60], 12)) fail ("tuning: the mapping repeats an octave up");
    if (t[61] > -1000) fail ("tuning: C# is unmapped");
    if (Preset.make ("plain").tuning !== undefined) fail ("Init has a tuning");
}

// The rack's fourth copies (the fifth distortion) are retired: their rack values and modulation
// targets keep their numbers and run or move nothing, and no menu offers them
{
    const retiredValues = [7, 10, 13, 16, 20, 24, 28, 32, 36, 42, 46, 50, 54, 58];
    if (PorridgeParams.rackEntries.length !== 65) fail (`the rack has ${PorridgeParams.rackEntries.length} values, not 65`);
    PorridgeParams.rackEntries.forEach ((e, v) =>
    {
        const retired = PorridgeParams.retiredEntry (v) !== undefined;
        if (retired !== retiredValues.includes (v)) fail (`rack value ${v} (${PorridgeParams.rackNames[v]}) retired: ${retired}`);
        if (retired && (e !== undefined || FxRack.ofValue (v) !== undefined)) fail (`retired rack value ${v} still runs`);
    });
    if (FxRack.all.some (e => e.copy > (e.kind === "distortion" ? 4 : 3))) fail ("the add menus offer a fourth copy");
    // (their indices before they were retired)
    const targets = { C4_Mix: 65, D4_Wet: 68, Sat5_Pregain: 75, D4_Rotation: 144, Ff4_Track: 449, Fl4_Track: 477 };
    for (const [key, i] of Object.entries (targets))
        if (ModMatrix.targetIndex (key) !== i || ModMatrix.targets[i].law !== "Retired") fail (`target ${key} isn't retired at ${i}`);
    if (ModMatrix.targets.length !== 484) fail (`${ModMatrix.targets.length} targets, not 484`);
    if (! ModMatrix.targets.every (t => (t.law === "Retired") === PorridgeParams.isRetiredId (t.key))) fail ("a retired copy's target moves something");
    if (ParamDefs.makeDefs ().some (d => PorridgeParams.isRetiredId (d.id))) fail ("a retired copy keeps its parameters");
}

// a program that used a fourth copy loads it onto a free copy of its kind, with its parameters,
// its connections and its place, or without it and a warning
{
    const value = (kind, copy) => FxRack.value ({ kind, copy });
    const retired = name => PorridgeParams.rackNames.indexOf (`${name} (retired)`);
    const load = (params, modulations = []) =>
    {
        const doc = { porridge: "preset", version: 1, name: "old", params, modulations };
        const r = Preset.parseJson (JSON.stringify (doc))._0;
        return { p: r.presets[0], warnings: r.warnings, get: id => r.presets[0].values.get (id) };
    };
    const target = key => ModMatrix.targetIndex (key);

    // onto delay 2, whose old values go; the connection follows it
    let r = load ({ FX_Rack_1: retired ("Delay 4"), D4_Wet: 0.8, D4_LengthL: 0.3, D2_Wet: 0.1, D2_Rotation: 0.6 },
                  [{ source: "lfo1", target: "D4_Wet", amount: 0.5 }]);
    if (r.get ("FX_Rack_1") !== value ("delay", 2) || r.get ("D2_Wet") !== Math.fround (0.8) || r.get ("D2_LengthL") !== Math.fround (0.3)
        || r.get ("D2_Rotation") !== Preset.defaultValues ().get ("D2_Rotation") || r.warnings.length)
        fail (`delay 4 loads as rack ${r.get ("FX_Rack_1")}, wet ${r.get ("D2_Wet")}: ${r.warnings}`);
    if (r.get ("Mod1_Target") !== target ("D2_Wet") || r.get ("Mod1_Source") !== 1) fail ("delay 4's connection doesn't follow it");
    const json = new TextDecoder ().decode (Preset.writePreset (r.p));
    if (/D4_/.test (json)) fail ("a retired copy's parameters are written");

    // with delay 2 in the rack and delay 3 modulated, it has nowhere to go
    r = load ({ FX_Rack_1: value ("delay", 2), FX_Rack_2: retired ("Delay 4"), FX_Rack_3: value ("air", 1) },
              [{ source: "lfo1", target: "D4_Wet", amount: 0.5 }, { source: "lfo2", target: "D3_Wet", amount: 0.2 }]);
    if (r.get ("FX_Rack_2") !== 0 || r.get ("FX_Rack_3") !== value ("air", 1) || r.warnings.length !== 1 || ! r.warnings[0].includes ("Delay 4"))
        fail (`delay 4 with no free delay: rack ${r.get ("FX_Rack_2")}, ${r.warnings}`);
    if (r.get ("Mod1_Target") !== target ("D3_Wet") || r.get ("Mod2_Source") !== 0) fail ("delay 4's connection outlives it");

    // the fifth distortion, in the voice lane after the filter, becomes the second
    r = load ({ VL_1: value ("filter", 2), VL_2: retired ("Distortion 5"), VL_FilterAt: 1, VL_AmpAt: 2, Sat5_Type: 3, Sat5_X2: 0.25 });
    if (r.get ("VL_2") !== value ("distortion", 2) || r.get ("Sat2_Type") !== 3 || r.get ("Sat2_X2") !== 0.25 || r.get ("VL_AmpAt") !== 2)
        fail (`distortion 5 loads as lane ${r.get ("VL_2")}, type ${r.get ("Sat2_Type")}`);

    // three flangers in use: the fourth leaves the lane, which closes up around the filter and amp
    r = load ({ VL_1: value ("flanger", 1), VL_2: retired ("Flanger 4"), VL_3: value ("flanger", 2), VL_FilterAt: 2, VL_AmpAt: 3,
                FX_Rack_1: value ("flanger", 3) });
    const lane = [1, 2, 3, 4].map (k => r.get ("VL_" + k));
    if (lane.join () !== [value ("flanger", 1), value ("flanger", 2), 0, 0].join () || r.get ("VL_FilterAt") !== 1 || r.get ("VL_AmpAt") !== 2
        || r.warnings.length !== 1)
        fail (`flanger 4 left out of the lane: ${lane}, filter at ${r.get ("VL_FilterAt")}, amp at ${r.get ("VL_AmpAt")}`);

    // a connection to a fourth copy that no slot held moved nothing, and goes without a word
    r = load ({}, [{ source: "lfo1", target: "Am4_Mix", amount: 0.5 }, { source: "lfo2", target: "Cutoff", amount: 0.2 }]);
    if (r.get ("Mod1_Target") !== target ("Cutoff") || r.get ("Mod2_Source") !== 0 || r.warnings.length) fail ("a dead connection to a retired copy stays");

    // the stored bank says what it couldn't keep too
    const stored = Preset.decodeNamedBank (JSON.stringify ({ porridge: "bank", version: 1, name: "b", presets: [
        { name: "full", params: { FX_Rack_1: value ("air", 1), FX_Rack_2: value ("air", 2), FX_Rack_3: value ("air", 3), FX_Rack_4: retired ("Air 4") } } ] }));
    if (! stored || stored[2].length !== 1 || stored[1][0].values.get ("FX_Rack_4") !== 0) fail ("the stored bank's warnings");
}

done (`ok: ${programs.length} programs round-trip`);
