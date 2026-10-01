// Checks ui/oatmeal/OatmealParams.res against display strings sampled from Oatmeal.dll:
// for each parameter, normalized positions 0, 0.025 ... 1 were set through the VST
// interface and the stored value and effGetParamDisplay/Label text were recorded.
//
//   npm run res && node tools/re/check-params.mjs

import { readFileSync } from "node:fs";
import * as OP from "../../ui/oatmeal/OatmealParams.res.mjs";

const samples = JSON.parse (readFileSync (new URL ("./param_samples.json", import.meta.url)));
const f32 = new Float32Array (1), i32 = new Int32Array (f32.buffer);

let checked = 0, badValue = 0, badText = 0;
const report = [];

for (const s of samples)
{
    const p = OP.params[s.i];
    const isInt = p.type === "i32" || p.type === "u32";
    for (const [norm, rawInt, rawFloat, text] of s.samples)
    {
        ++checked;
        const internal = OP.toInternal (s.i, norm);
        // Filter and Filter2 share one packed int (lo16 / hi16)
        const want = s.id === "Filter" ? rawInt & 0xffff : s.id === "Filter2" ? rawInt >>> 16
                   : isInt || Number.isInteger (internal) && Math.abs (rawFloat) < 1e-30 ? rawInt : rawFloat;
        const same = Object.is (internal, want) || Math.abs (internal - want) <= 1e-6 * Math.max (1, Math.abs (want));
        if (! same) { ++badValue; if (report.length < 60) report.push (`${s.id} @${norm}: value ${internal} != ${want}`); }

        // The sampling host truncated long texts to 21-22 characters. Oatmeal's own display of
        // the filter-2 envelope speed above 1x prints "/(10 - ratio)" instead of "*ratio"; Porridge
        // shows the ratio, so those samples are skipped.
        const got = OP.displayText (s.i, internal).trim(), exp = String (text).trim();
        if (s.id === "F_Speed" && norm > 0.5) continue;
        if (! (got === exp || (exp.length >= 21 && got.startsWith (exp)))) { ++badText; if (report.length < 60) report.push (`${s.id} @${norm}: "${got}" != "${text}"`); }
    }
}

console.log (`${samples.length} parameters, ${checked} samples: ${badValue} value mismatches, ${badText} text mismatches`);
for (const r of report) console.log ("  " + r);
process.exit (badValue + badText ? 1 : 0);
