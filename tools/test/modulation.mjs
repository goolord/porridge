// The modulation matrix's later features: a connection's hold (latched at note-on), slew and
// curve, the later sources (LFO 3, interval, alternate, cycle, voice level, wander, glide, held
// notes), the later slots (17..32), and which note a per-note source follows on the whole sound
// (MM_Follow). Renders a plain sine voice through the test host and measures its level.
//
//   node tools/test/modulation.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/modulation/.

import { writeFileSync } from "node:fs";
import { join } from "node:path";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as Preset from "../../ui/Preset.res.mjs";
import { root, outDir, render, checker } from "./lib.mjs";

const dir = outDir ("modulation");
const init = join (root, "tools", "re", "init_prog.bin");
const rate = 44100;
const { check, done } = checker ({ verbose: true });

const src = key => ModMatrix.sourceIndex (key);
const tgt = key => ModMatrix.targetIndex (key);

// a sine voice, nothing else; a held amp envelope
const plain = { O1_Waveform: 0, O2_Amp: 0, N_Amp: 0, Filter: 0, Voices: 16, PolyMode: 1, Attack: 0, Sustain: 1, Release: 0.01,
                VeloSens: 0, RandomAmp: 0, RandomPan: 0, RandomFreq: 0, FX_Rack_1: 0, FX_Rack_2: 0, FX_Rack_3: 0, FX_Rack_4: 0 };

// connection k's parameters
const conn = (k, source, target, amount, more = {}) => ({
    [ModMatrix.sourceId (k)]: src (source), [ModMatrix.targetId (k)]: tgt (target), [ModMatrix.amountId (k)]: amount,
    ...Object.fromEntries (Object.entries (more).map (([key, v]) => [`Mod${k}_${key}`, v])),
});

let count = 0;
function play (notes, sets, seconds)
{
    const events = join (dir, `events${count}.txt`);
    writeFileSync (events, notes.map (([at, key, length, vel = 100]) =>
        `${Math.round (at * rate)} 144 ${key} ${vel}\n${Math.round ((at + length) * rate)} 128 ${key} 0\n`).join (""));
    return render ({ program: init, events, frames: Math.round (seconds * rate), rate, sets: { ...plain, ...sets },
                     out: join (dir, `render${count++}.f32`) });
}

// RMS from a to b seconds (both channels)
const rms = ([l, r], a, b) =>
{
    let s = 0;
    const i0 = Math.round (a * rate), i1 = Math.round (b * rate);
    for (let i = i0; i < i1; ++i) s += l[i] * l[i] + r[i] * r[i];
    return Math.sqrt (s / (2 * (i1 - i0)));
};
// the RMS of each 20 ms from a to b
const levels = (x, a, b) => Array.from ({ length: Math.floor ((b - a) / 0.02) }, (_, k) => rms (x, a + 0.02 * k, a + 0.02 * (k + 1)));
const spread = xs => Math.max (...xs) / Math.min (...xs);
const near = (a, b, tol) => Math.abs (a / b - 1) < tol;
const f = x => x.toFixed (3);

// LFO 3 at 2 Hz (its knob holds the position: 0.02 * 2500^v)
const hz = x => Math.log (x / 0.02) / Math.log (2500);
const lfo3 = { LFO_3_Mode: 2, LFO_3_Rate: hz (2) };

// hold: a shared LFO 3 moving the volume swings it; latched at note-on, each note keeps one level
{
    const free = levels (play ([[0, 69, 1.5]], { ...lfo3, ...conn (32, "lfo3", "volume", 0.5) }, 1.5), 0.05, 1.4);
    const held = levels (play ([[0.13, 69, 1.3]], { ...lfo3, ...conn (32, "lfo3", "volume", 0.5, { Hold: 1 }) }, 1.5), 0.2, 1.4);
    check (spread (free) > 2, `LFO 3 (slot 32) on the volume swings it  ${f (spread (free))}x`);
    check (spread (held) < 1.03, `... latched at note-on, it holds  ${f (spread (held))}x`);
}

// slew: a square LFO 3 at 1 Hz flips the volume at 0.5 s; slewed over 500 ms, it is still on its way
{
    const sq = { LFO_3_Mode: 2, LFO_3_Rate: hz (1), LFO_3_Shape: 4 };
    const hard = play ([[0, 69, 1]], { ...sq, ...conn (1, "lfo3", "volume", 0.5) }, 1);
    const slewed = play ([[0, 69, 1]], { ...sq, ...conn (1, "lfo3", "volume", 0.5, { Slew: 0.5 }) }, 1);
    const before = rms (hard, 0.3, 0.45), after = rms (hard, 0.7, 0.9), justAfter = rms (hard, 0.52, 0.54);
    const slewedJust = rms (slewed, 0.52, 0.54), slewedAfter = rms (slewed, 0.95, 0.99);
    check (near (justAfter, after, 0.05), `square LFO 3 flips the volume at once  ${f (before)} > ${f (justAfter)} (${f (after)})`);
    check (slewedJust > justAfter * 1.8 && slewedAfter < slewedJust * 0.8,
           `... slewed over 500 ms, it eases down  ${f (slewedJust)} 20 ms after, ${f (slewedAfter)} at the end`);
}

// curve: macro 1 at 0.5 cuts the volume by 0.5, bent to 0.84 (curve 1) or 0.0625 (curve -1)
{
    const at = curve => rms (play ([[0, 69, 0.5]], { Macro_1: 0.5, ...conn (1, "macro1", "volume", -1, { Curve: curve }) }, 0.5), 0.1, 0.4);
    const none = rms (play ([[0, 69, 0.5]], {}, 0.5), 0.1, 0.4);
    const straight = at (0), up = at (1), down = at (-1);
    check (near (straight / none, 0.5, 0.02), `curve straight  ${f (straight / none)} (0.5)`);
    check (near (up / none, 1 - 0.5 ** 0.25, 0.03), `curve +100 %  ${f (up / none)} (${f (1 - 0.5 ** 0.25)})`);
    check (near (down / none, 1 - 0.5 ** 4, 0.02), `curve -100 %  ${f (down / none)} (${f (1 - 0.5 ** 4)})`);
}

// interval: an octave up after the first note is 0.5 (two octaves are 1)
{
    const x = play ([[0, 60, 0.4], [0.5, 72, 0.4], [1, 48, 0.4]], conn (1, "interval", "volume", 0.5), 1.5);
    const a = rms (x, 0.1, 0.35), b = rms (x, 0.6, 0.85), c = rms (x, 1.1, 1.35);
    check (near (b / a, 1.25, 0.02) && near (c / a, 0.5, 0.03), `interval: up an octave ${f (b / a)} (1.25), down two ${f (c / a)} (0.5)`);
}

// alternate and cycle, note by note
{
    const notes = [0, 0.3, 0.6, 0.9, 1.2].map (t => [t, 69, 0.25]);
    const alt = play (notes, conn (1, "alternate", "volume", 0.5), 1.5);
    const a = notes.map (([t]) => rms (alt, t + 0.05, t + 0.2));
    check (near (a[1] / a[0], 1 / 3, 0.02) && near (a[2] / a[0], 1, 0.02), `alternate  ${a.map (v => f (v / a[0])).join (" ")}`);
    const cyc = play (notes, conn (1, "cycle", "volume", 0.5), 1.5);
    const c = notes.map (([t]) => rms (cyc, t + 0.05, t + 0.2));
    const want = [1, 7 / 6, 4 / 3, 1.5, 1];
    check (c.every ((v, i) => near (v / c[0], want[i], 0.02)), `cycle  ${c.map (v => f (v / c[0])).join (" ")}`);
}

// voice level: a sounding note's level pans it right
{
    const [l, r] = play ([[0, 69, 0.5]], conn (1, "voiceLevel", "pan", 1), 0.5);
    const L = rms ([l, l], 0.2, 0.4), R = rms ([r, r], 0.2, 0.4);
    check (R > 2 * L, `voice level pans a sounding note right  L ${f (L)}, R ${f (R)}`);
}

// wander: each note drifts on its own
{
    const x = play ([[0, 69, 1]], { Wander_Rate: 1, ...conn (1, "wander", "volume", 0.5) }, 1);
    const s = spread (levels (x, 0.1, 0.9));
    check (s > 1.3, `wander moves the volume  ${f (s)}x`);
}

// glide: the second note of a mono glide starts loud and settles
{
    const x = play ([[0, 57, 0.6], [0.5, 69, 0.8]], { PolyMode: 0, Glide: 300, ...conn (1, "glide", "volume", 0.5) }, 1.4);
    const start = rms (x, 0.51, 0.56), end = rms (x, 1, 1.2), before = rms (x, 0.2, 0.4);
    check (start > end * 1.25 && near (end, before, 0.03), `glide: ${f (start)} as it starts, ${f (end)} once there (${f (before)} before)`);
}

// held notes: eight notes cut each by half, one note not at all
{
    const keys = [48, 52, 55, 59, 62, 65, 69, 72];
    const one = rms (play ([[0, 69, 0.5]], conn (1, "heldNotes", "volume", -0.5), 0.5), 0.1, 0.4);
    const free = rms (play (keys.map (k => [0, k, 0.5]), {}, 0.5), 0.1, 0.4);
    const eight = rms (play (keys.map (k => [0, k, 0.5]), conn (1, "heldNotes", "volume", -0.5), 0.5), 0.1, 0.4);
    const alone = rms (play ([[0, 69, 0.5]], {}, 0.5), 0.1, 0.4);
    check (near (one, alone, 0.01) && near (eight / free, 0.5, 0.03), `held notes: one ${f (one / alone)} (1), eight ${f (eight / free)} (0.5)`);
}

// follow: velocity on the utility's gain (the whole sound); a soft note after a loud one moves it
// all the way with the newest note, less when every note counts by its level
{
    const utility = PorridgeParams.rackEntries.findIndex (e => e && e[0] === "utility" && e[1] === 1);
    const sets = { FX_Rack_1: utility, Ut_On: 1, ...conn (1, "velocity", "Ut_Gain", -0.3) };
    const notes = [[0, 57, 1, 127], [0.3, 64, 0.7, 20]];
    const newest = rms (play (notes, { ...sets, MM_Follow: 0 }, 1), 0.5, 0.9);
    const byLevel = rms (play (notes, { ...sets, MM_Follow: 1 }, 1), 0.5, 0.9);
    const first = rms (play (notes, { ...sets, MM_Follow: 0 }, 1), 0.1, 0.25);
    check (newest > first * 1.5 && byLevel < newest * 0.8, `follow: loud note alone ${f (first)}, then with a soft one: newest ${f (newest)}, by level ${f (byLevel)}`);
}

// a preset keeps a connection's options, in a later slot too
{
    const p = Preset.make ("options");
    const set = (id, x) => p.values.set (id, x);
    for (const [k, source, target] of [[1, "lfo3", "Cutoff"], [20, "interval", "volume"]])
    {
        set (ModMatrix.sourceId (k), src (source));
        set (ModMatrix.targetId (k), tgt (target));
        set (ModMatrix.amountId (k), 0.5);
    }
    set (ModMatrix.holdId (1), 1);
    set (ModMatrix.slewId (1), 0.25);
    set (ModMatrix.curveId (20), -0.5);
    set ("MM_Follow", 1);
    const back = Preset.parseJson (JSON.stringify (Preset.toJson (p)))._0.presets[0];
    const same = id => Math.fround (back.values.get (id)) === Math.fround (p.values.get (id));
    // (the second connection fills slot 2)
    check (same (ModMatrix.holdId (1)) && same (ModMatrix.slewId (1)) && back.values.get (ModMatrix.curveId (2)) === -0.5 &&
           back.values.get (ModMatrix.sourceId (2)) === src ("interval") && same ("MM_Follow"),
           "a preset keeps hold, slew, curve and the follow setting");
}

done ("modulation ok");
