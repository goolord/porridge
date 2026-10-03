// Bundles the compiled ReScript view and worker into the two self-contained ES modules
// the patch manifest loads (Cmajor can't resolve the @rescript/runtime imports itself), and
// encodes Oatmeal's factory bank as a new instance's stored state keeps it, which the worker
// installs (worker/PatchWorker.res).
//
// bundle/ is emptied first: Cmajor's generator embeds every file in the view's folder in the
// plugin, not only the ones the manifest names, so a file left over there makes it bigger.
//
// run: npm run build   (compiles the ReScript sources, then bundles)

import { build } from "esbuild";
import { readFileSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");

rmSync (join (root, "bundle"), { recursive: true, force: true });
mkdirSync (join (root, "bundle"));

await build ({
    entryPoints: { view: join (root, "ui", "Index.res.mjs"), worker: join (root, "worker", "PatchWorker.res.mjs") },
    outdir: join (root, "bundle"),
    bundle: true,
    format: "esm",
    platform: "browser",
    target: "es2020",
    minify: true,
    legalComments: "none",
    logLevel: "warning",
});
console.log ("ui/Index.res.mjs -> bundle/view.js, worker/PatchWorker.res.mjs -> bundle/worker.js");

const Preset = await import (pathToFileURL (join (root, "ui", "Preset.res.mjs")).href);
const factory = Preset.factoryBank (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
writeFileSync (join (root, "bundle", "factory-bank.json"), Preset.encodeBank (factory));
console.log ("presets/oatmealprs.dat -> bundle/factory-bank.json");
