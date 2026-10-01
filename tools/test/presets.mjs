// Round-trip checks for the preset format (run `npm run res` first):
//   - every factory program survives Oatmeal -> Porridge JSON -> Oatmeal with identical
//     parameters, tables and name;
//   - the stored-state bank encoding reads back to the same presets;
//   - a preset missing parameters and tables reads back with their defaults.
//
// run: node tools/test/presets.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../../ui/Preset.res.mjs";
import * as Bank from "../../ui/Bank.res.mjs";
import * as OatmealFormat from "../../ui/oatmeal/OatmealFormat.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..", "..");
let failures = 0;
const fail = msg => { console.log ("FAIL " + msg); ++failures; };

const factory = OatmealFormat.parseFile (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
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

// missing fields take their defaults
const sparse = Preset.parseFile (new TextEncoder().encode (`{"porridge":"preset","version":1,"name":"x","params":{"Cutoff":0.25}}`));
const init = Preset.make ("Init");
if (sparse.TAG !== "Ok") fail ("sparse preset didn't parse");
else
{
    const p = sparse._0.presets[0];
    if (p.values.get ("Cutoff") !== 0.25) fail ("sparse: Cutoff");
    if (! [...init.values].every (([id, x]) => id === "Cutoff" || p.values.get (id) === x)) fail ("sparse: defaults");
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

console.log (failures === 0 ? `ok: ${programs.length} programs round-trip` : `${failures} failures`);
process.exit (failures === 0 ? 0 : 1);
