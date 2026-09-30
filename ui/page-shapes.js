// Shapes page: the two user oscillator waveforms and the two user LFO shapes.

import { el, place, Block, Button } from "./controls.js";
import { ShapeEditor, ops, genWave, genLfo } from "./editor.js";
import { DESIGN_WIDTH, DESIGN_HEIGHT } from "./style.js";

export const SHAPES_HINT = "Drag to draw, shift-click for a straight line, ctrl-drag to smooth. Right-click for tools.";

const SHAPES = [
    { key: "wave1", title: "oscillator 1 waveform", bipolar: true },
    { key: "wave2", title: "oscillator 2 waveform", bipolar: true },
    { key: "lfo1",  title: "lfo 1 shape",           bipolar: false },
    { key: "lfo2",  title: "lfo 2 shape",           bipolar: false },
];

let clipboard = null;

export function buildShapesPage (ctx, page)
{
    const blk = new Block (page, "", 6, 6, DESIGN_WIDTH - 12, DESIGN_HEIGHT - 30 - 12);
    const tabs = [];
    let current = 0;

    const title = el ("div", "ttl left", blk.el);
    title.style.fontSize = "16px";

    const box = { x: 10, y: 60, w: 1310, h: 430 };
    const specBox = { x: 10, y: 520, w: 1310, h: 158 };

    const editor = new ShapeEditor (ctx, blk.el, box, {
        points: 512,
        bipolar: true,
        grid: 16,
        onEdit: d => ctx.programs.setShape (SHAPES[current].key, d, false),
        onCommit: d => { ctx.programs.setShape (SHAPES[current].key, d, true); drawSpectrum(); },
        menu: [],
    });

    const spec = place (el ("canvas", null, blk.el), specBox.x, specBox.y, specBox.w, specBox.h);
    spec.style.position = "absolute";
    spec.width = specBox.w * 2; spec.height = specBox.h * 2;
    const specNote = el ("div", "note", blk.el, "harmonics (dB, first 64)");
    place (specNote, 12, 500);

    const apply = fn => { editor.pushUndo(); fn (editor.data); editor.draw(); ctx.programs.setShape (SHAPES[current].key, editor.data, true); drawSpectrum(); };

    const tools = [
        ["sine",     () => apply (d => d.set (SHAPES[current].bipolar ? genWave ("sine") : genLfo ("sine")))],
        ["saw",      () => apply (d => d.set (SHAPES[current].bipolar ? genWave ("saw") : genLfo ("saw")))],
        ["square",   () => apply (d => d.set (SHAPES[current].bipolar ? genWave ("square") : genLfo ("square")))],
        ["triangle", () => apply (d => d.set (SHAPES[current].bipolar ? genWave ("triangle") : genLfo ("triangle")))],
        ["random",   () => apply (d => d.set (SHAPES[current].bipolar ? genWave ("random") : genLfo ("random")))],
        ["fix",      () => apply (d => ops.fix (d, SHAPES[current].bipolar))],
        ["soften",   () => apply (d => ops.soften (d))],
        ["invert",   () => apply (d => ops.invert (d, SHAPES[current].bipolar))],
        ["reverse",  () => apply (d => ops.reverse (d))],
        ["copy",     () => { clipboard = Float32Array.from (editor.data); ctx.view.toast ("Copied the shape"); }],
        ["paste",    () => { if (clipboard) apply (d => d.set (clipboard)); }],
        ["undo",     () => { editor.undo(); ctx.programs.setShape (SHAPES[current].key, editor.data, true); drawSpectrum(); }],
    ];
    editor.menuItems = tools.map (([label, fn]) => ({ label, run: () => fn() }));

    SHAPES.forEach ((s, i) =>
    {
        const b = new Button (ctx, blk.el, s.title.replace (" waveform", "").replace (" shape", ""), 10 + i * 112, 28, 106, () => select (i));
        tabs.push (b.el);
    });

    tools.forEach (([label, fn], i) =>
    {
        new Button (ctx, blk.el, label, 1320 - (tools.length - i) * 68, 28, 62, fn);
    });

    function drawSpectrum()
    {
        const g = spec.getContext ("2d"), W = spec.width, H = spec.height;
        g.clearRect (0, 0, W, H);
        g.fillStyle = "rgba(236,227,196,0.45)"; g.fillRect (0, 0, W, H);
        g.strokeStyle = "#6f5f36"; g.lineWidth = 2; g.strokeRect (1, 1, W - 2, H - 2);
        const d = editor.data, n = d.length;
        const bars = 64, bw = W / bars;
        g.fillStyle = getComputedStyle (spec).getPropertyValue ("--signal").trim() || "#1c3c73";
        const mags = [];
        let mean = 0;
        if (! SHAPES[current].bipolar) { for (const v of d) mean += v; mean /= n; }
        for (let h = 1; h <= bars; ++h)
        {
            let re = 0, im = 0;
            for (let i = 0; i < n; ++i) { const a = 2 * Math.PI * h * i / n; re += (d[i] - mean) * Math.cos (a); im -= (d[i] - mean) * Math.sin (a); }
            mags.push (2 * Math.hypot (re, im) / n);
        }
        const peak = Math.max (1e-9, ...mags);
        mags.forEach ((m, k) =>
        {
            const db = 20 * Math.log10 (Math.max (m / peak, 1e-6));
            const f = Math.max (0, (db + 60) / 60);
            g.fillRect (k * bw + 2, H - 4 - f * (H - 8), bw - 4, f * (H - 8));
        });
    }

    function select (i)
    {
        current = i;
        const s = SHAPES[i];
        title.textContent = s.title;
        tabs.forEach ((t, k) => t.classList.toggle ("on", k === i));
        editor.bipolar = s.bipolar;
        editor.gridDivs = 16;
        editor.undoStack = [];
        editor.set (ctx.programs.shape (s.key) ?? new Float32Array (512));
        spec.style.display = s.bipolar ? "block" : "none";
        specNote.style.display = s.bipolar ? "block" : "none";
        drawSpectrum();
    }

    ctx.programs.onShapes (() => { editor.set (ctx.programs.shape (SHAPES[current].key) ?? new Float32Array (512)); drawSpectrum(); });
    select (0);

    return {
        select: key => select (Math.max (0, SHAPES.findIndex (s => s.key === key))),
        refresh: () => select (current),
    };
}
