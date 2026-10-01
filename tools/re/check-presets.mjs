// Parses every Oatmeal program/bank file below a folder with Porridge's loader and reports
// what it found. Read-only.
//
//   npm run res && node tools/re/check-presets.mjs "F:/VST32/oatmeal banks"

import { readFileSync, readdirSync } from "node:fs";
import { join, basename } from "node:path";
import { parseFile } from "../../ui/oatmeal/OatmealFormat.res.mjs";

const root = process.argv[2];
if (! root) { console.log ("usage: node tools/re/check-presets.mjs <folder>"); process.exit (2); }

const files = readdirSync (root, { recursive: true }).map (n => join (root, n));

let ok = 0, failed = 0, programs = 0;
const versions = new Map();
for (const f of files.filter (f => /\.(omp|omb|fxp|fxb|dat)$/i.test (f)))
{
    // parseFile returns a ReScript result: { TAG: "Ok" | "Error", _0: parsed | message }
    const r = parseFile (new Uint8Array (readFileSync (f)));
    if (r.TAG === "Error")
    {
        ++failed;
        console.log (`FAILED ${f}: ${r._0}`);
        continue;
    }
    const { programs: progs, version, warnings } = r._0;
    ++ok;
    programs += progs.length;
    versions.set (version, (versions.get (version) ?? 0) + progs.length);
    if (warnings.length) console.log (`${basename (f)}: ${warnings.join ("; ")}`);
}
console.log (`${ok} files read, ${failed} failed, ${programs} programs; source versions: ${[...versions].map (([v, n]) => v + " x" + n).join (", ")}`);
process.exit (failed ? 1 : 0);
