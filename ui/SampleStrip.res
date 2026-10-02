// The sample a shape was made from, shown above the drawing on the Shapes page: its name,
// where the shape came from, and (for a recording or a wavetable) an overview of the sample
// to click or drag along, which measures another part of it or picks another frame.

open! Web

let overviewWidth = 150.

type t = {
  ctx: Ctx.t,
  el: element,
  name: element,
  detail: element,
  overview: element,
  mutable source: option<WaveImport.t>,
  mutable analysis: option<WaveImport.analysis>,
  mutable scrubs: bool,
  // a drag starts (to save an undo step), moves to a position, and ends
  onStart: unit => unit,
  onPick: float => unit,
  onEnd: unit => unit,
}

let draw = t =>
  switch (t.source, t.analysis) {
  | (Some(source), Some(analysis)) if t.scrubs =>
    open Context2d
    let g = t.overview->getContext2d
    let (w, h) = CanvasStyle.paper(t.overview, g)
    let n = Int.toFloat(WaveImport.length(source))
    let x = sample => sample / n * w
    // the part measured, at least a few pixels wide
    let middle = x(analysis.from + analysis.length / 2.)
    let half = Math.max(3., x(analysis.length) / 2.)
    let (x0, x1) = (middle - half, middle + half)
    g->setFillStyle(CanvasStyle.tint(0.25))
    g->fillRect(x0, 0., x1 - x0, h)
    // the volume, mirrored about the middle: solid where it's measured
    let bars = Float.toInt(w / 2.)
    let env = source.envelope
    let count = TypedArray.length(env)
    for i in 0 to bars - 1 {
      let bx = Int.toFloat(i) * 2.
      let v = ByteView.getUnsafe(env, i * count / bars)
      let bh = Math.max(1., v * (h - 6.))
      g->setFillStyle(bx + 1.5 >= x0 && bx <= x1 ? CanvasStyle.ink : CanvasStyle.shade(0.3))
      g->fillRect(bx, (h - bh) / 2., 1.5, bh)
    }
    CanvasStyle.border(g, w, h)
  | _ => ()
  }

let statusText = t =>
  switch (t.source, t.analysis) {
  | (Some(source), Some(analysis)) =>
    switch source.kind {
    | Frames(_) => `${source.name}, ${analysis.detail}. Click or drag along it to pick another frame.`
    | Recording if t.scrubs =>
      `${source.name}: ${analysis.detail}. Click or drag along it to measure another part of the sound.`
    | _ => `${source.name}: ${analysis.detail}`
    }
  | _ => ""
  }

let hide = t => {
  t.source = None
  t.analysis = None
  t.el->removeClass("on")
}

// Shows a sample and what was made from it. scrubs: whether it has other parts to pick.
let show = (t, source: WaveImport.t, analysis, ~scrubs) => {
  t.source = Some(source)
  t.analysis = Some(analysis)
  t.scrubs = scrubs
  t.name->setTextContent(source.name)
  t.detail->setTextContent(analysis.detail)
  t.overview->setStyle("display", scrubs ? "block" : "none")
  // the text stops short of the overview and the close button
  let right = px((scrubs ? overviewWidth + 6. : 0.) + 28.)
  [t.name, t.detail]->Array.forEach(e => e->setStyle("right", right))
  t.el->addClass("on")
  draw(t)
}

// A new analysis of the same sample, while dragging.
let update = (t, analysis) => {
  t.analysis = Some(analysis)
  t.detail->setTextContent(analysis.detail)
  draw(t)
  t.ctx.status->Status.show(statusText(t))
}

let make = (ctx: Ctx.t, parent, box: box, ~onStart, ~onPick, ~onEnd) => {
  let e = el("div", ~cls="sstrip", ~parent)->placeBox(box)
  let name = el("div", ~cls="n", ~parent=e)
  let detail = el("div", ~cls="d", ~parent=e)
  let overview = CanvasStyle.make(e, {x: box.w - 28. - overviewWidth, y: 3., w: overviewWidth, h: 20.})
  let close = el("button", ~cls="btn x", ~text="×", ~parent=e)
  let t = {
    ctx,
    el: e,
    name,
    detail,
    overview,
    source: None,
    analysis: None,
    scrubs: false,
    onStart,
    onPick,
    onEnd,
  }
  ctx.status->Status.hover(e, () => statusText(t))
  close->onMouse(#mouseenter, _ => ctx.status->Status.show("Put the sample away (the shape stays as it is)"))
  close->onMouse(#mouseleave, _ => ctx.status->Status.show(statusText(t)))
  close->onMouse(#click, _ => {
    hide(t)
    ctx.status->Status.clear
  })

  // dragging analyses at most once a frame
  let pending = ref(None)
  let positionAt = ev => Controls.clamp01(Pair.first(overview->pointerFraction(ev)))
  let flush = () =>
    pending.contents->Option.forEach(p => {
      pending := None
      t.onPick(p)
    })
  let flushSoon = perFrame(flush)
  let pick = ev => {
    pending := Some(positionAt(ev))
    flushSoon()
  }
  overview->onPointer(#pointerdown, ev =>
    if ev->button == 0 {
      ev->preventDefault
      t.onStart()
      pick(ev)
      overview->Controls.capturePointer(ev, ~onMove=pick, ~onUp=() => {
        flush()
        t.onEnd()
      })
    }
  )
  t
}
