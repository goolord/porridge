// Checks that a build of the CLAP plugin keeps the parameter ids of an earlier build, through the
// minimal host tools/test/claphost.cpp (Windows; build it as its header says):
//
//   node tools/test/clap-ids.mjs <claphost.exe> <earlier Porridge.clap> <this Porridge.clap>
//
// - every parameter the earlier build lists is listed again under the same id, with the same
//   name, range and default (or is gone, where this tree's dsp/param-ids.txt says it was
//   removed: it has no endpoint), and no new parameter takes an earlier id;
// - every listed id is the one dsp/param-ids.txt gives the endpoint;
// - a state the earlier build saved, with values set through host events by id, loads into this
//   build with the same value under every id both list, and its "params" stored value keeps the
//   values of parameters that are stored state now (ui/StoredParams.res).

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { root } from "./lib.mjs";
import { readIds } from "../param-ids.mjs";

const [hostExe, earlier, current] = process.argv.slice (2);

if (! current)
{
    console.log ("usage: node tools/test/clap-ids.mjs <claphost.exe> <earlier Porridge.clap> <this Porridge.clap>");
    process.exit (1);
}

let failures = 0;
const fail = s => { console.log ("FAIL " + s); ++failures; };

const run = (plugin, ...commands) => execFileSync (hostExe, [plugin, "wait", "1500", ...commands], { encoding: "utf8", maxBuffer: 1 << 26 });

const parseList = text => new Map (text.split (/\r?\n/).filter (l => /^\d+\t/.test (l)).map (l =>
{
    const [id, name, module, min, max, init, value] = l.split ("\t");
    return [Number (id), { name, module, min: Number (min), max: Number (max), init: Number (init), value: Number (value) }];
}));

const dir = mkdtempSync (join (tmpdir (), "porridge-clap-ids-"));
const before = parseList (run (earlier, "list"));
const after = parseList (run (current, "list"));
console.log (`${before.size} parameters listed before, ${after.size} now`);

// the ids
const registry = readIds (join (root, "dsp", "param-ids.txt"));
const nameOfId = new Map ([...registry].map (([name, id]) => [id, name]));
const store = readFileSync (join (root, "dsp", "ParamStore.cmajor"), "utf8");
const endpoints = new Set ([...store.matchAll (/^ {4}input event (?:int|float) (\w+) \[\[/gm)].map (m => m[1]));
let removed = 0;

for (const [id, p] of before)
{
    const q = after.get (id);

    if (! q)
    {
        const name = nameOfId.get (id);
        if (name && ! endpoints.has (name)) ++removed;
        else fail (`${id} (${p.name}) is no longer listed`);
        continue;
    }

    for (const key of ["name", "min", "max", "init"])
        if (p[key] !== q[key]) fail (`${id}: its ${key} was ${p[key]}, now ${q[key]}`);
}

for (const id of after.keys())
{
    const name = nameOfId.get (id);
    if (! name) fail (`${id} (${after.get (id).name}) isn't in dsp/param-ids.txt`);
    else if (! endpoints.has (name)) fail (`${id} is listed but dsp/param-ids.txt gives it to ${name}, which isn't an endpoint`);
}

console.log (`${removed} earlier parameters removed, as dsp/param-ids.txt says`);

// a state from the earlier build: values set by id, then saved
const ids = [...before.keys()].filter (id => after.has (id));
const picks = [ids[0], ids[5], ids[Math.floor (ids.length / 2)], ids.at (-1)];
const sets = picks.flatMap (id =>
{
    const p = before.get (id);
    const v = p.min + (p.max - p.min) * 0.75;
    return ["set", String (id), String (Number.isInteger (p.min) && Number.isInteger (p.max) && p.max - p.min < 100 ? Math.round (v) : v)];
});

const stateFile = join (dir, "earlier.json");
const earlierValues = parseList (run (earlier, ...sets, "list", "save", stateFile));

for (const id of picks)
    if (earlierValues.get (id).value === before.get (id).value) fail (`setting ${id} (${before.get (id).name}) by id did nothing in the earlier build`);

// (parameters that are stored state now, as the earlier build saved them)
const state = JSON.parse (readFileSync (stateFile, "utf8"));
const storedNow = [...registry.keys()].filter (name => ! endpoints.has (name) && /^Sat\d?_(X|Y|C)\d+$/.test (name));
const storedSet = storedNow.length ? { name: storedNow[0], value: 0.25 } : null;

if (storedSet)
{
    state.parameters.push (storedSet);
    writeFileSync (stateFile, JSON.stringify (state));
}

const savedNow = join (dir, "now.json");
const loaded = parseList (run (current, "load", stateFile, "wait", "500", "list", "save", savedNow));
let compared = 0;

for (const [id, p] of earlierValues)
{
    const q = loaded.get (id);
    if (! q) continue;
    ++compared;
    if (Math.fround (p.value) !== Math.fround (q.value)) fail (`${id} (${p.name}) was ${p.value} in the earlier build's state, loads as ${q.value}`);
}

console.log (`${compared} values compared after loading the earlier build's state`);

if (storedSet)
{
    const saved = JSON.parse (readFileSync (savedNow, "utf8"));
    const kept = JSON.parse (saved.values?.params ?? "{}");
    if (kept[storedSet.name] !== storedSet.value) fail (`${storedSet.name} wasn't kept in the stored value "params" (${saved.values?.params})`);
    else console.log (`${storedSet.name} kept in the stored value "params"`);
}

console.log (failures ? `${failures} failures` : "all ids kept");
process.exit (failures ? 1 : 0);
