// The chorus tab: the voices as they move. Each dot is a voice, delayed by its place across the
// graph; it sweeps between the delay and the top of the range at the rate (left side above,
// right side below; in mono both sides hear the same). The dot at 0 is the dry sound. Drag the
// band's edges for the delay and the range, and the point on the speed track for the rate.

open! Web

let hint = "Each dot is a voice, as late as its place across: it sweeps between the band's edges at the rate. Drag the edges for the delay and the range, the speed point for the rate; shift for fine steps, right-click to reset."

let (rateMin, rateMax) = (0.01, 4.)

let make = (ctx: Ctx.t, body, e: FxRack.effect) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let w = Style.designWidth - 12.
  let settingsHeight = Grid.rowHeight + 2. * Grid.padBottom - Style.controlGap
  let topHeight = Style.pageHeight - 6. - 34. - settingsHeight - Grid.gap

  let panel = Panel.make(body, ~title="voices", ~x=0., ~y=0., ~w, ~h=topHeight)
  let g = FxGraph.make(ctx, panel.el, {x: 8., y: 25., w: w - 18., h: topHeight - 35.})
  let (left, right) = (40., g.w - 16.)
  let trackY = 14.
  let (top, bottom) = (52., g.h - 22.)
  let laneHeight = (bottom - top) / 2.
  // ms at the right edge, held while dragging
  let ceiling = ref(10.)
  let xOf = ms => left + FxDsp.clamp(ms / ceiling.contents, 0., 1.02) * (right - left)
  let msAt = x => (x - left) / (right - left) * ceiling.contents
  // the speed track: rate on a log scale
  let (trackL, trackR) = (left + 50., left + 330.)
  let rateX = hz =>
    trackL + Math.log(FxDsp.clamp(hz, rateMin, rateMax) / rateMin) / Math.log(rateMax / rateMin) * (trackR - trackL)
  let rateAt = x => rateMin * Math.pow(rateMax / rateMin, ~exp=FxDsp.clamp((x - trackL) / (trackR - trackL), 0., 1.))

  let grid = FxGraph.group(g.svg)
  let band = FxGraph.group(g.svg)
  let dots = FxGraph.group(g.svg)
  let layer = FxGraph.group(g.svg)
  let hits = FxGraph.group(g.svg)
  let readout = Plots.svgEl(hits, "text", [("class", Str("readout"))])

  let minimum = () => get("C_MinDelay")
  let range = () => get("C_Depth")
  let fit = () => ceiling := Math.max(2., (minimum() + range()) * 1.25)

  let focus = ref(None)
  let dragging = ref(false)
  let status = i => ctx.status->Status.show((model->ParamModel.def(i)).longText(model->ParamModel.get(i)))
  let hover = (i, on) => {
    focus := (on ? Some(i) : None)
    on ? status(i) : ctx.status->Status.show(hint)
  }
  let finish = () => {
    dragging := false
    fit()
  }

  let edge = (i, ~value: float => float) => {
    let x0 = ref(0.)
    let self = ref(None)
    let h = FxGraph.handle(
      g,
      ~layer,
      ~hits,
      ~cursor="ew-resize",
      ~ids=[i],
      ~start=() => {
        dragging := true
        x0 := self.contents->Option.mapOr(0., (h: FxGraph.handle) => h.x)
      },
      ~drag=((dx, _)) => {
        model->ParamModel.set(i, value(msAt(x0.contents + dx)))
        status(i)
      },
      ~finish,
      ~wheel=d => FxGraph.setNorm(g, i, FxGraph.norm(g, i) + d),
      ~hover=hover(i, ...),
    )
    self := Some(h)
    h
  }
  let lowHandle = edge(id("C_MinDelay"), ~value=ms => ms)
  let highHandle = edge(id("C_Depth"), ~value=ms => ms - minimum())

  let rateId = id("C_Rate")
  let rx0 = ref(0.)
  let rateSelf = ref(None)
  let rateHandle = FxGraph.handle(
    g,
    ~layer,
    ~hits,
    ~cursor="ew-resize",
    ~ids=[rateId],
    ~start=() => {
      dragging := true
      rx0 := rateSelf.contents->Option.mapOr(0., (h: FxGraph.handle) => h.x)
    },
    ~drag=((dx, _)) => {
      model->ParamModel.set(rateId, rateAt(rx0.contents + dx))
      status(rateId)
    },
    ~finish,
    ~wheel=d => FxGraph.setNorm(g, rateId, FxGraph.norm(g, rateId) + d),
    ~hover=hover(rateId, ...),
  )
  rateSelf := Some(rateHandle)

  let f = Float.toFixed(_, ~digits=1)
  let sweepText = () => {
    let period = 1. / Math.max(1e-4, get("C_Rate"))
    period >= 1. ? `a sweep every ${Float.toFixed(period, ~digits=1)} s` : `${Float.toFixed(1. / period, ~digits=1)} sweeps a second`
  }

  // everything, for the moment `t` (seconds)
  let draw = t => {
    let mode = Float.toInt(get("C_Mode"))
    g.svg->toggleClass("off", mode == 0)
    let stereo = Float.toInt(get("C_Stereo"))
    let voices = Math.Int.max(1, Float.toInt(get("C_Voices")))
    let mix = get("C_Mix")
    let (lo, hi) = (minimum(), minimum() + range())
    let lanes = stereo == 0 ? [("both sides", top + laneHeight / 2., laneHeight * 2.)] : [
          ("left", top, laneHeight),
          ("right", top + laneHeight, laneHeight),
        ]
    grid->setTextContent("")
    // time across
    let step = FxGraph.niceStep(ceiling.contents, 8.)
    let ms = ref(0.)
    while ms.contents <= ceiling.contents {
      let x = xOf(ms.contents)
      FxGraph.line(grid, ~cls="axis faint", x, top, x, bottom)
      FxGraph.text(grid, ~anchor="middle", x, g.h - 6., FxGraph.msText(ms.contents))
      ms := ms.contents + step
    }
    FxGraph.text(grid, ~anchor="end", right, g.h - 6. - 12., "later")
    lanes->Array.forEach(((name, y, height)) => {
      let y0 = stereo == 0 ? top : y
      FxGraph.line(grid, ~cls="axis", left, y0 + height, right, y0 + height)
      FxGraph.text(grid, ~cls="tick", 2., y0 + height / 2. + 3., name == "both sides" ? "L+R" : name == "left" ? "L" : "R")
    })
    // the speed track
    FxGraph.line(grid, ~cls="axis", trackL, trackY, trackR, trackY)
    FxGraph.text(grid, ~anchor="end", trackL - 10., trackY + 4., "slow")
    FxGraph.text(grid, trackR + 10., trackY + 4., "fast")
    FxGraph.text(grid, ~cls="readout", trackR + 44., trackY + 4., `rate ${FxGraph.short(g, rateId)}: ${sweepText()}`)
    rateHandle->FxGraph.place(rateX(get("C_Rate")), trackY)

    band->setTextContent("")
    let (xl, xh) = (xOf(lo), xOf(hi))
    Plots.svgEl(
      band,
      "rect",
      [("class", Str("band")), ("x", Num(xl)), ("y", Num(top)), ("width", Num(Math.max(1., xh - xl))), ("height", Num(bottom - top))],
    )->ignore
    FxGraph.line(band, ~cls="edge", xl, top, xl, bottom)
    FxGraph.line(band, ~cls="edge", xh, top, xh, bottom)
    lowHandle->FxGraph.place(xl, top - 8.)
    highHandle->FxGraph.place(xh, top - 8.)
    FxGraph.text(band, ~cls="note", ~anchor="end", xl - 9., top - 4., "delay")
    FxGraph.text(band, ~cls="note", xh + 9., top - 4., "range")

    dots->setTextContent("")
    let offsets = FxDsp.chorusOffsets(~stereo, ~voices)
    let rate = get("C_Rate")
    let at = (seed, off) =>
      mode == 4 ? FxDsp.chorusWalk(seed, t * rate) : FxDsp.chorusLfo(mode, Float.mod(t * rate + off, 1.))
    let size = 3. + 5. * Math.sqrt(mix / Int.toFloat(voices))
    lanes->Array.forEachWithIndex(((_, y, height), side) => {
      let yc = stereo == 0 ? y : y + height / 2.
      // the dry sound, at 0
      Plots.svgEl(
        dots,
        "circle",
        [("class", Str("dry")), ("cx", Num(xOf(0.))), ("cy", Num(yc)), ("r", Num(4. + 6. * (1. -. mix)))],
      )->ignore
      offsets->Array.forEachWithIndex(((offL, offR), v) => {
        let spread = (Int.toFloat(v) - (Int.toFloat(voices) - 1.) / 2.) * Math.min(14., (height - 20.) / Int.toFloat(voices))
        let seed = Int.toFloat(v) + (side == 1 ? 0.5 : 0.)
        let amount = at(seed, side == 1 ? offR : offL)
        let x = xOf(lo + amount * (hi - lo))
        Plots.svgEl(dots, "circle", [("class", Str("voice")), ("cx", Num(x)), ("cy", Num(yc + spread)), ("r", Num(size))])->ignore
      })
    })

    [(id("C_MinDelay"), lowHandle), (id("C_Depth"), highHandle), (rateId, rateHandle)]->Array.forEach(((i, h)) =>
      h->FxGraph.setClass(focus.contents == Some(i) ? "node hot" : "node")
    )
    switch focus.contents {
    | Some(i) if i != rateId =>
      let h = i == id("C_MinDelay") ? lowHandle : highHandle
      g->FxGraph.readout(
        readout,
        ~x=h.x,
        ~y=h.y + 30.,
        i == id("C_MinDelay") ? `delay ${FxGraph.short(g, i)}` : `range ${FxGraph.short(g, i)}: up to ${FxGraph.msText(hi)}`,
      )
    | _ => readout->setTextContent("")
    }
    ignore(f)
  }

  // the dots move while the tab is on screen
  let running = ref(false)
  let rec frame = now => {
    if FxGraph.shown(g) {
      draw(now / 1000.)
      requestAnimationFrame(frame)
    } else {
      running := false
    }
  }
  let start = () => {
    if !dragging.contents {
      fit()
    }
    draw(0.)
    if !running.contents {
      running := true
      requestAnimationFrame(frame)
    }
  }
  g.svg->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  g.svg->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  ["C_MinDelay", "C_Depth"]->Array.forEach(i =>
    model->ParamModel.listen(id(i), () => if !dragging.contents {
        fit()
      })
  )

  let settings = Panel.make(body, ~x=0., ~y=topHeight + Grid.gap, ~w, ~h=settingsHeight)
  let s = Grid.make(ctx, settings.el, ~y=Grid.padBottom, ~cw=Grid.fitColumns(w, 8))
  s->Grid.choice(id("C_Mode"), 0, 0, "mode")
  s->Grid.choice(id("C_Stereo"), 1, 0, "stereo")
  s->Grid.param(id("C_Voices"), 2, 0, "voices")
  s->Grid.param(id("C_Rate"), 3, 0, "rate")
  s->Grid.param(id("C_MinDelay"), 4, 0, "delay")
  s->Grid.param(id("C_Depth"), 5, 0, "range")
  s->Grid.param(id("C_Feedback"), 6, 0, "feedback")
  s->Grid.param(id("C_Mix"), 7, 0, "mix")

  start
}
