// Host-facing metadata per parameter index (used by tools/gen.mjs to declare the patch's
// endpoints): name, range, default, switch names, and a unit when the internal value is
// the number the original displays.

import { makeDefs } from "./paramdefs.js";

// The original has a few duplicate or misleading names; hosts need unique ones.
const RENAMED = { 30: "LFO 2 unit", 67: "Chorus mode", 68: "Chorus stereo", 75: "Delay on", 78: "D reverse L", 79: "D reverse R",
                  90: "Reverb on", 103: "Voice mode", 29: "LFO 1 > LFO 2 rate", 40: "LFO 2 > LFO 1 rate" };
const UNISON_NAMES = ["Unison voices", "Unison detune", "Unison spread", "Unison pitch jitter", "Unison pan jitter"];

let defs = null;

function unitFor (d)
{
    if (d.names || d.isInt) return undefined;

    // the unit is only meaningful when the displayed number equals the internal value
    const probe = [0.3, 0.7].map (v => d.fromNorm (v));
    for (const x of probe)
    {
        const m = /^(-?\d+(\.\d+)?) (ms|Hz|dB|st|cents|sec|semitones)\b/.exec (d.valueText (x));
        if (! m || Math.abs (parseFloat (m[1]) - x) > 0.02 * Math.max (1, Math.abs (x))) return undefined;
    }
    const m = /^-?\d+(\.\d+)? (\S+)/.exec (d.valueText (probe[0]));
    return m ? m[2] : undefined;
}

export function paramInfo (index)
{
    defs ??= makeDefs();
    const d = defs[index];
    const hostName = RENAMED[index] ?? (index >= 124 && index <= 128 ? UNISON_NAMES[index - 124] : d.name);

    return {
        hostName,
        min: d.min,
        max: d.max,
        init: d.init,
        names: d.names ?? undefined,
        unit: unitFor (d),
    };
}
