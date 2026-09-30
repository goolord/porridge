// Program/bank plumbing shared by the view and the headless worker.
// A program is kept exactly as Oatmeal stores it: a 10376-byte version-38 chunk.
// Parameter endpoints carry the same internal values the chunk holds.

import { FIELDS } from "./oatmeal/fields.js";

export const PROGRAM_SIZE = 10376;
export const NUM_PROGRAMS = 64;
export const NAME_OFFSET = 10352;
export const NAME_LENGTH = 24;

export const SHAPE_FIELDS = {
    wave1:    { offset: 32,   points: 512, index: 0 },
    wave2:    { offset: 2080, points: 512, index: 1 },
    lfo1:     { offset: 4136, points: 512, index: 2 },
    lfo2:     { offset: 6184, points: 512, index: 3 },
    velocity: { offset: 9596, points: 64,  index: 0 },
    touch:    { offset: 9852, points: 64,  index: 1 },
};

const FILTER_OFFSET = 8428;

function view (bytes) { return new DataView (bytes.buffer, bytes.byteOffset, bytes.byteLength); }

export function readField (bytes, field)
{
    const [, , , off, type] = field;
    const dv = view (bytes);
    switch (type)
    {
        case "f32":     return dv.getFloat32 (off, true);
        case "i32":     return dv.getInt32 (off, true);
        case "filter1": return dv.getInt32 (FILTER_OFFSET, true) & 0xffff;
        case "filter2": return (dv.getInt32 (FILTER_OFFSET, true) >>> 16) & 0xffff;
        case "pw":      return dv.getUint32 (off, true) / 4294967296;
    }
    return 0;
}

export function writeField (bytes, field, x)
{
    const [, , , off, type] = field;
    const dv = view (bytes);
    switch (type)
    {
        case "f32": dv.setFloat32 (off, x, true); break;
        case "i32": dv.setInt32 (off, Math.round (x), true); break;
        case "filter1":
        {
            const v = dv.getInt32 (FILTER_OFFSET, true);
            dv.setInt32 (FILTER_OFFSET, (v & ~0xffff) | (Math.round (x) & 0xffff), true);
            break;
        }
        case "filter2":
        {
            const v = dv.getInt32 (FILTER_OFFSET, true);
            dv.setInt32 (FILTER_OFFSET, (v & 0xffff) | ((Math.round (x) & 0xffff) << 16), true);
            break;
        }
        case "pw":
        {
            let u = Math.round (x * 4294967296);
            u = ((u % 4294967296) + 4294967296) % 4294967296;
            dv.setUint32 (off, u, true);
            break;
        }
    }
}

export function programValues (bytes)
{
    const m = new Map();
    for (const f of FIELDS)
        m.set (f[1], readField (bytes, f));
    return m;
}

export function writeValues (bytes, values)
{
    for (const f of FIELDS)
        if (values.has (f[1]))
            writeField (bytes, f, values.get (f[1]));
}

export function readShape (bytes, key)
{
    const s = SHAPE_FIELDS[key];
    const dv = view (bytes);
    const a = new Float32Array (s.points);
    for (let i = 0; i < s.points; ++i) a[i] = dv.getFloat32 (s.offset + 4 * i, true);
    return a;
}

export function writeShape (bytes, key, data)
{
    const s = SHAPE_FIELDS[key];
    const dv = view (bytes);
    for (let i = 0; i < s.points; ++i) dv.setFloat32 (s.offset + 4 * i, data[i] ?? 0, true);
}

export function programShapes (bytes)
{
    const r = {};
    for (const k of Object.keys (SHAPE_FIELDS)) r[k] = readShape (bytes, k);
    return r;
}

export function programName (bytes)
{
    let s = "";
    for (let i = 0; i < NAME_LENGTH; ++i)
    {
        const c = bytes[NAME_OFFSET + i];
        if (! c) break;
        s += String.fromCharCode (c);
    }
    return s;
}

export function setProgramName (bytes, name)
{
    for (let i = 0; i < NAME_LENGTH; ++i)
        bytes[NAME_OFFSET + i] = i < name.length && i < NAME_LENGTH - 1 ? (name.charCodeAt (i) & 0xff) : 0;
}

//==============================================================================
// Sending to the patch

export function sendShape (pc, key, data)
{
    const s = SHAPE_FIELDS[key];
    const payload = { which: s.index, data: Array.from (data) };
    pc.sendEventOrValue (s.points === 512 ? "shapeIn" : "curveIn", payload, -1, 1000);
}

export function sendShapes (pc, shapes)
{
    for (const k of Object.keys (SHAPE_FIELDS))
        if (shapes[k]) sendShape (pc, k, shapes[k]);
}

export function sendValues (pc, values)
{
    for (const [id, x] of values)
        pc.sendEventOrValue (id, x, -1, 1000);
}

//==============================================================================
// State encoding (base64 without relying on btoa/atob, which the worker may not have)

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64R = (() => { const r = new Int16Array (128).fill (-1); for (let i = 0; i < 64; ++i) r[B64.charCodeAt (i)] = i; return r; })();

export function toBase64 (bytes)
{
    let out = "";
    const n = bytes.length;
    const parts = [];
    for (let i = 0; i < n; i += 3)
    {
        const a = bytes[i], b = i + 1 < n ? bytes[i + 1] : 0, c = i + 2 < n ? bytes[i + 2] : 0;
        const t = (a << 16) | (b << 8) | c;
        out += B64[(t >> 18) & 63] + B64[(t >> 12) & 63] + (i + 1 < n ? B64[(t >> 6) & 63] : "=") + (i + 2 < n ? B64[t & 63] : "=");
        if (out.length > 65536) { parts.push (out); out = ""; }
    }
    parts.push (out);
    return parts.join ("");
}

export function fromBase64 (s)
{
    const clean = s.replace (/[^A-Za-z0-9+/]/g, "");
    const n = Math.floor (clean.length * 3 / 4);
    const out = new Uint8Array (n);
    let o = 0;
    for (let i = 0; i < clean.length; i += 4)
    {
        const a = B64R[clean.charCodeAt (i)], b = B64R[clean.charCodeAt (i + 1)];
        const c = i + 2 < clean.length ? B64R[clean.charCodeAt (i + 2)] : 0;
        const d = i + 3 < clean.length ? B64R[clean.charCodeAt (i + 3)] : 0;
        const t = (a << 18) | (b << 12) | (c << 6) | d;
        if (o < n) out[o++] = (t >> 16) & 255;
        if (o < n) out[o++] = (t >> 8) & 255;
        if (o < n) out[o++] = t & 255;
    }
    return out;
}

export function encodeBank (programs)
{
    const all = new Uint8Array (NUM_PROGRAMS * PROGRAM_SIZE);
    programs.forEach ((p, i) => all.set (p, i * PROGRAM_SIZE));
    return toBase64 (all);
}

export function decodeBank (s)
{
    const all = fromBase64 (s);
    const programs = [];
    for (let i = 0; i < NUM_PROGRAMS; ++i)
        programs.push (all.slice (i * PROGRAM_SIZE, (i + 1) * PROGRAM_SIZE));
    return programs;
}

export function encodeShapes (shapes)
{
    // exact: the float32 bytes of every shape, in SHAPE_FIELDS order
    const keys = Object.keys (SHAPE_FIELDS);
    const total = keys.reduce ((n, k) => n + SHAPE_FIELDS[k].points, 0);
    const f = new Float32Array (total);
    let o = 0;
    for (const k of keys) { const src = shapes[k]; for (let i = 0; i < SHAPE_FIELDS[k].points; ++i) f[o++] = src?.[i] ?? 0; }
    return toBase64 (new Uint8Array (f.buffer));
}

export function decodeShapes (s)
{
    if (typeof s !== "string") return null;
    const bytes = fromBase64 (s);
    const keys = Object.keys (SHAPE_FIELDS);
    const total = keys.reduce ((n, k) => n + SHAPE_FIELDS[k].points, 0);
    if (bytes.length < total * 4) return null;
    const f = new Float32Array (bytes.buffer.slice (bytes.byteOffset, bytes.byteOffset + total * 4));
    const r = {};
    let o = 0;
    for (const k of keys) { r[k] = f.slice (o, o + SHAPE_FIELDS[k].points); o += SHAPE_FIELDS[k].points; }
    return r;
}
