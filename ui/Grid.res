// A block with a control grid: controls are placed by column and row.

let columnWidth = 74. // grid column width
let rowHeight = 28. // grid row height
let padX = 5.
let padTop = 17.
let padBottom = 4.
let gap = 6.

let blockWidth = cols => Int.toFloat(cols) * columnWidth + 2. * padX
let blockHeight = rows => padTop + Int.toFloat(rows) * rowHeight + padBottom

type t = {
  ctx: Ctx.t,
  el: Dom.element,
  x: float,
  y: float,
  w: float,
  mutable h: float,
  cw: float,
}

let make = (ctx, parent, title, ~x, ~y, ~cols, ~rows, ~cw=columnWidth, ~w=?, ~h=?) => {
  let w = w->Option.getOr(Int.toFloat(cols) * cw + 2. * padX)
  let h = h->Option.getOr(blockHeight(rows))
  {ctx, el: Controls.block(parent, title, ~x, ~y, ~w, ~h), x, y, w, h, cw}
}

let cx = (g, c) => padX + Int.toFloat(c) * g.cw - 1.
let cy = r => padTop + Int.toFloat(r) * rowHeight

let param = (g, id, c, r, label, ~span=1) =>
  Controls.param(g.ctx, g.el, id, ~x=cx(g, c), ~y=cy(r), ~w=Int.toFloat(span) * g.cw - 2., ~label)

let choice = (g, id, c, r, label, ~span=1) =>
  Controls.choice(g.ctx, g.el, id, ~x=cx(g, c), ~y=cy(r), ~w=Int.toFloat(span) * g.cw - 2., ~label)

let toggle = (g, id, c, r, label, ~dy=5.) =>
  Controls.toggle(g.ctx, g.el, id, ~x=cx(g, c) + 3., ~y=cy(r) + dy, ~label)

let button = (g, text, c, r, ~w, ~status, ~dy=3., onClick) =>
  Controls.button(g.ctx, g.el, text, ~x=cx(g, c) + 3., ~y=cy(r) + dy, ~w, ~status, onClick)->ignore

// The area of a span of cells, for plots.
let box = (g, c, r, cols, rows): Web.box => {
  x: cx(g, c) + 3.,
  y: cy(r) + 2.,
  w: Int.toFloat(cols) * g.cw - 8.,
  h: Int.toFloat(rows) * rowHeight - 4.,
}

let bottom = g => g.y + g.h + gap
let right = g => g.x + g.w + gap

// Extend the block down so that its bottom edge sits one gap above y.
let stretchTo = (g, y) => {
  g.h = Math.max(g.h, y - gap - g.y)
  g.el->Web.setStyle("height", Web.px(g.h))
}
