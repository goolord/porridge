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
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as FilterTypes from "../../ui/FilterTypes.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as DistTypes from "../../ui/DistTypes.res.mjs";
import * as SlotParams from "../../ui/SlotParams.res.mjs";
import { root, outDir, render, renderAsync, pool, levelAt, powerSpectrum, octaveBands, checker } from "./lib.mjs";

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
// (Porridge's own kinds' parameters: rack slot 5's, "Fl_On@5")
const inSlot5 = sets => Object.fromEntries (Object.entries (sets).map (([k, v]) => [PorridgeParams.isWorkId (k) ? k + "@5" : k, v]));
const sounds = (name, sets, opts) => queued.push (async () =>
    soundCheck (name, await renderAsync ({ program: prog, events, frames, rate, sets: inSlot5 (sets), out: join (dir, name.replace (/[^A-Za-z0-9]+/g, "_") + ".f32") }), opts));
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
                              Mod1_Target: SlotParams.targetOfParam ("Ai_Air@5"), Mod1_Amount: 0.5 }, { tail: true });
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

// the noise generator's types: each sounds, stays bounded and has a spectrum of its own (its
// octave bands 4 dB from every other type's somewhere); the colours keep white's level and tilt
// as they should; white ignores what only the others use (the density, a sample); the crackle
// grows with its density; the digital noise brightens up the keyboard; the metallic noise has
// the note's pitch and never aliases; the sample plays at its speed (the transpose), each note
// from a place of its own, and nothing until one is loaded; and every type through the resonance,
// with unison spread
{
    const init = join (root, "tools", "re", "init_prog.bin");
    const one = join (dir, "noise_events.txt");
    writeFileSync (one, "0 144 60 100\n88200 128 60 0\n");
    const quiet = { O1_Amp: 0, O2_Amp: 0, N_Amp: 0.5, Filter: 0, Oat_Mode: 0 };
    // the samples: a 1 kHz sine and white noise, 2 s at 48 kHz, as loud as the white noise
    const f32 = (name, f, n = 96000) =>
    {
        const b = Buffer.alloc (8 + 4 * n);
        b.writeInt32LE (1, 0); b.writeInt32LE (n, 4);
        for (let i = 0; i < n; ++i) b.writeFloatLE (f (i), 8 + 4 * i);
        const path = join (dir, name);
        writeFileSync (path, b);
        return path;
    };
    let seed = 1;
    const sine = f32 ("noise_sine.f32", i => 0.8165 * Math.sin (2 * Math.PI * 1000 * i / 48000));
    const hiss = f32 ("noise_hiss.f32", () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 1073741824 - 1);
    const noiseRender = (name, sets, { events = one, sample = sine } = {}) =>
        render ({ program: init, events, frames: 2 * rate, rate, sets: { ...quiet, ...sets }, args: sample ? ["--impulse", `2:48000:${sample}`] : [],
                  out: join (dir, name + ".f32") })[0];
    // two sends to one slot at once (the view's and the worker's can be), a chunk of each in turn:
    // the one whose first chunk came last is kept whole, and nothing of the other gets into it,
    // though the other is longer and its chunks go on after the kept one is complete
    {
        const short = f32 ("noise_short.f32", i => 0.8165 * Math.sin (2 * Math.PI * 300 * i / 48000), 5000);
        const sampleRender = (name, files) =>
            render ({ program: init, events: one, frames: rate, rate, sets: { ...quiet, N_Type: PorridgeParams.noiseTypes.indexOf ("sample") },
                      args: files.flatMap (p => ["--impulse", `2:48000:${p}`]), out: join (dir, name + ".f32") })[0];
        const alone = sampleRender ("noise_send_alone", [short]), mixed = sampleRender ("noise_send_mixed", [hiss, short]);
        const differ = alone.reduce ((n, v, i) => n + (v !== mixed[i]), 0);
        check (differ === 0 && alone.some (v => v !== 0), `two sends to the noise's sample at once keep the later one  ${differ} samples differ`);
    }
    const from = Math.round (0.2 * rate), to = Math.round (1.9 * rate);
    const rmsOf = x => { let s = 0; for (let i = from; i < to; ++i) s += x[i] * x[i]; return Math.sqrt (s / (to - from)); };
    const bandsOf = x => octaveBands (powerSpectrum (x, from, to), rate);
    // the bands' slope over 250 Hz .. 8 kHz, per Hz (white is flat), dB an octave
    const slope = b =>
    {
        const xs = [3, 4, 5, 6, 7, 8], ys = xs.map (i => b[i] - 10 * Math.log10 (2) * i);
        const mx = xs.reduce ((p, q) => p + q) / 6, my = ys.reduce ((p, q) => p + q) / 6;
        return xs.reduce ((p, x, i) => p + (x - mx) * (ys[i] - my), 0) / xs.reduce ((p, x) => p + (x - mx) ** 2, 0);
    };
    const types = PorridgeParams.noiseTypes;
    const renders = types.map ((name, t) => noiseRender (`noise_${name}`, { N_Type: t }));
    const bands = renders.map (bandsOf), levels = renders.map (x => 20 * Math.log10 (rmsOf (x) / rmsOf (renders[0])));
    const crests = renders.map (x => 20 * Math.log10 (x.slice (from, to).reduce ((m, v) => Math.max (m, Math.abs (v)), 0) / rmsOf (x)));
    renders.forEach ((x, t) =>
    {
        const peak = x.reduce ((m, v) => Math.max (m, Math.abs (v)), 0);
        check (x.every (Number.isFinite) && rmsOf (x) > 1e-4 && peak < 16,
               `noise ${types[t].padEnd (9)} level ${levels[t].toFixed (2).padStart (6)} dB, peak/RMS ${crests[t].toFixed (1).padStart (4)} dB, slope ${slope (bands[t]).toFixed (2).padStart (5)} dB/oct`);
    });
    // (by the octave bands' shape, and the peak over the RMS: the crackle is in its clicks)
    let closest = Infinity, pair = "";
    for (let a = 0; a < types.length; ++a)
        for (let b = a + 1; b < types.length; ++b)
        {
            const d = Math.max (Math.abs (crests[a] - crests[b]), ...bands[a].map ((v, i) => Math.abs (v - levels[a] - bands[b][i] + levels[b])));
            if (d < closest) { closest = d; pair = `${types[a]} and ${types[b]}`; }
        }
    check (closest > 4, `noise types told apart  closest: ${pair}, ${closest.toFixed (1)} dB apart`);
    [["pink", -3], ["brown", -6], ["blue", 3], ["violet", 6]].forEach (([name, want]) =>
    {
        const t = types.indexOf (name);
        check (Math.abs (slope (bands[t]) - want) < 0.5 && Math.abs (levels[t]) < 0.5, `noise ${name} tilts ${want} dB/oct at white's level`);
    });
    const plain = noiseRender ("noise_white_plain", { N_Density: 0.9 }, { sample: null });
    check (plain.every ((v, i) => v === renders[0][i]), "white noise ignores the density and the sample");
    const crackle = types.indexOf ("crackle");
    const sparse = rmsOf (noiseRender ("noise_crackle_sparse", { N_Type: crackle, N_Density: 0.1 }));
    const dense = rmsOf (noiseRender ("noise_crackle_dense", { N_Type: crackle, N_Density: 0.9 }));
    check (20 * Math.log10 (dense / sparse) > 15, `crackle grows with its density  +${(20 * Math.log10 (dense / sparse)).toFixed (1)} dB`);
    const keyed = (name, t, key) =>
    {
        const ev = join (dir, `noise_events_${key}.txt`);
        writeFileSync (ev, `0 144 ${key} 100\n88200 128 ${key} 0\n`);
        return noiseRender (`noise_${name}_${key}`, { N_Type: t }, { events: ev });
    };
    const centroid = x => { const P = powerSpectrum (x, from, to); let s = 0, w = 0; P.forEach ((p, k) => { s += p * k; w += p; }); return s / w * rate / 4096; };
    const digital = types.indexOf ("digital");
    const [low, high] = [48, 72].map (k => centroid (keyed ("digital", digital, k)));
    check (high > 1.5 * low, `digital noise brightens up the keyboard  ${low.toFixed (0)} Hz -> ${high.toFixed (0)} Hz`);
    const metallic = types.indexOf ("metallic");
    const m60 = keyed ("metallic", metallic, 60), f60 = 440 * 2 ** (-9 / 12);
    const onHarmonics = [1, 2, 3, 4, 5, 6].map (h => levelAt (m60, h * f60, 0.3, rate)), between = [1, 2, 3, 4, 5, 6].map (h => levelAt (m60, (h + 0.5) * f60, 0.3, rate));
    const tonal = onHarmonics.reduce ((a, b) => a + b) / 6 - between.reduce ((a, b) => a + b) / 6;
    check (tonal > 30, `metallic noise is the note's pitch  harmonics ${tonal.toFixed (1)} dB over what lies between them`);
    const m96 = keyed ("metallic", metallic, 96), P96 = powerSpectrum (m96, from, to), f96 = 440 * 2 ** (27 / 12);
    let under = 0, all = 0;
    P96.forEach ((p, k) => { all += p; if (k * rate / 4096 < 0.8 * f96) under += p; });
    check (10 * Math.log10 (under / all) < -60, `metallic noise doesn't alias at C7  ${(10 * Math.log10 (under / all)).toFixed (1)} dB under the note`);
    const sample = types.indexOf ("sample");
    const at1k = noiseRender ("noise_sample", { N_Type: sample }), at2k = noiseRender ("noise_sample_up", { N_Type: sample, N_Transpose: 12 });
    check (levelAt (at1k, 1000, 0.3, rate) - levelAt (at1k, 2000, 0.3, rate) > 40 && levelAt (at2k, 2000, 0.3, rate) - levelAt (at2k, 1000, 0.3, rate) > 40,
           "the sample plays at its speed, an octave up with the transpose at 12");
    check (noiseRender ("noise_sample_none", { N_Type: sample }, { sample: null }).every (v => v === 0), "the sample type is silent with no sample");
    const twice = join (dir, "noise_events_twice.txt");
    writeFileSync (twice, `0 144 60 100\n${rate / 2} 128 60 0\n${rate} 144 60 100\n${rate * 3 / 2} 128 60 0\n`);
    const again = noiseRender ("noise_sample_twice", { N_Type: sample }, { events: twice, sample: hiss });
    let ab = 0, aa = 0, bb = 0;
    for (let i = 2000; i < 6000; ++i) { const a = again[i], b = again[rate + i]; ab += a * b; aa += a * a; bb += b * b; }
    check (Math.abs (ab / Math.sqrt (aa * bb)) < 0.3, `each note starts the sample at a place of its own  correlation ${(ab / Math.sqrt (aa * bb)).toFixed (3)}`);
    // through the resonance, with unison spread: bounded; and a colour on a low note with strong
    // resonance starts at its full level, as white does (its band's level drawn, not rung up): the
    // first 50 ms of 16 notes against their last 300 ms (the band is a few Hz wide, so one note's
    // start is one draw of its level)
    const notes = 16, gap = Math.round (0.6 * rate);
    const lowEvents = join (dir, "noise_events_low.txt");
    writeFileSync (lowEvents, Array.from ({ length: notes }, (_, k) => `${k * gap} 144 36 100\n${k * gap + gap - 2000} 128 36 0\n`).join (""));
    const onset = t =>
    {
        const x = render ({ program: init, events: lowEvents, frames: notes * gap, rate, sets: { ...quiet, N_Type: t, N_Resonance: 0.8 },
                            out: join (dir, `noise_${types[t]}_onset.f32`) })[0];
        let a = 0, b = 0;
        for (let k = 0; k < notes; ++k)
        {
            for (let i = 441; i < 2646; ++i) a += x[k * gap + i] ** 2 / 2205;
            for (let i = gap - 2000 - 13230; i < gap - 2000; ++i) b += x[k * gap + i] ** 2 / 13230;
        }
        return 10 * Math.log10 (a / b);
    };
    const whiteOnset = onset (0);
    ["pink", "brown", "blue", "violet"].forEach (name =>
    {
        const d = onset (types.indexOf (name)) - whiteOnset;
        check (Math.abs (d) < 3, `resonant ${name} noise starts as white does  ${d.toFixed (1)} dB (white's start against its end ${whiteOnset.toFixed (1)} dB)`);
    });
    types.forEach ((name, t) =>
    {
        const [l, r] = render ({ program: init, events: one, frames: 2 * rate, rate, args: ["--impulse", `2:48000:${hiss}`],
                                 sets: { ...quiet, N_Type: t, N_Resonance: 0.7, U_Voices: 4, U_Spread: 1 }, out: join (dir, `noise_${name}_resonant.f32`) });
        const peak = Math.max (...[l, r].map (x => x.reduce ((m, v) => Math.max (m, Math.abs (v)), 0)));
        check ([l, r].every (x => x.every (Number.isFinite)) && peak > 1e-3 && peak < 16, `noise ${name.padEnd (9)} resonant, unison spread  peak ${peak.toFixed (3)}`);
    });
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

// the wheels' parameters (Wheel_Pitch, Wheel_Mod) play as channel 1's pitch bend and controller
// 1 do: the same render as the MIDI message at the same frame, with its timing (on its sample, or
// in Oat mode at the next block, or with MPE at the next piece), whatever MIDI_Channel_n let in;
// whichever moved last wins; and a value the wheel already has (as a host sends with a state)
// does nothing
{
    const init = join (root, "tools", "re", "init_prog.bin");
    const sine = { O1_Waveform: 0, O2_Amp: 0, N_Amp: 0, Filter: 0, PolyMode: 1, Attack: 0, Sustain: 1, Release: 0.01, VeloSens: 0,
                   RandomAmp: 0, RandomPan: 0, RandomFreq: 0, FX_Rack_1: 0, FX_Rack_2: 0, FX_Rack_3: 0, FX_Rack_4: 0 };
    let n = 0;
    // a note at 0 on a channel (1-based) and these events ([frame, "status d1 d2" or "Endpoint value"])
    const wheelRender = (lines, sets = {}, channel = 1) =>
    {
        const file = join (dir, `wheels_events${n}.txt`);
        writeFileSync (file, [[0, `${143 + channel} 69 100`], ...lines].map (([at, e]) => `${at} ${e}\n`).join (""));
        return render ({ program: init, events: file, frames: 22050, rate, sets: { ...sine, ...sets }, out: join (dir, `wheels${n++}.f32`) });
    };
    const same = (a, b) => a.every ((ch, c) => ch.every ((v, i) => v === b[c][i]));
    const plain = wheelRender ([]);
    // (bend 4096 of 8192: half way up)
    const bend = (at, half = 1) => [at, `224 0 ${64 + 32 * half}`];
    for (const [mode, sets] of [["", {}], [" in Oat mode", { Oat_Mode: 1 }], [" with MPE", { MPE_On: 1 }]])
    {
        const midi = wheelRender ([bend (5000)], sets);
        const wheel = wheelRender ([[5000, "Wheel_Pitch 0.5"]], sets);
        check (same (midi, wheel) && ! same (midi, wheelRender ([], sets)), `pitch wheel 0.5 is a MIDI bend of 4096${mode}`);
    }
    // (channel 1 shut, the note on channel 2: a bend there is channel 2's)
    const shut = { MIDI_Channel_1: 0, MIDI_Channel_2: 1 };
    check (same (wheelRender ([[5000, "Wheel_Pitch 0.5"]], shut, 2), wheelRender ([[5000, "225 0 96"]], shut, 2)),
           "pitch wheel bends with MIDI channel 1 shut");
    check (same (wheelRender ([bend (5000), [9000, "Wheel_Pitch -0.5"]]), wheelRender ([bend (5000), bend (9000, -1)])) &&
           same (wheelRender ([[5000, "Wheel_Pitch -0.5"], bend (9000)]), wheelRender ([bend (5000, -1), bend (9000)])),
           "pitch wheel and MIDI bend: whichever moved last wins");

    // the mod wheel on a connection from the mod wheel source, and on an Oatmeal controller slot
    // listening to CC 1, and as the X/Y pad's X controller
    const routes = [
        ["mod wheel source > volume", { Mod1_Source: ModMatrix.sourceIndex ("modWheel"), Mod1_Target: ModMatrix.targetIndex ("volume"), Mod1_Amount: -0.5 }],
        ["CC slot on CC 1 > pitch", { CC1: 1, CC1_Target_1: 5, CC1_Depth_1: 0.5 }],
        ["X/Y pad's X on CC 1 > pitch", { XY_H_CC: 1, XY_H_Target_1: 5, XY_H_Depth_1: 0.5, XY_X: 0.4 }],
    ];
    for (const [name, sets] of routes)
    {
        const midi = wheelRender ([[5000, "176 1 127"]], sets);
        const wheel = wheelRender ([[5000, "Wheel_Mod 1"]], sets);
        check (same (midi, wheel) && ! same (midi, wheelRender ([], sets)), `mod wheel 1 is CC 1 at 127: ${name}`);
    }
    check (same (wheelRender ([[0, "Wheel_Mod 0"], [0, "Wheel_Pitch 0"]], routes[2][1]), wheelRender ([], routes[2][1])),
           "the wheels at the values they have change nothing (the X/Y pad on CC 1 keeps its X)");
    check (same (plain, wheelRender ([[5000, "Wheel_Mod 1"]])), "the mod wheel with nothing on it changes nothing");
}

done ("all ok");
