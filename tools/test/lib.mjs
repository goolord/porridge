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

// A biquad over a channel (a: [a1, a2], b: [b0, b1, b2]).
export const biquad = (x, [b0, b1, b2], [a1, a2]) =>
{
    const y = new Float64Array (x.length);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < x.length; ++i)
    {
        const v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
    }
    return y;
};

// ITU-R BS.1770's K-weighting at a rate (as pyloudnorm designs it): a high shelf of +4 dB
// from about 1.7 kHz, then a highpass at 38 Hz. What a loudness meter hears: brightness counts.
export const kWeight = (x, rate) =>
{
    const shelf = (() => {
        const G = 3.99984385397, Q = 0.7071752369554193, fc = 1681.974450955533;
        const A = 10 ** (G / 40), w = 2 * Math.PI * fc / rate, alpha = Math.sin (w) / (2 * Q), c = Math.cos (w);
        const a0 = (A + 1) - (A - 1) * c + 2 * Math.sqrt (A) * alpha;
        return [[A * ((A + 1) + (A - 1) * c + 2 * Math.sqrt (A) * alpha) / a0, -2 * A * ((A - 1) + (A + 1) * c) / a0,
                 A * ((A + 1) + (A - 1) * c - 2 * Math.sqrt (A) * alpha) / a0],
                [2 * ((A - 1) - (A + 1) * c) / a0, ((A + 1) - (A - 1) * c - 2 * Math.sqrt (A) * alpha) / a0]];
    }) ();
    const high = (() => {
        const Q = 0.5003270373253953, fc = 38.13547087613982;
        const w = 2 * Math.PI * fc / rate, alpha = Math.sin (w) / (2 * Q), c = Math.cos (w), a0 = 1 + alpha;
        return [[(1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0], [-2 * c / a0, (1 - alpha) / a0]];
    }) ();
    return biquad (biquad (x, ...shelf), ...high);
};

// the mean power of the loudest 300 ms (in 10 ms steps) of a stereo signal at a rate, dB
export const loudest = ([l, r], rate) =>
{
    const step = rate / 100, window = 30;
    const power = [];
    for (let a = 0; a + step <= l.length; a += step)
    {
        let s = 0;
        for (let i = a; i < a + step; ++i) s += l[i] * l[i] + r[i] * r[i];
        power.push (s / (2 * step));
    }
    let best = 0;
    for (let k = 0; k + window <= power.length; ++k)
        best = Math.max (best, power.slice (k, k + window).reduce ((a, b) => a + b, 0) / window);
    return 10 * Math.log10 (Math.max (best, 1e-18));
};
