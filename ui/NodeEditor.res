// What the graphical editors (envelopes, EQ) share: a graph (FxGraph) with points to drag, a
// readout beside a point, the editor's hint in the status line while the pointer is over it, and
// a "values" switch that swaps the plot for the raw parameter fields.
//
// An editor refreshes (refits and redraws) at most once a frame, however many of its
// parameters change, also while it is hidden.

open! Web

type t = {
  g: FxGraph.t,
  // the raw parameter fields
  values: Grid.t,
  // the point under the pointer, and the one being dragged
  mutable hover: option<int>,
  mutable dragging: option<int>,
  refresh: ref<unit => unit>,
  // refreshes in the next frame
  schedule: unit => unit,
}

// columns: of the raw parameter fields
let make = (ctx: Ctx.t, parent, box: box, ~hint, ~columns) => {
  let g = FxGraph.make(ctx, parent, box, ~hint)
  let vals = el("div", ~cls="vals", ~parent=g.root)
  let values = Grid.make(ctx, vals, ~x=0., ~y=22., ~cw=box.w / Int.toFloat(columns))
  // (search shows the values to reach one of them)
  Reach.place(vals, "", Controls.expandSwitch(ctx, g.root))
  let refresh = ref(() => ())
  {g, values, hover: None, dragging: None, refresh, schedule: perFrame(() => refresh.contents())}
}

// Refreshes the editor now, and whenever one of these parameters changes.
let start = (t, ids, refresh) => {
  t.refresh := refresh
  t.g.ctx.model->ParamModel.listenEach(ids, t.schedule)
  refresh()
}

// The point being dragged, or else the one under the pointer.
let focus = t => t.dragging->Option.orElse(t.hover)

let showHint = t => t.g.hint->Option.forEach(hint => t.g.ctx.status->Status.show(hint))

// Drags point i by its hit area, as one gesture on the parameters ids: onMove gets how far
// each move went, in design pixels (a tenth of that with shift).
let drag = (t, i, hit, ev, ~ids, ~onMove) => {
  let model = t.g.ctx.model
  t.dragging = Some(i)
  t.g.dragging = true
  ids->Array.forEach(id => model->ParamModel.beginGesture(id))
  Controls.dragBy(
    t.g.ctx,
    hit,
    ev,
    ~onMove=(dx, dy, mv) => {
      let f = mv->shiftKey ? Controls.fineShift : 1.
      onMove(dx * f, dy * f)
    },
    ~onUp=() => {
      ids->Array.forEach(id => model->ParamModel.endGesture(id))
      t.dragging = None
      t.g.dragging = false
      t.schedule()
      if t.hover == None {
        showHint(t)
      }
    },
  )
  t.schedule()
}

// Point i: a dot (these attributes) in the graph's layer, with a hit area above every dot, and
// around it what moves the parameters ids() gives (Modulators; r: the dot's largest radius). A
// press drags it (onDrag gets the hit area and the event), the right button calls onRightClick,
// and the wheel scrolls the parameter wheel() gives.
type node = {dot: element, hit: element, mods: Modulators.dots}

let node = (t, i, ~dot, ~hitR, ~cursor, ~onDrag, ~onRightClick, ~wheel: unit => option<string>, ~ids, ~r) => {
  let mods = Modulators.dotsFor(t.g.ctx.model, t.g.layer, ids, ~r)
  let dot = svgEl(t.g.layer, "circle", dot)
  let hit = svgEl(
    t.g.hits,
    "circle",
    [("class", Str("hit")), ("r", Num(hitR)), ("style", Str("cursor:" ++ cursor))],
  )
  // (before the press below, which the second right-click of a double one never reaches)
  Controls.hostMenuFor(t.g.ctx, hit, ids)
  hit->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 0 => onDrag(hit, ev)
    | 2 => onRightClick()
    | _ => ()
    }
  })
  hit->onMouse(#mouseenter, _ => {
    t.hover = Some(i)
    t.schedule()
  })
  hit->onMouse(#mouseleave, _ => {
    t.hover = None
    t.schedule()
    if t.dragging == None {
      showHint(t)
    }
  })
  hit->onWheel(ev => wheel()->Option.forEach(id => Controls.wheelParam(t.g.ctx.model, id, ev)))
  {dot, hit, mods}
}

// Puts the point at (x, y), shown or not.
let place = (n, x, y, ~shown=true) => {
  [n.dot, n.hit]->Array.forEach(e => {
    e->setAttribute("cx", Num(x))
    e->setAttribute("cy", Num(y))
    e->setAttribute("display", Str(shown ? "inline" : "none"))
  })
  Modulators.placeDots(n.mods, x, y, ~shown)
}
