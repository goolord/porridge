// Small read-only plots drawn in the signal ink. They carry information (envelope
// shape, current waveform, LFO shape), so they earn their space.

import { place } from "./controls.js";

const SVGNS = "http://www.w3.org/2000/svg";

export function svg (parent, box)
{
    const s = document.createElementNS (SVGNS, "svg");
    s.setAttribute ("class", "plot");
    s.setAttribute ("width", box.w);
    s.setAttribute ("height", box.h);
    s.setAttribute ("viewBox", `0 0 ${box.w} ${box.h}`);
    place (s, box.x, box.y, box.w, box.h);
    parent.appendChild (s);
    return s;
}

export function svgEl (parent, tag, attrs)
{
    const e = document.createElementNS (SVGNS, tag);
    for (const [k, v] of Object.entries (attrs ?? {})) e.setAttribute (k, v);
    parent.appendChild (e);
    return e;
}

function pathFrom (pts)
{
    return pts.map ((p, i) => (i ? "L" : "M") + p[0].toFixed (1) + " " + p[1].toFixed (1)).join ("");
}

// Envelope: attack, hold, decay 1 to breakpoint, decay 2 to sustain, (sustain), release.
// Time axis is compressed (sqrt) so that 1 ms and 10 s segments are both readable.
export class EnvelopePlot
{
    constructor (ctx, parent, prefix, box)
    {
        this.ctx = ctx; this.prefix = prefix; this.box = box;
        this.s = svg (parent, box);
        svgEl (this.s, "rect", { class: "bg", x: 0.5, y: 0.5, width: box.w - 1, height: box.h - 1 });
        this.fill = svgEl (this.s, "path", { class: "fill" });
        this.curve = svgEl (this.s, "path", { class: "curve" });
        for (const k of ["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release"])
            ctx.model.listen (prefix + k, () => this.draw());
        this.draw();
    }

    draw()
    {
        const m = this.ctx.model, p = this.prefix;
        const get = k => m.get (p + k) ?? 0;
        const tA = get ("Attack"), tH = get ("Hold"), tD1 = get ("Decay1"), bp = get ("Breakpoint");
        const tD2 = get ("Decay2"), sus = get ("Sustain"), tR = get ("Release");
        const skip1 = bp >= 1;

        const seg = t => Math.sqrt (Math.max (0, t) / 1000);          // compressed seconds
        const hold = 0.35;                                               // visual sustain width
        const parts = [seg (tA), seg (tH), skip1 ? 0 : seg (tD1), seg (tD2), hold, seg (tR)];
        const total = parts.reduce ((a, b) => a + b, 0) || 1;
        const W = this.box.w - 4, H = this.box.h - 5, x0 = 2, y0 = 2;
        const X = t => x0 + (t / total) * W;
        const Y = a => y0 + (1 - Math.sqrt (Math.max (0, Math.min (1, a)))) * H;   // sqrt amplitude reads like loudness

        let t = 0;
        const pts = [[X (0), Y (0)]];
        const curveTo = (dt, from, to, n = 16) =>
        {
            for (let k = 1; k <= n; ++k)
            {
                const f = k / n;
                const a = from + (to - from) * (1 - Math.pow (1 - f, 3));
                pts.push ([X (t + dt * f), Y (a)]);
            }
            t += dt;
        };

        t += parts[0]; pts.push ([X (t), Y (1)]);
        t += parts[1]; pts.push ([X (t), Y (1)]);
        let level = 1;
        if (! skip1) { curveTo (parts[2], 1, bp); level = bp; }
        curveTo (parts[3], level, sus);
        t += parts[4]; pts.push ([X (t), Y (sus)]);
        curveTo (parts[5], sus, 0);

        const d = pathFrom (pts);
        this.curve.setAttribute ("d", d);
        this.fill.setAttribute ("d", d + `L${X (t).toFixed (1)} ${Y (0)}L${X (0)} ${Y (0)}Z`);
    }
}

// Pitch envelope in semitones against the same compressed time axis. The attack is
// linear in frequency ratio (so it bends when drawn in semitones), the decay is linear in
// semitones, and the release glides at its st/sec rate; one second of it is shown.
export class PitchEnvelopePlot
{
    constructor (ctx, parent, box)
    {
        this.ctx = ctx; this.box = box;
        this.s = svg (parent, box);
        svgEl (this.s, "rect", { class: "bg", x: 0.5, y: 0.5, width: box.w - 1, height: box.h - 1 });
        this.zero = svgEl (this.s, "line", { class: "axis", x1: 2, x2: box.w - 2 });
        this.curve = svgEl (this.s, "path", { class: "curve" });
        for (const k of ["On", "Start", "Attack", "Peak", "Decay", "Sustain", "Release"])
            ctx.model.listen ("PEnv_" + k, () => this.draw());
        ctx.model.listen ("Tune_Octave", () => this.draw());
        this.draw();
    }

    draw()
    {
        const get = (k, d = 0) => this.ctx.model.get (k) ?? d;
        const oct = Math.log2 (Math.max (1e-6, get ("Tune_Octave", 2)));
        const start = get ("PEnv_Start"), peak = get ("PEnv_Peak") * oct, sus = get ("PEnv_Sustain") * oct;
        const S = start <= -48 ? 0 : Math.pow (2, start / 12), Pk = Math.pow (2, peak / 12);
        const rel = get ("PEnv_Release") * oct;
        const tA = get ("PEnv_Attack") * (Pk <= S ? 0.5 : 1), tD = get ("PEnv_Decay");

        const seg = t => Math.sqrt (Math.max (0, t) / 1000);
        const parts = [seg (tA), seg (tD), 0.35, 0.35];
        const total = parts.reduce ((a, b) => a + b, 0) || 1;

        const floor = -48;
        const st = r => r > 0 ? Math.max (floor, 12 * Math.log2 (r)) : floor;
        const vals = [st (S), peak, sus, sus + rel];
        const lim = Math.min (48, Math.max (12, 12 * Math.ceil (Math.max (...vals.map (Math.abs)) / 12)));

        const W = this.box.w - 4, H = this.box.h - 6, x0 = 2, y0 = 3;
        const X = t => x0 + (t / total) * W;
        const Y = v => y0 + (0.5 - 0.5 * Math.max (-1, Math.min (1, v / lim))) * H;

        const pts = [];
        const n = 24;
        for (let k = 0; k <= n; ++k) pts.push ([X (parts[0] * k / n), Y (st (S + (Pk - S) * k / n))]);
        let t = parts[0];
        pts.push ([X (t + parts[1]), Y (sus)]);
        t += parts[1] + parts[2];
        pts.push ([X (t), Y (sus)]);
        pts.push ([X (t + parts[3]), Y (sus + rel)]);

        this.zero.setAttribute ("y1", Y (0)); this.zero.setAttribute ("y2", Y (0));
        this.curve.setAttribute ("d", pathFrom (pts));
        this.s.classList.toggle ("off", ! get ("PEnv_On"));
    }
}

// Oscillator waveform: built-in shapes are drawn analytically, user shapes come from
// the program store (512 points).
export class WavePlot
{
    constructor (ctx, parent, osc, box)
    {
        this.ctx = ctx; this.osc = osc; this.box = box;
        this.s = svg (parent, box);
        svgEl (this.s, "rect", { class: "bg", x: 0.5, y: 0.5, width: box.w - 1, height: box.h - 1 });
        svgEl (this.s, "line", { class: "axis", x1: 2, x2: box.w - 2, y1: box.h / 2, y2: box.h / 2 });
        this.curve = svgEl (this.s, "path", { class: "curve" });
        const pre = osc === 0 ? "O1_" : "O2_";
        for (const id of [pre + "Waveform", pre + "PWM_W"])
            ctx.model.listen (id, () => this.draw());
        ctx.programs?.onShapes (() => this.draw());
        this.draw();
    }

    sample (wave, pw, user, ph)
    {
        switch (wave)
        {
            case 0: return Math.sin (2 * Math.PI * ph);
            case 1: return 1 - 2 * ph;
            case 2: return ph < pw ? 1 : -1;
            case 3: return ph < 0.5 ? 4 * ph - 1 : 3 - 4 * ph;
            case 4: return user ? user[Math.floor (ph * 512) & 511] : 0;
            case 5:
            {
                if (! user) return 0;
                const a = user[Math.floor (ph * 512) & 511];
                const b = user[Math.floor ((ph + pw) * 512) & 511];
                return 0.5 * (a - b);
            }
        }
        return 0;
    }

    draw()
    {
        const pre = this.osc === 0 ? "O1_" : "O2_";
        const wave = this.ctx.model.get (pre + "Waveform") ?? 0;
        const pw = this.ctx.model.get (pre + "PWM_W") ?? 0.5;
        const user = this.ctx.programs?.shape (this.osc === 0 ? "wave1" : "wave2");
        const W = this.box.w - 6, H = this.box.h - 8;
        const pts = [];
        const n = 96;
        for (let k = 0; k <= n; ++k)
        {
            const ph = (k / n) % 1 + (k === n ? 0.9999 : 0) - (k === n ? 0 : 0);
            const v = this.sample (wave, pw, user, k === n ? 0.99999 : ph);
            pts.push ([3 + (k / n) * W, 4 + (0.5 - 0.5 * Math.max (-1, Math.min (1, v))) * H]);
        }
        this.curve.setAttribute ("d", pathFrom (pts));
    }
}

export class LfoPlot
{
    constructor (ctx, parent, lfo, box)
    {
        this.ctx = ctx; this.lfo = lfo; this.box = box;
        this.s = svg (parent, box);
        svgEl (this.s, "rect", { class: "bg", x: 0.5, y: 0.5, width: box.w - 1, height: box.h - 1 });
        this.curve = svgEl (this.s, "path", { class: "curve" });
        ctx.model.listen (`LFO_${lfo + 1}_Shape`, () => this.draw());
        ctx.programs?.onShapes (() => this.draw());
        this.draw();
    }

    draw()
    {
        const shape = this.ctx.model.get (`LFO_${this.lfo + 1}_Shape`) ?? 0;
        const user = this.ctx.programs?.shape (this.lfo === 0 ? "lfo1" : "lfo2");
        const W = this.box.w - 6, H = this.box.h - 7;
        const pts = [];
        const n = 2 * 64;
        // deterministic pseudo-random values for the random shapes' preview
        const r = k => { const x = Math.sin (k * 12.9898 + this.lfo * 78.233) * 43758.5453; return x - Math.floor (x); };
        for (let k = 0; k <= n; ++k)
        {
            const ph = (k / n) * 2 % 1, cyc = Math.floor ((k / n) * 2 - 1e-9);
            let v;
            switch (shape)
            {
                case 0: v = 0.5 + 0.5 * Math.sin (2 * Math.PI * ph); break;
                case 1: v = 1 - ph; break;
                case 2: v = ph < 0.5 ? 1 : 0; break;
                case 3: v = ph < 0.5 ? 2 * ph : 2 - 2 * ph; break;
                case 4: { const a = r (cyc), b = r (cyc + 1); v = a + (b - a) * (0.5 - 0.5 * Math.cos (Math.PI * ph)); break; }
                case 5: v = r (cyc); break;
                default: v = user ? user[Math.floor (ph * 512) & 511] : 0.5;
            }
            pts.push ([3 + (k / n) * W, 3 + (1 - Math.max (0, Math.min (1, v))) * H]);
        }
        this.curve.setAttribute ("d", pathFrom (pts));
    }
}
