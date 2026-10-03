// Checks the menus that pick list values by sound (ValueList, FilterTypes, DistTypes,
// SpaceModels) against the values they stand for, which presets and hosts store as numbers:
//   - every value of every list parameter is offered by its menu, or shows in it while it is
//     set: the filter types the menu offers once (the same sound as another) and an effect's
//     "off" (its light); each has a name and a text for its field;
//   - the filter menus' first level has at most 12 rows;
//   - the lists keep their values: as many as before, and the names the tools and the DSP's
//     constants read (ParamDefs.choiceValue) where they were;
//   - every space model maps onto its kind's value and back, every value of the algo reverb's,
//     ambience's and convolver's lists is one of them, and what a swap carries over survives
//     the way back;
//   - every rack kind is still in an add menu entry.
//
// run: npm run res && node tools/test/pickers.mjs

import * as ParamDefs from "../../ui/ParamDefs.res.mjs";
import * as ValueList from "../../ui/ValueList.res.mjs";
import * as FilterTypes from "../../ui/FilterTypes.res.mjs";
import * as SpaceModels from "../../ui/SpaceModels.res.mjs";
import * as FxRack from "../../ui/FxRack.res.mjs";
import { checker } from "./lib.mjs";

const { check, done } = checker ();

const defs = ParamDefs.makeDefs ();
const listDefs = defs.filter (d => d.list !== undefined);

const filterLists = ["FilterType", "Filter2Type", "FxFilterType"];
// values left out of their menus on purpose, each shown while set (an effect's off, by its light)
const leftOut = {
    FilterType: [19, 22, 26, 35, 39, 42, 43],
    Filter2Type: [19, 22, 26, 35, 39, 42, 43],
    FxFilterType: [19, 22, 26, 35, 39, 42, 43],
    // (off: the effect's light)
    DistType: [0],
    ChorusMode: [0],
};
// how many values each list has (values are append only)
const counts = {
    Waveform: 9, LfoShape: 7, Lfo3Shape: 7, LfoUnit: 18, DelayUnit: 15, ArpUnit: 18, FilterType: 60, Filter2Type: 60,
    FxFilterType: 60, FilterDouble: 3, DistType: 17, DistMode: 4, VoiceMode: 3, TouchMode: 3, OscMix: 7, GlideMode: 7,
    ArpMode: 6, DelayReverse: 3, ChorusMode: 5, NoiseType: 9,
};

const seen = new Set ();
for (const d of listDefs)
{
    const names = d.names, n = names.length, list = d.list;
    seen.add (list);
    check (counts[list] === n, `${d.id}: ${n} values, not ${counts[list]}`);
    const menuAt = v => ValueList.menu (list, n, v);
    const offeredAt = v => ValueList.offered (menuAt (v));
    const usual = offeredAt (-1);
    check (usual.every (v => Number.isInteger (v) && v >= 0 && v < n), `${d.id}: offers a value it hasn't`);
    const missing = [...names.keys ()].filter (v => ! usual.includes (v));
    check (JSON.stringify (missing) === JSON.stringify (leftOut[list] ?? []), `${d.id}: leaves out ${missing}`);
    for (let v = 0; v < n; ++v)
    {
        const shows = offeredAt (v).includes (v) || (leftOut[list] ?? []).includes (v) && ! filterLists.includes (list);
        check (shows, `${d.id}: ${v} (${names[v]}) doesn't show in its menu while set`);
        const text = (d.shortNames ?? names)[v];
        check (typeof names[v] === "string" && names[v] !== "" && typeof text === "string" && text !== "",
               `${d.id}: ${v} has no name or text`);
    }
    if (filterLists.includes (list))
    {
        const rows = menuAt (0).length;
        check (rows <= 12, `${d.id}: ${rows} rows in the first level`);
        // a hidden type shows in its family while set, and the family row is the current one
        for (const v of leftOut[list])
            check (menuAt (v).some (e => e.sub && ValueList.offered (e.sub).includes (v)), `${d.id}: ${v} shows in no family`);
    }
}
check (Object.keys (counts).every (l => seen.has (l)), "a list no parameter shows: " + Object.keys (counts).filter (l => ! seen.has (l)));

// the names the tools and gen.mjs's constants go by are where they were
const named = [
    ["Filter", "SVF LP > BP > HP", 16], ["Filter", "reverb", 59], ["Filter", "MG low 24", 35], ["Filter2", "same as filter 1", 0],
    ["Ff_Type@1", "Sallen-Key", 19], ["Sat_Type", "soft clip", 2], ["Sat_Type", "custom shape", 5], ["Sat_Type", "lo-fi sampler", 16],
    ["LFO_1_Unit", "16ths", 5], ["LFO_1_Unit", "2/3 8ths", 7], ["LFO_2_Unit", "whole notes", 17], ["D_Unit", "quarter notes", 11],
    ["Arp_Unit", "32nds", 5], ["Arp_Unit", "sec", 2], ["LFO_1_Shape", "User", 6], ["O1_Waveform", "Saw", 6],
    ["O1_Waveform", "Oat saw", 1], ["GlideMode", "constant time", 0], ["GlideMode", "by interval", 1],
    ["LFO_3_Shape", "Sine", 0], ["LFO_3_Shape", "Triangle", 1], ["LFO_3_Shape", "Saw", 2], ["LFO_3_Shape", "Saw down", 3],
    ["LFO_3_Shape", "Square", 4], ["LFO_3_Shape", "Stepping random", 5], ["LFO_3_Shape", "Smooth random", 6],
];
for (const [id, name, v] of named)
    check (ParamDefs.choiceValue (id, name) === v, `${id} "${name}" is ${ParamDefs.choiceValue (id, name)}, not ${v}`);
check (FilterTypes.all.length === 60 && FilterTypes.all.every ((name, t) => FilterTypes.index (name) === t), "the filter types' names");

// the space models
{
    const models = SpaceModels.models;
    const lists = { space: ["Rv_Model", 5], ambience: ["Am_Model", 3], convolve: ["Cv_Impulse", 12] };
    for (const [kind, [id, n]] of Object.entries (lists))
        for (let v = 0; v < n; ++v)
        {
            const e = { kind, place: { TAG: "Rack", _0: 1 } };
            const get = x => x === FxRack.id (e, id) ? v : 0;
            const i = SpaceModels.current (get, e);
            const m = models[i];
            check (m !== undefined && m.kind === kind && m.param[0] === id && m.param[1] === v, `${kind} ${id} ${v} is no model`);
            check (SpaceModels.offered (e, i).some (([_, j]) => j === i), `${kind} ${v} isn't in its list while set`);
        }
    const oat = SpaceModels.current (() => 0, { kind: "reverb", place: "Fixed" });
    check (models[oat]?.kind === "reverb", "Oatmeal's reverb is no model");
    // offered: no convolver room, hall or plate; the cabinets on the convolver's list only
    const labels = kind => SpaceModels.offered ({ kind, place: { TAG: "Rack", _0: 0 } }, -1).map (([m]) => m.label).join ();
    check (labels ("space") === "hall,plate,nitrous,basin,vintage,Oatmeal,room,clear coat,tiny,spring,metal tank,cathedral,swell,noise bloom,file",
           "the reverbs' list: " + labels ("space"));
    check (labels ("convolve") === labels ("space") + ",cabinet 1×12,cabinet 4×12,telephone", "the convolver's list: " + labels ("convolve"));

    // what carries over, and back
    const there = { kind: "space", copy: 1 }, back = { kind: "reverb", copy: 1 };
    const values = { R_Dry: 0.9, R_Wet: 0.35, R_Predelay: 40, R_Length: 3.5 };
    const toAlgo = new Map (SpaceModels.carriedTo (there, SpaceModels.carriedFrom (x => values[x] ?? 0, back)));
    const again = new Map (SpaceModels.carriedTo (back, SpaceModels.carriedFrom (x => toAlgo.get (x) ?? 0, there)));
    const near = (a, b) => Math.abs (a - b) < 1e-6;
    check (near (toAlgo.get ("Rv_Predelay"), 40) && near (again.get ("R_Predelay"), 40), "the predelay doesn't carry over");
    check (near (again.get ("R_Length"), 3.5), "the decay doesn't carry over: " + again.get ("R_Length"));
    check (near (again.get ("R_Wet") / again.get ("R_Dry"), 0.35 / 0.9), "the mix doesn't carry over");
}

// every kind is still in an add menu entry
{
    const kinds = new Set (FxRack.menuGroups.flatMap (([_, entries]) => entries.flatMap (e => e.kinds)));
    check (FxRack.kinds.every (k => kinds.has (k)), "kinds no add menu offers: " + FxRack.kinds.filter (k => ! kinds.has (k)));
}

done ("ok: every list value maps to and from its menu");
