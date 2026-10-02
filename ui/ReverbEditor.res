// The reverb tab, as three pictures of the sound:
// - its shape over time: the dry hit, then (after the predelay) the reverb swelling and dying
//   away. Drag the start of the tail for the predelay and the wet level, its end for the length,
//   the top of the dry hit for the dry level;
// - how long each pitch rings: the length, shortened where the damping filters eat the lows
//   and highs on every pass. Drag the top for the length, the side points for the damping;
// - the room: drag its corner for the size. More diffusion scatters the reflections.
// The shapes come from the same network as the patch, run on an impulse.

open! Web

let hint = "The reverb's shape over time: drag the start of the tail for the predelay and wet level, its end for the length, the dry hit for the dry level. Shift for fine steps, right-click to reset."
let ringHint = "How long each pitch rings. Drag the top for the length, the side points for where the damping starts on the lows and the highs."
let roomHint = "The room: drag its corner for the size. The rays are the early reflections (early mix); more diffusion scatters them."

let floorDb = -60.

let make = (ctx: Ctx.t, body, e: FxRack.effect, ~w, ~h) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let gap = Grid.gap
  let settingsHeight = Grid.bareHeight(2)
  let rowHeight = 176.
  let topHeight = h - settingsHeight - rowHeight - 2. * gap
  let f = Float.toFixed(_, ~digits=1)

  let settings = (): FxDsp.reverbSettings => {
    size: get("R_Size"),
    length: get("R_Length"),
    dullness: get("R_Dullness"),
    brightness: get("R_Brightness"),
    angles: (get("R_1"), get("R_2"), get("R_3")),
    rotation: get("R_Rotation"),
    earlyMix: get("R_EarlyMix"),
  }
  let infinite = () => get("R_Length") >= FxDsp.infinite
  let wetId = id("R_Wet")
  let dryId = id("R_Dry")
  let predelayId = id("R_Predelay")
  let lengthId = id("R_Length")
  let sizeId = id("R_Size")
  let gain = db => db <= -100. ? 0. : Math.pow(10., ~exp=db / 20.)

  //==============================================================================
  // the shape over time

  let panel = Panel.make(body, ~title="sound", ~x=0., ~y=0., ~w, ~h=topHeight)
  let g = FxGraph.inPanel(ctx, panel, ~hint)
  let (left, right) = (16., g.w - 16.)
  let axisHeight = 14.
  let middle = (g.h - axisHeight) / 2.
  let halfHeight = middle - 8.
  // seconds across, held while dragging
  let from = ref(0.)
  let until = ref(2.)
  let xOf = t => left + (t - from.contents) / (until.contents - from.contents) * (right - left)
  let timeAt = x => from.contents + (x - left) / (right - left) * (until.contents - from.contents)
  // loudness up and down from the middle: 60 dB under where the tail starts at the middle (so
  // that it fades out at its length), the louder of it and the dry sound near the edges; held
  // while dragging
  let floor = ref(floorDb)
  let ceiling = ref(6.)
  let lift = db =>
    (FxDsp.clamp(db, floor.contents, ceiling.contents) - floor.contents) / (ceiling.contents - floor.contents) * halfHeight
  let dbAt = y => floor.contents + (middle - y) / halfHeight * (ceiling.contents - floor.contents)

  let grid = FxGraph.group(g.under)
  let shapes = FxGraph.group(g.under)
  let notes = FxGraph.group(g.under)

  let predelay = () => get("R_Predelay") / 1000.
  let tailSeconds = () => infinite() ? 8. : get("R_Length")
  let fit = () => {
    let pd = predelay()
    from := Math.min(0., pd) - 0.03 * Math.max(0.3, Math.abs(pd) + tailSeconds())
    until := Math.max(0.3, Math.max(0., pd) + tailSeconds() * 1.15)
  }

  // the network's response for `seconds` (its first n samples, at sr), kept until a setting that
  // shapes it changes. A longer one at the same rate starts the same, so while the span is held
  // (a predelay drag) it is made as long as the span allows.
  let cache = ref(None)
  let shapeIds = ["R_Size", "R_Length", "R_Dullness", "R_Brightness", "R_1", "R_2", "R_3", "R_Rotation", "R_EarlyMix"]
  let rate = seconds => FxDsp.clamp(60000. / seconds, 2000., 24000.)
  let impulse = seconds => {
    let key = shapeIds->Array.map(i => Float.toString(get(i)))->Array.join(",")
    let sr = rate(seconds)
    let n = Math.Int.max(1, Float.toInt(sr * seconds))
    switch cache.contents {
    | Some((k, (l, r, s))) if k == key && s == sr && TypedArray.length(l) >= n => (l, r, sr, n)
    | _ =>
      let span = until.contents - from.contents
      let (l, r) = FxDsp.reverbImpulse(settings(), ~sr, ~seconds=rate(span) == sr ? Math.max(seconds, span) : seconds)
      cache := Some((key, (l, r, sr)))
      (l, r, sr, n)
    }
  }
  // the tail's loudness (both sides) at time t after its start, smoothed over `window` seconds,
  // in dB at a wet level of 0 dB
  let envelope = ((l, r, sr, n), t, window) => {
    let (i0, i1) = (Math.Int.max(0, Float.toInt((t - window / 2.) * sr)), Float.toInt((t + window / 2.) * sr))
    let i1 = Math.Int.min(i1, n - 1)
    let sum = ref(0.)
    for i in i0 to i1 {
      let (a, b) = (ByteView.getUnsafe(l, i), ByteView.getUnsafe(r, i))
      sum := sum.contents + a * a + b * b
    }
    let n = Math.Int.max(1, i1 - i0 + 1)
    // RMS, raised to roughly the peaks you hear
    10. * Math.log10(Math.max(1e-12, sum.contents / Int.toFloat(n))) + 9.
  }

  // how loud the tail starts at a wet level of 0 dB, from the last drawing (held while dragging)
  let startLevel = ref(0.)
  let finish = () => {
    fit()
    g.redraw()
  }
  let startHandle = FxGraph.handle(
    g,
    ~ids=[predelayId, wetId],
    ~key="start",
    ~drag=({x, y}) => {
      model->ParamModel.set(predelayId, timeAt(x) * 1000.)
      model->ParamModel.set(wetId, gain(dbAt(y) - startLevel.contents))
    },
    ~finish,
  )
  let endHandle = FxGraph.handle(
    g,
    ~cls="node hollow",
    ~cursor="ew-resize",
    ~ids=[lengthId],
    ~key="end",
    ~drag=({x}) =>
      model->ParamModel.set(lengthId, x > right + 12. ? 120. : FxDsp.clamp(timeAt(x) - predelay(), 0.1, 29.9)),
    ~finish,
    ~wheel=lengthId,
  )
  let dryHandle = FxGraph.handle(
    g,
    ~cls="node faint",
    ~r=5.,
    ~cursor="ns-resize",
    ~ids=[dryId],
    ~key="dry",
    ~drag=({y}) => model->ParamModel.set(dryId, gain(dbAt(y))),
    ~finish,
  )

  // a label with a bracket under it, from x0 to x1
  let span = (x0, x1, y, text) => {
    FxGraph.line(notes, ~cls="bracket", x0, y, x1, y)
    FxGraph.line(notes, ~cls="bracket", x0, y - 3., x0, y + 3.)
    FxGraph.line(notes, ~cls="bracket", x1, y - 3., x1, y + 3.)
    FxGraph.text(notes, ~cls="note", ~anchor="middle", (x0 + x1) / 2., y - 4., text)
  }

  let draw = () => {
    g.svg->toggleClass("off", get("R_On") == 0.)
    grid->setTextContent("")
    shapes->setTextContent("")
    notes->setTextContent("")
    let bottom = g.h - axisHeight
    FxGraph.line(grid, ~cls="axis faint", left, middle, right, middle)
    let step = FxGraph.niceStep((until.contents - from.contents) * 1000., 10.)
    FxGraph.ticks(~from=Math.ceil(from.contents * 1000. / step) * step, ~until=until.contents * 1000., ~step, t => {
      let x = xOf(t / 1000.)
      FxGraph.line(grid, ~cls="axis faint", x, bottom - 4., x, bottom)
      FxGraph.text(grid, ~anchor="middle", x, g.h - 2., FxGraph.msText(t))
    })

    let pd = predelay()
    let seconds = Math.max(0.05, until.contents - Math.max(from.contents, pd))
    let response = impulse(seconds)
    let wetDb = FxGraph.gainDb(get("R_Wet"))
    let x0 = Math.max(left, xOf(pd))
    // the tail: a smooth shape, as loud above the middle as below
    let window = Math.max(0.006, (until.contents - from.contents) / 160.)
    let columns = Math.Int.max(2, Float.toInt((right - x0) / 3.))
    let levels = Array.fromInitializer(~length=columns + 1, c => {
      let x = x0 + Int.toFloat(c) * (right - x0) / Int.toFloat(columns)
      (x, envelope(response, timeAt(x) - pd, window) + wetDb)
    })
    if !g.dragging {
      startLevel :=
        levels->Array.slice(~start=0, ~end=8)->Array.reduce(-120., (m, (_, db)) => Math.max(m, db)) - wetDb
      let start = wetDb + startLevel.contents
      floor := start - 60.
      ceiling := Math.max(start, FxGraph.gainDb(get("R_Dry"))) + 4.
    }
    let upper = levels->Array.map(((x, db)) => (x, middle - lift(db)))
    let lower = levels->Array.map(((x, db)) => (x, middle + lift(db)))->Array.toReversed
    svgEl(
      shapes,
      "path",
      [("class", Str("tail")), ("d", Str(Plots.pathFrom(Array.concat(upper, lower)) ++ "Z"))],
    )->ignore
    // the dry hit
    let dx = xOf(0.)
    let dh = lift(FxGraph.gainDb(get("R_Dry")))
    svgEl(
      shapes,
      "path",
      [
        ("class", Str("hit")),
        ("d", Str(`M${f(dx - 3.)} ${f(middle)}L${f(dx)} ${f(middle - dh)}L${f(dx + 3.)} ${f(middle)}L${f(dx)} ${f(middle + dh)}Z`)),
      ],
    )->ignore
    dryHandle->FxGraph.place(dx, middle - dh)

    let startY = middle - lift(wetDb + startLevel.contents)
    startHandle->FxGraph.place(xOf(pd), startY)
    let endT = infinite() ? until.contents : pd + get("R_Length")
    endHandle->FxGraph.place(Math.min(right, xOf(endT)), middle)

    // what the shape is made of
    let noteY = bottom - 10.
    let hasGap = Math.abs(pd) > 0.002
    if hasGap {
      let (a, b) = pd > 0. ? (0., pd) : (pd, 0.)
      span(
        xOf(a),
        xOf(b),
        noteY,
        pd > 0. ? `predelay ${FxGraph.msText(pd * 1000.)}` : `dry ${FxGraph.msText(-.pd * 1000.)} late`,
      )
    }
    span(
      xOf(Math.max(0., pd)),
      Math.min(right, xOf(endT)),
      noteY - (hasGap ? 16. : 0.),
      infinite() ? "the tail never dies away" : `the tail: ${FxGraph.short(g, lengthId)} to fade by 60 dB`,
    )
    FxGraph.text(notes, ~cls="note", ~anchor="middle", dx, middle - dh - 8., "dry")

    switch g.focus {
    | Some("start") =>
      g->FxGraph.readout(
        ~x=startHandle.x,
        ~y=startHandle.y,
        `predelay ${FxGraph.short(g, predelayId)}  ·  wet ${FxGraph.short(g, wetId)}`,
      )
    | Some("end") =>
      g->FxGraph.readout(~x=endHandle.x, ~y=endHandle.y, `length ${FxGraph.short(g, lengthId)}`)
    | Some(_) => g->FxGraph.readout(~x=dryHandle.x, ~y=dryHandle.y, `dry ${FxGraph.short(g, dryId)}`)
    | None => g->FxGraph.hideReadout
    }
  }
  g.redraw = draw

  let soundRedraw = FxGraph.redraw(g, () => {
    if !g.dragging {
      fit()
    }
    draw()
  })
  let allIds =
    [
      "R_On",
      "R_Size",
      "R_Length",
      "R_Dullness",
      "R_Brightness",
      "R_Dry",
      "R_Wet",
      "R_1",
      "R_2",
      "R_3",
      "R_Rotation",
      "R_Predelay",
      "R_EarlyMix",
    ]->Array.map(id)
  g->FxGraph.listen(allIds, soundRedraw.request)

  //==============================================================================
  // how long each pitch rings

  let rowY = topHeight + gap
  let ringWidth = (w - gap) / 2.
  let ring = Panel.make(body, ~title="ring time by pitch", ~x=0., ~y=rowY, ~w=ringWidth, ~h=rowHeight)
  let rg = FxGraph.inPanel(ctx, ring, ~hint=ringHint)
  let (rLeft, rRight) = (40., rg.w - 10.)
  let (rTop, rBottom) = (14., rg.h - 14.)
  let (rxOf, hzAt) = FxGraph.logScale(~lo=20., ~hi=20000., ~left=rLeft, ~right=rRight)
  // seconds at the top, held while dragging
  let ceiling = ref(2.)
  let ryOf = s => rBottom - FxDsp.clamp(s / ceiling.contents, 0., 1.05) * (rBottom - rTop)
  let secondsAt = y => (rBottom - y) / (rBottom - rTop) * ceiling.contents
  let rGrid = FxGraph.group(rg.under)
  let rFill = FxGraph.path(rg.under, ~cls="fill")
  let rCurve = FxGraph.path(rg.under, ~cls="curve")
  let rNotes = FxGraph.group(rg.under)

  // A pitch's ring time: the length, less what the damping filters take on every pass (a pass
  // takes about the room size).
  let ringTime = hz => {
    let passesPerSecond = 1000. / (get("R_Size") * 0.845)
    let loss =
      -.FxGraph.gainDb(
        FxDsp.loopGain(
          ~lp=FxDsp.reverbLowpass(get("R_Dullness")),
          ~hp=FxDsp.reverbHighpass(get("R_Brightness")),
          hz,
        ),
      )
    let decay = (infinite() ? 0. : 60. / get("R_Length")) + passesPerSecond * loss
    decay <= 1e-6 ? infinity : 60. / decay
  }
  let rFit = () => {
    let top = (infinite() ? 10. : get("R_Length")) * 1.3
    let step = FxGraph.niceStep(top, 1.)
    ceiling := step * Math.ceil(top / step)
  }
  let rPoint = (i, ~cursor, ~drag) =>
    FxGraph.handle(
      rg,
      ~cursor,
      ~ids=[i],
      ~drag,
      ~finish=() => {
        rFit()
        rg.redraw()
      },
      ~wheel=i,
    )
  let brightId = id("R_Brightness")
  let dullId = id("R_Dullness")
  let lengthPoint = rPoint(lengthId, ~cursor="ns-resize", ~drag=({y}) =>
    model->ParamModel.set(lengthId, FxDsp.clamp(secondsAt(y), 0.1, 29.9))
  )
  let lowPoint = rPoint(brightId, ~cursor="ew-resize", ~drag=({x}) =>
    model->ParamModel.set(brightId, FxDsp.reverbHighpassValue(hzAt(x)))
  )
  let highPoint = rPoint(dullId, ~cursor="ew-resize", ~drag=({x}) =>
    model->ParamModel.set(dullId, FxDsp.reverbLowpassValue(hzAt(x)))
  )

  let rDraw = () => {
    rGrid->setTextContent("")
    rNotes->setTextContent("")
    [100., 1000., 10000.]->Array.forEach(hz => {
      let x = rxOf(hz)
      FxGraph.line(rGrid, ~cls="axis faint", x, rTop, x, rBottom)
      FxGraph.text(rGrid, ~anchor="middle", x, rg.h - 2., FxGraph.hzTick(hz))
    })
    FxGraph.text(rGrid, rLeft, rg.h - 2., "lows")
    FxGraph.text(rGrid, ~anchor="end", rRight, rg.h - 2., "highs")
    FxGraph.ticks(~until=ceiling.contents + 1e-9, ~step=FxGraph.niceStep(ceiling.contents, 4.), s => {
      let y = ryOf(s)
      FxGraph.line(rGrid, ~cls=s == 0. ? "axis" : "axis faint", rLeft, y, rRight, y)
      FxGraph.text(rGrid, ~anchor="end", rLeft - 4., y + 3., FxGraph.msText(s * 1000.))
    })
    let at = t => {
      let x = rLeft + (rRight - rLeft) * t
      (x, ryOf(Math.min(ceiling.contents * 1.05, ringTime(hzAt(x)))))
    }
    let points = [at(0.)]
    points->Plots.trace(at, ~steps=48)
    let d = Plots.pathFrom(points)
    rCurve->FxGraph.setPath(d)
    rFill->FxGraph.setPath(`${d}L${f(rRight)} ${f(rBottom)}L${f(rLeft)} ${f(rBottom)}Z`)
    // the top: the length; the sides: where the damping starts
    let (px, _) = points->Array.reduce((rLeft, infinity), ((bx, by), (x, y)) => y < by ? (x, y) : (bx, by))
    lengthPoint->FxGraph.place(px, ryOf(infinite() ? ceiling.contents : get("R_Length")))
    let lowHz = FxDsp.reverbHighpass(get("R_Brightness"))
    let highHz = FxDsp.reverbLowpass(get("R_Dullness"))
    lowPoint->FxGraph.place(rxOf(lowHz), ryOf(Math.min(ceiling.contents, ringTime(lowHz))))
    highPoint->FxGraph.place(rxOf(highHz), ryOf(Math.min(ceiling.contents, ringTime(highHz))))
    let ringText = hz => {
      let t = ringTime(hz)
      t == infinity ? "forever" : FxGraph.msText(t * 1000.)
    }
    FxGraph.text(rNotes, ~cls="note", rLeft + 4., rTop + 8., `lows (100 Hz) ring ${ringText(100.)}`)
    FxGraph.text(rNotes, ~cls="note", ~anchor="end", rRight - 4., rTop + 8., `highs (8 kHz) ${ringText(8000.)}`)
    switch rg.focus {
    | Some(i) =>
      let (h: FxGraph.handle, text) = if i == lengthId {
        (lengthPoint, `length ${FxGraph.short(rg, lengthId)}`)
      } else if i == brightId {
        (lowPoint, `lows damped below ${FxGraph.hzText(lowHz)} (brightness ${FxGraph.short(rg, i)})`)
      } else {
        (highPoint, `highs damped above ${FxGraph.hzText(highHz)} (dullness ${FxGraph.short(rg, i)})`)
      }
      rg->FxGraph.readout(~x=h.x, ~y=h.y, text)
    | None => rg->FxGraph.hideReadout
    }
  }
  rg.redraw = rDraw
  let ringRedraw = FxGraph.redraw(rg, () => {
    if !rg.dragging {
      rFit()
    }
    rDraw()
  })
  rg->FxGraph.listen(["R_Size", "R_Length", "R_Dullness", "R_Brightness"]->Array.map(id), ringRedraw.request)

  //==============================================================================
  // the room

  let room = Panel.make(body, ~title="room", ~x=ringWidth + gap, ~y=rowY, ~w=ringWidth, ~h=rowHeight)
  let og = FxGraph.inPanel(ctx, room, ~hint=roomHint)
  let oRays = FxGraph.group(og.under)
  let (ox, oy) = (16., 10.)
  let biggest = og.h - 2. * oy
  // a side for a size (10..250 ms), and back
  let sideOf = ms => 24. + Math.sqrt((FxDsp.clamp(ms, 10., 250.) - 10.) / 240.) * (biggest - 24.)
  let sizeAt = side => 10. + Math.pow(FxDsp.clamp((side - 24.) / (biggest - 24.), 0., 1.), ~exp=2.) * 240.
  let corner = FxGraph.handle(
    og,
    ~cursor="nwse-resize",
    ~ids=[sizeId],
    ~drag=({x, y}) => model->ParamModel.set(sizeId, sizeAt(Math.max(x - ox, y - oy))),
    ~wheel=sizeId,
  )

  // how far the network mixes its lines: 0 when the diffusion angles leave each alone
  let diffusion = () => {
    let m = FxDsp.mixMatrix((get("R_1"), get("R_2"), get("R_3")))
    1. - [0, 1, 2, 3]->Array.reduce(0., (s, i) => s + Math.abs(m->Array.getUnsafe(i)->Array.getUnsafe(i))) / 4.
  }

  let oDraw = () => {
    oRays->setTextContent("")
    let side = sideOf(get("R_Size"))
    svgEl(
      oRays,
      "rect",
      [("class", Str("room")), ("x", Num(ox)), ("y", Num(oy)), ("width", Num(side)), ("height", Num(side))],
    )->ignore
    // a source and a listener, and reflections between them off the walls
    let (sx, sy) = (ox + side * 0.3, oy + side * 0.35)
    let (lx, ly) = (ox + side * 0.7, oy + side * 0.7)
    let early = get("R_EarlyMix")
    let scatter = diffusion()
    let rays = 4 + Float.toInt(Math.round(scatter * 10.))
    for k in 0 to rays - 1 {
      let a = Int.toFloat(k) / Int.toFloat(rays) * 2. * Math.Constants.pi + 0.4
      // where the ray meets a wall, then on to the listener (scattered with the diffusion)
      let jitter = Math.sin(Int.toFloat(k) * 7.3) * scatter * side * 0.25
      let wx = FxDsp.clamp(sx + Math.cos(a) * side, ox, ox + side)
      let wy = FxDsp.clamp(sy + Math.sin(a) * side, oy, oy + side)
      svgEl(
        oRays,
        "path",
        [
          ("class", Str("ray")),
          ("stroke-opacity", Num(0.15 + 0.7 * early)),
          ("d", Str(`M${f(sx)} ${f(sy)}L${f(wx)} ${f(wy)}L${f(lx + jitter)} ${f(ly - jitter)}`)),
        ],
      )->ignore
    }
    svgEl(oRays, "circle", [("class", Str("source")), ("cx", Num(sx)), ("cy", Num(sy)), ("r", Num(3.5))])->ignore
    svgEl(oRays, "circle", [("class", Str("listener")), ("cx", Num(lx)), ("cy", Num(ly)), ("r", Num(3.5))])->ignore
    corner->FxGraph.place(ox + side, oy + side)
    let tx = ox + biggest + 18.
    let metres = get("R_Size") * 0.343
    FxGraph.text(oRays, ~cls="note big", tx, oy + 14., `${FxGraph.short(og, sizeId)} room`)
    FxGraph.text(
      oRays,
      ~cls="note",
      tx,
      oy + 32.,
      `sound crosses it in about ${Float.toFixed(get("R_Size"), ~digits=0)} ms (${Float.toFixed(metres, ~digits=0)} m)`,
    )
    FxGraph.text(oRays, ~cls="note", tx, oy + 52., `early reflections: ${Float.toFixed(early * 100., ~digits=0)} %`)
    FxGraph.text(
      oRays,
      ~cls="note",
      tx,
      oy + 68.,
      `diffusion: ${scatter < 0.15 ? "little (a metallic ring)" : scatter < 0.45 ? "some" : "smooth"}`,
    )
    FxGraph.text(
      oRays,
      ~cls="note",
      tx,
      oy + 84.,
      `the two sides: ${Math.abs(Math.sin(get("R_Rotation"))) < 0.15 ? "kept apart" : "mixed"} (stereo mix)`,
    )
    if og.focus != None {
      og->FxGraph.readout(~x=corner.x, ~y=corner.y, `size ${FxGraph.short(og, sizeId)}`)
    } else {
      og->FxGraph.hideReadout
    }
  }
  og.redraw = oDraw
  let roomRedraw = FxGraph.redraw(og, oDraw)
  og->FxGraph.listen(["R_Size", "R_EarlyMix", "R_1", "R_2", "R_3", "R_Rotation"]->Array.map(id), roomRedraw.request)

  //==============================================================================
  // every setting

  let settingsPanel = Panel.make(body, ~x=0., ~y=rowY + rowHeight + gap, ~w, ~h=settingsHeight)
  let s = Grid.make(ctx, settingsPanel.el, ~y=Grid.padBottom, ~cw=Grid.fitColumns(w, 7))
  s->Grid.param(id("R_Size"), 0, 0, "size")
  s->Grid.param(id("R_Length"), 1, 0, "length")
  s->Grid.param(id("R_Predelay"), 2, 0, "predelay")
  s->Grid.param(id("R_Dry"), 3, 0, "dry")
  s->Grid.param(id("R_Wet"), 4, 0, "wet")
  s->Grid.param(id("R_Dullness"), 5, 0, "dullness (highs)")
  s->Grid.param(id("R_Brightness"), 6, 0, "brightness (lows)")
  s->Grid.param(id("R_EarlyMix"), 0, 1, "early")
  s->Grid.param(id("R_1"), 1, 1, "diffusion 1")
  s->Grid.param(id("R_2"), 2, 1, "diffusion 2")
  s->Grid.param(id("R_3"), 3, 1, "diffusion 3")
  s->Grid.param(id("R_Rotation"), 4, 1, "stereo mix")

  () => {
    soundRedraw.now()
    ringRedraw.now()
    roomRedraw.now()
  }
}
