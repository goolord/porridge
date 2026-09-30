// Shape editor used for oscillator waveforms (512 points, -1..1), LFO shapes
// (512 points, 0..1) and the velocity/aftertouch curves (64 points, 0..1).
//
// Left-drag draws. Shift-click sets a line from the last point. Ctrl-drag smooths
// locally (more smoothing higher up). Right-click: context menu.

import { el, place } from "./controls.js";

export class ShapeEditor
{
    constructor (ctx, parent, box, opts)
    {
        this.ctx = ctx;
        this.box = box;
        this.n = opts.points;
        this.bipolar = !! opts.bipolar;
        this.onEdit = opts.onEdit;          // (Float32Array) => void, called while drawing (throttled by caller)
        this.onCommit = opts.onCommit;      // (Float32Array) => void, called at end of a stroke/operation
        this.gridDivs = opts.grid ?? 8;
        this.data = new Float32Array (this.n);
        this.undoStack = [];

        const c = this.canvas = place (el ("canvas", "draw", parent), box.x, box.y, box.w, box.h);
        c.width = box.w * 2; c.height = box.h * 2;
        this.g = c.getContext ("2d");

        c.addEventListener ("pointerdown", ev => this.onDown (ev));
        c.addEventListener ("contextmenu", ev => { ev.preventDefault(); this.openMenu (ev); });
        c.addEventListener ("mousemove", ev => this.hoverStatus (ev));
        c.addEventListener ("mouseleave", () => ctx.status.clear());
        this.menuItems = opts.menu ?? [];
    }

    set (data)
    {
        this.data = Float32Array.from (data);
        this.draw();
    }

    lo() { return this.bipolar ? -1 : 0; }

    valueAt (ev)
    {
        const r = this.canvas.getBoundingClientRect();
        const fx = (ev.clientX - r.left) / r.width, fy = (ev.clientY - r.top) / r.height;
        const i = Math.max (0, Math.min (this.n - 1, Math.round (fx * (this.n - 1))));
        const v = this.bipolar ? 1 - 2 * fy : 1 - fy;
        return [i, Math.max (this.lo(), Math.min (1, v)), fy];
    }

    hoverStatus (ev)
    {
        const [i, v] = this.valueAt (ev);
        const cur = this.data[i];
        this.ctx.status.show (`Point ${i + 1} of ${this.n}: ${cur.toFixed (4)}  (pointer at ${v.toFixed (4)})`);
    }

    pushUndo()
    {
        this.undoStack.push (Float32Array.from (this.data));
        if (this.undoStack.length > 40) this.undoStack.shift();
    }

    undo()
    {
        const d = this.undoStack.pop();
        if (d) { this.data = d; this.draw(); this.onCommit?.(this.data); }
    }

    line (i0, v0, i1, v1)
    {
        if (i1 < i0) [i0, v0, i1, v1] = [i1, v1, i0, v0];
        for (let i = i0; i <= i1; ++i)
            this.data[i] = i1 === i0 ? v1 : v0 + (v1 - v0) * (i - i0) / (i1 - i0);
    }

    smoothAt (i, amount)
    {
        const radius = Math.max (1, Math.round (amount * this.n / 16));
        const src = Float32Array.from (this.data);
        for (let k = -radius; k <= radius; ++k)
        {
            const j = i + k;
            if (j < 0 || j >= this.n) continue;
            let s = 0, w = 0;
            for (let m = -radius; m <= radius; ++m)
            {
                const q = this.wrap (j + m);
                if (q < 0) continue;
                const wt = 1 - Math.abs (m) / (radius + 1);
                s += src[q] * wt; w += wt;
            }
            const f = 1 - Math.abs (k) / (radius + 1);
            this.data[j] = src[j] * (1 - f) + (s / w) * f;
        }
    }

    wrap (j) { return this.bipolar || this.n === 512 ? ((j % this.n) + this.n) % this.n : (j < 0 || j >= this.n ? -1 : j); }

    onDown (ev)
    {
        if (ev.button !== 0) return;
        ev.preventDefault();
        const c = this.canvas;
        this.pushUndo();
        let [i, v] = this.valueAt (ev);

        if (ev.shiftKey && this.last)
        {
            const v0 = (ev.ctrlKey || ev.metaKey) ? this.data[this.last[0]] : this.last[1];
            const v1 = (ev.ctrlKey || ev.metaKey) ? this.data[i] : v;
            this.line (this.last[0], v0, i, v1);
            this.last = [i, v1];
            this.draw(); this.onCommit?.(this.data);
            return;
        }

        c.setPointerCapture (ev.pointerId);
        const smoothing = ev.ctrlKey || ev.metaKey;
        let prev = [i, v];
        const apply = (i, v, fy) =>
        {
            if (smoothing) this.smoothAt (i, 1 - fy);
            else this.line (prev[0], prev[1], i, v);
            prev = [i, v];
            this.last = [i, v];
            this.draw();
            this.onEdit?.(this.data);
        };
        apply (i, v, 0);

        const move = mv => { const [i, v, fy] = this.valueAt (mv); apply (i, v, fy); this.hoverStatus (mv); };
        const up = () =>
        {
            c.removeEventListener ("pointermove", move);
            c.removeEventListener ("pointerup", up);
            c.removeEventListener ("pointercancel", up);
            this.onCommit?.(this.data);
        };
        c.addEventListener ("pointermove", move);
        c.addEventListener ("pointerup", up);
        c.addEventListener ("pointercancel", up);
    }

    openMenu (ev)
    {
        const items = this.menuItems.map ((m, k) => ({ label: m.label, value: k }));
        const anchor = { offsetLeft: 0, offsetTop: 0, offsetHeight: 0, offsetParent: null };
        // open at pointer: use a temporary anchor element positioned at the pointer
        const r = this.canvas.getBoundingClientRect();
        const s = this.ctx.scale();
        const tmp = place (el ("div", null, this.canvas.parentElement), this.box.x + (ev.clientX - r.left) / s, this.box.y + (ev.clientY - r.top) / s, 1, 1);
        tmp.style.position = "absolute";
        this.ctx.menu.open (tmp, items, -1, k =>
        {
            this.pushUndo();
            this.menuItems[k].run (this);
            this.draw();
            this.onCommit?.(this.data);
        });
        tmp.remove();
        void anchor;
    }

    draw()
    {
        const g = this.g, W = this.canvas.width, H = this.canvas.height;
        const css = getComputedStyle (this.canvas);
        const ink = css.getPropertyValue ("--signal").trim() || "#1c3c73";
        const grid = "rgba(31,26,14,0.18)";
        g.clearRect (0, 0, W, H);
        g.fillStyle = "rgba(236,227,196,0.45)";
        g.fillRect (0, 0, W, H);
        g.strokeStyle = grid; g.lineWidth = 1;
        for (let k = 1; k < this.gridDivs; ++k)
        {
            const x = Math.round (k * W / this.gridDivs) + 0.5;
            g.beginPath(); g.moveTo (x, 0); g.lineTo (x, H); g.stroke();
        }
        for (let k = 1; k < 4; ++k)
        {
            const y = Math.round (k * H / 4) + 0.5;
            g.strokeStyle = (this.bipolar && k === 2) ? "rgba(31,26,14,0.4)" : grid;
            g.beginPath(); g.moveTo (0, y); g.lineTo (W, y); g.stroke();
        }
        const Y = v => this.bipolar ? (0.5 - 0.5 * v) * (H - 8) + 4 : (1 - v) * (H - 8) + 4;
        const X = i => (i / (this.n - 1)) * (W - 1);
        const base = this.bipolar ? Y (0) : Y (0);
        g.fillStyle = "rgba(28,60,115,0.16)";
        g.beginPath(); g.moveTo (X (0), base);
        for (let i = 0; i < this.n; ++i) g.lineTo (X (i), Y (this.data[i]));
        g.lineTo (X (this.n - 1), base); g.closePath(); g.fill();
        g.strokeStyle = ink; g.lineWidth = 2.4;
        g.beginPath();
        for (let i = 0; i < this.n; ++i) (i ? g.lineTo : g.moveTo).call (g, X (i), Y (this.data[i]));
        g.stroke();
        g.strokeStyle = "#6f5f36"; g.lineWidth = 2; g.strokeRect (1, 1, W - 2, H - 2);
    }
}

//==============================================================================
// Shape generators and operations shared by the editors

export const ops = {
    fix (d, bipolar)
    {
        if (bipolar)
        {
            let mean = 0; for (const v of d) mean += v; mean /= d.length;
            let peak = 0; for (let i = 0; i < d.length; ++i) { d[i] -= mean; peak = Math.max (peak, Math.abs (d[i])); }
            if (peak > 0) for (let i = 0; i < d.length; ++i) d[i] /= peak;
        }
        else
        {
            let lo = Infinity, hi = -Infinity;
            for (const v of d) { lo = Math.min (lo, v); hi = Math.max (hi, v); }
            if (hi > lo) for (let i = 0; i < d.length; ++i) d[i] = (d[i] - lo) / (hi - lo);
        }
    },
    soften (d, wrap = true)
    {
        const s = Float32Array.from (d), n = d.length;
        for (let i = 0; i < n; ++i)
        {
            const a = wrap ? s[(i - 1 + n) % n] : s[Math.max (0, i - 1)];
            const b = wrap ? s[(i + 1) % n] : s[Math.min (n - 1, i + 1)];
            d[i] = 0.25 * a + 0.5 * s[i] + 0.25 * b;
        }
    },
    invert (d, bipolar) { for (let i = 0; i < d.length; ++i) d[i] = bipolar ? -d[i] : 1 - d[i]; },
    reverse (d) { d.reverse(); },
};

export function genWave (kind, n = 512)
{
    const d = new Float32Array (n);
    for (let i = 0; i < n; ++i)
    {
        const p = i / n;
        switch (kind)
        {
            case "sine": d[i] = Math.sin (2 * Math.PI * p); break;
            case "saw": d[i] = 1 - 2 * p; break;
            case "square": d[i] = p < 0.5 ? 1 : -1; break;
            case "triangle": d[i] = p < 0.25 ? 4 * p : p < 0.75 ? 2 - 4 * p : 4 * p - 4; break;
            case "random": d[i] = 2 * Math.random() - 1; break;
        }
    }
    if (kind === "random") { for (let k = 0; k < 6; ++k) ops.soften (d); ops.fix (d, true); }
    return d;
}

export function genLfo (kind, n = 512)
{
    const w = genWave (kind, n);
    for (let i = 0; i < n; ++i) w[i] = 0.5 + 0.5 * w[i];
    return w;
}
