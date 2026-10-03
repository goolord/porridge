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
import { root, outDir, render, renderAsync, pool, levelAt, checker } from "./lib.mjs";

const dir = outDir ("smoke");

const bank = readFileSync (join (root, "presets", "oatmealprs.dat"));
const prog = join (dir, "p0.bin");
writeFileSync (prog, bank.subarray (bankHeaderSize, bankHeaderSize + programSize));
const events = join (dir, "events.txt");
writeFileSync (events, "0 144 48 100\n0 144 55 90\n0 144 64 110\n44100 128 48 0\n44100 128 55 0\n44100 128 64 0\n");

const rate = 44100, frames = 44100 * 12;
const { check, done } = checker ({ verbose: true });

// sounds queues a render of the chord and its check; flush runs the queued renders several at a
// time and makes their checks, in order
const queued = [];
const sounds = (name, sets, opts) => queued.push (async () =>
    soundCheck (name, await renderAsync ({ program: prog, events, frames, rate, sets, out: join (dir, name.replace (/[^A-Za-z0-9]+/g, "_") + ".f32") }), opts));
const flush = async () => { for (const [ok, msg] of await pool (queued.splice (0))) check (ok, msg); };

function soundCheck (name, channels, { tail })
{
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
    return [! problems.length, `${name.padEnd (24)} peak ${peak.toFixed (3).padStart (7)}  ${ends}${problems.length ? "  <- " + problems.join (", ") : ""}`];
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
// once more with HQ oversampling (4x), and in Oat mode at Oatmeal's 8x
for (let t = 1; t < DistTypes.all.length; ++t)
    for (const [mode, where] of [[1, "voice"], [0, "global"]])
        for (const drive of [0.2, 0.9])
            sounds (`dist ${DistTypes.all[t].short} ${where} ${drive}`, { Sat_Type: t, Sat_Mode: mode, Sat_Drive: drive, Sat_Tone: 0.7,
                                                                      Sat_Character: 0.3, Sat_Pregain: drive * 12 }, { tail: true });
for (let t = DistTypes.firstModel; t < DistTypes.all.length; ++t)
{
    sounds (`dist ${DistTypes.all[t].short} HQ`, { Sat_Type: t, Sat_Mode: 1, Sat_Oversample: 2 }, { tail: true });
    sounds (`dist ${DistTypes.all[t].short} Oat 8x`, { Sat_Type: t, Sat_Mode: 1, Sat_Oversample: 3, Oat_Mode: 1 }, { tail: true });
}
// the models' knobs gliding under the mod envelope, and the air's amount under an LFO
for (const t of [DistTypes.firstModel + 4, DistTypes.firstModel + 8])
    sounds (`dist ${DistTypes.all[t].short} gliding`, { Sat_Type: t, Sat_Mode: 0, Mod1_Source: ModMatrix.sourceIndex ("modEnv1"),
                                                       Mod1_Target: ModMatrix.targetIndex ("Sat_Drive"), Mod1_Amount: 0.8 }, { tail: true });
sounds ("air under an LFO", { FX_Rack_5: air, Ai_On: 1, Mod1_Source: ModMatrix.sourceIndex ("lfo1"),
                              Mod1_Target: ModMatrix.targetIndex ("Ai_Air"), Mod1_Amount: 0.5 }, { tail: true });
await flush ();

// the mix: the dry waits as long as the oversampling delays the distorted sound, so that the
// two line up (hard clipping, below its limit, is the sound as it was): HQ, and Oatmeal's 2x, 4x
// and 8x in Oat mode. Outside Oat mode every one of Oatmeal's values is HQ.
const hq = [];
for (const oat of [0, 1])
    for (const os of [0, 1, 2, 3])
    {
        const linear = { Sat_Type: 1, Sat_Mode: 0, Sat_Oversample: os, Sat_Pregain: -30, Sat_Postgain: 30, Oat_Mode: oat };
        const [wet] = render ({ program: prog, events, frames: rate, rate, sets: { ...linear, Sat_Mix: 1 }, out: join (dir, `mix_wet_${oat}${os}.f32`) });
        const [dry] = render ({ program: prog, events, frames: rate, rate, sets: { ...linear, Sat_Mix: 0 }, out: join (dir, `mix_dry_${oat}${os}.f32`) });
        let best = 0, bestLag = 0;
        for (let lag = -8; lag <= 8; ++lag)
        {
            let c = 0;
            for (let i = 1000; i < rate - 1000; ++i) c += wet[i] * dry[i + lag];
            if (c > best) { best = c; bestLag = lag; }
        }
        const what = oat ? `${[1, 2, 4, 8][os]}x in Oat mode` : os ? `HQ (value ${os})` : "off";
        check (bestLag === 0, `distortion mix ${what} lines up (best lag ${bestLag})`);
        if (! oat && os) hq.push (wet);
    }
check (hq.every (w => w.every ((v, i) => v === hq[0][i])), "outside Oat mode 2x, 4x and 8x are all HQ");

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

// the key EQ: a saw's harmonics at A3, each band moving its own (harmonic 1, 2, 4 ... of the
// note) by its gain and leaving those two octaves away nearly alone; switched on flat, it changes
// nothing; with unison spread, both channels go through it
{
    const one = join (dir, "keq_events.txt");
    writeFileSync (one, "0 144 57 100\n44100 128 57 0\n");
    const init = join (root, "tools", "re", "init_prog.bin");
    const plain = { O1_Waveform: 1, O2_Amp: 0, N_Amp: 0, Filter: 0, Oat_Mode: 1 };
    const harmonicsDb = (name, sets) =>
    {
        const [l] = render ({ program: init, events: one, frames: rate, rate, sets: { ...plain, ...sets }, out: join (dir, name + ".f32") });
        const from = Math.floor (0.3 * rate), size = 16384;
        // the level at each harmonic (the highest of the DFT's nearby bins, Hann windowed)
        return [1, 2, 4, 8, 16].map (h =>
        {
            let best = 0;
            for (let hz = h * 220 * 0.98; hz <= h * 220 * 1.02; hz += 1)
            {
                let re = 0, im = 0;
                for (let i = 0; i < size; ++i)
                {
                    const w = 0.5 - 0.5 * Math.cos (2 * Math.PI * i / size);
                    const a = 2 * Math.PI * hz * i / rate;
                    re += w * l[from + i] * Math.cos (a);
                    im += w * l[from + i] * Math.sin (a);
                }
                best = Math.max (best, Math.hypot (re, im));
            }
            return 20 * Math.log10 (best + 1e-12);
        });
    };
    const off = harmonicsDb ("keq_off", {});
    const flat = harmonicsDb ("keq_flat", { KEQ_On: 1 });
    const boost = harmonicsDb ("keq_boost", { KEQ_On: 1, KEQ_3_Gain: 12 });
    const cut = harmonicsDb ("keq_cut", { KEQ_On: 1, KEQ_5_Gain: -18 });
    const shelf = harmonicsDb ("keq_shelf", { KEQ_On: 1, KEQ_1_Gain: 12 });
    check (shelf[0] - off[0] > 1 && shelf[0] - off[0] < 8 && Math.abs (shelf[3] - off[3]) < 0.5,
           `key EQ low shelf +12 dB  1x ${(shelf[0] - off[0]).toFixed (2)} dB (half an octave over its corner), 8x ${(shelf[3] - off[3]).toFixed (2)} dB`);
    const show = a => a.map (v => v.toFixed (1)).join (" ");
    check (flat.every ((v, i) => Math.abs (v - off[i]) < 0.01), `key EQ flat changes nothing  ${show (off)} | ${show (flat)}`);
    check (Math.abs (boost[2] - off[2] - 12) < 1 && Math.abs (boost[0] - off[0]) < 1.5,
           `key EQ band 3 (4x) +12 dB  4x ${(boost[2] - off[2]).toFixed (2)} dB, 1x ${(boost[0] - off[0]).toFixed (2)} dB`);
    check (Math.abs (cut[4] - off[4] + 18) < 1.5 && Math.abs (cut[2] - off[2]) < 1.5,
           `key EQ band 5 (16x) -18 dB  16x ${(cut[4] - off[4]).toFixed (2)} dB, 4x ${(cut[2] - off[2]).toFixed (2)} dB`);
    sounds ("key EQ, unison spread", { KEQ_On: 1, KEQ_2_Gain: 18, KEQ_6_Gain: -24, KEQ_8_Gain: 24, U_Voices: 4, U_Spread: 1 }, { tail: false });
    await flush ();

    // an oscillator's noise roughens it: what lies between its harmonics rises well over the
    // clean saw's, its level stays about as it was; with unison and hard sync it stays bounded
    const between = sets =>
    {
        const [l] = render ({ program: init, events: one, frames: rate, rate, sets: { ...plain, ...sets }, out: join (dir, "osc_noise.f32") });
        const from = Math.floor (0.3 * rate), size = 16384;
        let rms = 0;
        for (let i = from; i < from + size; ++i) rms += l[i] * l[i];
        return { gap: [2.5, 4.5, 8.5].map (h => levelAt (l, h * 220, 0.3, rate)).reduce ((a, b) => a + b) / 3, level: 10 * Math.log10 (rms / size) };
    };
    const clean = between ({}), rough = between ({ O1_Noise: 0.5 });
    check (rough.gap - clean.gap > 15 && Math.abs (rough.level - clean.level) < 3,
           `osc noise fills the gaps  ${(rough.gap - clean.gap).toFixed (1)} dB between harmonics, level ${(rough.level - clean.level).toFixed (2)} dB`);
    sounds ("osc noise, unison, sync", { O1_Noise: 0.8, O2_Noise: 0.8, O2_NoiseColour: 1, U_Voices: 4, OscMix: 1 }, { tail: false });
    await flush ();
    // osc 2 heard in PM 2 > 1 (a sine a twelfth up): the sound gets louder by osc 2's own
    const pm = between ({ OscMix: 3, O2_Amp: 0.5, Transpose: 19 / 12, O2_Waveform: 0 });
    const heardPm = between ({ OscMix: 3, O2_Amp: 0.5, Transpose: 19 / 12, O2_Waveform: 0, O2_PairMix: 1 });
    check (heardPm.level - pm.level > 0.5, `osc 2 heard in PM  level ${(heardPm.level - pm.level).toFixed (2)} dB`);

    // the oscillators' shape: a sine morphed all the way to the saw is the HQ saw; phase
    // distortion brightens a sine (its third harmonic rises from nothing) and adds no DC to a
    // saw; both stay bounded with unison and in the sync and FM mixes
    const shaped = (name, sets) => render ({ program: init, events: one, frames: rate, rate, sets: { ...plain, ...sets }, out: join (dir, name + ".f32") })[0];
    const morphed = shaped ("morph_saw", { O1_Waveform: 0, O1_Morph: 1, O1_MorphTo: 1 }), saw = shaped ("hq_saw", { O1_Waveform: 6 });
    const morphDiff = morphed.reduce ((m, x, i) => Math.max (m, Math.abs (x - saw[i])), 0);
    check (morphDiff < 1e-6, `sine morphed to the saw is the HQ saw  max diff ${morphDiff.toExponential (2)}`);
    const third = sets => levelAt (shaped ("pd_sine", { O1_Waveform: 0, ...sets }), 660, 0.3, rate);
    check (third ({ O1_PD: 0.7 }) - third ({}) > 60, `phase distortion brightens a sine  3rd harmonic +${(third ({ O1_PD: 0.7 }) - third ({})).toFixed (1)} dB`);
    const bent = shaped ("pd_saw", { O1_Waveform: 6, O1_PD: 1 });
    const from = Math.floor (0.3 * rate), to = Math.floor (0.7 * rate);
    let dc = 0, peak = 0;
    for (let i = from; i < to; ++i) { dc += bent[i]; peak = Math.max (peak, Math.abs (bent[i])); }
    dc /= to - from;
    check (Math.abs (dc) < 0.01 * peak, `phase distortion adds no DC  ${(100 * dc / peak).toFixed (2)} % of the peak`);
    sounds ("osc shape, unison, sync", { O1_PD: 0.8, O1_Morph: 0.5, O1_MorphTo: 2, O2_PD: 0.5, O2_Morph: 1, O2_MorphTo: 4, U_Voices: 4, OscMix: 1 }, { tail: false });
    sounds ("osc shape, FM", { O1_PD: 0.6, O2_PD: 0.9, O2_Morph: 0.5, O2_Amp: 1, OscMix: 2 }, { tail: false });
    await flush ();
}

// the noise source, on the pitch and on the cutoff
const noise = ModMatrix.sourceIndex ("noise");
sounds ("noise > pitch", { Mod1_Source: noise, Mod1_Target: ModMatrix.targetIndex ("finePitch"), Mod1_Amount: 0.5 }, { tail: false });
sounds ("noise > cutoff", { Mod1_Source: noise, Mod1_Target: ModMatrix.targetIndex ("Cutoff"), Mod1_Amount: 0.3 }, { tail: false });

// Porridge's filter types, at a mid cutoff with some resonance
for (let t = FilterTypes.firstPorridge; t < FilterTypes.all.length; ++t)
    sounds (`filter ${t} ${FilterTypes.all[t]}`.slice (0, 24), { Filter: t, Cutoff: 0.45, Resonance: 0.6, F_Morph: 0.3, F_Drive: 0.3 }, { tail: false });
await flush ();

// the types the DSP runs as another's (FilterTypes): Sallen-Key is the SVF's lowpass (morph 0)
// with its own resonance law, peak 12 dB is B/P/B at the middle of its morph, whatever the morph
// knob says
{
    const voice = (name, sets) => render ({ program: prog, events, frames: rate, rate, sets: { Cutoff: 0.45, F_Morph: 0.3, ...sets },
                                           out: join (dir, `alias_${name}.f32`) })[0];
    const nullOf = (a, b) =>
    {
        let d = 0, s = 0;
        for (let i = 0; i < a.length; ++i) { d += (a[i] - b[i]) ** 2; s += a[i] * a[i]; }
        return 10 * Math.log10 ((d + 1e-30) / (s + 1e-30));
    };
    for (const res of [0.3, 0.9])
    {
        const sk = voice (`sk${res}`, { Filter: 19, Resonance: res });
        const svf = voice (`svf${res}`, { Filter: 16, Resonance: res * 1.98 / 1.96, F_Morph: 0 });
        check (nullOf (sk, svf) < -60, `Sallen-Key at resonance ${res} is the SVF's lowpass (null ${nullOf (sk, svf).toFixed (1)} dB)`);
        const peak = voice (`peak${res}`, { Filter: 24, Resonance: res });
        const bpb = voice (`bpb${res}`, { Filter: 30, Resonance: res, F_Morph: 0.5 });
        check (peak.every ((v, i) => v === bpb[i]), `peak 12 dB at resonance ${res} is B/P/B at its middle`);
    }
}

// mono legato with unison spread: the right side's filter envelopes start too (Oatmeal never
// starts them, and Oat mode keeps that, the right filter staying shut)
{
    const one = join (dir, "legato_events.txt");
    writeFileSync (one, "0 144 57 100\n22050 128 57 0\n");
    const init = join (root, "tools", "re", "init_prog.bin");
    const sides = oat =>
    {
        const [l, r] = render ({ program: init, events: one, frames: 22050, rate,
                                 sets: { PolyMode: 2, U_Voices: 4, U_Spread: 1, Filter: 3, Cutoff: 0.05, F_EnvMod: 1, F_Sustain: 1, Oat_Mode: oat },
                                 out: join (dir, `legato_${oat}.f32`) });
        const rms = x => Math.sqrt (x.slice (4410, 22050).reduce ((s, v) => s + v * v, 0) / 17640);
        return rms (r) / rms (l);
    };
    const fixed = sides (0), oat = sides (1);
    check (fixed > 0.7 && fixed < 1.4 && oat < 0.3, `legato stereo filter envelopes  R/L ${fixed.toFixed (2)}, in Oat mode ${oat.toFixed (2)}`);
}

done ("all ok");
