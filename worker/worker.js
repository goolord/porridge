// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes and response
// curves live in the patch's stored state and must be pushed into the DSP here.
// On a fresh instance it installs the factory bank and loads its first program, like
// Oatmeal does when it starts.

import * as fmt from "../ui/oatmeal/oatmeal-format.js";
import { encodeBank, decodeShapes, encodeShapes, programValues, programShapes, sendShapes, sendValues } from "../ui/bank.js";

export default function runWorker (patchConnection)
{
    const pc = patchConnection;
    const seen = new Map();
    let settled = false;

    const onState = ev =>
    {
        if (ev.key === "shapes")
        {
            const s = decodeShapes (ev.value);
            if (s) sendShapes (pc, s);
        }
        if (! settled) seen.set (ev.key, ev.value);
    };

    pc.addStoredStateValueListener (onState);
    pc.requestStoredStateValue ("bank");
    pc.requestStoredStateValue ("shapes");

    // Give the host a moment to answer; if there is no bank in the session this is a
    // new instance.
    setTimeout (async () =>
    {
        settled = true;
        const bank = seen.get ("bank");
        if (typeof bank === "string" && bank.length > 1000)
            return;

        let programs = null;
        try
        {
            const bytes = await readBytes (pc, "presets/oatmealprs.dat");
            if (bytes) programs = fmt.parseFile (bytes, { filename: "oatmealprs.dat" }).programs.map (p => p.bytes);
        }
        catch (e)
        {
            console.log ("Porridge: factory bank not available: " + e);
        }

        if (! programs || programs.length === 0)
            programs = [fmt.makeDefaultProgram ("Init")];

        const all = [];
        for (let i = 0; i < 64; ++i)
            all.push (programs[i] ?? fmt.makeDefaultProgram ("Init " + i));

        const first = all[0];
        sendValues (pc, programValues (first));
        const shapes = programShapes (first);
        sendShapes (pc, shapes);
        pc.sendStoredStateValue ("shapes", encodeShapes (shapes));
        pc.sendStoredStateValue ("program", 0);
        pc.sendStoredStateValue ("bank", encodeBank (all));
    }, 400);
}

// readResource returns different things depending on the runtime: the native worker gives
// an array of (signed) byte values, or a string when the file happens to be valid UTF-8; the
// WebAudio runtime gives a fetch Response.
async function readBytes (pc, path)
{
    for (const p of [path, "/" + path])
    {
        try
        {
            const bytes = await toBytes (await pc.readResource (p));
            if (bytes && bytes.length > 0) return bytes;
        }
        catch (e) {}
    }
    return null;
}

async function toBytes (data)
{
    if (data && typeof data.arrayBuffer === "function")
    {
        if (data.ok === false) return null;
        data = await data.arrayBuffer();
    }
    if (data instanceof ArrayBuffer) return new Uint8Array (data);
    if (ArrayBuffer.isView (data)) return new Uint8Array (data.buffer, data.byteOffset, data.byteLength);
    if (Array.isArray (data)) return Uint8Array.from (data);     // wraps negative values to 0..255
    if (typeof data === "string") return utf8 (data);
    return null;
}

function utf8 (text)
{
    const out = [];
    for (const ch of text)
    {
        const c = ch.codePointAt (0);
        if (c < 0x80) out.push (c);
        else if (c < 0x800) out.push (0xc0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push (0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push (0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return Uint8Array.from (out);
}
