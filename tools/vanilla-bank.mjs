// Builds presets/vanilla.porridge, Porridge's own preset bank: 64 programs made for the features
// Oatmeal doesn't have (per-voice distortion and panning driven by the modulation matrix, the
// voice lane's effects in every note, LFO 3 and wander, the oscillators' own envelopes, the key
// EQ, the distortion models, the HQ waveforms, PM/ring/AM, Porridge's filter types, envelope
// curves, the LFO extras, unison width, drift, the effects rack and its own effects, macros, MPE
// and microtuning) and for Oatmeal's that its own programs use most (drawn waveforms and the XY
// pad), plus programs after Oatmeal's own factory bank and some in the style of modern bass
// music. Every program moves: something evolves within each note and something varies from note
// to note, and the instruments (the drums aside) answer velocity, the mod wheel and aftertouch.
//
// Each program lists only what differs from Init. The bank goes through Preset.res, so the
// values are clamped and written exactly as the plugin writes them. Reverb is kept for the
// sounds that want a space (pads, bells, the harp); the rest get at most a little delay.
//
// run: npm run res && node tools/vanilla-bank.mjs
//      (then node tools/test/levels.mjs to measure the output gains below)

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../ui/Preset.res.mjs";
import * as FilterTypes from "../ui/FilterTypes.res.mjs";
import * as FxRack from "../ui/FxRack.res.mjs";
import * as PorridgeParams from "../ui/PorridgeParams.res.mjs";
import { choiceValue } from "../ui/ParamDefs.res.mjs";
import * as OatmealParams from "../ui/oatmeal/OatmealParams.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");
const author = "Porridge";

//==============================================================================
// helpers

// list values: short names here for the labels a parameter's list has (ParamDefs.choiceValue)
const choices = (id, labels) => Object.fromEntries (Object.entries (labels).map (([k, label]) => [k, choiceValue (id, label)]));
const wave = choices ("O1_Waveform", { sine: "Sine", saw: "Oatmeal saw", pulse: "Oatmeal pulse", tri: "Oatmeal triangle",
                                       user: "User", userPwm: "User PWM", sawHQ: "Saw", pulseHQ: "Pulse", triHQ: "Triangle" });
const mix = choices ("OscMix", { normal: "normal", sync: "hardsync", fm: "FM (1 -> 2, 1 silent)", pm: "PM 2 > 1",
                                 pmFeedback: "PM 1 feedback", ring: "ring 1 × 2", am: "AM 2 > 1" });
const filter = Object.fromEntries (Object.entries ({
    off: "off", lp2: "2P lowpass", lp4: "4P lowpass", hp2: "2P highpass", hp4: "4P highpass", bpWide: "2P wide bandpass",
    bp: "2P narrow bandpass", nlLp4: "nonlinear 4P lowpass", svf: "SVF LP > BP > HP", ladder: "ladder", diode: "diode ladder",
    sallenKey: "Sallen-Key", comb: "comb", formant: "formant", mgLow12: "MG low 12", mgDirty: "MG dirty",
    acid: "acid ladder", cleanDrive: "clean drive", combPlus: "comb +", formant1: "formant I", formant2: "formant II",
    formant3: "formant III",
}).map (([k, name]) => [k, FilterTypes.index (name)]));
const dist = choices ("Sat_Type", { off: "off", hard: "hard clip", soft: "soft clip", sine: "sine", asym: "asymmetric",
                                    tube: "tube", tape: "tape", saturate: "saturate", wavefold: "wavefold",
                                    bassAmp: "bass amp", guitarAmp: "guitar amp", lofi: "lo-fi sampler" });
const distMode = choices ("Sat_Mode", { global: "global", voicePost: "per voice, after filter",
                                        voicePre: "per voice, before filter", double: "double (before filter and global)" });
const lfoUnit = choices ("LFO_1_Unit", { ms: "ms", ms10: "10 ms", sec: "sec", sixteenth: "16ths", eighthTriplet: "2/3 8ths",
                                         eighth: "8ths", quarter: "quarter notes", half: "half notes", whole: "whole notes" });
const lfoShape = choices ("LFO_1_Shape", { sine: "Sine", saw: "Saw", square: "Square", tri: "Triangle",
                                           smoothRandom: "Smooth random", steppingRandom: "Stepping random", user: "User" });
const lfoMode = choices ("LFO_1_Sync", { perNote: "per note", globalReset: "global, reset on note", globalFree: "global, free" });
const steps = choices ("LFO_1_Steps", { off: "off", 2: "2", 3: "3", 4: "4", 6: "6", 8: "8", 12: "12", 16: "16", 24: "24", 32: "32" });
const delayUnit = choices ("D_Unit", { ms: "ms", sixteenth: "16ths", eighth: "8ths", quarter: "quarter notes" });
const poly = choices ("PolyMode", { mono: "Monophonic", poly: "Polyphonic", legato: "Monophonic, legato" });
// Oatmeal's own mod envelope targets (M1_Target_N, M2_Target_N), by the names the view gives them
// (OatmealParams.targetName)
const mTarget = choices ("M1_Target_1", { cutoff1: "cutoff", cutoff2: "filter split", resonance: "resonance",
                                          amp1: "osc 1 level", amp2: "osc 2 level", noiseAmp: "noise level",
                                          pitch1: "osc 1 pitch", pitch2: "osc 2 transpose", pw1: "osc 1 pulse width",
                                          pwmRate1: "osc 1 pwm rate", pwmDepth1: "osc 1 pwm depth",
                                          pw2: "osc 2 pulse width", lfo1Depth: "LFO 1 depth", lfo2Depth: "LFO 2 depth",
                                          filterMix: "filter mix" });

// osc 2's transpose is in octaves
const ratio = r => Math.log2 (r);
const semis = s => s / 12;

// envelopes: { a, h, d1, bp, d2, s, r } in ms and levels
const env = (prefix, e) => {
    const p = {};
    const set = (k, x) => { if (x !== undefined) p[prefix + k] = x; };
    set ("Attack", e.a); set ("Hold", e.h); set ("Decay1", e.d1); set ("Breakpoint", e.bp);
    set ("Decay2", e.d2); set ("Sustain", e.s); set ("Release", e.r);
    return p;
};
const amp = e => env ("", e);
const fenv = e => env ("F_", e);
const menv1 = e => env ("M1_", e);
const menv2 = e => env ("M2_", e);

// a list value by its name above
const pick = (list, name) =>
{
    if (name !== undefined && ! (name in list)) throw new Error ("no list value " + name);
    return list[name];
};

// an LFO: { sync, shape, unit } by the names in lfoMode, lfoShape and lfoUnit, and speed
const lfo = (n, { sync, shape, unit, speed }) => {
    const p = {};
    const set = (k, x) => { if (x !== undefined) p[`LFO_${n}_${k}`] = x; };
    set ("Sync", pick (lfoMode, sync)); set ("Shape", pick (lfoShape, shape)); set ("Unit", pick (lfoUnit, unit));
    set ("Speed", speed);
    return p;
};

// the delay, on: { unit } by its name in delayUnit, { length, feedback } for both sides or as
// [left, right], and wet
const delay = ({ unit, length, feedback, wet }) => {
    const p = { D_On: 1 };
    const lr = (k, x) => { if (x !== undefined) [p[k + "L"], p[k + "R"]] = Array.isArray (x) ? x : [x, x]; };
    if (unit !== undefined) p.D_Unit = pick (delayUnit, unit);
    lr ("D_Length", length); lr ("D_Feedback", feedback);
    p.D_Wet = wet;
    return p;
};

const mod = (source, target, amount, via) => via ? { source, target, amount, via } : { source, target, amount };

// the effects rack, slot by slot, by the names in its menu (with FX_Order, which orders the slots
// holding Oatmeal's four); Oatmeal's chorus, delay, reverb and EQ stay in their slots unless
// they're left out, or do nothing there (see the end)
const rack = (...names) => Object.fromEntries (FxRack.values (names.map (name =>
{
    const e = FxRack.ofValue (PorridgeParams.rackNames.indexOf (name));
    if (! e) throw new Error ("no rack entry " + name);
    return e;
})));

// the voice lane: effects in every voice, slot by slot by the names in its menu, and how many of
// them come before the filter and before the amp envelope (the rest come after the amp, and
// ring on after it)
const lane = (names, { filterAt = 0, ampAt = filterAt } = {}) => ({
    ...Object.fromEntries (names.map ((name, i) =>
    {
        const k = PorridgeParams.rackNames.indexOf (name);
        if (k < 0) throw new Error ("no rack entry " + name);
        return [PorridgeParams.laneId (i + 1), k];
    })),
    VL_FilterAt: filterAt, VL_AmpAt: ampAt,
});

// knob positions of the rack effects' frequencies and times (lo · (hi / lo) ^ knob)
const knob = (lo, hi) => x => PorridgeParams.expPos (lo, hi, x);
const hz = knob (20, 20000);
const fxRate = knob (0.02, 20);
const compAttack = knob (0.1, 300), compRelease = knob (5, 3000);
const flangerMs = knob (0.1, 20), bodeMs = knob (1, 1000), reverbSeconds = knob (0.1, 30);
const resonatorMs = knob (10, 10000);
const lfo3Hz = knob (0.02, 50), wanderHz = knob (0.02, 10);
// the shifter's ratio knob for a fraction of the note (2 · knob³)
const shiftRatio = r => Math.sign (r) * Math.cbrt (Math.abs (r) / 2);
const resonatorModel = choices ("Rs_Model", { harmonic: "harmonic", odd: "odd", fifths: "fifths", bar: "bar", bell: "bell", membrane: "membrane" });
const shifterMode = choices ("Sh_Mode", { up: "up", down: "down", stereo: "stereo (L up, R down)", ring: "ring" });

// LFO 3 (only the matrix reaches it): { shape, mode, sync } by the names in its lists, rate in
// Hz, random phase, and delay and fade-in in ms
const lfo3Shape = choices ("LFO_3_Shape", { sine: "Sine", tri: "Triangle", sawUp: "Saw", sawDown: "Saw down", square: "Square",
                                            sampleHold: "Stepping random", smoothRandom: "Smooth random" });
const lfo3Mode = choices ("LFO_3_Mode", { perVoice: "per-voice", sharedReset: "shared, reset on note", sharedFree: "shared, free" });
const lfo3Sync = choices ("LFO_3_Sync", { free: "free", bar: "1 bar", half: "1/2", quarter: "1/4", eighth: "1/8", sixteenth: "1/16" });
const lfo3 = ({ shape, mode, sync, rate, phaseRand, delay, fade }) => {
    const p = {};
    const set = (k, x) => { if (x !== undefined) p["LFO_3_" + k] = x; };
    set ("Shape", pick (lfo3Shape, shape)); set ("Mode", pick (lfo3Mode, mode)); set ("Sync", pick (lfo3Sync, sync));
    set ("Rate", rate === undefined ? undefined : lfo3Hz (rate)); set ("PhaseRand", phaseRand); set ("Delay", delay); set ("Fade", fade);
    return p;
};

// an oscillator's own envelope (its level follows it, under the amp envelope)
const oscEnv = (n, e) => ({ [`OE${n}_On`]: 1, ...env (`OE${n}_`, e) });

// the key EQ: gains (dB) of its eight bands, on the note's harmonics 1 (a low shelf), 2, 4 ... 128
const keyEq = gains => ({ KEQ_On: 1, ...Object.fromEntries (gains.map ((g, i) => [`KEQ_${i + 1}_Gain`, g])) });

// the XY pad's routes, Oatmeal's: { x: [[target, depth], ...], y: [...] } by the names in its
// target list (depths -1..1: the cutoffs in units of 4 octaves, levels of 60 dB, the rest of their
// range), and its random walk { radius 0..1, rate Hz } around where the pad sits
// (by Oatmeal's own names, which stay put while the menu words them its own way)
const xyTarget = Object.fromEntries (Object.entries ({ cutoff1: "cutoff 1", cutoff2: "cutoff 2", resonance: "resonance",
                                             envMod: "filter env mod", pitch: "pitch", pan: "pan", distortion: "distortion",
                                             lfo1Speed: "LFO 1 speed", lfo2Speed: "LFO 2 speed", lfo1Depth: "LFO 1 depth",
                                             lfo2Depth: "LFO 2 depth", amp2: "2 amp", noiseAmp: "noise amp",
                                             filterMix: "filter mix", me1Depth: "ME 1 depth" })
    .map (([k, name]) => [k, OatmealParams.xyTargets.indexOf (name)]));
const xy = ({ x = [], y = [], walk }) => ({
    ...Object.fromEntries ([["H", x], ["V", y]].flatMap (([axis, routes]) => routes.flatMap (([target, depth], i) =>
        [[`XY_${axis}_Target_${i + 1}`, pick (xyTarget, target)], [`XY_${axis}_Depth_${i + 1}`, depth]]))),
    ...(walk ? { XY_Var_Radius: walk.radius, XY_Var_Rate: walk.rate } : {}),
});
const bodeHz = PorridgeParams.bodeShiftValue;
const bassMono = PorridgeParams.bassMonoValue;
const impulse = name => PorridgeParams.impulseNames.indexOf (name);
const reverbModel = choices ("Rv_Model", { hall: "hall", plate: "plate", nitrous: "nitrous", basin: "basin", vintage: "vintage" });
const eqType = choices ("EQ_1_Type", { off: "off", peak: "peak/notch", lowShelf: "low shelf", highShelf: "high shelf" });

// a gentle single-band compressor: just downward compression above the threshold
const glue = (thresh, ratio, attack, release, makeup) => ({
    Cp_On: 1, Cp_Bands: 0, Cp_MidThresh: thresh, Cp_MidRatio: ratio, Cp_MidUpRatio: 1,
    Cp_Attack: compAttack (attack), Cp_Release: compRelease (release), Cp_OutGain: makeup,
});

// a single-cycle wave from harmonics [n, level, phase (cycles)], peak-normalised
const harmonics = list => {
    const w = new Float32Array (512);
    for (let i = 0; i < 512; ++i)
        for (const [n, a, ph = 0] of list)
            w[i] += a * Math.sin (2 * Math.PI * (n * i / 512 + ph));
    const peak = w.reduce ((m, x) => Math.max (m, Math.abs (x)), 0);
    return w.map (x => x / peak);
};

const base64 = f32 => Buffer.from (new Uint8Array (f32.buffer.slice (0))).toString ("base64");

// 5-limit just intonation on C
const justScale = `! just-12.scl
5-limit just intonation, 12 notes
 12
 16/15
 9/8
 6/5
 5/4
 4/3
 45/32
 3/2
 8/5
 5/3
 9/5
 15/8
 2/1
`;

//==============================================================================
// the programs

const programs = [

//------------------------------------------------------------------ keys
{
    name: "Felt Piano", category: "keys", tags: ["piano", "analog filter", "convolution", "compressor", "tremolo"],
    description: "A soft, close felt piano: triangle and sine through an MG lowpass whose envelope follows "
        + "velocity, two strings a few cents apart beating against each other, and a felt thump of pitched noise "
        + "on each hammer. Every note is tuned and voiced a little differently, high notes get less of the "
        + "filter envelope, and the whole thing breathes slowly in tone and position. A gentle compressor and a "
        + "small convolved room. Mod wheel: a Rhodes-style tremolo that pans each note; aftertouch opens the "
        + "felt. Macros: hammer, tone, room.",
    macros: ["hammer", "tone", "room", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.22, VeloSens: 0.8,
        U_Voices: 2, U_Detune: 3, U_Spread: 0.35,
        N_Resonance: 0.7, N_Transpose: 12,
        Filter: filter.mgLow12, Cutoff: 0.36, Resonance: 0.08, F_Track: 0.7, F_EnvMod: 0.3, F_VeloSens: 0.7,
        ...fenv ({ a: 0.5, bp: 1, d2: 700, s: 0.12, r: 300 }), Curve_Filter_Decay: 0.4,
        ...amp ({ a: 1.5, d1: 500, bp: 0.45, d2: 11000, s: 0, r: 380 }),
        ...menv2 ({ a: 0.3, bp: 1, d2: 120, s: 0, r: 40 }),
        ...lfo (1, { sync: "globalFree", unit: "sec", speed: 7 }),
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 17 }), LFOPhaseRand: 1,
        Drift_Pitch: 2,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Compressor", "Convolve"),
        ...glue (-22, 2.5, 15, 160, 3),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.12, Cv_LowCut: hz (150),
    },
    modulations: [
        mod ("modEnv2", "N_Amp", 0.38),
        mod ("velocity", "N_Amp", 0.08),
        mod ("velocity", "Cutoff", 0.08),
        mod ("key", "F_EnvMod", -0.08),
        mod ("random", "finePitch", 0.04),
        mod ("random", "Cutoff", 0.03),
        mod ("lfo1", "Cutoff", 0.03),
        mod ("lfo1", "pan", 0.06),
        mod ("lfo2", "volume", 0.35, "modWheel"),
        mod ("lfo2", "pan", 0.6, "modWheel"),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "F_EnvMod", 0.15),
        mod ("macro1", "N_Amp", 0.1),
        mod ("macro2", "Cutoff", 0.2),
        mod ("macro3", "Cv_Mix", 0.3),
    ],
},
{
    name: "Crunch Clav", category: "keys", tags: ["clavinet", "per-voice drive", "funk", "auto-wah"],
    description: "A clavinet with an asymmetric drive in front of each note's filter. Each pluck sweeps the "
        + "state-variable filter from bandpass back towards lowpass, like an envelope-following wah, harder "
        + "notes sweeping further; every note is picked at its own spot on the string (pulse width) and the "
        + "pulse slowly moves. Notes spread across the stereo field by key. Mod wheel: a quarter-note wah; "
        + "aftertouch: resonance. Macros: bite, cutoff, wah.",
    macros: ["bite", "cutoff", "wah", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.22, O1_PWM_R: 0.7, O1_PWM_D: 0.12,
        O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.35,
        Filter: filter.svf, F_Morph: 0.2, Cutoff: 0.33, Resonance: 0.4, F_Track: 0.5, F_EnvMod: 0.4, F_VeloSens: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 260, s: 0.1, r: 80 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 0.4, bp: 1, d2: 1400, s: 0.15, r: 90 }), Curve_Amp_Decay: 0.4,
        ...lfo (1, { sync: "globalReset", shape: "tri", unit: "quarter", speed: 1 }),
        LFO_1_Quantize: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePre, Sat_Pregain: 6, Sat_Postgain: -6,
        RandomPan: 0.15,
        ...delay ({ unit: "ms", length: [70, 95], feedback: 0.15, wet: 0.08 }),
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.2),
        mod ("key", "pan", 0.9),
        mod ("filterEnv", "F_Morph", 0.45),
        mod ("filterEnv", "F_Morph", 0.15, "velocity"),
        mod ("random", "O1_PWM_W", 0.08),
        mod ("random", "Cutoff", 0.03),
        mod ("lfo1", "Cutoff", 0.18, "modWheel"),
        mod ("lfo1", "Cutoff", 0.15, "macro3"),
        mod ("aftertouch", "Resonance", 0.25),
        mod ("macro1", "Sat_Pregain", 0.25),
        mod ("macro2", "Cutoff", 0.3),
    ],
},
{
    name: "Rotary Fold", category: "organ", tags: ["organ", "wavefolder", "per-voice pan", "rotary"],
    description: "A drawbar organ through a sine wavefolder on every voice, with a Hammond-style percussion "
        + "(a third harmonic that strikes and dies away, harder with velocity) and a short key click. Each note "
        + "has its own rotor: a panning, slightly detuning LFO from a random phase, over a slower shared drum "
        + "rotor that sways the tone and level. The mod wheel (or macro 2) speeds the rotors up; aftertouch "
        + "growls into the folder. Macros: fold, rotor speed, rotor depth, percussion.",
    macros: ["fold", "rotor speed", "rotor depth", "percussion"],
    params: {
        O1_Waveform: wave.user, O2_Waveform: wave.sine, Transpose: ratio (3), O2_Amp: 0, VeloSens: 0,
        N_Resonance: 0.6, N_Transpose: 24,
        ...amp ({ a: 3, bp: 1, s: 1, r: 45 }),
        ...menv1 ({ a: 0.5, bp: 1, d2: 900, s: 0, r: 60 }),
        ...menv2 ({ a: 0.2, bp: 1, d2: 30, s: 0, r: 10 }),
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -11,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 40 }), LFO_1_Pan: 0.3, LFO_1_Pitch: 0.22,
        LFOPhaseRand: 1, LFO_1_Slew: 0.3,
        ...lfo (2, { sync: "globalFree", unit: "ms10", speed: 55 }),
        FreqPan: 0.05, Drift_Pitch: 3,
        C_Mode: 1, C_Mix: 0.25,
        Macro_3: 0.4, Macro_4: 0.6,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.55, "macro4"),
        mod ("modEnv1", "O2_Amp", 0.08, "velocity"),
        mod ("modEnv2", "N_Amp", 0.3),
        mod ("lfo2", "Cutoff", 0.03),
        mod ("lfo2", "volume", 0.08),
        mod ("lfo2", "LFO_1_Pan", 0.1),
        mod ("modWheel", "LFO_1_Speed", -0.07),
        mod ("modWheel", "LFO_2_Speed", -0.06),
        mod ("macro2", "LFO_1_Speed", -0.07),
        mod ("macro2", "LFO_2_Speed", -0.06),
        mod ("aftertouch", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.13),
        mod ("macro3", "LFO_1_Pan", 0.4),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.7], [3, 0.5], [4, 0.45], [6, 0.3], [8, 0.3], [10, 0.12], [12, 0.15]]) },
},

{
    name: "Pulse Organ", category: "organ", tags: ["organ", "User PWM", "cross-modulated LFOs"],
    description: "After Oatmeal's organ blergh: a drawbar wave played as a pulse (User PWM), its width "
        + "pushed open by a slow mod envelope on each chord and slowly modulated, so the drawbars seem to "
        + "move. Two vibrato-and-pan LFOs modulate each other's depth, so the wobble never repeats, and a "
        + "short key click starts each note. Low shelves warm the body. Mod wheel: faster LFOs, like a rotor "
        + "speeding up; aftertouch: drive. Macros: drawbars, click, wobble.",
    macros: ["drawbars", "click", "wobble", ""],
    params: {
        O1_Waveform: wave.userPwm, O1_PWM_W: 0.4, O1_PWM_R: 0.51, O1_PWM_D: 0.08, VeloSens: 0,
        N_Resonance: 0.6, N_Transpose: 24,
        ...amp ({ a: 4, bp: 1, s: 1, r: 60 }),
        ...menv2 ({ a: 0.2, bp: 1, d2: 30, s: 0, r: 10 }),
        M1_Attack: 865, M1_Decay2: 2130, M1_Sustain: 0.2, M1_Release: 650,
        M1_Target_1: mTarget.pw1, M1_Depth_1: 0.17, M1_Target_2: mTarget.pwmDepth1, M1_Depth_2: -0.12,
        ...lfo (1, { unit: "ms10", speed: 22.6 }), LFO_1_Pitch: 0.25, LFO_1_Pan: 0.064, LFO_1_2: 0.085,
        ...lfo (2, { shape: "tri", unit: "ms10", speed: 40 }), LFO_2_Pitch: 0.2, LFO_2_Pan: 0.084, LFO_2_1: 0.079,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost,
        C_Mode: 4, C_Stereo: 1, C_Voices: 3, C_Rate: 0.032, C_Mix: 0.5,
        EQ_1_Type: eqType.lowShelf, EQ_1_Freq: 768, EQ_1_Amp: -10, EQ_2_Type: eqType.lowShelf, EQ_2_Freq: 362, EQ_2_Amp: 6,
        Macro_3: 0.5,
    },
    modulations: [
        mod ("modEnv2", "N_Amp", 0.3, "macro2"),
        mod ("random", "O1_PWM_W", 0.05),
        mod ("modWheel", "LFO_1_Speed", -0.06),
        mod ("modWheel", "LFO_2_Speed", -0.06),
        mod ("aftertouch", "Sat_Pregain", 0.12),
        mod ("macro1", "O1_PWM_W", 0.25),
        mod ("macro3", "LFO_1_Pitch", 0.1),
        mod ("macro3", "LFO_2_Pan", 0.2),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.8], [3, 0.6], [4, 0.5], [6, 0.35], [8, 0.4], [10, 0.1], [12, 0.12]]) },
},
{
    name: "Blorb Pulse", category: "keys", tags: ["pulse", "PWM", "highpass", "unison"],
    description: "After Oatmeal's blorb: two pulse-width-modulated pulses an octave apart, retriggered on "
        + "every note, through a resonant highpass whose envelope starts high and falls, so each note blooms "
        + "from a thin, bright blip into a full pulse. A random LFO per note keeps the highpass breathing and "
        + "every note's pulse width is its own. Mod wheel: resonance; aftertouch: thinner. Macros: blorb, width.",
    macros: ["blorb", "width", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.23, O1_PWM_R: 0.31, O1_PWM_D: 0.2,
        O2_Waveform: wave.pulseHQ, O2_Amp: 0.88, O2_PWM_W: 0.75, O2_PWM_R: 0.72, O2_PWM_D: -0.23, Transpose: -1,
        OscPhaseRand: 0, OscRetrig: 1, PWMPhaseRand: 0, PWMRetrig: 1,
        U_Voices: 4, U_Detune: 4, U_Spread: 0.33,
        Filter: filter.hp4, Cutoff: 0.27, Resonance: 0.54, F_Track: 1, F_EnvMod: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 4000, s: 0.01, r: 1800 }),
        ...amp ({ a: 2, bp: 1, d2: 9000, s: 0.4, r: 900 }),
        LFO_1_Pitch: 0.2,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "ms10", speed: 69 }),
        LFO_2_Cutoff_1: 0.2,
        C_Mode: 4, C_Stereo: 1, C_Feedback: -0.6, C_Mix: 0.5,
        RandomPan: 0.17,
        R_On: 1, R_Size: 52, R_Length: 3.2, R_Dullness: 0.6, R_Wet: 0.12,
    },
    modulations: [
        mod ("random", "O1_PWM_W", 0.08),
        mod ("random", "O2_PWM_W", 0.08),
        mod ("velocity", "F_EnvMod", 0.08),
        mod ("key", "F_EnvMod", -0.06),
        mod ("modWheel", "Resonance", 0.3),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "F_EnvMod", 0.2),
        mod ("macro2", "O1_PWM_D", 0.2),
        mod ("macro2", "O2_PWM_D", -0.2),
    ],
},
{
    name: "Phase Keys", category: "keys", tags: ["electric piano", "voice lane", "phaser", "osc envelopes", "key EQ", "tube"],
    description: "An electric piano in which every note has a phaser of its own: each starts its sweep at a random "
        + "point and higher notes sweep faster, so a chord shimmers several ways at once instead of all together. "
        + "The tine is a drawn wave two octaves up with its own envelope, a bark that dies away within a quarter "
        + "second, over a sine body; a tube model on each voice growls when you play hard, and the key EQ keeps "
        + "every note's upper harmonics soft. Mod wheel: a stereo tremolo; aftertouch: a deeper phaser. Macros: "
        + "phase, bark, tremolo, tone.",
    macros: ["phase", "bark", "tremolo", "tone"],
    params: {
        O1_Waveform: wave.sine, O2_Waveform: wave.user, Transpose: 2, O2_Amp: 0.6, VeloSens: 0.6,
        ...oscEnv (2, { a: 0.2, bp: 1, d2: 250, s: 0.06, r: 100 }), Curve_Osc2_Decay: 0.3,
        Filter: filter.lp2, Cutoff: 0.6, Resonance: 0.05, F_Track: 0.6, F_EnvMod: 0.15, F_VeloSens: 0.6,
        ...fenv ({ a: 0.5, bp: 1, d2: 1500, s: 0.3, r: 300 }),
        ...amp ({ a: 1, bp: 1, d2: 6000, s: 0, r: 350 }), Curve_Amp_Decay: 0.3,
        Sat_Type: dist.tube, Sat_Mode: distMode.voicePost, Sat_Drive: 0.3, Sat_Postgain: -12,
        ...lane (["Phaser"]),
        Ph_On: 1, Ph_Rate: fxRate (0.6), Ph_Depth: 0.55, Ph_Freq: hz (900), Ph_Feedback: 0.4, Ph_Stages: 1,
        Ph_Track: 0.5, Ph_Mix: 0.5, Ph_PhaseRand: 1, Ph_RateTrack: 0.5,
        ...keyEq ([0, 1.5, 0, -2, -4, -6, -8, -8]),
        ...lfo (1, { sync: "globalFree", unit: "ms10", speed: 18 }),
        Voices: 12,
        ...rack ("Ambience", "Delay"),
        Am_On: 1, Am_Model: 0, Am_Size: 0.3, Am_Mix: 0.2,
        ...delay ({ unit: "eighth", length: [3, 4], feedback: 0.25, wet: 0.06 }),
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.2),
        mod ("velocity", "Ph_Feedback", 0.15),
        mod ("random", "Ph_Freq", 0.08),
        mod ("random", "finePitch", 0.03),
        mod ("key", "O2_Amp", -0.15),
        mod ("lfo1", "volume", 0.35, "modWheel"),
        mod ("lfo1", "pan", 0.5, "modWheel"),
        mod ("lfo1", "volume", 0.35, "macro3"),
        mod ("lfo1", "pan", 0.5, "macro3"),
        mod ("aftertouch", "Ph_Depth", 0.3),
        mod ("aftertouch", "Ph_Feedback", 0.15),
        mod ("macro1", "Ph_Mix", 0.4),
        mod ("macro2", "O2_Amp", 0.2),
        mod ("macro4", "Cutoff", 0.3),
    ],
    tables: { wave2: harmonics ([[1, 1], [2, 0.4], [3, 0.25], [5, 0.12]]) },
},

//------------------------------------------------------------------ pads
{
    name: "Oat Field", category: "pad", tags: ["supersaw", "unison", "drift", "wide", "evolving", "XY pad"],
    description: "Seven-voice HQ supersaw with a supersaw-style detune curve, random unison phases and extra "
        + "stereo width, slowly drifting in pitch and cutoff like an old polysynth. Each chord opens slowly; "
        + "the detune breathes in and out over eleven seconds while a second slow LFO moves the cutoff, and "
        + "every note gets its own detune and brightness. The XY pad: X opens the filter, Y adds resonance. Mod "
        + "wheel: resonance; aftertouch: brighter and wider. Macros: brightness, width, drift.",
    macros: ["brightness", "width", "drift", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: -1, O2_Amp: 0.45,
        U_Voices: 7, U_Detune: 32, U_DetuneCurve: 0.7, U_RandomPhase: 1, U_Spread: 0.9, U_Width: 1.5, U_PanJitter: 0.3,
        Filter: filter.svf, Cutoff: 0.38, Resonance: 0.12, F_Track: 0.5,
        ...amp ({ a: 900, bp: 1, s: 1, r: 2600 }), Curve_Amp_Attack: -0.3, Curve_Amp_Release: 0.3,
        ...menv1 ({ a: 3500, bp: 1, s: 1, r: 2600 }), Curve_Mod1_Attack: -0.3,
        Drift_Pitch: 6, Drift_Cutoff: 1.5, Drift_Rate: 0.3, RandomPan: 0.3,
        ...lfo (1, { sync: "globalFree", shape: "tri", unit: "sec", speed: 11 }),
        ...lfo (2, { sync: "globalFree", unit: "sec", speed: 5 }),
        R_On: 1, R_Size: 65, R_Length: 3.5, R_Wet: 0.14, R_Dullness: 0.6,
        ...xy ({ x: [["cutoff1", 0.4]], y: [["resonance", 0.6]] }),
    },
    modulations: [
        mod ("modEnv1", "Cutoff", 0.12),
        mod ("lfo1", "U_Detune", 0.025),
        mod ("lfo2", "Cutoff", 0.09),
        mod ("lfo2", "F_Morph", 0.15),
        mod ("random", "U_Detune", 0.012),
        mod ("random", "Cutoff", 0.04),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "Resonance", 0.35),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("aftertouch", "U_Width", 0.15),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "U_Width", 0.25),
        mod ("macro3", "Drift_Pitch", 0.3),
    ],
},
{
    name: "Solina Phase", category: "pad", tags: ["string machine", "phaser", "ensemble", "vibrato"],
    description: "A string machine: two saws an octave apart through a soft MG lowpass, a three-voice ensemble "
        + "chorus, then the rack's phaser sweeping slowly with some feedback. Each chord brightens as it's "
        + "bowed, the octaves trade places slowly in every note, a vibrato fades in on held notes and each note "
        + "is a few cents off. Mod wheel: a faster, deeper phaser; aftertouch: brighter, more vibrato. Macros: "
        + "phase, ensemble, brightness.",
    macros: ["phase", "ensemble", "brightness", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 1, Detune: 0.4, O2_Amp: 0.55,
        Filter: filter.mgLow12, Cutoff: 0.5, Resonance: 0.05, F_Track: 0.5,
        ...amp ({ a: 350, bp: 1, s: 1, r: 1100 }), Curve_Amp_Attack: -0.2, Curve_Amp_Release: 0.3,
        ...menv1 ({ a: 1800, bp: 1, s: 1, r: 1100 }),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 17 }), LFO_1_Pitch: 0.3,
        LFO_1_Delay: 700, LFO_1_Fade: 1500,
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 5 }), LFOPhaseRand: 1,
        Drift_Pitch: 4, RandomPan: 0.2,
        ...rack ("Chorus", "Phaser", "Delay", "Reverb", "EQ"),
        C_Mode: 1, C_Stereo: 2, C_Voices: 3, C_Rate: 0.7, C_MinDelay: 5, C_Depth: 4, C_Mix: 0.5,
        Ph_On: 1, Ph_Rate: fxRate (0.12), Ph_Depth: 0.75, Ph_Freq: hz (700), Ph_Feedback: 0.45, Ph_Stages: 1,
        Ph_Spread: 0.4, Ph_Mix: 0.5,
        R_On: 1, R_Size: 55, R_Length: 2.2, R_Wet: 0.1,
        Macro_1: 0.5, Macro_2: 0.5,
    },
    modulations: [
        mod ("modEnv1", "Cutoff", 0.12),
        mod ("lfo2", "O2_Amp", 0.08),
        mod ("lfo2", "Cutoff", 0.03),
        mod ("random", "finePitch", 0.04),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "Ph_Rate", 0.2),
        mod ("modWheel", "Ph_Feedback", 0.2),
        mod ("aftertouch", "Cutoff", 0.12),
        mod ("aftertouch", "LFO_1_Pitch", 0.08),
        mod ("macro1", "Ph_Mix", 0.3),
        mod ("macro1", "Ph_Feedback", 0.15),
        mod ("macro2", "C_Mix", 0.25),
        mod ("macro3", "Cutoff", 0.25),
    ],
},
{
    name: "Stereo Swarm", category: "pad", tags: ["per-voice pan", "motion", "ambient"],
    description: "Every note lives its own life. A per-note LFO circles it around the stereo field from a "
        + "random phase, higher notes orbit faster and each note at its own speed. A random LFO per note wanders "
        + "its pitch, cutoff, position and osc balance, every note is detuned by its own few cents, and a slow "
        + "envelope opens some notes and closes others. Mod wheel: wider orbits; aftertouch: resonance. Macros: "
        + "orbit, orbit speed, brightness, wander.",
    macros: ["orbit", "orbit speed", "brightness", "wander"],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.7, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.4, Resonance: 0.2, F_Track: 0.4,
        ...amp ({ a: 1200, bp: 1, s: 1, r: 3200 }), Curve_Amp_Attack: -0.4, Curve_Amp_Release: 0.4,
        ...menv1 ({ a: 4000, bp: 1, s: 1, r: 3000 }),
        ...lfo (1, { sync: "perNote", unit: "sec", speed: 3 }), LFO_1_Pan: 0.42,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 2 }),
        LFO_2_Cutoff_1: 0.12, LFO_2_Pan: 0.12, LFOPhaseRand: 1,
        R_On: 1, R_Size: 70, R_Length: 3.5, R_Wet: 0.13,
        ...delay ({ unit: "eighth", length: [3, 4], feedback: 0.4, wet: 0.1 }),
        Macro_4: 0.5,
    },
    modulations: [
        mod ("key", "LFO_1_Speed", -0.06),
        mod ("random", "LFO_1_Speed", 0.025),
        mod ("random", "LFO_2_Speed", 0.03),
        mod ("random", "finePitch", 0.07),
        mod ("random", "Detune", 0.015),
        mod ("lfo2", "finePitch", 0.08, "macro4"),
        mod ("lfo2", "O2_Amp", 0.12, "macro4"),
        mod ("modEnv1", "Cutoff", 0.14, "random"),
        mod ("modWheel", "LFO_1_Pan", 0.3),
        mod ("aftertouch", "Resonance", 0.35),
        mod ("macro1", "LFO_1_Pan", 0.3),
        mod ("macro2", "LFO_1_Speed", -0.05),
        mod ("macro3", "Cutoff", 0.3),
    ],
},
{
    name: "Warm Wool", category: "pad", tags: ["ladder", "per-voice drive", "analog", "PWM"],
    description: "Soft saturation in front of each note's ladder filter, so the filter rounds off the drive. "
        + "Osc 2 is a warm harmonic wave played as a pulse (User PWM), its width swept by its own PWM and by a "
        + "slow per-note LFO, so the harmonics comb and shift inside every note; a shared random LFO makes the "
        + "fuzz breathe. Each note is tuned and filtered a little differently. Play harder for more fuzz. Mod "
        + "wheel: resonance; aftertouch: drive and cutoff. Macros: warmth, cutoff, movement.",
    macros: ["warmth", "cutoff", "movement", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.userPwm, O2_PWM_W: 0.4, O2_PWM_R: 0.3, O2_PWM_D: 0.3,
        Transpose: 0, Detune: -0.6, O2_Amp: 0.7,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePre, Sat_Pregain: 10, Sat_Postgain: -8,
        Filter: filter.ladder, Cutoff: 0.3, Resonance: 0.35, F_Track: 0.4, F_EnvMod: 0.15,
        ...fenv ({ a: 1500, bp: 1, d2: 3000, s: 0.6, r: 1500 }),
        ...amp ({ a: 600, bp: 1, s: 0.9, r: 1800 }), Curve_Amp_Attack: -0.4,
        ...lfo (1, { sync: "perNote", shape: "tri", unit: "sec", speed: 4 }), LFOPhaseRand: 1,
        ...lfo (2, { sync: "globalFree", shape: "smoothRandom", unit: "sec", speed: 3 }),
        Drift_Cutoff: 2, Drift_Pitch: 4, RandomPan: 0.35,
        C_Mode: 1, C_Mix: 0.4, R_On: 1, R_Size: 50, R_Length: 2, R_Wet: 0.09,
        Macro_3: 0.6,
    },
    modulations: [
        mod ("lfo1", "O2_PWM_W", 0.3, "macro3"),
        mod ("lfo1", "Cutoff", 0.1, "macro3"),
        mod ("lfo2", "Sat_Pregain", 0.05),
        mod ("random", "Cutoff", 0.05),
        mod ("random", "finePitch", 0.04),
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("modWheel", "Resonance", 0.3),
        mod ("aftertouch", "Sat_Pregain", 0.1),
        mod ("aftertouch", "Cutoff", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "Cutoff", 0.3),
    ],
    tables: { wave2: harmonics ([[1, 1], [2, 0.6], [3, 0.45], [4, 0.32], [5, 0.25], [6, 0.2], [7, 0.15], [8, 0.12], [10, 0.08], [12, 0.05]]) },
},
{
    name: "Vowel Choir", category: "pad", tags: ["formant", "choir", "per-voice motion", "breath"],
    description: "Formant filter voices: each note starts on its own vowel and wanders between vowels with "
        + "its own random LFO, breathes a little noise through the formants as it starts, and is sung a few "
        + "cents off the others; the vibrato fades in after a moment (LFO delay and fade-in). Mod wheel: more "
        + "vibrato; aftertouch: opens the vowels. Macros: vowel, wander, breath.",
    macros: ["vowel", "wander", "breath", ""],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 3, U_Detune: 12, U_Spread: 0.6,
        O2_Waveform: wave.pulseHQ, Transpose: 0, Detune: 0.4, O2_Amp: 0.3,
        Filter: filter.formant, Cutoff: 0.37, Resonance: 0.3, F_Track: 0.4, F_Morph: 0.3,
        ...amp ({ a: 500, bp: 1, s: 1, r: 1600 }), Curve_Amp_Attack: -0.3,
        ...menv2 ({ a: 150, bp: 1, d2: 900, s: 0.2, r: 600 }),
        ...lfo (1, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 3 }),
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 19 }), LFO_2_Pitch: 0.33,
        LFO_2_Delay: 400, LFO_2_Fade: 900, LFOPhaseRand: 1,
        RandomPan: 0.6, FreqPan: 0.08,
        C_Mode: 1, C_Mix: 0.35, R_On: 1, R_Size: 75, R_Length: 3, R_Wet: 0.17,
        Macro_2: 0.7, Macro_3: 0.5,
    },
    modulations: [
        mod ("random", "F_Morph", 0.15),
        mod ("random", "finePitch", 0.06),
        mod ("lfo1", "F_Morph", 0.4, "macro2"),
        mod ("lfo1", "Cutoff", 0.03),
        mod ("modEnv2", "N_Amp", 0.4, "macro3"),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "LFO_2_Pitch", 0.12),
        mod ("aftertouch", "Cutoff", 0.08),
        mod ("aftertouch", "F_Morph", 0.15),
        mod ("macro1", "F_Morph", 0.6),
    ],
},
{
    name: "Comb String", category: "pad", tags: ["comb", "karplus", "bowed", "vibrato"],
    description: "Noise bowing a comb filter tuned to each note, with a little saw for body: a bowed string "
        + "that changes character with the comb's feedback polarity (macro 2). The bow noise is tuned to the "
        + "note and its pressure wavers on its own in every note; a vibrato on the comb's tuning fades in, and a "
        + "high shelf keeps the hiss off the top. Mod wheel: more vibrato; aftertouch: bow harder. Macros: "
        + "resonance, polarity, air.",
    macros: ["resonance", "polarity", "air", ""],
    params: {
        O1_Amp: 0.12, O1_Waveform: wave.sawHQ, N_Amp: 0.5, N_Resonance: 0.3,
        Filter: filter.comb, Cutoff: 0.276, F_Track: 1, Resonance: 0.9, F_Morph: 0,
        ...amp ({ a: 250, bp: 1, s: 1, r: 1800 }), Curve_Amp_Attack: -0.2,
        ...lfo (1, { sync: "perNote", shape: "smoothRandom", unit: "ms10", speed: 60 }),
        LFO_1_Pan: 0.15, LFOPhaseRand: 1,
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 18 }), LFO_2_Cutoff_1: 0.005, LFO_2_Pitch: 0.3,
        LFO_2_Delay: 500, LFO_2_Fade: 1000,
        RandomPan: 0.5,
        FX_Order: 2, R_On: 1, R_Size: 65, R_Length: 3, R_Wet: 0.12,
        ...delay ({ unit: "eighth", length: 3, feedback: 0.4, wet: 0.1 }),
        EQ_1_Type: eqType.highShelf, EQ_1_Freq: 3500, EQ_1_Amp: -8,
    },
    modulations: [
        mod ("lfo1", "N_Amp", 0.06),
        mod ("lfo1", "Resonance", 0.015),
        mod ("lfo2", "Cutoff", 0.003, "modWheel"),
        mod ("random", "Resonance", 0.01),
        mod ("velocity", "N_Amp", 0.05),
        mod ("aftertouch", "N_Amp", 0.08),
        mod ("aftertouch", "N_Resonance", -0.15),
        mod ("macro1", "Resonance", 0.09),
        mod ("macro2", "F_Morph", 1),
        mod ("macro3", "N_Resonance", -0.3),
        mod ("macro3", "EQ_1_Amp", 0.06),
    ],
},

{
    name: "Grit Bloom", category: "pad", tags: ["per-voice drive", "per-voice pan", "voice lane", "phaser", "evolving"],
    description: "A clean pad that grows grit: a slow mod envelope raises each note's distortion drive and "
        + "cutoff, and moves the note out from the centre, each one to its own random side. As it blooms the "
        + "filter's resonance rises and a slow per-note LFO starts sweeping that peak through the upper "
        + "harmonics, every note at its own phase, while a high phaser fades in, one in every voice, starting "
        + "its sweep at a random point and drifting in pitch on its own. Mod wheel: faster phasers; aftertouch: "
        + "more grit. Macros: grit, bloom, shimmer.",
    macros: ["grit", "bloom", "shimmer", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: semis (7), O2_Amp: 0.4,
        Filter: filter.svf, Cutoff: 0.33, Resonance: 0.2, F_Track: 0.4,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: -6,
        ...menv1 ({ a: 2600, bp: 1, s: 1, r: 2000 }), Curve_Mod1_Attack: -0.3,
        ...amp ({ a: 380, bp: 1, s: 1, r: 2200 }), Curve_Amp_Attack: -0.2,
        ...lfo (2, { sync: "perNote", shape: "tri", unit: "sec", speed: 3.5 }), LFOPhaseRand: 1,
        ...lane (["Phaser"]),
        Ph_On: 1, Ph_Rate: fxRate (0.13), Ph_Depth: 0.6, Ph_Freq: hz (2500), Ph_Feedback: 0.6, Ph_Stages: 3,
        Ph_Spread: 0.6, Ph_Mix: 0, Ph_PhaseRand: 1,
        Wander_Rate: wanderHz (0.2),
        R_On: 1, R_Size: 55, R_Length: 2.5, R_Wet: 0.1,
        ...delay ({ unit: "eighth", length: [3, 4], feedback: 0.35, wet: 0.07 }),
        Macro_2: 1, Macro_3: 0.6,
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.22, "macro2"),
        mod ("modEnv1", "Sat_Postgain", -0.05, "macro2"),
        mod ("modEnv1", "Cutoff", 0.15, "macro2"),
        mod ("modEnv1", "pan", 0.8, "random"),
        mod ("modEnv1", "Resonance", 0.5, "macro3"),
        mod ("modEnv1", "F_Morph", 0.2, "macro3"),
        mod ("lfo2", "Cutoff", 0.1, "modEnv1"),
        mod ("modEnv1", "Ph_Mix", 0.8, "macro3"),
        mod ("wander", "Ph_Freq", 0.08),
        mod ("random", "finePitch", 0.05),
        mod ("random", "Detune", 0.01),
        mod ("modWheel", "Ph_Rate", 0.25),
        mod ("aftertouch", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},

{
    name: "Speckle Pad", category: "pad", tags: ["User PWM", "sample & hold", "ping-pong", "tape stop"],
    description: "After Oatmeal's padmeh: a User PWM wave over a sine two octaves down, through two parallel "
        + "lowpasses that a smooth random LFO and a stepping random LFO move independently, so every note "
        + "speckles and wanders on its own; the filter envelope closes them slowly as the chord settles. Notes "
        + "fan out by pitch and at random, sag in pitch as they're released, and a cross-feeding delay throws "
        + "echoes from side to side. Mod wheel: faster speckles; aftertouch: brighter. Macros: speckle, "
        + "brightness, echo.",
    macros: ["speckle", "brightness", "echo", ""],
    params: {
        O1_Waveform: wave.userPwm, O1_PWM_W: 0.24, O2_Waveform: wave.sine, O2_Amp: 0.56, Transpose: -2,
        Filter: filter.lp4, Cutoff: 0.46, Resonance: 0.39, F_Track: 1, F_Double: 1, F_EnvMod: -0.28,
        ...fenv ({ a: 1565, bp: 1, d2: 690, s: 1, r: 437 }),
        ...amp ({ a: 586, bp: 1, d2: 125, s: 0.5, r: 2980 }),
        ...lfo (1, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 4 }),
        LFO_1_Cutoff_1: 0.435, LFO_1_Cutoff_2: 0.41,
        ...lfo (2, { sync: "perNote", shape: "steppingRandom", unit: "ms10", speed: 57 }),
        LFO_2_Cutoff_1: 0.4, LFO_2_Cutoff_2: 0.35, LFO_2_Resonance: 0.04, LFO_2_Slew: 0.3, LFOPhaseRand: 1,
        PEnv_On: 1, PEnv_Start: 0, PEnv_Attack: 714, PEnv_Peak: 0, PEnv_Decay: 2169, PEnv_Sustain: 0, PEnv_Release: -3.3,
        FreqPan: 0.2, RandomPan: 0.39,
        C_Mode: 4, C_Stereo: 2, C_Voices: 6, C_Rate: 0.0016, C_MinDelay: 0.22, C_Depth: 2, C_Mix: 0.7,
        ...delay ({ length: [6, 3], feedback: [-0.6, 0.7], wet: 0.15 }), D_InputPan: 0.48,
        D_Rotation: -2.19, D_LP: 0.9, D_HP: 0.05,
        R_On: 1, R_Size: 58, R_Length: 2, R_Dullness: 0.84, R_Predelay: 65, R_Wet: 0.14,
        Macro_1: 0.5,
    },
    modulations: [
        mod ("random", "finePitch", 0.05),
        mod ("random", "O1_PWM_W", 0.08),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "LFO_2_Speed", -0.08),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "LFO_1_Cutoff_1", 0.15),
        mod ("macro1", "LFO_2_Cutoff_1", 0.15),
        mod ("macro2", "Cutoff", 0.2),
        mod ("macro3", "D_Wet", 0.15),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.35], [3, 0.5], [5, 0.3], [7, 0.2], [9, 0.12], [11, 0.06]]) },
},
{
    name: "Highpass Haze", category: "pad", tags: ["User PWM", "highpass", "slow", "evolving"],
    description: "After Oatmeal's sworg: two User PWM waves an octave apart, each with its own slow PWM, "
        + "through a resonant highpass that a slow envelope pulls up and lets back down, so the chord thins out "
        + "into a hazy top and fills in again. A mod envelope widens osc 1's pulse over seven seconds and "
        + "another lowers the cutoff; every note is a little apart in tune, and a slow LFO per note rocks the "
        + "balance of the two waves. Mod wheel: resonance; aftertouch: more haze. Macros: haze, glow.",
    macros: ["haze", "glow", "", ""],
    params: {
        O1_Waveform: wave.userPwm, O1_PWM_R: 0.765, O1_PWM_D: -0.08,
        O2_Waveform: wave.userPwm, O2_Amp: 0.6, O2_PWM_W: 0.31, O2_PWM_R: 0.26, O2_PWM_D: 0.064, Transpose: -1,
        Filter: filter.hp4, Cutoff: 0.24, Resonance: 0.55, F_Track: 0.98, F_EnvMod: 0.51,
        ...fenv ({ a: 3478, bp: 1, d2: 4560, s: 0.5, r: 3489 }),
        ...amp ({ a: 1487, bp: 1, s: 1, r: 2218 }),
        M1_Attack: 2014, M1_Decay2: 7772, M1_Sustain: 0.16, M1_Release: 996, M1_Target_1: mTarget.pw1, M1_Depth_1: 0.42,
        M2_Attack: 2377, M2_Decay2: 4000, M2_Sustain: 0.5, M2_Release: 439, M2_Target_1: mTarget.cutoff1, M2_Depth_1: -0.3,
        ...lfo (1, { sync: "perNote", unit: "sec", speed: 5 }), LFOPhaseRand: 1,
        Voices: 32, RandomPan: 0.05,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Oversample: 1,
        C_Mode: 4, C_Stereo: 1, C_Depth: 34, C_Feedback: 0.35,
        ...delay ({ unit: "eighth", length: 3, wet: 0.12 }), D_Rotation: 0.2, D_LP: 0.87, D_HP: 0.32,
        R_On: 1, R_Length: 4, R_Wet: 0.12,
        EQ_3_Type: eqType.peak, EQ_3_Freq: 6438, EQ_3_Amp: -12, EQ_3_Slope: 0.185,
        EQ_4_Type: eqType.peak, EQ_4_Freq: 11500, EQ_4_Amp: 8, EQ_4_Slope: 3.3,
    },
    modulations: [
        mod ("random", "finePitch", 0.05),
        mod ("lfo1", "O2_Amp", 0.08),
        mod ("lfo1", "Cutoff", 0.02),
        mod ("velocity", "F_EnvMod", 0.06),
        mod ("modWheel", "Resonance", 0.3),
        mod ("aftertouch", "Cutoff", 0.1),
        mod ("macro1", "F_EnvMod", 0.2),
        mod ("macro2", "EQ_4_Amp", 0.06),
    ],
    tables: {
        wave1: harmonics ([[1, 1], [2, 0.2], [4, 0.3], [8, 0.25], [16, 0.12]]),
        wave2: harmonics ([[1, 1], [3, 0.4], [5, 0.25], [7, 0.15]]),
    },
},
{
    name: "Drive Dog", category: "pad", tags: ["per-voice drive", "parallel filters", "evolving", "swell"],
    description: "After Oatmeal's sparklydog: a saw and a square an octave down, heavily driven on each voice "
        + "after two parallel resonant lowpasses two octaves apart. A mod envelope crossfades from the lower "
        + "filter to the upper one as the note opens, a slower one swells the square in over two seconds, and a "
        + "slow per-note LFO spreads the two filters apart and back. Mod wheel: resonance; aftertouch: more "
        + "drive. Macros: drive, bark, swell.",
    macros: ["drive", "bark", "swell", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, O2_Amp: 0, Transpose: -1,
        Filter: filter.lp4, Cutoff: 0.3, Resonance: 0.745, F_Double: 1, F_Mix: 0, F_Split: 1, F_EnvMod: 0.22,
        ...fenv ({ a: 456, bp: 1, d2: 2474, s: 0.04, r: 800 }),
        ...amp ({ a: 40, bp: 1, s: 1, r: 900 }),
        M1_Attack: 398, M1_Sustain: 0.16, M1_Target_1: mTarget.filterMix, M1_Depth_1: 1,
        M2_Attack: 2374, M2_Sustain: 1, M2_Release: 1579, M2_Target_1: mTarget.amp2, M2_Depth_1: 1, M2_Target_2: mTarget.amp2,
        M2_Depth_2: 1,
        ...lfo (1, { sync: "perNote", shape: "tri", unit: "sec", speed: 4 }), LFOPhaseRand: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 25, Sat_Postgain: -16,
        RandomPan: 0.3,
        R_On: 1, R_Size: 45, R_Length: 1.8, R_Wet: 0.08,
    },
    modulations: [
        mod ("lfo1", "F_Split", 0.15),
        mod ("random", "Cutoff", 0.04),
        mod ("random", "finePitch", 0.04),
        mod ("velocity", "F_EnvMod", 0.08),
        mod ("modWheel", "Resonance", 0.2),
        mod ("aftertouch", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.12),
        mod ("macro2", "Resonance", 0.2),
        mod ("macro2", "F_EnvMod", 0.1),
        mod ("macro3", "O2_Amp", 0.1),
    ],
},
{
    name: "Ghost Tide", category: "pad", tags: ["PWM", "FM chorus", "evolving", "filter envelope"],
    description: "After Oatmeal's ghrutenbngtb: a pulse that opens from nothing into a square as a mod "
        + "envelope widens it, with a triangle two octaves up fading in alongside, through a filter that starts "
        + "wide open and closes over four seconds while a wobble on it grows in over the same time, all through "
        + "a slow FM chorus. Every note is a few cents off, and a random LFO per note moves it around. Mod "
        + "wheel: a faster wobble; aftertouch: opens the filter back up. Macros: tide, wobble.",
    macros: ["tide", "wobble", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0, O1_PWM_R: 0.93, O1_PWM_D: 0.07,
        O2_Waveform: wave.triHQ, O2_Amp: 0, Transpose: 2,
        Filter: filter.lp2, Cutoff: 1, Resonance: 0.52, F_Track: 1, F_Speed: 3, F_EnvMod: -0.65,
        ...fenv ({ a: 4035, bp: 1, s: 1, r: 1721 }),
        ...amp ({ a: 120, bp: 1, s: 1, r: 900 }),
        M1_Attack: 355, M1_Sustain: 1, M1_Release: 556,
        M1_Target_1: mTarget.pw1, M1_Depth_1: 0.43, M1_Target_2: mTarget.amp2, M1_Depth_2: 1,
        M2_Attack: 4668, M2_Sustain: 1, M2_Target_1: mTarget.lfo1Depth, M2_Depth_1: 1,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 44.6 }), LFO_1_Cutoff_1: 0.14,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom" }), LFO_2_Pan: 0.24, LFO_2_1: 0.13,
        LFOPhaseRand: 1,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 7.7,
        C_Mode: 3, C_Stereo: 2, C_Voices: 3, C_Rate: 0.023, C_Depth: 12.4, C_Mix: 0.8,
        R_On: 1, R_Size: 55, R_Length: 2.5, R_Wet: 0.1,
    },
    modulations: [
        mod ("random", "finePitch", 0.05),
        mod ("random", "LFO_1_Speed", 0.03),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "LFO_1_Speed", -0.08),
        mod ("aftertouch", "Cutoff", 0.25),
        mod ("macro1", "F_EnvMod", -0.15),
        mod ("macro2", "LFO_1_Cutoff_1", 0.2),
    ],
},
{
    name: "Future Chords", category: "pad", tags: ["supersaw", "sidechain pump", "future bass", "OTT"],
    description: "Future-bass chords: a seven-voice supersaw and an octave above, every chord scooping up "
        + "into pitch, with a filter envelope on each stab. A drawn quarter-note duck pumps the volume like a "
        + "sidechain from the chord's first beat, the detune breathes slowly, each note is a few cents apart, "
        + "and the three-band compressor squashes it OTT-style. Mod wheel: a vibrato wobble on the whole chord; "
        + "aftertouch: brighter. Macros: pump, brightness, squash, wobble.",
    macros: ["pump", "brightness", "squash", "wobble"],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 7, U_Detune: 25, U_DetuneCurve: 0.6, U_RandomPhase: 1, U_Spread: 0.9,
        U_Width: 1.4,
        O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.35,
        Filter: filter.ladder, Cutoff: 0.48, Resonance: 0.15, F_Track: 0.5, F_EnvMod: 0.25, F_VeloSens: 0.4,
        ...fenv ({ a: 1, bp: 1, d2: 600, s: 0.5, r: 400 }),
        ...amp ({ a: 4, bp: 1, s: 1, r: 350 }),
        PEnv_On: 1, PEnv_Start: -1.5, PEnv_Attack: 70, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        ...lfo (1, { sync: "globalReset", shape: "user", unit: "quarter", speed: 1 }),
        LFO_1_Quantize: 1,
        ...lfo (2, { sync: "globalFree", unit: "ms10", speed: 22 }),
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ"),
        C_Mode: 1, C_Stereo: 2, C_Mix: 0.3,
        Cp_On: 1, Cp_Depth: 0.5, Cp_Attack: compAttack (5), Cp_Release: compRelease (120), Cp_Mix: 0.7,
        ...delay ({ unit: "eighth", length: 3, feedback: 0.3, wet: 0.08 }),
        Macro_1: 1, Macro_3: 0.5,
    },
    modulations: [
        mod ("lfo1", "volume", 0.48, "macro1"),
        mod ("lfo1", "Cutoff", 0.05, "macro1"),
        mod ("lfo2", "finePitch", 0.35, "modWheel"),
        mod ("lfo2", "finePitch", 0.35, "macro4"),
        mod ("random", "finePitch", 0.05),
        mod ("velocity", "Cutoff", 0.05),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro2", "Cutoff", 0.25),
        mod ("macro3", "Cp_Depth", 0.5),
    ],
    // a sidechain duck: silent on the beat, back up by the next (LFO shapes are 0..1)
    tables: { lfoShape1: Float32Array.from ({ length: 512 }, (_, i) => 1 - Math.exp (-7 * i / 511)) },
},
{
    name: "Tuned Jets", category: "pad", tags: ["voice lane", "flanger", "wander", "XY pad", "User"],
    description: "A flanger in every voice whose delay follows the note's period, so with its feedback it rings at the "
        + "note, a string drawn out into a jet. Each note's flanger starts at its own point of its sweep and sweeps "
        + "faster the higher it plays, and its feedback wanders on its own, so the notes of a chord swell and hollow "
        + "out apart. Under it, a drawn wave rich in odd harmonics, a saw an octave up and a little breath. The XY "
        + "pad: X opens the filter, Y adds resonance, with a slow random walk. Mod wheel: more ring; "
        + "aftertouch: brighter. Macros: jet, ring, air, wander.",
    macros: ["jet", "ring", "air", "wander"],
    params: {
        O1_Waveform: wave.user, O2_Waveform: wave.sawHQ, Transpose: 1, Detune: 0.5, O2_Amp: 0.3, N_Amp: 0.08,
        Filter: filter.mgLow12, Cutoff: 0.42, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 700, bp: 1, s: 1, r: 2500 }), Curve_Amp_Attack: -0.3, Curve_Amp_Release: 0.3,
        ...lane (["Flanger"]),
        Fl_On: 1, Fl_Rate: fxRate (0.15), Fl_Depth: 0.08, Fl_Delay: flangerMs (1000 / 261.63), Fl_Feedback: 0.65,
        Fl_Mix: 0.5, Fl_Track: 1, Fl_RateTrack: 0.5, Fl_PhaseRand: 1,
        Wander_Rate: wanderHz (0.25),
        ...xy ({ x: [["cutoff1", 0.35]], y: [["resonance", 0.4]], walk: { radius: 0.2, rate: 0.4 } }),
        Drift_Pitch: 3,
        ...rack ("Chorus", "Reverb"),
        C_Mode: 1, C_Stereo: 2, C_Mix: 0.3,
        R_On: 1, R_Size: 65, R_Length: 3.2, R_Wet: 0.13, R_Dullness: 0.6,
        Macro_4: 0.6,
    },
    modulations: [
        mod ("wander", "Fl_Feedback", 0.12, "macro4"),
        mod ("wander", "Cutoff", 0.05),
        mod ("random", "Fl_Depth", 0.04),
        mod ("random", "finePitch", 0.04),
        mod ("velocity", "Cutoff", 0.06),
        mod ("velocity", "Fl_Mix", 0.1),
        mod ("modWheel", "Fl_Feedback", 0.15),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "Fl_Mix", 0.3),
        mod ("macro2", "Fl_Feedback", 0.2),
        mod ("macro3", "N_Amp", 0.15),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.15], [3, 0.45], [5, 0.3], [7, 0.2], [9, 0.12], [11, 0.07]]) },
},

//------------------------------------------------------------------ leads
{
    name: "Velvet Lead", category: "lead", tags: ["mono", "ladder", "vibrato", "compressor", "PWM", "XY pad"],
    description: "A legato ladder lead with glide: a saw and a slowly pulse-width-modulated square, each note "
        + "scooping up into pitch. The vibrato waits, fades in and then quickens the longer a note is held; a "
        + "slow per-note LFO keeps the filter alive. A gentle compressor holds it steady in front of the delay. "
        + "The XY pad: X opens the filter, Y deepens the vibrato. Mod wheel: more vibrato; aftertouch: brighter "
        + "and driven. Macros: drive, cutoff.",
    macros: ["drive", "cutoff", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 60, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, O2_PWM_W: 0.45, O2_PWM_R: 0.4, O2_PWM_D: 0.2,
        Transpose: 0, Detune: 0.8, O2_Amp: 0.6,
        Filter: filter.ladder, Cutoff: 0.42, Resonance: 0.35, F_Track: 0.5, F_EnvMod: 0.22,
        ...fenv ({ a: 5, bp: 1, d2: 600, s: 0.4, r: 300 }),
        ...amp ({ a: 8, bp: 1, s: 1, r: 260 }),
        ...menv1 ({ a: 2500, bp: 1, s: 1, r: 200 }),
        PEnv_On: 1, PEnv_Start: -0.4, PEnv_Attack: 45, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 18 }), LFO_1_Pitch: 0.36,
        LFO_1_Delay: 350, LFO_1_Fade: 600,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 1.5 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -3,
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ"),
        ...glue (-20, 3, 8, 120, 4),
        ...delay ({ unit: "eighth", length: 3, feedback: 0.35, wet: 0.13 }),
        ...xy ({ x: [["cutoff1", 0.35]], y: [["lfo1Depth", 0.8]] }),
    },
    modulations: [
        mod ("modEnv1", "LFO_1_Speed", -0.035),
        mod ("modEnv1", "Cutoff", 0.05),
        mod ("lfo2", "Cutoff", 0.04),
        mod ("lfo2", "O2_PWM_W", 0.1),
        mod ("velocity", "Cutoff", 0.06),
        mod ("modWheel", "LFO_1_Pitch", 0.15),
        mod ("aftertouch", "Cutoff", 0.18),
        mod ("aftertouch", "Sat_Pregain", 0.08),
        mod ("macro1", "Sat_Pregain", 0.2),
        mod ("macro2", "Cutoff", 0.3),
    ],
},
{
    name: "Fuzz Lead", category: "lead", tags: ["mono", "fuzz", "guitar amp", "convolution", "cabinet"],
    description: "Two detuned saws through a guitar amp (a distortion model: a high-gain amp into a 4×12 "
        + "cabinet) after the filter, so the amp sees every harmonic and the two saws grind against each other, "
        + "then a 1×12 cabinet (convolved) blended in for a smaller box. Held notes swell into more gain like an "
        + "amp feeding back, the pick attack and the beat between the saws change from note to note, and a random "
        + "LFO wobbles the tone. It starts as a crunch: the mod wheel turns it into full fuzz; aftertouch sweeps "
        + "a resonant wah in front of the amp. Macros: fuzz, cutoff, cabinet, tone.",
    macros: ["fuzz", "cutoff", "cabinet", "tone"],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 1.2, O2_Amp: 0.8,
        Filter: filter.mgLow12, Cutoff: 0.66, Resonance: 0.15, F_EnvMod: 0.1, F_Track: 0.5,
        Sat_Type: dist.guitarAmp, Sat_Mode: distMode.voicePost, Sat_Drive: 0.35, Sat_Tone: 0.5, Macro_4: 0.5,
        ...fenv ({ a: 2, bp: 1, d2: 400, s: 0.3, r: 200 }),
        ...amp ({ a: 3, bp: 1, s: 1, r: 180 }),
        ...menv1 ({ a: 2200, bp: 1, s: 1, r: 200 }), Curve_Mod1_Attack: -0.4,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 17 }), LFO_1_Pitch: 0.38,
        LFO_1_Delay: 500, LFO_1_Fade: 500,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 1.2 }),
        ...rack ("Chorus", "Convolve", "Delay", "Reverb", "EQ"),
        Cv_On: 1, Cv_Impulse: impulse ("cabinet 1×12"), Cv_Mix: 0.5,
        ...delay ({ unit: "eighth", length: [3, 2], feedback: 0.3, wet: 0.1 }),
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.08),
        mod ("modEnv1", "Cutoff", 0.04),
        mod ("lfo2", "Cutoff", 0.03),
        mod ("random", "Detune", 0.012),
        mod ("random", "F_EnvMod", 0.04),
        mod ("velocity", "F_EnvMod", 0.06),
        mod ("modWheel", "Sat_Pregain", 0.15),
        mod ("modWheel", "Cutoff", 0.06),
        mod ("aftertouch", "Cutoff", -0.15),
        mod ("aftertouch", "Resonance", 0.5),
        mod ("macro1", "Sat_Drive", 0.3),
        mod ("macro2", "Cutoff", 0.3),
        mod ("macro3", "Cv_Mix", -0.4),
        mod ("macro4", "Sat_Tone", 0.3),
    ],
},
{
    name: "Feedback Lead", category: "lead", tags: ["phase modulation", "feedback", "mono"],
    description: "Oscillator 1 phase-modulates itself (osc mix: PM 1 feedback), from a sine towards a saw. A "
        + "mod envelope and velocity open the feedback on each note's attack, a slow per-note LFO keeps it "
        + "turning between hollow and buzzy, and the feedback eases off for high notes; osc 2 adds a sine sub. "
        + "Mod wheel: more vibrato; aftertouch: more feedback. Macros: feedback, sub.",
    macros: ["feedback", "sub", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 40, GlideMode: 0,
        OscMix: mix.pmFeedback, O1_Waveform: wave.sine, PM_Feedback: 0.4, O2_Waveform: wave.sine, Transpose: -1, O2_Amp: 0.45,
        ...menv1 ({ a: 1, bp: 1, d2: 700, s: 0.3, r: 200 }),
        ...amp ({ a: 4, bp: 1, s: 1, r: 220 }),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 18 }), LFO_1_Pitch: 0.34,
        LFO_1_Delay: 300, LFO_1_Fade: 700,
        ...lfo (2, { sync: "perNote", shape: "tri", unit: "sec", speed: 2.2 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 3,
        ...delay ({ unit: "quarter", length: 1, wet: 0.11 }), D_Rotation: 1.2,
    },
    modulations: [
        mod ("modEnv1", "PM_Feedback", 0.3),
        mod ("velocity", "PM_Feedback", 0.15),
        mod ("lfo2", "PM_Feedback", 0.2),
        mod ("key", "PM_Feedback", -0.15),
        mod ("modWheel", "LFO_1_Pitch", 0.12),
        mod ("aftertouch", "PM_Feedback", 0.2),
        mod ("macro1", "PM_Feedback", 0.4),
        mod ("macro2", "O2_Amp", 0.12),
    ],
},
{
    name: "MPE Sync Lead", category: "lead", tags: ["MPE", "hard sync", "per-voice pan", "expressive"],
    description: "A hard-sync lead for MPE controllers (MPE on): osc 2 is synced to osc 1 and each note's "
        + "attack sweeps its pitch down into place, its slide sweeps it back up through the harmonics, its "
        + "pressure drives its own distortion and vibrato, and its pitch bend also moves it in the stereo field. "
        + "A slow LFO per note keeps the sync tone shifting. With a normal keyboard, aftertouch and the bend "
        + "wheel do the same for every note, and the mod wheel takes the slide's place. Macros: sync, drive.",
    macros: ["sync", "drive", "", ""],
    params: {
        MPE_On: 1, MPE_BendRange: 48, AftertouchMode: 2,
        OscMix: mix.sync, O1_Waveform: wave.sawHQ, O1_Amp: 0.3, O2_Waveform: wave.sawHQ, Transpose: semis (7), O2_Amp: 1,
        Filter: filter.ladder, Cutoff: 0.5, Resonance: 0.2, F_Track: 0.5,
        ...amp ({ a: 10, bp: 1, s: 1, r: 400 }),
        ...menv1 ({ a: 1, bp: 1, d2: 350, s: 0, r: 100 }), Curve_Mod1_Decay: 0.3,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 0,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 18 }), LFOPhaseRand: 1,
        ...lfo (2, { sync: "perNote", shape: "tri", unit: "sec", speed: 3 }),
        ...delay ({ unit: "eighth", length: 3, feedback: 0.3, wet: 0.08 }),
    },
    modulations: [
        mod ("modEnv1", "Transpose", 0.08),
        mod ("modEnv1", "Transpose", 0.04, "velocity"),
        mod ("slide", "Transpose", 0.15),
        mod ("modWheel", "Transpose", 0.15),
        mod ("lfo2", "Transpose", 0.03),
        mod ("slide", "Cutoff", 0.2),
        mod ("aftertouch", "Sat_Pregain", 0.25),
        mod ("aftertouch", "LFO_1_Pitch", 0.4),
        mod ("bend", "pan", 0.5),
        mod ("velocity", "Cutoff", 0.08),
        mod ("macro1", "Transpose", 0.15),
        mod ("macro2", "Sat_Pregain", 0.2),
    ],
},

{
    name: "Trill Lead", category: "lead", tags: ["trill", "tempo sync", "flanger chorus", "evolving"],
    description: "After Oatmeal's urghlblrugh: a saw and a triangle through a lowpass, with a sixteenth-note "
        + "square LFO on the pitch whose depth grows over a few seconds, so a held note slowly opens into a "
        + "whole-tone trill above it, harder notes trilling sooner. A flanging negative-feedback chorus. Mod "
        + "wheel: the trill right away; aftertouch: brighter. Macros: trill, cutoff.",
    macros: ["trill", "cutoff", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.triHQ, O2_Amp: 0.75,
        Filter: filter.lp4, Cutoff: 0.55, Resonance: 0.48, F_Track: 0.5, F_EnvMod: 0.18,
        ...fenv ({ a: 8.7, bp: 1, d2: 2281, s: 0.01, r: 300 }),
        ...amp ({ a: 4, bp: 1, s: 1, r: 308 }),
        ...menv1 ({ a: 3800, bp: 1, s: 1, r: 300 }), M1_VeloSens: 0.6,
        ...lfo (1, { sync: "perNote", shape: "square", unit: "sixteenth", speed: 1 }),
        LFO_1_Quantize: 1, LFO_1_Slew: 0.05,
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 18 }), LFO_2_Pitch: 0.25,
        C_Mode: 1, C_Stereo: 2, C_Voices: 2, C_Rate: 0.042, C_MinDelay: 1.7, C_Depth: 11, C_Feedback: -0.7, C_Mix: 0.6,
        RandomPan: 0.15,
        Sat_Type: dist.asym, Sat_Pregain: 3,
        ...delay ({ unit: "eighth", length: 3, feedback: 0.3, wet: 0.08 }),
        Macro_1: 1,
    },
    modulations: [
        // the envelope lifts the pitch by up to a whole tone and the square takes it back down every other
        // sixteenth: a trill between the note and a whole tone above
        mod ("modEnv1", "pitch", 1 / 24, "macro1"),
        mod ("lfo1", "pitch", 1 / 24, "modEnv1"),
        mod ("modWheel", "pitch", 1 / 24),
        mod ("lfo1", "pitch", 1 / 24, "modWheel"),
        mod ("velocity", "Cutoff", 0.06),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro2", "Cutoff", 0.25),
    ],
},
{
    name: "Overwrought Sync", category: "lead", tags: ["hard sync", "mono", "reverse delay", "XY random walk"],
    description: "After Oatmeal's overwrought: a mono hard-sync lead whose synced pulse climbs two octaves "
        + "over a couple of seconds and sinks back over eight, while resonant noise and a vibrato swell in. The "
        + "XY pad's random walk wanders the sync pitch and the cutoff, the pulse width moves, and the delay "
        + "plays its echoes backwards. Mod wheel: sweep the sync by hand; aftertouch: drive. Macros: sweep, "
        + "noise, wander.",
    macros: ["sweep", "noise", "wander", ""],
    params: {
        PolyMode: poly.legato, Glide: 25, GlideMode: 0,
        OscMix: mix.sync, O1_Waveform: wave.sawHQ, O1_Amp: 0.5, O2_Waveform: wave.pulseHQ, O2_Amp: 1.5,
        O2_PWM_R: 0.77, O2_PWM_D: 0.34, Transpose: 0,
        N_Resonance: 0.88, N_Transpose: -12,
        Filter: filter.ladder, Cutoff: 0.45, Resonance: 0.3, F_Track: 0.6, F_EnvMod: 0.25,
        ...fenv ({ a: 0.2, bp: 1, d2: 3000, s: 0.1, r: 1000 }),
        ...amp ({ a: 3, bp: 1, d2: 3000, s: 0.75, r: 615 }),
        ...menv1 ({ a: 2600, bp: 1, d2: 8600, s: 0, r: 8000 }),
        ...menv2 ({ a: 2200, bp: 1, s: 1, r: 1500 }),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 30 }),
        XY_Var_Radius: 0.25, XY_Var_Rate: 2.26,
        Sat_Type: dist.asym, Sat_Mode: distMode.double, Sat_Pregain: 7.6, Sat_Oversample: 1,
        C_Mode: 1, C_Stereo: 1, C_Depth: 11, C_Feedback: -0.53, C_Mix: 0.4,
        ...delay ({ unit: "eighth", length: [4, 3], feedback: 0.4, wet: 0.15 }), D_Quantize: 1, D_ReverseL: 1, D_ReverseR: 1,
        D_Rotation: 0.34, D_LP: 0.9, D_HP: 0.21,
        EQ_1_Type: eqType.lowShelf, EQ_1_Freq: 388, EQ_1_Amp: 4, EQ_2_Type: eqType.peak, EQ_2_Freq: 4284, EQ_2_Amp: -8,
        EQ_2_Slope: 6.9,
        Macro_1: 1, Macro_2: 0.5, Macro_3: 0.5,
    },
    modulations: [
        mod ("modEnv1", "Transpose", 0.25, "macro1"),
        mod ("modEnv2", "N_Amp", 0.4, "macro2"),
        mod ("lfo1", "finePitch", 0.25, "modEnv2"),
        mod ("x", "Transpose", 0.06, "macro3"),
        mod ("y", "Cutoff", 0.08, "macro3"),
        mod ("velocity", "Transpose", 0.04),
        mod ("modWheel", "Transpose", 0.25),
        mod ("aftertouch", "Sat_Pregain", 0.12),
    ],
},
{
    name: "Shifter Lead", category: "lead", tags: ["voice lane", "key shifter", "LFO 3", "wander", "saturate"],
    description: "Two saws with a frequency shifter in every voice that follows the key: it moves each note's partials "
        + "by a fraction of the note's own pitch, up on the left and down on the right, so every note has the same "
        + "glassy, slightly inharmonic shine wherever it is played, chords included. LFO 3, one per note, fades in "
        + "after half a second and sways the shift on held notes, and each note's offset wanders on its own; harder "
        + "notes shift further. A saturate model after the filter. Mod wheel: vibrato; aftertouch: more shine. "
        + "Macros: shift, shine, drive, vibrato.",
    macros: ["shift", "shine", "drive", "vibrato"],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.6, O2_Amp: 0.7,
        Filter: filter.ladder, Cutoff: 0.5, Resonance: 0.25, F_Track: 0.5, F_EnvMod: 0.25, F_VeloSens: 0.4,
        ...fenv ({ a: 2, bp: 1, d2: 700, s: 0.4, r: 300 }),
        ...amp ({ a: 4, bp: 1, s: 1, r: 260 }),
        Sat_Type: dist.saturate, Sat_Mode: distMode.voicePost, Sat_Drive: 0.4,
        ...lane (["Shifter"]),
        Sh_On: 1, Sh_Ratio: shiftRatio (0.03), Sh_Mode: shifterMode.stereo, Sh_Mix: 0.4,
        ...lfo3 ({ shape: "tri", mode: "perVoice", rate: 0.4, phaseRand: 1, delay: 500, fade: 1500 }),
        Wander_Rate: wanderHz (0.3),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 18 }), LFO_1_Delay: 400, LFO_1_Fade: 600,
        Voices: 8,
        ...rack ("Delay"),
        ...delay ({ unit: "sixteenth", length: 3, feedback: 0.35, wet: 0.12 }),
    },
    modulations: [
        mod ("lfo3", "Sh_Ratio", 0.04),
        mod ("wander", "Sh_Hz", 0.15),
        mod ("velocity", "Sh_Ratio", 0.03),
        mod ("random", "Sh_Ratio", 0.03),
        mod ("velocity", "Cutoff", 0.06),
        mod ("modWheel", "LFO_1_Pitch", 0.15),
        mod ("aftertouch", "Sh_Mix", 0.4),
        mod ("aftertouch", "Cutoff", 0.08),
        mod ("macro1", "Sh_Ratio", 0.15),
        mod ("macro2", "Sh_Mix", 0.4),
        mod ("macro3", "Sat_Drive", 0.3),
        mod ("macro4", "LFO_1_Pitch", 0.15),
    ],
},
{
    name: "Tearout Screech", category: "lead", tags: ["hard sync", "formant", "dubstep", "frequency shifter"],
    description: "A screaming dubstep lead: a hard-synced saw whose sync pitch dives in on every note and "
        + "wobbles in sixteenth triplets, through a formant filter whose vowel follows the same wobble, then a "
        + "hard clipper, a ring-modulating frequency shifter and a compressor. Mod wheel: drives the sync up "
        + "into a scream; aftertouch: more metal from the shifter. Macros: wobble, scream, metal.",
    macros: ["wobble", "scream", "metal", ""],
    params: {
        PolyMode: poly.legato, Glide: 20, GlideMode: 0,
        OscMix: mix.sync, O1_Waveform: wave.sawHQ, O1_Amp: 0.3, O2_Waveform: wave.sawHQ, O2_Amp: 1, Transpose: 1,
        U_Voices: 2, U_Detune: 15, U_Spread: 0.6,
        Filter: filter.formant3, Cutoff: 0.55, Resonance: 0.6, F_Track: 0.5, F_Morph: 0.3,
        ...amp ({ a: 2, bp: 1, s: 1, r: 120 }),
        ...menv1 ({ a: 0.5, bp: 1, d2: 220, s: 0, r: 100 }),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighthTriplet", speed: 1 }), LFO_2_Quantize: 1,
        Sat_Type: dist.hard, Sat_Mode: distMode.voicePost, Sat_Oversample: 2, Sat_Pregain: 18, Sat_Postgain: -14,
        ...rack ("Chorus", "Bode", "Compressor", "Delay", "Reverb", "EQ"),
        Bd_On: 1, Bd_Mode: 3, Bd_Shift: bodeHz (110), Bd_Mix: 0.15,
        ...glue (-18, 4, 3, 80, 4),
        Macro_1: 0.7,
    },
    modulations: [
        mod ("modEnv1", "Transpose", 0.12),
        mod ("lfo2", "Transpose", 0.08, "macro1"),
        mod ("lfo2", "F_Morph", 0.35, "macro1"),
        mod ("velocity", "Transpose", 0.04),
        mod ("modWheel", "Transpose", 0.2),
        mod ("modWheel", "Sat_Pregain", 0.08),
        mod ("aftertouch", "Bd_Mix", 0.3),
        mod ("macro2", "Transpose", 0.2),
        mod ("macro3", "Bd_Mix", 0.3),
    ],
},

//------------------------------------------------------------------ bass
{
    name: "Sub Fold", category: "bass", tags: ["wavefolder", "per-voice drive", "sub", "wobble"],
    description: "A pure sine sub, with a quiet sine an octave up so it carries on small speakers. A short "
        + "mod envelope and velocity drive each note's attack into a wavefolder (sine distortion) in front of a "
        + "keytracked ladder whose envelope lets the folds through only at the start, so the note settles back "
        + "to a round sub. The mod wheel brings in a tempo-synced wobble of the fold and the filter; aftertouch "
        + "folds it harder. Macros: fold, octave, wobble rate.",
    macros: ["fold", "octave", "wobble rate", ""],
    params: {
        PolyMode: poly.mono,
        O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.1,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePre, Sat_Pregain: -30,
        Filter: filter.ladder, Cutoff: 0.5, Resonance: 0.05, F_Track: 1, F_EnvMod: 0.3,
        ...fenv ({ a: 0.5, bp: 1, d2: 300, s: 0, r: 100 }),
        ...menv1 ({ a: 0.5, bp: 1, d2: 300, s: 0, r: 100 }),
        ...amp ({ a: 1, bp: 1, s: 1, r: 80 }),
        ...lfo (2, { sync: "globalReset", unit: "eighth", speed: 1 }), LFO_2_Quantize: 1,
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.35),
        mod ("velocity", "Sat_Pregain", 0.08),
        mod ("lfo2", "Sat_Pregain", 0.22, "modWheel"),
        mod ("lfo2", "Cutoff", 0.15, "modWheel"),
        mod ("aftertouch", "Sat_Pregain", 0.15),
        mod ("macro1", "Sat_Pregain", 0.12),
        mod ("macro2", "O2_Amp", 0.15),
        mod ("macro3", "LFO_2_Speed", -0.1),
    ],
},
{
    name: "Rubber Bass", category: "bass", tags: ["phase modulation", "pitch envelope", "wobble"],
    description: "A clean phase-modulation bass, an octave below the keys: osc 2 an octave up modulates osc 1, "
        + "with a short envelope on the modulation depth and a quick pitch drop for the thump. Every note "
        + "bounces a little differently, high notes stay rounder, and the mod wheel brings in an eighth-note "
        + "wobble of the modulation; aftertouch brightens it. Macros: bounce.",
    macros: ["bounce", "", "", ""],
    params: {
        PolyMode: poly.mono, GlobalTranspose: -1,
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.5,
        ...menv1 ({ a: 0.5, bp: 1, d2: 260, s: 0, r: 100 }), Curve_Mod1_Decay: 0.4,
        PEnv_On: 1, PEnv_Start: 0, PEnv_Attack: 0.2, PEnv_Peak: 12, PEnv_Decay: 45, PEnv_Sustain: 0,
        ...amp ({ a: 1, bp: 1, s: 1, r: 90 }),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighth", speed: 1 }),
        LFO_2_Quantize: 1,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 5, Sat_Postgain: -2,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.15),
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("velocity", "O2_Amp", 0.05),
        mod ("random", "O2_Amp", 0.03),
        mod ("key", "O2_Amp", -0.06),
        mod ("lfo2", "O2_Amp", 0.08, "modWheel"),
        mod ("aftertouch", "O2_Amp", 0.08),
        mod ("macro1", "O2_Amp", 0.15),
    ],
},
{
    name: "Reese Drift", category: "bass", tags: ["reese", "unison", "drift", "SVF", "flanger", "XY pad"],
    description: "Two detuned HQ saws with unison and analog drift, through a state-variable filter whose "
        + "slow LFO morphs it between lowpass and bandpass. A second slow LFO changes how fast the saws beat "
        + "against each other, and a slow flanger in the rack (with the bass kept mono) adds the jet. The XY "
        + "pad: X opens the filter, Y adds resonance and drive. Mod wheel: resonance and more bandpass; "
        + "aftertouch: drive. Macros: growl, drive.",
    macros: ["growl", "drive", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 20, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 2.2, O2_Amp: 1,
        U_Voices: 3, U_Detune: 30, U_Spread: 0.5, U_Width: 1.2,
        Drift_Pitch: 12, Drift_Rate: 0.6,
        Filter: filter.svf, F_Morph: 0.1, Cutoff: 0.33, Resonance: 0.25, F_Track: 0.5,
        ...xy ({ x: [["cutoff1", 0.3]], y: [["resonance", 0.5], ["distortion", 0.3]] }),
        ...lfo (1, { sync: "globalFree", unit: "sec", speed: 6 }),
        ...lfo (2, { sync: "globalFree", shape: "tri", unit: "sec", speed: 9 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 8, Sat_Postgain: -5,
        ...amp ({ a: 2, bp: 1, s: 1, r: 120 }),
        ...rack ("Chorus", "Flanger", "Utility", "Delay", "Reverb", "EQ"),
        Fl_On: 1, Fl_Rate: fxRate (0.08), Fl_Depth: 0.6, Fl_Delay: flangerMs (2), Fl_Feedback: 0.45, Fl_Mix: 0.3,
        Ut_On: 1, Ut_BassMono: bassMono (120),
    },
    modulations: [
        mod ("lfo1", "F_Morph", 0.15),
        mod ("lfo2", "Detune", 0.012),
        mod ("lfo2", "Cutoff", 0.03),
        mod ("modWheel", "Resonance", 0.3),
        mod ("modWheel", "F_Morph", 0.2),
        mod ("aftertouch", "Sat_Pregain", 0.12),
        mod ("velocity", "Cutoff", 0.06),
        mod ("macro1", "F_Morph", 0.5),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Acid Oats", category: "bass", tags: ["acid", "diode ladder", "per-voice drive"],
    description: "A 303-style line: diode ladder near self-oscillation, a snappy filter envelope and glide, "
        + "into an asymmetric drive. Velocity works as accent, opening the envelope and adding grit; every "
        + "note's squelch is a little different and high notes get less envelope, like a player riding the "
        + "knobs. Mod wheel: resonance; aftertouch: cutoff. Macros: cutoff, resonance, env mod, drive.",
    macros: ["cutoff", "resonance", "env mod", "drive"],
    params: {
        PolyMode: poly.legato, Glide: 45, GlideMode: 0,
        O1_Waveform: wave.sawHQ,
        Filter: filter.diode, Cutoff: 0.27, Resonance: 0.85, F_EnvMod: 0.55, F_VeloSens: 0.6, F_Track: 0.3,
        ...fenv ({ a: 0.2, bp: 1, d2: 280, s: 0, r: 80 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 1, bp: 1, d2: 1200, s: 0.6, r: 50 }),
        ...lfo (2, { sync: "globalFree", shape: "smoothRandom", unit: "sec", speed: 4 }),
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 10, Sat_Postgain: -7,
        ...delay ({ unit: "sixteenth", length: 3, feedback: 0.35, wet: 0.1 }),
        Macro_3: 0.3, Macro_4: 0.3,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("random", "F_EnvMod", 0.04),
        mod ("random", "Cutoff", 0.02),
        mod ("key", "F_EnvMod", -0.08),
        mod ("lfo2", "Cutoff", 0.05),
        mod ("modWheel", "Resonance", 0.12),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "Resonance", 0.25),
        mod ("macro3", "F_EnvMod", 0.25),
        mod ("macro4", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Octave Bass", category: "bass", tags: ["voice lane", "octaver", "bass amp", "key EQ", "XY pad"],
    description: "A reedy drawn wave through an octaver in the voice, which finds a sub octave and an octave up "
        + "from the note itself, then a ladder and a bass amp (a distortion model) in the voice too. The key EQ "
        + "cuts each note's second harmonic and lifts its fourth and eighth, so the growl sits in the same place on "
        + "every note. Harder notes get more sub, high ones less, each note's octave up and drive differ, and its "
        + "tone and octave up wander on their own while it is held. The XY pad: X opens the filter, Y adds "
        + "resonance, and a slow random walk keeps them moving. Mod wheel: an eighth-note wobble of the filter and "
        + "the octave up; aftertouch: more amp, brighter. Macros: sub, octave up, amp, cutoff.",
    macros: ["sub", "octave up", "amp", "cutoff"],
    params: {
        PolyMode: poly.legato, Glide: 35, GlideMode: 0,
        O1_Waveform: wave.user,
        Filter: filter.ladder, Cutoff: 0.33, Resonance: 0.25, F_Track: 0.5, F_EnvMod: 0.3, F_VeloSens: 0.4,
        ...fenv ({ a: 0.5, bp: 1, d2: 350, s: 0.3, r: 120 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 2, bp: 1, s: 1, r: 90 }),
        ...lane (["Octaver", "Distortion 2"], { filterAt: 1, ampAt: 2 }),
        Oc_On: 1, Oc_Sub: 0.6, Oc_Up: 0.2, Oc_Dry: 0.8,
        Sat2_Type: dist.bassAmp, Sat2_Drive: 0.45, Sat2_Tone: 0.5, Sat2_Character: 0.4,
        ...keyEq ([0, -4, 3, 4, 0, -2, -4, -6]),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighth", speed: 1 }), LFO_2_Quantize: 1,
        Wander_Rate: wanderHz (0.5),
        ...xy ({ x: [["cutoff1", 0.4]], y: [["resonance", 0.5]], walk: { radius: 0.15, rate: 0.5 } }),
        ...rack ("Compressor"),
        ...glue (-20, 3, 5, 90, 2),
    },
    modulations: [
        mod ("velocity", "Oc_Sub", 0.2),
        mod ("velocity", "F_EnvMod", 0.08),
        mod ("key", "Oc_Sub", -0.2),
        mod ("random", "Oc_Up", 0.15),
        mod ("random", "Sat2_Pregain", 0.08),
        mod ("wander", "Cutoff", 0.12),
        mod ("wander", "Oc_Up", 0.15),
        mod ("lfo2", "Oc_Up", 0.4, "modWheel"),
        mod ("lfo2", "Cutoff", 0.12, "modWheel"),
        mod ("aftertouch", "Sat2_Pregain", 0.25),
        mod ("aftertouch", "Cutoff", 0.1),
        mod ("macro1", "Oc_Sub", 0.3),
        mod ("macro2", "Oc_Up", 0.4),
        mod ("macro3", "Sat2_Pregain", 0.2),
        mod ("macro4", "Cutoff", 0.3),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.35], [3, 0.55], [4, 0.2], [5, 0.35], [7, 0.2], [9, 0.1]]) },
},

{
    name: "Wooly Bass", category: "bass", tags: ["User PWM", "mono", "chorus", "glide"],
    description: "After Oatmeal's bassmeh: a User PWM wave with a slow PWM, gliding, through a resonant "
        + "lowpass with a deep, quick envelope and an asymmetric drive, then a fully wet chorus for width over "
        + "a mono low end. Every note's pulse width and envelope differ a little, and high notes get less "
        + "envelope. Mod wheel: a quarter-note filter wobble; aftertouch: cutoff. Macros: wool, wobble rate.",
    macros: ["wool", "wobble rate", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0, GlobalTranspose: -1,
        O1_Waveform: wave.userPwm, O1_PWM_W: 0.73, O1_PWM_R: 0.83, O1_PWM_D: 0.12, OscPhaseRand: 0, PWMPhaseRand: 0,
        Filter: filter.ladder, Cutoff: 0.36, Resonance: 0.41, F_Track: 1, F_EnvMod: 0.55,
        ...fenv ({ a: 0.2, bp: 1, d2: 450, s: 0.03, r: 120 }),
        ...amp ({ a: 22, bp: 1, d2: 1177, s: 0.25, r: 90 }),
        ...lfo (2, { sync: "globalReset", unit: "quarter", speed: 1 }), LFO_2_Quantize: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 9,
        ...rack ("Chorus", "Utility", "Delay", "Reverb", "EQ"),
        C_Mode: 1, C_Stereo: 2, C_Rate: 0.32, C_MinDelay: 1.2, C_Depth: 3.5, C_Mix: 1,
        Ut_On: 1, Ut_BassMono: bassMono (140),
    },
    modulations: [
        mod ("random", "O1_PWM_W", 0.05),
        mod ("random", "F_EnvMod", 0.03),
        mod ("velocity", "F_EnvMod", 0.1),
        mod ("key", "F_EnvMod", -0.1),
        mod ("lfo2", "Cutoff", 0.15, "modWheel"),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "Resonance", 0.25),
        mod ("macro1", "O1_PWM_D", 0.15),
        mod ("macro2", "LFO_2_Speed", -0.12),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.5], [3, 0.45], [4, 0.25], [5, 0.25], [6, 0.12], [7, 0.14], [9, 0.08], [11, 0.05]]) },
},
{
    name: "Snap Bass", category: "bass", tags: ["filter envelope", "tempo sync", "pluck"],
    description: "After Oatmeal's greh: a bright harmonic wave an octave down through a resonant 2-pole "
        + "lowpass with an eight-octave envelope that snaps shut in a few tens of milliseconds, a sixteenth-note "
        + "LFO bouncing the cutoff on held notes and a quick vibrato. Every note snaps a little differently. "
        + "Mod wheel: a deeper bounce; aftertouch: resonance. Macros: snap, bounce.",
    macros: ["snap", "bounce", "", ""],
    params: {
        O1_Waveform: wave.user, VeloSens: 0, GlobalTranspose: -1,
        Filter: filter.lp2, Cutoff: 0.27, Resonance: 0.78, F_Track: 1, F_EnvMod: 1, F_VeloSens: 0.4,
        ...fenv ({ a: 0.2, bp: 1, d2: 30, s: 0.27, r: 100 }),
        ...amp ({ a: 1, bp: 1, s: 1, r: 80 }),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 12.4 }), LFO_1_Pitch: 0.33,
        ...lfo (2, { sync: "perNote", unit: "sixteenth", speed: 2.46 }), LFO_2_Quantize: 1,
        LFO_2_Cutoff_1: 0.3,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 2,
    },
    modulations: [
        mod ("random", "Cutoff", 0.03),
        mod ("random", "Resonance", 0.05),
        mod ("modWheel", "LFO_2_Cutoff_1", 0.2),
        mod ("aftertouch", "Resonance", 0.15),
        mod ("macro1", "Cutoff", -0.1),
        mod ("macro1", "Resonance", 0.15),
        mod ("macro2", "LFO_2_Cutoff_1", 0.2),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.8], [3, 0.6], [4, 0.5], [5, 0.4], [6, 0.3], [8, 0.2], [10, 0.15], [12, 0.1], [16, 0.05]]) },
},
{
    name: "Wub Bass", category: "bass", tags: ["dubstep", "wobble", "tempo sync", "OTT"],
    description: "A classic dubstep wobble: detuned saws over a sine sub an octave down, through a driven "
        + "dirty lowpass that an eighth-note LFO swings open and shut, with the drive after it pumping along. "
        + "The mod wheel (or macro 1) speeds the wobble up to sixteenths and triplets for the build; the three-"
        + "band compressor squashes it and a utility keeps the lows mono. Aftertouch: resonance. Macros: wobble "
        + "rate, depth, drive.",
    macros: ["wobble rate", "depth", "drive", ""],
    params: {
        PolyMode: poly.legato, Glide: 40, GlideMode: 0,
        O1_Waveform: wave.sawHQ, U_Voices: 3, U_Detune: 15, U_Spread: 0.5,
        O2_Waveform: wave.sine, Transpose: -1, O2_Amp: 0.6,
        Filter: filter.mgDirty, F_Drive: 0.4, Cutoff: 0.28, Resonance: 0.45, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, s: 1, r: 100 }),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighth", speed: 1 }),
        LFO_2_Quantize: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Oversample: 1, Sat_Pregain: 14, Sat_Postgain: -10,
        ...rack ("Chorus", "Compressor", "Utility", "Delay", "Reverb", "EQ"),
        Cp_On: 1, Cp_Depth: 0.5, Cp_Attack: compAttack (3), Cp_Release: compRelease (80), Cp_Mix: 0.8,
        Ut_On: 1, Ut_BassMono: bassMono (120),
        Macro_2: 0.7,
    },
    modulations: [
        mod ("lfo2", "Cutoff", 0.4, "macro2"),
        mod ("lfo2", "Sat_Pregain", 0.06),
        mod ("lfo2", "Resonance", 0.1, "macro2"),
        mod ("modWheel", "LFO_2_Speed", -0.12),
        mod ("macro1", "LFO_2_Speed", -0.12),
        mod ("velocity", "Sat_Pregain", 0.06),
        mod ("aftertouch", "Resonance", 0.25),
        mod ("macro3", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Growl Bass", category: "bass", tags: ["dubstep", "FM", "formant", "growl"],
    description: "A growl: a sine phase-modulated by another at the same pitch, its index and a formant "
        + "filter's vowel both riding a quarter-note LFO and kicking on each note, into a hard clipper (4x "
        + "oversampled), a second distortion, the three-band compressor and a bass-mono utility. Mod wheel: "
        + "the growl goes to eighths; aftertouch: more FM. Macros: growl, vowel, rate.",
    macros: ["growl", "vowel", "rate", ""],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0,
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 0, O2_Amp: 0.25,
        Filter: filter.formant1, Cutoff: 0.5, Resonance: 0.5, F_Track: 0.3, F_Morph: 0.2,
        ...amp ({ a: 2, bp: 1, s: 1, r: 100 }),
        ...menv1 ({ a: 1, bp: 1, d2: 250, s: 0.4, r: 100 }),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "quarter", speed: 1 }),
        LFO_2_Quantize: 1,
        Sat_Type: dist.hard, Sat_Mode: distMode.voicePost, Sat_Oversample: 2, Sat_Pregain: 18, Sat_Postgain: -14,
        ...rack ("Chorus", "Distortion 2", "Compressor", "Utility", "Delay", "Reverb", "EQ"),
        Sat2_Type: dist.soft, Sat2_Pregain: 6, Sat2_Postgain: -4,
        Cp_On: 1, Cp_Depth: 0.6, Cp_Attack: compAttack (2), Cp_Release: compRelease (70), Cp_Mix: 0.8,
        Ut_On: 1, Ut_BassMono: bassMono (130),
        Macro_1: 0.6, Macro_2: 0.6,
    },
    modulations: [
        mod ("lfo2", "O2_Amp", 0.12, "macro1"),
        mod ("lfo2", "F_Morph", 0.35, "macro2"),
        mod ("modEnv1", "O2_Amp", 0.08),
        mod ("modEnv1", "F_Morph", 0.15),
        mod ("velocity", "O2_Amp", 0.04),
        mod ("modWheel", "LFO_2_Speed", -0.1),
        mod ("macro3", "LFO_2_Speed", -0.1),
        mod ("aftertouch", "O2_Amp", 0.08),
    ],
},
{
    name: "Neuro Comb", category: "bass", tags: ["neuro", "comb", "phaser", "OTT"],
    description: "A neuro bass: detuned saws through a comb filter tuned to the note, whose tuning a slow LFO "
        + "drags off and back for that hollow, metallic sweep, while an eighth-note LFO works its feedback and "
        + "damping. Then an asymmetric drive, a phaser, the three-band compressor and a bass-mono utility. "
        + "Mod wheel: a faster, deeper sweep; aftertouch: more feedback. Macros: sweep, chew, drive.",
    macros: ["sweep", "chew", "drive", ""],
    params: {
        PolyMode: poly.legato, Glide: 25, GlideMode: 0,
        O1_Waveform: wave.sawHQ, U_Voices: 3, U_Detune: 25, U_Spread: 0.5,
        O2_Waveform: wave.sawHQ, Detune: 1.5, O2_Amp: 0.7,
        Filter: filter.combPlus, Cutoff: 0.45, F_Track: 1, Resonance: 0.7, F_Morph: 0.3,
        ...amp ({ a: 2, bp: 1, s: 1, r: 100 }),
        ...lfo (1, { sync: "globalFree", unit: "sec", speed: 4 }),
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighth", speed: 1 }),
        LFO_2_Quantize: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 12, Sat_Postgain: -9,
        ...rack ("Chorus", "Phaser", "Compressor", "Utility", "Delay", "Reverb", "EQ"),
        Ph_On: 1, Ph_Rate: fxRate (0.3), Ph_Depth: 0.6, Ph_Feedback: 0.4, Ph_Mix: 0.35,
        Cp_On: 1, Cp_Depth: 0.6, Cp_Attack: compAttack (3), Cp_Release: compRelease (80), Cp_Mix: 0.8,
        Ut_On: 1, Ut_BassMono: bassMono (120),
        Macro_1: 0.6, Macro_2: 0.5,
    },
    modulations: [
        mod ("lfo1", "Cutoff", 0.08, "macro1"),
        mod ("lfo2", "Resonance", 0.15, "macro2"),
        mod ("lfo2", "F_Morph", 0.3, "macro2"),
        mod ("modWheel", "LFO_1_Speed", -0.15),
        mod ("lfo1", "Cutoff", 0.06, "modWheel"),
        mod ("aftertouch", "Resonance", 0.15),
        mod ("velocity", "Sat_Pregain", 0.06),
        mod ("macro3", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Yoi Bass", category: "bass", tags: ["dubstep", "formant", "vowel", "pitch envelope"],
    description: "A yoi bass: a saw and a square an octave down through a formant filter whose vowel jumps "
        + "on every note while the pitch scoops up from below, a quick 'yoi'. Then a soft drive and the three-"
        + "band compressor. Every note's vowel starts a little differently; the mod wheel adds a quarter-note "
        + "vowel wobble, aftertouch more drive. Macros: yoi, vowel, drive.",
    macros: ["yoi", "vowel", "drive", ""],
    params: {
        PolyMode: poly.legato, Glide: 50, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, Transpose: -1, O2_Amp: 0.5,
        Filter: filter.formant2, Cutoff: 0.45, Resonance: 0.55, F_Track: 0.3, F_Morph: 0.05,
        ...amp ({ a: 2, bp: 1, s: 1, r: 100 }),
        ...menv1 ({ a: 0.5, bp: 1, d2: 180, s: 0.3, r: 100 }),
        PEnv_On: 1, PEnv_Start: -7, PEnv_Attack: 60, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "quarter", speed: 1 }),
        LFO_2_Quantize: 1,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 10, Sat_Postgain: -6,
        ...rack ("Chorus", "Compressor", "Utility", "Delay", "Reverb", "EQ"),
        Cp_On: 1, Cp_Depth: 0.5, Cp_Attack: compAttack (3), Cp_Release: compRelease (90), Cp_Mix: 0.8,
        Ut_On: 1, Ut_BassMono: bassMono (120),
        Macro_1: 1,
    },
    modulations: [
        mod ("modEnv1", "F_Morph", 0.55, "macro1"),
        mod ("random", "F_Morph", 0.06),
        mod ("velocity", "F_Morph", 0.08),
        mod ("lfo2", "F_Morph", 0.3, "modWheel"),
        mod ("aftertouch", "Sat_Pregain", 0.12),
        mod ("macro2", "F_Morph", 0.4),
        mod ("macro3", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ plucks, mallets, bells
{
    name: "Spring Twang", category: "pluck", tags: ["surf", "analog filter", "convolution", "spring", "tremolo"],
    description: "A twangy surf pluck: a narrow pulse and a saw through the clean-drive filter, pushed a little, "
        + "with a snappy envelope, into a convolved spring reverb. Every note is picked at its own spot (pulse "
        + "width) and the pulse drifts while it rings; harder notes push the filter drive. Macro 1 brings in an "
        + "amp tremolo, the mod wheel a whammy-bar vibrato, and aftertouch bends the string up a little. Macros: "
        + "tremolo, spring, twang.",
    macros: ["tremolo", "spring", "twang", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.3, O1_PWM_R: 0.3, O1_PWM_D: 0.08,
        O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.5, O2_Amp: 0.45,
        Filter: filter.cleanDrive, F_Drive: 0.35, Cutoff: 0.45, Resonance: 0.3, F_Track: 0.6, F_EnvMod: 0.35,
        F_VeloSens: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 260, s: 0.2, r: 200 }), Curve_Filter_Decay: 0.4,
        ...amp ({ a: 0.5, bp: 1, d2: 7000, s: 0, r: 350 }), Curve_Amp_Decay: 0.15,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 16 }),
        ...lfo (2, { sync: "globalFree", unit: "ms10", speed: 17 }),
        ...rack ("Chorus", "Delay", "Convolve", "Reverb", "EQ"),
        Cv_On: 1, Cv_Impulse: impulse ("spring"), Cv_Mix: 0.28, Cv_LowCut: hz (250),
        Voices: 12,
    },
    modulations: [
        mod ("lfo2", "volume", 0.45, "macro1"),
        mod ("lfo1", "finePitch", 0.3, "modWheel"),
        mod ("aftertouch", "finePitch", 0.25),
        mod ("random", "O1_PWM_W", 0.08),
        mod ("random", "Cutoff", 0.03),
        mod ("velocity", "Cutoff", 0.06),
        mod ("velocity", "F_Drive", 0.2),
        mod ("macro2", "Cv_Mix", 0.35),
        mod ("macro3", "F_EnvMod", 0.15),
        mod ("macro3", "F_Drive", 0.4),
    ],
},
{
    name: "Resonator Pluck", category: "pluck", tags: ["voice lane", "resonator", "osc envelopes", "string"],
    description: "Only a pick goes in: a pulse and a triangle that their own envelopes cut off within a tenth "
        + "of a second, and a tick of noise, into a resonator in every voice tuned to its note, which rings as "
        + "the string. Each string rings for its own time and at its own brightness, harder plucks are brighter, "
        + "high strings ring shorter, and each is tuned a hair apart and placed at its own spot in the stereo field. "
        + "The amp envelope damps the string when the key is let go. Mod wheel: a longer ring; aftertouch: "
        + "brighter. Macros: ring, brightness, pick, body.",
    macros: ["ring", "brightness", "pick", "body"],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.3, O2_Waveform: wave.triHQ, Transpose: 1, O2_Amp: 0.5,
        ...oscEnv (1, { a: 0.2, bp: 1, d2: 100, s: 0, r: 20 }),
        ...oscEnv (2, { a: 0.2, bp: 1, d2: 50, s: 0, r: 20 }),
        N_Resonance: 0.5, N_Transpose: 12,
        Filter: filter.svf, Cutoff: 0.55, Resonance: 0.1, F_Track: 0.6, F_EnvMod: 0.25, F_VeloSens: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 900, s: 0.2, r: 300 }),
        ...amp ({ a: 0.3, bp: 1, s: 1, r: 260 }),
        ...menv2 ({ a: 0.2, bp: 1, d2: 15, s: 0, r: 10 }),
        ...lane (["Resonator"], { filterAt: 1 }),
        Rs_On: 1, Rs_Model: resonatorModel.harmonic, Rs_Decay: resonatorMs (1500), Rs_Bright: 0.5, Rs_Mix: 0.9, Rs_Gain: 24,
        Voices: 12,
        ...rack ("Delay", "Algo reverb"),
        ...delay ({ unit: "eighth", length: [3, 4], feedback: 0.25, wet: 0.07 }),
        Rv_On: 1, Rv_Model: reverbModel.plate, Rv_Size: 0.35, Rv_Decay: reverbSeconds (1.6), Rv_Mix: 0.12,
        Macro_4: 0.5,
    },
    modulations: [
        mod ("random", "Rs_Decay", 0.05),
        mod ("random", "Rs_Bright", 0.12),
        mod ("random", "finePitch", 0.03),
        mod ("random", "pan", 0.35),
        mod ("velocity", "Rs_Bright", 0.2),
        mod ("velocity", "Cutoff", 0.08),
        mod ("key", "Rs_Decay", -0.15),
        mod ("modEnv2", "N_Amp", 0.3),
        mod ("modWheel", "Rs_Decay", 0.15),
        mod ("aftertouch", "Rs_Bright", 0.4),
        mod ("aftertouch", "Cutoff", 0.1),
        mod ("macro1", "Rs_Decay", 0.2),
        mod ("macro2", "Rs_Bright", 0.3),
        mod ("macro2", "Cutoff", 0.15),
        mod ("macro3", "O1_PWM_W", 0.25),
        mod ("macro4", "Rs_Mix", 0.15),
    ],
},
{
    name: "Wide Harp", category: "pluck", tags: ["phase modulation", "per-voice pan", "harp", "plate"],
    description: "A clear harp spread across the stereo field by pitch (frequency pan): low strings left, high "
        + "strings right. Each pluck is a quick burst of phase modulation from osc 2 at the same pitch and a "
        + "tick of tuned noise, over a sine that rings on nearly pure; every string is plucked a little "
        + "differently and tuned a hair apart, high strings are plucked softer. The mud below 120 Hz is shelved "
        + "off and a light plate sits around it. Mod wheel: a shimmering vibrato. Macros: brightness, space.",
    macros: ["brightness", "space", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 0, O2_Amp: 0.05,
        N_Resonance: 0.85,
        ...menv1 ({ a: 0.3, bp: 1, d2: 600, s: 0, r: 150 }), Curve_Mod1_Decay: 0.3,
        ...menv2 ({ a: 0.2, bp: 1, d2: 90, s: 0, r: 20 }),
        ...amp ({ a: 0.8, bp: 1, d2: 9000, s: 0, r: 1500 }),
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 15 }), LFOPhaseRand: 1,
        FreqPan: 0.22, Voices: 16, VeloSens: 0.75,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Algo reverb"),
        EQ_1_Type: eqType.lowShelf, EQ_1_Freq: 120, EQ_1_Amp: -6,
        Rv_On: 1, Rv_Model: reverbModel.plate, Rv_Size: 0.4, Rv_Decay: reverbSeconds (1.8), Rv_Predelay: 15,
        Rv_Damp: hz (6000), Rv_LowCut: hz (200), Rv_Mix: 0.14,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.28),
        mod ("velocity", "O2_Amp", 0.06),
        mod ("modEnv2", "N_Amp", 0.35),
        mod ("velocity", "N_Amp", 0.06),
        mod ("random", "O2_Amp", 0.04),
        mod ("random", "finePitch", 0.03),
        mod ("key", "O2_Amp", -0.05),
        mod ("lfo2", "finePitch", 0.12, "modWheel"),
        mod ("macro1", "O2_Amp", 0.12),
        mod ("macro2", "Rv_Mix", 0.2),
    ],
},
{
    name: "AM Bells", category: "bells", tags: ["amplitude modulation", "wavefolder", "per-voice drive", "shimmer"],
    description: "Amplitude modulation at a ratio of about 3.5 gives inharmonic bell partials. The modulation "
        + "is struck deep and rings out towards a purer tone, each bell's ratio is a little different, and a "
        + "slow per-note LFO bends the ratio so the partials shimmer and slide against each other. A sine folder "
        + "on each voice is driven by velocity, so hard hits ring metallic while soft ones stay pure. Bells "
        + "scatter around the stereo field. Mod wheel: more shimmer; aftertouch: more metal. Macros: metal, "
        + "shimmer.",
    macros: ["metal", "shimmer", "", ""],
    params: {
        OscMix: mix.am, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: ratio (3.5), O2_Amp: 0.5,
        ...amp ({ a: 1, bp: 1, d2: 9000, s: 0, r: 3000 }), Curve_Amp_Decay: 0.3,
        ...menv1 ({ a: 0.5, bp: 1, d2: 3000, s: 0, r: 1000 }),
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 2.5 }), LFOPhaseRand: 1,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -12,
        RandomPan: 0.5, FreqPan: 0.1, Drift_Pitch: 2, Voices: 16,
        R_On: 1, R_Size: 75, R_Length: 3.5, R_Wet: 0.15,
        Macro_2: 0.4,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.15),
        mod ("random", "Transpose", 0.004),
        mod ("lfo2", "Transpose", 0.004, "macro2"),
        mod ("lfo2", "Transpose", 0.006, "modWheel"),
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("aftertouch", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.12),
    ],
},
{
    name: "Just Bells", category: "bells", tags: ["microtuning", "just intonation", "FM"],
    description: "Two-operator FM bells (phase modulation, the way the DX7 does FM): a sine modulator at 3.5 "
        + "times the pitch, its index struck high and falling away, so each bell starts clangorous and rings out "
        + "towards a pure tone. Two unison copies a few cents apart beat like a real bell, each bell's ratio is "
        + "cast a little differently, and a slow LFO keeps the index glinting. Tuned to 5-limit just intonation "
        + "on C (a Scala scale saved with the program), so thirds and fifths are beat-free in the key of C. Mod "
        + "wheel: more glint; aftertouch: rub the bell brighter. Macros: strike, ring.",
    macros: ["strike", "ring", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: ratio (3.5), O2_Amp: 0.06,
        U_Voices: 2, U_Detune: 4, U_Spread: 0.6,
        ...menv1 ({ a: 0.3, bp: 1, d2: 4000, s: 0, r: 600 }), Curve_Mod1_Decay: 0.3,
        ...amp ({ a: 0.5, bp: 1, d2: 20000, s: 0, r: 3000 }), Curve_Amp_Decay: 0.1,
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 3 }), LFOPhaseRand: 1,
        RandomPan: 0.4, FreqPan: 0.1, Voices: 16,
        R_On: 1, R_Size: 70, R_Length: 3, R_Wet: 0.15,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.2),
        mod ("velocity", "O2_Amp", 0.08),
        mod ("random", "Transpose", 0.003),
        mod ("lfo2", "O2_Amp", 0.03),
        mod ("lfo2", "O2_Amp", 0.05, "modWheel"),
        mod ("aftertouch", "O2_Amp", 0.1),
        mod ("macro1", "O2_Amp", 0.12),
        mod ("macro2", "R_Wet", 0.1),
    ],
    tuning: { scl: justScale, kbm: "" },
},
{
    name: "Folded Mallets", category: "mallet", tags: ["FM", "wavefolder", "marimba", "vibraphone"],
    description: "FM mallets (phase modulation): a sine bar with a modulator at four times its pitch, struck "
        + "for a few tens of milliseconds for the knock of a marimba, and a click of tuned noise. Every hit has "
        + "its own hardness and a hair of detune, and high bars are struck softer. A wavefolder after the "
        + "envelope adds bite to hard hits only, dying away with the note. The mod wheel turns on a "
        + "vibraphone's motor: a tremolo that also pans. A small convolved room. Macros: hardness, fold.",
    macros: ["hardness", "fold", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 2, O2_Amp: 0,
        N_Resonance: 0.9,
        ...menv1 ({ a: 0.2, bp: 1, d2: 300, s: 0, r: 50 }), Curve_Mod1_Decay: 0.3,
        ...menv2 ({ a: 0.2, bp: 1, d2: 60, s: 0, r: 15 }),
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -20,
        ...amp ({ a: 0.3, bp: 1, d2: 3500, s: 0, r: 450 }),
        ...lfo (1, { sync: "globalFree", unit: "ms10", speed: 18 }),
        FreqPan: 0.15, Voices: 16, VeloSens: 0.8,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.1,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.6),
        mod ("velocity", "O2_Amp", 0.1),
        mod ("random", "O2_Amp", 0.05),
        mod ("key", "O2_Amp", -0.08),
        mod ("random", "finePitch", 0.02),
        mod ("modEnv2", "N_Amp", 0.35),
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("lfo1", "volume", 0.4, "modWheel"),
        mod ("lfo1", "pan", 0.25, "modWheel"),
        mod ("macro1", "O2_Amp", 0.1),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},

{
    name: "Glass Pluck", category: "pluck", tags: ["phase modulation", "feedback", "digital", "OTT"],
    description: "A glassy digital pluck: a sine phase-modulating itself, its feedback struck high on every "
        + "note (harder with velocity, less for high notes) and falling back towards a pure tone, over a quiet "
        + "sine an octave up. Each pluck's feedback is cast a little differently. A light OTT, a dotted-eighth "
        + "delay and a small plate. Mod wheel: vibrato; aftertouch: more feedback. Macros: glass, space.",
    macros: ["glass", "space", "", ""],
    params: {
        OscMix: mix.pmFeedback, O1_Waveform: wave.sine, PM_Feedback: 0.1, O2_Waveform: wave.sine, Transpose: 1,
        O2_Amp: 0.25,
        ...menv1 ({ a: 0.3, bp: 1, d2: 900, s: 0, r: 100 }), Curve_Mod1_Decay: 0.3,
        ...amp ({ a: 0.5, bp: 1, d2: 5000, s: 0, r: 500 }),
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 17 }),
        RandomPan: 0.3, Voices: 12,
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ", "Algo reverb"),
        Cp_On: 1, Cp_Depth: 0.4, Cp_Mix: 0.6,
        ...delay ({ unit: "sixteenth", length: 3, feedback: 0.35, wet: 0.12 }), D_Rotation: 1,
        Rv_On: 1, Rv_Model: reverbModel.plate, Rv_Size: 0.35, Rv_Decay: reverbSeconds (1.5), Rv_Mix: 0.1,
    },
    modulations: [
        mod ("modEnv1", "PM_Feedback", 0.5),
        mod ("velocity", "PM_Feedback", 0.15),
        mod ("key", "PM_Feedback", -0.1),
        mod ("random", "PM_Feedback", 0.05),
        mod ("lfo2", "finePitch", 0.15, "modWheel"),
        mod ("aftertouch", "PM_Feedback", 0.2),
        mod ("macro1", "PM_Feedback", 0.2),
        mod ("macro2", "Rv_Mix", 0.2),
        mod ("macro2", "D_Wet", 0.1),
    ],
},
{
    name: "Vlorg Glass", category: "bells", tags: ["User", "resonant noise", "wavefolder", "comb chorus"],
    description: "After Oatmeal's vlorgulon: a hollow odd-harmonic wave with a sine two octaves up that pings "
        + "on every note (louder with velocity) and resonant noise that blooms in behind it (more for soft "
        + "notes), through a sine folder and a negative-feedback chorus that combs it like glass. Every note's "
        + "ping is tuned a hair differently and a slow LFO per note works the folder. Mod wheel: a deeper comb; "
        + "aftertouch: more fold. Macros: ping, breath.",
    macros: ["ping", "breath", "", ""],
    params: {
        O1_Waveform: wave.user, O2_Waveform: wave.sine, O2_Amp: 0, Transpose: 2, VeloSens: 0,
        N_Resonance: 0.835, N_Transpose: 12,
        ...amp ({ a: 3, bp: 1, d2: 6000, s: 0.3, r: 600 }),
        ...menv1 ({ a: 0.2, bp: 1, d2: 400, s: 0, r: 50 }),
        ...menv2 ({ a: 59, bp: 1, d2: 1100, s: 0, r: 200 }),
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 3 }), LFOPhaseRand: 1,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -8, Sat_Oversample: 1,
        C_Mode: 4, C_Stereo: 1, C_Rate: 0.081, C_MinDelay: 0.1, C_Depth: 1.4, C_Feedback: -0.66, C_Mix: 0.6,
        RandomPan: 0.3, Voices: 12,
        Macro_1: 0.7, Macro_2: 0.5,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.6, "velocity"),
        mod ("modEnv1", "O2_Amp", 0.15, "macro1"),
        mod ("modEnv2", "N_Amp", 0.5, "macro2"),
        mod ("velocity", "N_Amp", -0.15),
        mod ("random", "Transpose", 0.004),
        mod ("lfo2", "Sat_Pregain", 0.04),
        mod ("modWheel", "C_Feedback", -0.2),
        mod ("aftertouch", "Sat_Pregain", 0.1),
    ],
    tables: { wave1: harmonics ([[1, 1], [3, 0.3], [5, 0.4], [7, 0.2], [11, 0.15], [13, 0.1]]) },
},

//------------------------------------------------------------------ brass
{
    name: "Brassy Oats", category: "brass", tags: ["brass", "per-voice drive", "ladder", "EQ", "section"],
    description: "Synth brass: a ladder with a slow-attack filter envelope and a soft drive on each voice, "
        + "so loud chords get raspy without turning to mush. Each note's pitch scoops up slightly and each "
        + "player is a few cents and a shade of brightness apart, with a little breath wavering the filter; a "
        + "vibrato comes in on long notes. The EQ lifts the upper mids and the top for the bite of real brass. "
        + "Mod wheel: more vibrato; aftertouch: growl. Macros: rasp, swell, bite.",
    macros: ["rasp", "swell", "bite", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 1.1, O2_Amp: 0.8,
        Filter: filter.ladder, Cutoff: 0.31, Resonance: 0.15, F_EnvMod: 0.42, F_VeloSens: 0.6, F_Track: 0.6,
        ...fenv ({ a: 70, bp: 1, d2: 700, s: 0.55, r: 300 }), Curve_Filter_Attack: -0.3,
        ...amp ({ a: 25, bp: 1, s: 1, r: 260 }),
        PEnv_On: 1, PEnv_Start: -0.6, PEnv_Attack: 60, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 19 }), LFO_1_Pitch: 0.28,
        LFO_1_Delay: 600, LFO_1_Fade: 900, LFOPhaseRand: 1,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "sec", speed: 0.8 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -4,
        RandomPan: 0.3, Drift_Pitch: 4,
        C_Mode: 1, C_Mix: 0.3,
        EQ_1_Type: eqType.peak, EQ_1_Freq: 1800, EQ_1_Amp: 3.5, EQ_2_Type: eqType.highShelf, EQ_2_Freq: 4500, EQ_2_Amp: 5,
        Macro_3: 0.5,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("random", "finePitch", 0.05),
        mod ("random", "Cutoff", 0.03),
        mod ("lfo2", "Cutoff", 0.025),
        mod ("modWheel", "LFO_1_Pitch", 0.12),
        mod ("aftertouch", "Sat_Pregain", 0.12),
        mod ("aftertouch", "Cutoff", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "F_EnvMod", 0.2),
        mod ("macro3", "EQ_1_Amp", 0.05),
        mod ("macro3", "EQ_2_Amp", 0.05),
    ],
},

//------------------------------------------------------------------ rhythmic
{
    name: "S&H Panner", category: "sequence", tags: ["per-voice pan", "sample & hold", "tempo sync", "PWM"],
    description: "A per-note random LFO that takes a new value every 16th note jumps each note around the "
        + "stereo field and moves its cutoff. Every note has its own random pattern, so a chord splits into "
        + "independent lines, and a slower LFO per note sweeps the pulse width underneath. A little slew rounds "
        + "the steps. Mod wheel: the steps go to 32nds; aftertouch: resonance. Macros: jump, filter.",
    macros: ["jump", "filter", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.3, O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.33, Resonance: 0.5, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, s: 0.8, r: 250 }),
        ...lfo (1, { sync: "perNote", shape: "steppingRandom", unit: "sixteenth", speed: 1 }),
        LFO_1_Quantize: 1, LFO_1_Slew: 0.08, LFO_1_Pan: 0.85, LFO_1_Cutoff_1: 0.45,
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 4 }),
        LFOPhaseRand: 1,
        ...delay ({ unit: "eighth", length: 3, feedback: 0.4, wet: 0.12 }), D_Quantize: 1,
    },
    modulations: [
        mod ("lfo2", "O1_PWM_W", 0.15),
        mod ("lfo1", "O2_Amp", 0.06),
        mod ("modWheel", "LFO_1_Speed", -0.1),
        mod ("aftertouch", "Resonance", 0.3),
        mod ("velocity", "Cutoff", 0.06),
        mod ("macro1", "LFO_1_Pan", 0.15),
        mod ("macro2", "LFO_1_Cutoff_1", 0.2),
        mod ("macro2", "Resonance", 0.2),
    ],
},
{
    name: "Formant Steps", category: "sequence", tags: ["voice lane", "formant", "LFO 3", "sample & hold", "User PWM"],
    description: "Every note talks in its own rhythm: a formant filter in each voice, following the note, whose "
        + "vowel LFO 3 picks again every sixteenth (sample & hold, one per note, each from a random start), so a "
        + "held chord turns into several voices chattering against each other, each at its own place in the "
        + "stereo field. Under it, a drawn saw-like wave played as a pulse (User PWM), its width swept slowly in "
        + "each note. Harder notes ring more. Mod wheel: wider vowel steps; aftertouch: brighter vowels. Macros: steps, "
        + "vowel, resonance, drive.",
    macros: ["steps", "vowel", "resonance", "drive"],
    params: {
        O1_Waveform: wave.userPwm, O1_PWM_W: 0.35, O2_Waveform: wave.sawHQ, Transpose: -1, O2_Amp: 0.35,
        Filter: filter.ladder, Cutoff: 0.6, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 3, bp: 1, s: 1, r: 200 }),
        ...lane (["Filter"], { ampAt: 1 }),
        Ff_On: 1, Ff_Type: FilterTypes.index ("formant II"), Ff_Cutoff: hz (900), Ff_Track: 0.8, Ff_Resonance: 0.45,
        Ff_Morph: 0.5, Ff_Drive: 0.15, Ff_Mix: 1,
        ...lfo3 ({ shape: "sampleHold", mode: "perVoice", sync: "sixteenth", phaseRand: 1 }),
        ...lfo (2, { sync: "perNote", unit: "sec", speed: 3 }), LFOPhaseRand: 1,
        ...rack ("Delay"),
        ...delay ({ unit: "sixteenth", length: [3, 4], feedback: 0.35, wet: 0.1 }),
        Macro_1: 0.5,
    },
    modulations: [
        mod ("lfo3", "Ff_Morph", 0.25),
        mod ("lfo3", "Ff_Morph", 0.25, "macro1"),
        mod ("lfo3", "Ff_Morph", 0.25, "modWheel"),
        mod ("random", "Ff_Cutoff", 0.05),
        mod ("random", "pan", 0.4),
        mod ("lfo2", "O1_PWM_W", 0.12),
        mod ("velocity", "Ff_Resonance", 0.2),
        mod ("velocity", "Cutoff", 0.05),
        mod ("aftertouch", "Ff_Cutoff", 0.15),
        mod ("aftertouch", "Ff_Resonance", 0.3),
        mod ("macro2", "Ff_Morph", 0.4),
        mod ("macro3", "Ff_Resonance", 0.3),
        mod ("macro4", "Ff_Drive", 0.4),
    ],
    tables: { wave1: harmonics (Array.from ({ length: 24 }, (_, i) => [i + 1, (i % 4 === 2 ? 0.6 : 1) / (i + 1)])) },
},

{
    name: "Step Filter", category: "sequence", tags: ["sample & hold", "parallel filters", "XY random walk", "drive"],
    description: "After Oatmeal's filterbleh: a saw and a narrow pulse an octave up through two parallel "
        + "resonant lowpasses that a stepping random LFO jumps every sixteenth (each note its own pattern), "
        + "while the XY pad's random walk wanders both cutoffs, into a heavy asymmetric drive and an irregular "
        + "chorus. Mod wheel: thirty-second steps; aftertouch: resonance. Macros: steps, wander, drive.",
    macros: ["steps", "wander", "drive", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, O2_Amp: 0.66, O2_PWM_W: 0.14, O2_PWM_R: 2.3, O2_PWM_D: 0.12,
        Transpose: 1,
        Filter: filter.lp4, Cutoff: 0.2, Resonance: 0.7, F_Double: 1, F_Track: 0.5,
        ...amp ({ a: 3, bp: 1, s: 1, r: 200 }),
        ...lfo (1, { sync: "perNote", shape: "steppingRandom", unit: "sixteenth", speed: 1 }),
        LFO_1_Quantize: 1, LFO_1_Cutoff_1: 0.75, LFO_1_Cutoff_2: 0.58, LFOPhaseRand: 1,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom" }), LFO_2_Pan: 0.13,
        XY_Var_Radius: 0.63, XY_Var_Rate: 0.44,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 19, Sat_Postgain: -14,
        C_Mode: 4, C_Stereo: 1, C_Voices: 2, C_Rate: 0.025, C_Depth: 13, C_Feedback: -0.72, C_Mix: 0.67,
        Macro_2: 0.6,
    },
    modulations: [
        mod ("x", "Cutoff", 0.15, "macro2"),
        mod ("y", "F_Split", 0.2, "macro2"),
        mod ("modWheel", "LFO_1_Speed", -0.1),
        mod ("aftertouch", "Resonance", 0.2),
        mod ("velocity", "Cutoff", 0.06),
        mod ("macro1", "LFO_1_Cutoff_1", 0.15),
        mod ("macro3", "Sat_Pregain", 0.1),
    ],
},
{
    name: "Chip Arp", category: "sequence", tags: ["arpeggiator", "chiptune", "pulse", "octaves"],
    description: "A chiptune arpeggio: hold a chord and the arpeggiator runs up it in sixteenths, each note "
        + "then its octave. Every step gets its own pulse duty (12.5, 25, 50 % and in between), a quick "
        + "chip-style vibrato comes in with the mod wheel, and notes spread by pitch. Aftertouch: a wider duty. "
        + "Macros: duty, echo.",
    macros: ["duty", "echo", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.25, VeloSens: 0.3,
        ...amp ({ a: 0.2, bp: 1, d2: 400, s: 0.55, r: 40 }),
        ...lfo (1, { sync: "perNote", shape: "tri", unit: "ms10", speed: 12 }),
        Arp_Mode: 1, Arp_Unit: 8, Arp_Quantize: 1,
        Arp_P0: 1, Arp_P1: 1, Arp_P2: 1, Arp_P3: 1, Arp_P4: 1, Arp_P5: 1, Arp_P6: 1, Arp_P7: 1, Arp_End: 7,
        Arp_Add_1_On: 1, Arp_Add_1_Shift: 12,
        FreqPan: 0.15,
        ...delay ({ unit: "sixteenth", length: 3, feedback: 0.3, wet: 0.1 }),
    },
    modulations: [
        mod ("random", "O1_PWM_W", 0.18),
        mod ("key", "O1_PWM_W", 0.05),
        mod ("lfo1", "finePitch", 0.4, "modWheel"),
        mod ("aftertouch", "O1_PWM_W", 0.2),
        mod ("macro1", "O1_PWM_W", 0.25),
        mod ("macro2", "D_Wet", 0.15),
    ],
},
{
    name: "Arp Bubbles", category: "sequence", tags: ["arpeggiator", "random", "bandpass", "delay"],
    description: "Hold a chord and the arpeggiator picks random notes from it in sixteenths, each followed by "
        + "its octave and its twelfth. Every note is a bubble: a sine and triangle through a resonant state-"
        + "variable bandpass whose cutoff lands somewhere new each time, with a little upward pitch blip, "
        + "scattered across the stereo field into a ping-pong delay. Mod wheel: resonance; aftertouch: more "
        + "echo. Macros: fizz, echo.",
    macros: ["fizz", "echo", "", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.4,
        Filter: filter.svf, F_Morph: 0.5, Cutoff: 0.55, Resonance: 0.55, F_Track: 0.6,
        ...amp ({ a: 0.3, bp: 1, d2: 900, s: 0, r: 120 }), Curve_Amp_Decay: 0.3,
        PEnv_On: 1, PEnv_Start: -5, PEnv_Attack: 35, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        Arp_Mode: 1, Arp_Unit: 8, Arp_Quantize: 1,
        Arp_P0: 15, Arp_P1: 15, Arp_P2: 15, Arp_P3: 15, Arp_P4: 15, Arp_P5: 15, Arp_P6: 15, Arp_P7: 15, Arp_End: 7,
        Arp_Add_1_On: 1, Arp_Add_1_Shift: 12, Arp_Add_2_On: 1, Arp_Add_2_Shift: 19,
        ...delay ({ unit: "sixteenth", length: 3, feedback: 0.4, wet: 0.15 }), D_Rotation: 1.5,
        R_On: 1, R_Size: 45, R_Length: 1.6, R_Wet: 0.08,
    },
    modulations: [
        mod ("random", "Cutoff", 0.15),
        mod ("random", "pan", 0.6),
        mod ("random", "F_Morph", 0.15),
        mod ("velocity", "Cutoff", 0.05),
        mod ("modWheel", "Resonance", 0.3),
        mod ("aftertouch", "D_Wet", 0.15),
        mod ("macro1", "Resonance", 0.3),
        mod ("macro2", "D_Wet", 0.15),
    ],
},

//------------------------------------------------------------------ fx and textures
{
    name: "Doppler Flyby", category: "fx", tags: ["per-voice pan", "one-shot LFO", "doppler"],
    description: "Each note flies past: a one-shot ramp sweeps it across the stereo field, in a random "
        + "direction for every note, while a second one-shot LFO with a drawn S-curve holds the pitch high on "
        + "the approach and drops it sharply as the note passes, about a fifth down, brightest at the closest "
        + "point. Every flyby's engine beats at its own rate. Hold notes for the full pass. Macros: distance, "
        + "drop.",
    macros: ["distance", "drop", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 3, O2_Amp: 0.6, N_Amp: 0.15,
        Filter: filter.svf, F_Morph: 0.25, Cutoff: 0.5, Resonance: 0.15,
        ...lfo (1, { sync: "perNote", shape: "saw", unit: "sec", speed: 3.2 }),
        LFO_1_OneShot: 1, LFOPhaseRand: 0,
        ...lfo (2, { sync: "perNote", shape: "user", unit: "sec", speed: 3.2 }),
        LFO_2_OneShot: 1,
        ...amp ({ a: 1500, bp: 1, d2: 1600, s: 0, r: 600 }), Curve_Amp_Attack: -0.5, Curve_Amp_Decay: -0.5,
        R_On: 1, R_Size: 80, R_Length: 2.5, R_Wet: 0.1,
        Macro_2: 0.6,
    },
    modulations: [
        mod ("lfo1", "pan", 1, "random"),
        mod ("lfo2", "pitch", 0.25, "macro2"),
        mod ("lfo1", "Cutoff", -0.12, "lfo1"),
        mod ("random", "Detune", 0.02),
        mod ("macro1", "Cutoff", -0.25),
        mod ("macro1", "R_Wet", 0.1),
    ],
    // high on the approach, a steep drop as the note passes, low as it goes away (LFO shapes are 0..1)
    tables: { lfoShape2: Float32Array.from ({ length: 512 }, (_, i) => 0.5 - 0.5 * Math.tanh (7 * (i / 511 - 0.5)) / Math.tanh (3.5)) },
},
{
    name: "Glass Spiral", category: "texture", tags: ["frequency shifter", "bode", "voice lane", "key shifter", "ambient"],
    description: "Glassy tones fed into the Bode frequency shifter's feedback delay: every echo comes back "
        + "shifted a little higher than the last, so each note spirals up into a shimmering cloud while the dry "
        + "note stays where it is. Before that, a key shifter in every voice adds partials moved by a fraction of "
        + "the note that each note draws at random, so every note glints with its own inharmonic edge. Each note's "
        + "sparkle (a glassy partial) is struck and fades, its ratio cast a little differently, and a slow LFO "
        + "drifts the spiral's speed. Notes land at random places in the stereo field. Mod wheel: a longer spiral; "
        + "aftertouch: more of it. Macros: shift, spiral, mix, glint.",
    macros: ["shift", "spiral", "mix", "glint"],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: ratio (3), O2_Amp: 0.12, Voices: 12,
        Filter: filter.svf, Cutoff: 0.6, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 4, bp: 1, d2: 1800, s: 0.3, r: 1800 }), Curve_Amp_Decay: 0.3,
        ...menv1 ({ a: 0.5, bp: 1, d2: 1500, s: 0, r: 500 }),
        ...lfo (2, { sync: "globalFree", unit: "sec", speed: 10 }),
        RandomPan: 0.5, Drift_Pitch: 3,
        ...lane (["Shifter"]),
        Sh_On: 1, Sh_Ratio: shiftRatio (0.25), Sh_Mode: shifterMode.up, Sh_Mix: 0.3,
        ...rack ("Chorus", "Bode", "Delay", "Reverb", "EQ", "Algo reverb"),
        Bd_On: 1, Bd_Shift: bodeHz (35), Bd_Mode: 0, Bd_Feedback: 0.55, Bd_Delay: bodeMs (220), Bd_Mix: 0.4,
        Rv_On: 1, Rv_Model: reverbModel.hall, Rv_Size: 0.5, Rv_Decay: reverbSeconds (2.5), Rv_Mix: 0.15,
        Macro_4: 0.5,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.15),
        mod ("random", "Transpose", 0.01),
        mod ("random", "Sh_Ratio", 0.12),
        mod ("lfo2", "Bd_Shift", 0.04),
        mod ("velocity", "Cutoff", 0.08),
        mod ("velocity", "Sh_Mix", 0.1),
        mod ("modWheel", "Bd_Feedback", 0.2),
        mod ("aftertouch", "Bd_Mix", 0.2),
        mod ("macro1", "Bd_Shift", 0.25),
        mod ("macro2", "Bd_Feedback", 0.3),
        mod ("macro3", "Bd_Mix", 0.3),
        mod ("macro4", "Sh_Mix", 0.3),
    ],
},
{
    name: "Tape Memory", category: "keys", tags: ["lo-fi", "tape", "voice lane", "wander", "wow and flutter"],
    description: "A worn tape keyboard: an old sampler in every voice, its sample rate kept on whole multiples of "
        + "the note so the grit stays in tune, then a tape model on the whole sound, heavy drift, a slow random wow "
        + "on pitch and echoes that run into the chorus (the delay comes first in the effects order). Each note "
        + "carries its own tape hiss, a fast random flutter and a slow wander off pitch of its own, the level wavers "
        + "like a stretched tape, every note is a little duller or brighter, and notes ring on for seconds after "
        + "the key is let go. Mod wheel: more wow; aftertouch: brighter. Macros: wear, echo, tape.",
    macros: ["wear", "echo", "tape", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.4,
        Filter: filter.lp2, Cutoff: 0.5, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, d2: 2500, s: 0.4, r: 3500 }), Curve_Amp_Decay: 0.3, Curve_Amp_Release: 0.35,
        N_Amp: 0.14,
        Drift_Pitch: 14, Drift_Rate: 0.8, Drift_Cutoff: 3,
        ...lfo (1, { sync: "globalFree", shape: "smoothRandom", unit: "ms10", speed: 60 }),
        LFO_1_Slew: 0.5,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom", unit: "ms", speed: 2 }),
        Wander_Rate: wanderHz (0.15),
        ...lane (["Distortion 2"]),
        Sat2_Type: dist.lofi, Sat2_Track: 1, Sat2_Drive: 0.35, Sat2_Tone: 0.4, Sat2_Mix: 0.7,
        Sat_Type: dist.tape, Sat_Mode: distMode.global, Sat_Drive: 0.4,
        FX_Order: 6, C_Mode: 4, C_Mix: 0.5,
        ...delay ({ unit: "eighth", length: 3, feedback: 0.45, wet: 0.18 }), D_LP: 0.5,
        EQ_1_Type: 3, EQ_1_Freq: 6000, EQ_1_Amp: -8, EQ_2_Type: 2, EQ_2_Freq: 150, EQ_2_Amp: 2,
        Macro_3: 0.5,
    },
    modulations: [
        mod ("lfo1", "finePitch", 0.1),
        mod ("lfo1", "finePitch", 0.15, "modWheel"),
        mod ("lfo1", "volume", 0.12),
        mod ("lfo2", "finePitch", 0.03),
        mod ("lfo2", "finePitch", 0.05, "macro1"),
        mod ("wander", "finePitch", 0.05),
        mod ("random", "Cutoff", 0.05),
        mod ("velocity", "Cutoff", 0.06),
        mod ("aftertouch", "Cutoff", 0.12),
        mod ("macro1", "Drift_Pitch", 0.4),
        mod ("macro1", "Sat2_Pregain", 0.1),
        mod ("macro1", "N_Amp", 0.08),
        mod ("macro2", "D_Wet", 0.1),
        mod ("macro3", "Sat_Drive", 0.3),
    ],
},
{
    name: "Rise Machine", category: "fx", tags: ["riser", "envelope curves", "supersaw"],
    description: "Hold a chord for an eight-second riser: a slow mod envelope, curved to accelerate towards "
        + "the top, raises the cutoff, the pitch, the resonance and the unison detune, brings in noise and "
        + "speeds up a tremolo that turns into a flutter at the top, then holds there. Macros: pitch rise.",
    macros: ["pitch rise", "", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 7, U_Detune: 30, U_DetuneCurve: 0.5, U_RandomPhase: 1, U_Spread: 0.8,
        U_Width: 1.4, N_Amp: 0.05,
        Filter: filter.svf, Cutoff: 0.22, Resonance: 0.35,
        ...menv1 ({ a: 8000, bp: 1, s: 1, r: 1500 }), Curve_Mod1_Attack: -0.6,
        ...lfo (2, { sync: "globalReset", shape: "tri", unit: "eighth", speed: 1 }),
        Macro_1: 1,
        ...amp ({ a: 50, bp: 1, s: 1, r: 1500 }),
        ...delay ({ unit: "eighth", length: [3, 4], wet: 0.2 }),
        R_On: 1, R_Size: 90, R_Length: 4, R_Wet: 0.18,
    },
    modulations: [
        mod ("modEnv1", "Cutoff", 0.5),
        mod ("modEnv1", "pitch", 0.5, "macro1"),
        mod ("modEnv1", "U_Detune", 0.1),
        mod ("modEnv1", "N_Amp", 0.2),
        mod ("modEnv1", "Resonance", 0.3),
        mod ("modEnv1", "LFO_2_Speed", -0.25),
        mod ("lfo2", "volume", 0.35, "modEnv1"),
        mod ("lfo2", "pan", 0.3, "modEnv1"),
    ],
},

{
    name: "Whoosh", category: "fx", tags: ["noise", "XY random walk", "resonant", "sweep"],
    description: "After Oatmeal's whoosh: resonant noise through a resonant lowpass swept by a per-note LFO, "
        + "whose depth and speed the XY pad's random walk keeps changing, while a random LFO pans it and also "
        + "modulates the sweep. Each whoosh swells open over a second and a half, harder notes further, and "
        + "the drive grows with it. Mod wheel: faster wandering; aftertouch: brighter. Macros: sweep, wander.",
    macros: ["sweep", "wander", "", ""],
    params: {
        O1_Amp: 0, N_Amp: 0.84, N_Resonance: 0.9,
        Filter: filter.lp4, Cutoff: 0.44, Resonance: 0.71, F_Track: 1,
        ...amp ({ a: 400, bp: 1, s: 1, r: 1200 }), Curve_Amp_Attack: -0.4,
        ...menv1 ({ a: 1500, bp: 1, s: 1, r: 1200 }),
        ...lfo (1, { sync: "perNote", unit: "ms10", speed: 35.7 }), LFO_1_Cutoff_1: 0.4,
        ...lfo (2, { sync: "perNote", shape: "smoothRandom" }), LFO_2_Pan: 0.33, LFO_2_1: 1,
        XY_Var_Radius: 1, XY_Var_Rate: 3.3,
        Sat_Type: dist.asym, Sat_Mode: distMode.double, Sat_Pregain: 8, Sat_Postgain: -6, Sat_Oversample: 1,
        C_Mode: 4, C_Stereo: 1, R_On: 1, R_Wet: 0.15,
        Macro_2: 0.7,
    },
    modulations: [
        mod ("x", "LFO_1_Cutoff_1", 0.2, "macro2"),
        mod ("y", "LFO_1_Speed", 0.08, "macro2"),
        mod ("modEnv1", "Cutoff", 0.2),
        mod ("modEnv1", "Cutoff", 0.1, "velocity"),
        mod ("modEnv1", "Sat_Pregain", 0.05),
        mod ("modWheel", "LFO_1_Speed", -0.08),
        mod ("aftertouch", "Cutoff", 0.12),
        mod ("macro1", "LFO_1_Cutoff_1", 0.2),
    ],
},
{
    name: "Reverse Swell", category: "fx", tags: ["reverse reverb", "swell", "convolution", "tremolo"],
    description: "Plays like a sound running backwards: each note swells in on a curve that rushes at the "
        + "end and stops short when let go, its filter and resonance opening with it and a tremolo speeding up "
        + "into it, through a reversed hall impulse (convolution), so the reverb rises towards each note "
        + "instead of trailing away from it. Mod wheel: a longer, wetter reverse; aftertouch: brighter. Macros: swell, "
        + "reverse.",
    macros: ["swell", "reverse", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.triHQ, Transpose: 1, O2_Amp: 0.5, U_Voices: 3, U_Detune: 12,
        U_Spread: 0.7, N_Amp: 0.05,
        Filter: filter.svf, Cutoff: 0.3, Resonance: 0.25, F_Track: 0.5,
        ...amp ({ a: 1600, bp: 1, s: 1, r: 25 }), Curve_Amp_Attack: -0.7,
        ...menv1 ({ a: 1600, bp: 1, s: 1, r: 25 }), Curve_Mod1_Attack: -0.7,
        ...lfo (2, { sync: "perNote", unit: "ms10", speed: 25 }),
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("hall"), Cv_Reverse: 1, Cv_Mix: 0.25, Cv_LowCut: hz (150),
        Macro_1: 0.6,
    },
    modulations: [
        mod ("modEnv1", "Cutoff", 0.35),
        mod ("modEnv1", "Resonance", 0.3),
        mod ("modEnv1", "LFO_2_Speed", -0.2),
        mod ("lfo2", "volume", 0.3, "modEnv1"),
        mod ("random", "finePitch", 0.05),
        mod ("modWheel", "Cv_Mix", 0.3),
        mod ("modWheel", "Resonance", 0.15),
        mod ("aftertouch", "Cutoff", 0.15),
        mod ("macro1", "Resonance", 0.2),
        mod ("macro2", "Cv_Mix", 0.3),
    ],
},

//------------------------------------------------------------------ drums
{
    name: "Oat Kick", category: "drums", tags: ["kick", "pitch envelope", "drive", "compressor"],
    description: "After Oatmeal's kick: a sine whose pitch envelope falls from thirty semitones up in a few "
        + "tens of milliseconds and settles a little below the note, with a click of noise on top, into an "
        + "asymmetric drive and a compressor. Velocity hits harder: higher, drier and more driven. Every kick "
        + "is tuned a hair differently. Play it around C2 to C3. Macros: drive, click, tune.",
    macros: ["drive", "click", "tune", ""],
    params: {
        O1_Waveform: wave.sine, OscPhaseRand: 0, OscRetrig: 1, VeloSens: 0.7,
        PEnv_On: 1, PEnv_Start: 30, PEnv_Attack: 25, PEnv_Peak: 0, PEnv_Decay: 250, PEnv_Sustain: -3,
        ...amp ({ a: 0.2, bp: 1, d2: 1400, s: 0, r: 120 }),
        ...menv2 ({ a: 0.2, bp: 1, d2: 25, s: 0, r: 10 }),
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 9, Sat_Postgain: -4,
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ"),
        ...glue (-16, 4, 2, 120, 3),
        Macro_2: 0.5,
    },
    modulations: [
        mod ("modEnv2", "N_Amp", 0.4, "macro2"),
        mod ("velocity", "Sat_Pregain", 0.08),
        mod ("velocity", "pitch", 0.03),
        mod ("random", "finePitch", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro3", "pitch", 0.25),
    ],
},
{
    name: "Porridge Snare", category: "drums", tags: ["snare", "noise", "EQ", "convolution"],
    description: "After Oatmeal's snareblah: a sine body whose pitch drops on the hit and fades out faster "
        + "than the noise of the wires, through a soft clipper, a bright peak and a shelf in the EQ, and a small "
        + "convolved room. Every hit's tone and the brightness of its wires are a little different, and harder "
        + "hits are brighter. Macros: body, wires, room.",
    macros: ["body", "wires", "room", ""],
    params: {
        O1_Waveform: wave.sine, O1_Amp: 2.3, N_Amp: 1.1, OscPhaseRand: 0, OscRetrig: 1, GlobalTranspose: -1,
        Filter: filter.svf, Cutoff: 0.8, Resonance: 0.1,
        PEnv_On: 1, PEnv_Start: 12, PEnv_Attack: 15, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        ...amp ({ a: 0.2, bp: 1, d2: 1100, s: 0, r: 150 }),
        ...menv1 ({ a: 120, bp: 1, s: 1, r: 20000 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 13,
        EQ_1_Type: eqType.highShelf, EQ_1_Freq: 2700, EQ_1_Amp: -7, EQ_1_Slope: 0.7,
        EQ_2_Type: eqType.peak, EQ_2_Freq: 8400, EQ_2_Amp: 9, EQ_2_Slope: 3.1,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.14,
        Macro_1: 0.5, Macro_2: 0.5,
    },
    modulations: [
        mod ("modEnv1", "O1_Amp", -0.4),
        mod ("random", "finePitch", 0.3),
        mod ("random", "Cutoff", 0.04),
        mod ("velocity", "Cutoff", 0.08),
        mod ("macro1", "O1_Amp", 0.1),
        mod ("macro2", "N_Amp", 0.1),
        mod ("macro3", "Cv_Mix", 0.3),
    ],
},
{
    name: "Hold Hat", category: "drums", tags: ["hi-hat", "ring modulation", "noise", "metallic"],
    description: "A hi-hat that opens while you hold the key: a tap is a closed hat, a held key rings open "
        + "and closes when you let go. Noise and two ring-modulated pulses at an inharmonic ratio (for the "
        + "metal) through a highpass, every hit's tone and position a little different, harder hits brighter. "
        + "Macros: tone, metal.",
    macros: ["tone", "metal", "", ""],
    params: {
        OscMix: mix.ring, O1_Waveform: wave.pulseHQ, O2_Waveform: wave.pulseHQ, Transpose: ratio (1.47), O1_Amp: 0.4,
        O2_Amp: 1, GlobalTranspose: 2, N_Amp: 0.8,
        Filter: filter.hp2, Cutoff: 0.86, Resonance: 0.2,
        ...amp ({ a: 0.2, d1: 40, bp: 0.3, d2: 2500, s: 0.2, r: 70 }),
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.08,
        Voices: 4,
        Macro_2: 0.4,
    },
    modulations: [
        mod ("random", "Cutoff", 0.03),
        mod ("random", "pan", 0.2),
        mod ("random", "Transpose", 0.01),
        mod ("velocity", "Cutoff", 0.05),
        mod ("macro1", "Cutoff", 0.08),
        mod ("macro2", "O1_Amp", 0.15),
    ],
},
{
    name: "Tank Tom", category: "drums", tags: ["tom", "pitch envelope", "convolution", "metal tank"],
    description: "A tom with an inharmonic second membrane mode, its pitch dropping an octave on the hit and "
        + "a stick click on top, ringing into a convolved metal tank. Every hit is tuned a little differently, "
        + "and harder hits start higher and click harder. Play it up the keyboard for a set of toms. Macros: "
        + "tank, stick.",
    macros: ["tank", "stick", "", ""],
    params: {
        O1_Waveform: wave.sine, O2_Waveform: wave.triHQ, Transpose: ratio (1.59), O2_Amp: 0.25,
        OscPhaseRand: 0, OscRetrig: 1, N_Resonance: 0.4,
        PEnv_On: 1, PEnv_Start: 12, PEnv_Attack: 0.2, PEnv_Peak: 12, PEnv_Decay: 120, PEnv_Sustain: 0,
        ...amp ({ a: 0.2, bp: 1, d2: 3500, s: 0, r: 300 }),
        ...menv1 ({ a: 0.2, bp: 1, d2: 600, s: 0, r: 50 }),
        ...menv2 ({ a: 0.2, bp: 1, d2: 30, s: 0, r: 10 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("metal tank"), Cv_Mix: 0.25, Cv_LowCut: hz (120),
        Macro_1: 0.5, Macro_2: 0.5,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", -0.15),
        mod ("modEnv2", "N_Amp", 0.35, "macro2"),
        mod ("velocity", "N_Amp", 0.06),
        mod ("velocity", "pitch", 0.04),
        mod ("random", "finePitch", 0.2),
        mod ("macro1", "Cv_Mix", 0.35),
    ],
},
{
    name: "Clap Stack", category: "drums", tags: ["clap", "noise", "bandpass", "room"],
    description: "A clap: bandpassed noise that a fast square LFO chops into a flurry of hands for the first "
        + "few tens of milliseconds, then a tail, into a small room. Each clap's flurry spacing, tone and place "
        + "are a little different, and harder hits are brighter. Macros: tone, room.",
    macros: ["tone", "room", "", ""],
    params: {
        O1_Amp: 0, N_Amp: 1.2,
        Filter: filter.svf, F_Morph: 0.5, Cutoff: 0.68, Resonance: 0.3,
        ...amp ({ a: 0.2, bp: 1, d2: 1300, s: 0, r: 150 }),
        ...menv1 ({ a: 0.2, bp: 1, d2: 220, s: 0, r: 10 }),
        ...lfo (1, { sync: "perNote", shape: "square", unit: "ms", speed: 9 }),
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.2,
    },
    modulations: [
        mod ("lfo1", "volume", 1, "modEnv1"),
        mod ("random", "LFO_1_Speed", 0.03),
        mod ("random", "Cutoff", 0.04),
        mod ("random", "pan", 0.15),
        mod ("velocity", "Cutoff", 0.06),
        mod ("macro1", "Cutoff", 0.1),
        mod ("macro2", "Cv_Mix", 0.3),
    ],
},


//------------------------------------------------------------------ init
{
    name: "Init Porridge", category: "init", tags: ["init"],
    description: "A starting point with Porridge's choices: an HQ saw, an open ladder filter with keytrack, "
        + "and a soft drive on each voice, ready for the macros and the modulation matrix.",
    macros: ["", "", "", ""],
    params: {
        // (both oscillators, as Init sets them)
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ,
        Filter: filter.ladder, Cutoff: 0.6, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, s: 1, r: 120 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 0,
    },
    modulations: [],
},
];

//==============================================================================
// Output gains, measured by rendering each program through the test host (tools/test/levels.mjs):
// a four-note chord (a single note for the mono programs) sits near -18 dB RMS over its loudest
// 300 ms, and a held five-note chord at full velocity peaks below -1 dBFS. Re-measure them after
// changing a program's sound.
const gains = {
    "Felt Piano": 0.382,
    "Crunch Clav": 0.2,
    "Rotary Fold": 0.0857,
    "Pulse Organ": 0.132,
    "Blorb Pulse": 0.194,
    "Phase Keys": 0.173,
    "Oat Field": 0.182,
    "Solina Phase": 0.215,
    "Stereo Swarm": 0.187,
    "Warm Wool": 0.191,
    "Vowel Choir": 0.521,
    "Comb String": 0.193,
    "Grit Bloom": 0.103,
    "Speckle Pad": 0.111,
    "Highpass Haze": 0.335,
    "Drive Dog": 0.386,
    "Ghost Tide": 0.112,
    "Future Chords": 0.482,
    "Tuned Jets": 0.084,
    "Velvet Lead": 0.449,
    "Fuzz Lead": 0.412,
    "Feedback Lead": 0.227,
    "MPE Sync Lead": 0.0657,
    "Trill Lead": 0.288,
    "Overwrought Sync": 0.111,
    "Shifter Lead": 0.223,
    "Tearout Screech": 0.989,
    "Sub Fold": 0.177,
    "Rubber Bass": 0.177,
    "Reese Drift": 0.349,
    "Acid Oats": 0.299,
    "Octave Bass": 0.383,
    "Wooly Bass": 0.141,
    "Snap Bass": 0.147,
    "Wub Bass": 0.756,
    "Growl Bass": 1.42,
    "Neuro Comb": 0.8,
    "Yoi Bass": 0.588,
    "Spring Twang": 0.325,
    "Resonator Pluck": 1.3,
    "Wide Harp": 0.154,
    "AM Bells": 0.081,
    "Just Bells": 0.129,
    "Folded Mallets": 0.0992,
    "Glass Pluck": 0.247,
    "Vlorg Glass": 0.0797,
    "Brassy Oats": 0.0984,
    "S&H Panner": 0.191,
    "Formant Steps": 0.264,
    "Step Filter": 0.374,
    "Chip Arp": 0.241,
    "Arp Bubbles": 1.35,
    "Doppler Flyby": 0.461,
    "Glass Spiral": 0.303,
    "Tape Memory": 0.248,
    "Rise Machine": 0.273,
    "Whoosh": 0.323,
    "Reverse Swell": 0.204,
    "Oat Kick": 0.231,
    "Porridge Snare": 0.183,
    "Hold Hat": 0.315,
    "Tank Tom": 0.203,
    "Clap Stack": 0.448,
    "Init Porridge": 0.285,
};

const doc = {
    porridge: "bank", version: 1, name: "Vanilla",
    presets: programs.map (p => ({
        name: p.name, author, category: p.category, tags: p.tags, description: p.description,
        params: { ...p.params, Gain: gains[p.name] ?? p.params.Gain ?? 0.1 },
        modulations: p.modulations, macros: p.macros,
        tables: Object.fromEntries (Object.entries (p.tables ?? {}).map (([k, t]) => [k, base64 (t)])),
        ...(p.tuning ? { tuning: p.tuning } : {}),
    })),
};

// check every key against the plugin's lists before writing
const parsed = Preset.parseJson (JSON.stringify (doc));
if (parsed.TAG !== "Ok") throw new Error (parsed._0);
const known = new Set (Preset.make ("x").values.keys());
for (const p of doc.presets)
{
    for (const id of Object.keys (p.params))
        if (! known.has (id)) throw new Error (`${p.name}: unknown parameter ${id}`);
    if (p.modulations.length > 16) throw new Error (`${p.name}: too many modulations`);
}
parsed._0.presets.forEach ((p, i) =>
{
    const want = doc.presets[i].modulations.length;
    const got = [...p.values].filter (([id, x]) => /^Mod\d+_Source$/.test (id) && x > 0).length;
    if (got !== want) throw new Error (`${p.meta.name}: ${want - got} modulations have an unknown source or target`);
});

// Oatmeal's chorus, delay, reverb and EQ leave the rack where they're switched off (the EQ: every
// band off), as they do from an Oatmeal import, so that no program shows idle effects
parsed._0.presets.forEach (p => Preset.withoutIdleEffects (p.values));

// and no program shows an effect that does nothing: every one in its rack and its voice lane is on
for (const p of parsed._0.presets)
{
    const get = id => p.values.get (id) ?? 0;
    for (const e of [...FxRack.read (get), ...FxRack.readLane (get)])
        if (! FxRack.isOn (e, get)) throw new Error (`${p.meta.name}: its ${FxRack.kindName (e.kind)} is off`);
}

const out = join (root, "presets", "vanilla.porridge");
writeFileSync (out, Preset.writeBank (parsed._0.presets, "Vanilla"));
console.log (`wrote ${parsed._0.presets.length} programs to presets/vanilla.porridge`);
