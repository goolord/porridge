// Checks that a one-shot LFO holds the end of its cycle: a per-note LFO 1 sweeps the voice's
// pan over one cycle, and after the cycle the pan must stay where the sweep ended, not jump
// back towards where it started (the tables' last interval interpolates to the wrap guard).
//
// run: node tools/test/oneshot.mjs   (build the host with tools/test/build.sh and run
//      `npm run res` first)

import { writeFileSync, readFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../../ui/Preset.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..", "..");
const build = join (root, "tools", "test", "build");
const dir = join (build, "oneshot");
const host = join (build, process.platform === "win32" ? "host.exe" : "host");
mkdirSync (dir, { recursive: true });

const rate = 44100, frames = rate, cycle = 0.25;   // seconds
const prog = join (dir, "init.bin");
writeFileSync (prog, Preset.toOatmeal (Preset.make ("Init")));
const eventsPath = join (dir, "events.txt");
writeFileSync (eventsPath, "0 144 60 100\n");

// returns the pan, R / (L + R) in RMS, over [from, to) seconds
const render = (name, sets) =>
{
    const out = join (dir, name + ".f32");
    const args = ["--program", prog, "--events", eventsPath, "--frames", String (frames), "--rate", String (rate), "--out", out];
    for (const [k, v] of Object.entries (sets)) args.push ("--set", `${k}=${v}`);
    execFileSync (host, args);
    const buf = readFileSync (out);
    const n = buf.readInt32LE (4);
    const data = new Float32Array (buf.buffer.slice (buf.byteOffset + 8, buf.byteOffset + 8 + 8 * n));
    return (from, to) =>
    {
        let l = 0, r = 0;
        for (let i = Math.floor (from * rate); i < Math.floor (to * rate); ++i) { l += data[i] ** 2; r += data[n + i] ** 2; }
        return Math.sqrt (r) / (Math.sqrt (l) + Math.sqrt (r));
    };
};

let failures = 0;
const base = { LFO_1_Sync: 0, LFO_1_Unit: 2, LFO_1_Speed: cycle, LFO_1_Pan: 0.4, LFOPhase: 0, LFOPhaseRand: 0, LFO_1_OneShot: 1 };

// saw and square end at 1, sample & hold over 4 steps at 0.75: the pan must stay at the
// value it had near the end of the cycle
for (const [name, sets] of [["saw", { LFO_1_Shape: 1 }], ["square", { LFO_1_Shape: 2 }], ["saw-steps", { LFO_1_Shape: 1, LFO_1_Steps: 3 }]])
{
    const pan = render (name, { ...base, ...sets });
    const start = pan (0.01, 0.03), end = pan (cycle - 0.005, cycle - 0.001), held = pan (cycle + 0.05, 0.95);
    const ok = Math.abs (held - end) < 0.03 && Math.abs (held - start) > 0.1;
    console.log (`${ok ? "ok  " : "FAIL"} ${name}: pan ${start.toFixed (3)} at the start, ${end.toFixed (3)} near the end, ${held.toFixed (3)} held`);
    if (! ok) ++failures;
}

console.log (failures === 0 ? "ok: one-shot LFOs hold the end of the cycle" : `${failures} failures`);
process.exit (failures === 0 ? 0 : 1);
