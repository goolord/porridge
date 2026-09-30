// XY pad: drag to set X/Y (-1..1). Right-button drag keeps the distance to the centre
// constant (moves around a circle), middle click centres. The dashed circle shows the
// random-walk radius; the small ring shows where the synth currently is (if the patch
// reports it).

import { svg, svgEl } from "./plots.js";
import { place } from "./controls.js";

export class XYPad
{
    constructor (ctx, parent, box)
    {
        this.ctx = ctx;
        const side = Math.min (box.w, box.h);
        this.box = { x: box.x + (box.w - side) / 2, y: box.y + (box.h - side) / 2, w: side, h: side };
        const s = this.s = svg (parent, this.box);
        s.classList.add ("draw");
        const S = side;
        svgEl (s, "rect", { class: "bg", x: 0.5, y: 0.5, width: S - 1, height: S - 1 });
        svgEl (s, "line", { class: "axis", x1: S / 2, x2: S / 2, y1: 1, y2: S - 1 });
        svgEl (s, "line", { class: "axis", x1: 1, x2: S - 1, y1: S / 2, y2: S / 2 });
        this.radius = svgEl (s, "circle", { r: 0, fill: "none", stroke: "var(--signal)", "stroke-width": 1, "stroke-dasharray": "2 2", opacity: 0.8 });
        this.live = svgEl (s, "circle", { r: 3, fill: "none", stroke: "var(--signal)", "stroke-width": 1, opacity: 0 });
        this.hx = svgEl (s, "line", { stroke: "var(--signal)", "stroke-width": 1.4 });
        this.hy = svgEl (s, "line", { stroke: "var(--signal)", "stroke-width": 1.4 });
        this.dot = svgEl (s, "circle", { r: 3.2, fill: "var(--signal)" });

        s.addEventListener ("pointerdown", ev => this.onDown (ev));
        s.addEventListener ("contextmenu", ev => ev.preventDefault());
        s.addEventListener ("mouseenter", () => { this.hover = true; this.status(); });
        s.addEventListener ("mouseleave", () => { this.hover = false; if (! this.dragging) ctx.status.clear(); });

        for (const id of ["XY_X", "XY_Y", "XY_Var_Radius"])
            ctx.model.listen (id, () => this.draw());

        if (ctx.pc?.addEndpointListener)
        {
            this.liveListener = v => { this.livePos = v; this.draw(); };
            ctx.pc.addEndpointListener ("xyOut", this.liveListener);
        }
        this.draw();
    }

    toPx (x, y) { const S = this.box.w; return [S / 2 + x * (S / 2 - 3), S / 2 - y * (S / 2 - 3)]; }

    status()
    {
        const x = this.ctx.model.get ("XY_X"), y = this.ctx.model.get ("XY_Y");
        const r = Math.hypot (x, y), a = Math.atan2 (y, x) * 180 / Math.PI;
        this.ctx.status.show (`XY pad (${x.toFixed (3)}, ${y.toFixed (3)} / ${r.toFixed (3)}, ${a.toFixed (2)} degrees)`);
    }

    draw()
    {
        const x = this.ctx.model.get ("XY_X") ?? 0, y = this.ctx.model.get ("XY_Y") ?? 0;
        const [px, py] = this.toPx (x, y);
        const S = this.box.w;
        this.dot.setAttribute ("cx", px); this.dot.setAttribute ("cy", py);
        this.hx.setAttribute ("x1", px - 6); this.hx.setAttribute ("x2", px + 6); this.hx.setAttribute ("y1", py); this.hx.setAttribute ("y2", py);
        this.hy.setAttribute ("y1", py - 6); this.hy.setAttribute ("y2", py + 6); this.hy.setAttribute ("x1", px); this.hy.setAttribute ("x2", px);
        const rr = (this.ctx.model.get ("XY_Var_Radius") ?? 0) * (S / 2 - 3);
        this.radius.setAttribute ("cx", px); this.radius.setAttribute ("cy", py); this.radius.setAttribute ("r", rr);

        if (this.livePos && rr > 0)
        {
            const [lx, ly] = this.toPx (this.livePos[0] ?? this.livePos.x, this.livePos[1] ?? this.livePos.y);
            this.live.setAttribute ("cx", lx); this.live.setAttribute ("cy", ly); this.live.setAttribute ("opacity", 1);
        }
        else this.live.setAttribute ("opacity", 0);

        if (this.hover || this.dragging) this.status();
    }

    onDown (ev)
    {
        ev.preventDefault();
        const m = this.ctx.model;
        if (ev.button === 1) { m.gestureSet ("XY_X", 0); m.gestureSet ("XY_Y", 0); return; }

        const s = this.s;
        s.setPointerCapture (ev.pointerId);
        this.dragging = true;
        m.begin ("XY_X"); m.begin ("XY_Y");
        const circular = ev.button === 2;
        const r0 = Math.hypot (m.get ("XY_X"), m.get ("XY_Y"));
        let x = m.get ("XY_X"), y = m.get ("XY_Y");
        let last = [ev.clientX, ev.clientY];
        const S = this.box.w, scale = this.ctx.scale();

        const apply = (cx, cy, fine) =>
        {
            let nx, ny;
            if (fine)
            {
                nx = x + (cx - last[0]) / scale / (S / 2) * 0.15;
                ny = y - (cy - last[1]) / scale / (S / 2) * 0.15;
            }
            else
            {
                const r = s.getBoundingClientRect();
                nx = ((cx - r.left) / r.width - 0.5) * 2 * (S / 2) / (S / 2 - 3);
                ny = -((cy - r.top) / r.height - 0.5) * 2 * (S / 2) / (S / 2 - 3);
            }
            if (circular && r0 > 0)
            {
                const a = Math.atan2 (ny, nx);
                nx = Math.cos (a) * r0; ny = Math.sin (a) * r0;
            }
            x = Math.max (-1, Math.min (1, nx));
            y = Math.max (-1, Math.min (1, ny));
            last = [cx, cy];
            m.set ("XY_X", x); m.set ("XY_Y", y);
        };

        if (! (ev.shiftKey || ev.ctrlKey)) apply (ev.clientX, ev.clientY, false);

        const move = mv => apply (mv.clientX, mv.clientY, mv.shiftKey || mv.ctrlKey);
        const up = () =>
        {
            s.removeEventListener ("pointermove", move);
            s.removeEventListener ("pointerup", up);
            s.removeEventListener ("pointercancel", up);
            this.dragging = false;
            m.end ("XY_X"); m.end ("XY_Y");
            if (! this.hover) this.ctx.status.clear();
        };
        s.addEventListener ("pointermove", move);
        s.addEventListener ("pointerup", up);
        s.addEventListener ("pointercancel", up);
    }
}
