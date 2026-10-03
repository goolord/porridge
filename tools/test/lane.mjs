// The voice lane (dsp/VoiceFx.cmajor): every kind it runs sounds, stays bounded and falls silent
// in each voice; the frequency shifter's ratio and the filter's tracking follow each note's key
// (and on the whole sound, the shifter's the newest note's); a resonator after
// the amp envelope rings on past its end (the voice lingers until it's quiet), one before it
// doesn't; moving the amp after a lane distortion changes what it hears. Renders through the
// test host.
//
//   node tools/test/lane.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/lane/.

import { join } from "node:path";
import { rackEntries } from "../../ui/PorridgeParams.res.mjs";
import { root, outDir, player, rms as rmsOf, levelAt, checker } from "./lib.mjs";

const dir = outDir ("lane");
const init = join (root, "tools", "re", "init_prog.bin");
const rate = 44100;
const { check, done } = checker ({ verbose: true });

const entry = (key, copy = 1) => rackEntries.findIndex (e => e && e[0] === key && e[1] === copy);

// a saw voice, nothing else
const plain = { O1_Waveform: 1, O2_Amp: 0, N_Amp: 0, Filter: 0, Voices: 16, PolyMode: 1, Attack: 0, Sustain: 1, Release: 50,
                VeloSens: 0, RandomAmp: 0, RandomPan: 0, RandomFreq: 0, FX_Rack_1: 0, FX_Rack_2: 0, FX_Rack_3: 0, FX_Rack_4: 0 };

const play = player ({ dir, program: init, base: plain, rate });
const rms = (x, a, b) => rmsOf (x, a, b, rate);
const at = (x, hz, from) => levelAt (x, hz, from, rate);

// every kind, after the amp (the default places): it sounds, stays bounded, the voices end
const chord = [[0, 48, 0.6], [0, 55, 0.6], [0, 64, 0.6]];
const kinds = [
    ["filter", "filter", { Ff_On: 1, Ff_Type: 17, Ff_Resonance: 0.7, Ff_Track: 1 }],
    ["distortion", entry ("distortion", 2), { Sat2_Type: 7, Sat2_Pregain: 18 }],
    ["eq", entry ("eq", 2), { EQ2_On: 1, EQ2_1_Type: 1, EQ2_1_Freq: 1000, EQ2_1_Amp: 12, EQ2_1_Slope: 1 }],
    ["phaser", "phaser", { Ph_On: 1, Ph_Feedback: 0.8 }],
    ["flanger", "flanger", { Fl_On: 1, Fl_Feedback: 0.9 }],
    ["utility", "utility", { Ut_On: 1, Ut_Pan: 0.5, Ut_Gain: -6 }],
    ["freq shifter", "bode", { Bd_On: 1, Bd_Ratio: 0.5, Bd_Mode: 2, Bd_Feedback: 0.8 }],
    ["resonator", "resonator", { Rs_On: 1, Rs_Decay: 0.8, Rs_Model: 4 }],
];
for (const [name, value, sets] of kinds)
{
    const fx = typeof value === "number" ? value : entry (value);
    const [l, r] = play (chord, { VL_1: fx, ...sets }, 4);
    let peak = 0, finite = true, last = 0;
    for (const ch of [l, r])
        for (let i = 0; i < ch.length; ++i)
        {
            if (! Number.isFinite (ch[i])) finite = false;
            const a = Math.abs (ch[i]);
            peak = Math.max (peak, a);
            if (a > 0) last = Math.max (last, i);
        }
    check (finite && peak > 1e-3 && peak < 16 && last < l.length - 1,
           `${name.padEnd (11)} in each voice: peak ${peak.toFixed (3)}, silent after ${(last / rate).toFixed (2)} s`);
}

// the lane's EQ runs in the voices: a 12 dB bell at 1 kHz lifts a saw's harmonic there (C3's
// 8th, 1046.5 Hz) by most of that, and leaves its fundamental
{
    const eq = { VL_1: entry ("eq", 2), EQ2_On: 1, EQ2_1_Type: 1, EQ2_1_Freq: 1046.5, EQ2_1_Amp: 12, EQ2_1_Slope: 1 };
    const [x] = play ([[0, 48, 1]], eq, 1);
    const [dry] = play ([[0, 48, 1]], {}, 1);
    const lift = at (x, 1046.5, 0.3) - at (dry, 1046.5, 0.3);
    const low = at (x, 130.8, 0.3) - at (dry, 130.8, 0.3);
    check (lift > 9 && Math.abs (low) < 1, `EQ in each voice: 1 kHz harmonic ${lift.toFixed (1)} dB, fundamental ${low.toFixed (1)} dB`);
}

// the frequency shifter's ratio follows the key: half the note up moves 220 Hz to 330 and 440 Hz
// to 660 (with 50 Hz more from the shift), in each voice, and on the whole sound for the newest note
for (const [where, slot] of [["in each voice", "VL_1"], ["on the whole sound", "FX_Rack_5"]])
{
    const shift = Math.cbrt (50 / 5000);
    const sine = { O1_Waveform: 0, [slot]: entry ("bode"), Bd_On: 1, Bd_Ratio: Math.cbrt (0.25), Bd_Shift: shift, Bd_Mix: 1 };
    const [a] = play ([[0, 57, 1]], sine, 1);
    const [b] = play ([[0, 69, 1]], sine, 1);
    const lowGain = at (a, 380, 0.3) - at (a, 220, 0.3);
    const highGain = at (b, 710, 0.3) - at (b, 440, 0.3);
    check (lowGain > 30 && highGain > 30,
           `freq shifter ${where}: 220 Hz → 380 Hz (${lowGain.toFixed (1)} dB over 220), 440 Hz → 710 Hz (${highGain.toFixed (1)} dB over 440)`);
}

// the filter's tracking: a lowpass at middle C tracking fully takes a note's 4th harmonic down by
// the same amount an octave up; without tracking, the higher note's loses more
{
    const lp = (track, key) =>
    {
        const f = 440 * 2 ** ((key - 69) / 12);
        const [x] = play ([[0, key, 1]], { VL_1: entry ("filter"), Ff_On: 1, Ff_Type: 3, Ff_Cutoff: Math.log (261.63 / 20) / Math.log (1000), Ff_Track: track }, 1);
        const [dry] = play ([[0, key, 1]], {}, 1);
        return at (x, 4 * f, 0.3) - at (dry, 4 * f, 0.3);
    };
    const t0 = lp (1, 60), t1 = lp (1, 72), n0 = lp (0, 60), n1 = lp (0, 72);
    check (Math.abs (t1 - t0) < 2 && n1 - n0 < -6, `filter tracking: 4th harmonic ${t0.toFixed (1)} / ${t1.toFixed (1)} dB tracking, ${n0.toFixed (1)} / ${n1.toFixed (1)} dB without`);
}

// a resonator after the amp rings on after the note ends; before it, the amp ends it
{
    const res = { VL_1: entry ("resonator"), Rs_On: 1, Rs_Decay: 0.6, Rs_Mix: 1, Release: 20 };
    const after = play ([[0, 57, 0.3]], { ...res, VL_AmpAt: 0 }, 2);
    const before = play ([[0, 57, 0.3]], { ...res, VL_AmpAt: 1 }, 2);
    const a = rms (after, 0.6, 0.8), b = rms (before, 0.6, 0.8);
    let last = 0;
    for (let i = 0; i < after[0].length; ++i) if (after[0][i] !== 0) last = i;
    check (a > 1e-4 && b < 1e-6 && last < after[0].length - 1,
           `resonator after the amp rings on (${a.toExponential (2)} 0.3 s after), before it doesn't (${b.toExponential (2)}); the voice ends at ${(last / rate).toFixed (2)} s`);
}

// a lane distortion before the amp hears the full level; after the amp's release it's quieter
{
    const dist = { VL_1: entry ("distortion", 2), Sat2_Type: 2, Sat2_Pregain: 24, Release: 400 };
    const late = play ([[0, 57, 0.3]], { ...dist, VL_AmpAt: 1 }, 1);
    const early = play ([[0, 57, 0.3]], { ...dist, VL_AmpAt: 0 }, 1);
    const l1 = rms (late, 0.45, 0.55), l0 = rms (early, 0.45, 0.55);
    check (Math.abs (l1 / l0 - 1) > 0.1, `the amp after a lane distortion changes its release: ${l1.toFixed (4)} vs ${l0.toFixed (4)}`);
}

// the resonator's gain sets its ringing's level apart from the mix: +12 dB is four times as loud
{
    const res = { VL_1: entry ("resonator"), Rs_On: 1, Rs_Mix: 1 };
    const flat = rms (play ([[0, 57, 0.5]], res, 0.5), 0.1, 0.4);
    const loud = rms (play ([[0, 57, 0.5]], { ...res, Rs_Gain: 12 }, 0.5), 0.1, 0.4);
    check (Math.abs (20 * Math.log10 (loud / flat) - 12) < 0.3, `resonator gain +12 dB: ${(20 * Math.log10 (loud / flat)).toFixed (2)} dB louder`);
}

done ("voice lane ok");
