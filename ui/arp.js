// Arpeggiator pattern: 16 step cells and a pattern-length handle.
// Click a step to advance its command, shift-click to go back, right-click for the list.

import { el, place } from "./controls.js";

// short glyphs for the 16 step commands, in the synth's order
const GLYPH = ["·", "↑", "↑|", "↓", "↓|", "↕", "↕|", "=", "→", "↔", "⤺", "⤺↑", "⤺↓", "⊤", "⊥", "?"];

export class ArpPattern
{
    constructor (ctx, parent, box)
    {
        this.ctx = ctx;
        const cw = Math.floor (box.w / 16);
        this.cells = [];
        for (let i = 0; i < 16; ++i)
        {
            const id = "Arp_P" + i.toString (16).toUpperCase();
            const c = place (el ("div", "cell", parent), box.x + i * cw, box.y, cw - 2, 24);
            c.tabIndex = 0;
            c.addEventListener ("pointerdown", ev => this.onCell (ev, i, id));
            c.addEventListener ("contextmenu", ev => ev.preventDefault());
            c.addEventListener ("mouseenter", () => { this.hoverId = id; this.status (id); });
            c.addEventListener ("mouseleave", () => { this.hoverId = null; ctx.status.clear(); });
            c.addEventListener ("keydown", ev =>
            {
                if (ev.key === "ArrowUp" || ev.key === " ") { this.step (id, 1); ev.preventDefault(); }
                if (ev.key === "ArrowDown") { this.step (id, -1); ev.preventDefault(); }
                if (ev.key === "Enter") this.menu (c, id);
            });
            ctx.model.listen (id, () => this.draw());
            this.cells.push (c);
        }

        // length handle: a thin rail under the cells
        const rail = this.rail = place (el ("div", "draw", parent), box.x, box.y + 27, 16 * cw - 2, 12);
        rail.style.borderBottom = "1px solid var(--edge)";
        this.handle = el ("div", null, rail);
        this.handle.style.cssText = "position:absolute;top:2px;width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;border-bottom:8px solid var(--signal)";
        this.cw = cw;
        rail.addEventListener ("pointerdown", ev => this.onRail (ev));
        rail.addEventListener ("mouseenter", () => { this.railHover = true; this.status ("Arp_End"); });
        rail.addEventListener ("mouseleave", () => { this.railHover = false; ctx.status.clear(); });
        ctx.model.listen ("Arp_End", () => this.draw());
        this.draw();
    }

    status (id) { this.ctx.status.show (this.ctx.model.def (id).longText (this.ctx.model.get (id))); }

    step (id, d)
    {
        const x = this.ctx.model.get (id);
        this.ctx.model.gestureSet (id, (x + d + 16) % 16);
    }

    menu (anchor, id)
    {
        const def = this.ctx.model.def (id);
        this.ctx.menu.open (anchor, def.names.map ((n, i) => ({ label: GLYPH[i] + "  " + n, value: i })),
                            this.ctx.model.get (id), v => this.ctx.model.gestureSet (id, v));
    }

    onCell (ev, i, id)
    {
        ev.preventDefault();
        if (ev.button === 2) this.menu (this.cells[i], id);
        else if (ev.button === 1 || (ev.button === 0 && (ev.ctrlKey || ev.metaKey))) this.ctx.model.gestureSet (id, 0);
        else if (ev.button === 0) this.step (id, ev.shiftKey ? -1 : 1);
    }

    onRail (ev)
    {
        ev.preventDefault();
        const rail = this.rail;
        rail.setPointerCapture (ev.pointerId);
        this.ctx.model.begin ("Arp_End");
        const set = cx =>
        {
            const r = rail.getBoundingClientRect();
            const n = Math.max (0, Math.min (15, Math.floor ((cx - r.left) / r.width * 16)));
            this.ctx.model.set ("Arp_End", n);
            this.status ("Arp_End");
        };
        set (ev.clientX);
        const move = mv => set (mv.clientX);
        const up = () =>
        {
            rail.removeEventListener ("pointermove", move);
            rail.removeEventListener ("pointerup", up);
            this.ctx.model.end ("Arp_End");
        };
        rail.addEventListener ("pointermove", move);
        rail.addEventListener ("pointerup", up);
    }

    draw()
    {
        const end = this.ctx.model.get ("Arp_End") ?? 15;
        for (let i = 0; i < 16; ++i)
        {
            const id = "Arp_P" + i.toString (16).toUpperCase();
            const v = this.ctx.model.get (id) ?? 0;
            const c = this.cells[i];
            c.textContent = GLYPH[v] ?? "?";
            c.classList.toggle ("off", v === 0);
            c.classList.toggle ("out", i > end);
        }
        this.handle.style.left = (end * this.cw + this.cw / 2 - 7) + "px";
        if (this.hoverId) this.status (this.hoverId);
        if (this.railHover) this.status ("Arp_End");
    }
}
