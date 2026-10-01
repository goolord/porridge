// Shared by the test scripts: paths, rendering through the test host (tools/test/build.sh
// builds it), reading the bundled banks and counting failures.

import { readFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../../ui/Preset.res.mjs";

export const root = join (dirname (fileURLToPath (import.meta.url)), "..", "..");
const build = join (root, "tools", "test", "build");
export const host = join (build, "host.exe");

// tools/test/build/<name>/, made if it isn't there
export const outDir = name =>
{
    const dir = join (build, name);
    mkdirSync (dir, { recursive: true });
    return dir;
};

// Renders through the test host into `out` and returns the output's channels. sets: { endpoint:
// value } for --set; args: any other host arguments.
export function render ({ program, events, frames, rate = 44100, sets = {}, args = [], out })
{
    execFileSync (host, [...(program ? ["--program", program] : []), "--events", events,
                         "--frames", String (frames), "--rate", String (rate), ...args,
                         ...Object.entries (sets).flatMap (([k, v]) => ["--set", `${k}=${v}`]), "--out", out]);
    const b = readFileSync (out);
    const channels = b.readInt32LE (0), n = b.readInt32LE (4);
    const data = new Float32Array (b.buffer.slice (b.byteOffset + 8, b.byteOffset + 8 + 4 * channels * n));
    return Array.from ({ length: channels }, (_, c) => data.subarray (c * n, (c + 1) * n));
}

// the presets of a bank or preset file, by its path from the repository root
export function readBank (path)
{
    const r = Preset.parseFile (new Uint8Array (readFileSync (join (root, path))));
    if (r.TAG !== "Ok") throw new Error (path + " didn't parse");
    return r._0.presets;
}

// Counts failures: check (ok, msg) and fail (msg) print "FAIL msg" (verbose: check prints
// "ok   msg" too); done (summary) prints the summary or the failure count and exits.
export function checker ({ verbose = false } = {})
{
    let failures = 0;
    const fail = msg => { console.log ("FAIL " + msg); ++failures; };
    const check = (ok, msg) => { if (! ok) fail (msg); else if (verbose) console.log ("ok   " + msg); };
    const done = summary =>
    {
        console.log (failures === 0 ? summary : `${failures} failures`);
        process.exit (failures === 0 ? 0 : 1);
    };
    return { check, fail, done };
}
