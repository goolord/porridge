// Smoke test for Porridge's own effects and filter types: renders the first factory program's
// chord through each rack effect (on, at its defaults) and through each of Porridge's filter
// types, and checks that the output is finite, sounds, stays bounded, and (for the effects)
// falls back to digital silence once the tail has died.
//
//   node tools/test/smoke.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/smoke/.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { programSize, bankHeaderSize } from "../../ui/oatmeal/OatmealFormat.res.mjs";
import { rackEntries } from "../../ui/PorridgeParams.res.mjs";
import * as FilterTypes from "../../ui/FilterTypes.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as DistTypes from "../../ui/DistTypes.res.mjs";
import { root, outDir, render, checker } from "./lib.mjs";

const dir = outDir ("smoke");

const bank = readFileSync (join (root, "presets", "oatmealprs.dat"));
const prog = join (dir, "p0.bin");
writeFileSync (prog, bank.subarray (bankHeaderSize, bankHeaderSize + programSize));
const events = join (dir, "events.txt");
writeFileSync (events, "0 144 48 100\n0 144 55 90\n0 144 64 110\n44100 128 48 0\n44100 128 55 0\n44100 128 64 0\n");

const rate = 44100, frames = 44100 * 12;
const { check, done } = checker ({ verbose: true });

function sounds (name, sets, { tail })
{
    const channels = render ({ program: prog, events, frames, rate, sets, out: join (dir, name.replace (/[^A-Za-z0-9]+/g, "_") + ".f32") });
    const n = channels[0].length;
    let peak = 0, finite = true, lastSound = 0;
    for (const ch of channels)
        for (let i = 0; i < n; ++i)
        {
            const v = ch[i];
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
    check (! problems.length, `${name.padEnd (24)} peak ${peak.toFixed (3).padStart (7)}  ${ends}${problems.length ? "  <- " + problems.join (", ") : ""}`);
}

// every one of Porridge's own effects, in rack slot 5 after Oatmeal's chain
const switches = { flanger: "Fl_On", phaser: "Ph_On", compressor: "Cp_On", space: "Rv_On", convolve: "Cv_On",
                   bode: "Bd_On", filter: "Ff_On", utility: "Ut_On", ambience: "Am_On", air: "Ai_On" };
rackEntries.forEach ((entry, value) =>
{
    if (! entry || entry[1] !== 1 || ! switches[entry[0]]) return;
    sounds (entry[0], { FX_Rack_5: value, [switches[entry[0]]]: 1 }, { tail: true });
});

// a few settings that push them
sounds ("flanger feedback", { FX_Rack_5: 21, Fl_On: 1, Fl_Feedback: -1, Fl_Depth: 1 }, { tail: true });
sounds ("phaser 16 stages", { FX_Rack_5: 25, Ph_On: 1, Ph_Stages: 5, Ph_Feedback: 1 }, { tail: true });
sounds ("bode echoes", { FX_Rack_5: 39, Bd_On: 1, Bd_Feedback: 0.8, Bd_Mode: 2 }, { tail: true });
for (let m = 0; m < 5; ++m)
    sounds (`algo reverb model ${m}`, { FX_Rack_5: 33, Rv_On: 1, Rv_Model: m, Rv_Decay: 0.4 }, { tail: true });
for (let k = 0; k < 11; ++k)
    sounds (`convolve impulse ${k}`, { FX_Rack_5: 37, Cv_On: 1, Cv_Impulse: k, Cv_Mix: 0.5 }, { tail: true });
const ambience = rackEntries.findIndex (e => e && e[0] === "ambience" && e[1] === 1);
for (let m = 0; m < 3; ++m)
    for (const [size, time] of [[0, 0], [0.3, 0.3], [1, m === 2 ? 0.25 : 0.6]])     // (verb tiny is slower when big)
        sounds (`ambience ${m} size ${size} time ${time}`, { FX_Rack_5: ambience, Am_On: 1, Am_Model: m, Am_Size: size, Am_Time: time,
                                                            Am_HighTime: 0.5, Am_LowTime: -0.5, Am_Mix: 0.5 }, { tail: true });
const air = rackEntries.findIndex (e => e && e[0] === "air" && e[1] === 1);
sounds ("air pushed", { FX_Rack_5: air, Ai_On: 1, Ai_Air: 1, Ai_Body: 0.2, Ai_DarkFreq: 0.2, Ai_Darken: 0.8 }, { tail: true });

// the distortion's types, in every voice and on the whole sound, gently and pushed; the models
// once more at 8x oversampling
for (let t = 1; t < DistTypes.all.length; ++t)
    for (const [mode, where] of [[1, "voice"], [0, "global"]])
        for (const drive of [0.2, 0.9])
            sounds (`dist ${DistTypes.all[t].short} ${where} ${drive}`, { Sat_Type: t, Sat_Mode: mode, Sat_Drive: drive, Sat_Tone: 0.7,
                                                                      Sat_Character: 0.3, Sat_Pregain: drive * 12 }, { tail: true });
for (let t = DistTypes.firstModel; t < DistTypes.all.length; ++t)
    sounds (`dist ${DistTypes.all[t].short} 8x`, { Sat_Type: t, Sat_Mode: 1, Sat_Oversample: 3 }, { tail: true });
// the models' knobs gliding under the mod envelope, and the air's amount under an LFO
for (const t of [DistTypes.firstModel + 4, DistTypes.firstModel + 8])
    sounds (`dist ${DistTypes.all[t].short} gliding`, { Sat_Type: t, Sat_Mode: 0, Mod1_Source: ModMatrix.sourceIndex ("modEnv1"),
                                                       Mod1_Target: ModMatrix.targetIndex ("Sat_Drive"), Mod1_Amount: 0.8 }, { tail: true });
sounds ("air under an LFO", { FX_Rack_5: air, Ai_On: 1, Mod1_Source: ModMatrix.sourceIndex ("lfo1"),
                              Mod1_Target: ModMatrix.targetIndex ("Ai_Air"), Mod1_Amount: 0.5 }, { tail: true });

// the mix: the dry waits as long as the oversampling delays the distorted sound, so that the
// two line up (hard clipping, below its limit, is the sound as it was)
for (const os of [0, 1, 2, 3])
{
    const linear = { Sat_Type: 1, Sat_Mode: 0, Sat_Oversample: os, Sat_Pregain: -30, Sat_Postgain: 30 };
    const [wet] = render ({ program: prog, events, frames: rate, rate, sets: { ...linear, Sat_Mix: 1 }, out: join (dir, `mix_wet_${os}.f32`) });
    const [dry] = render ({ program: prog, events, frames: rate, rate, sets: { ...linear, Sat_Mix: 0 }, out: join (dir, `mix_dry_${os}.f32`) });
    let best = 0, bestLag = 0;
    for (let lag = -8; lag <= 8; ++lag)
    {
        let c = 0;
        for (let i = 1000; i < rate - 1000; ++i) c += wet[i] * dry[i + lag];
        if (c > best) { best = c; bestLag = lag; }
    }
    check (bestLag === 0, `distortion mix at ${[1, 2, 4, 8][os]}x lines up (best lag ${bestLag})`);
}

// the oscillators' own envelopes: with a short decay to silence, the chord dies away under the
// amp envelope's sustain; switched on at their defaults (a gate), it sounds as before
{
    const rms = (name, sets, from, to) =>
    {
        const [l, r] = render ({ program: prog, events, frames: rate, rate, sets, out: join (dir, name + ".f32") });
        let sum = 0;
        for (let i = Math.floor (from * rate); i < Math.floor (to * rate); ++i) sum += l[i] * l[i] + r[i] * r[i];
        return Math.sqrt (sum / ((to - from) * rate));
    };
    const quiet = { N_Amp: 0 };
    const base = rms ("osc_env_off", quiet, 0.5, 0.9);
    const decayed = rms ("osc_env_decay", { ...quiet, OE1_On: 1, OE2_On: 1, OE1_Sustain: 0, OE2_Sustain: 0,
                                             OE1_Decay2: 60, OE2_Decay2: 60 }, 0.5, 0.9);
    const gate = rms ("osc_env_gate", { ...quiet, OE1_On: 1, OE2_On: 1 }, 0.5, 0.9);
    const early = rms ("osc_env_decay", { ...quiet, OE1_On: 1, OE2_On: 1, OE1_Sustain: 0, OE2_Sustain: 0,
                                           OE1_Decay2: 60, OE2_Decay2: 60 }, 0, 0.02);
    check (base > 1e-3 && decayed < base * 0.01 && early > 1e-3,
           `osc envelopes decay      ${base.toFixed (4)} -> ${decayed.toExponential (2)} (first 20 ms ${early.toFixed (4)})`);
    check (Math.abs (gate - base) < base * 0.05, `osc envelopes as a gate  ${base.toFixed (4)} vs ${gate.toFixed (4)}`);
}

// the noise source, on the pitch and on the cutoff
const noise = ModMatrix.sourceIndex ("noise");
sounds ("noise > pitch", { Mod1_Source: noise, Mod1_Target: ModMatrix.targetIndex ("finePitch"), Mod1_Amount: 0.5 }, { tail: false });
sounds ("noise > cutoff", { Mod1_Source: noise, Mod1_Target: ModMatrix.targetIndex ("Cutoff"), Mod1_Amount: 0.3 }, { tail: false });

// Porridge's filter types, at a mid cutoff with some resonance
for (let t = FilterTypes.firstPorridge; t < FilterTypes.all.length; ++t)
    sounds (`filter ${t} ${FilterTypes.all[t]}`.slice (0, 24), { Filter: t, Cutoff: 0.45, Resonance: 0.6, F_Morph: 0.3, F_Drive: 0.3 }, { tail: false });

done ("all ok");
