// The compressor tab, laid out like a multiband dynamics plugin (Dynastia, OTT):
// - a column per band (low, mid, high): its level meter from 0 to -60 dB with the live level
//   and the gain the band gets, and two thresholds to drag: downward compression above the top
//   one, upward below the bottom one. Beside the meter, the band's ratios and output gain; the
//   switch in its title takes the band out;
// - the compress amount, a big knob scaling every band's gain change, with attack and release;
// - along the bottom: input and output gain, the crossover between the bands (drag either
//   split), and the dry/wet mix.
// With one band, the mid band's settings work on the whole sound and the others rest.

open! Web

let hint = "Drag a band's thresholds: compressed downward above the top one, lifted upward below the bottom one. Shift for fine steps, right-click to reset."

let (floorDb, ceilDb) = (-60., 0.)

type meter = {level: array<float>, gain: array<float>}

@get external meterWhich: JSON.t => int = "which"
@get external meterLevel: JSON.t => array<float> = "level"
@get external meterGain: JSON.t => array<float> = "gain"

let make = (ctx: Ctx.t, body, e: FxRack.effect, ~w, ~h) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let gap = Grid.gap
  let bottomH = Grid.panelHeight(1) + 10.
  let topH = h - bottomH - gap
  let rightW = 250.
  let bandW = (w - rightW - 3. * gap) / 3.
  let status = i => ctx.status->Status.show(model->ParamModel.longText(i))
  let single = () => get("Cp_Bands") == 0.

  // the gain band b gives a steady level x (dB): down above its threshold, up below its up
  // threshold (capped at +30 dB), scaled by the amount, then its trim
  let bandGain = (b, x: float) => {
    let band = PorridgeParams.compressorBands[b]->Option.mapOr("Mid", Pair.first)
    let (t, r) = (get(`Cp_${band}Thresh`), get(`Cp_${band}Ratio`))
    let (u, ru) = (Math.min(get(`Cp_${band}UpThresh`), t), get(`Cp_${band}UpRatio`))
    let g = if x > t {
      (t + (x - t) / r) - x
    } else if x < u && x > -90. {
      Math.min(30., (u - (u - x) / ru) - x)
    } else {
      0.
    }
    g * get("Cp_Depth") + get(`Cp_${band}Gain`)
  }

  let meters = ref({level: [-120., -120., -120.], gain: [0., 0., 0.]})
  // each band's drawing: of everything, and of what the meter moves
  let redraws: array<unit => unit> = []
  let meterRedraws: array<unit => unit> = []

  //==============================================================================
  // a band

  let bandPanel = (b, (band, name)) => {
    let p = Panel.make(body, ~title=name, ~x=Int.toFloat(b) * (bandW + gap), ~y=0., ~w=bandW, ~h=topH)
    p->Panel.headerToggle(ctx, id(`Cp_${band}On`), ~label="on")
    let meterW = 112.
    let g = FxGraph.make(ctx, p.el, {x: 8., y: 25., w: meterW, h: topH - 35.})
    let (top, bottom) = (14., g.h - 14.)
    let yOf = db => top + (ceilDb - FxDsp.clamp(db, floorDb, ceilDb)) / (ceilDb - floorDb) * (bottom - top)
    let dbAt = y => ceilDb - (y - top) / (bottom - top) * (ceilDb - floorDb)
    let scale = FxGraph.group(g.under)
    let bars = FxGraph.group(g.under)
    let barX = 30.
    let barW = 26.
    FxGraph.ticks(~from=floorDb, ~until=ceilDb, ~step=6., db => {
      let y = yOf(db)
      FxGraph.line(scale, ~cls="grid", barX, y, g.w - 4., y)
      FxGraph.text(scale, ~anchor="end", barX - 4., y + 3.5, Float.toString(db))
    })
    let zone = svgEl(bars, "rect", [("class", Str("compzone")), ("x", Num(barX)), ("width", Num(g.w - 4. - barX))])
    let levelBar = svgEl(bars, "rect", [("class", Str("complevel")), ("x", Num(barX)), ("width", Num(barW))])
    let gainBar = svgEl(bars, "rect", [("class", Str("compgain")), ("x", Num(barX + barW + 4.)), ("width", Num(8.))])

    // a threshold: a line across, a point at its end and its value
    let threshold = (param, ~below) => {
      let i = id(param)
      let line = svgEl(g.layer, "line", [("class", Str("compthresh")), ("x1", Num(barX))])
      let text = svgEl(g.layer, "text", [("class", Str("readout")), ("text-anchor", Str("end"))])
      let hd = FxGraph.handle(
        g,
        ~cursor="ns-resize",
        ~ids=[i],
        ~hot=false,
        ~drag=({y}) => {
          let v = Math.round(dbAt(y) * 10.) / 10.
          // the upward threshold stays under the downward one
          let other = model->ParamModel.get(id(below ? `Cp_${band}Thresh` : `Cp_${band}UpThresh`))
          model->ParamModel.set(i, below ? Math.min(v, other) : Math.max(v, other))
        },
        ~wheel=i,
        ~hover=on => on ? status(i) : ctx.status->Status.show(hint),
      )
      () => {
        let y = yOf(model->ParamModel.get(i))
        let x = g.w - 10.
        line->setAttribute("x2", Num(x))
        line->setAttribute("y1", Num(y))
        line->setAttribute("y2", Num(y))
        hd->FxGraph.place(x, y)
        text->setAttribute("x", Num(x - 8.))
        text->setAttribute("y", Num(below ? y + 14. : y - 6.))
        text->setTextContent(FxGraph.dbText(model->ParamModel.get(i)))
      }
    }
    let down = threshold(`Cp_${band}Thresh`, ~below=false)
    let up = threshold(`Cp_${band}UpThresh`, ~below=true)

    // the band's curve: output level for a steady input level, with the live level on it
    let cx0 = meterW + 16.
    let cTop = 25. + 3. * Grid.rowHeight + 22.
    let readout = el("div", ~cls="note", ~parent=p.el)->place(cx0, cTop - 18., ~w=bandW - cx0 - 10., ~h=16.)
    let cs = Math.min(bandW - cx0 - 12., topH - cTop - 12.)
    let cg = FxGraph.make(ctx, p.el, {x: cx0 + (bandW - cx0 - 10. - cs) / 2., y: cTop, w: cs, h: cs})
    let cl = FxGraph.group(cg.svg)
    let dot = svgEl(cg.svg, "circle", [("class", Str("dot")), ("r", Num(3.5))])
    let pos = (db: float) => 4. + (FxDsp.clamp(db, floorDb, ceilDb) - floorDb) / (ceilDb - floorDb) * (cs - 8.)
    let drawCurve = () => {
      cl->setTextContent("")
      FxGraph.line(cl, ~cls="axis", pos(floorDb), cs - pos(floorDb), pos(ceilDb), cs - pos(ceilDb))
      [-12., -24., -36., -48.]->Array.forEach(v => {
        FxGraph.line(cl, ~cls="grid", pos(v), 4., pos(v), cs - 4.)
        FxGraph.line(cl, ~cls="grid", 4., cs - pos(v), cs - 4., cs - pos(v))
      })
      let n = 60
      let points = Array.fromInitializer(~length=n + 1, k => {
        let x = floorDb + (ceilDb - floorDb) * Int.toFloat(k) / Int.toFloat(n)
        (pos(x), cs - pos(x + bandGain(b, x)))
      })
      FxGraph.path(cl, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(points))
    }

    // the live level, the gain it gets, and where it is on the curve
    let drawMeter = () => {
      let level = meters.contents.level[b]->Option.getOr(-120.)
      let gain = meters.contents.gain[b]->Option.getOr(0.)
      let yl = yOf(level)
      levelBar->setAttribute("y", Num(yl))
      levelBar->setAttribute("height", Num(Math.max(0., bottom - yl)))
      // the gain change, from the level it acts on: down when compressing, up when lifting
      let yg = yOf(level + gain)
      gainBar->setAttribute("y", Num(Math.min(yl, yg)))
      gainBar->setAttribute("height", Num(Math.abs(yg - yl)))
      gainBar->setAttribute("class", Str(gain >= 0. ? "compgain up" : "compgain"))
      readout->setTextContent(
        level <= -100. ? "" : `in ${Float.toFixed(level, ~digits=1)} dB · ${gain >= 0. ? "lift" : "cut"} ${Float.toFixed(Math.abs(gain), ~digits=1)} dB`,
      )
      dot->setStyle("display", level > floorDb ? "" : "none")
      dot->setAttribute("cx", Num(pos(level)))
      dot->setAttribute("cy", Num(cs - pos(level + bandGain(b, level))))
    }

    let draw = () => {
      let resting = single() && b != 1 || get(`Cp_${band}On`) == 0.
      p.el->toggleClass("resting", resting)
      let (yd, yu) = (yOf(get(`Cp_${band}Thresh`)), yOf(get(`Cp_${band}UpThresh`)))
      zone->setAttribute("y", Num(yd))
      zone->setAttribute("height", Num(Math.max(0., yu - yd)))
      down()
      up()
      drawCurve()
      drawMeter()
    }
    redraws->Array.push(draw)
    meterRedraws->Array.push(drawMeter)
    model->ParamModel.listenEach(
      [
        `Cp_${band}Thresh`,
        `Cp_${band}UpThresh`,
        `Cp_${band}Ratio`,
        `Cp_${band}UpRatio`,
        `Cp_${band}Gain`,
        `Cp_${band}On`,
        "Cp_Bands",
        "Cp_Depth",
      ]->Array.map(id),
      draw,
    )

    let grid = Grid.make(ctx, p.el, ~x=meterW + 16., ~cw=bandW - meterW - 26.)
    grid->Grid.param(id(`Cp_${band}Ratio`), 0, 0, "ratio")
    grid->Grid.param(id(`Cp_${band}UpRatio`), 0, 1, "up ratio")
    grid->Grid.param(id(`Cp_${band}Gain`), 0, 2, "gain")
  }
  PorridgeParams.compressorBands->Array.forEachWithIndex((band, b) => bandPanel(b, band))

  //==============================================================================
  // the compress amount

  let right = Panel.make(body, ~title="compress", ~x=w - rightW, ~y=0., ~w=rightW, ~h=topH)
  let size = Math.min(rightW - 40., topH - 25. - 3. * Grid.rowHeight - 30.)
  let knobBox: box = {x: (rightW - size) / 2., y: 30., w: size, h: size}
  let knob = Plots.svg(right.el, knobBox)
  knob->setAttribute("class", Str("plot bigknob"))
  let (kc, kr) = (size / 2., size / 2. - 10.)
  let arcAt = (v: float) => {
    let a = (-135. + 270. * v) * Math.Constants.pi / 180.
    (kc + kr * Math.sin(a), kc - kr * Math.cos(a))
  }
  let f = Float.toFixed(_, ~digits=2)
  let arc = (v: float) => {
    let (x0, y0) = arcAt(0.)
    let (x1, y1) = arcAt(v)
    `M${f(x0)} ${f(y0)} A${f(kr)} ${f(kr)} 0 ${v > 2. /. 3. ? "1" : "0"} 1 ${f(x1)} ${f(y1)}`
  }
  svgEl(knob, "path", [("class", Str("knobtrack")), ("d", Str(arc(0.9999)))])->ignore
  let fill = svgEl(knob, "path", [("class", Str("knobfill"))])
  svgEl(knob, "circle", [("class", Str("knobcap")), ("cx", Num(kc)), ("cy", Num(kc)), ("r", Num(kr - 14.))])->ignore
  let pointer = svgEl(knob, "line", [("class", Str("knobpointer"))])
  let value = svgEl(knob, "text", [("class", Str("knobvalue")), ("x", Num(kc)), ("y", Num(kc + 6.)), ("text-anchor", Str("middle"))])
  let depthId = id("Cp_Depth")
  let drawKnob = () => {
    let v = model->ParamModel.get(depthId)
    fill->setAttribute("d", Str(v > 0.001 ? arc(v) : ""))
    let (x, y) = arcAt(v)
    pointer->setAttribute("x1", Num(kc + (x - kc) * 0.35))
    pointer->setAttribute("y1", Num(kc + (y - kc) * 0.35))
    pointer->setAttribute("x2", Num(kc + (x - kc) * 0.7))
    pointer->setAttribute("y2", Num(kc + (y - kc) * 0.7))
    value->setTextContent(Float.toFixed(v * 100., ~digits=0) ++ " %")
  }
  model->ParamModel.listen(depthId, drawKnob)
  drawKnob()
  knob->onPointer(#pointerdown, ev =>
    switch ev->button {
    | 0 =>
      ev->preventDefault
      model->ParamModel.beginGesture(depthId)
      Controls.dragBy(ctx, knob, ev, ~onMove=(_, dy, mv) => {
        let d = -.dy / 200. * (mv->shiftKey ? 0.1 : 1.)
        model->ParamModel.set(depthId, FxDsp.clamp(model->ParamModel.get(depthId) + d, 0., 1.))
        status(depthId)
      }, ~onUp=() => model->ParamModel.endGesture(depthId))
    | 2 => model->ParamModel.gestureSet(depthId, (model->ParamModel.def(depthId)).init)
    | _ => ()
    }
  )
  knob->suppressContextMenu
  knob->onWheel(ev => Controls.wheelParam(model, depthId, ev))
  ctx.status->Status.hover(knob, () => model->ParamModel.longText(depthId))
  el("div", ~cls="grp center", ~text="compress", ~parent=right.el)->place(0., knobBox.y + size + 2., ~w=rightW)->ignore
  let rg = Grid.make(ctx, right.el, ~y=topH - 3. * Grid.rowHeight - Grid.padBottom, ~cw=(rightW - 2. - 2. * Grid.padX + Grid.columnGap) / 2.)
  rg->Grid.param(id("Cp_Attack"), 0, 0, "attack")
  rg->Grid.param(id("Cp_Release"), 1, 0, "release")
  rg->Grid.choice(id("Cp_Bands"), 0, 1, "bands", ~span=2)
  rg->Grid.param(id("Cp_Mix"), 0, 2, "mix", ~span=2)

  //==============================================================================
  // along the bottom: levels and the crossover

  let strip = Panel.make(body, ~title="levels and crossover", ~x=0., ~y=topH + gap, ~w, ~h=bottomH)
  let sg = Grid.make(ctx, strip.el)
  sg->Grid.param(id("Cp_InGain"), 0, 0, "input")
  sg->Grid.param(id("Cp_OutGain"), 1, 0, "output")
  let trackX = 2. * Grid.columnWidth + 20.
  let xg = FxGraph.make(ctx, strip.el, {x: trackX, y: 22., w: w - trackX - 14., h: bottomH - 28.})
  let xl = xg.layer
  let (tl, tr) = (14., xg.w - 14.)
  let (xOfHz, _) = FxGraph.logScale(~lo=20., ~hi=20000., ~left=tl, ~right=tr)
  let ty = xg.h / 2. + 2.
  FxGraph.line(xl, ~cls="axis", tl, ty, tr, ty)
  [100., 1000., 10000.]->Array.forEach(hz => {
    let x = xOfHz(hz)
    FxGraph.line(xl, ~cls="grid", x, ty - 6., x, ty + 6.)
    FxGraph.text(xl, ~anchor="start", x + 3., ty - 3., FxGraph.hzTick(hz))
  })
  let bandLabels = ["low", "mid", "high"]->Array.map(t => {
    let e = svgEl(xl, "text", [("class", Str("note big")), ("text-anchor", Str("middle")), ("y", Num(ty + 18.))])
    e->setTextContent(t)
    e
  })
  let hzOf = i => PorridgeParams.expValue(20., 20000., model->ParamModel.get(i))
  let split = (param, ~low) => {
    let i = id(param)
    let readout = svgEl(xg.hits, "text", [("class", Str("readout")), ("text-anchor", Str("middle"))])
    let hd = FxGraph.handle(
      xg,
      ~cursor="ew-resize",
      ~ids=[i],
      ~hot=false,
      ~drag=({x}) => {
        let x = FxDsp.clamp(x, tl, tr)
        let v = (x - tl) / (tr - tl)
        // the low split stays under the high one
        let other = model->ParamModel.get(id(low ? "Cp_HighSplit" : "Cp_LowSplit"))
        model->ParamModel.set(i, low ? Math.min(v, other - 0.02) : Math.max(v, other + 0.02))
      },
      ~wheel=i,
    )
    () => {
      let x = xOfHz(hzOf(i))
      hd->FxGraph.place(x, ty)
      hd->FxGraph.show(!single())
      readout->setAttribute("x", Num(x))
      readout->setAttribute("y", Num(ty - 10.))
      readout->setTextContent(single() ? "" : FxGraph.hzText(hzOf(i)))
    }
  }
  let lowSplit = split("Cp_LowSplit", ~low=true)
  let highSplit = split("Cp_HighSplit", ~low=false)
  let drawSplits = () => {
    lowSplit()
    highSplit()
    let (a, b) = (xOfHz(hzOf(id("Cp_LowSplit"))), xOfHz(hzOf(id("Cp_HighSplit"))))
    let centres = single() ? [-100., (tl + tr) / 2., -100.] : [(tl + a) / 2., (a + b) / 2., (b + tr) / 2.]
    bandLabels->Array.forEachWithIndex((e, k) => e->setAttribute("x", Num(centres->Array.getUnsafe(k))))
  }
  model->ParamModel.listenEach(["Cp_LowSplit", "Cp_HighSplit", "Cp_Bands"]->Array.map(id), drawSplits)
  drawSplits()

  //==============================================================================
  // the meters, from the patch

  let drawAll = () => redraws->Array.forEach(f => f())
  let drawMeters = perFrame(() => meterRedraws->Array.forEach(f => f()))
  ctx.pc->PatchConnection.addEndpointListener("compMeterOut", j =>
    if meterWhich(j) == e.copy - 1 && body->offsetParent->Option.isSome {
      meters := {level: meterLevel(j), gain: meterGain(j)}
      drawMeters()
    }
  )
  drawAll()
  () => {
    drawAll()
    drawSplits()
    drawKnob()
  }
}
