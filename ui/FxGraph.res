// What the FX page's graphs share: an SVG area, points to drag (each bound to parameters),
// axis ticks, and redraws that wait for the next frame and skip hidden tabs.

open! Web

type t = {
  ctx: Ctx.t,
  root: element,
  svg: element,
  w: float,
  h: float,
}

let make = (ctx, parent, box: box) => {
  let root = el("div", ~cls="ed", ~parent)->placeBox(box)
  let area = {x: 0., y: 0., w: box.w, h: box.h}
  let svg = Plots.svg(root, area)
  Plots.background(svg, area)
  svg->suppressContextMenu
  {ctx, root, svg, w: box.w, h: box.h}
}

let group = (parent, ~cls="") => Plots.svgEl(parent, "g", cls == "" ? [] : [("class", Str(cls))])

let line = (parent, ~cls, x1, y1, x2, y2) =>
  Plots.svgEl(
    parent,
    "line",
    [("class", Str(cls)), ("x1", Num(x1)), ("y1", Num(y1)), ("x2", Num(x2)), ("y2", Num(y2))],
  )->ignore

let text = (parent, ~cls="tick", ~anchor="start", x, y, s) =>
  Plots.svgEl(
    parent,
    "text",
    [("class", Str(cls)), ("x", Num(x)), ("y", Num(y)), ("text-anchor", Str(anchor))],
  )->setTextContent(s)

let path = (parent, ~cls) => Plots.svgEl(parent, "path", [("class", Str(cls))])

let setPath = (e, d) => e->setAttribute("d", Str(d))

// Whether the graph is on screen (its tab is shown).
let shown = g => g.root->offsetParent->Option.isSome

// A redraw at the next frame, once however often it is asked for; nothing while hidden (the
// page calls `now` when the tab is shown).
type redraw = {request: unit => unit, now: unit => unit}

let redraw = (g, draw) => {
  let pending = ref(false)
  let now = () => {
    pending := false
    draw()
  }
  {
    request: () =>
      if !pending.contents && shown(g) {
        pending := true
        requestAnimationFrame(_ => if pending.contents {
          now()
        })
      },
    now,
  }
}

// Calls fn whenever one of these parameters changes.
let listen = (g, ids, fn) => ids->Array.forEach(id => g.ctx.model->ParamModel.listen(id, fn))

let get = (g, id) => g.ctx.model->ParamModel.get(id)
let set = (g, id, x) => g.ctx.model->ParamModel.set(id, x)
let def = (g, id) => g.ctx.model->ParamModel.def(id)

// A parameter's knob position, and setting it from one.
let norm = (g, id) => def(g, id).toNorm(get(g, id))
let setNorm = (g, id, n) => set(g, id, def(g, id).fromNorm(FxDsp.clamp(n, 0., 1.)))

let short = (g, id) => def(g, id).shortText(get(g, id))

//==============================================================================
// Points to drag

type handle = {
  dot: element,
  hit: element,
  mutable x: float,
  mutable y: float,
  mutable visible: bool,
}

// A point, drawn in `layer` with its hit area in `hits` (so that hit areas stay above every
// drawing). Dragging calls drag with the distance moved so far, in graph pixels (a tenth with
// shift), between gestures on its parameters; right-click puts them back to their defaults;
// the wheel nudges them.
let handle = (
  g,
  ~layer,
  ~hits,
  ~cls="node",
  ~r=6.,
  ~cursor="move",
  ~ids: array<string>,
  ~drag: ((float, float)) => unit,
  ~start=() => (),
  ~finish=() => (),
  ~wheel: option<float => unit>=?,
  ~rightClick: option<unit => unit>=?,
  ~hover: bool => unit,
) => {
  let dot = Plots.svgEl(layer, "circle", [("class", Str(cls)), ("r", Num(r))])
  let hit = Plots.svgEl(
    hits,
    "circle",
    [("class", Str("hit")), ("r", Num(r + 5.)), ("style", Str("cursor:" ++ cursor))],
  )
  let h = {dot, hit, x: 0., y: 0., visible: true}
  let model = g.ctx.model
  hit->onPointer(#pointerdown, ev => {
    ev->preventDefault
    // not a press on the graph behind it too
    ev->stopPropagation
    switch ev->button {
    | 0 =>
      ids->Array.forEach(id => model->ParamModel.beginGesture(id))
      start()
      let k = g.w / (g.svg->getBoundingClientRect).width
      let last = ref((ev->clientX, ev->clientY))
      let moved = ref((0., 0.))
      hit->Controls.capturePointer(
        ev,
        ~onMove=mv => {
          let (lx, ly) = last.contents
          last := (mv->clientX, mv->clientY)
          let f = mv->shiftKey ? 0.1 * k : k
          let (mx, my) = moved.contents
          moved := (mx + (mv->clientX - lx) * f, my + (mv->clientY - ly) * f)
          drag(moved.contents)
        },
        ~onUp=() => {
          ids->Array.forEach(id => model->ParamModel.endGesture(id))
          finish()
        },
      )
    | 2 =>
      switch rightClick {
      | Some(fn) => fn()
      | None => ids->Array.forEach(id => model->ParamModel.gestureSet(id, def(g, id).init))
      }
    | _ => ()
    }
  })
  wheel->Option.forEach(fn =>
    hit->onWheel(ev => {
      ev->preventDefault
      let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
      ids->Array.forEach(id => model->ParamModel.beginGesture(id))
      fn(ev->shiftKey ? d * 0.1 : d)
      ids->Array.forEach(id => model->ParamModel.endGesture(id))
    })
  )
  hit->onMouse(#mouseenter, _ => hover(true))
  hit->onMouse(#mouseleave, _ => hover(false))
  h
}

let place = (h, x, y) => {
  h.x = x
  h.y = y
  [h.dot, h.hit]->Array.forEach(e => {
    e->setAttribute("cx", Num(x))
    e->setAttribute("cy", Num(y))
  })
}

let show = (h, on) => {
  h.visible = on
  [h.dot, h.hit]->Array.forEach(e => e->setStyle("display", on ? "" : "none"))
}

let setClass = (h, cls) => h.dot->setAttribute("class", Str(cls))

// A label beside a point, kept inside the graph.
let readout = (g, e, ~x, ~y, s) => {
  let leftHalf = x < g.w * 0.6
  e->setTextContent(s)
  e->setAttribute("x", Num(leftHalf ? x + 12. : x - 12.))
  e->setAttribute("y", Num(y < 30. ? y + 22. : y - 10.))
  e->setAttribute("text-anchor", Str(leftHalf ? "start" : "end"))
}

//==============================================================================
// Axes

// A round step that puts about `count` ticks across `span`.
let niceStep = (span: float, count: float) => {
  let raw = span / count
  let p = Math.pow(10., ~exp=Math.floor(Math.log10(raw)))
  let m = raw / p
  p * (m < 1.5 ? 1. : m < 3.5 ? 2. : m < 7.5 ? 5. : 10.)
}

// Times in ms, as text.
let msText = (ms: float) =>
  Math.abs(ms) >= 1000.
    ? Float.toString(Math.round(ms / 10.) / 100.) ++ " s"
    : Math.abs(ms) >= 100.
    ? Float.toString(Math.round(ms)) ++ " ms"
    : Float.toString(Math.round(ms * 10.) / 10.) ++ " ms"

let hzText = (hz: float) =>
  hz >= 1000. ? Float.toFixed(hz / 1000., ~digits=hz >= 10000. ? 1 : 2) ++ " kHz" : Float.toFixed(hz, ~digits=0) ++ " Hz"

let dbText = (db: float) => (db > 0. ? "+" : "") ++ Float.toFixed(db, ~digits=1) ++ " dB"

let gainDb = (x: float) => x <= 0. ? -120. : 20. * Math.log10(x)
