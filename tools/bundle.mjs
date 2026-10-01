// Bundles the compiled ReScript view and worker into the two self-contained ES modules
// the patch manifest loads (Cmajor can't resolve the @rescript/runtime imports itself), and
// encodes Oatmeal's factory bank as a new instance's stored state keeps it, which the worker
// installs (worker/PatchWorker.res).
//
// run: npm run build   (compiles the ReScript sources, then bundles)

import { build } from "esbuild";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");

const bundles = [
    ["ui/Index.res.mjs", "bundle/view.js"],
    ["worker/PatchWorker.res.mjs", "bundle/worker.js"],
];

for (const [entry, out] of bundles)
{
    await build ({
        entryPoints: [join (root, entry)],
        outfile: join (root, out),
        bundle: true,
        format: "esm",
        platform: "browser",
        target: "es2020",
        legalComments: "none",
        logLevel: "warning",
    });
    console.log (`${entry} -> ${out}`);
}

const Preset = await import (pathToFileURL (join (root, "ui", "Preset.res.mjs")).href);
const factory = Preset.factoryBank (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
writeFileSync (join (root, "bundle", "factory-bank.json"), Preset.encodeBank (factory));
console.log ("presets/oatmealprs.dat -> bundle/factory-bank.json");
