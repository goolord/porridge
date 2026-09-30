// Visual language borrowed from the original Oatmeal default skin: khaki panels,
// lowercase labels, bold lowercase block titles in the block corner, one ink colour
// for everything that carries a value.

export const DESIGN_WIDTH = 1344;
export const DESIGN_HEIGHT = 732;

export const css = `
:host, porridge-view {
    --ground: #978552;
    --panel: #b9aa7b;
    --panel-hi: #c9bc92;
    --edge: #6f5f36;
    --ink: #1f1a0e;
    --ink-soft: #4c4127;
    --ink-faint: #7a6c45;
    --signal: #1c3c73;
    --signal-soft: rgba(28, 60, 115, 0.22);
    --paper: #ece3c4;

    display: block;
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: var(--ground);
    font-family: Bahnschrift, "DIN Alternate", "DIN 2014", "Barlow", "Arial Narrow", sans-serif;
    font-stretch: semi-condensed;
    color: var(--ink);
    user-select: none;
    -webkit-user-select: none;
    cursor: default;
}

.pv-stage {
    position: absolute;
    left: 0;
    top: 0;
    width: ${DESIGN_WIDTH}px;
    height: ${DESIGN_HEIGHT}px;
    transform-origin: 0 0;
}

.pv-page { position: absolute; inset: 0 0 30px 0; display: none; }
.pv-page.on { display: block; }

.blk {
    position: absolute;
    box-sizing: border-box;
    background: var(--panel);
    border: 1px solid var(--edge);
    border-radius: 3px;
    padding: 4px 6px 5px 6px;
}
.blk > .ttl {
    position: absolute;
    right: 6px;
    top: 2px;
    font-weight: 700;
    font-size: 14px;
    letter-spacing: 0.01em;
    color: var(--ink);
    pointer-events: none;
}
.blk > .ttl.left { right: auto; left: 6px; }

/* a parameter row: label left, value right, position track underneath */
.p {
    position: absolute;
    box-sizing: border-box;
    height: 26px;
    padding: 1px 3px 0 3px;
    border-radius: 2px;
    cursor: ns-resize;
}
.p:hover, .p.drag { background: var(--panel-hi); }
.p .l {
    position: absolute; left: 3px; top: 1px;
    font-size: 11px; color: var(--ink-soft); white-space: nowrap;
}
.p .v {
    position: absolute; right: 3px; top: 10px;
    font-size: 12.5px; font-variant-numeric: tabular-nums; white-space: nowrap;
}
.p .t {
    position: absolute; left: 3px; right: 3px; bottom: 1px; height: 2px;
    background: rgba(31, 26, 14, 0.14);
}
.p .t i {
    position: absolute; top: 0; bottom: 0; background: var(--signal);
}
.p.dim .v, .p.dim .l { opacity: 0.45; }

/* choice: same footprint, click cycles, menu on right click */
.p.ch { cursor: pointer; }
.p.ch .v::after { content: ""; display: inline-block; width: 0; height: 0; margin-left: 4px;
    border-left: 3px solid transparent; border-right: 3px solid transparent; border-top: 4px solid var(--ink-faint);
    vertical-align: 2px; }

/* toggle */
.tg {
    position: absolute; height: 18px; cursor: pointer; font-size: 11.5px; color: var(--ink-soft);
    display: flex; align-items: center; gap: 5px; white-space: nowrap;
}
.tg b { width: 9px; height: 9px; border: 1px solid var(--ink); box-sizing: border-box; background: transparent; }
.tg.on b { background: var(--signal); border-color: var(--signal); }
.tg.on { color: var(--ink); }

.btn {
    position: absolute; height: 20px; box-sizing: border-box; padding: 0 8px;
    border: 1px solid var(--edge); border-radius: 2px; background: var(--panel-hi);
    font: inherit; font-size: 12px; color: var(--ink); cursor: pointer; line-height: 18px; text-align: center;
}
.btn:hover { background: var(--paper); }
.btn:active { background: var(--signal); color: var(--paper); }
.btn.on { background: var(--signal); color: var(--paper); border-color: var(--signal); }

.plot { position: absolute; display: block; }
.plot path.curve { fill: none; stroke: var(--signal); stroke-width: 1.4; }
.plot path.fill { fill: var(--signal-soft); stroke: none; }
.plot path.axis, .plot line.axis { stroke: rgba(31,26,14,0.28); stroke-width: 1; fill: none; }
.plot.off { opacity: 0.4; }
.plot rect.bg { fill: rgba(236, 227, 196, 0.35); stroke: var(--edge); stroke-width: 1; }

.sep { position: absolute; height: 1px; background: rgba(31,26,14,0.2); }
.note { position: absolute; font-size: 11px; color: var(--ink-faint); white-space: nowrap; }

/* status bar */
.pv-status {
    position: absolute; left: 0; right: 0; bottom: 0; height: 30px;
    display: flex; align-items: center; gap: 8px; padding: 0 8px; box-sizing: border-box;
    background: var(--panel); border-top: 1px solid var(--edge);
    font-size: 13px;
}
.pv-status .msg { flex: 1; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pv-status .msg.idle { color: var(--ink-faint); font-size: 12px; }
.pv-status .prog { display: flex; align-items: center; gap: 4px; }
.pv-status .prog .name {
    min-width: 210px; padding: 1px 6px; border: 1px solid var(--edge); background: var(--paper);
    font-size: 13px; cursor: pointer; white-space: nowrap; overflow: hidden;
}
.pv-status .btn { position: static; height: 21px; }
.pv-status .pages { display: flex; gap: 0; }
.pv-status .pages .btn { border-radius: 0; margin-left: -1px; }

/* menus */
.menu {
    position: absolute; z-index: 50; background: var(--paper); border: 1px solid var(--ink);
    padding: 2px 0; font-size: 12.5px; max-height: 560px; overflow-y: auto; min-width: 120px;
    box-shadow: 2px 2px 0 rgba(31,26,14,0.35);
}
.menu div { padding: 2px 12px 2px 10px; white-space: nowrap; cursor: pointer; }
.menu div:hover { background: var(--signal); color: var(--paper); }
.menu div.cur { font-weight: 700; }
.menu div.hd { color: var(--ink-faint); cursor: default; font-size: 11px; padding-top: 5px; }
.menu div.hd:hover { background: transparent; color: var(--ink-faint); }

/* text entry */
.entry {
    position: absolute; z-index: 40; font: inherit; font-size: 12.5px; box-sizing: border-box;
    border: 1px solid var(--signal); background: var(--paper); color: var(--ink); padding: 0 3px; outline: none;
}

/* arp pattern cells */
.cell {
    position: absolute; box-sizing: border-box; border: 1px solid var(--edge); background: var(--panel-hi);
    font-size: 11px; text-align: center; cursor: pointer; line-height: 22px; color: var(--ink);
}
.cell.off { background: transparent; color: var(--ink-faint); }
.cell.out { opacity: 0.35; }
.cell:hover { outline: 1px solid var(--signal); outline-offset: -1px; }

/* drawing surfaces */
.draw { position: absolute; cursor: crosshair; }

.drop {
    position: absolute; inset: 0; z-index: 100; display: none; align-items: center; justify-content: center;
    background: rgba(28, 60, 115, 0.55); color: var(--paper); font-size: 22px; font-weight: 700;
}
.drop.on { display: flex; }

.toast {
    position: absolute; left: 50%; bottom: 40px; transform: translateX(-50%); z-index: 90;
    background: var(--ink); color: var(--paper); padding: 5px 12px; font-size: 13px; border-radius: 2px;
    display: none; max-width: 80%;
}
.toast.on { display: block; }

.p:focus-visible, .btn:focus-visible, .tg:focus-visible, .cell:focus-visible { outline: 2px solid var(--signal); outline-offset: 1px; }
`;
