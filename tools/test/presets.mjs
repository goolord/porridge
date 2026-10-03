// Round-trip checks for the preset format (run `npm run res` first):
//   - every factory program survives Oatmeal -> Porridge JSON -> Oatmeal with identical
//     parameters, tables and name;
//   - the stored-state bank encoding reads back to the same presets;
//   - the factory bank a new instance starts with reads back, its first preset on its own
//     too, and bundle/factory-bank.json (from npm run build) is up to date;
//   - a preset missing parameters and tables reads back with their defaults;
//   - modulations, macro names and microtunings survive a round trip;
//   - Porridge's extra list values export as Oatmeal's nearest, and are reported;
//   - rack values and targets keep their numbers, and programs from before the slots load each
//     effect's copy into its slot (connections, shapes and impulse files too), two convolvers
//     as one with a warning, the key shifter as the Bode; a reorder moves what's in the slots.
//   - the noise's type, density and sample survive a round trip, and the types that aren't
//     white are reported for an Oatmeal export, which plays white noise.
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
import * as ValueList from "../../ui/ValueList.res.mjs";
import * as Impulse from "../../ui/Impulse.res.mjs";
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

// Init has the HQ saw while the waveforms' default stays Oatmeal's sine: an Init program goes
// through the stored bank (which leaves defaults out) and back with its saw, a program stored
// without waveforms reads back with sines, and Oatmeal programs keep their aliasing waves
{
    const hqSaw = ParamDefs.choiceValue ("O1_Waveform", "Saw");
    const wave = p => [p.values.get ("O1_Waveform"), p.values.get ("O2_Waveform")].join ();
    if (hqSaw !== 6 || ParamDefs.choiceValue ("O1_Waveform", "Oat saw") !== 1) fail ("the waveforms' values moved");
    const bank = Preset.fillBank ([Preset.make ("plain")]);
    const back = Preset.decodeBank (Preset.encodeBank (bank));
    if (wave (bank[1]) !== "6,6" || wave (Preset.init ("x")) !== "6,6") fail ("Init's waveforms: " + wave (bank[1]));
    if (! back || ! back.every ((p, i) => sameValues (bank[i].values, p.values))) fail ("the stored bank changes Init's waveforms");
    if (wave (back[0]) !== "0,0" || Preset.defaultValues ().get ("O1_Waveform") !== 0) fail ("the waveforms' default changed");
    if (presets.some (p => p.values.get ("O1_Waveform") >= 6 || p.values.get ("O2_Waveform") >= 6)) fail ("an Oatmeal program has an HQ wave");
    const v = Bank.programValues (Preset.toOatmeal (Preset.init ("x")));
    if (v.get ("O1_Waveform") !== 1 || v.get ("O2_Waveform") !== 1) fail ("Init's HQ saws export as " + v.get ("O1_Waveform"));
    const menu = ValueList.menu ("Waveform", 9, 0).map (({ value, heading }) => (heading ? `[${heading}] ` : "") + value).join ();
    if (menu !== "0,6,7,8,4,5,[Oat (aliasing)] 1,2,3") fail ("the waveform menu: " + menu);
}

// The slots (October 2026): rack values keep their numbers, the copies' ones and the old fourth
// copies' naming instances now, and the instances added after them; only the key shifter's and
// the second convolver's are retired. The copies' and Porridge's kinds' firsts' targets keep their
// places, retired, and the slots' knobs' come after them.
{
    const value = (kind, n) => PorridgeParams.entryValue (kind, n);
    const retiredValues = PorridgeParams.rackEntries.map ((_, v) => v).filter (v => PorridgeParams.retiredEntry (v) !== undefined);
    const names = retiredValues.map (v => PorridgeParams.rackNames[v]).join ();
    if (names !== "Convolve 2 (retired),Shifter (retired),Shifter 2 (retired)") fail ("retired rack values: " + names);
    if (value ("delay", 4) !== 10 || value ("distortion", 5) !== 20 || value ("flanger", 4) !== 24 || PorridgeParams.rackEntries.length !== 125) fail ("the old fourth copies aren't instances");
    for (const k of PorridgeParams.rackKinds)
        if (k.runsIn !== "LaneOnly" && PorridgeParams.instanceNumbers (k).some (n => value (k.key, n) < 0)) fail (`${k.key} lacks an instance`);
    if (PorridgeParams.instanceNumbers (PorridgeParams.rackKinds.find (k => k.key === "convolve")).length !== 1) fail ("more than one convolver");
    // (their indices before the slots)
    const targets = { C4_Mix: 65, D4_Wet: 68, Sat5_Pregain: 75, D4_Rotation: 144, Ff4_Track: 449, Fl4_Track: 477, D2_Wet: 66, Fl_Rate: 77 };
    for (const [key, i] of Object.entries (targets))
        if (ModMatrix.targetIndex (key) !== i || ModMatrix.targets[i].law !== "Retired") fail (`target ${key} isn't retired at ${i}`);
    for (const key of ["C_Mix", "D_Wet", "R_Wet", "EQ_3_Amp", "Sat_Pregain", "Sat_Mix", "O1_Morph"])
        if (ModMatrix.targets[ModMatrix.targetIndex (key)].law.TAG !== "Knob") fail (`target ${key} doesn't move its knob`);
    if (ModMatrix.firstSlotTarget !== 491 || ModMatrix.targets.length !== 491 + 8 * 28 + 4 * 21) fail (`${ModMatrix.targets.length} targets`);
    if (PorridgeParams.rackKnobs !== 28 || PorridgeParams.laneKnobs !== 21) fail ("the slots' knobs");
    if (ParamDefs.makeDefs ().some (d => PorridgeParams.isLegacyId (d.id))) fail ("a copy keeps its parameters");
}

// a program from before the slots loads each effect in a slot into it: its parameters (its
// shape's points too) and connections; copies in no slot, and their connections, go; two
// convolvers keep the first; the key shifter becomes the Bode
{
    const value = (kind, n) => PorridgeParams.entryValue (kind, n);
    const named = name => PorridgeParams.rackNames.indexOf (name);
    const load = (params, modulations = [], impulses) =>
    {
        const doc = { porridge: "preset", version: 1, name: "old", params, modulations, ...(impulses ? { impulses } : {}) };
        const r = Preset.parseJson (JSON.stringify (doc))._0;
        return { p: r.presets[0], warnings: r.warnings, get: id => r.presets[0].values.get (id) };
    };
    const knob = (g, first) =>
    {
        const k = PorridgeParams.rackKinds.find (k => k.params.some (([p]) => p === first));
        return ModMatrix.slotTarget (g, PorridgeParams.knobIndex (k, first) + 1);
    };
    const f = Math.fround;

    // a delay copy in slot 1: its values and connection there, a copy outside the rack gone
    let r = load ({ FX_Rack_1: value ("delay", 2), D2_Wet: 0.8, D2_LengthL: 0.3, D3_Wet: 0.1, FX_Rack_2: value ("flanger", 1), Fl_Rate: 0.7 },
                  [{ source: "lfo1", target: "D2_Wet", amount: 0.5 }, { source: "lfo2", target: "D3_Wet", amount: 0.2 },
                   { source: "macro1", target: "Fl_Mix", amount: 0.3 }]);
    if (r.get ("FX_Rack_1") !== value ("delay", 2) || r.get ("D_Wet@1") !== f (0.8) || r.get ("D_LengthL@1") !== f (0.3)
        || r.get ("FX_Rack_2") !== value ("flanger", 1) || r.get ("Fl_Rate@2") !== f (0.7) || r.warnings.length)
        fail (`a delay copy loads as rack ${r.get ("FX_Rack_1")}, wet ${r.get ("D_Wet@1")}: ${r.warnings}`);
    if (r.get ("Mod1_Target") !== knob (0, "D_Wet") || r.get ("Mod2_Target") !== knob (1, "Fl_Mix") || r.get ("Mod3_Source") !== 0)
        fail (`the copies' connections: ${r.get ("Mod1_Target")}, ${r.get ("Mod2_Target")}`);
    const json = new TextDecoder ().decode (Preset.writePreset (r.p));
    const doc = JSON.parse (json);
    if (/"(D[23]|Fl)_[A-Za-z]+"/.test (json) || doc.params["D_Wet@1"] !== 0.8 || "Fl_Rate@1" in doc.params || "D_Wet@2" in doc.params)
        fail ("the slots' parameters are written as " + Object.keys (doc.params).filter (k => k.includes ("@")).join ());
    if (doc.modulations.map (m => m.target).join () !== "D_Wet@1,Fl_Mix@2") fail ("the slots' connections are written as " + json);
    const again = Preset.parseJson (json)._0.presets[0];
    if (! sameValues (r.p.values, again.values)) fail ("a program with slots doesn't read back");

    // the old fourth copies are instances again; a distortion in the lane keeps its shape
    r = load ({ FX_Rack_1: named ("Delay 4"), D4_Wet: 0.8, VL_1: value ("filter", 2), VL_2: named ("Distortion 5"), VL_FilterAt: 1, VL_AmpAt: 2,
                Ff2_Cutoff: 0.4, Sat5_Type: 3, Sat5_X2: 0.25 });
    if (r.get ("FX_Rack_1") !== value ("delay", 4) || r.get ("D_Wet@1") !== f (0.8) || r.get ("VL_1") !== PorridgeParams.laneValue (FxRack.spec ("filter"))
        || r.get ("Ff_Cutoff@L1") !== f (0.4) || r.get ("VL_2") !== PorridgeParams.laneValue (FxRack.spec ("distortion"))
        || r.get ("Sat_Type@L2") !== 3 || r.get ("Sat_X2@L2") !== 0.25 || r.get ("VL_AmpAt") !== 2 || r.warnings.length)
        fail (`delay 4 and distortion 5: rack ${r.get ("FX_Rack_1")}, lane ${r.get ("VL_2")}, type ${r.get ("Sat_Type@L2")}: ${r.warnings}`);

    // two convolvers: the first stays, with its file, the second goes, its file too; the noise's
    // sample keeps its place
    const imp = name => ({ name, rate: 48000, left: Bank.floatsToBase64 (new Float32Array ([1, 0.5, 0.25])) });
    r = load ({ FX_Rack_1: value ("convolve", 1), FX_Rack_2: named ("Convolve 2 (retired)"), Cv_Mix: 0.6, Cv2_Mix: 0.2 }, [],
              [imp ("a.wav"), imp ("b.wav"), imp ("n.wav")]);
    if (r.get ("FX_Rack_1") !== value ("convolve", 1) || r.get ("FX_Rack_2") !== 0 || r.get ("Cv_Mix@1") !== f (0.6)
        || r.warnings.length !== 1 || ! r.warnings[0].includes ("two convolvers")
        || r.p.impulses[0]?.name !== "a.wav" || r.p.impulses[1] !== undefined || r.p.impulses[2]?.name !== "n.wav")
        fail (`two convolvers: rack ${r.get ("FX_Rack_2")}, files ${r.p.impulses.map (x => x?.name)}: ${r.warnings}`);
    // the second alone is the convolver
    r = load ({ FX_Rack_3: named ("Convolve 2 (retired)"), Cv2_Mix: 0.2 }, [], [null, imp ("b.wav")]);
    if (r.get ("FX_Rack_3") !== value ("convolve", 1) || r.get ("Cv_Mix@3") !== f (0.2) || r.p.impulses[0]?.name !== "b.wav" || r.warnings.length)
        fail (`the second convolver alone: rack ${r.get ("FX_Rack_3")}, file ${r.p.impulses[0]?.name}: ${r.warnings}`);

    // the stored bank says what it couldn't keep too
    const stored = Preset.decodeNamedBank (JSON.stringify ({ porridge: "bank", version: 1, name: "b", presets: [
        { name: "two", params: { FX_Rack_1: value ("convolve", 1), FX_Rack_2: named ("Convolve 2 (retired)") } } ] }));
    if (! stored || stored[2].length !== 1 || stored[1][0].values.get ("FX_Rack_2") !== 0) fail ("the stored bank's warnings");

    // the key shifter (retired: the frequency shifter took it in) loads as the lane's Bode: its
    // ratio of the note, its offset (±1 kHz) as the shift (±5 kHz) at cbrt (1/5) of its turn, its
    // mode and mix; its connections follow it, an offset's amount scaled as its knob
    const k = Math.cbrt (0.2), near = (a, b) => Math.abs (a - b) < 1e-6;
    r = load ({ VL_1: named ("Shifter (retired)"), VL_AmpAt: 1, Sh_On: 1, Sh_Ratio: 0.3, Sh_Hz: -0.5, Sh_Mode: 2, Sh_Mix: 0.7 },
             [{ source: "lfo1", target: "Sh_Hz", amount: 0.2 }, { source: "wander", target: "Sh_Ratio", amount: 0.1 },
              { source: "lfo2", target: "Sh2_Mix", amount: 0.3 }]);
    if (r.get ("VL_1") !== PorridgeParams.laneValue (FxRack.spec ("bode")) || r.get ("VL_AmpAt") !== 1 || r.get ("Bd_On@L1") !== 1
        || r.get ("Bd_Ratio@L1") !== f (0.3) || ! near (r.get ("Bd_Shift@L1"), -0.5 * k) || r.get ("Bd_Mode@L1") !== 2
        || r.get ("Bd_Mix@L1") !== f (0.7) || r.warnings.length)
        fail (`the shifter loads as lane ${r.get ("VL_1")}, ratio ${r.get ("Bd_Ratio@L1")}, shift ${r.get ("Bd_Shift@L1")}: ${r.warnings}`);
    if (r.get ("Mod1_Target") !== knob (8, "Bd_Shift") || ! near (r.get ("Mod1_Amount"), 0.2 * k)
        || r.get ("Mod2_Target") !== knob (8, "Bd_Ratio") || r.get ("Mod3_Source") !== 0)
        fail ("the shifter's connections don't follow it (or a dead one stays)");
    // its defaults (ratio 0.5 of the note)
    r = load ({ VL_1: named ("Shifter (retired)"), Sh_On: 1 });
    if (r.get ("Bd_Ratio@L1") !== f (0.5) || r.get ("Bd_Shift@L1") !== 0 || r.get ("Bd_Mix@L1") !== f (0.5)) fail ("the shifter's defaults");
    // an offset its connections took past ±1 kHz, where the knob ended, goes further now: said
    r = load ({ VL_1: named ("Shifter (retired)"), Sh_On: 1, Sh_Hz: 0.4 }, [{ source: "lfo1", target: "Sh_Hz", amount: 0.4 }]);
    if (r.warnings.length !== 1 || ! r.warnings[0].includes ("±1 kHz")) fail (`a shifter's offset modulated past its end: ${r.warnings}`);
}

// reordering the rack moves each effect's parameters, instance and connections with it; one taken
// out takes its connections; one added gets its kind's defaults and a free instance
{
    const p = Preset.make ("order");
    const vals = new Map (p.values);
    const get = id => vals.get (id) ?? 0;
    const apply = list => list.forEach (([id, x]) => vals.set (id, x));
    apply ([["FX_Rack_1", PorridgeParams.entryValue ("delay", 5)], ["D_Wet@1", 0.8], ["FX_Rack_2", PorridgeParams.entryValue ("flanger", 3)],
            ["Fl_Rate@2", 0.25], ["Mod1_Source", 1], ["Mod1_Target", ModMatrix.slotTarget (0, 15)], ["Mod1_Amount", 0.5]]);
    const [delay, flanger] = FxRack.read (get);
    apply (FxRack.values (get, [flanger, delay]));
    if (get ("FX_Rack_1") !== PorridgeParams.entryValue ("flanger", 3) || get ("FX_Rack_2") !== PorridgeParams.entryValue ("delay", 5)
        || get ("Fl_Rate@1") !== 0.25 || get ("D_Wet@2") !== 0.8 || get ("Mod1_Target") !== ModMatrix.slotTarget (1, 15))
        fail (`a reorder: ${get ("FX_Rack_1")} ${get ("FX_Rack_2")}, wet ${get ("D_Wet@2")}, target ${get ("Mod1_Target")}`);
    const fresh = FxRack.free (FxRack.read (get), undefined, undefined, "flanger");
    apply (FxRack.values (get, [...FxRack.read (get), fresh]));
    if (get ("FX_Rack_3") !== PorridgeParams.entryValue ("flanger", 1) || get ("Fl_Rate@3") !== Preset.defaultValues ().get ("Fl_Rate@3"))
        fail (`a second flanger: ${get ("FX_Rack_3")}`);
    apply (FxRack.values (get, FxRack.read (get).filter (e => e.kind !== "delay")));
    if (get ("Mod1_Source") !== 0 || get ("FX_Rack_3") !== 0) fail ("a removed delay's connection stays");
    // (one convolver)
    apply (FxRack.values (get, [FxRack.free ([], undefined, undefined, "convolve")]));
    if (FxRack.free (FxRack.read (get), undefined, undefined, "convolve") !== undefined || ! FxRack.atLimit (FxRack.read (get)).includes ("convolve"))
        fail ("a second convolver can be added");
}

// the noise's type and density, and its sample (Impulse's noise slot, beside the convolvers'
// files), through a preset file and the stored bank; a file from before the noise's sample (two
// impulses) reads with none; an Oatmeal export plays white noise and says so, though not for a
// density of white noise; the types keep their values; a sample from a file is made mono, loops
// without a jump and is as loud as the white noise
{
    if (PorridgeParams.noiseTypes.join () !== "white,pink,brown,blue,violet,crackle,digital,metallic,sample") fail ("the noise types moved");
    const n = 6000, rate = 44100;
    const audio = { samples: Float32Array.from ({ length: n }, (_, i) => 0.3 * Math.sin (i * 0.05) + 0.1 * Math.sin (i * 0.31)), sampleRate: rate,
                    frameSize: undefined, sides: undefined };
    const imp = Impulse.noiseFromAudio ("hiss.wav", audio);
    if (! imp || imp.right !== undefined || imp.rate !== rate) fail ("the noise's sample from a file");
    else
    {
        const d = imp.left, m = d.length;
        const rms = Math.sqrt (d.reduce ((a, v) => a + v * v, 0) / m);
        const step = Math.max (...Array.from ({ length: m - 1 }, (_, i) => Math.abs (d[i + 1] - d[i])));
        if (Math.abs (rms - 0.57735) > 1e-3) fail (`the noise's sample's RMS ${rms}`);
        if (Math.abs (d[0] - d[m - 1]) > 2 * step) fail (`the noise's sample jumps ${Math.abs (d[0] - d[m - 1])} at its loop (steps ${step})`);
    }
    const p = Preset.make ("noisy");
    p.values.set ("N_Type", 7); p.values.set ("N_Density", 0.75); p.values.set ("N_Amp", 0.3);
    const withSample = { ...p, impulses: [undefined, undefined, imp] };
    const back = Preset.parseFile (Preset.writePreset (withSample))._0.presets[0];
    if (back.values.get ("N_Type") !== 7 || back.values.get ("N_Density") !== 0.75) fail ("the noise's type and density in a preset file");
    const sample = back.impulses[Impulse.noiseSlot];
    if (! sample || sample.name !== "hiss.wav" || sample.rate !== rate || sample.left.length !== imp.left.length
        || ! sample.left.every ((v, i) => v === imp.left[i]) || back.impulses[0] !== undefined)
        fail ("the noise's sample in a preset file");
    const stored = Preset.decodeBank (Preset.encodeBank (Preset.fillBank ([withSample])));
    if (! stored || stored[0].values.get ("N_Type") !== 7 || stored[0].impulses[Impulse.noiseSlot]?.left.length !== imp.left.length)
        fail ("the noise's sample in the stored bank");
    const older = Impulse.listFromJson (JSON.parse (JSON.stringify ([Impulse.toJson (imp), null])));
    if (older.length !== Impulse.slots || older[0]?.name !== "hiss.wav" || older[Impulse.noiseSlot] !== undefined) fail ("two impulses read as the convolvers'");
    const lost = Preset.porridgeOnly (p);
    if (! lost.some (l => l.includes ("noise types"))) fail ("porridgeOnly misses the noise type: " + lost);
    if (Bank.programValues (Preset.toOatmeal (p)).has ("N_Type")) fail ("the noise type goes into an Oatmeal program");
    const density = Preset.make ("dense");
    density.values.set ("N_Density", 0.75);
    if (Preset.porridgeOnly (density).length !== 0) fail ("a density of white noise is reported: " + Preset.porridgeOnly (density));
}

done (`ok: ${programs.length} programs round-trip`);
