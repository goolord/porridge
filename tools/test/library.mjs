// Checks the preset browser's searching (ui/Library.res) on the bundled banks:
//   - query parsing: words, field filters, quotes;
//   - matching by name, tag, category, author, description and source;
//   - facets: categories (any), tags (all), authors (any), and their counts;
//   - ranking: names that start with the search come first;
//   - empty "Init NN" slots are left out, except for the bank's own when asked.
//
// run: npm run res && node tools/test/library.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as Preset from "../../ui/Preset.res.mjs";
import * as Library from "../../ui/Library.res.mjs";

const root = join (dirname (fileURLToPath (import.meta.url)), "..", "..");
let failures = 0;
const check = (ok, msg) => { if (! ok) { console.log ("FAIL " + msg); ++failures; } };
const same = (a, b) => JSON.stringify (a) === JSON.stringify (b);

const read = path => {
    const r = Preset.parseFile (new Uint8Array (readFileSync (join (root, path))));
    if (r.TAG !== "Ok") throw new Error (path + " didn't parse");
    return r._0.presets;
};
const vanilla = Library.makeSource ("vanilla", "Vanilla", "Bundled", read ("presets/vanilla.porridge"));
const oatmeal = Library.makeSource ("oatmeal", "Oatmeal factory", "Bundled", read ("presets/oatmealprs.dat"));
const bank = Library.makeSource ("bank", "This bank", "Bank", read ("presets/oatmealprs.dat"));
const sources = [bank, vanilla, oatmeal];
const all = Library.entries (sources, undefined);

const names = (text, filters = Library.noFilters) =>
    Library.search (all, Library.parse (text), filters).map (e => e.preset.meta.name);

// parsing
{
    const q = Library.parse (`Warm tag:"per-voice pan" CAT:pad author:Porridge name:oat 12:00`);
    check (same (q.words, ["warm", "12:00"]), "words " + JSON.stringify (q.words));
    check (same (q.tags, ["per-voice pan"]), "tags " + JSON.stringify (q.tags));
    check (same (q.categories, ["pad"]), "categories");
    check (same (q.authors, ["porridge"]), "authors");
    check (same (q.names, ["oat"]), "names");
    check (Library.isEmptyQuery (Library.parse ("  tag:  ")), "empty filters are ignored");
}

// empty slots
{
    check (! all.some (e => /^Init \d+$/.test (e.preset.meta.name)), "Init slots listed");
    const withSlots = Library.entries (sources, true);
    check (withSlots.filter (e => e.source === bank).length === 64, "the bank's own slots, with emptySlots");
    check (withSlots.filter (e => e.source === oatmeal).length === 17, "other sources keep leaving out Init slots");
}

// matching
{
    check (names ("").length === all.length, "an empty search finds everything");
    check (names ("felt")[0] === "Felt Piano", "name: " + names ("felt")[0]);
    check (names ("tag:microtuning").join () === "Just Bells", "tag filter");
    check (names ("cat:bass").length === 12, "category filter: " + names ("cat:bass").length);
    check (names ("author:porridge").length === vanilla.presets.length, "author filter");
    check (names ("tremolo").includes ("Spring Twang"), "description words match");
    check (names ("oatmeal factory").length === 17, "source names match: " + names ("oatmeal factory").length);
    check (names ("name:bassmeh").length === 2, "the bank and the bundled copy");
    check (names ("pan wide").every (n => names ("pan").includes (n)), "every word must match");
    check (names ("zzzz").length === 0, "nothing matches nonsense");
    check (names ("FUZZ")[0] === "Fuzz Lead", "case doesn't matter");
}

// ranking: a name starting with the word, then a word in the name, then the rest
{
    const r = names ("pan");
    check (r[0] === "S&H Panner", "ranking: " + r.slice (0, 3).join (", "));
    const bells = names ("bells");
    check (bells.slice (0, 2).every (n => n.endsWith ("Bells")), "ranking by word: " + bells.join (", "));
}

// facets
{
    const f = { ...Library.noFilters, categories: ["pad", "bass"] };
    check (names ("", f).length === names ("cat:pad").length + names ("cat:bass").length, "categories are any-of");
    const t = { ...Library.noFilters, tags: ["per-voice pan", "per-voice drive"] };
    const both = names ("", t);
    check (both.length > 0 && both.every (n => names ('tag:"per-voice pan"').includes (n) && names ('tag:"per-voice drive"').includes (n)), "tags are all-of");
    check (names ("", { ...Library.noFilters, source: "vanilla" }).length === 64, "source filter");
    const toggled = Library.toggleFacet (Library.toggleFacet (Library.noFilters, "Tag", "x"), "Tag", "x");
    check (toggled.tags.length === 0, "toggling twice removes a facet value");

    // counts ignore the facet's own picks, so the other values stay pickable
    const counts = Library.facetCounts (all, Library.parse (""), { ...Library.noFilters, categories: ["pad"] }, "Category");
    const pad = counts.find (([key]) => key === "pad"), bass = counts.find (([key]) => key === "bass");
    check (pad && pad[2] === 12 && bass && bass[2] === 12, "category counts: " + JSON.stringify (counts.slice (0, 3)));
    const tagCounts = Library.facetCounts (all, Library.parse ("cat:pad"), Library.noFilters, "Tag");
    check (["per-voice drive", "per-voice pan", "evolving"].includes (tagCounts[0][0]), "tag counts follow the search: " + tagCounts[0][0]);
    const picked = Library.facetCounts (all, Library.parse ("zzzz"), { ...Library.noFilters, tags: ["wide"] }, "Tag");
    check (picked.some (([key, , n]) => key === "wide" && n === 0), "picked values stay listed");
}

console.log (failures === 0 ? `ok: library search over ${all.length} presets` : `${failures} failures`);
process.exit (failures === 0 ? 0 : 1);
