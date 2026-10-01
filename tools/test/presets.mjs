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

console.log (failures === 0 ? `ok: ${programs.length} programs round-trip` : `${failures} failures`);
process.exit (failures === 0 ? 0 : 1);
