// What the graphical editors (envelopes, EQ) share: a plot with points to drag, a readout
// beside a point, the editor's hint in the status line while the pointer is over it, and a
// "values" switch that swaps the plot for the raw parameter fields.
//
// An editor refreshes (refits and redraws) at most once a frame, however many of its
// parameters change.

open! Web

type t = {
  ctx: Ctx.t,
  box: box,
  hint: string,
  root: element,
  svg: element,
  // the raw parameter fields
  values: Grid.t,
  // the point under the pointer, and the one being dragged
  mutable hover: option<int>,
  mutable dragging: option<int>,
  mutable refresh: unit => unit,
  mutable pending: bool,
}

// columns: of the raw parameter fields
let make = (ctx: Ctx.t, parent, box: box, ~hint, ~columns) => {
  let root = el("div", ~cls="ed", ~parent)->placeBox(box)
  let area = {x: 0., y: 0., w: box.w, h: box.h}
  let svg = Plots.svg(root, area)
  Plots.background(svg, area)
  let vals = el("div", ~cls="vals", ~parent=root)
  let values = Grid.make(ctx, vals, ~x=0., ~y=22., ~cw=box.w / Int.toFloat(columns))
  Controls.expandSwitch(ctx, root)
  let t = {
    ctx,
    box,
    hint,
    root,
    svg,
    values,
    hover: None,
    dragging: None,
    refresh: () => (),
    pending: false,
  }
  svg->suppressContextMenu
  svg->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  svg->onMouse(#mouseleave, _ =>
    if t.dragging == None {
      ctx.status->Status.clear
    }
  )
  t
}

// Refreshes in the next frame.
let schedule = t =>
  if !t.pending {
    t.pending = true
    requestAnimationFrame(_ => {
      t.pending = false
      t.refresh()
    })
  }

// Refreshes the editor now, and whenever one of these parameters changes.
let start = (t, ids, refresh) => {
  t.refresh = refresh
  ids->Array.forEach(id => t.ctx.model->ParamModel.listen(id, () => schedule(t)))
  refresh()
}

// The point being dragged, or else the one under the pointer.
let focus = t => t.dragging->Option.orElse(t.hover)

let showHint = t => t.ctx.status->Status.show(t.hint)

// Hovering over point i's hit area.
let hookNode = (t, hit, i) => {
  hit->onMouse(#mouseenter, _ => {
    t.hover = Some(i)
    schedule(t)
  })
  hit->onMouse(#mouseleave, _ => {
    t.hover = None
    schedule(t)
    if t.dragging == None {
      showHint(t)
    }
  })
}

// Drags point i by its hit area, as one gesture on the parameters ids: onMove gets how far
// each move went, in design pixels (a tenth of that with shift).
let drag = (t, i, hit, ev, ~ids, ~onMove) => {
  let model = t.ctx.model
  t.dragging = Some(i)
  ids->Array.forEach(id => model->ParamModel.beginGesture(id))
  Controls.dragBy(
    t.ctx,
    hit,
    ev,
    ~onMove=(dx, dy, mv) => {
      let f = mv->shiftKey ? Controls.fineShift : 1.
      onMove(dx * f, dy * f)
    },
    ~onUp=() => {
      ids->Array.forEach(id => model->ParamModel.endGesture(id))
      t.dragging = None
      schedule(t)
      if t.hover == None {
        showHint(t)
      }
    },
  )
  schedule(t)
}

// Shows text beside the point (x, y): dx to its right on the left of the plot (left of it
// on the right), above it by `above`, or below it by `below` when it is within nearTop of
// the top.
let showReadout = (t, readout, text, (x: float, y: float), ~dx, ~above, ~below, ~nearTop) => {
  let leftHalf = x < t.box.w * 0.6
  readout->setTextContent(text)
  readout->setAttribute("x", Num(leftHalf ? x + dx : x - dx))
  readout->setAttribute("y", Num(y < nearTop ? y + below : y - above))
  readout->setAttribute("text-anchor", Str(leftHalf ? "start" : "end"))
}
