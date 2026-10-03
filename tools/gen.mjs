// Generates the parameter plumbing from the parameter table (run `npm run res` first):
//   dsp/ParamStore.cmajor  - the parameter endpoints: Oatmeal's 342 (named after the original skin
//                            actions), then Porridge's own (ui/PorridgeParams.res), forwarding every
//                            change to the synth as (slot, value); hosts don't list the routing
//                            and setup ones (ParamInfo: automatable: false); the stored parameters
//                            (ui/StoredParams.res: the custom shapes' points) have slots but no
//                            endpoints, and come in one shaperIn event per distortion
//   dsp/param-ids.txt      - every parameter's CLAP id, kept for good (tools/param-ids.mjs): new
//                            parameters are added to it
//   dsp/Slots.cmajor       - slot constants: index into the synth's mirror of the program struct,
//                            every slot's default, and names for the choice values the DSP tests
//   dsp/ModTables.cmajor   - the modulation matrix's sources and targets (ui/ModMatrix.res), with
//                            each parameter target's knob law as a table
//   tools/test/build/fields_gen.h - endpoint -> chunk field table for the C++ test host
//   tools/test/PorridgeTest.cmajorpatch - the test host's manifest: Porridge.cmajorpatch's
//                            sources with the test graph in place of dsp/Porridge.cmajor
//
// run: node tools/gen.mjs

import { writeFileSync, readFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { all as fields } from "../ui/oatmeal/Fields.res.mjs";
import { xyTargets, modEnvTargets, ccTargets } from "../ui/oatmeal/OatmealParams.res.mjs";
import { paramInfo } from "../ui/ParamInfo.res.mjs";
import { all as porridgeParams, slotOf as porridgeSlot, fxOrder, rackId, rackSlots, rackKinds, rackEntries,
         knobSpecs, workSpecs, slotCount, knobCount, rackKnobs, knobsOf, slotKindId, firstInstance,
         instanceCount } from "../ui/PorridgeParams.res.mjs";
import { makeDefs, choiceValue } from "../ui/ParamDefs.res.mjs";
import { programSize, tableOffset } from "../ui/oatmeal/OatmealFormat.res.mjs";
import * as ModMatrix from "../ui/ModMatrix.res.mjs";
import { groups as storedGroups, isStored } from "../ui/StoredParams.res.mjs";
import { readIds, assignIds, idsText } from "./param-ids.mjs";

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
// Filter 1 and filter 2 share one int in the chunk; they get their own virtual slots, the two
// after the struct's. Porridge's own parameters follow from slot 2600, then the slots' knobs
// (endpoints), the slots' custom shapes' points (stored), the working parameters of Porridge's
// own kinds (no endpoints: a slot's values are swapped into them to run it), and each slot's
// knobs' values as its kind's parameters take them (Q, which the modulation matrix moves).
const M = rackKnobs;
const knobsFrom = porridgeSlot (porridgeParams.length);
const knobBase = [];
{
    let s = knobsFrom;
    for (let g = 0; g < slotCount; ++g) { knobBase.push (s); s += knobCount (g); }
}
const slotShaperIds = storedGroups.slice (1).flat();
const shaperFrom = knobsFrom + knobSpecs.length;
const workFrom = shaperFrom + slotShaperIds.length;
const qBase = workFrom + workSpecs.length;
const NUM_SLOTS = qBase + slotCount * M;
const VIRTUAL = { filter1: programSize / 4, filter2: programSize / 4 + 1 };
if (VIRTUAL.filter2 >= porridgeSlot (0)) throw new Error ("the virtual slots run into Porridge's own");

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
    const s = num (x);
    return (/[.e]/.test (s) ? s : s + ".0") + "f";
}

const defs = new Map (makeDefs().map (d => [d.id, d]));
const endpoints = [], handlers = [], slots = [], cfields = [];
const slotDefaults = new Array (NUM_SLOTS).fill (0);
let hostListed = 0;

const all = [
    ...fields.map (f => ({ ...f, slot: slotOf (f) })),
    ...porridgeParams.map ((p, i) => ({ index: fields.length + i, id: p.id, slot: porridgeSlot (i), porridge: true })),
];
// the slots' knobs (endpoints), their shapes' points (stored) and the working parameters (slots only)
const knobInfo = s => ({ hostName: s.name, min: 0, max: 1, init: 0, automatable: true });
const knobs = knobSpecs.map ((s, i) => ({ id: s.id, slot: knobsFrom + i, porridge: true, info: knobInfo (s), isInt: false }));
const slotShapers = slotShaperIds.map ((id, i) => ({ id, slot: shaperFrom + i, porridge: true, ident: false,
    info: { hostName: defs.get (id).name, min: defs.get (id).min, max: defs.get (id).max, init: defs.get (id).init, automatable: false }, isInt: false }));
const work = workSpecs.map ((s, i) => ({ id: s.id, slot: workFrom + i, porridge: true, work: true }));
const byId = new Map ([...all, ...knobs, ...slotShapers, ...work].map (f => [f.id, f]));
const slotById = id =>
{
    const f = byId.get (id);
    if (! f) throw new Error (`unknown parameter ${id}`);
    return f.slot;
};

for (const f of [...all, ...knobs, ...slotShapers, ...work])
{
    const { index, id, offset, kind, slot } = f;

    if (f.work)
    {
        slots.push (`    let ${id} = ${slot};`);
        const k = workSpecs.find (s => s.id === id).kind;
        slotDefaults[slot] = k.init ?? 0;
        continue;
    }

    const info = f.info ?? paramInfo (index);
    const isInt = f.info ? f.isInt : defs.get (id).isInt;
    // (the stored parameters have slots but no endpoints: they come in shaperIn, below)
    const endpoint = ! isStored (id);
    const ann = [`name: ${cmajString (info.hostName)}`];
    // (hosts list only automatable parameters: routing and setup stay out of their lists)
    if (info.automatable && endpoint) ++hostListed;
    else ann.push ("automatable: false");

    if (isInt)
    {
        ann.push (`min: ${info.min | 0}`, `max: ${info.max | 0}`, `init: ${Math.round (info.init)}`);
        if (info.names) ann.push (`text: ${cmajString (info.names.join ("|"))}`);
        else ann.push (`step: 1`);
        if (endpoint)
        {
            endpoints.push (`    input event int ${id} [[ ${ann.join (", ")} ]];`);
            handlers.push (`    event ${id} (int v) { paramOut <- porridge::ParamChange (${slot}, float (v)); }`);
        }
        slotDefaults[slot] = Math.round (info.init);
    }
    else
    {
        ann.push (`min: ${num (info.min)}`, `max: ${num (info.max)}`, `init: ${num (info.init)}`);
        if (info.unit) ann.push (`unit: ${cmajString (info.unit)}`);
        if (endpoint)
        {
            endpoints.push (`    input event float ${id} [[ ${ann.join (", ")} ]];`);
            handlers.push (`    event ${id} (float v) { paramOut <- porridge::ParamChange (${slot}, v); }`);
        }
        slotDefaults[slot] = info.init;
    }

    if (f.ident !== false) slots.push (`    let ${id} = ${slot};`);
    if (endpoint)
        cfields.push (f.porridge ? `    { "${id}", -1, FieldType::${isInt ? "i32" : "f32"}, ${isInt} },`
                                 : `    { "${id}", ${offset}, FieldType::${kind}, ${isInt} },`);
}

// The stored parameters (ui/StoredParams.res: the custom shapes' points) reach the DSP as one
// shaperIn event per distortion, which ParamStore passes on to their slots one by one.
const groupSize = storedGroups[0].length;
if (storedGroups.some (g => g.length !== groupSize)) throw new Error ("the stored parameters' groups differ in size");
const shaperSlots = storedGroups.flat().map (slotById);
const storedFields = storedGroups.flatMap ((g, k) => g.map ((id, i) => `    { "${id}", ${k}, ${i}, ${cf (slotDefaults[slotById (id)])} },`));

// Hosts know a parameter by its CLAP id, which dsp/param-ids.txt keeps for every endpoint there
// has been (tools/param-ids.mjs): a new parameter gets one here, and the endpoints' order and
// number don't matter to hosts.
const idsPath = join (root, "dsp", "param-ids.txt");
const clapIds = readIds (idsPath);
const newIds = assignIds (clapIds, [...all, ...knobs].filter (f => ! isStored (f.id)).map (f => f.id));
writeGenerated (idsPath, idsText (clapIds));
if (newIds.length) console.log (`new CLAP ids (dsp/param-ids.txt): ${newIds.join (", ")}`);

// A camelCase identifier from a menu label: "LFO 1 speed" -> lfo1Speed, "1 PWM rate" -> osc1PwmRate.
function labelIdent (label)
{
    const words = label.replace (/[()]/g, "").toLowerCase().split (/[^a-z0-9]+/).filter (w => w);
    const s = words.map ((w, i) => i === 0 ? w : w[0].toUpperCase() + w.slice (1)).join ("");
    return /^[0-9]/.test (s) ? "osc" + s : s;
}

const ns = (name, doc, lines) => `/// ${doc}\nnamespace porridge::${name}\n{\n${lines.join ("\n")}\n}\n`;

const targetConstants = (name, doc, labels) => ns (name, doc, labels.map ((l, i) => `    let ${labelIdent (l)} = ${i};`));

// Choice values the DSP compares against, by their menu labels (which must exist).
const choices = [
    { ns: "waveType", param: "O1_Waveform", doc: "Oscillator waveforms (O1_Waveform, O2_Waveform).",
      values: { sine: "Sine", saw: "Oat saw", pulse: "Oat pulse", triangle: "Oat triangle", user: "User",
                userPwm: "User PWM", sawHQ: "Saw", pulseHQ: "Pulse", triangleHQ: "Triangle" } },
    { ns: "oscMixMode", param: "OscMix", doc: "How the two oscillators combine (OscMix).",
      values: { normal: "normal", sync: "hardsync", fm: "FM (1 -> 2, 1 silent)", pm2to1: "PM 2 > 1",
                pmFeedback: "PM 1 feedback", ring: "ring 1 × 2", am: "AM 2 > 1" } },
    { ns: "filterType", param: "Filter", doc: "Filter types (Filter; Filter2 uses 0 for \"same as filter 1\").",
      values: { off: "off", lp1: "1P lowpass", lp2: "2P lowpass", lp4: "4P lowpass", hp1: "1P highpass", hp2: "2P highpass",
                hp4: "4P highpass", bpWide: "2P wide bandpass", bpNarrow: "2P narrow bandpass", bp4: "4P bandpass",
                notch: "2P notch", lp2Nonlinear: "nonlinear 2P lowpass", lp4Nonlinear: "nonlinear 4P lowpass",
                phaser4: "phaser, 4 stages", phaser12: "phaser, 12 stages", phaser36: "phaser, 36 stages",
                svf: "SVF LP > BP > HP", ladder: "ladder", diodeLadder: "diode ladder", sallenKey: "Sallen-Key",
                comb: "comb", formant: "formant",
                bp12: "bandpass 12 dB", bp24: "bandpass 24 dB", peak12: "peak 12 dB", peak24: "peak 24 dB",
                notch12: "notch 12 dB", notch24: "notch 24 dB", lbh24: "L/B/H 24 (morph)", lnh: "L/N/H (morph)",
                bpb: "B/P/B (morph)", npn: "N/P/N (morph)", mg6: "MG low 6", mg12: "MG low 12", mg18: "MG low 18",
                mg24: "MG low 24", mgDirty: "MG dirty", acid: "acid ladder", french: "French LP", german: "German LP",
                cleanDrive: "clean drive", pzSvf: "PZ SVF", combPlus: "comb +", combMinus: "comb −",
                flanger: "flanger", flangerPlus: "flanger +", flangerMinus: "flanger −", phaser: "phaser",
                phaserPlus: "phaser +", phaserMinus: "phaser −", formant1: "formant I", formant2: "formant II",
                formant3: "formant III", lowEq: "low EQ", bandEq: "band EQ", highEq: "high EQ", ringMod: "ring mod",
                sampleHold: "sample & hold", diffusor: "diffusor", reverb: "reverb", last: "reverb" } },
    { ns: "impulse", param: "Cv_Impulse", doc: "The convolver's impulses (Cv_Impulse).",
      values: { room: "room", hall: "hall", cathedral: "cathedral", plate: "plate", spring: "spring",
                cab1x12: "cabinet 1×12", cab4x12: "cabinet 4×12", metalTank: "metal tank", telephone: "telephone",
                swell: "swell", noiseBloom: "noise bloom", file: "file" } },
    { ns: "reverbModel", param: "Rv_Model", doc: "The algorithmic reverb's models (Rv_Model).",
      values: { hall: "hall", plate: "plate", nitrous: "nitrous", basin: "basin", vintage: "vintage" } },
    { ns: "ambienceModel", param: "Am_Model", doc: "The ambience's models (Am_Model).",
      values: { room: "room", clearCoat: "clear coat", verbTiny: "verb tiny" } },
    { ns: "bodeMode", param: "Bd_Mode", doc: "The frequency shifter's modes (Bd_Mode).",
      values: { up: "up", down: "down", stereo: "stereo (L up, R down)", ring: "ring" } },
    { ns: "satMode", param: "Sat_Mode", doc: "Where the distortion sits (Sat_Mode).",
      values: { global: "global", afterFilter: "per voice, after filter", beforeFilter: "per voice, before filter",
                both: "double (before filter and global)" } },
    { ns: "satType", param: "Sat_Type", doc: "The distortion's types (Sat_Type): Oatmeal's curves, the custom shape, then the models (tube on).",
      values: { off: "off", hardClip: "hard clip", softClip: "soft clip", sine: "sine", asymmetric: "asymmetric",
                custom: "custom shape", tube: "tube", tape: "tape", saturate: "saturate", mixerDrive: "mixer drive",
                sevenStage: "7-stage clip", multiband: "multiband", wavefold: "wavefold", bassAmp: "bass amp",
                guitarAmp: "guitar amp", bitcrush: "bitcrush", lofi: "lo-fi sampler" } },
    { ns: "polyMode", param: "PolyMode", doc: "The voice modes (PolyMode).",
      values: { mono: "Monophonic", poly: "Polyphonic", legato: "Monophonic, legato" } },
    { ns: "arpMode", param: "Arp_Mode", doc: "The arpeggiator's modes (Arp_Mode): the patterns, then the chords from chord on.",
      values: { off: "off", pattern: "pattern", globalSubseq: "pattern (global subseq)", chordPattern: "chord pattern",
                chord: "chord", transposedChords: "transposed chords" } },
    { ns: "lfoShape", param: "LFO_1_Shape", doc: "LFO 1 and 2's shapes (LFO_1_Shape, LFO_2_Shape).",
      values: { sine: "Sine", saw: "Saw", square: "Square", triangle: "Triangle", smoothRandom: "Smooth random",
                steppingRandom: "Stepping random", user: "User" } },
    { ns: "lfoSync", param: "LFO_1_Sync", doc: "Whether LFO 1 and 2 run per note or for every note (LFO_1_Sync, LFO_2_Sync).",
      values: { perNote: "per note", globalReset: "global, reset on note", globalFree: "global, free" } },
    { ns: "lfo3Mode", param: "LFO_3_Mode", doc: "Whether LFO 3 runs per voice or shared (LFO_3_Mode).",
      values: { perVoice: "per-voice", sharedReset: "shared, reset on note", sharedFree: "shared, free" } },
    { ns: "aftertouchMode", param: "AftertouchMode", doc: "Which pressure the voices read (AftertouchMode).",
      values: { ignore: "ignore all", channel: "channel", poly: "polyphonic" } },
];

function choiceConstants ({ ns: name, param, doc, values })
{
    // (choiceValue finds Porridge's own kinds' parameters in the slots)
    return ns (name, doc, Object.entries (values).map (([value, label]) => `    let ${value} = ${choiceValue (param, label)};`));
}

const fxOrders = Array.from ({ length: 24 }, (_, k) => fxOrder (k));

// The knob laws' table (porridge::mods::table): each row is a law, the internal value at knob
// positions 0..1 in TABLE - 1 steps. The modulation matrix's parameter targets and the slots'
// knobs share it; laws that are the same share a row.
const TABLE = 257;
const rows = [], rowNames = [];
const rowOf = new Map();    // row text -> row index

function rowFor (id, d)
{
    const row = Array.from ({ length: TABLE }, (_, k) => cf (d.fromNorm (k / (TABLE - 1))));
    // a pulse width (ParamDefs' isPw) is a 32-bit phase, so the top of its knob (100 %) wraps
    // to 0, as Oatmeal's does: end the table on its last step instead, or the inverse lookup
    // lands at the wrong end
    if (d.kind === "pw") row[TABLE - 1] = row[TABLE - 2];
    const text = row.join (", ");
    if (! rowOf.has (text))
    {
        rowOf.set (text, rows.length);
        rows.push (row);
        rowNames.push ([]);
    }
    rowNames[rowOf.get (text)].push (id);
    return rowOf.get (text);
}

// The rack's kinds as tables (porridge::rack), so that the synth runs every slot with one piece
// of code: each kind's index, the kind and instance a rack value runs (-1 for none: empty, one of
// Oatmeal's four, or retired), and each kind's knobs: the working parameter each one's value is
// swapped into, and its law (a table row for a float, or rounding between lo and hi for a list).
function rackKindTables ()
{
    const kindOf = rackEntries.map ((e, v) => e && v > 4 ? rackKinds.findIndex (k => k.key === e[0]) : -1);
    const instOf = rackEntries.map ((e, v) => kindOf[v] >= 0 ? e[1] - firstInstance (rackKinds[kindOf[v]]) : -1);
    const knobs = [], work = [], row = [], lo = [], hi = [];

    for (const k of rackKinds)
    {
        const list = knobsOf (k);
        if (list.length > M) throw new Error (`${k.key} has more knobs than a slot`);
        knobs.push (list.length);

        // (a lane-only kind's parameters are in the lane's slots' defs)
        const key = k.runsIn === "LaneOnly" ? "L1" : "1";

        for (let i = 0; i < M; ++i)
        {
            const id = list[i]?.[0];
            const d = id && defs.get (`${id}@${key}`);
            if (id && ! d) throw new Error (`no def for ${id}@${key}`);
            work.push (id ? slotById (id) : 0);
            row.push (d && ! d.isInt ? rowFor (id, d) : -1);
            lo.push (cf (d && d.isInt ? d.min : 0));
            hi.push (cf (d && d.isInt ? d.max : 0));
        }
    }

    return `
    /// the kinds above as tables: their indices, the kind and instance (0 ..) each rack value
    /// runs (-1: none), where each kind runs, and each kind's knobs (knobs: how many; work: the
    /// slot its value is swapped into; row: its law's row of mods::table, or -1 for a list,
    /// whose value is lo + the knob's position * (hi - lo), rounded)
${rackKinds.map ((k, i) => `    let ${k.key}Kind = ${i};`).join ("\n")}
    let numKinds = ${rackKinds.length};
    let kindOf = int[${kindOf.length}] (${kindOf.join (", ")});
    let instOf = int[${instOf.length}] (${instOf.join (", ")});
    /// whether each kind runs in the rack, and in the voice lane (PorridgeParams' runsIn)
    let inRack = bool[${rackKinds.length}] (${rackKinds.map (k => k.runsIn !== "LaneOnly").join (", ")});
    let inLane = bool[${rackKinds.length}] (${rackKinds.map (k => k.runsIn !== "Rack").join (", ")});
    /// whether a kind's working parameters are its alone (Porridge's own kinds), or one of
    /// Oatmeal's effects' (its chorus, delay, reverb, EQ and distortion)
    let own = bool[${rackKinds.length}] (${rackKinds.map (k => k.firstInRack).join (", ")});
    let knobs = int[${knobs.length}] (${knobs.join (", ")});
    let work = int[${work.length}] (${work.join (", ")});
    let row = int[${row.length}] (${row.join (", ")});
    let lo = float[${lo.length}] (${lo.join (", ")});
    let hi = float[${hi.length}] (${hi.join (", ")});`;
}

// The slots (the rack's, then the voice lane's): the parameter holding each one's value, where
// its knobs' endpoints start, how many it has, and Q, its knobs' values as its kind takes them.
function slotTables ()
{
    return `
    /// the slots, the rack's then the lane's: the parameter that says what each holds, its
    /// knobs' first endpoint slot and how many it has; q: the first of the values its knobs
    /// give its kind's parameters (slotKnobs per slot, which the modulation matrix moves)
    let numSlots = ${slotCount};
    let slotKnobs = ${M};
    let kindSlot = int[${slotCount}] (${Array.from ({ length: slotCount }, (_, g) => slotById (slotKindId (g))).join (", ")});
    let knobBase = int[${slotCount}] (${knobBase.join (", ")});
    let knobCount = int[${slotCount}] (${Array.from ({ length: slotCount }, (_, g) => knobCount (g)).join (", ")});
    let q = ${qBase};`;
}

const header = `//  Generated by tools/gen.mjs - do not edit by hand.\n\n`;

writeGenerated (join (root, "dsp", "ParamStore.cmajor"), header +
`/// Every parameter of the original, in the original order, as an endpoint named after the
/// original skin action, then Porridge's own parameters. Values are the internal values
/// stored in an Oatmeal preset. Each change is forwarded to the synth as (slot, value).
/// (Hosts know them by their ids in dsp/param-ids.txt, so the order doesn't matter to them.)
processor ParamStore
{
    output event porridge::ParamChange paramOut;

${endpoints.join ("\n")}

    /// the custom shapes' points, which are stored state rather than endpoints (ui/StoredParams.res)
    input event porridge::ShaperPoints shaperIn;

${handlers.join ("\n")}

    event shaperIn (porridge::ShaperPoints s)
    {
        if (s.which >= 0 && s.which < porridge::numShapers)
            for (wrap<${groupSize}> i)
                paramOut <- porridge::ParamChange (porridge::shaperSlots.at (s.which * ${groupSize} + int (i)), s.values[i]);
    }
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

    /// The custom shape's points of distortion \`which\` (0: Oatmeal's, then the rack's copies),
    /// as the view sends them (ui/StoredParams.res): the count less 2, then each point's in, out
    /// and bend. They are stored state, not parameter endpoints.
    struct ShaperPoints
    {
        int which;
        float[${groupSize}] values;
    }

    let numShapers = ${storedGroups.length};

    /// each distortion's points' slots, in ShaperPoints' order
    let shaperSlots = int[${shaperSlots.length}] (${shaperSlots.join (", ")});
}

/// Index of every parameter in the synth's mirror of the program struct.
namespace porridge::slot
{
${slots.join ("\n")}
}

/// The effects rack and the voice lane (ui/PorridgeParams.res): their slots, and for each kind of
/// effect how many instances the rack can run at once. Oatmeal's chorus, delay, reverb and EQ
/// are values 1..4 (fixed effects with parameters of their own); every other value is a kind and
/// an instance, run with its slot's knobs.
namespace porridge::rack
{
    let slots = int[${rackSlots}] (${Array.from ({ length: rackSlots }, (_, k) => slotById (rackId (k + 1))).join (", ")});
${rackKinds.map (k => `    let ${k.key}Count = ${instanceCount (k)};`).join ("\n")}
${slotTables()}

    /// how many values a rack slot can hold
    let numEntries = ${rackEntries.length};
${rackKindTables()}
}

${targetConstants ("xyTgt", "X/Y pad targets (XY_H_Target_n, XY_V_Target_n).", xyTargets)}
${targetConstants ("meTgt", "Mod envelope targets (M1_Target_n, M2_Target_n).", modEnvTargets)}
${targetConstants ("ccTgt", "MIDI controller targets (CCn_Target_n).", ccTargets)}
${choices.map (choiceConstants).join ("\n")}`);

mkdirSync (join (root, "tools", "test", "build"), { recursive: true });
writeGenerated (join (root, "tools", "test", "build", "fields_gen.h"), header +
`#pragma once
enum class FieldType { f32, i32, filter1, filter2, pw };
// every parameter endpoint and where the program chunk holds it (-1: Porridge's own, not in it)
struct PorridgeField { const char* id; int offset; FieldType type; bool isInt; };
static const PorridgeField porridgeFields[] =
{
${cfields.join ("\n")}
};
// the stored parameters (ui/StoredParams.res): which shaperIn event (distortion) carries each,
// where in it, and its default
struct StoredField { const char* id; int which; int index; float init; };
static const StoredField storedFields[] =
{
${storedFields.join ("\n")}
};
static const int numShapers = ${storedGroups.length}, shaperSize = ${groupSize};
static const int programSize = ${programSize};
static const int waveOffsets[4] = { ${["Wave1", "Wave2", "LfoShape1", "LfoShape2"].map (tableOffset).join (", ")} };
static const int curveOffsets[2] = { ${["VelocityCurve", "AftertouchCurve"].map (tableOffset).join (", ")} };
`);

// the test host's manifest: the patch's sources, with the test graph in place of the top level
const { source } = JSON.parse (readFileSync (join (root, "Porridge.cmajorpatch"), "utf8"));
writeGenerated (join (root, "tools", "test", "PorridgeTest.cmajorpatch"), JSON.stringify ({
    CmajorVersion: 1,
    ID: "dev.porridge.test",
    version: "1.0",
    name: "PorridgeTest",
    isInstrument: true,
    source: [...source.filter (s => s !== "dsp/Porridge.cmajor").map (s => "../../" + s), "PorridgeTest.cmajor"],
}, null, 4) + "\n");

//==============================================================================
// modulation tables

// (a retired copy's targets move nothing, like none's; a slot's knob moves what its kind has
// there, by the kind's law: the synth works its row out, porridge::rack::row)
const kinds = { Knob: 1, Pitch: 2, Volume: 3, Pan: 4, Retired: 0, Slot: 5 };
const targetKind = [], targetSlot = [], targetRow = [], targetScale = [], targetKnob = [];

ModMatrix.targets.forEach ((t, i) =>
{
    const law = t.law;
    const tag = typeof law === "string" ? law : law.TAG;
    targetKind.push (i === 0 ? 0 : kinds[tag]);
    targetScale.push (cf (tag === "Pitch" ? law._0 : 0));

    if (tag === "Knob")
    {
        const d = defs.get (law._0);
        const f = byId.get (law._0);
        if (! d || ! f) throw new Error (`unknown modulation target ${law._0}`);
        targetSlot.push (f.slot);
        // (targets with the same law share a row)
        targetRow.push (rowFor (law._0, d));
        targetKnob.push (-1);
    }
    else if (tag === "Slot")
    {
        const [g, k] = [law._0, law._1];
        if (k > knobCount (g)) throw new Error (`slot ${g} has no knob ${k}`);
        targetSlot.push (qBase + g * M + k - 1);
        targetRow.push (-1);
        targetKnob.push (g * M + k - 1);
    }
    else
    {
        targetSlot.push (-1);
        targetRow.push (-1);
        targetKnob.push (-1);
    }
});

const ident = s => s.replace (/[^A-Za-z0-9_]/g, "_");
const names = ids => ids.slice (0, 3).join (", ") + (ids.length > 3 ? ` and ${ids.length - 3} more` : "");

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
    let slotKnob = 5;

    /// each connection's parameters' slots (the later slots' come after the first ones' apart)
${[["Source", "sourceId"], ["Target", "targetId"], ["Amount", "amountId"], ["Via", "viaId"], ["Hold", "holdId"], ["Slew", "slewId"], ["Curve", "curveId"], ["Steps", "stepsId"]].map (([name, fn]) =>
    `    let conn${name} = int[numSlots] (${Array.from ({ length: ModMatrix.slots }, (_, k) => slotById (ModMatrix[fn] (k + 1))).join (", ")});`).join ("\n")}

    /// whether each source runs -1..1 (else 0..1), for a connection's steps
    let sourceBipolar = bool[numSources] (${ModMatrix.sources.map (s => String (s.bipolar)).join (", ")});

    let targetKind  = int[${targetKind.length}] (${targetKind.join (", ")});
    let targetSlot  = int[${targetSlot.length}] (${targetSlot.join (", ")});
    let targetRow   = int[${targetRow.length}] (${targetRow.join (", ")});
    let targetScale = float[${targetScale.length}] (${targetScale.join (", ")});
    /// a slot knob target's slot and knob (slot * rack::slotKnobs + knob), -1 for the others
    let targetKnob  = int[${targetKnob.length}] (${targetKnob.join (", ")});

    let table = float[${rows.length * TABLE}] (
${rows.map ((r, i) => `        ${r.join (", ")}${i + 1 < rows.length ? "," : ""}  // ${names (rowNames[i])}`).join ("\n")}
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

console.log (`generated ${endpoints.length} parameter endpoints (${hostListed} listed by hosts) (${knobs.length} of them the slots' knobs) and ${storedGroups.flat ().length} stored parameters, ${ModMatrix.targets.length} modulation targets, ${NUM_SLOTS} slots`);
