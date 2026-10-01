// Builds presets/vanilla.porridge, Porridge's own preset bank: 32 programs made for the
// features Oatmeal doesn't have (per-voice distortion and panning driven by the modulation
// matrix, the HQ waveforms, PM/ring/AM, the zero-delay-feedback filters, envelope curves,
// the LFO extras, unison width, drift, the effects order, macros, MPE and microtuning).
//
// Each program lists only what differs from Init. The bank goes through Preset.res, so the
// values are clamped and written exactly as the plugin writes them.
//
// run: npm run res && node tools/vanilla-bank.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../ui/Preset.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");
const author = "Porridge";

//==============================================================================
// helpers

// list values
const wave = { sine: 0, saw: 1, pulse: 2, tri: 3, user: 4, userPwm: 5, sawHQ: 6, pulseHQ: 7, triHQ: 8 };
const mix = { normal: 0, sync: 1, fm: 2, pm: 3, pmFeedback: 4, ring: 5, am: 6 };
const filter = { off: 0, lp2: 2, lp4: 3, hp2: 5, bpWide: 7, bp: 8, nlLp4: 12, svf: 16, ladder: 17, diode: 18,
                 sallenKey: 19, comb: 20, formant: 21 };
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
    name: "Vanilla Keys", category: "keys", tags: ["electric piano", "per-voice drive", "per-voice pan"],
    description: "A phase-modulated electric piano. Every note has its own soft clipper, so hard notes bark "
        + "while chords stay clean, and its own tremolo panner, so held chords shimmer across the stereo field. "
        + "Low notes sit left and high notes right. Macros: tremolo, bark, tine.",
    macros: ["tremolo", "bark", "tine", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 0, O2_Amp: 0.3,
        ...amp ({ a: 1.5, bp: 1, d2: 5000, s: 0, r: 450 }), Curve_Amp_Decay: 0.35,
        ...menv1 ({ a: 0.5, bp: 1, d2: 700, s: 0, r: 200 }),
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 4, Sat_Postgain: -2,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 22, LFO_1_Pan: 0.12, LFOPhaseRand: 1,
        FreqPan: 0.12,
        C_Mode: 1, C_Mix: 0.3, R_On: 1, R_Size: 45, R_Length: 1.8, R_Wet: 0.15,
        Macro_1: 0.3,
    },
    modulations: [
        mod ("velocity", "O2_Amp", 0.12),
        mod ("modEnv1", "O2_Amp", 0.1),
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "LFO_1_Pan", 0.35),
        mod ("macro2", "Sat_Pregain", 0.2),
        mod ("macro3", "O2_Amp", 0.15),
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
        R_On: 1, R_Size: 25, R_Length: 0.8, R_Wet: 0.1,
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
        C_Mode: 1, C_Mix: 0.25, R_On: 1, R_Size: 40, R_Length: 1.4, R_Wet: 0.14,
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
        R_On: 1, R_Size: 80, R_Length: 4.5, R_Wet: 0.3, R_Dullness: 0.6,
    },
    modulations: [
        mod ("lfo2", "Cutoff", 0.05),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "U_Width", 0.25),
        mod ("macro3", "Drift_Pitch", 0.3),
    ],
},
{
    name: "Stereo Swarm", category: "pad", tags: ["per-voice pan", "motion", "ambient"],
    description: "Every note circles the stereo field on its own: a per-note LFO pans it from a random starting "
        + "phase, higher notes orbit faster, and each note gets a slightly different speed. A second, random LFO "
        + "per note nudges its cutoff and position. Macros: orbit, orbit speed, brightness.",
    macros: ["orbit", "orbit speed", "brightness", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.7, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.4, Resonance: 0.2, F_Track: 0.4,
        ...amp ({ a: 1200, bp: 1, s: 1, r: 3200 }), Curve_Amp_Attack: -0.4, Curve_Amp_Release: 0.4,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 3, LFO_1_Pan: 0.42,
        LFO_2_Sync: lfoMode.perNote, LFO_2_Shape: lfoShape.smoothRandom, LFO_2_Unit: lfoUnit.sec, LFO_2_Speed: 2,
        LFO_2_Cutoff_1: 0.12, LFO_2_Pan: 0.12, LFOPhaseRand: 1,
        R_On: 1, R_Size: 90, R_Length: 5, R_Wet: 0.35, D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 4,
        D_FeedbackL: 0.45, D_FeedbackR: 0.45, D_Wet: 0.12,
    },
    modulations: [
        mod ("key", "LFO_1_Speed", -0.06),
        mod ("random", "LFO_1_Speed", 0.025),
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
        C_Mode: 1, C_Mix: 0.4, R_On: 1, R_Size: 60, R_Length: 2.5, R_Wet: 0.22,
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
        C_Mode: 1, C_Mix: 0.35, R_On: 1, R_Size: 90, R_Length: 3.5, R_Wet: 0.35,
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
        + "that changes character with the comb's feedback polarity (macro 2). Reverb comes before the delay. "
        + "Macros: resonance, polarity.",
    macros: ["resonance", "polarity", "", ""],
    params: {
        O1_Amp: 0.12, O1_Waveform: wave.sawHQ, N_Amp: 0.5,
        Filter: filter.comb, Cutoff: 0.276, F_Track: 1, Resonance: 0.9, F_Morph: 0,
        ...amp ({ a: 250, bp: 1, s: 1, r: 1800 }), Curve_Amp_Attack: -0.2,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 4, LFO_1_Pan: 0.15, LFOPhaseRand: 1,
        RandomPan: 0.5,
        FX_Order: 2, R_On: 1, R_Size: 80, R_Length: 3.5, R_Wet: 0.3,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_Wet: 0.15,
    },
    modulations: [
        mod ("macro1", "Resonance", 0.09),
        mod ("macro2", "F_Morph", 1),
    ],
},
{
    name: "Grit Bloom", category: "pad", tags: ["per-voice drive", "per-voice pan", "evolving"],
    description: "A clean pad that grows grit: a slow mod envelope raises each note's distortion drive and "
        + "cutoff, and moves the note out from the centre, each one to its own random side. Macros: grit, bloom.",
    macros: ["grit", "bloom", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: semis (7), O2_Amp: 0.4,
        Filter: filter.svf, Cutoff: 0.33, Resonance: 0.2, F_Track: 0.4,
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: -6,
        ...menv1 ({ a: 3000, bp: 1, s: 1, r: 2000 }), Curve_Mod1_Attack: -0.3,
        ...amp ({ a: 800, bp: 1, s: 1, r: 2200 }),
        R_On: 1, R_Size: 70, R_Length: 3, R_Wet: 0.28,
        Macro_2: 1,
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.22, "macro2"),
        mod ("modEnv1", "Sat_Postgain", -0.05, "macro2"),
        mod ("modEnv1", "Cutoff", 0.15, "macro2"),
        mod ("modEnv1", "pan", 0.8, "random"),
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ leads
{
    name: "Velvet Lead", category: "lead", tags: ["mono", "ladder", "vibrato"],
    description: "A legato ladder lead with glide. The vibrato waits, then fades in (LFO delay and fade-in), "
        + "and the mod wheel adds more. Macros: drive, cutoff.",
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
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.4, D_FeedbackR: 0.4, D_Wet: 0.2,
        R_On: 1, R_Wet: 0.15,
    },
    modulations: [
        mod ("modWheel", "LFO_1_Pitch", 0.15),
        mod ("macro1", "Sat_Pregain", 0.2),
        mod ("macro2", "Cutoff", 0.3),
    ],
},
{
    name: "Fuzz Lead", category: "lead", tags: ["mono", "fuzz", "diode ladder"],
    description: "Hard clipping (4x oversampled) into a diode ladder: a fuzz-box lead. The mod wheel pushes "
        + "the fuzz. Macros: fuzz, cutoff.",
    macros: ["fuzz", "cutoff", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 30, GlideMode: 0,
        O1_Waveform: wave.pulseHQ, O1_PWM_W: 0.5, O2_Waveform: wave.sawHQ, Transpose: -1, O2_Amp: 0.5,
        Sat_Type: dist.hard, Sat_Mode: distMode.voicePre, Sat_Oversample: 2, Sat_Pregain: 22, Sat_Postgain: -4,
        Filter: filter.diode, Cutoff: 0.48, Resonance: 0.3, F_EnvMod: 0.18, F_Track: 0.5,
        ...fenv ({ a: 2, bp: 1, d2: 400, s: 0.3, r: 200 }),
        ...amp ({ a: 3, bp: 1, s: 1, r: 180 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 17, LFO_1_Pitch: 0.38,
        LFO_1_Delay: 500, LFO_1_Fade: 500,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 2, D_Wet: 0.18, R_On: 1, R_Wet: 0.12,
    },
    modulations: [
        mod ("modWheel", "Sat_Pregain", 0.15),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "Cutoff", 0.3),
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
        D_On: 1, D_Unit: delayUnit.quarter, D_LengthL: 1, D_LengthR: 1, D_Rotation: 1.2, D_Wet: 0.15,
        R_On: 1, R_Wet: 0.15,
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
        R_On: 1, R_Size: 50, R_Wet: 0.18,
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
    description: "A diode-ladder bass with an asymmetric drive on the voice. Velocity adds drive, and low "
        + "notes are driven harder than high ones, so the bass line grows teeth as it goes down. Macros: chew, drive.",
    macros: ["chew", "drive", "", ""],
    params: {
        PolyMode: poly.legato, Glide: 25, GlideMode: 0,
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, Transpose: -1, O2_Amp: 0.6,
        Filter: filter.diode, Cutoff: 0.25, Resonance: 0.45, F_EnvMod: 0.4, F_VeloSens: 0.5, F_Track: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 350, s: 0.15, r: 120 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 1, bp: 1, s: 0.8, r: 60 }),
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 8, Sat_Postgain: -6,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("key", "Sat_Pregain", -0.2),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Sub Fold", category: "bass", tags: ["wavefolder", "per-voice drive", "sub"],
    description: "A sine sub through a wavefolder (sine distortion) in front of a ladder. A short mod "
        + "envelope and velocity fold each note's attack into harmonics, then it settles back to a round sub. "
        + "Macros: fold.",
    macros: ["fold", "", "", ""],
    params: {
        PolyMode: poly.mono,
        O1_Waveform: wave.sine, O2_Waveform: wave.triHQ, Transpose: 0, O2_Amp: 0.3,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePre, Sat_Pregain: -14,
        Filter: filter.ladder, Cutoff: 0.45, Resonance: 0.1, F_Track: 1,
        ...menv1 ({ a: 0.5, bp: 1, d2: 350, s: 0.1, r: 100 }),
        ...amp ({ a: 1, bp: 1, s: 1, r: 80 }),
    },
    modulations: [
        mod ("modEnv1", "Sat_Pregain", 0.15),
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Rubber Bass", category: "bass", tags: ["phase modulation", "pitch envelope"],
    description: "A clean phase-modulation bass: osc 2 an octave up modulates osc 1, with a short envelope on "
        + "the modulation depth and a quick pitch drop for the thump. Macros: bounce.",
    macros: ["bounce", "", "", ""],
    params: {
        PolyMode: poly.mono,
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
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 0.9, O2_Amp: 1,
        U_Voices: 3, U_Detune: 18, U_Spread: 0.5, U_Width: 1.2,
        Drift_Pitch: 8, Drift_Rate: 0.6,
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
    description: "A 303-style line: diode ladder, high resonance, filter envelope and glide. Velocity works "
        + "as accent, opening the envelope and adding grit to the drive. Macros: cutoff, resonance, env mod, drive.",
    macros: ["cutoff", "resonance", "env mod", "drive"],
    params: {
        PolyMode: poly.legato, Glide: 45, GlideMode: 0,
        O1_Waveform: wave.sawHQ,
        Filter: filter.diode, Cutoff: 0.2, Resonance: 0.75, F_EnvMod: 0.45, F_VeloSens: 0.6, F_Track: 0.3,
        ...fenv ({ a: 0.2, bp: 1, d2: 220, s: 0, r: 80 }), Curve_Filter_Decay: 0.3,
        ...amp ({ a: 1, bp: 1, d2: 1200, s: 0.6, r: 50 }),
        Sat_Type: dist.asym, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -4,
        D_On: 1, D_Unit: delayUnit.sixteenth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.4, D_FeedbackR: 0.4, D_Wet: 0.15,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.15),
        mod ("macro1", "Cutoff", 0.3),
        mod ("macro2", "Resonance", 0.25),
        mod ("macro3", "F_EnvMod", 0.25),
        mod ("macro4", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ plucks, mallets, bells
{
    name: "Scatter Pluck", category: "pluck", tags: ["per-voice pan", "pluck", "delay"],
    description: "Every note lands at its own random place in the stereo field, and the harder you play the "
        + "wider they scatter (random to pan, scaled by velocity). Soft notes stay in the middle. Macros: scatter "
        + "(every note, whatever its velocity), decay.",
    macros: ["scatter", "decay", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.pulseHQ, Transpose: 1, O2_Amp: 0.3,
        Filter: filter.ladder, Cutoff: 0.25, Resonance: 0.25, F_EnvMod: 0.45, F_Track: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 320, s: 0, r: 200 }), Curve_Filter_Decay: 0.4,
        ...amp ({ a: 0.5, bp: 1, d2: 1300, s: 0, r: 450 }), Curve_Amp_Decay: 0.5,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 2,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 4, D_FeedbackL: 0.5, D_FeedbackR: 0.5, D_Wet: 0.25,
        R_On: 1, R_Wet: 0.18,
    },
    modulations: [
        mod ("random", "pan", 1, "velocity"),
        mod ("velocity", "Sat_Pregain", 0.1),
        mod ("random", "pan", 0.5, "macro1"),
        mod ("macro2", "F_EnvMod", 0.15),
    ],
},
{
    name: "Wide Harp", category: "pluck", tags: ["phase modulation", "per-voice pan", "harp"],
    description: "A harp spread across the stereo field by pitch (frequency pan): low strings left, high "
        + "strings right. A short PM envelope gives the pluck. Macros: brightness.",
    macros: ["brightness", "", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.25,
        ...menv1 ({ a: 0.5, bp: 1, d2: 400, s: 0, r: 200 }),
        ...amp ({ a: 1, bp: 1, d2: 3200, s: 0, r: 1600 }), Curve_Amp_Decay: 0.4,
        FreqPan: 0.22, Voices: 16,
        R_On: 1, R_Size: 60, R_Length: 2.5, R_Wet: 0.3,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.12),
        mod ("velocity", "O2_Amp", 0.08),
        mod ("macro1", "O2_Amp", 0.15),
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
        R_On: 1, R_Size: 90, R_Length: 4, R_Wet: 0.35,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "Sat_Pregain", 0.12),
    ],
},
{
    name: "Just Bells", category: "bells", tags: ["microtuning", "just intonation", "phase modulation"],
    description: "Phase-modulated bells tuned to 5-limit just intonation on C (a Scala scale saved with the "
        + "program), so thirds and fifths beat-free in the key of C. Macros: strike.",
    macros: ["strike", "", "", ""],
    params: {
        OscMix: mix.pm, O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: ratio (3.5), O2_Amp: 0.35,
        ...menv1 ({ a: 0.5, bp: 1, d2: 1500, s: 0, r: 500 }),
        ...amp ({ a: 1, bp: 1, d2: 6000, s: 0, r: 2500 }), Curve_Amp_Decay: 0.5,
        RandomPan: 0.4, FreqPan: 0.1, Voices: 16,
        R_On: 1, R_Size: 80, R_Length: 3.5, R_Wet: 0.3,
    },
    modulations: [
        mod ("modEnv1", "O2_Amp", 0.12),
        mod ("velocity", "O2_Amp", 0.08),
        mod ("macro1", "O2_Amp", 0.15),
    ],
    tuning: { scl: justScale, kbm: "" },
},
{
    name: "Folded Mallets", category: "mallet", tags: ["wavefolder", "per-voice drive", "marimba"],
    description: "Sine mallets through a wavefolder on every voice. The folder sits after the amp envelope, "
        + "so velocity sets how bright each hit is and the brightness dies away with the note. Macros: fold.",
    macros: ["fold", "", "", ""],
    params: {
        O1_Waveform: wave.sine, O2_Waveform: wave.sine, Transpose: 2, O2_Amp: 0.12,
        Sat_Type: dist.sine, Sat_Mode: distMode.voicePost, Sat_Pregain: -16,
        ...amp ({ a: 0.5, bp: 1, d2: 1800, s: 0, r: 500 }), Curve_Amp_Decay: 0.4,
        FreqPan: 0.15, Voices: 16,
        R_On: 1, R_Size: 40, R_Length: 1.5, R_Wet: 0.18,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.18),
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Ringing Steel", category: "pluck", tags: ["ring modulation", "per-voice drive", "metallic"],
    description: "Ring modulation by a sine a major sixth up, then a plucked ladder filter and a hard "
        + "clipper on each voice. Metallic, a bit like a steel drum through an amp. Macros: ring, drive.",
    macros: ["ring", "drive", "", ""],
    params: {
        OscMix: mix.ring, O1_Waveform: wave.sawHQ, O2_Waveform: wave.sine, Transpose: ratio (5 / 3), O2_Amp: 0.7,
        Filter: filter.ladder, Cutoff: 0.3, Resonance: 0.3, F_EnvMod: 0.4, F_Track: 0.5,
        ...fenv ({ a: 0.2, bp: 1, d2: 500, s: 0, r: 300 }),
        ...amp ({ a: 0.5, bp: 1, d2: 2200, s: 0, r: 600 }), Curve_Amp_Decay: 0.4,
        Sat_Type: dist.hard, Sat_Mode: distMode.voicePost, Sat_Oversample: 1, Sat_Pregain: 4, Sat_Postgain: -3,
        RandomPan: 0.3,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 2, D_Wet: 0.15, R_On: 1, R_Wet: 0.15,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "O2_Amp", -0.1),
        mod ("macro2", "Sat_Pregain", 0.15),
    ],
},

//------------------------------------------------------------------ brass
{
    name: "Brassy Oats", category: "brass", tags: ["brass", "per-voice drive", "ladder"],
    description: "Synth brass: a ladder with a slow-attack filter envelope and a soft drive on each voice, "
        + "so loud chords get raspy without turning to mush. Each note's pitch scoops up slightly. Macros: "
        + "rasp, swell.",
    macros: ["rasp", "swell", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 1.1, O2_Amp: 0.8,
        Filter: filter.ladder, Cutoff: 0.28, Resonance: 0.15, F_EnvMod: 0.35, F_VeloSens: 0.6, F_Track: 0.6,
        ...fenv ({ a: 70, bp: 1, d2: 700, s: 0.55, r: 300 }), Curve_Filter_Attack: -0.3,
        ...amp ({ a: 25, bp: 1, s: 1, r: 260 }),
        PEnv_On: 1, PEnv_Start: -0.6, PEnv_Attack: 60, PEnv_Peak: 0, PEnv_Decay: 10, PEnv_Sustain: 0,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 6, Sat_Postgain: -4,
        RandomPan: 0.3, Drift_Pitch: 4,
        C_Mode: 1, C_Mix: 0.3, R_On: 1, R_Size: 50, R_Wet: 0.18,
    },
    modulations: [
        mod ("velocity", "Sat_Pregain", 0.12),
        mod ("macro1", "Sat_Pregain", 0.15),
        mod ("macro2", "F_EnvMod", 0.2),
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
        Filter: filter.ladder, Cutoff: 0.33, Resonance: 0.4, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, s: 0.8, r: 250 }),
        LFO_1_Sync: lfoMode.perNote, LFO_1_Shape: lfoShape.steppingRandom, LFO_1_Unit: lfoUnit.sixteenth, LFO_1_Speed: 1,
        LFO_1_Quantize: 1, LFO_1_Slew: 0.12, LFO_1_Pan: 0.45, LFO_1_Cutoff_1: 0.2,
        LFOPhaseRand: 1,
        D_On: 1, D_Unit: delayUnit.eighth, D_Quantize: 1, D_LengthL: 3, D_LengthR: 3, D_Wet: 0.15, R_On: 1, R_Wet: 0.12,
    },
    modulations: [
        mod ("macro1", "LFO_1_Pan", 0.3),
        mod ("macro2", "LFO_1_Cutoff_1", 0.2),
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
        D_On: 1, D_Unit: delayUnit.sixteenth, D_LengthL: 3, D_LengthR: 3, D_Wet: 0.12, R_On: 1, R_Wet: 0.12,
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
        + "direction for every note, and its pitch drops as it passes. Hold notes for the full pass. Macros: "
        + "distance.",
    macros: ["distance", "", "", ""],
    params: {
        O1_Waveform: wave.sawHQ, O2_Waveform: wave.sawHQ, Transpose: 0, Detune: 3, O2_Amp: 0.6, N_Amp: 0.15,
        Filter: filter.svf, F_Morph: 0.25, Cutoff: 0.5, Resonance: 0.15,
        LFO_1_Sync: lfoMode.perNote, LFO_1_Shape: lfoShape.saw, LFO_1_Unit: lfoUnit.sec, LFO_1_Speed: 3.2,
        LFO_1_OneShot: 1, LFOPhaseRand: 0,
        ...amp ({ a: 1500, bp: 1, d2: 1600, s: 0, r: 600 }), Curve_Amp_Attack: -0.5, Curve_Amp_Decay: -0.5,
        R_On: 1, R_Size: 90, R_Length: 3, R_Wet: 0.12,
    },
    modulations: [
        mod ("lfo1", "pan", 1, "random"),
        mod ("lfo1", "finePitch", -0.6),
        mod ("macro1", "Cutoff", -0.25),
        mod ("macro1", "R_Wet", 0.1),
    ],
},
{
    name: "Rain on Oats", category: "texture", tags: ["noise", "per-voice pan", "per-voice drive"],
    description: "Resonant noise drops: every note is a short ping of filtered noise at a random place in the "
        + "stereo field, some of them crackling (random to drive). Play fast clusters. Macros: crackle.",
    macros: ["crackle", "", "", ""],
    params: {
        O1_Amp: 0, N_Amp: 1, N_Resonance: 0.95, RandomPan: 1, RandomFreq: 150, Voices: 16,
        ...amp ({ a: 0.5, bp: 1, d2: 260, s: 0, r: 200 }), Curve_Amp_Decay: 0.4,
        Sat_Type: dist.hard, Sat_Mode: distMode.voicePost, Sat_Pregain: 0,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 5, D_Wet: 0.2, R_On: 1, R_Size: 80, R_Length: 3,
        R_Wet: 0.35,
    },
    modulations: [
        mod ("random", "Sat_Pregain", 0.15),
        mod ("macro1", "Sat_Pregain", 0.15),
    ],
},
{
    name: "Tape Memory", category: "keys", tags: ["lo-fi", "drift", "effects order"],
    description: "A worn tape keyboard: heavy drift, a slow random wow on pitch, a soft drive on each voice "
        + "and echoes that run into the chorus (the delay comes first in the effects order). Macros: wear, echo.",
    macros: ["wear", "echo", "", ""],
    params: {
        O1_Waveform: wave.triHQ, O2_Waveform: wave.sine, Transpose: 1, O2_Amp: 0.4,
        Filter: filter.lp2, Cutoff: 0.45, Resonance: 0.1, F_Track: 0.5,
        ...amp ({ a: 2, bp: 1, d2: 2500, s: 0.4, r: 600 }), Curve_Amp_Decay: 0.3,
        Drift_Pitch: 14, Drift_Rate: 0.8, Drift_Cutoff: 3,
        LFO_1_Sync: lfoMode.globalFree, LFO_1_Shape: lfoShape.smoothRandom, LFO_1_Unit: lfoUnit.ms10, LFO_1_Speed: 60,
        LFO_1_Slew: 0.5,
        Sat_Type: dist.soft, Sat_Mode: distMode.voicePost, Sat_Pregain: 4,
        FX_Order: 6, C_Mode: 4, C_Mix: 0.5,
        D_On: 1, D_Unit: delayUnit.eighth, D_LengthL: 3, D_LengthR: 3, D_FeedbackL: 0.45, D_FeedbackR: 0.45, D_LP: 0.5,
        D_Wet: 0.2, R_On: 1, R_Wet: 0.15,
        EQ_1_Type: 3, EQ_1_Freq: 6000, EQ_1_Amp: -8, EQ_2_Type: 2, EQ_2_Freq: 150, EQ_2_Amp: 2,
    },
    modulations: [
        mod ("lfo1", "finePitch", 0.1),
        mod ("macro1", "Drift_Pitch", 0.4),
        mod ("macro1", "Sat_Pregain", 0.1),
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
        R_On: 1, R_Size: 120, R_Length: 5, R_Wet: 0.35,
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
// Output gains, measured by rendering each program through the test host: a four-note chord
// (a single note for the mono programs) sits near -18 dB RMS, and a held five-note chord at
// full velocity peaks below -1 dBFS. Re-measure them after changing a program's sound.
const gains = {
    "Vanilla Keys": 0.214,
    "Crunch Clav": 0.354,
    "Rotary Fold": 0.123,
    "Oat Field": 0.194,
    "Stereo Swarm": 0.219,
    "Warm Wool": 0.298,
    "Vowel Choir": 0.476,
    "Comb String": 0.662,
    "Grit Bloom": 0.26,
    "Velvet Lead": 0.356,
    "Fuzz Lead": 0.463,
    "Feedback Lead": 0.186,
    "MPE Glide Lead": 0.0601,
    "Chew Bass": 0.264,
    "Sub Fold": 0.323,
    "Rubber Bass": 0.169,
    "Reese Drift": 0.324,
    "Acid Oats": 0.345,
    "Scatter Pluck": 0.242,
    "Wide Harp": 0.229,
    "AM Bells": 0.165,
    "Just Bells": 0.18,
    "Folded Mallets": 0.174,
    "Ringing Steel": 0.277,
    "Brassy Oats": 0.163,
    "S&H Panner": 0.217,
    "Gated Grit": 0.233,
    "Doppler Flyby": 0.592,
    "Rain on Oats": 0.179,
    "Tape Memory": 0.181,
    "Rise Machine": 0.178,
    "Init Porridge": 0.313,
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
