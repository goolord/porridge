// Parses every Oatmeal program/bank file below a folder with Porridge's loader and reports
// what it found. Read-only.
//
//   node tools/re/check-presets.mjs "F:/VST32/oatmeal banks"

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname, basename } from "node:path";
import { parseFile } from "../../ui/oatmeal/oatmeal-format.js";

const root = process.argv[2];
if (! root) { console.log ("usage: node tools/re/check-presets.mjs <folder>"); process.exit (2); }

const files = [];
const walk = d => { for (const n of readdirSync (d)) { const p = join (d, n); statSync (p).isDirectory() ? walk (p) : files.push (p); } };
walk (root);

let ok = 0, failed = 0, programs = 0;
const versions = new Map();
for (const f of files.filter (f => /\.(omp|omb|fxp|fxb|dat)$/i.test (f)))
{
    try
    {
        const r = parseFile (new Uint8Array (readFileSync (f)), { filename: basename (f) });
        ++ok;
        programs += r.programs.length;
        for (const p of r.programs) versions.set (p.sourceVersion ?? r.version ?? "?", (versions.get (p.sourceVersion ?? r.version ?? "?") ?? 0) + 1);
        if (r.warnings?.length) console.log (`${basename (f)}: ${r.warnings.join ("; ")}`);
    }
    catch (e)
    {
        ++failed;
        console.log (`FAILED ${f}: ${e.message}`);
    }
}
console.log (`${ok} files read, ${failed} failed, ${programs} programs; source versions: ${[...versions].map (([v, n]) => v + " x" + n).join (", ")}`);
process.exit (failed ? 1 : 0);
