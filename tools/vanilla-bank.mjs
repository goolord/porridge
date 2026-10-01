// Builds presets/vanilla.porridge, Porridge's own preset bank: programs made for the features
// Oatmeal doesn't have (per-voice distortion and panning driven by the modulation matrix, the
// HQ waveforms, PM/ring/AM, Porridge's filter types, envelope curves, the LFO extras, unison
// width, drift, the effects rack and its own effects, macros, MPE and microtuning).
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
import * as PorridgeParams from "../ui/PorridgeParams.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");
const author = "Porridge";

//==============================================================================
// helpers

// list values
const wave = { sine: 0, saw: 1, pulse: 2, tri: 3, user: 4, userPwm: 5, sawHQ: 6, pulseHQ: 7, triHQ: 8 };
const mix = { normal: 0, sync: 1, fm: 2, pm: 3, pmFeedback: 4, ring: 5, am: 6 };
const filter = { off: 0, lp2: 2, lp4: 3, hp2: 5, bpWide: 7, bp: 8, nlLp4: 12, svf: 16, ladder: 17, diode: 18,
                 sallenKey: 19, comb: 20, formant: 21,
                 mgLow12: FilterTypes.index ("MG low 12"), acid: FilterTypes.index ("acid ladder"),
                 cleanDrive: FilterTypes.index ("clean drive"), combPlus: FilterTypes.index ("comb +"),
                 formant2: FilterTypes.index ("formant II") };
const dist = { off: 0, hard: 1, soft: 2, sine: 3, asym: 4 };
const distMode = { global: 0, voicePost: 1, voicePre: 2, double: 3 };
const lfoUnit = { ms: 0, ms10: 1, sec: 2, sixteenth: 5, eighth: 8, quarter: 11, half: 14, whole: 17 };
const lfoShape = { sine: 0, saw: 1, square: 2, tri: 3, smoothRandom: 4, steppingRandom: 5, user: 6 };
const lfoMode = { perNote: 0, globalReset: 1, globalFree: 2 };
const steps = { off: 0, 2: 1, 3: 2, 4: 3, 6: 4, 8: 5, 12: 6, 16: 7, 24: 8, 32: 9 };
const delayUnit = { ms: 0, sixteenth: 5, eighth: 8, quarter: 11 };
const poly = { mono: 0, poly: 1, legato: 2 };

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

const mod = (source, target, amount, via) => via ? { source, target, amount, via } : { source, target, amount };

// the effects rack, slot by slot, by the names in its menu; Oatmeal's chorus, delay, reverb and
// EQ stay in their slots unless they're left out
const rack = (...names) => Object.fromEntries (Array.from ({ length: PorridgeParams.rackSlots }, (_, i) =>
{
    const k = names[i] === undefined ? 0 : PorridgeParams.rackNames.indexOf (names[i]);
    if (k < 0) throw new Error ("no rack entry " + names[i]);
    return [PorridgeParams.rackId (i + 1), k];
}));

// knob positions of the rack effects' frequencies and times (lo · (hi / lo) ^ knob)
const knob = (lo, hi) => x => PorridgeParams.expPos (lo, hi, x);
const hz = knob (20, 20000);
const fxRate = knob (0.02, 20);
const compAttack = knob (0.1, 300), compRelease = knob (5, 3000);
const flangerMs = knob (0.1, 20), bodeMs = knob (1, 1000), reverbSeconds = knob (0.1, 30);
const bodeHz = PorridgeParams.bodeShiftValue;
const bassMono = PorridgeParams.bassMonoValue;
const impulse = name => PorridgeParams.impulseNames.indexOf (name);
const reverbModel = { hall: 0, plate: 1, nitrous: 2, basin: 3, vintage: 4 };
const eqType = { off: 0, peak: 1, lowShelf: 2, highShelf: 3 };

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
    name: "Felt Piano", category: "keys", tags: ["piano", "analog filter", "convolution", "compressor"],
    description: "A soft, close felt piano: triangle and sine through an MG lowpass whose envelope follows "
        + "velocity, with a short felt thump of pitched noise on each hammer. A gentle compressor evens the "
        + "touch and a small convolved room sits behind it. Macros: hammer, tone, room.",
    macros: ["hammer", "tone", "room", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.22, VeloSens: 0.8,
        N_Resonance: 0.7, N_Transpose: 12,
        Filter: filter.mgLow12, Cutoff: 0.36, Resonance: 0.08, F_Track: 0.7, F_EnvMod: 0.3, F_VeloSens: 0.7,
        ...fenv ({ a: 0.5, bp: 1, d2: 700, s: 0.12, r: 300 }), Curve_Filter_Decay: 0.4,
        ...amp ({ a: 1.5, d1: 500, bp: 0.45, d2: 11000, s: 0, r: 380 }),
        ...menv2 ({ a: 0.3, bp: 1, d2: 120, s: 0, r: 40 }),
        Drift_Pitch: 2,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Compressor", "Convolve"),
        ...glue (-22, 2.5, 15, 160, 3),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.12, Cv_LowCut: hz (150),
    },
    modulations: [
        mod ("modEnv2", "N_Amp", 0.38),
        mod ("velocity", "Cutoff", 0.08),
        mod ("macro1", "F_EnvMod", 0.15),
        mod ("macro1", "N_Amp", 0.1),
        mod ("macro2", "Cutoff", 0.2),
        mod ("macro3", "Cv_Mix", 0.3),
    ],
},
{
    name: "Crunch Clav", category: "keys", tags: ["clavinet", "per-voice drive", "funk"],
    description: "A clavinet with an asymmetric drive in front of each note's filter: velocity sets the crunch, "
        + "and the state-variable filter sits between lowpass and bandpass. Notes spread across the stereo "
        + "field by key. Macros: bite, wah.",
    macros: ["bite", "wah", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.22, O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.35,
        Filter: filter.svf, F_Morph: 0.35, Cutoff: 0.33, Resonance: 0.35, F_Track: 0.5, F_EnvMod: 0.3, F_VeloSens: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 260, s: 0.1, r: 80 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 0.4, bp: 1, d2: 1400, s: 0.15, r: 90 }), Curve_Amp_Decay: 0.4,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePre, Sat_Pregain: 6, Sat_Postgain: -6,
        RandomPan: 0.15,
        D_On: 1, D_Unit: delayUnit.ms, D_LengthL: 70, D_LengthR: 95, D_FeedbackL: 0.15, D_FeedbackR: 0.15, D_Wet: 0.08,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.2),
        mod ("key", "pan", 0.9),
        mod ("macro1", "Sat_Pregain", 0.25),
        mod ("macro2", "Cutoff", 0.35),
    ],
},
{
    name: "Rotary Fold", category: "organ", tags: ["organ", "wavefolder", "per-voice pan"],
    description: "A drawbar organ through a sine wavefolder on every voice. Each note has its own rotor: a "
        + "panning, slightly detuning LFO that starts at a random phase. The mod wheel (or macro 2) speeds the "
        + "rotors up. Macros: fold, rotor speed, rotor depth.",
    macros: ["fold", "rotor speed", "rotor depth", ""],
    params: {
        O1_Waveform: wave.user, VeloSens: 0,
        ...amp ({ a: 3, bp: 1, s: 1, r: 45 }),
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -11,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 40, LFO_1_Pan: 0.3, LFO_1_Pitch: 0.22,
        LFOPhaseRand: 1, LFO_1_Slew: 0.3,
        FreqPan: 0.05, Drift_Pitch: 3,
        C_Mode: 1, C_Mix: 0.25,
        Macro_3: 0.4,
    },
    modulations: [
        mod ("modWheel", "LFO_1_Speed", -0.07),
        mod ("macro2", "LFO_1_Speed", -0.07),
        mod ("macro1", "Sat_Pregain", 0.13),
        mod ("macro3", "LFO_1_Pan", 0.4),
    ],
    tables: { wave1: harmonics ([[1, 1], [2, 0.7], [3, 0.5], [4, 0.45], [6, 0.3], [8, 0.3], [10, 0.12], [12, 0.15]]) },
},

//------------------------------------------------------------------ pads
{
    name: "Oat Field", category: "pad", tags: ["supersaw", "unison", "drift", "wide"],
    description: "Seven-voice HQ supersaw with a supersaw-style detune curve, random unison phases and extra "
        + "stereo width, slowly drifting in pitch and cutoff like an old polysynth. Macros: brightness, width, drift.",
    macros: ["brightness", "width", "drift", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: -1, O2_Amp: 0.45,
        U_Voices: 7, U_Detune: 32, U_DetuneCurve: 0.7, U_RandomPhase: 1, U_Spread: 0.9, U_Width: 1.5, U_PanJitter: 0.3,
        Filter: filter.svf, Cutoff: 0.42, Resonance: 0.12, F_Track: 0.5,
        ...amp ({ a: 900, bp: 1, s: 1, r: 2600 }), Curve_Amp_Attack: -0.3, Curve_Amp_Release: 0.3,
        Drift_Pitch: 6, Drift_Cutoff: 1.5, Drift_Rate: 0.3, RandomPan: 0.3,
        LFO_2_Sync: lfoMode.globalFree, LFO_2_Unit: lfoUnit.sec, LFO_2_Speed: 9,
        R_On: 1, R_Size: 65, R_Length: 3.5, R_Wet: 0.14, R_Dullness: 0.6,
    },
    modulations: [
        mod ("lfo2", "Cutoff", 0.05),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "U_Width", 0.25),
        mod ("macro3", "Drift_Pitch", 0.3),
    ],
},
{
    name: "Solina Phase", category: "pad", tags: ["string machine", "phaser", "ensemble"],
    description: "A string machine: two saws an octave apart through a soft MG lowpass, a three-voice ensemble "
        + "chorus, then the rack's phaser sweeping slowly with some feedback. Macros: phase, ensemble, brightness.",
    macros: ["phase", "ensemble", "brightness", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 1, Detune: 0.4, O2_Amp: 0.55,
        Filter: filter.mgLow12, Cutoff: 0.55, Resonance: 0.05, F_Track: 0.5,
        ...amp ({ a: 350, bp: 1, s: 1, r: 1100 }), Curve_Amp_Attack: -0.2, Curve_Amp_Release: 0.3,
        Drift_Pitch: 4, RandomPan: 0.2,
        ...rack ("Chorus", "Phaser", "Delay", "Reverb", "EQ"),
        C_Mode: 1, C_Stereo: 2, C_Voices: 3, C_Rate: 0.7, C_MinDelay: 5, C_Depth: 4, C_Mix: 0.5,
        Ph_On: 1, Ph_Rate: fxRate (0.12), Ph_Depth: 0.75, Ph_Freq: hz (700), Ph_Feedback: 0.45, Ph_Stages: 1,
        Ph_Spread: 0.4, Ph_Mix: 0.5,
        R_On: 1, R_Size: 55, R_Length: 2.2, R_Wet: 0.1,
        Macro_1: 0.5, Macro_2: 0.5,
    },
    modulations: [
        mod ("macro1", "Ph_Mix", 0.3),
        mod ("macro1", "Ph_Feedback", 0.15),
        mod ("macro2", "C_Mix", 0.25),
        mod ("macro3", "Cutoff", 0.25),
        mod ("velocity", "Cutoff", 0.05),
    ],
},
{
    name: "Stereo Swarm", category: "pad", tags: ["per-voice pan", "motion", "ambient"],
    description: "Every note lives its own life. A per-note LFO circles it around the stereo field from a "
        + "random phase, higher notes orbit faster and each note at its own speed. A random LFO per note wanders "
        + "its pitch, cutoff, position and osc balance, every note is detuned by its own few cents, and a slow "
        + "envelope opens some notes and closes others. Macros: orbit, orbit speed, brightness, wander.",
    macros: ["orbit", "orbit speed", "brightness", "wander"],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.7, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.4, Resonance: 0.2, F_Track: 0.4,
        ...amp ({ a: 1200, bp: 1, s: 1, r: 3200 }), Curve_Amp_Attack: -0.4, Curve_Amp_Release: 0.4,
        ...menv1 ({ a: 4000, bp: 1, s: 1, r: 3000 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 3, LFO_1_Pan: 0.42,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Shape: lfoShape.smoothRandom, LFO_2_Unit: lfoUnit.sec, LFO_2_Speed: 2,
        LFO_2_Cutoff_1: 0.12, LFO_2_Pan: 0.12, LFOPhaseRand: 1,
        R_On: 1, R_Size: 70, R_Length: 3.5, R_Wet: 0.13, D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 4,
        D_FeedbackL: 0.4, D_FeedbackR: 0.4, D_Wet: 0.1,
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
        mod ("macro1", "LFO_1_Pan", 0.3),
        mod ("macro2", "LFO_1_Speed", -0.05),
        mod ("macro3", "Cutoff", 0.3),
    ],
},
{
    name: "Warm Wool", category: "pad", tags: ["ladder", "per-voice drive", "analog"],
    description: "Soft saturation in front of each note's ladder filter, so the filter rounds off the drive. "
        + "Play harder for more fuzz. PWM, drift and a slow filter envelope keep it moving. Macros: warmth, cutoff.",
    macros: ["warmth", "cutoff", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, O2_PWM_W: 0.4, O2_PWM_R: 0.3, O2_PWM_D: 0.3,
        Transpose: 0, Detune: -0.6, O2_Amp: 0.7,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePre, Sat_Pregain: 10, Sat_Postgain: -8,
        Filter: filter.ladder, Cutoff: 0.3, Resonance: 0.35, F_Track: 0.4, F_EnvMod: 0.15,
        ...fenv ({ a: 1500, bp: 1, d2: 3000, s: 0.6, r: 1500 }),
        ...amp ({ a: 600, bp: 1, s: 0.9, r: 1800 }), Curve_Amp_Attack: -0.4,
        Drift_Cutoff: 2, Drift_Pitch: 4, RandomPan: 0.35,
        C_Mode: 1, C_Mix: 0.4, R_On: 1, R_Size: 50, R_Length: 2, R_Wet: 0.09,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "Cutoff", 0.3),
    ],
},
{
    name: "Vowel Choir", category: "pad", tags: ["formant", "choir", "per-voice motion"],
    description: "Formant filter voices: each note starts on its own vowel and wanders between vowels with "
        + "its own random LFO, and the vibrato fades in after a moment (LFO delay and fade-in). Macros: vowel, "
        + "wander.",
    macros: ["vowel", "wander", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 3, U_Detune: 12, U_Spread: 0.6,
        O2_Waveform: wave.pulseHQ, Transpose: 0, Detune: 0.4, O2_Amp: 0.3,
        Filter: filter.formant, Cutoff: 0.37, Resonance: 0.3, F_Track: 0.4, F_Morph: 0.3,
        ...amp ({ a: 500, bp: 1, s: 1, r: 1600 }), Curve_Amp_Attack: -0.3,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Shape: lfoShape.smoothRandom, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 3,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Unit: lfoUnit.ms10, LFO_2_Speed: 19, LFO_2_Pitch: 0.33,
        LFO_2_Delay: 400, LFO_2_Fade: 900, LFOPhaseRand: 1,
        RandomPan: 0.6, FreqPan: 0.08,
        C_Mode: 1, C_Mix: 0.35, R_On: 1, R_Size: 75, R_Length: 3, R_Wet: 0.17,
        Macro_2: 0.5,
    },
    modulations: [
        mod ("random", "F_Morph", 0.15),
        mod ("lfo1", "F_Morph", 0.4, "macro2"),
        mod ("macro1", "F_Morph", 0.6),
    ],
},
{
    name: "Comb String", category: "pad", tags: ["comb", "karplus", "bowed"],
    description: "Noise bowing a comb filter tuned to each note, with a little saw for body: a bowed string "
        + "that changes character with the comb's feedback polarity (macro 2). The bow noise is itself tuned to "
        + "the note and a high shelf takes the hiss off the top, so it stays warm. Macros: resonance, polarity, air.",
    macros: ["resonance", "polarity", "air", ""],
    params: {
        O1_Amp: 0.12, O1_Waveform: wave.sawHQ, N_Amp: 0.5, N_Resonance: 0.3,
        Filter: filter.comb, Cutoff: 0.276, F_Track: 1, Resonance: 0.9, F_Morph: 0,
        ...amp ({ a: 250, bp: 1, s: 1, r: 1800 }), Curve_Amp_Attack: -0.2,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 4, LFO_1_Pan: 0.15, LFOPhaseRand: 1,
        RandomPan: 0.5,
        FX_Order: 2, R_On: 1, R_Size: 65, R_Length: 3, R_Wet: 0.12,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.4, D_FeedbackR: 0.4, D_Wet: 0.1,
        EQ_1_Type: eqType.highShelf, EQ_1_Freq: 3500, EQ_1_Amp: -8,
    },
    modulations: [
        mod ("macro1", "Resonance", 0.09),
        mod ("macro2", "F_Morph", 1),
        mod ("macro3", "N_Resonance", -0.3),
        mod ("macro3", "EQ_1_Amp", 0.06),
    ],
},
{
    name: "Grit Bloom", category: "pad", tags: ["per-voice drive", "per-voice pan", "evolving"],
    description: "A clean pad that grows grit: a slow mod envelope raises each note's distortion drive and "
        + "cutoff, and moves the note out from the centre, each one to its own random side. As it blooms the "
        + "filter's resonance rises and a slow per-note LFO starts sweeping that peak through the upper "
        + "harmonics, every note at its own phase, so the top end shimmers and shifts while the grit grows. "
        + "Macros: grit, bloom, shimmer.",
    macros: ["grit", "bloom", "shimmer", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: semis (7), O2_Amp: 0.4,
        Filter: filter.svf, Cutoff: 0.33, Resonance: 0.2, F_Track: 0.4,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: -6,
        ...menv1 ({ a: 2600, bp: 1, s: 1, r: 2000 }), Curve_Mod1_Attack: -0.3,
        ...amp ({ a: 380, bp: 1, s: 1, r: 2200 }), Curve_Amp_Attack: -0.2,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Shape: lfoShape.tri, LFO_2_Unit: lfoUnit.sec, LFO_2_Speed: 3.5, LFOPhaseRand: 1,
        ...rack ("Chorus", "Phaser", "Delay", "Reverb", "EQ"),
        Ph_On: 1, Ph_Rate: fxRate (0.13), Ph_Depth: 0.6, Ph_Freq: hz (2500), Ph_Feedback: 0.6, Ph_Stages: 3,
        Ph_Spread: 0.6, Ph_Mix: 0,
        R_On: 1, R_Size: 55, R_Length: 2.5, R_Wet: 0.1,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 4, D_FeedbackL: 0.35, D_FeedbackR: 0.35, D_Wet: 0.07,
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
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ leads
{
    name: "Velvet Lead", category: "lead", tags: ["mono", "ladder", "vibrato", "compressor"],
    description: "A legato ladder lead with glide. The vibrato waits, then fades in (LFO delay and fade-in), "
        + "and the mod wheel adds more. A gentle compressor holds it steady in front of the delay. Macros: drive, "
        + "cutoff.",
    macros: ["drive", "cutoff", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 60, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, O2_PWM_W: 0.45, Transpose: 0, Detune: 0.8, O2_Amp: 0.6,
        Filter: filter.ladder, Cutoff: 0.42, Resonance: 0.35, F_Track: 0.5, F_EnvMod: 0.22,
        ...fenv ({ a: 5, bp: 1, d2: 600, s: 0.4, r: 300 }),
        ...amp ({ a: 8, bp: 1, s: 1, r: 260 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 18, LFO_1_Pitch: 0.36,
        LFO_1_Delay: 350, LFO_1_Fade: 600,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -3,
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ"),
        ...glue (-20, 3, 8, 120, 4),
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.35, D_FeedbackR: 0.35, D_Wet: 0.13,
    },
    modulations: [
        mod ("modWheel", "LFO_1_Pitch", 0.15),
        mod ("macro1", "Sat_Pregain", 0.2),
        mod ("macro2", "Cutoff", 0.3),
    ],
},
{
    name: "Fuzz Lead", category: "lead", tags: ["mono", "fuzz", "convolution", "cabinet"],
    description: "Two detuned saws through an asymmetric clipper (4x oversampled) after the filter, so the "
        + "clipper sees every harmonic and the two saws grind against each other, then a 1×12 guitar cabinet "
        + "(convolved) takes the fizz off. It starts as a crunch: the mod wheel turns it into full fuzz. Macros: "
        + "fuzz, cutoff, cabinet.",
    macros: ["fuzz", "cutoff", "cabinet", ""],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 1.2, O2_Amp: 0.8,
        Filter: filter.mgLow12, Cutoff: 0.66, Resonance: 0.15, F_EnvMod: 0.1, F_Track: 0.5,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Oversample: 2, Sat_Pregain: 20, Sat_Postgain: -14,
        ...fenv ({ a: 2, bp: 1, d2: 400, s: 0.3, r: 200 }),
        ...amp ({ a: 3, bp: 1, s: 1, r: 180 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 17, LFO_1_Pitch: 0.38,
        LFO_1_Delay: 500, LFO_1_Fade: 500,
        ...rack ("Chorus", "Convolve", "Delay", "Reverb", "EQ"),
        Cv_On: 1, Cv_Impulse: impulse ("cabinet 1×12"), Cv_Mix: 1, Cv_Gain: -6,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 2, D_FeedbackL: 0.3, D_FeedbackR: 0.3, D_Wet: 0.1,
    },
    modulations: [
        mod ("modWheel", "Sat_Pregain", 0.15),
        mod ("modWheel", "Cutoff", 0.06),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "Cutoff", 0.3),
        mod ("macro3", "Cv_Mix", -0.6),
    ],
},
{
    name: "Feedback Lead", category: "lead", tags: ["phase modulation", "feedback", "mono"],
    description: "Oscillator 1 phase-modulates itself (osc mix: PM 1 feedback), from a sine towards a saw. A "
        + "mod envelope and velocity open the feedback on each note's attack; osc 2 adds a sine sub. Macros: "
        + "feedback.",
    macros: ["feedback", "", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 40, GlideMode: 0,
        OscMix: mix.pmFeedback, O1_Waveform: wave.sine, PM_Feedback: 0.45, O2_Waveform: wave.sine, Transpose: -1, O2_Amp: 0.45,
        ...menv1 ({ a: 1, bp: 1, d2: 700, s: 0.3, r: 200 }),
        ...amp ({ a: 4, bp: 1, s: 1, r: 220 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 18, LFO_1_Pitch: 0.34,
        LFO_1_Delay: 300, LFO_1_Fade: 700,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 3,
        D_On: 1, D_Unit: delayUnit.quarter, D_LengthL: 1, D_LengthR: 1, D_Rotation: 1.2, D_Wet: 0.11,
    },
    modulations: [
        mod ("modEnv1", "PM_Feedback", 0.3),
        mod ("velocity", "PM_Feedback", 0.15),
        mod ("macro1", "PM_Feedback", 0.4),
    ],
},
{
    name: "MPE Glide Lead", category: "lead", tags: ["MPE", "per-voice drive", "per-voice pan", "expressive"],
    description: "For MPE controllers (MPE on): each note's slide opens its filter, its pressure drives its "
        + "own distortion and vibrato, and its pitch bend also moves it in the stereo field. With a normal "
        + "keyboard, aftertouch and the bend wheel do the same for every note.",
    macros: ["", "", "", ""],
    params: {
        MPE_On: 1, MPE_BendRange: 48, AftertouchMode: 2,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.triHQ, Transpose: 1, O2_Amp: 0.4,
        Filter: filter.ladder, Cutoff: 0.3, Resonance: 0.3, F_Track: 0.5,
        ...amp ({ a: 10, bp: 1, s: 1, r: 400 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 0,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 18, LFOPhaseRand: 1,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.3, D_FeedbackR: 0.3, D_Wet: 0.08,
    },
    modulations: [
        mod ("slide", "Cutoff", 0.4),
        mod ("aftertouch", "Sat_Pregain", 0.25),
        mod ("aftertouch", "LFO_1_Pitch", 0.4),
        mod ("bend", "pan", 0.5),
    ],
},

//------------------------------------------------------------------ bass
{
    name: "Chew Bass", category: "bass", tags: ["per-voice drive", "diode ladder", "mono"],
    description: "A resonant diode ladder chewing in front of an asymmetric drive on the voice: the filter "
        + "envelope and an eighth-note LFO keep the resonant peak moving, and the drive after it turns the "
        + "peak into a snarl. Velocity adds drive, and low notes are driven harder than high ones, so the line "
        + "grows teeth as it goes down. Macros: chew, drive, cutoff.",
    macros: ["chew", "drive", "cutoff", ""],
    params: {
        PolyMode: poly.legato, Glide: 25, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, Transpose: -1, O2_Amp: 0.6,
        Filter: filter.diode, Cutoff: 0.27, Resonance: 0.74, F_EnvMod: 0.5, F_VeloSens: 0.5, F_Track: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 300, s: 0.15, r: 120 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 1, bp: 1, s: 0.8, r: 60 }),
        LFO_2_Sync: lfoMode.globalReset, LFO_2_Shape: lfoShape.tri, LFO_2_Unit: lfoUnit.eighth, LFO_2_Speed: 1,
        LFO_2_Quantize: 1,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 12, Sat_Postgain: -9,
        Macro_1: 0.5,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("key", "Sat_Pregain", -0.2),
        mod ("lfo2", "Cutoff", 0.12, "macro1"),
        mod ("macro1", "Resonance", 0.15),
        mod ("macro2", "Sat_Pregain", 0.15),
        mod ("macro3", "Cutoff", 0.25),
    ],
},
{
    name: "Sub Fold", category: "bass", tags: ["wavefolder", "per-voice drive", "sub"],
    description: "A pure sine sub, with a quiet sine an octave up so it carries on small speakers. A short "
        + "mod envelope and velocity drive each note's attack into a wavefolder (sine distortion) in front of a "
        + "keytracked ladder whose envelope lets the folds through only at the start, so the note settles back "
        + "to a round sub. Macros: fold, octave.",
    macros: ["fold", "octave", "", ""],
    params: {
        PolyMode: poly.mono,
        O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.1,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePre, Sat_Pregain: -30,
        Filter: filter.ladder, Cutoff: 0.5, Resonance: 0.05, F_Track: 1, F_EnvMod: 0.3,
        ...fenv ({ a: 0.5, bp: 1, d2: 300, s: 0, r: 100 }),
        ...menv1 ({ a: 0.5, bp: 1, d2: 300, s: 0, r: 100 }),
        ...amp ({ a: 1, bp: 1, s: 1, r: 80 }),
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.35),
        mod ("velocity", "Sat_Pregain", 0.08),
        mod ("macro1", "Sat_Pregain", 0.12),
        mod ("macro2", "O2_Amp", 0.15),
    ],
},
{
    name: "Rubber Bass", category: "bass", tags: ["phase modulation", "pitch envelope"],
    description: "A clean phase-modulation bass, an octave below the keys: osc 2 an octave up modulates osc 1, "
        + "with a short envelope on the modulation depth and a quick pitch drop for the thump. Macros: bounce.",
    macros: ["bounce", "", "", ""],
    params: {
        PolyMode: poly.mono, GlobalTranspose: -1,
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.5,
        ...menv1 ({ a: 0.5, bp: 1, d2: 260, s: 0, r: 100 }), Curve_Mod1_Decay: 0.4,
        PEnv_On: 1, PEnv_Start: 0, PEnv_Attack: 0.2, PEnv_Peak: 12, PEnv_Decay: 45, PEnv_Sustain: 0,
        ...amp ({ a: 1, bp: 1, s: 1, r: 90 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 5, Sat_Postgain: -2,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.15),
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("macro1", "O2_Amp", 0.15),
    ],
},
{
    name: "Reese Drift", category: "bass", tags: ["reese", "unison", "drift", "SVF"],
    description: "Two detuned HQ saws with unison and analog drift, through a state-variable filter whose "
        + "slow LFO morphs it between lowpass and bandpass. Macros: growl, drive.",
    macros: ["growl", "drive", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 20, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 2.2, O2_Amp: 1,
        U_Voices: 3, U_Detune: 30, U_Spread: 0.5, U_Width: 1.2,
        Drift_Pitch: 12, Drift_Rate: 0.6,
        Filter: filter.svf, F_Morph: 0.1, Cutoff: 0.33, Resonance: 0.25, F_Track: 0.5,
        LFO_1_Sync: lfoMode.globalFree, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 6,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 8, Sat_Postgain: -5,
        ...amp ({ a: 2, bp: 1, s: 1, r: 120 }),
    },
    modulations: [
        mod ("lfo1", "F_Morph", 0.15),
        mod ("macro1", "F_Morph", 0.5),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Acid Oats", category: "bass", tags: ["acid", "diode ladder", "per-voice drive"],
    description: "A 303-style line: diode ladder near self-oscillation, a snappy filter envelope and glide, "
        + "into an asymmetric drive. Velocity works as accent, opening the envelope and adding grit. Macros: "
        + "cutoff, resonance, env mod, drive.",
    macros: ["cutoff", "resonance", "env mod", "drive"],
    params: {
        PolyMode: poly.legato, Glide: 45, GlideMode: 0,
        O1_Waveform: wave.sawHQ,
        Filter: filter.diode, Cutoff: 0.27, Resonance: 0.85, F_EnvMod: 0.55, F_VeloSens: 0.6, F_Track: 0.3,
        ...fenv ({ a: 0.2, bp: 1, d2: 280, s: 0, r: 80 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 1, bp: 1, d2: 1200, s: 0.6, r: 50 }),
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 10, Sat_Postgain: -7,
        D_On: 1, D_Unit: delayUnit.sixteenth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.35, D_FeedbackR: 0.35, D_Wet: 0.1,
        Macro_3: 0.3, Macro_4: 0.3,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "Resonance", 0.25),
        mod ("macro3", "F_EnvMod", 0.25),
        mod ("macro4", "Sat_Pregain", 0.15),
    ],
},

{
    name: "Talk Bass", category: "bass", tags: ["formant", "vowel", "mono", "compressor"],
    description: "A bass that talks: a saw and a square an octave down through a formant filter. Each note's "
        + "mod envelope sweeps the vowel and an eighth-note LFO makes held notes yap, then a soft drive, a "
        + "compressor and a bass-mono utility keep it solid. Macros: talk, vowel, drive.",
    macros: ["talk", "vowel", "drive", ""],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, Transpose: -1, O2_Amp: 0.5,
        Filter: filter.formant2, Cutoff: 0.45, Resonance: 0.5, F_Track: 0.3, F_Morph: 0.1,
        ...menv1 ({ a: 60, bp: 1, d2: 350, s: 0.25, r: 150 }),
        ...amp ({ a: 2, bp: 1, s: 1, r: 90 }),
        LFO_2_Sync: lfoMode.globalReset, LFO_2_Shape: lfoShape.tri, LFO_2_Unit: lfoUnit.eighth, LFO_2_Speed: 1,
        LFO_2_Quantize: 1,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 8, Sat_Postgain: -5,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Compressor", "Utility"),
        ...glue (-20, 3, 5, 90, 3),
        Ut_On: 1, Ut_BassMono: bassMono (150),
        Macro_1: 0.4,
    },
    modulations: [
        mod ("modEnv1", "F_Morph", 0.5),
        mod ("lfo2", "F_Morph", 0.25, "macro1"),
        mod ("velocity", "F_Morph", 0.1),
        mod ("macro2", "F_Morph", 0.4),
        mod ("macro3", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ plucks, mallets, bells
{
    name: "Spring Twang", category: "pluck", tags: ["surf", "analog filter", "convolution", "spring", "tremolo"],
    description: "A twangy surf pluck: a narrow pulse and a saw through the clean-drive filter, pushed a little, "
        + "with a snappy envelope, into a convolved spring reverb. Macro 1 brings in an amp tremolo. Macros: "
        + "tremolo, spring, twang.",
    macros: ["tremolo", "spring", "twang", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.3, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.5, O2_Amp: 0.45,
        Filter: filter.cleanDrive, F_Drive: 0.35, Cutoff: 0.45, Resonance: 0.3, F_Track: 0.6, F_EnvMod: 0.35,
        F_VeloSens: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 260, s: 0.2, r: 200 }), Curve_Filter_Decay: 0.4,
        ...amp ({ a: 0.5, bp: 1, d2: 7000, s: 0, r: 350 }), Curve_Amp_Decay: 0.15,
        LFO_2_Sync: lfoMode.globalFree, LFO_2_Unit: lfoUnit.ms10, LFO_2_Speed: 17,
        ...rack ("Chorus", "Delay", "Convolve", "Reverb", "EQ"),
        Cv_On: 1, Cv_Impulse: impulse ("spring"), Cv_Mix: 0.28, Cv_LowCut: hz (250),
        Voices: 12,
    },
    modulations: [
        mod ("lfo2", "volume", 0.45, "macro1"),
        mod ("velocity", "Cutoff", 0.06),
        mod ("macro2", "Cv_Mix", 0.35),
        mod ("macro3", "F_EnvMod", 0.15),
        mod ("macro3", "F_Drive", 0.4),
    ],
},
{
    name: "Squash Pluck", category: "pluck", tags: ["supersaw", "compressor", "OTT", "delay"],
    description: "A bright supersaw pluck squashed OTT-style by the three-band compressor: downward compression "
        + "tames the attack and upward compression lifts the tail and the top, so each pluck stays dense as it "
        + "dies. A short tempo delay behind it. Macros: squash, brightness, delay.",
    macros: ["squash", "brightness", "delay", ""],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 5, U_Detune: 22, U_DetuneCurve: 0.5, U_RandomPhase: 1, U_Spread: 0.7,
        U_Width: 1.3,
        O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.3, Resonance: 0.2, F_Track: 0.5, F_EnvMod: 0.5, F_VeloSens: 0.4,
        ...fenv ({ a: 0.2, bp: 1, d2: 230, s: 0, r: 200 }), Curve_Filter_Decay: 0.45,
        ...amp ({ a: 0.5, bp: 1, d2: 2400, s: 0, r: 250 }), Curve_Amp_Decay: 0.25,
        ...rack ("Chorus", "Compressor", "Delay", "Reverb", "EQ"),
        Cp_On: 1, Cp_Depth: 0.6, Cp_Attack: compAttack (3), Cp_Release: compRelease (90), Cp_InGain: 4, Cp_Mix: 0.8,
        Cp_LowUpThresh: -40, Cp_MidUpThresh: -40, Cp_HighUpThresh: -40, Cp_MidUpRatio: 3, Cp_HighUpRatio: 3,
        D_On: 1, D_Unit: delayUnit.sixteenth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.3, D_FeedbackR: 0.3, D_Wet: 0.1,
    },
    modulations: [
        mod ("macro1", "Cp_Depth", 0.4),
        mod ("macro2", "Cutoff", 0.2),
        mod ("macro3", "D_Wet", 0.12),
    ],
},
{
    name: "Wide Harp", category: "pluck", tags: ["phase modulation", "per-voice pan", "harp", "plate"],
    description: "A clear harp spread across the stereo field by pitch (frequency pan): low strings left, high "
        + "strings right. Each pluck is a quick burst of phase modulation from osc 2 at the same pitch and a tick of "
        + "tuned noise, over a sine that rings on nearly pure; the mud below 120 Hz is shelved off and a light "
        + "plate sits around it. Macros: brightness, space.",
    macros: ["brightness", "space", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 0, O2_Amp: 0.05,
        N_Resonance: 0.85,
        ...menv1 ({ a: 0.3, bp: 1, d2: 600, s: 0, r: 150 }), Curve_Mod1_Decay: 0.3,
        ...menv2 ({ a: 0.2, bp: 1, d2: 90, s: 0, r: 20 }),
        ...amp ({ a: 0.8, bp: 1, d2: 9000, s: 0, r: 1500 }),
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
        mod ("macro1", "O2_Amp", 0.12),
        mod ("macro2", "Rv_Mix", 0.2),
    ],
},
{
    name: "AM Bells", category: "bells", tags: ["amplitude modulation", "wavefolder", "per-voice drive"],
    description: "Amplitude modulation at a ratio of 3.5 gives inharmonic bell partials. A sine folder on "
        + "each voice is driven by velocity, so hard hits ring metallic while soft ones stay pure. Bells scatter "
        + "around the stereo field. Macros: metal.",
    macros: ["metal", "", "", ""],
    params: {
        OscMix: mix.am, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: ratio (3.5), O2_Amp: 0.8,
        ...amp ({ a: 1, bp: 1, d2: 5000, s: 0, r: 3000 }), Curve_Amp_Decay: 0.6,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -12,
        RandomPan: 0.5, FreqPan: 0.1, Drift_Pitch: 2, Voices: 16,
        R_On: 1, R_Size: 75, R_Length: 3.5, R_Wet: 0.15,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "Sat_Pregain", 0.12),
    ],
},
{
    name: "Just Bells", category: "bells", tags: ["microtuning", "just intonation", "FM"],
    description: "Two-operator FM bells (phase modulation, the way the DX7 does FM): a sine modulator at 3.5 "
        + "times the pitch, its index struck high and falling away, so each bell starts clangorous and rings out "
        + "towards a pure tone. Two unison copies a few cents apart beat like a real bell. Tuned to 5-limit just "
        + "intonation on C (a Scala scale saved with the program), so thirds and fifths are beat-free in the key "
        + "of C. Macros: strike, ring.",
    macros: ["strike", "ring", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: ratio (3.5), O2_Amp: 0.06,
        U_Voices: 2, U_Detune: 4, U_Spread: 0.6,
        ...menv1 ({ a: 0.3, bp: 1, d2: 4000, s: 0, r: 600 }), Curve_Mod1_Decay: 0.3,
        ...amp ({ a: 0.5, bp: 1, d2: 20000, s: 0, r: 3000 }), Curve_Amp_Decay: 0.1,
        RandomPan: 0.4, FreqPan: 0.1, Voices: 16,
        R_On: 1, R_Size: 70, R_Length: 3, R_Wet: 0.15,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.2),
        mod ("velocity", "O2_Amp", 0.08),
        mod ("macro1", "O2_Amp", 0.12),
        mod ("macro2", "R_Wet", 0.1),
    ],
    tuning: { scl: justScale, kbm: "" },
},
{
    name: "Folded Mallets", category: "mallet", tags: ["FM", "wavefolder", "marimba"],
    description: "FM mallets (phase modulation): a sine bar with a modulator at four times its pitch, struck "
        + "for a few tens of milliseconds for the knock of a marimba, and a click of tuned noise. A wavefolder "
        + "after the envelope adds bite to hard hits only, dying away with the note. A small convolved room. "
        + "Macros: hardness, fold.",
    macros: ["hardness", "fold", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 2, O2_Amp: 0,
        N_Resonance: 0.9,
        ...menv1 ({ a: 0.2, bp: 1, d2: 300, s: 0, r: 50 }), Curve_Mod1_Decay: 0.3,
        ...menv2 ({ a: 0.2, bp: 1, d2: 60, s: 0, r: 15 }),
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -20,
        ...amp ({ a: 0.3, bp: 1, d2: 3500, s: 0, r: 450 }),
        FreqPan: 0.15, Voices: 16, VeloSens: 0.8,
        ...rack ("Chorus", "Delay", "Reverb", "EQ", "Convolve"),
        Cv_On: 1, Cv_Impulse: impulse ("room"), Cv_Mix: 0.1,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.6),
        mod ("velocity", "O2_Amp", 0.1),
        mod ("modEnv2", "N_Amp", 0.35),
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("macro1", "O2_Amp", 0.1),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ brass
{
    name: "Brassy Oats", category: "brass", tags: ["brass", "per-voice drive", "ladder", "EQ"],
    description: "Synth brass: a ladder with a slow-attack filter envelope and a soft drive on each voice, "
        + "so loud chords get raspy without turning to mush. Each note's pitch scoops up slightly. The EQ lifts "
        + "the upper mids and the top for the bite of real brass. Macros: rasp, swell, bite.",
    macros: ["rasp", "swell", "bite", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 1.1, O2_Amp: 0.8,
        Filter: filter.ladder, Cutoff: 0.31, Resonance: 0.15, F_EnvMod: 0.42, F_VeloSens: 0.6, F_Track: 0.6,
        ...fenv ({ a: 70, bp: 1, d2: 700, s: 0.55, r: 300 }), Curve_Filter_Attack: -0.3,
        ...amp ({ a: 25, bp: 1, s: 1, r: 260 }),
        PEnv_On: 1, PEnv_Start: -0.6, PEnv_Attack: 60, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -4,
        RandomPan: 0.3, Drift_Pitch: 4,
        C_Mode: 1, C_Mix: 0.3,
        EQ_1_Type: eqType.peak, EQ_1_Freq: 1800, EQ_1_Amp: 3.5, EQ_2_Type: eqType.highShelf, EQ_2_Freq: 4500, EQ_2_Amp: 5,
        Macro_3: 0.5,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "F_EnvMod", 0.2),
        mod ("macro3", "EQ_1_Amp", 0.05),
        mod ("macro3", "EQ_2_Amp", 0.05),
    ],
},

//------------------------------------------------------------------ rhythmic
{
    name: "S&H Panner", category: "sequence", tags: ["per-voice pan", "sample & hold", "tempo sync"],
    description: "A per-note random LFO that takes a new value every 16th note jumps each note around the "
        + "stereo field and moves its cutoff. Every note has its own random pattern, so a chord splits into "
        + "independent lines. A little slew rounds the steps. Macros: jump, filter.",
    macros: ["jump", "filter", "", ""],
    params: {
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.3, O2_Waveform: wave.sawHQ, Transpose: 1, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.33, Resonance: 0.5, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, s: 0.8, r: 250 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Shape: lfoShape.steppingRandom, LFO_1_Unit: lfoUnit.sixteenth, LFO_1_Speed: 1,
        LFO_1_Quantize: 1, LFO_1_Slew: 0.08, LFO_1_Pan: 0.85, LFO_1_Cutoff_1: 0.45,
        LFOPhaseRand: 1,
        D_On: 1, D_Unit: delayUnit.eighth, D_Quantize: 1, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.4, D_FeedbackR: 0.4,
        D_Wet: 0.12,
    },
    modulations: [
        mod ("macro1", "LFO_1_Pan", 0.15),
        mod ("macro2", "LFO_1_Cutoff_1", 0.2),
        mod ("macro2", "Resonance", 0.2),
    ],
},
{
    name: "Gated Grit", category: "sequence", tags: ["per-voice drive", "tempo sync", "gate"],
    description: "A 16th-note square LFO, reset on each note, gates the volume and the drive of every voice "
        + "together, and bounces the sound between left and right. Slew softens the edges. Macros: gate, grit.",
    macros: ["gate", "grit", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: -1, O2_Amp: 0.6, U_Voices: 3, U_Detune: 15,
        U_Spread: 0.5,
        Filter: filter.svf, Cutoff: 0.45, Resonance: 0.2,
        ...amp ({ a: 5, bp: 1, s: 1, r: 300 }),
        LFO_2_Sync: lfoMode.globalReset, LFO_2_Shape: lfoShape.square, LFO_2_Unit: lfoUnit.sixteenth, LFO_2_Speed: 1,
        LFO_2_Quantize: 1, LFO_2_Slew: 0.2,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 8, Sat_Postgain: -6,
        D_On: 1, D_Unit: delayUnit.sixteenth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.4, D_FeedbackR: 0.4, D_Wet: 0.1,
        Macro_1: 0.6,
    },
    modulations: [
        mod ("lfo2", "volume", 0.5, "macro1"),
        mod ("lfo2", "Sat_Pregain", 0.12),
        mod ("lfo2", "pan", 0.3),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ fx and textures
{
    name: "Doppler Flyby", category: "fx", tags: ["per-voice pan", "one-shot LFO", "doppler"],
    description: "Each note flies past: a one-shot ramp sweeps it across the stereo field, in a random "
        + "direction for every note, while a second one-shot LFO with a drawn S-curve holds the pitch high on "
        + "the approach and drops it sharply as the note passes, about a fifth down, brightest at the closest "
        + "point. Hold notes for the full pass. Macros: distance, drop.",
    macros: ["distance", "drop", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 3, O2_Amp: 0.6, N_Amp: 0.15,
        Filter: filter.svf, F_Morph: 0.25, Cutoff: 0.5, Resonance: 0.15,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Shape: lfoShape.saw, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 3.2,
        LFO_1_OneShot: 1, LFOPhaseRand: 0,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Shape: lfoShape.user, LFO_2_Unit: lfoUnit.sec, LFO_2_Speed: 3.2,
        LFO_2_OneShot: 1,
        ...amp ({ a: 1500, bp: 1, d2: 1600, s: 0, r: 600 }), Curve_Amp_Attack: -0.5, Curve_Amp_Decay: -0.5,
        R_On: 1, R_Size: 80, R_Length: 2.5, R_Wet: 0.1,
        Macro_2: 0.6,
    },
    modulations: [
        mod ("lfo1", "pan", 1, "random"),
        mod ("lfo2", "pitch", 0.25, "macro2"),
        mod ("lfo1", "Cutoff", -0.12, "lfo1"),
        mod ("macro1", "Cutoff", -0.25),
        mod ("macro1", "R_Wet", 0.1),
    ],
    // high on the approach, a steep drop as the note passes, low as it goes away (LFO shapes are 0..1)
    tables: { lfoShape2: Float32Array.from ({ length: 512 }, (_, i) => 0.5 - 0.5 * Math.tanh (7 * (i / 511 - 0.5)) / Math.tanh (3.5)) },
},
{
    name: "Glass Spiral", category: "texture", tags: ["frequency shifter", "bode", "feedback", "ambient"],
    description: "Glassy tones fed into the Bode frequency shifter's feedback delay: every echo comes back "
        + "shifted a little higher than the last, so each note spirals up into a shimmering cloud while the dry "
        + "note stays where it is. Notes land at random places in the stereo field. Macros: shift, spiral, mix.",
    macros: ["shift", "spiral", "mix", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: ratio (3), O2_Amp: 0.2, Voices: 12,
        Filter: filter.svf, Cutoff: 0.6, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 4, bp: 1, d2: 1800, s: 0.3, r: 1800 }), Curve_Amp_Decay: 0.3,
        RandomPan: 0.5, Drift_Pitch: 3,
        ...rack ("Chorus", "Bode", "Delay", "Reverb", "EQ", "Algo reverb"),
        Bd_On: 1, Bd_Shift: bodeHz (35), Bd_Mode: 0, Bd_Feedback: 0.55, Bd_Delay: bodeMs (220), Bd_Mix: 0.4,
        Rv_On: 1, Rv_Model: reverbModel.hall, Rv_Size: 0.5, Rv_Decay: reverbSeconds (2.5), Rv_Mix: 0.15,
    },
    modulations: [
        mod ("macro1", "Bd_Shift", 0.25),
        mod ("macro2", "Bd_Feedback", 0.3),
        mod ("macro3", "Bd_Mix", 0.3),
        mod ("velocity", "Cutoff", 0.08),
    ],
},
{
    name: "Tape Memory", category: "keys", tags: ["lo-fi", "drift", "effects order"],
    description: "A worn tape keyboard: heavy drift, a slow random wow on pitch, a soft drive on each voice "
        + "and echoes that run into the chorus (the delay comes first in the effects order). Each note carries "
        + "its own tape hiss and a fast random flutter that roughens the pitch like noise modulating it, and "
        + "rings on for seconds after the key is let go. Macros: wear, echo.",
    macros: ["wear", "echo", "", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.4,
        Filter: filter.lp2, Cutoff: 0.5, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, d2: 2500, s: 0.4, r: 3500 }), Curve_Amp_Decay: 0.3, Curve_Amp_Release: 0.35,
        N_Amp: 0.14,
        Drift_Pitch: 14, Drift_Rate: 0.8, Drift_Cutoff: 3,
        LFO_1_Sync: lfoMode.globalFree, LFO_1_Shape: lfoShape.smoothRandom, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 60,
        LFO_1_Slew: 0.5,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Shape: lfoShape.smoothRandom, LFO_2_Unit: lfoUnit.ms, LFO_2_Speed: 2,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 4,
        FX_Order: 6, C_Mode: 4, C_Mix: 0.5,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.45, D_FeedbackR: 0.45, D_LP: 0.5,
        D_Wet: 0.18,
        EQ_1_Type: 3, EQ_1_Freq: 6000, EQ_1_Amp: -8, EQ_2_Type: 2, EQ_2_Freq: 150, EQ_2_Amp: 2,
    },
    modulations: [
        mod ("lfo1", "finePitch", 0.1),
        mod ("lfo2", "finePitch", 0.03),
        mod ("lfo2", "finePitch", 0.05, "macro1"),
        mod ("macro1", "Drift_Pitch", 0.4),
        mod ("macro1", "Sat_Pregain", 0.1),
        mod ("macro1", "N_Amp", 0.08),
        mod ("macro2", "D_Wet", 0.1),
    ],
},
{
    name: "Rise Machine", category: "fx", tags: ["riser", "envelope curves", "supersaw"],
    description: "Hold a chord for an eight-second riser: a slow mod envelope, curved to accelerate towards "
        + "the top, raises the cutoff, the pitch and the unison detune and brings in noise, then holds there. "
        + "Macros: pitch rise.",
    macros: ["pitch rise", "", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, U_Voices: 7, U_Detune: 30, U_DetuneCurve: 0.5, U_RandomPhase: 1, U_Spread: 0.8,
        U_Width: 1.4, N_Amp: 0.05,
        Filter: filter.svf, Cutoff: 0.22, Resonance: 0.35,
        ...menv1 ({ a: 8000, bp: 1, s: 1, r: 1500 }), Curve_Mod1_Attack: -0.6,
        Macro_1: 1,
        ...amp ({ a: 50, bp: 1, s: 1, r: 1500 }),
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 4, D_Wet: 0.2,
        R_On: 1, R_Size: 90, R_Length: 4, R_Wet: 0.18,
    },
    modulations: [
        mod ("modEnv1", "Cutoff", 0.5),
        mod ("modEnv1", "pitch", 0.5, "macro1"),
        mod ("modEnv1", "U_Detune", 0.1),
        mod ("modEnv1", "N_Amp", 0.2),
    ],
},

//------------------------------------------------------------------ init
{
    name: "Init Porridge", category: "init", tags: ["init"],
    description: "A starting point with Porridge's choices: an HQ saw, an open ladder filter with keytrack, "
        + "and a soft drive on each voice, ready for the macros and the modulation matrix.",
    macros: ["", "", "", ""],
    params: {
        O1_Waveform: wave.sawHQ,
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
    "Felt Piano": 0.546,
    "Crunch Clav": 0.276,
    "Rotary Fold": 0.106,
    "Oat Field": 0.2,
    "Solina Phase": 0.259,
    "Stereo Swarm": 0.184,
    "Warm Wool": 0.218,
    "Vowel Choir": 0.32,
    "Comb String": 0.428,
    "Grit Bloom": 0.126,
    "Velvet Lead": 0.58,
    "Fuzz Lead": 1.06,
    "Feedback Lead": 0.216,
    "MPE Glide Lead": 0.0668,
    "Chew Bass": 0.363,
    "Sub Fold": 0.431,
    "Rubber Bass": 0.183,
    "Reese Drift": 0.4,
    "Acid Oats": 0.297,
    "Talk Bass": 0.934,
    "Spring Twang": 0.295,
    "Squash Pluck": 0.752,
    "Wide Harp": 0.145,
    "AM Bells": 0.118,
    "Just Bells": 0.125,
    "Folded Mallets": 0.0986,
    "Brassy Oats": 0.126,
    "S&H Panner": 0.193,
    "Gated Grit": 0.218,
    "Doppler Flyby": 0.522,
    "Glass Spiral": 0.215,
    "Tape Memory": 0.142,
    "Rise Machine": 0.251,
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

const out = join (root, "presets", "vanilla.porridge");
writeFileSync (out, Preset.writeBank (parsed._0.presets, "Vanilla"));
console.log (`wrote ${parsed._0.presets.length} programs to presets/vanilla.porridge`);
