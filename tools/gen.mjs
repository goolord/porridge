// Generates the parameter plumbing from the parameter table (run `npm run res` first):
//   dsp/ParamStore.cmajor  - the parameter endpoints: Oatmeal's 342 (named after the original skin
//                            actions), then Porridge's own (ui/PorridgeParams.res), forwarding every
//                            change to the synth as (slot, value)
//   dsp/Slots.cmajor       - slot constants: index into the synth's mirror of the program struct,
//                            every slot's default, and names for the choice values the DSP tests
//   dsp/ModTables.cmajor   - the modulation matrix's sources and targets (ui/ModMatrix.res), with
//                            each parameter target's knob law as a table
//   tools/test/build/fields_gen.h - endpoint -> chunk field table for the C++ test host
//
// run: node tools/gen.mjs

import { writeFileSync, readFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { all as fields } from "../ui/oatmeal/Fields.res.mjs";
import { xyTargets, modEnvTargets, ccTargets } from "../ui/oatmeal/OatmealParams.res.mjs";
import { paramInfo } from "../ui/ParamInfo.res.mjs";
import { all as porridgeParams, slotOf as porridgeSlot, fxOrder } from "../ui/PorridgeParams.res.mjs";
import { makeDefs } from "../ui/ParamDefs.res.mjs";
import * as ModMatrix from "../ui/ModMatrix.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..");

// Writes a file unless it already holds this text. Git may check the generated files out with
// CRLF line endings, so they are compared without them: an unchanged file is left alone and
// doesn't show up as modified.
function writeGenerated (path, text)
{
    if (existsSync (path) && readFileSync (path, "utf8").replace (/\r\n/g, "\n") === text)
        return;

    writeFileSync (path, text);
}

// The synth mirrors the program struct as float P[NUM_SLOTS], slot = chunk offset / 4.
// Filter 1 and filter 2 share one int in the chunk; they get their own virtual slots.
// Porridge's own parameters follow from slot 2600.
const NUM_SLOTS = porridgeSlot (porridgeParams.length);
const VIRTUAL = { filter1: 2594, filter2: 2595 };

function slotOf ({ offset, kind })
{
    if (kind === "filter1" || kind === "filter2") return VIRTUAL[kind];
    return offset / 4;
}

function cmajString (s) { return JSON.stringify (s); }

function num (x)
{
    if (Number.isInteger (x)) return String (x);
    let s = String (Math.fround (x));
    if (! /[.e]/.test (s)) s += ".0";
    return s;
}

// a float32 literal
function cf (x)
{
    if (! Number.isFinite (x)) throw new Error (`not a finite table value: ${x}`);
    let s = num (x);
    if (! /[.e]/.test (s)) s += ".0";
    return s + "f";
}

const defs = new Map (makeDefs().map (d => [d.id, d]));
const endpoints = [], handlers = [], slots = [], cfields = [], cextra = [];
const slotDefaults = new Array (NUM_SLOTS).fill (0);

const all = [
    ...fields.map (f => ({ ...f, slot: slotOf (f) })),
    ...porridgeParams.map ((p, i) => ({ index: fields.length + i, id: p.id, slot: porridgeSlot (i), porridge: true })),
];

for (const f of all)
{
    const { index, id, offset, kind, slot } = f;
    const info = paramInfo (index);
    const { isInt } = defs.get (id);
    const ann = [`name: ${cmajString (info.hostName)}`];

    if (isInt)
    {
        ann.push (`min: ${info.min | 0}`, `max: ${info.max | 0}`, `init: ${Math.round (info.init)}`);
        if (info.names) ann.push (`text: ${cmajString (info.names.join ("|"))}`);
        else ann.push (`step: 1`);
        endpoints.push (`    input event int ${id} [[ ${ann.join (", ")} ]];`);
        handlers.push (`    event ${id} (int v) { paramOut <- porridge::ParamChange (${slot}, float (v)); }`);
        slotDefaults[slot] = Math.round (info.init);
    }
    else
    {
        ann.push (`min: ${num (info.min)}`, `max: ${num (info.max)}`, `init: ${num (info.init)}`);
        if (info.unit) ann.push (`unit: ${cmajString (info.unit)}`);
        endpoints.push (`    input event float ${id} [[ ${ann.join (", ")} ]];`);
        handlers.push (`    event ${id} (float v) { paramOut <- porridge::ParamChange (${slot}, v); }`);
        slotDefaults[slot] = info.init;
    }

    slots.push (`    let ${id} = ${slot};`);
    if (f.porridge) cextra.push (`    { "${id}", ${isInt ? "true" : "false"} },`);
    else cfields.push (`    { "${id}", ${offset}, FieldType::${kind} },`);
}

// A camelCase identifier from a menu label: "LFO 1 speed" -> lfo1Speed, "1 PWM rate" -> osc1PwmRate.
function labelIdent (label)
{
    const words = label.replace (/[()]/g, "").toLowerCase().split (/[^a-z0-9]+/).filter (w => w);
    const s = words.map ((w, i) => i === 0 ? w : w[0].toUpperCase() + w.slice (1)).join ("");
    return /^[0-9]/.test (s) ? "osc" + s : s;
}

function targetConstants (ns, doc, labels)
{
    return `/// ${doc}\nnamespace porridge::${ns}\n{\n${labels.map ((l, i) => `    let ${labelIdent (l)} = ${i};`).join ("\n")}\n}\n`;
}

// Choice values the DSP compares against, by their menu labels (which must exist).
const choices = [
    { ns: "waveType", param: "O1_Waveform", doc: "Oscillator waveforms (O1_Waveform, O2_Waveform).",
      values: { sine: "Sine", saw: "Saw", pulse: "Pulse", triangle: "Triangle", user: "User", userPwm: "User PWM",
                sawHQ: "Saw HQ", pulseHQ: "Pulse HQ", triangleHQ: "Triangle HQ" } },
    { ns: "oscMixMode", param: "OscMix", doc: "How the two oscillators combine (OscMix).",
      values: { normal: "normal", sync: "hardsync", fm: "FM (1 -> 2, 1 silent)", pm2to1: "PM 2 > 1",
                pmFeedback: "PM 1 feedback", ring: "ring 1 × 2", am: "AM 2 > 1" } },
    { ns: "filterType", param: "Filter", doc: "Filter types (Filter; Filter2 uses 0 for \"same as filter 1\").",
      values: { off: "off", lp1: "1P lowpass", lp2: "2P lowpass", lp4: "4P lowpass", hp1: "1P highpass", hp2: "2P highpass",
                hp4: "4P highpass", bpWide: "2P wide bandpass", bpNarrow: "2P narrow bandpass", bp4: "4P bandpass",
                notch: "2P notch", lp2Nonlinear: "nonlinear 2P lowpass", lp4Nonlinear: "nonlinear 4P lowpass",
                phaser4: "phaser, 4 stages", phaser12: "phaser, 12 stages", phaser36: "phaser, 36 stages",
                svf: "SVF LP > BP > HP", ladder: "ladder", diodeLadder: "diode ladder", sallenKey: "Sallen-Key",
                comb: "comb", formant: "formant" } },
    { ns: "satMode", param: "Sat_Mode", doc: "Where the distortion sits (Sat_Mode).",
      values: { global: "global", afterFilter: "per voice, after filter", beforeFilter: "per voice, before filter",
                both: "double (before filter and global)" } },
];

function choiceConstants ({ ns, param, doc, values })
{
    const names = paramInfo (all.find (f => f.id === param).index).names;
    const lines = Object.entries (values).map (([name, label]) =>
    {
        const i = names.indexOf (label);
        if (i < 0) throw new Error (`${param} has no choice "${label}"`);
        return `    let ${name} = ${i};`;
    });
    return `/// ${doc}\nnamespace porridge::${ns}\n{\n${lines.join ("\n")}\n}\n`;
}

const fxOrders = Array.from ({ length: 24 }, (_, k) => fxOrder (k));

const header = `//  Generated by tools/gen.mjs - do not edit by hand.\n\n`;

writeGenerated (join (root, "dsp", "ParamStore.cmajor"), header +
`/// Every parameter of the original, in the original order, as an endpoint named after the
/// original skin action, then Porridge's own parameters. Values are the internal values
/// stored in an Oatmeal preset. Each change is forwarded to the synth as (slot, value).
processor ParamStore
{
    output event porridge::ParamChange paramOut;

${endpoints.join ("\n")}

${handlers.join ("\n")}
}
`);

writeGenerated (join (root, "dsp", "Slots.cmajor"), header +
`namespace porridge
{
    /// A parameter change: slot = chunk offset / 4 (or a virtual slot), value = internal value.
    struct ParamChange
    {
        int slot;
        float value;
    }

    let numSlots = ${NUM_SLOTS};

    /// Every slot's default (the parameter's, 0 where no parameter lives), which the synth
    /// starts from: hosts may not send a parameter they have never changed
    let slotDefaults = float[numSlots] (${slotDefaults.map (cf).join (", ")});

    /// FX_Order's effect orders (0 chorus, 1 delay, 2 reverb, 3 EQ), four per value
    let fxOrders = int[${fxOrders.length * 4}] (${fxOrders.flat().join (", ")});
}

/// Index of every parameter in the synth's mirror of the program struct.
namespace porridge::slot
{
${slots.join ("\n")}
}

${targetConstants ("xyTgt", "X/Y pad targets (XY_H_Target_n, XY_V_Target_n).", xyTargets)}
${targetConstants ("meTgt", "Mod envelope targets (M1_Target_n, M2_Target_n).", modEnvTargets)}
${targetConstants ("ccTgt", "MIDI controller targets (CCn_Target_n).", ccTargets)}
${choices.map (choiceConstants).join ("\n")}`);

mkdirSync (join (root, "tools", "test", "build"), { recursive: true });
writeGenerated (join (root, "tools", "test", "build", "fields_gen.h"), header +
`#pragma once
enum class FieldType { f32, i32, filter1, filter2, pw };
struct PorridgeField { const char* id; int offset; FieldType type; };
static const PorridgeField porridgeFields[] =
{
${cfields.join ("\n")}
};
// Porridge's own parameters: endpoint id, int or float
struct PorridgeExtra { const char* id; bool isInt; };
static const PorridgeExtra porridgeExtras[] =
{
${cextra.join ("\n")}
};
`);

//==============================================================================
// modulation tables

const TABLE = 257;

const kinds = { Knob: 1, Pitch: 2, Volume: 3, Pan: 4 };
const targetKind = [], targetSlot = [], targetRow = [], targetScale = [], rows = [], rowNames = [];

ModMatrix.targets.forEach ((t, i) =>
{
    const law = t.law;
    const tag = typeof law === "string" ? law : law.TAG;
    targetKind.push (i === 0 ? 0 : kinds[tag]);
    targetScale.push (cf (tag === "Pitch" ? law._0 : 0));

    if (tag === "Knob")
    {
        const d = defs.get (law._0);
        const f = all.find (f => f.id === law._0);
        if (! d || ! f) throw new Error (`unknown modulation target ${law._0}`);
        targetSlot.push (f.slot);
        targetRow.push (rows.length);
        rows.push (Array.from ({ length: TABLE }, (_, k) => cf (d.fromNorm (k / (TABLE - 1)))));
        rowNames.push (law._0);
    }
    else
    {
        targetSlot.push (-1);
        targetRow.push (-1);
    }
});

const ident = s => s.replace (/[^A-Za-z0-9_]/g, "_");

writeGenerated (join (root, "dsp", "ModTables.cmajor"), header +
`/// The modulation matrix's sources and targets (ui/ModMatrix.res). A parameter target moves
/// its knob: the table holds each one's knob law, the internal value at knob positions 0..1
/// in ${TABLE - 1} steps.
namespace porridge::mods
{
    let numSlots = ${ModMatrix.slots};
    let numSources = ${ModMatrix.sources.length};
    let numTargets = ${ModMatrix.targets.length};
    let tableSize = ${TABLE};

    /// target kinds
    let knob = 1;
    let pitch = 2;
    let volume = 3;
    let pan = 4;

    let targetKind  = int[${targetKind.length}] (${targetKind.join (", ")});
    let targetSlot  = int[${targetSlot.length}] (${targetSlot.join (", ")});
    let targetRow   = int[${targetRow.length}] (${targetRow.join (", ")});
    let targetScale = float[${targetScale.length}] (${targetScale.join (", ")});

    let table = float[${rows.length * TABLE}] (
${rows.map ((r, i) => `        ${r.join (", ")}${i + 1 < rows.length ? "," : ""}  // ${rowNames[i]}`).join ("\n")}
    );
}

/// Source indices
namespace porridge::mods::src
{
${ModMatrix.sources.map ((s, i) => `    let ${ident (s.key)} = ${i};`).join ("\n")}
}

/// Target indices
namespace porridge::mods::tgt
{
${ModMatrix.targets.map ((t, i) => `    let ${ident (t.key)} = ${i};`).join ("\n")}
}
`);

console.log (`generated ${all.length} parameters, ${ModMatrix.targets.length} modulation targets`);
