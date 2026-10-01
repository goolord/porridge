// A control grid inside a panel (or any positioned element): controls are placed by
// column and row from an origin.

let columnWidth = 87. // grid column width
let rowHeight = 28. // grid row height
let padX = 5.
let padTop = 25. // below a panel's title or tab strip
let padBottom = 6.
let gap = 6.

// The panel height that fits rows of controls below the title.
let panelHeight = rows => padTop + Int.toFloat(rows) * rowHeight + padBottom

type t = {
  ctx: Ctx.t,
  el: Dom.element,
  ox: float,
  oy: float,
  cw: float,
}

let make = (ctx, el, ~x=padX, ~y=padTop, ~cw=columnWidth) => {ctx, el, ox: x, oy: y, cw}

let cx = (g, c) => g.ox + Int.toFloat(c) * g.cw - 1.
let cy = (g, r) => g.oy + Int.toFloat(r) * rowHeight

// controls keep a few pixels apart, so that each label reads with its own control
let controlWidth = (g, span) => Int.toFloat(span) * g.cw - 4.

let param = (g, id, c, r, label, ~span=1) =>
  Controls.param(g.ctx, g.el, id, ~x=cx(g, c) + 1., ~y=cy(g, r), ~w=controlWidth(g, span), ~label)

let choice = (g, id, c, r, label, ~span=1) =>
  Controls.choice(
    g.ctx,
    g.el,
    id,
    ~x=cx(g, c) + 1.,
    ~y=cy(g, r),
    ~w=controlWidth(g, span),
    ~label,
  )

let toggle = (g, id, c, r, label, ~dy=5.) =>
  Controls.toggle(g.ctx, g.el, id, ~x=cx(g, c) + 3., ~y=cy(g, r) + dy, ~label)

let button = (g, text, c, r, ~w, ~status, ~dy=3., onClick) =>
  Controls.button(g.ctx, g.el, text, ~x=cx(g, c) + 3., ~y=cy(g, r) + dy, ~w, ~status, onClick)->ignore

// The area of a span of cells, for plots.
let box = (g, c, r, cols, rows): Web.box => {
  x: cx(g, c) + 3.,
  y: cy(g, r) + 2.,
  w: Int.toFloat(cols) * g.cw - 8.,
  h: Int.toFloat(rows) * rowHeight - 4.,
}
