// The rack's slots in the CLAP plugin, through the minimal host tools/test/claphost.cpp (Windows;
// build it as its header says):
//
//   node tools/test/clap-slots.mjs <claphost.exe> <Porridge.clap>
//
// - a slot's knobs are named after the kind it holds, with its value texts, and hidden while
//   it holds nothing (or where its kind has no parameter); a state that changes what a slot
//   holds makes the plugin ask the host to rescan the parameters' info and texts;
// - a session from before the slots (its copies' parameters, which the plugin no longer has,
//   and its connections to them) loads into the slots: the worker moves each copy's values onto
//   its slot's knobs and its connections onto the slot's targets, and the stored "params" keeps
//   no copies' values; a state that has "params" already gets the removed parameters' values
//   merged into it.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { root } from "./lib.mjs";
import { readIds } from "../param-ids.mjs";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import * as ModMatrix from "../../ui/ModMatrix.res.mjs";

const [hostExe, plugin] = process.argv.slice (2);

if (! plugin)
{
    console.log ("usage: node tools/test/clap-slots.mjs <claphost.exe> <Porridge.clap>");
    process.exit (1);
}

let failures = 0;
const check = (ok, s) => { console.log ((ok ? "ok   " : "FAIL ") + s); if (! ok) ++failures; };
const run = (...commands) => execFileSync (hostExe, [plugin, "wait", "1500", ...commands], { encoding: "utf8", maxBuffer: 1 << 26 });
const parseList = text => new Map (text.split (/\r?\n/).filter (l => /^\d+\t/.test (l)).map (l =>
{
    const [id, name, , , , , value, flags] = l.split ("\t");
    return [Number (id), { name, value: Number (value), hidden: (Number (flags) & 4) !== 0 }];
}));
const ids = readIds (join (root, "dsp", "param-ids.txt"));
const dir = mkdtempSync (join (tmpdir (), "porridge-clap-slots-"));
const state = (parameters, values = {}) =>
{
    const file = join (dir, `state${Math.random ().toString (36).slice (2)}.json`);
    writeFileSync (file, JSON.stringify ({ parameters: Object.entries (parameters).map (([name, value]) => ({ name, value })), values }));
    return file;
};
const knob = (g, i) => ids.get (PorridgeParams.knobId (g, i));

// an empty rack: the knobs are hidden
{
    const list = parseList (run ("list"));
    const k = list.get (knob (2, 15));
    check (k?.name === "FX 3 knob 15" && k.hidden, `an empty slot's knob: "${k?.name}", hidden ${k?.hidden}`);
}

// a delay in slot 3: its knobs named and worded after it, and the host asked to rescan
{
    const file = state ({ FX_Rack_3: PorridgeParams.entryValue ("delay", 2), FX3_15: 0.5 });
    const out = run ("load", file, "wait", "500", "list", "text", String (knob (2, 15)), "0.5", "text", String (knob (2, 2)), "0.07142857");
    const list = parseList (out);
    const wet = list.get (knob (2, 15));
    check (/^rescan 6$/m.test (out), `the state asks the host to rescan the parameters' info and texts (${out.match (/^rescan \d+$/m)?.[0]})`);
    check (wet?.name === "FX 3 delay wet out" && ! wet.hidden && wet.value === 0.5, `slot 3's knob 15: "${wet?.name}" = ${wet?.value}`);
    check (list.get (knob (2, 16))?.hidden === true, "a knob the delay doesn't use stays hidden");
    const texts = [...out.matchAll (/^text \d+ (.*)$/gm)].map (m => m[1]);
    check (/dB$/.test (texts[0]) && texts[1] === "10 ms", `its texts: ${texts.join (", ")}`);
}

// a session from before the slots: flanger copy 2 in slot 3, its rate, switch and a connection
// to its mix; and a shape already in the stored "params"
{
    const flMix = PorridgeParams.knobIndex (PorridgeParams.rackKinds.find (k => k.key === "flanger"), "Fl_Mix") + 1;
    const file = state ({
        FX_Rack_3: PorridgeParams.entryValue ("flanger", 2), Fl2_On: 1, Fl2_Rate: 0.7,
        Mod1_Source: ModMatrix.sourceIndex ("lfo1"), Mod1_Target: ModMatrix.targetIndex ("Fl2_Mix"), Mod1_Amount: 0.5,
    }, { params: JSON.stringify ({ Sat_Y3: 0.25 }) });
    const saved = join (dir, "saved.json");
    const out = run ("load", file, "wait", "3000", "list", "save", saved);
    const list = parseList (out);
    check (list.get (knob (2, 1))?.value === 1 && Math.abs (list.get (knob (2, 2))?.value - 0.7) < 1e-6,
           `its values on slot 3's knobs: on ${list.get (knob (2, 1))?.value}, rate ${list.get (knob (2, 2))?.value}`);
    check (list.get (knob (2, 2))?.name === "FX 3 flanger rate", `named "${list.get (knob (2, 2))?.name}"`);
    const s = JSON.parse (readFileSync (saved, "utf8"));
    const p = Object.fromEntries (s.parameters.map (x => [x.name, x.value]));
    check (p.Mod1_Target === ModMatrix.slotTarget (2, flMix) && p.Mod1_Amount === 0.5,
           `its connection moves slot 3's mix (target ${p.Mod1_Target}, want ${ModMatrix.slotTarget (2, flMix)})`);
    const kept = JSON.parse (s.values?.params ?? "{}");
    check (kept.Sat_Y3 === 0.25 && ! Object.keys (kept).some (k => PorridgeParams.isLegacyId (k)),
           `the stored "params" keeps the shape, and no copy's values (${s.values?.params})`);
}

console.log (failures ? `${failures} failures` : "slots ok");
process.exit (failures ? 1 : 0);
