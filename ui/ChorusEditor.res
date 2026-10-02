// The chorus tab: the voices as they move. Each dot is a voice, delayed by its place across the
// graph; it sweeps between the delay and the top of the range at the rate (left side above,
// right side below; in mono both sides hear the same). The dot at 0 is the dry sound. Drag the
// band's edges for the delay and the range, and the point on the speed track for the rate.

open! Web

let hint = "Each dot is a voice, as late as its place across: it sweeps between the band's edges at the rate. Drag the edges for the delay and the range, the speed point for the rate; shift for fine steps, right-click to reset."

let (rateMin, rateMax) = (0.01, 4.)

let make = (ctx: Ctx.t, body, e: FxRack.effect, ~w, ~h) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let settingsHeight = Grid.bareHeight(1)
  let topHeight = h - settingsHeight - Grid.gap

  let panel = Panel.make(body, ~title="voices", ~x=0., ~y=0., ~w, ~h=topHeight)
  let g = FxGraph.inPanel(ctx, panel, ~hint)
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
  let (rateX, rateAt) = FxGraph.logScale(~lo=rateMin, ~hi=rateMax, ~left=trackL, ~right=trackR)

  let grid = FxGraph.group(g.under)
  let band = FxGraph.group(g.under)
  let dots = FxGraph.group(g.under)

  let minimum = () => get("C_MinDelay")
  let range = () => get("C_Depth")
  let fit = () => ceiling := Math.max(2., (minimum() + range()) * 1.25)

  // the band's edges, and the point on the speed track: value maps where it is dragged to
  let point = (i, value) =>
    FxGraph.handle(
      g,
      ~cursor="ew-resize",
      ~ids=[i],
      ~drag=({x}) => model->ParamModel.set(i, value(x)),
      ~finish=() => {
        fit()
        g.redraw()
      },
      ~wheel=i,
    )
  let lowHandle = point(id("C_MinDelay"), msAt)
  let highHandle = point(id("C_Depth"), x => msAt(x) - minimum())
  let rateId = id("C_Rate")
  let rateHandle = point(rateId, rateAt)

  let sweepText = () => {
    let period = 1. / Math.max(1e-4, get("C_Rate"))
    period >= 1. ? `a sweep every ${Float.toFixed(period, ~digits=1)} s` : `${Float.toFixed(1. / period, ~digits=1)} sweeps a second`
  }

  // each side's lane: its label, middle (both sides: the middle of the two) and height
  let lanes = () =>
    get("C_Stereo") == 0.
      ? [("L+R", top + laneHeight / 2., laneHeight * 2.)]
      : [("L", top, laneHeight), ("R", top + laneHeight, laneHeight)]

  // everything but the voices
  let draw = () => {
    g.svg->toggleClass("off", get("C_Mode") == 0.)
    let stereo = get("C_Stereo") != 0.
    let (lo, hi) = (minimum(), minimum() + range())
    grid->setTextContent("")
    // time across
    FxGraph.ticks(~until=ceiling.contents, ~step=FxGraph.niceStep(ceiling.contents, 8.), ms => {
      let x = xOf(ms)
      FxGraph.line(grid, ~cls="axis faint", x, top, x, bottom)
      FxGraph.text(grid, ~anchor="middle", x, g.h - 6., FxGraph.msText(ms))
    })
    FxGraph.text(grid, ~anchor="end", right, g.h - 6. - 12., "later")
    lanes()->Array.forEach(((name, y, height)) => {
      let y0 = stereo ? y : top
      FxGraph.line(grid, ~cls="axis", left, y0 + height, right, y0 + height)
      FxGraph.text(grid, ~cls="tick", 2., y0 + height / 2. + 3., name)
    })
    // the speed track
    FxGraph.line(grid, ~cls="axis", trackL, trackY, trackR, trackY)
    FxGraph.text(grid, ~anchor="end", trackL - 10., trackY + 4., "slow")
    FxGraph.text(grid, trackR + 10., trackY + 4., "fast")
    FxGraph.text(grid, ~cls="readout", trackR + 44., trackY + 4., `rate ${FxGraph.short(g, rateId)}: ${sweepText()}`)
    rateHandle->FxGraph.place(rateX(get("C_Rate")), trackY)

    band->setTextContent("")
    let (xl, xh) = (xOf(lo), xOf(hi))
    svgEl(
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

    switch g.focus {
    | Some(k) if k == lowHandle.key =>
      g->FxGraph.readout(~x=lowHandle.x, ~y=lowHandle.y + 30., `delay ${FxGraph.short(g, k)}`)
    | Some(k) if k == highHandle.key =>
      g->FxGraph.readout(~x=highHandle.x, ~y=highHandle.y + 30., `range ${FxGraph.short(g, k)}: up to ${FxGraph.msText(hi)}`)
    | _ => g->FxGraph.hideReadout
    }
  }
  g.redraw = draw

  // each side's dots, the dry sound's then the voices': made again only when the number of
  // sides or voices changes, and moved each frame
  let made = ref((0, 0, []))
  let dotsFor = (sides, count) =>
    switch made.contents {
    | (s, c, els) if s == sides && c == count => els
    | _ =>
      dots->setTextContent("")
      let els = Array.fromInitializer(~length=sides * (count + 1), i =>
        svgEl(dots, "circle", [("class", Str(mod(i, count + 1) == 0 ? "dry" : "voice"))])
      )
      made := (sides, count, els)
      els
    }
  let place = (dot, x, y, r) => {
    dot->setAttribute("cx", Num(x))
    dot->setAttribute("cy", Num(y))
    dot->setAttribute("r", Num(r))
  }

  // the voices at the moment `t` (seconds)
  let drawVoices = t => {
    let mode = Float.toInt(get("C_Mode"))
    let stereo = Float.toInt(get("C_Stereo"))
    let voices = Math.Int.max(1, Float.toInt(get("C_Voices")))
    let mix = get("C_Mix")
    let (lo, hi) = (minimum(), minimum() + range())
    let offsets = FxDsp.chorusOffsets(~stereo, ~voices)
    let rate = get("C_Rate")
    let at = (seed, off) =>
      mode == 4 ? FxDsp.chorusWalk(seed, t * rate) : FxDsp.chorusLfo(mode, Float.mod(t * rate + off, 1.))
    let size = 3. + 5. * Math.sqrt(mix / Int.toFloat(voices))
    let sides = lanes()
    let count = Array.length(offsets)
    let els = dotsFor(Array.length(sides), count)
    sides->Array.forEachWithIndex(((_, y, height), side) => {
      let yc = stereo == 0 ? y : y + height / 2.
      let first = side * (count + 1)
      // the dry sound, at 0
      place(els->Array.getUnsafe(first), xOf(0.), yc, 4. + 6. * (1. -. mix))
      offsets->Array.forEachWithIndex(((offL, offR), v) => {
        let spread = (Int.toFloat(v) - (Int.toFloat(voices) - 1.) / 2.) * Math.min(14., (height - 20.) / Int.toFloat(voices))
        let seed = Int.toFloat(v) + (side == 1 ? 0.5 : 0.)
        let amount = at(seed, side == 1 ? offR : offL)
        let x = xOf(lo + amount * (hi - lo))
        place(els->Array.getUnsafe(first + 1 + v), x, yc + spread, size)
      })
    })
  }

  let redraw = FxGraph.redraw(g, draw)
  g->FxGraph.listen(["C_Mode", "C_Stereo", "C_MinDelay", "C_Depth", "C_Rate"]->Array.map(id), redraw.request)
  // the voices move while the tab is on screen
  let animate = FxGraph.animate(g, now => drawVoices(now / 1000.))
  g->FxGraph.listen(["C_MinDelay", "C_Depth"]->Array.map(id), () => if !g.dragging {
      fit()
    })

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

  () => {
    if !g.dragging {
      fit()
    }
    redraw.now()
    drawVoices(0.)
    animate()
  }
}
