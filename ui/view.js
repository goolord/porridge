import { css, DESIGN_WIDTH, DESIGN_HEIGHT } from "./style.js";
import { el, place, Menu, Status } from "./controls.js";
import { ParamModel } from "./model.js";
import { makeDefs, makeContextProgram } from "./paramdefs.js";
import { buildMainPage } from "./page-main.js";
import { buildMidiPage, MIDI_HINT } from "./page-midi.js";
import { buildShapesPage, SHAPES_HINT } from "./page-shapes.js";

const HINTS = {
    main: "Drag or scroll to change a value, shift for fine steps. Double-click to type, right-click to reset.",
    shapes: SHAPES_HINT,
    midi: MIDI_HINT,
};
import { ProgramStore } from "./programs.js";

export class PorridgeView extends HTMLElement
{
    init (patchConnection)
    {
        this.pc = patchConnection;
        this.defs = makeDefs (() => this.contextProgram?.bytes);
        this.model = new ParamModel (patchConnection, this.defs);
        this.contextProgram = makeContextProgram (this.defs);
        this.contextProgram.update (this.model.values);
        this.model.listenAny (id => this.contextProgram.update (new Map ([[id, this.model.get (id)]])));

        const shadow = this.attachShadow ({ mode: "open" });
        el ("style", null, shadow).textContent = css;

        const stage = this.stage = el ("div", "pv-stage", shadow);
        const msg = el ("div", "msg");
        this.ctx = {
            model: this.model,
            pc: patchConnection,
            status: new Status (msg),
            menu: new Menu (stage),
            scale: () => this.scaleFactor ?? 1,
            stage,
            view: this,
        };

        this.programs = new ProgramStore (patchConnection, this.model, {
            onChange: () => this.updateProgramBar(),
            onMessage: t => this.toast (t),
        });
        this.ctx.programs = this.programs;

        this.pages = {
            main:   el ("div", "pv-page on", stage),
            midi:   el ("div", "pv-page", stage),
            shapes: el ("div", "pv-page", stage),
        };

        buildMainPage (this.ctx, this.pages.main);
        buildMidiPage (this.ctx, this.pages.midi);
        this.shapes = buildShapesPage (this.ctx, this.pages.shapes);

        this.buildStatusBar (stage, msg);
        this.buildDropZone (stage);

        this.resizeObserver = new ResizeObserver (() => this.layout());
        this.resizeObserver.observe (this);
        this.layout();

        this.programs.start();
        this.updateProgramBar();
        this.ctx.status.setIdle (HINTS.main);
    }

    disconnectedCallback()
    {
        this.resizeObserver?.disconnect();
        this.model?.dispose();
        this.programs?.dispose();
        this.shapes?.dispose?.();
    }

    layout()
    {
        const w = this.clientWidth || DESIGN_WIDTH, h = this.clientHeight || DESIGN_HEIGHT;
        const s = Math.min (w / DESIGN_WIDTH, h / DESIGN_HEIGHT);
        this.scaleFactor = s;
        const ox = Math.max (0, (w - DESIGN_WIDTH * s) / 2);
        const oy = Math.max (0, (h - DESIGN_HEIGHT * s) / 2);
        this.stage.style.transform = `translate(${ox}px, ${oy}px) scale(${s})`;
    }

    showPage (name)
    {
        for (const [k, p] of Object.entries (this.pages))
            p.classList.toggle ("on", k === name);
        for (const [k, b] of Object.entries (this.pageButtons))
            b.classList.toggle ("on", k === name);
        this.ctx.menu.close();
        this.ctx.status.setIdle (HINTS[name] ?? "");
        if (name === "shapes") this.shapes?.refresh?.();
    }

    openShape (which)
    {
        this.showPage ("shapes");
        this.shapes?.select?.(which);
    }

    buildStatusBar (stage, msg)
    {
        const bar = el ("div", "pv-status", stage);
        bar.appendChild (msg);

        const prog = el ("div", "prog", bar);
        const btn = (parent, text, title, fn) =>
        {
            const b = el ("button", "btn", parent, text);
            b.addEventListener ("click", fn);
            b.addEventListener ("mouseenter", () => this.ctx.status.show (title));
            b.addEventListener ("mouseleave", () => this.ctx.status.clear());
            return b;
        };

        btn (prog, "<", "Previous program", () => this.programs.select (this.programs.current - 1));
        this.progName = el ("div", "name", prog);
        this.progName.addEventListener ("click", () => this.openProgramMenu());
        this.progName.addEventListener ("dblclick", () => this.renameProgram());
        this.progName.addEventListener ("mouseenter", () => this.ctx.status.show ("Click to pick a program, double-click to rename it"));
        this.progName.addEventListener ("mouseleave", () => this.ctx.status.clear());
        btn (prog, ">", "Next program", () => this.programs.select (this.programs.current + 1));

        btn (bar, "Load", "Load an Oatmeal program or bank (.omp, .omb, .fxp, .fxb, .dat). You can also drop the file onto the window.", () => this.pickFile());
        btn (bar, "Save program", "Save this program as an Oatmeal .omp file", () => this.programs.downloadProgram());
        btn (bar, "Save bank", "Save all 64 programs as an Oatmeal .omb bank", () => this.programs.downloadBank());
        btn (bar, "Init", "Reset this program to the Init patch", () => this.programs.initCurrent());
        btn (bar, "Panic", "Stop all notes and clear effect tails", () => this.programs.panic());

        const pages = el ("div", "pages", bar);
        this.pageButtons = {
            main: btn (pages, "Synth", "Synth page", () => this.showPage ("main")),
            shapes: btn (pages, "Shapes", "Draw oscillator waveforms and LFO shapes", () => this.showPage ("shapes")),
            midi: btn (pages, "MIDI", "MIDI channels, controllers, velocity and aftertouch curves", () => this.showPage ("midi")),
        };
        this.pageButtons.main.classList.add ("on");

        this.fileInput = el ("input", null, stage);
        this.fileInput.type = "file";
        this.fileInput.accept = ".omp,.omb,.fxp,.fxb,.dat";
        this.fileInput.style.display = "none";
        this.fileInput.addEventListener ("change", () =>
        {
            const f = this.fileInput.files?.[0];
            if (f) this.loadFile (f);
            this.fileInput.value = "";
        });

        this.toastEl = el ("div", "toast", stage);
    }

    buildDropZone (stage)
    {
        const drop = el ("div", "drop", stage, "Drop an Oatmeal program or bank");
        let depth = 0;
        this.addEventListener ("dragenter", e => { e.preventDefault(); depth++; drop.classList.add ("on"); });
        this.addEventListener ("dragleave", e => { e.preventDefault(); if (--depth <= 0) { depth = 0; drop.classList.remove ("on"); } });
        this.addEventListener ("dragover", e => e.preventDefault());
        this.addEventListener ("drop", e =>
        {
            e.preventDefault();
            depth = 0;
            drop.classList.remove ("on");
            const f = e.dataTransfer?.files?.[0];
            if (f) this.loadFile (f);
        });
    }

    pickFile() { this.fileInput.click(); }

    async loadFile (file)
    {
        try
        {
            const buf = await file.arrayBuffer();
            this.programs.loadFile (new Uint8Array (buf), file.name);
        }
        catch (e)
        {
            this.toast ("Couldn't read " + file.name + ": " + e.message);
        }
    }

    updateProgramBar()
    {
        if (! this.progName) return;
        const i = this.programs.current;
        const name = this.programs.name (i);
        this.progName.textContent = String (i + 1).padStart (2, "0") + "  " + name;
    }

    openProgramMenu()
    {
        const items = [];
        for (let i = 0; i < 64; ++i)
            items.push ({ label: String (i + 1).padStart (2, "0") + "  " + this.programs.name (i), value: i });
        this.ctx.menu.open (this.progName, items, this.programs.current, v => this.programs.select (v));
    }

    renameProgram()
    {
        const input = el ("input", "entry", this.stage);
        const r = this.progName;
        let x = 0, y = 0, n = r;
        while (n && n !== this.stage) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
        place (input, x, y, r.offsetWidth, r.offsetHeight);
        input.maxLength = 23;
        input.value = this.programs.name (this.programs.current);
        input.select(); input.focus();
        let done = false;
        const finish = ok =>
        {
            if (done) return; done = true;
            if (ok) this.programs.rename (this.programs.current, input.value);
            input.remove();
        };
        input.addEventListener ("keydown", k => { k.stopPropagation(); if (k.key === "Enter") finish (true); if (k.key === "Escape") finish (false); });
        input.addEventListener ("blur", () => finish (true));
    }

    toast (text)
    {
        this.toastEl.textContent = text;
        this.toastEl.classList.add ("on");
        clearTimeout (this.toastTimer);
        this.toastTimer = setTimeout (() => this.toastEl.classList.remove ("on"), 3500);
    }
}
