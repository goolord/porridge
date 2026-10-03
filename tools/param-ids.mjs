// The CLAP parameter ids (dsp/param-ids.txt): every parameter there has ever been, by its
// endpoint name, with the id hosts know it by. Hosts keep automation and MIDI links by id, so an
// id never changes and is never given to another parameter: the file only grows.
//
// The parameters that existed in October 2026 have the endpoint handles they had then (hosts
// knew them by those, when the CLAP wrapper used the handle as the id). A new parameter's id is
// a hash of its name (from 65536 up, in 31 bits), so that branches adding parameters
// independently give them different ids without knowing of each other: their lines merge as a
// union (.gitattributes), and gen.mjs puts the file back in order. A file left with conflict
// markers reads as the union of both sides too, so rerunning gen.mjs resolves it.
//
// tools/gen.mjs keeps the file (adding the parameters it lacks); tools/clap-patch.mjs gives the
// CLAP wrapper the table.

import { readFileSync, existsSync } from "node:fs";

const header = `# The CLAP id of every parameter endpoint there has been: "<id> <endpoint name>", one per line.
# Kept by tools/gen.mjs, which adds new parameters; never change or remove a line (hosts save
# automation by these ids). See tools/param-ids.mjs.
`;

// The ids in a registry file: Map name -> id. Comments, blank lines and conflict markers are
// skipped, so a conflicted file reads as both sides' lines.
export function readIds (path)
{
    const ids = new Map();
    if (! existsSync (path)) return ids;

    const byId = new Map();

    for (const line of readFileSync (path, "utf8").split (/\r?\n/))
    {
        const m = /^(\d+) (\S+)\s*$/.exec (line);
        if (! m) continue;

        const id = Number (m[1]), name = m[2];
        const had = ids.get (name);

        if (had !== undefined && had !== id)
            throw new Error (`${path}: ${name} has two ids, ${had} and ${id}; keep the one hosts have seen (the one on main)`);

        if (byId.has (id) && byId.get (id) !== name)
            throw new Error (`${path}: id ${id} is both ${byId.get (id)} and ${name}; give the newer parameter a fresh id (remove its line and rerun tools/gen.mjs)`);

        ids.set (name, id);
        byId.set (id, name);
    }

    return ids;
}

// FNV-1a, 32 bits
function hash (s)
{
    let h = 0x811c9dc5;

    for (let i = 0; i < s.length; ++i)
    {
        h ^= s.charCodeAt (i);
        h = Math.imul (h, 0x01000193) >>> 0;
    }

    return h;
}

const firstHashed = 0x10000;

// A fresh id for a parameter: from its name's hash, skipping ids already given.
function freshId (name, taken)
{
    for (let salt = 0; ; ++salt)
    {
        const id = firstHashed + hash (salt ? `${name}#${salt}` : name) % (0x7fffffff - firstHashed);
        if (! taken.has (id)) return id;
    }
}

// Gives every name an id (adding to `ids`); the new names.
export function assignIds (ids, names)
{
    const taken = new Set (ids.values());
    const added = [];

    for (const name of names)
    {
        if (ids.has (name)) continue;

        const id = freshId (name, taken);
        ids.set (name, id);
        taken.add (id);
        added.push (name);
    }

    return added;
}

// The registry file's text, in id order.
export const idsText = ids =>
    header + [...ids].sort ((a, b) => a[1] - b[1]).map (([name, id]) => `${id} ${name}\n`).join ("");
