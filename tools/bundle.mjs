// Bundles the compiled ReScript view and worker into the two self-contained ES modules
// the patch manifest loads (Cmajor can't resolve the @rescript/runtime imports itself).
//
// run: npm run build   (compiles the ReScript sources, then bundles)

import { build } from "esbuild";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

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
