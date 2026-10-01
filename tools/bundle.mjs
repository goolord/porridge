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

await build ({
    entryPoints: { view: join (root, "ui", "Index.res.mjs"), worker: join (root, "worker", "PatchWorker.res.mjs") },
    outdir: join (root, "bundle"),
    bundle: true,
    format: "esm",
    platform: "browser",
    target: "es2020",
    legalComments: "none",
    logLevel: "warning",
});
console.log ("ui/Index.res.mjs -> bundle/view.js, worker/PatchWorker.res.mjs -> bundle/worker.js");

// The sound matcher's worker: a plain script, which the view runs after the engine's class
// (bundle/match-engine.js, from tools/match-engine.mjs) in one blob (ui/match/MatchPool.res).
await build ({
    entryPoints: { "match-worker": join (root, "ui", "match", "MatchWorker.res.mjs") },
    outdir: join (root, "bundle"),
    bundle: true,
    format: "iife",
    platform: "browser",
    target: "es2020",
    legalComments: "none",
    logLevel: "warning",
});
console.log ("ui/match/MatchWorker.res.mjs -> bundle/match-worker.js");

const Preset = await import (pathToFileURL (join (root, "ui", "Preset.res.mjs")).href);
const factory = Preset.factoryBank (new Uint8Array (readFileSync (join (root, "presets", "oatmealprs.dat"))));
writeFileSync (join (root, "bundle", "factory-bank.json"), Preset.encodeBank (factory));
console.log ("presets/oatmealprs.dat -> bundle/factory-bank.json");
