// Visual language borrowed from the original Oatmeal default skin: khaki panels,
// lowercase labels, bold lowercase block titles, one ink colour for everything that
// carries a value.

let designWidth = 1100.
let designHeight = 580.
let headerHeight = 34.
let statusHeight = 22.
// the area pages lay their panels out in
let pageHeight = designHeight - headerHeight - statusHeight

let px = Web.px

// Every control (parameter, list, switch, grid button) is one cell tall: this height, in a
// grid row this much taller (Grid.rowHeight), so that neighbours never touch.
let controlHeight = 26.
let controlGap = 2.

let groundColour = "#978552"

let css = `
:host, porridge-view {
    --ground: ${groundColour};
    --panel: #b9aa7b;
    --panel-hi: #c9bc92;
    --edge: #6f5f36;
    --ink: #1f1a0e;
    --ink-soft: #4c4127;
    --ink-faint: #7a6c45;
    --signal: #1c3c73;
    --signal-soft: rgba(28, 60, 115, 0.22);
    --paper: #ece3c4;
    --mod: #a3501c;
    /* what every control sits on, so that it reads as something to grab */
    --tile: rgba(236, 227, 196, 0.32);
    --tile-edge: rgba(111, 95, 54, 0.4);

    display: block;
    position: relative;
    /* important, because Cmajor sets the manifest's size on the view as an inline style, which
       would pin it at the design size and stop the stage scaling with the window */
    width: 100% !important;
    height: 100% !important;
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
    width: ${px(designWidth)};
    height: ${px(designHeight)};
    transform-origin: 0 0;
}

.pv-page { position: absolute; left: 0; right: 0; top: ${px(headerHeight)}; bottom: ${px(statusHeight)}; display: none; }
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
    left: 7px;
    top: 3px;
    font-weight: 700;
    font-size: 14px;
    letter-spacing: 0.01em;
    color: var(--ink);
    pointer-events: none;
}

/* panel tabs: the active one is filled with the signal ink */
.ptabs { position: absolute; left: 3px; top: 2px; display: flex; gap: 1px; z-index: 1; }
.ptab {
    padding: 0 7px; height: 18px; line-height: 18px; border-radius: 2px;
    font-size: 13px; font-weight: 700; color: var(--ink-faint); cursor: pointer; white-space: nowrap;
}
.ptab { background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.ptab:hover { color: var(--ink); background: var(--panel-hi); }
.ptab.on { color: var(--paper); background: var(--signal); }
.pbody { position: absolute; inset: 0; display: none; }
.pbody.on { display: block; }
.blk > .hdr { position: absolute; right: 6px; top: 1px; width: 40px; height: 18px; }

/* the effects order: a chain of chips in the title row, dragged sideways */
.fxorder {
    position: absolute; right: 6px; top: 1px; height: 18px; display: flex; align-items: center; gap: 3px;
    font-size: 12px; color: var(--ink-faint); user-select: none;
}
.fxorder .lbl { margin-right: 2px; }
.fxorder .arrow { font-weight: 700; }
.fxorder .chip {
    padding: 0 7px; height: 18px; line-height: 18px; border-radius: 2px; font-weight: 700;
    color: var(--ink); background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); cursor: grab;
}
.fxorder .chip:hover { background: var(--panel-hi); }
.fxorder .chip.drag { color: var(--paper); background: var(--signal); position: relative; z-index: 1; cursor: grabbing; }
.fxorder .chip.drop-before { box-shadow: inset 0 0 0 1px var(--tile-edge), -3px 0 0 var(--signal); }
.fxorder .chip.drop-after { box-shadow: inset 0 0 0 1px var(--tile-edge), 3px 0 0 var(--signal); }

/* a parameter row: label left, value right, position track underneath, on a tile */
.p {
    position: absolute;
    box-sizing: border-box;
    height: ${px(controlHeight)};
    padding: 1px 3px 0 3px;
    border-radius: 2px;
    cursor: ns-resize;
    background: var(--tile);
    box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.p:hover, .p.drag { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
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
/* the range modulation sweeps */
.p .t em { position: absolute; top: -1px; bottom: -1px; background: var(--mod); opacity: 0.6; display: none; }
.p.dim .v, .p.dim .l { opacity: 0.45; }

/* choice: same footprint, click opens the menu, right click steps */
.p.ch { cursor: pointer; }
.p.ch .v::after { content: ""; display: inline-block; width: 0; height: 0; margin-left: 4px;
    border-left: 3px solid transparent; border-right: 3px solid transparent; border-top: 4px solid var(--ink-faint);
    vertical-align: 2px; }

/* toggle: a switch on the same tile, and in the same footprint, as a parameter */
.tg {
    position: absolute; box-sizing: border-box; height: ${px(controlHeight)}; cursor: pointer;
    font-size: 12px; color: var(--ink-soft); display: flex; align-items: center; gap: 5px;
    white-space: nowrap; overflow: hidden; padding: 0 5px; border-radius: 2px;
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.tg:hover { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
.tg b { flex: none; width: 11px; height: 11px; border: 1.5px solid var(--ink); box-sizing: border-box; border-radius: 1px; background: transparent; }
.tg.on b { background: var(--signal); border-color: var(--signal); box-shadow: inset 0 0 0 1.5px var(--paper); }
.tg.on { color: var(--ink); }
.tg span { overflow: hidden; text-overflow: ellipsis; }
/* in a title row, a switch is as tall as the tabs */
.hdr .tg { height: 18px; font-size: 11.5px; }
.hdr .tg b { width: 9px; height: 9px; border-width: 1px; box-shadow: none; }

.btn {
    position: absolute; height: 20px; box-sizing: border-box; padding: 0 8px;
    border: 1px solid var(--edge); border-radius: 2px; background: var(--panel-hi);
    font: inherit; font-size: 12px; color: var(--ink); cursor: pointer; line-height: 18px; text-align: center;
}
.btn:hover { background: var(--paper); }
.btn:active { background: var(--signal); color: var(--paper); }
.btn.on { background: var(--signal); color: var(--paper); border-color: var(--signal); }
/* a button in a grid cell */
.btn.gc { height: ${px(controlHeight)}; line-height: ${px(controlHeight - 2.)}; padding: 0 4px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.plot { position: absolute; display: block; }
.plot path.curve { fill: none; stroke: var(--signal); stroke-width: 1.4; }
.plot path.fill { fill: var(--signal-soft); stroke: none; }
.plot path.axis, .plot line.axis { stroke: rgba(31,26,14,0.28); stroke-width: 1; fill: none; }
.plot.off { opacity: 0.4; }
.plot rect.bg { fill: rgba(236, 227, 196, 0.35); stroke: var(--edge); stroke-width: 1; }
.plot path.curve.faint { stroke-width: 1; stroke-dasharray: 3 2; opacity: 0.7; }
.plot line.axis.faint { stroke: rgba(31,26,14,0.12); }
.plot text.tick { font-size: 10px; fill: var(--ink-faint); }

/* graphical editors (envelopes, EQ): drag the points; "values" swaps in the raw fields */
.ed { position: absolute; }
.ed .node { fill: var(--paper); stroke: var(--signal); stroke-width: 1.6; }
.ed .node.hot { fill: var(--signal); }
.ed .node.hollow { fill: var(--panel); stroke-dasharray: 2 1.5; }
.ed .node.bend { fill: var(--panel); stroke-width: 1.3; }
.ed .node.bend.hot { fill: var(--signal); }
.ed .hit { fill: transparent; pointer-events: all; }
.ed .band { fill: var(--paper); stroke: var(--signal); stroke-width: 1.6; }
.ed .band.hot { fill: var(--signal); }
.ed .band.off { fill: transparent; stroke: var(--ink-faint); stroke-dasharray: 2 2; }
.ed .nodelabel { font-size: 10px; font-weight: 700; text-anchor: middle; fill: var(--signal); pointer-events: none; }
.ed .nodelabel.hot { fill: var(--paper); }
.ed .nodelabel.off { fill: var(--ink-faint); }
.ed .readout {
    font-size: 11.5px; fill: var(--ink); font-variant-numeric: tabular-nums; pointer-events: none;
    paint-order: stroke; stroke: var(--paper); stroke-width: 3px; stroke-linejoin: round;
}
.ed .xbtn { position: absolute; right: 4px; top: 4px; z-index: 2; height: 17px; line-height: 15px; padding: 0 6px; font-size: 11px; opacity: 0.85; }
.ed .xbtn:hover { opacity: 1; }
.ed .vals { position: absolute; inset: 0; display: none; }
.ed.expanded .vals { display: block; }
.ed.expanded > svg { display: none; }

.sep { position: absolute; height: 1px; background: rgba(31,26,14,0.2); }
.note { position: absolute; font-size: 11px; color: var(--ink-faint); white-space: nowrap; }
.note.wrap { white-space: normal; line-height: 1.35; }
.scale { position: absolute; height: ${px(controlHeight)}; line-height: ${px(controlHeight)}; font-size: 12.5px; color: var(--ink-faint);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.scale.on { color: var(--ink); font-weight: 700; }

/* header: page tabs, then the program and file controls */
.pv-head {
    position: absolute; left: 0; right: 0; top: 0; height: ${px(headerHeight)};
    display: flex; align-items: center; gap: 6px; padding: 0 6px; box-sizing: border-box;
    background: var(--panel); border-bottom: 1px solid var(--edge);
    font-size: 13px;
}
.pv-head .brand { font-weight: 700; font-size: 17px; letter-spacing: 0.02em; padding: 0 8px 0 4px; }
.pv-head .btn { position: static; height: 22px; }
.pv-head .pages { display: flex; }
.pv-head .pages .btn { border-radius: 0; margin-left: -1px; min-width: 64px; font-size: 13px; }
.pv-head .pages .btn:first-child { border-radius: 2px 0 0 2px; }
.pv-head .pages .btn:last-child { border-radius: 0 2px 2px 0; }
.pv-head .spacer { flex: 1; }
.pv-head .prog { display: flex; align-items: center; gap: 3px; }
.pv-head .prog .name {
    width: 200px; height: 20px; line-height: 20px; padding: 0 6px; border: 1px solid var(--edge); background: var(--paper);
    font-size: 13px; cursor: pointer; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.pv-head .prog .btn { width: 22px; padding: 0; }
.pv-head .btn.icon { width: 26px; padding: 0; font-size: 15px; line-height: 19px; }

/* status line: hover texts, or a hint for the page */
.pv-status {
    position: absolute; left: 0; right: 0; bottom: 0; height: ${px(statusHeight)};
    padding: 0 8px; box-sizing: border-box; line-height: ${px(statusHeight)};
    background: var(--panel); border-top: 1px solid var(--edge);
    font-size: 12.5px; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.pv-status.idle { color: var(--ink-faint); font-size: 12px; }

/* menus */
.menu {
    position: absolute; z-index: 50; background: var(--paper); border: 1px solid var(--ink);
    padding: 2px 0; font-size: 12.5px; max-height: 560px; overflow-y: auto; min-width: 120px;
    box-shadow: 2px 2px 0 rgba(31,26,14,0.35);
}
.menu div { padding: 2px 12px 2px 10px; white-space: nowrap; cursor: pointer; }
.menu div:hover { background: var(--signal); color: var(--paper); }
.menu div.cur { font-weight: 700; }
.menu.icons div { display: flex; align-items: center; }
.menu.icons .icw { width: 38px; flex: none; }

/* icons (Icons.res): strokes in the text colour */
.ic { display: block; height: 14px; width: auto; flex: none; overflow: visible;
    fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
.ic .f { fill: currentColor; stroke: none; }
.ic .dash { stroke-dasharray: 2 2; stroke-width: 1.2; }
.ic text { fill: currentColor; stroke: none; font-size: 6.5px; font-weight: 700; text-anchor: middle; }
.ic.bold { stroke-width: 2.1; height: 15px; }
.icw { display: inline-flex; align-items: center; gap: 2px; vertical-align: middle; }
.hq { font-size: 7.5px; font-weight: 700; line-height: 9px; padding: 0 2px; border-radius: 2px;
    background: var(--signal); color: var(--paper); letter-spacing: 0.03em; }
.menu div:hover .hq { background: var(--paper); color: var(--signal); }
.p .v.withicon { display: flex; align-items: center; gap: 2px; top: 9px; max-width: calc(100% - 6px); }
.p .v.withicon > span:last-child { overflow: hidden; text-overflow: ellipsis; }
.p.ch .v.withicon::after { margin-left: 1px; flex: none; }
.p .v .ic { height: 12px; color: var(--signal); }

/* text entry */
.entry {
    position: absolute; z-index: 40; font: inherit; font-size: 12.5px; box-sizing: border-box;
    border: 1px solid var(--signal); background: var(--paper); color: var(--ink); padding: 0 3px; outline: none;
}

/* arp pattern cells */
.cell {
    position: absolute; box-sizing: border-box; border: 1px solid var(--edge); background: var(--panel-hi);
    font-size: 11px; cursor: pointer; color: var(--ink);
    display: flex; align-items: center; justify-content: center;
}
.cell .icw { gap: 1px; }
.cell.off { background: transparent; color: var(--ink-faint); }
.cell.out { opacity: 0.35; }
.cell:hover { outline: 1px solid var(--signal); outline-offset: -1px; }

/* drawing surfaces */
.draw { position: absolute; cursor: crosshair; }
.hlabel { position: absolute; font-size: 11px; color: var(--ink-soft); pointer-events: none;
    background: rgba(236, 227, 196, 0.75); padding: 0 4px; border-radius: 2px; }

/* the sample a shape was made from: its name, what came of it, and its overview to drag along */
.sstrip { position: absolute; box-sizing: border-box; display: none; border-radius: 2px;
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.sstrip.on { display: block; }
.sstrip .n, .sstrip .d { position: absolute; left: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sstrip .n { top: 1px; font-size: 11px; color: var(--ink-soft); }
.sstrip .d { top: 10px; font-size: 12.5px; }
.sstrip canvas { position: absolute; cursor: ew-resize; }
.sstrip .x { right: 3px; top: 3px; width: 20px; padding: 0; font-size: 14px; line-height: 17px; }

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

/* mod page: source chips (with a jack on the right), target chips (jack on the left) */
.src, .tgt {
    position: absolute; box-sizing: border-box; height: ${px(controlHeight)}; border-radius: 2px;
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
    font-size: 13px; line-height: ${px(controlHeight)}; white-space: nowrap; color: var(--ink);
}
.src { padding: 0 28px 0 13px; cursor: grab; }
.tgt { padding: 0 6px 0 27px; cursor: pointer; }
.src .sw { position: absolute; left: 4px; top: 5px; bottom: 5px; width: 4px; border-radius: 2px; }
.src .lbl, .tgt .lbl { display: block; overflow: hidden; text-overflow: ellipsis; }
.src .n { position: absolute; right: 25px; top: 6px; display: none; min-width: 14px; height: 14px; padding: 0 2px;
    box-sizing: border-box; border-radius: 7px; background: var(--ink); color: var(--paper);
    font-size: 10px; line-height: 14px; text-align: center; font-weight: 700; }
.jk { position: absolute; top: 6px; width: 14px; height: 14px; box-sizing: border-box; border-radius: 50%;
    border: 2px solid var(--ink); background: var(--paper); box-shadow: inset 0 0 0 2px var(--paper); }
.src .jk { right: 6px; }
.tgt .jk { left: 6px; }
.jk.on { background: var(--ink); }
.src:hover, .tgt:hover, .src.lit, .src:focus-visible, .tgt:focus-visible { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
.src.sel { background: var(--paper); box-shadow: inset 0 0 0 1.5px var(--signal); }
.src.plug { padding: 0; cursor: grab; }
.tgt.on { font-weight: 700; }
.tgt.on .jk { background: var(--ink); }
.tgt.hot { background: var(--signal); color: var(--paper); box-shadow: none; }
.tgt.hot .jk { border-color: var(--paper); box-shadow: inset 0 0 0 2px var(--signal); }
.grp { position: absolute; font-size: 12px; font-weight: 700; line-height: 20px; color: var(--ink-faint); white-space: nowrap; }
.mcount { position: absolute; right: 9px; top: 4px; font-size: 12px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.picker { display: none; z-index: 20; border-color: var(--signal); box-shadow: 3px 3px 0 rgba(31,26,14,0.3); }
.picker.on { display: block; }
.picker .btn { z-index: 1; }
.wires { position: absolute; pointer-events: none; overflow: visible; z-index: 30; }
.wirecell { position: absolute; pointer-events: none; overflow: visible; z-index: 1; }
.wire { fill: none; stroke-width: 3.5; stroke-linecap: round; opacity: 0.9; }
.wire.muted { stroke-dasharray: 5 4; opacity: 0.5; }
.wire.drag { stroke-dasharray: 7 4; }
.conn { position: absolute; left: 0; display: none; }
.conn.on { display: block; }
.conn .btn.gc { font-size: 17px; line-height: 22px; color: var(--ink-soft); }
.conn .btn.gc:hover { color: var(--ink); }
.conn:hover .src, .conn:hover .tgt { box-shadow: inset 0 0 0 1px var(--edge); }
.addrow {
    position: absolute; box-sizing: border-box; display: flex; align-items: center; gap: 8px; padding: 0 10px;
    border: 1.5px dashed var(--edge); border-radius: 2px; font-size: 13px; color: var(--ink-soft); cursor: pointer;
}
.addrow:hover, .addrow:focus-visible { background: var(--panel-hi); color: var(--ink); border-color: var(--ink); outline: none; }
.addrow b { font-size: 17px; line-height: 1; }
.addrow .sub { color: var(--ink-faint); font-size: 12px; margin-left: 6px; }
.mempty { position: absolute; left: 20px; right: 20px; top: 92px; text-align: center; color: var(--ink-soft);
    font-size: 13px; line-height: 1.45; }
.mempty .big { font-size: 17px; font-weight: 700; color: var(--ink); margin-bottom: 6px; }
.msw { display: block; width: 12px; height: 12px; border-radius: 50%; }
.menu.icons .icw:has(.msw) { width: 20px; }

/* dialogs */
.shade { position: absolute; inset: 0; z-index: 80; background: rgba(31,26,14,0.35); display: flex; align-items: center; justify-content: center; }
.dlg {
    width: 460px; box-sizing: border-box; padding: 10px 14px 12px 14px; background: var(--panel);
    border: 1px solid var(--ink); border-radius: 3px; box-shadow: 3px 3px 0 rgba(31,26,14,0.35);
}
.dlg .dttl { font-weight: 700; font-size: 15px; margin-bottom: 8px; }
.dlg .drow { display: flex; align-items: flex-start; gap: 8px; margin: 5px 0; font-size: 12px; color: var(--ink-soft); }
.dlg .drow span { width: 74px; padding-top: 3px; }
.dlg input, .dlg textarea {
    flex: 1; font: inherit; font-size: 13px; color: var(--ink); background: var(--paper);
    border: 1px solid var(--edge); padding: 2px 5px; outline: none; box-sizing: border-box;
}
.dlg input:focus, .dlg textarea:focus { border-color: var(--signal); }
.dlg textarea { height: 84px; resize: none; }
.dlg .dbtns { display: flex; justify-content: flex-end; gap: 6px; margin-top: 10px; }
.dlg .btn { position: static; min-width: 64px; }
.dlg .seg { display: flex; flex-wrap: wrap; }
.dlg .seg .btn { min-width: 0; padding: 0 6px; border-radius: 0; margin-left: -1px; }
.dlg .seg .btn.off { opacity: 0.45; pointer-events: none; }
.dlg .dnote { margin: 6px 0 6px 82px; font-size: 11.5px; line-height: 1.35; color: var(--ink-faint); }
.dlg .dnote + .btn { margin-left: 82px; }

/* the preset browser (PresetBrowser.res): sources and facets, the list, the details */
.brw {
    width: 1060px; height: 546px; box-sizing: border-box; display: flex; flex-direction: column;
    background: var(--panel); border: 1px solid var(--ink); border-radius: 3px; box-shadow: 3px 3px 0 rgba(31,26,14,0.35);
}
.brw ::-webkit-scrollbar { width: 9px; }
.brw ::-webkit-scrollbar-thumb { background: rgba(111,95,54,0.45); border-radius: 4px; border: 2px solid transparent; background-clip: padding-box; }
.brw ::-webkit-scrollbar-track { background: transparent; }
.brw-head { display: flex; align-items: center; gap: 10px; padding: 8px 10px 7px 12px; }
.brw-title { font-weight: 700; font-size: 16px; }
.brw-search { flex: 1; position: relative; }
.brw-search input {
    display: block; width: 100%; height: 26px; box-sizing: border-box; padding: 0 26px 0 8px;
    font: inherit; font-size: 13.5px; color: var(--ink); background: var(--paper); border: 1px solid var(--edge); outline: none;
}
.brw-search input:focus { border-color: var(--signal); }
.brw-search input::placeholder { color: var(--ink-faint); }
.brw-x {
    position: absolute; right: 3px; top: 3px; width: 20px; height: 20px; display: none; padding: 0;
    border: none; background: transparent; font: inherit; font-size: 12px; color: var(--ink-faint); cursor: pointer;
}
.brw-x.on { display: block; }
.brw-x:hover { color: var(--ink); }
.brw-count { width: 84px; text-align: right; font-size: 12px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.brw-body { flex: 1; min-height: 0; display: flex; gap: 8px; padding: 0 10px; }

.brw-side {
    width: 188px; flex: none; overflow-y: auto; padding: 2px 0 8px; border-radius: 2px;
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.brw-shead { padding: 7px 8px 2px; font-size: 11.5px; font-weight: 700; color: var(--ink-faint); }
.brw-srow { display: flex; align-items: center; gap: 6px; height: 22px; padding: 0 8px; font-size: 13px; cursor: pointer; white-space: nowrap; }
.brw-srow:hover { background: var(--panel-hi); }
.brw-srow.on { background: var(--signal); color: var(--paper); }
.brw-slabel { flex: 1; overflow: hidden; text-overflow: ellipsis; }
.brw-srow.bad .brw-slabel { text-decoration: line-through; opacity: 0.6; }
.brw-srm { display: none; font-size: 11px; padding: 0 2px; }
.brw-srow:hover .brw-srm { display: inline; }
.brw-open { font-size: 12.5px; color: var(--ink-soft); }
.brw-n { font-size: 11px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.on > .brw-n { color: inherit; opacity: 0.75; }
.brw-facet { display: flex; flex-direction: column; }
.brw-facet .brw-fv {
    display: flex; justify-content: space-between; gap: 6px; height: 21px; line-height: 21px; padding: 0 8px 0 14px;
    font-size: 12.5px; cursor: pointer; white-space: nowrap;
}
.brw-facet .brw-fv > span:first-child { overflow: hidden; text-overflow: ellipsis; }
.brw-chips { display: flex; flex-wrap: wrap; gap: 3px; padding: 3px 8px; }
.brw-chips .brw-fv {
    display: inline-flex; gap: 4px; height: 18px; line-height: 18px; padding: 0 6px; border-radius: 9px;
    font-size: 11.5px; cursor: pointer; white-space: nowrap; background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.brw-fv:hover { background: var(--panel-hi); }
.brw-fv.on { background: var(--signal); color: var(--paper); box-shadow: none; }

.brw-list { flex: 1; min-width: 0; overflow-y: auto; position: relative; background: var(--paper); border: 1px solid var(--edge); }
.brw-row {
    display: flex; align-items: center; gap: 8px; height: 24px; padding: 0 8px 0 4px; box-sizing: border-box;
    font-size: 13px; cursor: pointer; white-space: nowrap; border-bottom: 1px solid rgba(31,26,14,0.07);
}
.brw-row:hover { background: rgba(28,60,115,0.08); }
.brw-row.sel { background: var(--signal); color: var(--paper); }
.brw-num { width: 18px; flex: none; text-align: right; font-size: 11px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.brw-name { flex: 1 1 160px; min-width: 80px; overflow: hidden; text-overflow: ellipsis; }
.brw-row.cur .brw-name { font-weight: 700; }
.brw-row.cur .brw-num { color: var(--signal); font-weight: 700; }
.brw-cat { width: 64px; flex: none; font-size: 12px; color: var(--ink-soft); overflow: hidden; text-overflow: ellipsis; }
.brw-tags { width: 200px; flex: none; display: flex; gap: 3px; overflow: hidden; }
.brw-list.nosrc .brw-tags { width: 290px; }
.brw-src { width: 96px; flex: none; text-align: right; font-size: 11.5px; color: var(--ink-faint); overflow: hidden; text-overflow: ellipsis; }
.brw-row.sel .brw-num, .brw-row.sel .brw-cat, .brw-row.sel .brw-src { color: inherit; opacity: 0.8; }
.brw-chip {
    flex: none; height: 16px; line-height: 16px; padding: 0 6px; border-radius: 8px; font-size: 11px; cursor: pointer;
    background: rgba(31,26,14,0.08); color: var(--ink-soft);
}
.brw-chip:hover { background: rgba(28,60,115,0.2); color: var(--ink); }
.brw-chip.on { background: var(--signal); color: var(--paper); }
.brw-row.sel .brw-chip { background: rgba(236,227,196,0.22); color: var(--paper); }
.brw-row.sel .brw-chip.on { background: var(--paper); color: var(--signal); }
.brw-more { padding: 10px; text-align: center; font-size: 12.5px; color: var(--ink-faint); }
.brw-none { padding-top: 70px; display: flex; flex-direction: column; align-items: center; gap: 12px; font-size: 14px; color: var(--ink-soft); }
.brw-none .btn { position: static; }

.brw-info { width: 252px; flex: none; overflow-y: auto; padding: 0 2px 8px 4px; }
.brw-iname { margin: 1px 0 3px; font-weight: 700; font-size: 17px; line-height: 1.2; overflow-wrap: anywhere; }
.brw-isub { margin-bottom: 8px; font-size: 12px; color: var(--ink-soft); }
.brw-itags { display: flex; flex-wrap: wrap; gap: 3px; margin-bottom: 9px; }
.brw-idesc { font-size: 12.5px; line-height: 1.42; white-space: pre-wrap; user-select: text; -webkit-user-select: text; }
.brw-ihead { margin: 10px 0 2px; font-size: 11.5px; font-weight: 700; color: var(--ink-faint); }
.brw-itext { font-size: 12px; line-height: 1.35; color: var(--ink-soft); }
.brw-empty { padding-top: 20px; font-size: 12.5px; color: var(--ink-faint); }

.brw-foot { display: flex; align-items: center; gap: 8px; padding: 7px 10px 8px; }
.brw-foot .tg { position: static; height: 22px; padding: 0 8px 0 5px; }
.brw-hint { flex: 1; font-size: 11.5px; color: var(--ink-faint); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.brw-foot .btn { position: static; height: 22px; min-width: 72px; }
.brw-load { font-weight: 700; }
.brw-load.off { opacity: 0.45; pointer-events: none; }

.p:focus-visible, .btn:focus-visible, .tg:focus-visible, .cell:focus-visible, .src:focus-visible, .tgt:focus-visible, .addrow:focus-visible { outline: 2px solid var(--signal); outline-offset: 1px; }
`
