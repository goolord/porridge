// Smoke test for Porridge's own effects and filter types: renders the first factory program's
// chord through each rack effect (on, at its defaults) and through each of Porridge's filter
// types, and checks that the output is finite, sounds, stays bounded, and (for the effects)
// falls back to digital silence once the tail has died.
//
//   node tools/test/smoke.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/smoke/.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { programSize, bankHeaderSize } from "../../ui/oatmeal/OatmealFormat.res.mjs";
import { rackEntries } from "../../ui/PorridgeParams.res.mjs";
import * as FilterTypes from "../../ui/FilterTypes.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..", "..");
const build = join (root, "tools", "test", "build");
const dir = join (build, "smoke");
const host = join (build, process.platform === "win32" ? "host.exe" : "host");
mkdirSync (dir, { recursive: true });

const bank = readFileSync (join (root, "presets", "oatmealprs.dat"));
const prog = join (dir, "p0.bin");
writeFileSync (prog, bank.subarray (bankHeaderSize, bankHeaderSize + programSize));
const events = join (dir, "events.txt");
writeFileSync (events, "0 144 48 100\n0 144 55 90\n0 144 64 110\n44100 128 48 0\n44100 128 55 0\n44100 128 64 0\n");

const rate = 44100, frames = 44100 * 12;
let failures = 0;

function render (name, sets)
{
    const out = join (dir, name.replace (/[^A-Za-z0-9]+/g, "_") + ".f32");
    execFileSync (host, ["--program", prog, "--events", events, "--frames", String (frames), "--rate", String (rate),
                         ...sets.flatMap (s => ["--set", s]), "--out", out]);
    const b = readFileSync (out);
    const channels = b.readInt32LE (0), n = b.readInt32LE (4);
    return { channels, n, data: new Float32Array (b.buffer.slice (b.byteOffset + 8, b.byteOffset + 8 + channels * n * 4)) };
}

function check (name, sets, { tail })
{
    const { channels, n, data } = render (name, sets);
    let peak = 0, finite = true, lastSound = 0;
    for (let c = 0; c < channels; ++c)
        for (let i = 0; i < n; ++i)
        {
            const v = data[c * n + i];
            if (! Number.isFinite (v)) finite = false;
            const a = Math.abs (v);
            if (a > peak) peak = a;
            if (a > 0) lastSound = Math.max (lastSound, i);
        }
    const problems = [];
    if (! finite) problems.push ("not finite");
    if (peak < 1e-3) problems.push ("silent");
    if (peak > 16) problems.push (`peak ${peak.toFixed (2)}`);
    if (tail && lastSound >= n - 1) problems.push ("never falls silent");
    const ends = lastSound >= n - 1 ? "still sounding" : `silent after ${(lastSound / rate).toFixed (2)} s`;
    console.log (`${problems.length ? "FAIL" : "ok  "} ${name.padEnd (24)} peak ${peak.toFixed (3).padStart (7)}  ${ends}${problems.length ? "  <- " + problems.join (", ") : ""}`);
    failures += problems.length ? 1 : 0;
}

// every one of Porridge's own effects, in rack slot 5 after Oatmeal's chain
const switches = { flanger: "Fl_On", phaser: "Ph_On", compressor: "Cp_On", space: "Rv_On", convolve: "Cv_On",
                   bode: "Bd_On", filter: "Ff_On", utility: "Ut_On" };
rackEntries.forEach ((entry, value) =>
{
    if (! entry || entry[1] !== 1 || ! switches[entry[0]]) return;
    check (entry[0], [`FX_Rack_5=${value}`, `${switches[entry[0]]}=1`], { tail: true });
});

// a few settings that push them
check ("flanger feedback", ["FX_Rack_5=21", "Fl_On=1", "Fl_Feedback=-1", "Fl_Depth=1"], { tail: true });
check ("phaser 16 stages", ["FX_Rack_5=25", "Ph_On=1", "Ph_Stages=5", "Ph_Feedback=1"], { tail: true });
check ("bode echoes", ["FX_Rack_5=39", "Bd_On=1", "Bd_Feedback=0.8", "Bd_Mode=2"], { tail: true });
for (let m = 0; m < 5; ++m)
    check (`algo reverb model ${m}`, ["FX_Rack_5=33", "Rv_On=1", `Rv_Model=${m}`, "Rv_Decay=0.4"], { tail: true });
for (let k = 0; k < 11; ++k)
    check (`convolve impulse ${k}`, ["FX_Rack_5=37", "Cv_On=1", `Cv_Impulse=${k}`, "Cv_Mix=0.5"], { tail: true });

// Porridge's filter types, at a mid cutoff with some resonance
for (let t = FilterTypes.firstPorridge; t < FilterTypes.all.length; ++t)
    check (`filter ${t} ${FilterTypes.all[t]}`.slice (0, 24), [`Filter=${t}`, "Cutoff=0.45", "Resonance=0.6", "F_Morph=0.3", "F_Drive=0.3"], { tail: false });

console.log (failures ? `${failures} failures` : "all ok");
process.exit (failures ? 1 : 0);
