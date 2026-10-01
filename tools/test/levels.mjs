// Renders the Vanilla bank's programs through the test host and measures them:
//   - gain: the output gain that puts a four-note chord (a single note for the mono programs) at
//     -18 dB RMS over its loudest 300 ms, less if a held five-note chord at full velocity would
//     peak above -1 dBFS (tools/vanilla-bank.mjs keeps these);
//   - peak: that chord's peak with the gain, in dBFS;
//   - tail: the level 1 s after the keys are released, against the last half second held (dB):
//     the release, delay and reverb that are left;
//   - centroid and bands: where the held sound's energy sits;
//   - motion: how much it moves while the keys are held, from 93 ms windows: the spread of the
//     spectral centroid (semitones) and of the stereo position (% of the way to a side).
//
// run: node tools/test/levels.mjs [name ...]   (build the host with tools/test/build.sh and run
//      `npm run res` and `node tools/vanilla-bank.mjs` first)
//      --wav writes each render to tools/test/build/levels/<name>.wav

import { writeFileSync } from "node:fs";
import { join } from "node:path";
import * as Preset from "../../ui/Preset.res.mjs";
import * as Scala from "../../ui/Scala.res.mjs";
import { outDir, render, readBank } from "./lib.mjs";

const dir = outDir ("levels");

const args = process.argv.slice (2);
const wav = args.includes ("--wav");
const only = args.filter (a => ! a.startsWith ("--"));

const rate = 44100, hold = 3, tail = 3;
const target = -18;

const bank = readBank ("presets/vanilla.porridge");
const init = Preset.make ("Init").values;

const db = x => 20 * Math.log10 (Math.max (x, 1e-12));

const play = (p, name, notes, velocity) =>
{
    const prog = join (dir, name + ".bin");
    writeFileSync (prog, Preset.toOatmeal (p));
    const events = join (dir, name + ".txt");
    writeFileSync (events, notes.flatMap (n => [`0 144 ${n} ${velocity}`, `${hold * rate} 128 ${n} 0`]).join ("\n") + "\n");
    // Oatmeal's export loses Porridge's values: set every one that isn't Init's
    const sets = { Gain: 1 }, args = [];
    for (const [id, x] of p.values)
        if (id !== "Gain" && x !== init.get (id)) sets[id] = x;
    if (p.tuning)
    {
        const t = Scala.table (p.tuning);
        if (t.TAG === "Ok")
        {
            const file = join (dir, name + ".tun");
            writeFileSync (file, Array.from (t._0.semitones).join ("\n"));
            args.push ("--tuning", file);
        }
    }
    return render ({ program: prog, events, frames: (hold + tail) * rate, rate, sets, args, out: join (dir, name + ".f32") });
};

const rms = ([l, r], from, to) =>
{
    let s = 0;
    const a = Math.floor (from * rate), b = Math.floor (to * rate);
    for (let i = a; i < b; ++i) s += l[i] * l[i] + r[i] * r[i];
    return Math.sqrt (s / (2 * (b - a)));
};

const peak = ([l, r]) => l.reduce ((m, x, i) => Math.max (m, Math.abs (x), Math.abs (r[i])), 0);

// energy per band (dB relative to the total) over the held part, from 8192-point FFTs
const bands = [[20, 120], [120, 500], [500, 2000], [2000, 6000], [6000, 20000]];
const fft = (re, im) =>
{
    const n = re.length;
    for (let i = 1, j = 0; i < n; ++i)
    {
        let bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= n; len <<= 1)
    {
        const a = -2 * Math.PI / len;
        for (let i = 0; i < n; i += len)
            for (let k = 0; k < len / 2; ++k)
            {
                const c = Math.cos (a * k), s = Math.sin (a * k);
                const ur = re[i + k], ui = im[i + k];
                const vr = re[i + k + len / 2] * c - im[i + k + len / 2] * s;
                const vi = re[i + k + len / 2] * s + im[i + k + len / 2] * c;
                re[i + k] = ur + vr; im[i + k] = ui + vi;
                re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
            }
    }
};
// the power per bin of N samples of one channel from start, through a Hann window
const windowedPower = (ch, start, N) =>
{
    const re = new Float64Array (N), im = new Float64Array (N);
    for (let i = 0; i < N; ++i) re[i] = ch[start + i] * (0.5 - 0.5 * Math.cos (2 * Math.PI * i / N));
    fft (re, im);
    return Float64Array.from ({ length: N / 2 }, (_, k) => re[k] * re[k] + im[k] * im[k]);
};
const spectrum = ([l, r], from, to) =>
{
    const N = 8192, power = new Float64Array (N / 2);
    for (let start = Math.floor (from * rate); start + N <= to * rate; start += N / 2)
        for (const ch of [l, r])
            windowedPower (ch, start, N).forEach ((p, k) => power[k] += p);
    const total = power.reduce ((a, b) => a + b, 0) || 1;
    let centroid = 0;
    power.forEach ((p, k) => centroid += p * k * rate / N);
    const band = bands.map (([lo, hi]) =>
    {
        let s = 0;
        for (let k = Math.ceil (lo * N / rate); k < Math.min (N / 2, hi * N / rate); ++k) s += power[k];
        return db (Math.sqrt (s / total));
    });
    return { centroid: centroid / total, band };
};

// the spread of the centroid (semitones) and of the stereo balance (%) over 93 ms windows from
// 0.3 s to the release, leaving out windows more than 50 dB below the loudest
const motion = ([l, r]) =>
{
    const N = 4096, frames = [];
    for (let start = Math.floor (0.3 * rate); start + N <= hold * rate; start += N / 2)
    {
        const power = new Float64Array (N / 2);
        let el = 0, er = 0;
        for (const [ch, side] of [[l, 0], [r, 1]])
        {
            const p = windowedPower (ch, start, N);
            for (let k = 1; k < N / 2; ++k)
            {
                power[k] += p[k];
                if (side) er += p[k]; else el += p[k];
            }
        }
        const total = el + er;
        let c = 0;
        power.forEach ((p, k) => c += p * k * rate / N);
        frames.push ({ total, centroid: c / Math.max (total, 1e-30), pan: Math.sqrt (er) / Math.max (Math.sqrt (el) + Math.sqrt (er), 1e-30) });
    }
    const loudest = Math.max (...frames.map (x => x.total));
    const live = frames.filter (x => x.total > loudest * 1e-5);
    const spread = xs => { const m = xs.reduce ((a, b) => a + b, 0) / xs.length; return Math.sqrt (xs.reduce ((a, b) => a + (b - m) ** 2, 0) / xs.length); };
    return { timbre: spread (live.map (x => 12 * Math.log2 (Math.max (x.centroid, 1)))), pan: 200 * spread (live.map (x => x.pan)) };
};

const writeWav = (file, [l, r], gain) =>
{
    const n = l.length, b = Buffer.alloc (44 + 8 * n);
    b.write ("RIFF", 0); b.writeUInt32LE (36 + 8 * n, 4); b.write ("WAVEfmt ", 8);
    b.writeUInt32LE (16, 16); b.writeUInt16LE (3, 20); b.writeUInt16LE (2, 22); b.writeUInt32LE (rate, 24);
    b.writeUInt32LE (8 * rate, 28); b.writeUInt16LE (8, 32); b.writeUInt16LE (32, 34);
    b.write ("data", 36); b.writeUInt32LE (8 * n, 40);
    for (let i = 0; i < n; ++i) { b.writeFloatLE (l[i] * gain, 44 + 8 * i); b.writeFloatLE (r[i] * gain, 48 + 8 * i); }
    writeFileSync (file, b);
};

const fileName = s => s.replace (/[^A-Za-z0-9]+/g, "-");
const gains = {};
console.log ("program              gain     peak  tail  centroid   <120  -500   -2k   -6k  >6k (dB)   motion: timbre  pan");
for (const p of bank)
{
    const name = p.meta.name;
    if (only.length && ! only.some (o => name.toLowerCase().includes (o.toLowerCase()))) continue;
    const mono = p.values.get ("PolyMode") !== 1;
    const low = p.meta.category === "bass";
    const notes = mono ? [low ? 36 : 60] : [48, 55, 64, 71];
    const id = fileName (name);
    const sound = play (p, id, notes, 100);
    // the loudest 300 ms while the keys are down, so that plucks and pads compare
    let level = 0;
    for (let t = 0; t + 0.3 <= hold; t += 0.05) level = Math.max (level, rms (sound, t, t + 0.3));
    const loud = play (p, id + "-loud", mono ? notes : [48, 55, 60, 64, 71], 127);
    const gain = Math.min (Math.pow (10, target / 20) / Math.max (level, 1e-9), Math.pow (10, -1 / 20) / Math.max (peak (loud), 1e-9));
    const after = rms (sound, hold + 1, hold + 1.5) / Math.max (rms (sound, hold - 0.5, hold), 1e-9);
    const { centroid, band } = spectrum (sound, 0.25, hold);
    const moves = motion (sound);
    gains[name] = Number (gain.toPrecision (3));
    console.log (`${name.padEnd (18)} ${gain.toFixed (3).padStart (6)} ${db (peak (loud) * gain).toFixed (1).padStart (7)}`
        + ` ${db (after).toFixed (0).padStart (5)} ${centroid.toFixed (0).padStart (8)}  `
        + band.map (x => x.toFixed (0).padStart (5)).join (" ")
        + `  ${moves.timbre.toFixed (1).padStart (13)} st ${moves.pan.toFixed (0).padStart (3)} %`);
    if (wav) writeWav (join (dir, id + ".wav"), sound, gain);
}
console.log (JSON.stringify (gains, null, 4));
