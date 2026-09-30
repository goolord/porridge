// Panel controls. Every control is bound to one parameter id (the Cmajor endpoint id,
// which is the original skin's action name, e.g. "Cutoff" or "O1_Waveform").
// Values held by the model are *internal* values (the numbers stored in an Oatmeal
// preset); defs translate them to knob positions and to the original display text.

export function el (tag, cls, parent, text)
{
    const e = document.createElement (tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    if (parent) parent.appendChild (e);
    return e;
}

export function place (e, x, y, w, h)
{
    e.style.left = x + "px";
    e.style.top = y + "px";
    if (w !== undefined) e.style.width = w + "px";
    if (h !== undefined) e.style.height = h + "px";
    return e;
}

const DRAG_PIXELS = 220;      // pixels of vertical travel for the full range
const FINE_SHIFT = 0.1;
const FINE_CTRL = 0.25;

export class Block
{
    constructor (parent, title, x, y, w, h, opts = {})
    {
        this.el = place (el ("div", "blk", parent), x, y, w, h);
        if (title)
            el ("div", "ttl" + (opts.titleLeft ? " left" : ""), this.el, title);
    }
}

// Shared hover/drag/status handling
class ControlBase
{
    constructor (ctx, id)
    {
        this.ctx = ctx;
        this.id = id;
        this.def = ctx.model.def (id);
        if (! this.def) throw new Error ("unknown parameter " + id);
    }

    hookStatus (e)
    {
        e.addEventListener ("mouseenter", () => { this.hover = true; this.ctx.status.show (this.statusText()); });
        e.addEventListener ("mouseleave", () => { this.hover = false; if (! this.dragging) this.ctx.status.clear(); });
    }

    statusText()
    {
        return this.def.longText (this.ctx.model.get (this.id));
    }

    refreshStatus()
    {
        if (this.hover || this.dragging)
            this.ctx.status.show (this.statusText());
    }
}

export class Param extends ControlBase
{
    // label shown above-left; value right. w defaults to 76
    constructor (ctx, parent, id, x, y, w = 76, label = undefined)
    {
        super (ctx, id);
        const e = this.el = place (el ("div", "p", parent), x, y, w);
        e.tabIndex = 0;
        el ("span", "l", e, label ?? this.def.short);
        this.v = el ("span", "v", e);
        const t = el ("span", "t", e);
        this.fill = el ("i", null, t);
        this.hookStatus (e);

        e.addEventListener ("pointerdown", ev => this.onDown (ev));
        e.addEventListener ("wheel", ev => this.onWheel (ev), { passive: false });
        e.addEventListener ("dblclick", ev => this.onEdit (ev));
        e.addEventListener ("contextmenu", ev => ev.preventDefault());
        e.addEventListener ("keydown", ev => this.onKey (ev));

        ctx.model.listen (id, () => this.update());
        this.update();
    }

    update()
    {
        const x = this.ctx.model.get (this.id);
        this.v.textContent = this.def.shortText (x);
        const n = Math.max (0, Math.min (1, this.def.toNorm (x)));

        if (this.def.bipolar)
        {
            const a = Math.min (n, 0.5), b = Math.max (n, 0.5);
            this.fill.style.left = (a * 100) + "%";
            this.fill.style.width = Math.max (1, (b - a) * 100) + "%";
            if (b - a < 0.004) this.fill.style.width = "1px";
        }
        else
        {
            this.fill.style.left = "0";
            this.fill.style.width = (n * 100) + "%";
        }

        this.refreshStatus();
    }

    setNorm (n)
    {
        n = Math.max (0, Math.min (1, n));
        this.ctx.model.set (this.id, this.def.fromNorm (n));
    }

    onDown (ev)
    {
        if (ev.button === 2) { this.ctx.model.gestureSet (this.id, this.def.init); ev.preventDefault(); return; }
        if (ev.button === 1) { this.ctx.model.gestureSet (this.id, this.def.fromNorm (0.5)); ev.preventDefault(); return; }
        if (ev.button !== 0) return;

        ev.preventDefault();
        const e = this.el;
        e.setPointerCapture (ev.pointerId);
        this.dragging = true;
        e.classList.add ("drag");
        this.ctx.model.begin (this.id);

        let lastX = ev.clientX, lastY = ev.clientY;
        let norm = this.def.toNorm (this.ctx.model.get (this.id));
        const scale = this.ctx.scale();

        const move = mv =>
        {
            const dy = (lastY - mv.clientY) / scale;
            const dx = (mv.clientX - lastX) / scale;
            lastX = mv.clientX; lastY = mv.clientY;
            let d = (dy + dx * 0.35) / DRAG_PIXELS;
            if (mv.shiftKey) d *= FINE_SHIFT;
            if (mv.ctrlKey || mv.metaKey) d *= FINE_CTRL;
            norm = Math.max (0, Math.min (1, norm + d));
            this.setNorm (norm);
        };

        const up = () =>
        {
            e.removeEventListener ("pointermove", move);
            e.removeEventListener ("pointerup", up);
            e.removeEventListener ("pointercancel", up);
            this.dragging = false;
            e.classList.remove ("drag");
            this.ctx.model.end (this.id);
            if (! this.hover) this.ctx.status.clear();
        };

        e.addEventListener ("pointermove", move);
        e.addEventListener ("pointerup", up);
        e.addEventListener ("pointercancel", up);
        this.refreshStatus();
    }

    onWheel (ev)
    {
        ev.preventDefault();
        let d = (ev.deltaY < 0 ? 1 : -1) / 100;
        if (ev.shiftKey) d *= FINE_SHIFT;
        const n = this.def.toNorm (this.ctx.model.get (this.id));
        this.ctx.model.begin (this.id);
        this.setNorm (n + d);
        this.ctx.model.end (this.id);
    }

    onKey (ev)
    {
        const step = ev.shiftKey ? 0.001 : 0.01;
        const n = this.def.toNorm (this.ctx.model.get (this.id));
        if (ev.key === "ArrowUp" || ev.key === "ArrowRight") { this.setNorm (n + step); ev.preventDefault(); }
        else if (ev.key === "ArrowDown" || ev.key === "ArrowLeft") { this.setNorm (n - step); ev.preventDefault(); }
        else if (ev.key === "Enter") this.onEdit (ev);
        else if (ev.key === "Delete" || ev.key === "Backspace") this.ctx.model.gestureSet (this.id, this.def.init);
    }

    onEdit (ev)
    {
        ev.preventDefault?.();
        const e = this.el;
        const input = el ("input", "entry", e.parentElement);
        place (input, e.offsetLeft, e.offsetTop, e.offsetWidth, e.offsetHeight);
        input.value = this.def.editText (this.ctx.model.get (this.id));
        input.select();
        input.focus();

        let done = false;
        const finish = commit =>
        {
            if (done) return;
            done = true;
            if (commit)
            {
                const x = this.def.parse (input.value);
                if (x !== undefined && Number.isFinite (x))
                    this.ctx.model.gestureSet (this.id, x);
            }
            input.remove();
            e.focus();
        };

        input.addEventListener ("keydown", k =>
        {
            k.stopPropagation();
            if (k.key === "Enter") finish (true);
            else if (k.key === "Escape") finish (false);
        });
        input.addEventListener ("blur", () => finish (true));
    }
}

export class Choice extends ControlBase
{
    constructor (ctx, parent, id, x, y, w = 76, label = undefined, opts = {})
    {
        super (ctx, id);
        const e = this.el = place (el ("div", "p ch", parent), x, y, w);
        e.tabIndex = 0;
        el ("span", "l", e, label ?? this.def.short);
        this.v = el ("span", "v", e);
        this.names = opts.names ?? this.def.shortNames ?? this.def.names;
        this.hookStatus (e);

        e.addEventListener ("pointerdown", ev => this.onDown (ev));
        e.addEventListener ("contextmenu", ev => ev.preventDefault());
        e.addEventListener ("wheel", ev =>
        {
            ev.preventDefault();
            this.step (ev.deltaY < 0 ? -1 : 1);
        }, { passive: false });
        e.addEventListener ("keydown", ev =>
        {
            if (ev.key === "ArrowUp" || ev.key === "ArrowLeft") { this.step (-1); ev.preventDefault(); }
            else if (ev.key === "ArrowDown" || ev.key === "ArrowRight" || ev.key === " ") { this.step (1); ev.preventDefault(); }
            else if (ev.key === "Enter") this.openMenu();
        });

        ctx.model.listen (id, () => this.update());
        this.update();
    }

    count() { return this.def.names.length; }

    update()
    {
        const x = this.ctx.model.get (this.id);
        this.v.textContent = this.names[x] ?? String (x);
        this.refreshStatus();
    }

    step (d)
    {
        const n = this.count();
        const x = this.ctx.model.get (this.id);
        this.ctx.model.gestureSet (this.id, ((x + d) % n + n) % n);
    }

    onDown (ev)
    {
        ev.preventDefault();
        if (ev.button === 2 || ev.altKey) { this.openMenu(); return; }
        if (ev.button === 1 || (ev.button === 0 && (ev.ctrlKey || ev.metaKey))) { this.ctx.model.gestureSet (this.id, 0); return; }
        if (ev.button === 0) this.step (ev.shiftKey ? -1 : 1);
    }

    openMenu()
    {
        const items = this.def.names.map ((n, i) => ({ label: this.def.menuNames?.[i] ?? n, value: i }));
        this.ctx.menu.open (this.el, items, this.ctx.model.get (this.id), v => this.ctx.model.gestureSet (this.id, v),
                            this.def.menuGroups);
    }
}

export class Toggle extends ControlBase
{
    constructor (ctx, parent, id, x, y, label = undefined)
    {
        super (ctx, id);
        const e = this.el = place (el ("div", "tg", parent), x, y);
        e.tabIndex = 0;
        el ("b", null, e);
        el ("span", null, e, label ?? this.def.short);
        this.hookStatus (e);
        e.addEventListener ("pointerdown", ev =>
        {
            ev.preventDefault();
            if (ev.button === 0) this.flip();
            else if (ev.button === 2 || ev.button === 1) this.ctx.model.gestureSet (this.id, 0);
        });
        e.addEventListener ("contextmenu", ev => ev.preventDefault());
        e.addEventListener ("keydown", ev => { if (ev.key === " " || ev.key === "Enter") { this.flip(); ev.preventDefault(); } });
        ctx.model.listen (id, () => this.update());
        this.update();
    }

    flip() { this.ctx.model.gestureSet (this.id, this.ctx.model.get (this.id) ? 0 : 1); }

    update()
    {
        this.el.classList.toggle ("on", !! this.ctx.model.get (this.id));
        this.refreshStatus();
    }
}

export class Button
{
    constructor (ctx, parent, text, x, y, w, onClick, statusText)
    {
        const e = this.el = place (el ("button", "btn", parent, text), x, y, w);
        e.addEventListener ("click", () => onClick());
        if (statusText)
        {
            e.addEventListener ("mouseenter", () => ctx.status.show (statusText));
            e.addEventListener ("mouseleave", () => ctx.status.clear());
        }
    }
}

export class Menu
{
    constructor (root)
    {
        this.root = root;
        this.el = null;
        this.closer = ev => { if (this.el && ! this.el.contains (ev.target)) this.close(); };
    }

    open (anchor, items, current, onPick, groups)
    {
        this.close();
        const m = this.el = el ("div", "menu", this.root);
        items.forEach ((it, i) =>
        {
            if (groups && groups[i])
                el ("div", "hd", m, groups[i]);
            const d = el ("div", it.value === current ? "cur" : "", m, it.label);
            d.addEventListener ("pointerdown", ev => { ev.stopPropagation(); ev.preventDefault(); this.close(); onPick (it.value); });
        });

        // position below the anchor inside the stage
        const stage = this.root;
        let x = 0, y = 0, n = anchor;
        while (n && n !== stage) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
        y += anchor.offsetHeight;
        const W = stage.offsetWidth, H = stage.offsetHeight;
        m.style.left = "0px"; m.style.top = "0px";
        const mw = m.offsetWidth, mh = m.offsetHeight;
        if (x + mw > W - 4) x = W - mw - 4;
        if (y + mh > H - 4) y = Math.max (4, y - anchor.offsetHeight - mh);
        m.style.left = x + "px";
        m.style.top = y + "px";
        setTimeout (() => document.addEventListener ("pointerdown", this.closer, true), 0);
    }

    close()
    {
        document.removeEventListener ("pointerdown", this.closer, true);
        this.el?.remove();
        this.el = null;
    }
}

export class Status
{
    constructor (msgEl)
    {
        this.msgEl = msgEl;
        this.idle = "";
    }

    show (text) { this.msgEl.textContent = text; this.msgEl.classList.remove ("idle"); }
    clear()     { this.msgEl.textContent = this.idle; this.msgEl.classList.add ("idle"); }
    setIdle (t) { this.idle = t; this.clear(); }
}
