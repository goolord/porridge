// The voices' extras: the sources chord position, gap, legato and pitch; a connection's steps;
// the lane phaser's and flanger's random start and rate tracking, the flanger's delay tracking,
// the lo-fi sampler's note tracking, and the octaver. Renders through the test host.
//
//   node tools/test/extras.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/extras/.

import { join } from "node:path";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";
import * as Preset from "../../ui/Preset.res.mjs";
import { rackEntries, expPos } from "../../ui/PorridgeParams.res.mjs";
import { root, outDir, player, rms as rmsOf, levelAt, checker, fft } from "./lib.mjs";

const dir = outDir ("extras");
const init = join (root, "tools", "re", "init_prog.bin");
const rate = 44100;
const { check, done } = checker ({ verbose: true });

const src = key => ModMatrix.sourceIndex (key);
const tgt = key => ModMatrix.targetIndex (key);
const entry = (key, copy = 1) => rackEntries.findIndex (e => e && e[0] === key && e[1] === copy);

// a sine voice, nothing else; a held amp envelope
const sine = { O1_Waveform: 0, O2_Amp: 0, N_Amp: 0, Filter: 0, Voices: 16, PolyMode: 1, Attack: 0, Sustain: 1, Release: 0.01,
               VeloSens: 0, RandomAmp: 0, RandomPan: 0, RandomFreq: 0, FX_Rack_1: 0, FX_Rack_2: 0, FX_Rack_3: 0, FX_Rack_4: 0 };
const saw = { ...sine, O1_Waveform: 1 };

const conn = (k, source, target, amount, more = {}) => ({
    [ModMatrix.sourceId (k)]: src (source), [ModMatrix.targetId (k)]: tgt (target), [ModMatrix.amountId (k)]: amount,
    ...Object.fromEntries (Object.entries (more).map (([key, v]) => [`Mod${k}_${key}`, v])),
});

const play = player ({ dir, program: init, base: sine, rate });
const rms = (x, a, b) => rmsOf (x, a, b, rate);
const near = (a, b, tol) => Math.abs (a / b - 1) < tol;
const f = x => x.toFixed (3);
const keyHz = k => 440 * 2 ** ((k - 69) / 12);

//==============================================================================
// sources, each on the volume (gain 1 + amount x)

// chord position: a held chord's lowest note -1, middle 0, highest 1; a note alone 0
{
    const keys = [48, 55, 64];
    const x = play (keys.map (k => [0, k, 0.6]), conn (1, "chord", "volume", 0.5), 0.6);
    const plain = play (keys.map (k => [0, k, 0.6]), {}, 0.6);
    const gain = keys.map (k => 10 ** ((levelAt (x[0], keyHz (k), 0.15, rate) - levelAt (plain[0], keyHz (k), 0.15, rate)) / 20));
    const alone = rms (play ([[0, 69, 0.5]], conn (1, "chord", "volume", 0.5), 0.5), 0.1, 0.4) /
                  rms (play ([[0, 69, 0.5]], {}, 0.5), 0.1, 0.4);
    check (near (gain[0], 0.5, 0.03) && near (gain[1], 1, 0.03) && near (gain[2], 1.5, 0.03) && near (alone, 1, 0.01),
           `chord position: low ${f (gain[0])} (0.5), middle ${f (gain[1])} (1), high ${f (gain[2])} (1.5), alone ${f (alone)} (1)`);
}

// gap: the first note 1, one 0.5 s after the last 0.74 (log 50 / log 200), a chord's second 0
{
    const x = play ([[0, 69, 0.3], [0.5, 69, 0.3], [1, 57, 0.3], [1, 64, 0.3]], conn (1, "gap", "volume", 0.5), 1.4);
    const plain = play ([[0, 69, 0.3], [0.5, 69, 0.3], [1, 57, 0.3], [1, 64, 0.3]], {}, 1.4);
    const first = rms (x, 0.05, 0.25) / rms (plain, 0.05, 0.25);
    const second = rms (x, 0.55, 0.75) / rms (plain, 0.55, 0.75);
    const chord = [57, 64].map (k => 10 ** ((levelAt (x[0], keyHz (k), 1.0, rate) - levelAt (plain[0], keyHz (k), 1.0, rate)) / 20));
    const want = 1 + 0.5 * Math.log (50) / Math.log (200);
    // (the chord's notes come in one order or the other: one has the 0.5 s gap, the other none)
    check (near (first, 1.5, 0.01) && near (second, want, 0.01) && near (Math.min (...chord), 1, 0.02) && near (Math.max (...chord), want, 0.02),
           `gap: first ${f (first)} (1.5), 0.5 s after ${f (second)} (${f (want)}), a chord's ${chord.map (f).join (" and ")}`);
}

// legato: a note started while another is held 1, one after a rest 0
{
    const notes = [[0, 57, 0.5], [0.3, 69, 0.5], [1, 69, 0.4]];
    const x = play (notes, conn (1, "legato", "volume", 0.5), 1.5);
    const over = rms (x, 0.55, 0.75), after = rms (x, 1.1, 1.3);
    check (near (over / after, 1.5, 0.01), `legato: overlapping ${f (over / after)}x the one after a rest (1.5)`);
}

// pitch: the note as it sounds; an octave over middle C 0.2, also when the transpose puts it there
{
    const at = (key, sets = {}) => rms (play ([[0, key, 0.4]], { ...conn (1, "pitch", "volume", 1), ...sets }, 0.4), 0.1, 0.35) /
                                   rms (play ([[0, key, 0.4]], sets, 0.4), 0.1, 0.35);
    const c4 = at (60), c5 = at (72), c3 = at (48), transposed = at (60, { GlobalTranspose: 1 });
    check (near (c4, 1, 0.01) && near (c5, 1.2, 0.01) && near (c3, 0.8, 0.01) && near (transposed, 1.2, 0.01),
           `pitch: C3 ${f (c3)} (0.8), C4 ${f (c4)} (1), C5 ${f (c5)} (1.2), C4 an octave up ${f (transposed)} (1.2)`);
}

// steps: macro 1 at 0.3 cutting the volume: as it is 0.7, two steps 1 (0 rounds down), three 0.5;
// key C5 (0.2, bipolar) on the volume: three steps snap it to 0
{
    const none = rms (play ([[0, 69, 0.4]], {}, 0.4), 0.1, 0.35);
    const at = steps => rms (play ([[0, 69, 0.4]], { Macro_1: 0.3, ...conn (1, "macro1", "volume", -1, { Steps: steps }) }, 0.4), 0.1, 0.35) / none;
    const free = at (0), two = at (2), three = at (3);
    const keyed = steps => rms (play ([[0, 72, 0.4]], conn (1, "key", "volume", 1, { Steps: steps }), 0.4), 0.1, 0.35) /
                           rms (play ([[0, 72, 0.4]], {}, 0.4), 0.1, 0.35);
    check (near (free, 0.7, 0.01) && near (two, 1, 0.01) && near (three, 0.5, 0.01) && near (keyed (0), 1.2, 0.01) && near (keyed (3), 1, 0.01),
           `steps: macro ${f (free)} (0.7), 2 steps ${f (two)} (1), 3 steps ${f (three)} (0.5); key ${f (keyed (0))} (1.2), 3 steps ${f (keyed (3))} (1)`);

    const p = Preset.make ("steps");
    p.values.set (ModMatrix.sourceId (1), src ("random"));
    p.values.set (ModMatrix.targetId (1), tgt ("pitch"));
    p.values.set (ModMatrix.amountId (1), 0.5);
    p.values.set (ModMatrix.stepsId (1), 25);
    const back = Preset.parseJson (JSON.stringify (Preset.toJson (p)))._0.presets[0];
    check (back.values.get (ModMatrix.stepsId (1)) === 25, "a preset keeps a connection's steps");
}

//==============================================================================
// effects in the voices

// a level curve (windows of `step` s), how far two differ (their largest difference over the
// first's peak), and how alike they are (correlation)
const curve = (x, a, b, step = 0.02) => Array.from ({ length: Math.round ((b - a) / step) }, (_, k) => rms (x, a + step * k, a + step * (k + 1)));
const differs = (a, b) => Math.max (...a.map ((v, i) => Math.abs (v - b[i]))) / Math.max (...a);
const correlation = (a, b) =>
{
    const ma = a.reduce ((s, v) => s + v, 0) / a.length, mb = b.reduce ((s, v) => s + v, 0) / b.length;
    let ab = 0, aa = 0, bb = 0;
    a.forEach ((v, i) => { ab += (v - ma) * (b[i] - mb); aa += (v - ma) ** 2; bb += (b[i] - mb) ** 2; });
    return ab / Math.sqrt (aa * bb);
};

// the lane phaser on a sine, its notch sweeping past it: the level swings with the LFO
const phaser = more => ({ VL_1: entry ("phaser"), Ph_On: 1, Ph_Depth: 1, Ph_Mix: 0.5, Ph_Feedback: 0, Ph_Track: 1,
                          Ph_Freq: expPos (20, 20000, 261.63), Ph_Rate: expPos (0.02, 20, 1), ...more });

// random start: two notes of a key sweep alike from their note-ons, apart with a random start
{
    const notes = [[0, 60, 0.9], [1, 60, 0.9]];
    const same = play (notes, phaser ({}), 2);
    const rand = play (notes, phaser ({ Ph_PhaseRand: 1 }), 2);
    const d0 = differs (curve (same, 0.05, 0.85), curve (same, 1.05, 1.85));
    const d1 = differs (curve (rand, 0.05, 0.85), curve (rand, 1.05, 1.85));
    // (from the note-on they differ only where the blocks fall)
    check (d0 < 0.05 && d1 > 0.2, `phaser random start: two notes' sweeps differ by ${f (d0)} from the note-on, ${f (d1)} at random`);

    const fl = { VL_1: entry ("flanger"), Fl_On: 1, Fl_Depth: 1, Fl_Mix: 0.5, Fl_Feedback: 0.5, Fl_Rate: expPos (0.02, 20, 1) };
    const flSame = play (notes, { ...saw, ...fl }, 2);
    const flRand = play (notes, { ...saw, ...fl, Fl_PhaseRand: 1 }, 2);
    const e0 = differs (curve (flSame, 0.05, 0.85), curve (flSame, 1.05, 1.85));
    const e1 = differs (curve (flRand, 0.05, 0.85), curve (flRand, 1.05, 1.85));
    check (e0 < 0.06 && e1 > 0.2, `flanger random start: ${f (e0)} from the note-on, ${f (e1)} at random`);
}

// rate tracking: an octave up sweeps twice as fast, so that C5's sweep in 10 ms windows matches
// C4's in 20 ms ones (the centre follows the note too); without, it doesn't
{
    const c4 = curve (play ([[0, 60, 4]], phaser ({ Ph_RateTrack: 1 }), 4), 0.1, 3.7, 0.02);
    const c5 = curve (play ([[0, 72, 4]], phaser ({ Ph_RateTrack: 1 }), 4), 0.05, 1.85, 0.01);
    const fixed = curve (play ([[0, 72, 4]], phaser ({}), 4), 0.05, 1.85, 0.01);
    const tracked = correlation (c4, c5), untracked = correlation (c4, fixed);
    check (tracked > 0.95 && untracked < 0.5,
           `phaser rate tracking: C5's sweep is C4's at twice the speed (correlation ${f (tracked)}; ${f (untracked)} without)`);
}

// the flanger's delay tracking: at feedback 0.9 the comb's peaks sit on the note's harmonics,
// for a note far from middle C (the delay knob at middle C's period), and one too low for the
// untracked delay's reach
{
    const fl = { VL_1: entry ("flanger"), Fl_On: 1, Fl_Depth: 0, Fl_Mix: 1, Fl_Feedback: 0.9,
                 Fl_Delay: Math.log (1000 / 261.63 / 0.1) / Math.log (200) };
    const gain = (key, track) =>
    {
        const x = play ([[0, key, 1]], { ...saw, ...fl, Fl_Track: track }, 1);
        const d = play ([[0, key, 1]], saw, 1);
        return levelAt (x[0], keyHz (key), 0.4, rate) - levelAt (d[0], keyHz (key), 0.4, rate);
    };
    const g67 = gain (67, 1), u67 = gain (67, 0), g48 = gain (48, 1);
    check (g67 > 15 && u67 < 5 && g48 > 15, `flanger delay tracking: G4's fundamental +${g67.toFixed (1)} dB tracked, ${u67.toFixed (1)} dB not; C3 +${g48.toFixed (1)} dB`);
}

// the lo-fi sampler's tracking: on a sine, its output stays on the note's harmonics
{
    // the share of the power within 3 bins of the note's harmonics
    const harmonic = (x, hz) =>
    {
        const n = 32768, i0 = Math.round (0.2 * rate);
        const re = new Float64Array (n), im = new Float64Array (n);
        for (let i = 0; i < n; ++i) re[i] = x[i0 + i] * (0.5 - 0.5 * Math.cos (2 * Math.PI * i / n));
        fft (re, im);
        let all = 0, on = 0;
        for (let b = 1; b < n / 2; ++b)
        {
            const p = re[b] * re[b] + im[b] * im[b];
            const h = b * rate / n / hz;
            all += p;
            if (Math.abs (h - Math.round (h)) * hz * n / rate <= 3 && Math.round (h) >= 1) on += p;
        }
        return on / all;
    };
    const lofi = track => ({ VL_1: entry ("distortion", 2), Sat2_Type: 16, Sat2_Drive: 0.75, Sat2_Tone: 0.5, Sat2_Track: track });
    const key = 57;
    const on = harmonic (play ([[0, key, 1.2]], lofi (1), 1.2)[0], keyHz (key));
    const off = harmonic (play ([[0, key, 1.2]], lofi (0), 1.2)[0], keyHz (key));
    check (on > 0.999 && off < on - 0.01, `lo-fi tracking: ${(100 * on).toFixed (2)} % of the power on the note's harmonics, ${(100 * off).toFixed (2)} % without`);
}

// the octaver: each note of a chord gets its own octave down; the octave up doubles a sine
{
    const keys = [57, 64];
    const oc = more => ({ VL_1: entry ("octaver"), Oc_On: 1, ...more });
    const down = play (keys.map (k => [0, k, 1]), oc ({ Oc_Sub: 1, Oc_Dry: 0 }), 1);
    const dry = play (keys.map (k => [0, k, 1]), {}, 1);
    const subs = keys.map (k => levelAt (down[0], keyHz (k) / 2, 0.3, rate) - levelAt (dry[0], keyHz (k), 0.3, rate));
    const without = keys.map (k => levelAt (dry[0], keyHz (k) / 2, 0.3, rate) - levelAt (dry[0], keyHz (k), 0.3, rate));
    check (subs.every (d => d > -12) && without.every (d => d < -60),
           `octaver down: each note's octave below at ${subs.map (d => d.toFixed (1)).join (", ")} dB (dry ${without.map (d => d.toFixed (0)).join (", ")} dB)`);

    const up = play ([[0, 57, 1]], oc ({ Oc_Sub: 0, Oc_Up: 1, Oc_Dry: 0 }), 1);
    const one = play ([[0, 57, 1]], {}, 1);
    const octave = levelAt (up[0], 2 * keyHz (57), 0.3, rate) - levelAt (one[0], keyHz (57), 0.3, rate);
    const fund = levelAt (up[0], keyHz (57), 0.3, rate) - levelAt (one[0], keyHz (57), 0.3, rate);
    check (octave > -12 && fund < octave - 30, `octaver up: the octave at ${octave.toFixed (1)} dB, the note itself at ${fund.toFixed (1)} dB`);

    const [l] = play (keys.map (k => [0, k, 1]), oc ({ Oc_Sub: 1, Oc_Up: 1 }), 1.5);
    let peak = 0, finite = true;
    for (const v of l) { if (! Number.isFinite (v)) finite = false; peak = Math.max (peak, Math.abs (v)); }
    check (finite && peak < 4, `octaver bounded: peak ${f (peak)}`);
}

done ("extras ok");
