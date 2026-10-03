// Shared by the test scripts: paths, rendering through the test host (tools/test/build.sh
// builds it), one at a time or several at once, reading the bundled banks, counting failures
// and measuring renders.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { execFile, execFileSync } from "node:child_process";
import { availableParallelism } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../../ui/Preset.res.mjs";
import * as SlotParams from "../../ui/SlotParams.res.mjs";
import * as StoredParams from "../../ui/StoredParams.res.mjs";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";

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

// A slot's parameter ("Fl_Rate@3") as the knob the patch has for it, for the kind the sets put in
// its slot (the rack and lane values, read from the sets, 0 where they don't say): SlotParams.
export const toEndpoints = sets =>
{
    // (sets that name the old copies' parameters, D2_Wet or Fl_Rate for the effect in a slot,
    // load into the slots as a program from before them would: Preset.migrateSlots)
    const targetKeys = Object.keys (sets).filter (k => /^Mod\d+_Target$/.test (k));
    const keyOf = k => ModMatrix.targets[sets[k]]?.key;
    if (Object.keys (sets).some (k => PorridgeParams.isLegacyId (k)) || targetKeys.some (k => PorridgeParams.isLegacyId (keyOf (k))))
    {
        // (connections to them too)
        const m = Preset.migrateSlots ("test", sets, targetKeys.map (k => ({ source: "x", target: keyOf (k), amount: 1 })));
        if (m.modulations.length !== targetKeys.length) throw new Error ("a test's connection to a copy in no slot");
        sets = { ...m.params };
        targetKeys.forEach ((k, i) => { sets[k] = SlotParams.targetIndex (m.modulations[i].target); });
    }
    const get = id => sets[id] ?? 0;
    // (every knob of a slot the sets fill: its kind's defaults, as the view sets them)
    const filled = {};
    for (let g = 0; g < PorridgeParams.slotCount; ++g)
        if (sets[PorridgeParams.slotKindId (g)])
            for (const [knob, v] of SlotParams.knobValues (SlotParams.lookup, id => sets[id] ?? SlotParams.lookup (id)?.init ?? 0, g))
                filled[knob] = v;
    return Object.fromEntries (Object.entries ({ ...filled, ...sets }).flatMap (([k, v]) =>
    {
        if (! k.includes ("@") || StoredParams.isStored (k)) return [[k, v]];
        const knob = SlotParams.knobOf (get, k);
        // (its slot holds another kind: the patch doesn't hear it, as from the view)
        if (knob === undefined) return [];
        return [[knob, SlotParams.toKnob (SlotParams.lookup (k), v)]];
    }));
};

const hostArgs = ({ program, events, frames, rate = 44100, sets = {}, args = [], out }) =>
    [...(program ? ["--program", program] : []), "--events", events, "--frames", String (frames), "--rate", String (rate), ...args,
     ...Object.entries (toEndpoints (sets)).flatMap (([k, v]) => ["--set", `${k}=${v}`]), "--out", out];

// the channels of a host output file's contents
const channelsOf = b =>
{
    const channels = b.readInt32LE (0), n = b.readInt32LE (4);
    const data = new Float32Array (b.buffer.slice (b.byteOffset + 8, b.byteOffset + 8 + 4 * channels * n));
    return Array.from ({ length: channels }, (_, c) => data.subarray (c * n, (c + 1) * n));
};

// Renders through the test host into `out` and returns the output's channels. sets: { endpoint:
// value } for --set; args: any other host arguments.
export function render (job)
{
    execFileSync (host, hostArgs (job));
    return channelsOf (readFileSync (job.out));
}

// render, without waiting: a promise of the channels (run many at once with `pool`)
export const renderAsync = job => new Promise ((resolve, reject) =>
    execFile (host, hostArgs (job), (error, stdout, stderr) =>
    {
        if (stderr) process.stderr.write (stderr);
        if (error) reject (error); else resolve (readFile (job.out).then (channelsOf));
    }));

// runs the tasks (functions returning promises) `jobs` at a time; their results, in order
export const pool = async (tasks, jobs = availableParallelism ()) =>
{
    const results = new Array (tasks.length);
    let next = 0;
    await Promise.all (Array.from ({ length: Math.min (jobs, tasks.length) }, async () =>
    {
        while (next < tasks.length)
        {
            const i = next++;
            results[i] = await tasks[i] ();
        }
    }));
    return results;
};

// A play (notes, sets, seconds) that renders notes ([at s, key, length s, velocity = 100]) for
// `seconds` from `program` with base's settings and sets over them, numbering its files in `dir`.
export const player = ({ dir, program, base, rate = 44100 }) =>
{
    let count = 0;
    return (notes, sets, seconds) =>
    {
        const events = join (dir, `events${count}.txt`);
        writeFileSync (events, notes.map (([at, key, length, vel = 100]) =>
            `${Math.round (at * rate)} 144 ${key} ${vel}\n${Math.round ((at + length) * rate)} 128 ${key} 0\n`).join (""));
        return render ({ program, events, frames: Math.round (seconds * rate), rate, sets: { ...base, ...sets },
                         out: join (dir, `render${count++}.f32`) });
    };
};

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

// the RMS of a stereo signal at a rate from a to b seconds (both channels)
export const rms = ([l, r], a, b, rate) =>
{
    let s = 0;
    const i0 = Math.round (a * rate), i1 = Math.round (b * rate);
    for (let i = i0; i < i1; ++i) s += l[i] * l[i] + r[i] * r[i];
    return Math.sqrt (s / (2 * (i1 - i0)));
};

// the level of a channel at a rate at a frequency (Hann-windowed DFT bin) over 16384 samples
// from `from` s, dB
export const levelAt = (x, hz, from, rate) =>
{
    const size = 16384, i0 = Math.round (from * rate);
    let re = 0, im = 0;
    for (let i = 0; i < size; ++i)
    {
        const w = 0.5 - 0.5 * Math.cos (2 * Math.PI * i / size), a = 2 * Math.PI * hz * i / rate;
        re += w * x[i0 + i] * Math.cos (a);
        im += w * x[i0 + i] * Math.sin (a);
    }
    return 20 * Math.log10 (Math.hypot (re, im) + 1e-12);
};

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

// An in-place radix-2 FFT of re and im (a power-of-2 length).
export const fft = (re, im) =>
{
    const N = re.length;
    for (let i = 1, j = 0; i < N; ++i)
    {
        let bit = N >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= N; len <<= 1)
    {
        const w = -2 * Math.PI / len, wr = Math.cos (w), wi = Math.sin (w), h = len / 2;
        for (let i = 0; i < N; i += len)
            for (let k = 0, cr = 1, ci = 0; k < h; ++k)
            {
                const p = i + k, q = p + h;
                const vr = re[q] * cr - im[q] * ci, vi = re[q] * ci + im[q] * cr;
                re[q] = re[p] - vr; im[q] = im[p] - vi; re[p] += vr; im[p] += vi;
                const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
            }
    }
};

// The power spectrum of a channel from sample a to b (Welch: 4096-point Hann frames, half
// overlapping), each bin's mean power; bin k is k * rate / 4096 Hz.
export const powerSpectrum = (x, a, b) =>
{
    const N = 4096, P = new Float64Array (N / 2);
    let frames = 0;
    for (let s = a; s + N <= b; s += N / 2, ++frames)
    {
        const re = new Float64Array (N), im = new Float64Array (N);
        for (let i = 0; i < N; ++i) re[i] = x[s + i] * (0.5 - 0.5 * Math.cos (2 * Math.PI * i / N));
        fft (re, im);
        for (let k = 0; k < N / 2; ++k) P[k] += re[k] * re[k] + im[k] * im[k];
    }
    return P.map (p => p / Math.max (frames, 1));
};

// The octave bands' power (dB) of a power spectrum at a rate, centred on 31.5 Hz .. 16 kHz.
export const octaveBands = (P, rate) => [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000].map (f =>
{
    let s = 0;
    for (let k = 1; k < P.length; ++k)
    {
        const hz = k * rate / (2 * P.length);
        if (hz >= f / Math.SQRT2 && hz < f * Math.SQRT2) s += P[k];
    }
    return 10 * Math.log10 (s + 1e-30);
});
