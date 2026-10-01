// The tone of a feedback loop (the delay's or the reverb's): a lowpass and a highpass that
// every pass goes through again, so that each repeat is darker and thinner than the one before.
// The solid curve is one pass, the dashed ones later passes. Drag a point sideways to move its
// cutoff.

open! Web

type spec = {
  lowpass: string,
  highpass: string,
  // parameter value <-> cutoff in Hz
  lowpassHz: float => float,
  lowpassValue: float => float,
  highpassHz: float => float,
  highpassValue: float => float,
  // the later passes to draw: label and number of passes
  later: unit => array<(string, float)>,
}

let (fMin, fMax) = (20., 20000.)
let (dbTop, dbBottom) = (3., -42.)
let margin = 8.

let hint = "Drag a point sideways to move that filter's cutoff, shift for fine steps; right-click resets it. The dashed curves are later repeats."

// `highlight` picks out one more curve, e.g. the echo under the pointer: its label and passes.
let make = (ctx: Ctx.t, parent, box: box, spec, ~highlight: ref<option<(string, float)>>=ref(None)) => {
  let g = FxGraph.make(ctx, parent, box)
  let (left, right) = (margin, g.w - margin)
  let (top, bottom) = (margin, g.h - 14.)
  let xOf = f => left + Math.log(f / fMin) / Math.log(fMax / fMin) * (right - left)
  let freqAt = x => fMin * Math.pow(fMax / fMin, ~exp=FxDsp.clamp((x - left) / (right - left), 0., 1.))
  let yOf = db => top + (dbTop - FxDsp.clamp(db, dbBottom, dbTop)) / (dbTop - dbBottom) * (bottom - top)

  let grid = FxGraph.group(g.svg)
  [50., 100., 200., 500., 1000., 2000., 5000., 10000.]->Array.forEach(f => {
    let x = xOf(f)
    FxGraph.line(grid, ~cls=f == 100. || f == 1000. || f == 10000. ? "axis" : "axis faint", x, 1., x, g.h - 1.)
    if f == 100. || f == 1000. || f == 10000. {
      FxGraph.text(grid, x + 3., g.h - 4., f >= 1000. ? Float.toString(f / 1000.) ++ "k" : Float.toString(f))
    }
  })
  [0., -12., -24., -36.]->Array.forEach(db => {
    let y = yOf(db)
    FxGraph.line(grid, ~cls=db == 0. ? "axis" : "axis faint", 1., y, g.w - 1., y)
    if db != 0. {
      FxGraph.text(grid, 4., y - 3., Float.toString(db) ++ " dB")
    }
  })

  let laterLayer = FxGraph.group(g.svg)
  let fill = FxGraph.path(g.svg, ~cls="fill")
  let curve = FxGraph.path(g.svg, ~cls="curve")
  let layer = FxGraph.group(g.svg)
  let hits = FxGraph.group(g.svg)
  let readout = Plots.svgEl(hits, "text", [("class", Str("readout"))])

  let lpHz = () => spec.lowpassHz(FxGraph.get(g, spec.lowpass))
  let hpHz = () => spec.highpassHz(FxGraph.get(g, spec.highpass))
  let dbAt = (passes, f) =>
    passes * FxGraph.gainDb(FxDsp.loopGain(~lp=lpHz(), ~hp=hpHz(), f))

  let focus = ref(None)
  let dragging = ref(false)
  let draw = ref(() => ())

  let status = id => ctx.status->Status.show((FxGraph.def(g, id)).longText(FxGraph.get(g, id)))
  let point = (id, ~toValue) => {
    let x0 = ref(0.)
    let self = ref(None)
    let h = FxGraph.handle(
      g,
      ~layer,
      ~hits,
      ~cursor="ew-resize",
      ~ids=[id],
      ~start=() => {
        dragging := true
        x0 := self.contents->Option.mapOr(0., (h: FxGraph.handle) => h.x)
      },
      ~drag=((dx, _)) => FxGraph.set(g, id, toValue(freqAt(x0.contents + dx))),
      ~finish=() => {
        dragging := false
        draw.contents()
      },
      ~wheel=d => FxGraph.setNorm(g, id, FxGraph.norm(g, id) + d),
      ~hover=on => {
        focus := (on ? Some(id) : None)
        on ? status(id) : ctx.status->Status.show(hint)
        draw.contents()
      },
    )
    self := Some(h)
    h
  }
  let lp = point(spec.lowpass, ~toValue=spec.lowpassValue)
  let hp = point(spec.highpass, ~toValue=spec.highpassValue)

  let curveFor = passes => {
    let at = t => {
      let x = left + (right - left) * t
      (x, yOf(dbAt(passes, freqAt(x))))
    }
    let points = [at(0.)]
    points->Plots.trace(at, ~steps=48)
    points
  }

  draw :=
    () => {
      let one = curveFor(1.)
      let d = Plots.pathFrom(one)
      curve->FxGraph.setPath(d)
      let y0 = Float.toString(yOf(dbBottom))
      fill->FxGraph.setPath(`${d}L${Float.toString(right)} ${y0}L${Float.toString(left)} ${y0}Z`)
      laterLayer->setTextContent("")
      spec.later()->Array.forEach(((label, passes)) => {
        let points = curveFor(passes)
        FxGraph.path(laterLayer, ~cls="curve faint")->FxGraph.setPath(Plots.pathFrom(points))
        // label the curve where it falls through -12 dB, on the high side
        let y12 = yOf(-12.)
        switch points->Array.findLastIndex(((_, y)) => y <= y12) {
        | i if i > 0 && i < Array.length(points) - 1 =>
          let (x, _) = points->Array.getUnsafe(i)
          FxGraph.text(laterLayer, ~cls="tick curvelabel", x + 3., y12 + 10., label)
        | _ => ()
        }
      })
      highlight.contents->Option.forEach(((label, passes)) => {
        let points = curveFor(passes)
        FxGraph.path(laterLayer, ~cls="curve hl")->FxGraph.setPath(Plots.pathFrom(points))
        let y12 = yOf(-12.)
        switch points->Array.findLastIndex(((_, y)) => y <= y12) {
        | i if i > 0 =>
          let (x, _) = points->Array.getUnsafe(i)
          FxGraph.text(laterLayer, ~cls="readout", ~anchor="end", x - 3., y12 - 4., label)
        | _ => ()
        }
      })
      let (fl, fh) = (lpHz(), hpHz())
      lp->FxGraph.place(xOf(fl), yOf(dbAt(1., fl)))
      hp->FxGraph.place(xOf(fh), yOf(dbAt(1., fh)))
      [(spec.lowpass, lp), (spec.highpass, hp)]->Array.forEach(((id, h)) =>
        h->FxGraph.setClass(focus.contents == Some(id) ? "node hot" : "node")
      )
      switch focus.contents {
      | Some(id) =>
        let h = id == spec.lowpass ? lp : hp
        let hz = id == spec.lowpass ? fl : fh
        let name = id == spec.lowpass ? "lowpass" : "highpass"
        g->FxGraph.readout(readout, ~x=h.x, ~y=h.y, `${name} ${FxGraph.hzText(hz)}`)
        if dragging.contents {
          status(id)
        }
      | None => readout->setTextContent("")
      }
    }

  let redraw = FxGraph.redraw(g, () => draw.contents())
  g->FxGraph.listen([spec.lowpass, spec.highpass], redraw.request)
  g.svg->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  g.svg->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  redraw
}
