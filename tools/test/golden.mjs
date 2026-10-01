// Regression check for the DSP: renders every factory program through the test host and
// compares the output with a recording made earlier, sample for sample. The renders are in
// Oat mode (Oatmeal's MIDI timing) and Porridge-only features are off in factory programs,
// so changes that keep them neutral must leave every render bit-identical.
//
//   node tools/test/golden.mjs record     render and keep the result as the reference
//   node tools/test/golden.mjs check      render and compare with the reference
//
// Build the host first (tools/test/build.sh; it needs `npm run build`). Output goes to
// tools/test/build/golden/.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { programSize, bankHeaderSize, bankPrograms } from "../../ui/oatmeal/OatmealFormat.res.mjs";
import { root, outDir, render } from "./lib.mjs";

const mode = process.argv[2];

if (mode !== "record" && mode !== "check")
{
    console.log ("usage: node tools/test/golden.mjs record|check");
    process.exit (1);
}

const dir = outDir ("golden");

// a chord, a release, a single note with bend, pressure and the mod wheel
const events = [
    [0, 0x90, 48, 100], [0, 0x90, 55, 90], [0, 0x90, 64, 110],
    [30000, 0xb0, 1, 90], [40000, 0xd0, 80, 0],
    [44032, 0x80, 48, 0], [44032, 0x80, 55, 0], [44032, 0x80, 64, 0],
    [56000, 0x90, 60, 100], [60000, 0xe0, 0, 80], [70000, 0xe0, 0, 64], [80000, 0x80, 60, 0],
];
const eventsPath = join (dir, "events.txt");
writeFileSync (eventsPath, events.map (e => e.join (" ")).join ("\n") + "\n");

const bank = readFileSync (join (root, "presets", "oatmealprs.dat"));
const hashes = {};

for (let i = 0; i < bankPrograms; ++i)
{
    const prog = join (dir, `p${i}.bin`);
    writeFileSync (prog, bank.subarray (bankHeaderSize + i * programSize, bankHeaderSize + (i + 1) * programSize));
    const out = join (dir, `p${i}.f32`);
    render ({ program: prog, events: eventsPath, frames: 100000, sets: { Oat_Mode: 1 }, out });
    hashes[i] = createHash ("sha256").update (readFileSync (out)).digest ("hex");
}

const refPath = join (dir, "reference.json");

if (mode === "record")
{
    writeFileSync (refPath, JSON.stringify (hashes, null, 1));
    console.log (`recorded ${bankPrograms} renders`);
}
else
{
    if (! existsSync (refPath)) { console.log ("no reference; run `record` first"); process.exit (1); }
    const ref = JSON.parse (readFileSync (refPath, "utf8"));
    const changed = Object.keys (hashes).filter (k => hashes[k] !== ref[k]);
    console.log (changed.length === 0 ? `all ${bankPrograms} renders identical` : `changed: ${changed.join (", ")}`);
    process.exit (changed.length === 0 ? 0 : 1);
}
