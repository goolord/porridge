// The rack's pool (dsp/Common.cmajor's FxPool, Synth's claimPool): effects claim what their
// settings need, so stacking costs nothing up front:
//   - eight delays in the rack at their longest (10 s a side) all get their lines;
//   - a rack that needs more than the pool has runs one effect dry, and says which slot
//     (poolOut, which the test host writes with --pool);
//   - a delay whose line grows while another's lines sit after its own moves with what it holds:
//     the side that didn't change echoes on as if nothing happened;
//   - a short delay takes a few blocks, not its longest line's.
// Renders through the test host with an impulse in place of the voices.
//
//   node tools/test/pool.mjs
//
// Build the host first (tools/test/build.sh). Output goes to tools/test/build/pool/.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as SlotParams from "../../ui/SlotParams.res.mjs";
import { root, outDir, render, toEndpoints, checker } from "./lib.mjs";

const dir = outDir ("pool");
const { check, done } = checker ({ verbose: true });
const rate = 44100;
const init = join (root, "tools", "re", "init_prog.bin");

// an impulse, then silence
const input = join (dir, "impulse.f32");
{
    const n = rate * 2;
    const b = Buffer.alloc (8 + 8 * n);
    b.writeInt32LE (2, 0); b.writeInt32LE (n, 4);
    b.writeFloatLE (0.5, 8); b.writeFloatLE (0.5, 8 + 4 * n);
    writeFileSync (input, b);
}
const events = join (dir, "none.txt");
writeFileSync (events, "");

const value = (kind, n) => PorridgeParams.entryValue (kind, n);
const empty = Object.fromEntries (Array.from ({ length: 8 }, (_, k) => [PorridgeParams.rackId (k + 1), 0]));
// a delay of `seconds` a side (in seconds from 1 s, else in 10 ms units), with the dry sound and
// no feedback (a delay whose first block is silent goes to sleep, as Oatmeal's does)
const delayIn = (slot, seconds) => ({
    [`D_On@${slot}`]: 1, [`D_Unit@${slot}`]: seconds >= 1 ? 2 : 1,
    [`D_LengthL@${slot}`]: seconds >= 1 ? seconds : seconds * 100, [`D_LengthR@${slot}`]: seconds >= 1 ? seconds : seconds * 100,
    [`D_FeedbackL@${slot}`]: 0, [`D_FeedbackR@${slot}`]: 0, [`D_Wet@${slot}`]: 1,
});

const run = (name, sets, { seconds = 1, eventsFile = events } = {}) =>
{
    const pool = join (dir, name + ".pool.txt");
    writeFileSync (pool, "");
    const out = render ({ program: init, events: eventsFile, frames: Math.round (seconds * rate), rate,
                          sets: { ...empty, Sat_Type: 0, ...sets }, args: ["--input", input, "--pool", pool], out: join (dir, name + ".f32") });
    const marks = readFileSync (pool, "utf8").trim ().split ("\n").filter (l => l).map (l => Number (l.split (" ")[1]));
    return { out, marks: marks.at (-1) ?? 0 };
};
const firstEcho = (x, from = 0) => { for (let i = from; i < x.length; ++i) if (Math.abs (x[i]) > 0.01) return i; return -1; };

// eight delays at their longest
{
    const sets = {};
    for (let k = 1; k <= 8; ++k)
        Object.assign (sets, { [PorridgeParams.rackId (k)]: value ("delay", k + 1) }, delayIn (k, 100));
    const { marks } = run ("eight_delays", sets);
    check (marks === 0, `eight delays at 10 s a side fit (out of memory: ${marks.toString (2)})`);
}

// more than the pool: Oatmeal's delay at 30 s, six delays at 10 s and the convolver
{
    const sets = { FX_Rack_1: value ("convolve", 1), "Cv_On@1": 1, FX_Rack_2: 2, FX_Order: PorridgeParams.fxOrderIndex ([1, 0, 2, 3]), D_On: 1, D_Unit: 2, D_LengthL: 100, D_LengthR: 100 };
    for (let k = 3; k <= 8; ++k)
        Object.assign (sets, { [PorridgeParams.rackId (k)]: value ("delay", k) }, delayIn (k, 100));
    const { marks } = run ("too_much", sets);
    check (marks !== 0 && (marks & (marks - 1)) === 0, `a rack that needs more than the pool runs one effect dry, and says which (${marks.toString (2)})`);
    // without the convolver, it all fits
    const { marks: fits } = run ("just_enough", { ...sets, FX_Rack_1: 0 });
    check (fits === 0, `without the convolver it fits (${fits.toString (2)})`);
}

// a delay's line grows while another delay's lines sit after it: it moves with what it holds,
// so its left side, which didn't change, echoes on as it would have
{
    const base = { FX_Rack_1: value ("delay", 2), FX_Rack_2: value ("delay", 3), ...delayIn (1, 1), ...delayIn (2, 1),
                   "D_FeedbackL@1": 0.9 };
    const grown = { ...base, "D_LengthR@1": 4 };
    const knob = SlotParams.knobOf (id => ({ ...base })[id] ?? 0, "D_LengthR@1");
    const at = Math.round (1.5 * rate);
    const ev = join (dir, "grow.txt");
    writeFileSync (ev, `${at} ${knob} ${toEndpoints (grown)[knob]}\n`);
    const a = run ("grow_later", base, { seconds: 3, eventsFile: ev }).out[0];
    const b = run ("grown", grown, { seconds: 3 }).out[0];
    let worst = 0, level = 0;
    for (let i = at + 64; i < a.length; ++i) { worst = Math.max (worst, Math.abs (a[i] - b[i])); level = Math.max (level, Math.abs (b[i])); }
    check (level > 0.01 && worst < 1e-6, `a growing delay keeps its left side's echoes (peak ${level.toFixed (3)}, differs by ${worst.toExponential (1)})`);
}

// a short delay: its echo where it should be
{
    const { out } = run ("short", { FX_Rack_1: value ("delay", 2), ...delayIn (1, 0.25) });
    const echo = firstEcho (out[0], 1000) - 64;
    check (Math.abs (echo - 0.25 * rate) < 64, `a 250 ms delay echoes at ${(echo / rate * 1000).toFixed (1)} ms`);
}

done ("pool ok");
