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

// Colours the canvases draw with too, as "r, g, b" for rgba (see CanvasStyle).
let edgeRgb = "111, 95, 54"
let inkRgb = "31, 26, 14"
let signalRgb = "28, 60, 115"
let paperRgb = "236, 227, 196"
let rgb = rgb => `rgb(${rgb})`
let rgba = (rgb, alpha) => `rgba(${rgb}, ${Float.toString(alpha)})`

let css = `
:host, porridge-view {
    --ground: ${groundColour};
    --panel: #b9aa7b;
    --panel-hi: #c9bc92;
    --edge: ${rgb(edgeRgb)};
    --ink: ${rgb(inkRgb)};
    --ink-soft: #4c4127;
    --ink-faint: #7a6c45;
    --signal: ${rgb(signalRgb)};
    --signal-soft: ${rgba(signalRgb, 0.22)};
    --paper: ${rgb(paperRgb)};
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
.pbody.cover { background: var(--panel); z-index: 1; border-radius: inherit; }
.blk:has(> .pbody.cover.on) > .ptabs { z-index: 2; }
.blk.responding > :not(.pbody):not(.ptabs) { visibility: hidden; }
.blk > .hdr, .pbody > .hdr { position: absolute; right: 6px; top: 1px; width: 40px; height: 18px; }

/* the FX page: a tab per effect in the order they run (the rack's are dragged sideways), and a
   page per tab */
.fxstrip { position: absolute; display: flex; align-items: center; gap: 3px; }
.fxtab {
    position: relative; display: flex; align-items: center; gap: 5px; height: 22px; padding: 0 9px; border-radius: 2px;
    font-size: 13px; font-weight: 700; white-space: nowrap; color: var(--ink-soft); cursor: pointer;
    background: var(--panel); box-shadow: inset 0 0 0 1px var(--edge);
}
.fxtab:hover { color: var(--ink); background: var(--panel-hi); }
.fxtab.on { color: var(--paper); background: var(--signal); box-shadow: none; }
.fxtab .led { width: 7px; height: 7px; border-radius: 50%; box-sizing: border-box; border: 1.5px solid var(--ink-faint); }
.fxtab .led.lit { background: var(--signal); border-color: var(--signal); }
.fxtab .led, .card .led { cursor: pointer; position: relative; }
.fxtab .led::after, .card .led::after { content: ""; position: absolute; inset: -5px; }
.fxtab .led:hover, .card .led:hover { box-shadow: 0 0 0 2px var(--panel-hi), 0 0 0 3px var(--ink-soft); }
.fxtab.on .led { border-color: var(--paper); }
.fxtab.on .led.lit { background: var(--paper); }
.fxtab .x { font-weight: 400; font-size: 14px; margin: 0 -4px 0 1px; opacity: 0; }
.fxtab:hover .x { opacity: 0.6; }
.fxtab .x:hover { opacity: 1; }
.fxtab.add { padding: 0 8px; font-size: 15px; background: transparent; box-shadow: none; border: 1.5px dashed var(--edge); height: 19px; }
.fxtab.add:hover { background: var(--panel-hi); }
.fxtab.drag { z-index: 2; cursor: grabbing; color: var(--paper); background: var(--signal); }
.fxtab.drop-before, .card.drop-before { box-shadow: inset 0 0 0 1px var(--edge), -4px 0 0 var(--signal); }
.fxtab.drop-after, .card.drop-after { box-shadow: inset 0 0 0 1px var(--edge), 4px 0 0 var(--signal); }
.fxsep { font-weight: 700; color: var(--paper); font-size: 15px; }
.fxgap { width: 10px; }
.fxbody { position: absolute; display: none; }
.fxbody.on { display: block; }

/* the routing tab: nodes, the distortion's places, and the rack's cards */
.flowsvg { left: 0; top: 0; pointer-events: none; }
.fnode, .fslot {
    position: absolute; box-sizing: border-box; border-radius: 2px; font-size: 13px; text-align: center;
    line-height: 28px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.fnode { background: var(--paper); border: 1px solid var(--edge); color: var(--ink); }
.fnode.out { line-height: normal; text-align: left; background: var(--tile); }
.fnode.end { background: transparent; border: none; font-weight: 700; text-align: left; padding-left: 4px; }
.fnode .olabel { position: absolute; left: 7px; top: 3px; font-weight: 700; font-size: 13px; }
.fslot { border: 1.5px dashed var(--edge); color: var(--ink-faint); cursor: pointer; }
.fslot:hover { background: var(--panel-hi); }
.fslot:empty::after { content: "distortion here?"; opacity: 0; }
.fslot:empty:hover::after { opacity: 1; }
.fslot.on { border: 1px solid var(--signal); background: var(--signal); color: var(--paper); font-weight: 700; }
.fslot.idle { border-style: solid; color: var(--ink-soft); }
.card {
    position: absolute; box-sizing: border-box; border-radius: 3px; background: var(--tile);
    box-shadow: inset 0 0 0 1px var(--edge);
}
.card.drag { z-index: 3; box-shadow: inset 0 0 0 1.5px var(--signal), 3px 3px 0 rgba(31,26,14,0.25); background: var(--panel-hi); }
.card .chead {
    position: absolute; left: 0; right: 0; top: 0; height: 26px; display: flex; align-items: center; gap: 6px;
    padding: 0 6px; box-sizing: border-box; cursor: grab; border-bottom: 1px solid var(--tile-edge);
}
.card .chead:hover { background: var(--panel-hi); }
.card .ctitle { flex: 1; font-weight: 700; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.card .led { flex: none; width: 8px; height: 8px; border-radius: 50%; box-sizing: border-box; border: 1.5px solid var(--ink-faint); }
.card .led.lit { background: var(--signal); border-color: var(--signal); }
.card .cx { font-weight: 400; font-size: 15px; color: var(--ink-faint); cursor: pointer; }
.card .cx:hover { color: var(--ink); }
.card .cctl { position: absolute; left: 6px; right: 6px; top: 32px; height: 56px; }
.card .csum { position: absolute; left: 7px; right: 6px; top: 92px; font-size: 11.5px; line-height: 1.4;
    color: var(--ink-soft); white-space: pre-line; overflow: hidden; }
.card.off .csum { opacity: 0.55; }
.card.compact .cctl { display: none; }
.card.compact .csum { top: 34px; }
.addcard {
    position: absolute; box-sizing: border-box; border: 1.5px dashed var(--edge); border-radius: 3px;
    display: flex; align-items: center; justify-content: center; font-size: 20px; color: var(--ink-soft); cursor: pointer;
}
.addcard:hover { background: var(--panel-hi); color: var(--ink); }
.plot path.flow { fill: none; stroke: var(--ink-soft); stroke-width: 1.5; }
.plot path.flowhead { fill: none; stroke: var(--ink-soft); stroke-width: 1.5; stroke-linejoin: round; }

/* the effects' graphs */
.plot line.stem { stroke: var(--signal); stroke-width: 1.8; }
.plot line.stem.dry { stroke: var(--ink-faint); stroke-width: 1.5; stroke-dasharray: 3 2; }
.plot circle.head { fill: var(--signal); }
.plot path.glyph { fill: var(--signal-soft); stroke: var(--signal); stroke-width: 0.9; }
.plot circle.pointed { fill: none; stroke: var(--mod); stroke-width: 1.5; }
.plot path.curve.hl { stroke: var(--mod); stroke-width: 1.6; }
.plot path.swell { fill: var(--signal-soft); stroke: var(--signal); stroke-width: 1; }
.plot line.link { stroke: var(--signal); stroke-width: 1; stroke-dasharray: 2 3; opacity: 0.7; }
.plot line.marker { stroke: var(--mod); stroke-width: 1.2; stroke-dasharray: 4 3; }
.plot text.clip { font-size: 8px; fill: var(--mod); }
.plot text.lane { font-size: 13px; font-weight: 700; fill: var(--ink-soft); }
.plot text.curvelabel { fill: var(--ink-soft); }
.plot path.env { fill: var(--signal-soft); stroke: var(--signal); stroke-width: 1; stroke-linejoin: round; }
.plot path.tail { fill: var(--signal-soft); stroke: var(--signal); stroke-width: 1.3; stroke-linejoin: round; }
.plot path.hit { fill: var(--ink-soft); }
.plot line.bracket { stroke: var(--ink-faint); stroke-width: 1; }
.plot text.note { font-size: 11px; fill: var(--ink-soft); }
.plot text.note.big { font-size: 13px; font-weight: 700; fill: var(--ink); }
.plot rect.room { fill: var(--paper); fill-opacity: 0.5; stroke: var(--ink-soft); stroke-width: 1.5; }
.plot path.ray { fill: none; stroke: var(--signal); stroke-width: 1; }
.plot circle.source { fill: var(--mod); }
.plot circle.listener { fill: var(--ink); }
.plot path.decay { fill: none; stroke: var(--ink); stroke-width: 1.2; stroke-dasharray: 5 3; }
.plot path.wave { fill: none; stroke: var(--signal); stroke-width: 1; }
.plot rect.band { fill: var(--signal-soft); stroke: none; }
.plot line.edge { stroke: var(--signal); stroke-width: 1.2; }
.plot circle.voice { fill: var(--signal); fill-opacity: 0.75; stroke: var(--paper); stroke-width: 1; }
.plot circle.dry { fill: none; stroke: var(--ink-soft); stroke-width: 1.5; stroke-dasharray: 2 2; }
.plot rect.dline { fill: var(--paper); stroke: var(--edge); }
.plot text.dlabel { font-size: 11px; fill: var(--ink); }
.plot circle.dial { fill: none; stroke: var(--edge); stroke-dasharray: 2 2; }
.plot line.needle { stroke: var(--ink); stroke-width: 1.5; }
.ed .plot path.flow { stroke: var(--signal); stroke-width: 1.5; opacity: 0.85; }
.ed .plot path.flow.neg { stroke-dasharray: 3 2; }
.ed .plot path.flowhead { stroke: var(--signal); }
.ed .plot path.flow.none, .ed .plot path.flowhead.none { opacity: 0.12; }
.ed .node.faint { fill: var(--panel); stroke: var(--ink-faint); }
.ed .node.faint.hot { fill: var(--ink-faint); }

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
.btn.withicon { display: flex; align-items: center; justify-content: center; gap: 5px; }
.btn.withicon > span { overflow: hidden; text-overflow: ellipsis; }

.plot { position: absolute; display: block; }
.plot path.curve { fill: none; stroke: var(--signal); stroke-width: 1.4; }
.plot path.fill { fill: var(--signal-soft); stroke: none; }
.plot path.axis, .plot line.axis { stroke: rgba(31,26,14,0.28); stroke-width: 1; fill: none; }
.plot.off { opacity: 0.4; }
.plot.mini { cursor: pointer; }
.plot path.curve.depth { stroke: var(--mod); stroke-width: 1.2; stroke-dasharray: 4 3; }
.plot text.tick.depth { fill: var(--mod); }
.plot.mini line.mark { stroke-dasharray: 2 2; stroke-width: 1; }
.plot.mini:hover rect.bg { stroke: var(--signal); }
.plot rect.bg { fill: rgba(236, 227, 196, 0.35); stroke: var(--edge); stroke-width: 1; }
.plot path.curve.faint { stroke-width: 1; stroke-dasharray: 3 2; opacity: 0.7; }
.plot path.curve.dim { stroke-width: 1; opacity: 0.45; }
.plot path.curve.fill { fill: var(--signal-soft); stroke-width: 1; }
.plot line.grid { stroke: rgba(31,26,14,0.1); stroke-width: 1; }
.plot line.mark { stroke: var(--ink-faint); stroke-width: 1.2; stroke-dasharray: 3 3; }
.plot line.curve { stroke: var(--signal); stroke-width: 2; }
.plot line.curve.alt { stroke: var(--mod); }
.plot circle.dot { fill: var(--signal); }
.plot rect.compzone { fill: var(--signal-soft); opacity: 0.5; }
.plot rect.complevel { fill: var(--signal); opacity: 0.75; }
.plot rect.compgain { fill: var(--mod); }
.plot rect.compgain.up { fill: #3f7a3a; }
.plot line.compthresh { stroke: var(--signal); stroke-width: 1.5; }
.plot text.readout { font-size: 11px; font-weight: 700; fill: var(--signal); }
.blk.resting .ed, .blk.resting .p { opacity: 0.4; }
.plot.bigknob { cursor: ns-resize; }
.plot path.knobtrack { fill: none; stroke: rgba(31,26,14,0.15); stroke-width: 9; stroke-linecap: round; }
.plot path.knobfill { fill: none; stroke: var(--signal); stroke-width: 9; stroke-linecap: round; }
.plot circle.knobcap { fill: var(--paper); stroke: var(--edge); stroke-width: 1.5; }
.plot line.knobpointer { stroke: var(--ink); stroke-width: 3; stroke-linecap: round; }
.plot text.knobvalue { font-size: 18px; font-weight: 700; fill: var(--ink); }
.grp.center { text-align: center; }
.plot path.impulse { fill: none; stroke: var(--signal); stroke-width: 1; }
.plot path.front { fill: none; stroke: var(--signal); stroke-width: 1.4; }
.plot path.front.bright { stroke-width: 0.9; }
.plot path.front.dull { stroke-width: 3; stroke-opacity: 0.6; }
.plot path.room { fill: var(--paper); fill-opacity: 0.5; stroke: var(--ink-soft); stroke-width: 2; }
.plot path.plate { fill: rgba(150, 160, 170, 0.35); stroke: var(--ink-soft); stroke-width: 1.5; }
.plot path.spring { fill: none; stroke: var(--ink-faint); stroke-width: 1.2; stroke-dasharray: 2 1.5; }
.plot path.basin { fill: rgba(28, 60, 115, 0.12); stroke: var(--ink-soft); stroke-width: 2; }
.plot path.unit { fill: rgba(31, 26, 14, 0.75); stroke: var(--edge); }
.plot path.display { fill: #1d2a1a; stroke: #46563a; }
.plot path.pixel { fill: #3b5a2c; }
.plot path.pixel.lit { fill: #9fdc6a; }
.plot text.lcd { font-size: 12px; font-family: monospace; fill: #9fdc6a; }
.plot path.hallray { fill: none; stroke: var(--mod); stroke-width: 1; stroke-dasharray: 3 2; }
.plot circle.spark { fill: var(--signal); }
.plot circle.spark.dull { fill: var(--ink-soft); }
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
/* a full header doesn't squeeze the buttons (their labels would wrap out of them): the program name gives way instead */
.pv-head .btn { position: static; height: 22px; flex-shrink: 0; white-space: nowrap; }
.pv-head .pages { display: flex; }
.pv-head .pages .btn { border-radius: 0; margin-left: -1px; min-width: 64px; font-size: 13px; }
.pv-head .pages .btn:first-child { border-radius: 2px 0 0 2px; }
.pv-head .pages .btn:last-child { border-radius: 0 2px 2px 0; }
.pv-head .spacer { flex: 1; }
.pv-head .prog { display: flex; align-items: center; gap: 3px; min-width: 0; }
.pv-head .prog .name {
    width: 200px; min-width: 0; height: 20px; line-height: 20px; padding: 0 6px; border: 1px solid var(--edge); background: var(--paper);
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
    position: absolute; z-index: 70; background: var(--paper); border: 1px solid var(--ink);
    padding: 2px 0; font-size: 12.5px; max-height: 560px; overflow-y: auto; min-width: 120px;
    box-shadow: 2px 2px 0 rgba(31,26,14,0.35);
}
.menu div { padding: 2px 12px 2px 10px; white-space: nowrap; cursor: pointer; }
.menu div:hover { background: var(--signal); color: var(--paper); }
.menu div.cur { font-weight: 700; }
.menu.cols { column-gap: 0; }
.menu.cols div { break-inside: avoid; }
.menu div.mh { padding: 4px 12px 1px 10px; font-size: 11px; color: var(--ink-faint); cursor: default;
    text-transform: uppercase; letter-spacing: 0.06em; }
.menu div.mh:hover { background: none; color: var(--ink-faint); }
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
.tgt.first { box-shadow: inset 0 0 0 1.5px var(--signal); }
.grp { position: absolute; font-size: 12px; font-weight: 700; line-height: 20px; color: var(--ink-faint); white-space: nowrap; }
.mcount { position: absolute; right: 9px; top: 4px; font-size: 12px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.picker { display: none; z-index: 20; border-color: var(--signal); box-shadow: 3px 3px 0 rgba(31,26,14,0.3); }
.picker.on { display: block; }
.picker .btn { z-index: 1; }
.picker > .ttl { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
/* the picker's targets, under its title row: they scroll when they don't all fit */
.picks { position: absolute; left: 0; right: 0; bottom: 0; overflow-x: hidden; overflow-y: auto; }
.psearch {
    position: absolute; z-index: 1; height: 20px; box-sizing: border-box; padding: 0 7px; border: 1px solid var(--edge); border-radius: 2px;
    font: inherit; font-size: 12.5px; color: var(--ink); background: var(--paper); outline: none;
}
.psearch:focus { border-color: var(--signal); }
.psearch::placeholder { color: var(--ink-faint); }
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
.brw ::-webkit-scrollbar, .picks::-webkit-scrollbar { width: 9px; }
.brw ::-webkit-scrollbar-thumb, .picks::-webkit-scrollbar-thumb { background: rgba(111,95,54,0.45); border-radius: 4px; border: 2px solid transparent; background-clip: padding-box; }
.brw ::-webkit-scrollbar-track, .picks::-webkit-scrollbar-track { background: transparent; }
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
.brw-addfolder { display: block; box-sizing: border-box; width: calc(100% - 12px); margin: 2px 6px 4px; height: 22px;
  font-size: 12px; }
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

/* the sound matcher's drawer (MatchDrawer.res): the sample and the locks, then four cards */
.mt {
    position: absolute; left: 0; right: 0; bottom: ${px(statusHeight)}; height: 236px; z-index: 60;
    box-sizing: border-box; display: flex; flex-direction: column;
    background: var(--panel); border-top: 1px solid var(--ink); box-shadow: 0 -3px 0 rgba(31,26,14,0.16);
    transform: translateY(calc(100% + 30px)); visibility: hidden; transition: transform 0.18s ease-out, visibility 0s 0.18s;
}
.mt.on { transform: none; visibility: visible; transition: transform 0.18s ease-out; }
.mt-head { display: flex; align-items: center; gap: 7px; height: 36px; padding: 0 8px 0 10px; flex: none; }
.mt-head .btn { position: static; height: 22px; white-space: nowrap; }
.mt-head .btn.icon { width: 24px; padding: 0; font-size: 15px; line-height: 19px; }
.mt-head .btn.hidden, .mt:not(.loaded) .mt-loaded { display: none; }
.mt-head .spacer { flex: 1; }
.mt-title { font-weight: 700; font-size: 15px; white-space: nowrap; margin-right: 4px; }
.mt-target { display: none; align-items: center; gap: 7px; height: 28px; padding: 0 9px 0 4px; border-radius: 2px; cursor: pointer;
    min-width: 0; max-width: 340px; background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.mt.loaded .mt-target { display: flex; }
.mt-target:hover { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
.mt-wave { flex: none; display: block; }
.mt-tnames { min-width: 0; line-height: 1.12; }
.mt-tname { font-size: 12.5px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mt-tinfo { font-size: 11px; color: var(--ink-soft); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mt-locklabel { font-size: 12px; color: var(--ink-soft); white-space: nowrap; }
.mt-locklabel.off { color: var(--ink-faint); }
.mt-locks { display: flex; gap: 2px; }
.mt-lock { display: flex; align-items: center; gap: 3px; height: 20px; padding: 0 6px 0 4px; border-radius: 2px; font-size: 12px; cursor: pointer;
    color: var(--ink-soft); background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.mt-lock .ic { height: 11px; opacity: 0.4; }
.mt-lock:hover { background: var(--panel-hi); color: var(--ink); }
.mt-lock.on { background: var(--signal); color: var(--paper); box-shadow: none; }
.mt-lock.on .ic { opacity: 1; }
.mt-lock.off { opacity: 0.45; cursor: default; }
.mt-lock.off:hover { background: var(--tile); color: var(--ink-soft); }
.mt-bar { height: 2px; flex: none; margin: 0 10px; background: rgba(31,26,14,0.1); visibility: hidden; }
.mt-bar.on { visibility: visible; }
.mt-bar > div { height: 100%; width: 0; background: var(--signal); transition: width 0.25s linear; }
.mt-crumbs { display: none; align-items: center; gap: 6px; height: 18px; padding: 4px 12px 0; font-size: 12px; color: var(--ink-soft);
    flex: none; white-space: nowrap; overflow: hidden; }
.mt-crumbs.on { display: flex; }
.mt-crumb { cursor: pointer; }
.mt-crumb:hover { color: var(--ink); text-decoration: underline; }
.mt-crumb.on { cursor: default; font-weight: 700; color: var(--ink); text-decoration: none; }
.mt-sep { color: var(--ink-faint); }
.mt-cards { flex: 1; min-height: 0; display: none; gap: 8px; padding: 8px 10px 10px; }
.mt.loaded .mt-cards { display: flex; }
.mt-card { flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; gap: 5px; padding: 6px 8px 8px; box-sizing: border-box;
    border-radius: 3px; cursor: pointer; background: var(--panel-hi); border: 1px solid var(--edge); }
.mt-card:hover { border-color: var(--ink); }
.mt-card.live { border-color: var(--signal); box-shadow: 0 0 0 1.5px var(--signal); }
.mt-card.kept { border-color: var(--ink); box-shadow: 0 0 0 1.5px var(--ink); }
.mt-card.empty { cursor: default; background: var(--panel); border-style: dashed; }
.mt-ctop { display: flex; align-items: center; gap: 6px; height: 22px; }
.mt-ctitle { font-weight: 700; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mt-badge { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; line-height: 14px; color: var(--paper);
    background: var(--signal); border-radius: 2px; padding: 0 4px; }
.mt-badge:empty, .mt-best:empty { display: none; }
.mt-best { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; line-height: 12px; color: var(--signal);
    border: 1px solid var(--signal); border-radius: 2px; padding: 0 3px; }
.mt-card.kept .mt-badge { background: var(--ink); }
.mt-score { margin-left: auto; font-size: 20px; font-weight: 700; font-variant-numeric: tabular-nums; color: var(--signal); }
.mt-card.empty .mt-score { color: var(--ink-faint); animation: mt-pulse 1.1s ease-in-out infinite; }
@keyframes mt-pulse { 50% { opacity: 0.3; } }
.mt-pic { display: block; border-radius: 2px; }
.mt-desc { font-size: 12px; line-height: 15px; height: 30px; color: var(--ink-soft); overflow: hidden;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.mt-cbtns { display: flex; gap: 4px; margin-top: auto; }
.mt-cbtns .btn { position: static; flex: 1; height: 22px; }
.mt-card.empty .mt-cbtns { visibility: hidden; }
.mt-empty { display: flex; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 8px; margin: 6px 14px 14px;
    padding: 0 150px; text-align: center; border: 1.5px dashed var(--edge); border-radius: 3px; font-size: 12.5px; line-height: 1.4;
    color: var(--ink-soft); cursor: pointer; }
.mt-empty:hover { background: var(--panel-hi); }
.mt-empty .big { font-size: 17px; font-weight: 700; color: var(--ink); }
.mt-empty .btn { position: static; height: 22px; }
.mt.loaded .mt-empty { display: none; }

/* a sample dragged over the window: match it, or make a shape of it (by the half it's dropped on) */
.drop .dz { display: none; }
.drop:not(.sample) .dz.only { display: block; }
.drop.sample .dz:not(.only) { display: flex; flex: 1; align-self: stretch; flex-direction: column; align-items: center; justify-content: center; gap: 6px; }
.drop.sample:not(.split) .dz:last-child { display: none; }
.drop.split .dz:last-child { border-left: 2px dashed rgba(236, 227, 196, 0.55); }
.drop.split .dz.hot { background: rgba(28, 60, 115, 0.4); }
.dz b { font-size: 22px; }
.dz span { font-size: 13px; font-weight: 400; max-width: 380px; text-align: center; opacity: 0.92; }
`
