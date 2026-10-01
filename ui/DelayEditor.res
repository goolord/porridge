// The delay tab: the echoes an impulse makes, on a lane per side, to drag; the stereo
// feedback (input pan and rotation) as a diagram; the loop's tone; and every setting.
//
// Echoes: each side's first echo moves sideways for that side's length and up or down for the
// wet level (both sides share it); the hollow point after it sets that side's feedback; the
// faint stem at 0 is the dry signal. Echo heights include the loop filters' broadband loss.

open! Web

let hint = "Drag a side's first echo sideways for its length, up or down for the wet level; drag the hollow point after it for its feedback, and the faint stem at 0 for the dry level. Shift for fine steps, right-click to reset."

let laneLabel = 22. // room for the L / R labels left of time 0

let make = (ctx: Ctx.t, body, e: FxRack.effect) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  // for ids that are already this delay's
  let value = x => model->ParamModel.get(x)
  let (gap, w) = (Grid.gap, Style.designWidth - 12.)
  let topHeight = 330.

  //==============================================================================
  // echoes

  let panel = Panel.make(body, ~title="echoes", ~x=0., ~y=0., ~w, ~h=topHeight)
  panel->Panel.headerToggle(ctx, id("D_On"), ~label="on")
  let g = FxGraph.make(ctx, panel.el, {x: 8., y: 25., w: w - 18., h: topHeight - 35.})
  let (left, right) = (laneLabel + 10., g.w - 10.)
  let axisHeight = 14.
  let laneHeight = (g.h - axisHeight) / 2.
  let centre = side => laneHeight * (Int.toFloat(side) + 0.5)
  let halfLane = laneHeight / 2. - 8.

  // the time span and amplitude scale, held while dragging
  let span = ref(16.)
  let scale = ref(1.2)
  let xOf = t => left + t / span.contents * (right - left)
  let yOf = (side, amp) => centre(side) - FxDsp.clamp(amp / scale.contents, -1.08, 1.08) * halfLane
  let ampAt = (side, y) => (centre(side) - y) / halfLane * scale.contents

  let grid = FxGraph.group(g.svg)
  let stems = FxGraph.group(g.svg)
  let glyphs = FxGraph.group(g.svg)
  let marks = FxGraph.group(g.svg)
  let layer = FxGraph.group(g.svg)
  let hits = FxGraph.group(g.svg)
  let readout = Plots.svgEl(hits, "text", [("class", Str("readout"))])

  let unit = () => Float.toInt(get("D_Unit"))
  let quantized = () => get("D_Quantize") != 0.
  let heard = x => quantized() ? Math.max(1., Math.round(x)) : x
  let lengths = () => (heard(get("D_LengthL")), heard(get("D_LengthR")))
  let lowpass = () => FxDsp.delayCutoff(get("D_LP"))
  let highpass = () => FxDsp.delayCutoff(get("D_HP"))
  let loss = () => FxDsp.broadbandGain(~lp=lowpass(), ~hp=highpass())
  let panGain = side => side == 0 ? 2. - 2. * get("D_InputPan") : 2. * get("D_InputPan")
  let lengthId = side => id(side == 0 ? "D_LengthL" : "D_LengthR")
  let feedbackId = side => id(side == 0 ? "D_FeedbackL" : "D_FeedbackR")
  let reverseId = side => id(side == 0 ? "D_ReverseL" : "D_ReverseR")
  // a side's first echo, before the rotation mixes the sides
  let first = side => {
    let reversed = value(reverseId(side)) == 1.
    (reversed ? 1. : loss()) * panGain(side) * get("D_Wet")
  }
  // where a side's feedback point sits: what the next pass would leave of the first echo
  let feedbackRef = side => Math.max(first(side) * loss(), 0.25 * scale.contents)

  let settings = (): FxDsp.delaySettings => {
    let (lengthL, lengthR) = lengths()
    {
      lengthL,
      lengthR,
      feedbackL: get("D_FeedbackL"),
      feedbackR: get("D_FeedbackR"),
      rotation: get("D_Rotation"),
      inputPan: get("D_InputPan"),
      lp: lowpass(),
      hp: highpass(),
      wet: get("D_Wet"),
      reverseL: Float.toInt(get("D_ReverseL")),
      reverseR: Float.toInt(get("D_ReverseR")),
    }
  }

  // a length in the unit, as text: "3 16ths (0.75 beats)", "250 ms"
  let lengthText = units => {
    let n = Float.toFixed(units, ~digits=quantized() || Math.round(units) == units ? 0 : 2)
    let name = (model->ParamModel.def(id("D_Unit"))).shortText(Int.toFloat(unit()))
    switch FxDsp.unitLength(unit()) {
    | Ms(ms) => FxGraph.msText(units * ms)
    | Beats(b) =>
      `${n} × ${name} (${Float.toString(Math.round(units * b * 100.) / 100.)} beats)`
    }
  }

  let fit = () => {
    let (l, r) = lengths()
    let longest = Math.max(l, r)
    span := Math.max(4., Math.ceil(longest * 5.5))
    let echoes = FxDsp.echoes(settings(), ~until=span.contents)
    let peak = echoes->Array.reduce(Math.max(get("D_Dry"), first(0)), (m, e) => Math.max(m, Math.abs(e.amp)))
    scale := Math.min(2.5, Math.max(1., peak * 1.1))
  }

  let drawGrid = () => {
    grid->setTextContent("")
    [0, 1]->Array.forEach(side => {
      let y = centre(side)
      FxGraph.line(grid, ~cls="axis", left, y, right, y)
      FxGraph.text(grid, ~cls="lane", ~anchor="middle", laneLabel / 2. + 2., y + 4., side == 0 ? "L" : "R")
    })
    FxGraph.line(grid, ~cls="axis faint", 0., laneHeight, g.w, laneHeight)
    let bottom = g.h - axisHeight
    FxGraph.line(grid, ~cls="axis", left, bottom, right, bottom)
    // the unit grid (where whole lengths fall), then labelled ticks
    let unitPx = (right - left) / span.contents
    if unitPx >= 6. {
      for k in 1 to Float.toInt(span.contents) {
        let x = xOf(Int.toFloat(k))
        FxGraph.line(grid, ~cls="axis faint", x, 1., x, bottom)
      }
    }
    switch FxDsp.unitLength(unit()) {
    | Ms(ms) =>
      let total = span.contents * ms
      let step = FxGraph.niceStep(total, 8.)
      let t = ref(0.)
      while t.contents <= total +. 1e-9 {
        let x = xOf(t.contents / ms)
        FxGraph.line(grid, ~cls="axis", x, bottom, x, bottom + 4.)
        FxGraph.text(grid, ~anchor="middle", x, g.h - 2., FxGraph.msText(t.contents))
        t := t.contents + step
      }
    | Beats(b) =>
      let total = span.contents * b
      let step = Math.max(0.25, FxGraph.niceStep(total, 10.))
      let t = ref(0.)
      while t.contents <= total +. 1e-9 {
        let x = xOf(t.contents / b)
        let whole = Math.abs(t.contents - Math.round(t.contents)) < 1e-6
        FxGraph.line(grid, ~cls=whole ? "axis" : "axis faint", x, whole ? 1. : bottom - 4., x, bottom + 4.)
        if whole || step < 1. {
          FxGraph.text(grid, ~anchor="middle", x, g.h - 2., Float.toString(t.contents))
        }
        t := t.contents + step
      }
      FxGraph.text(grid, ~anchor="end", right, g.h - 2. - 11., "beats")
    }
  }

  let focus = ref(None)
  let dragging = ref(false)
  let draw = ref(() => ())
  let request = ref(() => ())
  // the echoes drawn last, and the one under the pointer
  let drawn = ref([])
  let pointed = ref(None)
  // the tone graph's extra curve: the pointed echo's
  let highlight = ref(None)
  let toneRequest = ref(() => ())

  // An echo's tone, drawn small above (or under) it: what the loop's filters leave of every
  // frequency after its passes, 20 Hz to 20 kHz across.
  let glyph = (x, y, passes, ~below) => {
    let (gw, gh) = (22., 11.)
    let y0 = below ? y + 6. : y - 6. - gh
    let lp = lowpass()
    let hp = highpass()
    let points = Array.fromInitializer(~length=23, i => {
      let t = Int.toFloat(i) / 22.
      let f = 20. * Math.pow(1000., ~exp=t)
      let db = Int.toFloat(passes) * FxGraph.gainDb(FxDsp.loopGain(~lp, ~hp, f))
      (x - gw / 2. + t * gw, y0 + gh * (1. - FxDsp.clamp((db + 30.) / 30., 0., 1.)))
    })
    let d = Plots.pathFrom(points)
    let bottomY = Float.toString(y0 + gh)
    Plots.svgEl(
      glyphs,
      "path",
      [
        ("class", Str("glyph")),
        ("d", Str(`${d}L${Float.toString(x + gw / 2.)} ${bottomY}L${Float.toString(x - gw / 2.)} ${bottomY}Z`)),
      ],
    )->ignore
  }

  let status = ids =>
    ctx.status->Status.show(
      ids->Array.map(i => (model->ParamModel.def(i)).longText(model->ParamModel.get(i)))->Array.join("    "),
    )

  let hover = (key, ids, on) => {
    focus := (on ? Some(key) : None)
    on ? status(ids) : ctx.status->Status.show(hint)
    draw.contents()
  }
  let start = () => dragging := true
  let finish = () => {
    dragging := false
    fit()
    drawGrid()
    draw.contents()
  }

  // a side's first echo: length sideways, wet up and down
  let echoHandle = side => {
    let origin = ref((0., 0.))
    let self = ref(None)
    let ids = [lengthId(side), id("D_Wet")]
    let h = FxGraph.handle(
      g,
      ~layer,
      ~hits,
      ~ids,
      ~start=() => {
        start()
        origin := self.contents->Option.mapOr((0., 0.), (h: FxGraph.handle) => (h.x, h.y))
      },
      ~drag=((dx, dy)) => {
        let (x0, y0) = origin.contents
        let t = (x0 + dx - left) / (right - left) * span.contents
        model->ParamModel.set(lengthId(side), quantized() ? Math.round(t) : t)
        let per = first(side) / Math.max(1e-9, get("D_Wet"))
        if per > 0.05 {
          model->ParamModel.set(id("D_Wet"), Math.max(0., ampAt(side, y0 + dy) / per))
        }
      },
      ~finish,
      ~hover=hover(`echo${Int.toString(side)}`, ids, ...),
    )
    self := Some(h)
    h
  }
  // a side's feedback: up and down
  let feedbackHandle = side => {
    let y0 = ref(0.)
    let self = ref(None)
    let fid = feedbackId(side)
    let h = FxGraph.handle(
      g,
      ~layer,
      ~hits,
      ~cls="node hollow",
      ~cursor="ns-resize",
      ~ids=[fid],
      ~start=() => {
        start()
        y0 := self.contents->Option.mapOr(0., (h: FxGraph.handle) => h.y)
      },
      ~drag=((_, dy)) => model->ParamModel.set(fid, ampAt(side, y0.contents + dy) / feedbackRef(side)),
      ~finish,
      ~wheel=d => FxGraph.setNorm(g, fid, FxGraph.norm(g, fid) + d),
      ~hover=hover(`feedback${Int.toString(side)}`, [fid], ...),
    )
    self := Some(h)
    h
  }
  // the dry signal at 0, on both sides
  let dryHandle = side => {
    let y0 = ref(0.)
    let self = ref(None)
    let dry = id("D_Dry")
    let h = FxGraph.handle(
      g,
      ~layer,
      ~hits,
      ~cls="node faint",
      ~r=4.5,
      ~cursor="ns-resize",
      ~ids=[dry],
      ~start=() => {
        start()
        y0 := self.contents->Option.mapOr(0., (h: FxGraph.handle) => h.y)
      },
      ~drag=((_, dy)) => model->ParamModel.set(dry, Math.max(0., ampAt(side, y0.contents + dy))),
      ~finish,
      ~hover=hover("dry", [dry], ...),
    )
    self := Some(h)
    h
  }
  let echoHandles = [echoHandle(0), echoHandle(1)]
  let feedbackHandles = [feedbackHandle(0), feedbackHandle(1)]
  let dryHandles = [dryHandle(0), dryHandle(1)]

  draw :=
    () => {
      let on = get("D_On") != 0.
      g.svg->toggleClass("off", !on)
      stems->setTextContent("")
      glyphs->setTextContent("")
      marks->setTextContent("")
      let s = settings()
      let echoes = FxDsp.echoes(s, ~until=span.contents)
      drawn := echoes
      // a tone above every echo with room for it
      let lastGlyph = [-100., -100.]
      echoes->Array.forEach(echo => {
        let x = xOf(echo.time)
        if x - lastGlyph->Array.getUnsafe(echo.side) >= 26. && Math.abs(echo.amp) > scale.contents * 0.06 {
          lastGlyph->Array.setUnsafe(echo.side, x)
          glyph(x, yOf(echo.side, echo.amp), echo.passes, ~below=echo.amp < 0.)
        }
      })
      pointed.contents->Option.forEach((echo: FxDsp.echo) => {
        let x = xOf(echo.time)
        Plots.svgEl(
          marks,
          "circle",
          [("class", Str("pointed")), ("cx", Num(x)), ("cy", Num(yOf(echo.side, echo.amp))), ("r", Num(5.))],
        )->ignore
      })
      let dry = get("D_Dry")
      [0, 1]->Array.forEach(side => {
        let y0 = centre(side)
        // dry
        let x = xOf(0.)
        FxGraph.line(stems, ~cls="stem dry", x, y0, x, yOf(side, dry))
        dryHandles->Array.getUnsafe(side)->FxGraph.place(x, yOf(side, dry))
      })
      echoes->Array.forEach(echo => {
        let x = xOf(echo.time)
        let y0 = centre(echo.side)
        let y = yOf(echo.side, echo.amp)
        let reversed = value(reverseId(echo.side)) != 0.
        if reversed {
          // a reversed echo swells into its time
          let length = echo.side == 0 ? s.lengthL : s.lengthR
          let x1 = Math.max(left, xOf(echo.time - length * 0.6))
          Plots.svgEl(
            stems,
            "path",
            [
              ("class", Str("swell")),
              ("d", Str(`M${Float.toString(x1)} ${Float.toString(y0)}L${Float.toString(x)} ${Float.toString(y)}L${Float.toString(x)} ${Float.toString(y0)}Z`)),
            ],
          )->ignore
        } else {
          FxGraph.line(stems, ~cls="stem", x, y0, x, y)
          Plots.svgEl(stems, "circle", [("class", Str("head")), ("cx", Num(x)), ("cy", Num(y)), ("r", Num(2.2))])->ignore
        }
        if Math.abs(echo.amp) > scale.contents * 1.08 {
          FxGraph.text(marks, ~cls="clip", ~anchor="middle", x, echo.amp > 0. ? y - 3. : y + 9., "▲")
        }
      })
      [0, 1]->Array.forEach(side => {
        let length = side == 0 ? s.lengthL : s.lengthR
        let x = xOf(length)
        let e = echoHandles->Array.getUnsafe(side)
        e->FxGraph.place(x, yOf(side, first(side)))
        let f = feedbackHandles->Array.getUnsafe(side)
        let fx = xOf(2. * length)
        f->FxGraph.show(fx <= right + 1.)
        let fy = yOf(side, value(feedbackId(side)) * feedbackRef(side))
        f->FxGraph.place(fx, fy)
        if fx <= right + 1. {
          FxGraph.line(marks, ~cls="link", e.x, e.y, fx, fy)
        }
        let key = Int.toString(side)
        e->FxGraph.setClass(focus.contents == Some("echo" ++ key) ? "node hot" : "node")
        f->FxGraph.setClass(focus.contents == Some("feedback" ++ key) ? "node hollow hot" : "node hollow")
        dryHandles->Array.getUnsafe(side)->FxGraph.setClass(focus.contents == Some("dry") ? "node faint hot" : "node faint")
      })
      switch focus.contents {
      | Some(key) =>
        let side = String.endsWith(key, "1") ? 1 : 0
        let sideName = side == 0 ? "L" : "R"
        let (h: FxGraph.handle, text) = if String.startsWith(key, "echo") {
          (
            echoHandles->Array.getUnsafe(side),
            `${sideName} ${lengthText(side == 0 ? s.lengthL : s.lengthR)}  ·  wet ${FxGraph.short(g, id("D_Wet"))}`,
          )
        } else if String.startsWith(key, "feedback") {
          (feedbackHandles->Array.getUnsafe(side), `${sideName} feedback ${FxGraph.short(g, feedbackId(side))}`)
        } else {
          (dryHandles->Array.getUnsafe(0), `dry ${FxGraph.short(g, id("D_Dry"))}`)
        }
        g->FxGraph.readout(readout, ~x=h.x, ~y=h.y, text)
        if dragging.contents {
          status(
            String.startsWith(key, "echo")
              ? [lengthId(side), id("D_Wet")]
              : String.startsWith(key, "feedback") ? [feedbackId(side)] : [id("D_Dry")],
          )
        }
      | None =>
        switch pointed.contents {
        | Some(echo) =>
          let x = xOf(echo.time)
          let db = FxGraph.gainDb(Math.abs(echo.amp))
          g->FxGraph.readout(
            readout,
            ~x,
            ~y=yOf(echo.side, echo.amp),
            `${echo.side == 0 ? "L" : "R"} at ${lengthText(echo.time)}  ·  ${FxGraph.dbText(db)}  ·  ${Int.toString(echo.passes)}× through the filters`,
          )
        | None => readout->setTextContent("")
        }
      }
    }

  // the echo under the pointer: its tone in the tone graph
  g.svg->onMouse(#mousemove, ev => {
    let r = g.svg->getBoundingClientRect
    let k = g.w / r.width
    let (px, py) = ((ev->clientX - r.left) * k, (ev->clientY - r.top) * k)
    let side = py < laneHeight ? 0 : 1
    let near =
      dragging.contents || focus.contents != None
        ? None
        : drawn.contents
          ->Array.filter(e => e.side == side && Math.abs(xOf(e.time) - px) < 8.)
          ->Array.reduce(None, (best, e) =>
            switch best {
            | Some(b: FxDsp.echo) if Math.abs(xOf(b.time) - px) <= Math.abs(xOf(e.time) - px) => best
            | _ => Some(e)
            }
          )
    if near != pointed.contents {
      pointed := near
      highlight := near->Option.map(e => (`this echo: ${Int.toString(e.passes)}×`, Int.toFloat(e.passes)))
      draw.contents()
      toneRequest.contents()
    }
  })
  g.svg->onMouse(#mouseleave, _ =>
    if pointed.contents != None {
      pointed := None
      highlight := None
      draw.contents()
      toneRequest.contents()
    }
  )

  let echoRedraw = FxGraph.redraw(g, () => {
    if !dragging.contents {
      fit()
      drawGrid()
    }
    draw.contents()
  })
  request := echoRedraw.request
  let delayIds =
    [
      "D_On",
      "D_Unit",
      "D_Quantize",
      "D_ReverseL",
      "D_ReverseR",
      "D_LengthL",
      "D_LengthR",
      "D_FeedbackL",
      "D_FeedbackR",
      "D_InputPan",
      "D_Rotation",
      "D_LP",
      "D_HP",
      "D_Dry",
      "D_Wet",
    ]->Array.map(id)
  g->FxGraph.listen(delayIds, echoRedraw.request)
  g.svg->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  g.svg->onMouse(#mouseleave, _ => ctx.status->Status.clear)

  //==============================================================================
  // tone, stereo and settings

  let bottomY = topHeight + gap
  let bottomHeight = Style.pageHeight - 6. - 34. - bottomY
  let toneWidth = 300.
  let tone = Panel.make(body, ~title="feedback tone", ~x=0., ~y=bottomY, ~w=toneWidth, ~h=bottomHeight)
  let toneRedraw = LoopTone.make(
    ctx,
    tone.el,
    {x: 8., y: 25., w: toneWidth - 18., h: bottomHeight - 35.},
    {
      lowpass: id("D_LP"),
      highpass: id("D_HP"),
      lowpassHz: FxDsp.delayCutoff,
      lowpassValue: FxDsp.delayCutoffValue,
      highpassHz: FxDsp.delayCutoff,
      highpassValue: FxDsp.delayCutoffValue,
      later: () => [("2×", 2.), ("4×", 4.), ("8×", 8.)],
    },
    ~highlight,
  )
  toneRequest := toneRedraw.request

  let stereoWidth = 262.
  let stereo = Panel.make(
    body,
    ~title="stereo",
    ~x=toneWidth + gap,
    ~y=bottomY,
    ~w=stereoWidth,
    ~h=bottomHeight,
  )
  let stereoRedraw = DelayStereo.make(
    ctx,
    stereo.el,
    {x: 8., y: 25., w: stereoWidth - 18., h: bottomHeight - 35.},
    ~pan=id("D_InputPan"),
    ~rotation=id("D_Rotation"),
    ~feedbackL=id("D_FeedbackL"),
    ~feedbackR=id("D_FeedbackR"),
  )

  let settingsX = toneWidth + stereoWidth + 2. * gap
  let settingsWidth = w - settingsX
  let panel = Panel.make(body, ~title="settings", ~x=settingsX, ~y=bottomY, ~w=settingsWidth, ~h=bottomHeight)
  let s = Grid.make(ctx, panel.el, ~cw=Grid.fitColumns(settingsWidth, 5))
  s->Grid.choice(id("D_Unit"), 0, 0, "unit")
  s->Grid.toggle(id("D_Quantize"), 1, 0, "quantize")
  s->Grid.param(id("D_InputPan"), 2, 0, "input pan")
  s->Grid.param(id("D_Rotation"), 3, 0, "rotation")
  s->Grid.param(id("D_Dry"), 4, 0, "dry")
  s->Grid.param(id("D_LengthL"), 0, 1, "length l")
  s->Grid.param(id("D_FeedbackL"), 1, 1, "feedback l")
  s->Grid.choice(id("D_ReverseL"), 2, 1, "reverse l")
  s->Grid.param(id("D_LP"), 3, 1, "lowpass")
  s->Grid.param(id("D_Wet"), 4, 1, "wet")
  s->Grid.param(id("D_LengthR"), 0, 2, "length r")
  s->Grid.param(id("D_FeedbackR"), 1, 2, "feedback r")
  s->Grid.choice(id("D_ReverseR"), 2, 2, "reverse r")
  s->Grid.param(id("D_HP"), 3, 2, "highpass")

  // shown again when the tab comes up
  () => {
    echoRedraw.now()
    toneRedraw.now()
    stereoRedraw.now()
  }
}
