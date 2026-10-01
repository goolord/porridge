// A control grid inside a panel (or any positioned element): controls are placed by
// column and row from an origin.
//
// The layout rules, so that a control never needs a pixel offset:
// - every control fills a cell: Style.controlHeight tall, at the top of its row, and as wide
//   as the columns it spans (less a small gap), so neighbours can never overlap;
// - parameters, lists, switches and grid buttons all have that same footprint;
// - for narrower controls, make a grid with narrower columns (~cw) and give wider controls a
//   span, rather than offsetting them;
// - a cell that is already taken is reported in the console when a second control lands on it.

let columnWidth = 87. // grid column width
let rowHeight = Style.controlHeight + Style.controlGap // grid row height
let padX = 5.
let padTop = 25. // below a panel's title or tab strip
let padBottom = 6.
let gap = 6.
let columnGap = 4. // between the controls of neighbouring columns

// The panel height that fits rows of controls below the title.
let panelHeight = rows => padTop + Int.toFloat(rows) * rowHeight + padBottom

// The column width at which this many columns fill a panel this wide (borders included),
// with the same margin left and right.
let fitColumns = (panelWidth, cols) => (panelWidth - 2. - 2. * padX + columnGap) / Int.toFloat(cols)

type t = {
  ctx: Ctx.t,
  el: Dom.element,
  ox: float,
  oy: float,
  cw: float,
  // the cells taken so far, "column,row"
  taken: Set.t<string>,
}

let make = (ctx, el, ~x=padX, ~y=padTop, ~cw=columnWidth) => {
  ctx,
  el,
  ox: x,
  oy: y,
  cw,
  taken: Set.make(),
}

// The left edge of column c's cell (a pixel left of its control, for older call sites) and
// the top of row r.
let cx = (g, c) => g.ox + Int.toFloat(c) * g.cw - 1.
let cy = (g, r) => g.oy + Int.toFloat(r) * rowHeight

// controls keep a few pixels apart, so that each label reads with its own control
let controlWidth = (g, span) => Int.toFloat(span) * g.cw - columnGap

// The box a control spanning these cells fills.
let cell = (g, c, r, ~span=1, ~rows=1): Web.box => {
  x: g.ox + Int.toFloat(c) * g.cw,
  y: cy(g, r),
  w: controlWidth(g, span),
  h: Int.toFloat(rows) * rowHeight - Style.controlGap,
}

// Marks the cells as taken, and warns when one already was.
let claim = (g, c, r, ~span=1, ~rows=1, what) =>
  for i in c to c + span - 1 {
    for j in r to r + rows - 1 {
      let key = `${Int.toString(i)},${Int.toString(j)}`
      if g.taken->Set.has(key) {
        Console.warn(`Grid: ${what} overlaps another control at column ${Int.toString(i)}, row ${Int.toString(j)}`)
      }
      g.taken->Set.add(key)
    }
  }

let param = (g, id, c, r, label, ~span=1) => {
  g->claim(c, r, ~span, id)
  let b = g->cell(c, r, ~span)
  Controls.param(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label)
}

let choice = (g, id, c, r, label, ~span=1) => {
  g->claim(c, r, ~span, id)
  let b = g->cell(c, r, ~span)
  Controls.choice(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label)
}

let toggle = (g, id, c, r, label, ~span=1) => {
  g->claim(c, r, ~span, id)
  let b = g->cell(c, r, ~span)
  Controls.toggle(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label)
}

// A button filling its cells. (~w is ignored: the width comes from the span. ~dy is only
// for older call sites, and moves the button down from the top of its row.)
let button = (g, text, c, r, ~span=1, ~w as _: option<float>=?, ~status=?, ~dy=0., onClick) => {
  g->claim(c, r, ~span, text)
  let b = g->cell(c, r, ~span)
  Controls.button(
    g.ctx,
    g.el,
    text,
    ~x=b.x,
    ~y=b.y + dy,
    ~w=b.w,
    ~h=b.h,
    ~cls="gc",
    ~status?,
    onClick,
  )->ignore
}

// A note (wrapped, faint text) filling a span of cells.
let note = (g, text, c, r, ~span=1, ~rows=1) => {
  g->claim(c, r, ~span, ~rows, "a note")
  let b = g->cell(c, r, ~span, ~rows)
  let e = Web.el("div", ~cls="note wrap", ~text, ~parent=g.el)->Web.placeBox({...b, x: b.x + 2.})
  e
}

// The area of a span of cells, for plots.
let box = (g, c, r, cols, rows): Web.box => {
  x: cx(g, c) + 3.,
  y: cy(g, r) + 2.,
  w: Int.toFloat(cols) * g.cw - 8.,
  h: Int.toFloat(rows) * rowHeight - 4.,
}
