// MIDI page: channel filter, sustain pedal, velocity/aftertouch curves and the six
// assignable controllers.

import { el, place, Block, Toggle, Button } from "./controls.js";
import { GridBlock, blockH } from "./page-main.js";
import { DESIGN_WIDTH, DESIGN_HEIGHT } from "./style.js";
import { ShapeEditor, ops } from "./editor.js";

export const MIDI_HINT = "Right-click a curve for presets. Controller moves are smoothed over about 50 ms.";

export function buildMidiPage (ctx, page)
{
    const G = (title, x, y, cols, rows, opts) => new GridBlock (ctx, page, title, x, y, cols, rows, opts);
    const X0 = 6, Y0 = 6, W = DESIGN_WIDTH - 12, GAP = 6;
    const pageH = DESIGN_HEIGHT - 30;

    // channel strip
    const chn = G ("midi input", X0, Y0, 16, 1, { w: W, cw: 46 });
    for (let c = 0; c < 16; ++c)
        chn.tg ("MIDI_Channel_" + (c + 1), c, 0, String (c + 1));
    const bx = chn.cx (16) + 12;
    new Button (ctx, chn.el, "all", bx, chn.cy (0) + 3, 44, () => { for (let c = 1; c <= 16; ++c) ctx.model.gestureSet ("MIDI_Channel_" + c, 1); }, "Receive on every channel");
    new Button (ctx, chn.el, "none", bx + 50, chn.cy (0) + 3, 44, () => { for (let c = 1; c <= 16; ++c) ctx.model.gestureSet ("MIDI_Channel_" + c, 0); }, "Ignore every channel");
    new Toggle (ctx, chn.el, "SustainPedal", bx + 124, chn.cy (0) + 5, "use sustain pedal (cc 64)");
    const chLabel = el ("div", "note", chn.el, "channels");
    place (chLabel, 10, 2);

    // controllers: two rows of three along the bottom
    const ccW = (W - 2 * GAP) / 3, ccH = blockH (3);
    const Ycc = pageH - 2 * ccH - 2 * GAP;

    // curve editors fill the space between
    const Y1 = chn.bottom();
    const curveH = Ycc - GAP - Y1, curveW = (W - GAP) / 2;

    const curveBlock = (title, key, x) =>
    {
        const b = new Block (page, title, x, Y1, curveW, curveH);
        const box = { x: 10, y: 24, w: curveW - 20, h: curveH - 34 };
        const ed = new ShapeEditor (ctx, b.el, box, {
            points: 64, bipolar: false, grid: 8,
            onEdit: d => ctx.programs.setShape (key, d, false),
            onCommit: d => ctx.programs.setShape (key, d, true),
            menu: [
                { label: "linear",            run: e => { for (let i = 0; i < 64; ++i) e.data[i] = i / 63; } },
                { label: "soften",            run: e => ops.soften (e.data, false) },
                { label: "scale to the top",  run: e => { const m = Math.max (...e.data); if (m > 0) for (let i = 0; i < 64; ++i) e.data[i] /= m; } },
                { label: "fit top and bottom", run: e => ops.fix (e.data, false) },
                { label: "undo",              run: e => e.undo() },
            ],
        });
        ed.hoverStatus = ev =>
        {
            const [i] = ed.valueAt (ev);
            ctx.status.show (`${title}: ${(100 * i / 63).toFixed (2)} % -> ${(100 * ed.data[i]).toFixed (2)} %`);
        };
        ed.set (ctx.programs.shape (key) ?? new Float32Array (64).map ((_, i) => i / 63));
        ctx.programs.onShapes (() => ed.set (ctx.programs.shape (key) ?? new Float32Array (64)));
        return b;
    };

    curveBlock ("velocity map", "velocity", X0);
    curveBlock ("aftertouch map", "touch", X0 + curveW + GAP);

    for (let k = 0; k < 6; ++k)
    {
        const n = k + 1;
        const b = G ("cc " + n, X0 + (k % 3) * (ccW + GAP), Ycc + Math.floor (k / 3) * (ccH + GAP), 4, 3, { w: ccW, cw: (ccW - 12) / 4 });
        b.p ("CC" + n, 0, 0, "controller");
        b.btn ("learn", 1, 0, 60, () => ctx.programs.learn ("CC" + n), "Move a controller to assign it", 4);
        for (let t = 0; t < 4; ++t)
        {
            const c = (t % 2) * 2, r = 1 + Math.floor (t / 2);
            b.ch (`CC${n}_Target_${t + 1}`, c, r, "target " + (t + 1));
            b.p (`CC${n}_Depth_${t + 1}`, c + 1, r, "depth");
        }
    }
}
