// Parameter definitions for the view, built on the reverse-engineered parameter table
// (oatmeal/oatmeal-params.js, verified against Oatmeal.dll).
//
// Endpoint values are Oatmeal's internal values, except pulse width, which the patch takes
// as a 0..1 fraction (Oatmeal stores it as a 32-bit phase).

import * as OP from "./oatmeal/oatmeal-params.js";
import { makeDefaultProgram } from "./oatmeal/oatmeal-format.js";
import { FIELDS } from "./oatmeal/fields.js";
import { writeField } from "./bank.js";

const FILTER_NAMES = ["off", "1P lowpass", "2P lowpass", "4P lowpass", "1P highpass", "2P highpass", "4P highpass",
                      "2P wide bandpass", "2P narrow bandpass", "4P bandpass", "2P notch",
                      "nonlinear 2P lowpass", "nonlinear 4P lowpass", "phaser, 4 stages", "phaser, 12 stages", "phaser, 36 stages"];

// Compact names for the narrow value fields (the full names appear in menus and the status bar).
const SHORT = {
    Filter:          ["off", "1P LP", "2P LP", "4P LP", "1P HP", "2P HP", "4P HP", "2P BP wide", "2P BP narrow", "4P BP", "2P notch", "2P LP drive", "4P LP drive", "phaser 4", "phaser 12", "phaser 36"],
    Filter2:         ["as filter 1", "1P LP", "2P LP", "4P LP", "1P HP", "2P HP", "4P HP", "2P BP wide", "2P BP narrow", "4P BP", "2P notch", "2P LP drive", "4P LP drive", "phaser 4", "phaser 12", "phaser 36"],
    Sat_Mode:        ["global", "voice, post-filter", "voice, pre-filter", "double"],
    PolyMode:        ["mono", "poly", "mono legato"],
    AftertouchMode:  ["ignore", "channel", "poly"],
    OscMix:          ["normal", "hardsync", "FM 1 > 2"],
    GlideMode:       ["P", "P·o", "P/o", "P·(o+1/o)", "P·(1+o)", "P·(1+1/o)", "P·(1+o+1/o)"],
    Arp_Mode:        ["off", "pattern", "global subseq", "chord pattern", "chord", "transp. chords"],
    D_ReverseL:      ["normal", "rev. out", "rev. fb"],
    D_ReverseR:      ["normal", "rev. out", "rev. fb"],
};

const UNIT_SHORT = { semitones: "st", semitone: "st", octaves: "oct", octave: "oct", seconds: "s", sec: "s" };

function compact (s)
{
    // "1392.50 Hz (*3.1648)" -> "1392.5 Hz"; "-6.02 dB (50.00 %)" -> "-6.02 dB"; "0.00 semitones" -> "0.00 st"
    const i = s.indexOf (" (");
    s = (i > 0 ? s.slice (0, i) : s).trim();
    s = s.replace (/[a-z]+/g, w => UNIT_SHORT[w] ?? w);
    // keep at most five significant digits so the readout fits its field
    return s.replace (/^(-?)(\d+)\.(\d+)/, (m, sign, a, b) =>
        a.length >= 5 ? sign + a : a.length + b.length > 5 ? sign + a + "." + b.slice (0, 5 - a.length) : m);
}

function firstNumber (s)
{
    const m = /-?\d+(\.\d+)?/.exec (s.replace ("-inf", "-1e9"));
    return m ? parseFloat (m[0]) : NaN;
}

export function makeDefs (contextProgram = () => null)
{
    const init = makeDefaultProgram ("Init");

    return FIELDS.map (([index, id, name, off, type]) =>
    {
        const p = OP.PARAMS[index];
        const isPw = type === "pw";
        const isInt = type === "i32" || type === "filter1" || type === "filter2";
        const toF = x => isPw ? (Math.round (x * 4294967296) >>> 0) : x;
        const fromF = x => isPw ? x / 4294967296 : x;

        let names = p.labels ? p.labels.slice() : null;
        if (type === "filter1") names = FILTER_NAMES.slice();
        if (type === "filter2") names = ["same as filter 1", ...FILTER_NAMES.slice (1)];
        if (names && p.states && names.length < p.states)
            while (names.length < p.states) names.push (String (names.length));

        let lo = fromF (Math.min (p.min, p.max)), hi = fromF (Math.max (p.min, p.max));
        if (type === "filter1" || type === "filter2") { lo = 0; hi = 15; }
        const initValue = fromF (OP.readInternal (init, index));
        const bipolar = ! names && lo < 0 && hi > 0;

        const def = {
            id, index, name, type, isInt,
            short: name,
            names: names && ! (isInt && names.length > 40) ? names : null,
            shortNames: SHORT[id] ?? null,
            init: initValue,
            min: isPw ? 0 : lo,
            max: isPw ? 1 : hi,
            bipolar,

            clamp (x)
            {
                if (! Number.isFinite (x)) x = initValue;
                if (isInt) return Math.max (Math.round (this.min), Math.min (Math.round (this.max), Math.round (x)));
                return Math.max (this.min, Math.min (this.max, x));
            },

            toNorm (x) { return OP.toNormalized (index, toF (x)); },
            fromNorm (v) { return fromF (OP.toInternal (index, Math.max (0, Math.min (1, v)))); },

            longText (x)
            {
                const prog = contextProgram();
                return OP.statusText (index, OP.textNormalized (index, toF (x)), prog ?? undefined);
            },

            valueText (x) { return OP.displayText (index, toF (x), contextProgram() ?? undefined); },
            shortText (x) { return compact (this.valueText (x)); },
            editText (x) { return this.shortText (x); },

            // Typed values are read in display units: find the knob position whose displayed
            // number matches.
            parse (text)
            {
                const want = parseFloat (text);
                if (! Number.isFinite (want)) return undefined;
                const at = v => firstNumber (this.valueText (this.fromNorm (v)));
                let a = 0, b = 1, fa = at (a), fb = at (b);
                if (! Number.isFinite (fa) || ! Number.isFinite (fb) || fa === fb) return undefined;
                const up = fb > fa;
                if (up ? want <= fa : want >= fa) return this.fromNorm (0);
                if (up ? want >= fb : want <= fb) return this.fromNorm (1);
                for (let k = 0; k < 40; ++k)
                {
                    const m = (a + b) / 2, fm = at (m);
                    if (Number.isFinite (fm) && (up ? fm < want : fm > want)) a = m; else b = m;
                }
                return this.fromNorm ((a + b) / 2);
            },
        };

        return def;
    });
}

// A scratch v38 program holding the current values, used as the context for status texts
// (several texts depend on other fields: octave size, tuning, breakpoint, targets...).
export function makeContextProgram (defs)
{
    const bytes = makeDefaultProgram ("Init");
    return {
        bytes,
        update (values)
        {
            for (const f of FIELDS)
                if (values.has (f[1])) writeField (bytes, f, values.get (f[1]));
        },
    };
}
