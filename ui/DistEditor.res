// The distortion tab: the curve from input to output, and a full-scale sine before and after,
// with the drive, limit, output gain and the oversampling filters' gain in them. Drag the sine
// up or down for the drive.
//
// With the custom shape (like Fruity WaveShaper) the curve is the shape itself, to edit: drag
// a point, click between them to add one, right-click one to take it out, and drag the small
// point in the middle of a segment up or down to bend it. The drive moves the sound across it.
//
// Oatmeal's distortion also says where it sits (in every voice, or on the whole sound before the
// rack); the others run in the rack.

open! Web

let hint = "Drag up or down on the sine for more or less drive (pregain), shift for fine steps."
let shapeHint = "The custom shape: drag a point, click between points to add one, right-click a point to take it out, drag a segment's middle point up or down to bend it. Shift for fine steps."

let custom = 5.
let maxPoints = PorridgeParams.shaperPoints

// `id` maps Oatmeal's distortion's parameters to this one's; `placement` shows where Oatmeal's
// sits.
let make = (ctx: Ctx.t, body, ~id: string => string, ~placement) => {
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let (gap, w) = (Grid.gap, Style.designWidth - 12.)
  let settingsHeight = Grid.rowHeight + 2. * Grid.padBottom - Style.controlGap
  let h = Style.pageHeight - 6. - 34. - settingsHeight - gap
  let half = (w - gap) / 2.
  let f = Float.toFixed(_, ~digits=2)

  let isCustom = () => get("Sat_Type") == custom
  let count = () => Math.Int.min(maxPoints, Float.toInt(get("Sat_Points")) + 2)
  let xId = k => id(PorridgeParams.shaperX(k + 1))
  let yId = k => id(PorridgeParams.shaperY(k + 1))
  let bendId = k => id(PorridgeParams.shaperBend(k + 1))
  let points = () =>
    Array.fromInitializer(~length=count(), k => (
      model->ParamModel.get(xId(k)),
      model->ParamModel.get(yId(k)),
      model->ParamModel.get(bendId(k)),
    ))
  // writes a whole shape (its points in order, the ends at -1 and 1)
  let setPoints = (list: array<(float, float, float)>) => {
    let n = Array.length(list)
    model->ParamModel.gestureSet(id("Sat_Points"), Int.toFloat(n - 2))
    list->Array.forEachWithIndex(((x, y, bend), k) => {
      let x = k == 0 ? -1. : k == n - 1 ? 1. : x
      [(xId(k), x), (yId(k), y), (bendId(k), bend)]->Array.forEach(((i, v)) =>
        if model->ParamModel.get(i) != v {
          model->ParamModel.gestureSet(i, v)
        }
      )
    })
  }

  let distort = x =>
    FxDsp.distort(
      ~kind=Float.toInt(get("Sat_Type")),
      ~oversample=Float.toInt(get("Sat_Oversample")),
      ~pregain=get("Sat_Pregain"),
      ~limit=get("Sat_Limit"),
      ~postgain=get("Sat_Postgain"),
      ~custom=points(),
      x,
    )
  let scale = ref(1.)
  let fit = () => {
    let peak =
      Array.fromInitializer(~length=201, k => Math.abs(distort(Int.toFloat(k) / 100. - 1.)))->Math.maxMany
    scale := Math.max(1., Math.ceil(peak * 1.1 * 4.) / 4.)
  }

  let pregain = id("Sat_Pregain")
  let dragging = ref(false)
  let redraws = []
  let request = () => redraws->Array.forEach((r: FxGraph.redraw) => r.request())

  let graph = (~title, ~x, ~drive: unit => bool, draw) => {
    let panel = Panel.make(body, ~title, ~x, ~y=0., ~w=half, ~h)
    let g = FxGraph.make(ctx, panel.el, {x: 8., y: 25., w: half - 18., h: h - 35.})
    let grid = FxGraph.group(g.svg)
    let layer = FxGraph.group(g.svg)
    let redraw = FxGraph.redraw(g, () => {
      if !dragging.contents {
        fit()
      }
      grid->setTextContent("")
      layer->setTextContent("")
      g.svg->toggleClass("off", get("Sat_Type") == 0.)
      draw(g, grid, layer)
    })
    redraws->Array.push(redraw)
    // drag up for more drive
    g.svg->onPointer(#pointerdown, ev =>
      if ev->button == 0 && drive() {
        ev->preventDefault
        dragging := true
        model->ParamModel.beginGesture(pregain)
        let start = model->ParamModel.get(pregain)
        let k = g.h / (g.svg->getBoundingClientRect).height
        let travel = ref(0.)
        let last = ref(ev->clientY)
        g.svg->Controls.capturePointer(
          ev,
          ~onMove=mv => {
            let dy = (mv->clientY - last.contents) * k
            last := mv->clientY
            travel := travel.contents + (mv->shiftKey ? dy * 0.1 : dy)
            model->ParamModel.set(pregain, start - travel.contents * 0.25)
            ctx.status->Status.show((model->ParamModel.def(pregain)).longText(model->ParamModel.get(pregain)))
          },
          ~onUp=() => {
            model->ParamModel.endGesture(pregain)
            dragging := false
            request()
          },
        )
      }
    )
    g.svg->onMouse(#mousemove, _ => g.svg->setStyle("cursor", drive() ? "ns-resize" : "crosshair"))
    g.svg->onMouse(#mouseenter, _ => ctx.status->Status.show(drive() ? hint : shapeHint))
    g.svg->onMouse(#mouseleave, _ => if !dragging.contents {
        ctx.status->Status.clear
      })
    (panel, g)
  }

  //==============================================================================
  // the curve: input across, output up; or the custom shape to edit

  let m = 12.
  let shapeLayer = ref(None)
  let (curvePanel, cg) = graph(~title="curve", ~x=0., ~drive=() => !isCustom(), (g, grid, layer) => {
    let (cx, cy) = (g.w / 2., g.h / 2.)
    let (rx, ry) = (g.w / 2. - m, g.h / 2. - m)
    let range = isCustom() ? 1. : scale.contents
    let xOf = x => cx + x * rx
    let yOf = y => cy - FxDsp.clamp(y / range, -1.05, 1.05) * ry
    FxGraph.line(grid, ~cls="axis", m, cy, g.w - m, cy)
    FxGraph.line(grid, ~cls="axis", cx, m, cx, g.h - m)
    [-1., 1.]->Array.forEach(v => {
      FxGraph.line(grid, ~cls="axis faint", xOf(v), m, xOf(v), g.h - m)
      FxGraph.line(grid, ~cls="axis faint", m, yOf(v), g.w - m, yOf(v))
    })
    FxGraph.text(grid, ~anchor="end", xOf(1.) - 4., cy - 4., isCustom() ? "in" : "0 dBFS in")
    FxGraph.text(grid, cx + 4., yOf(range) + 10., isCustom() ? "out" : `${f(range)} out`)
    // a straight line for comparison
    FxGraph.path(layer, ~cls="curve faint")->FxGraph.setPath(`M${f(xOf(-1.))} ${f(yOf(-1.))}L${f(xOf(1.))} ${f(yOf(1.))}`)
    let curve = x => isCustom() ? FxDsp.customShape(points(), x) : distort(x)
    let at = t => {
      let x = t * 2. - 1.
      (xOf(x), yOf(curve(x)))
    }
    let path = [at(0.)]
    path->Plots.trace(at, ~steps=200)
    FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(path))
    shapeLayer.contents->Option.forEach(fn => fn(xOf, yOf))
  })

  // the custom shape's points, and a bend point in the middle of every segment
  let shapeHandles = FxGraph.group(cg.svg)
  let shapeHits = FxGraph.group(cg.svg)
  let readout = Plots.svgEl(shapeHits, "text", [("class", Str("readout"))])
  let focus = ref(None)
  let geometry = ref((x => x, y => y))
  let xAt = px => {
    let (cx, rx) = (cg.w / 2., cg.w / 2. - m)
    (px - cx) / rx
  }
  let yAt = py => {
    let (cy, ry) = (cg.h / 2., cg.h / 2. - m)
    (cy - py) / ry
  }
  let pointHandles = Array.fromInitializer(~length=maxPoints, k => {
    let origin = ref((0., 0.))
    let self = ref(None)
    let h = FxGraph.handle(
      cg,
      ~layer=shapeHandles,
      ~hits=shapeHits,
      ~ids=[xId(k), yId(k)],
      ~start=() => {
        dragging := true
        origin := self.contents->Option.mapOr((0., 0.), (h: FxGraph.handle) => (h.x, h.y))
      },
      ~drag=((dx, dy)) => {
        let (x0, y0) = origin.contents
        let n = count()
        // the ends stay at the ends; the others between their neighbours
        if k > 0 && k < n - 1 {
          let lo = model->ParamModel.get(xId(k - 1)) + 0.005
          let hi = model->ParamModel.get(xId(k + 1)) - 0.005
          model->ParamModel.set(xId(k), FxDsp.clamp(xAt(x0 + dx), lo, hi))
        }
        model->ParamModel.set(yId(k), FxDsp.clamp(yAt(y0 + dy), -1., 1.))
      },
      ~finish=() => {
        dragging := false
        request()
      },
      // right-click takes a point out (not the ends)
      ~rightClick=() => {
        let n = count()
        if k > 0 && k < n - 1 {
          setPoints(points()->Array.filterWithIndex((_, i) => i != k))
        }
      },
      ~hover=on => {
        focus := (on ? Some(`p${Int.toString(k)}`) : None)
        request()
      },
    )
    self := Some(h)
    h
  })
  let bendHandles = Array.fromInitializer(~length=maxPoints, k => {
    let start = ref(0.)
    let h = FxGraph.handle(
      cg,
      ~layer=shapeHandles,
      ~hits=shapeHits,
      ~cls="node bend",
      ~r=4.,
      ~cursor="ns-resize",
      ~ids=[bendId(k)],
      ~start=() => {
        dragging := true
        start := model->ParamModel.get(bendId(k))
      },
      ~drag=((_, dy)) => {
        // up bends towards the later point's level: bend the way the segment rises
        let (_, y0, _) = points()[k - 1]->Option.getOr((0., 0., 0.))
        let (_, y1, _) = points()[k]->Option.getOr((0., 0., 0.))
        let sign = y1 >= y0 ? 1. : -1.
        model->ParamModel.set(bendId(k), FxDsp.clamp(start.contents + dy / 80. * sign, -1., 1.))
      },
      ~finish=() => {
        dragging := false
        request()
      },
      ~hover=on => {
        focus := (on ? Some(`b${Int.toString(k)}`) : None)
        request()
      },
    )
    h
  })

  shapeLayer :=
    Some(
      (xOf, yOf) => {
        geometry := (xOf, yOf)
        let on = isCustom()
        let list = points()
        let n = Array.length(list)
        pointHandles->Array.forEachWithIndex((h, k) => {
          h->FxGraph.show(on && k < n)
          switch list[k] {
          | Some((x, y, _)) =>
            h->FxGraph.place(xOf(x), yOf(y))
            h->FxGraph.setClass(focus.contents == Some(`p${Int.toString(k)}`) ? "node hot" : "node")
          | None => ()
          }
        })
        bendHandles->Array.forEachWithIndex((h, k) => {
          h->FxGraph.show(on && k > 0 && k < n)
          switch (list[k - 1], list[k]) {
          | (Some((x0, _, _)), Some((x1, _, _))) =>
            let x = (x0 + x1) / 2.
            h->FxGraph.place(xOf(x), yOf(FxDsp.customShape(list, x)))
            h->FxGraph.setClass(focus.contents == Some(`b${Int.toString(k)}`) ? "node bend hot" : "node bend")
          | _ => ()
          }
        })
        switch focus.contents {
        | Some(key) if on =>
          let k = key->String.slice(~start=1)->Int.fromString->Option.getOr(0)
          let isBend = String.startsWith(key, "b")
          let h = isBend ? bendHandles->Array.getUnsafe(k) : pointHandles->Array.getUnsafe(k)
          let text = switch list[k] {
          | Some((x, y, bend)) =>
            isBend ? `bend ${Float.toFixed(bend * 100., ~digits=0)} %` : `in ${f(x)}  ·  out ${f(y)}`
          | None => ""
          }
          cg->FxGraph.readout(readout, ~x=h.x, ~y=h.y, text)
        | _ => readout->setTextContent("")
        }
      },
    )

  // a click between points adds one there, on the curve, and drags it
  cg.svg->onPointer(#pointerdown, ev =>
    if ev->button == 0 && isCustom() && count() < maxPoints {
      ev->preventDefault
      let r = cg.svg->getBoundingClientRect
      let k = cg.w / r.width
      let x = xAt((ev->clientX - r.left) * k)
      let list = points()
      if x > -0.99 && x < 0.99 {
        let i = list->Array.findIndex(((px, _, _)) => px > x)
        if i > 0 {
          let (_, y, _) = (x, FxDsp.customShape(list, x), 0.)
          let next = list->Array.copy
          next->Array.splice(~start=i, ~remove=0, ~insert=[(x, y, 0.)])
          setPoints(next)
        }
      }
    }
  )
  cg.svg->suppressContextMenu

  let resetShape = Controls.button(
    ctx,
    curvePanel.el,
    "straight",
    ~x=half - 80.,
    ~y=2.,
    ~w=70.,
    ~status="Start the custom shape again from a straight line",
    () => setPoints([(-1., -1., 0.), (1., 1., 0.)]),
  )
  resetShape->setStyle("height", "18px")
  resetShape->setStyle("line-height", "16px")

  //==============================================================================
  // a sine through it

  graph(~title="waveform", ~x=half + gap, ~drive=() => true, (g, grid, layer) => {
    let cy = g.h / 2.
    let ry = g.h / 2. - m
    let xOf = t => m + t * (g.w - 2. * m)
    let yOf = y => cy - FxDsp.clamp(y / scale.contents, -1.05, 1.05) * ry
    FxGraph.line(grid, ~cls="axis", m, cy, g.w - m, cy)
    [-1., 1.]->Array.forEach(v => FxGraph.line(grid, ~cls="axis faint", m, yOf(v), g.w - m, yOf(v)))
    let sine = t => Math.sin(2. * Math.Constants.pi * t)
    let input = [(xOf(0.), yOf(0.))]
    input->Plots.trace(t => (xOf(t), yOf(sine(t))), ~steps=64)
    FxGraph.path(layer, ~cls="curve faint")->FxGraph.setPath(Plots.pathFrom(input))
    let output = [(xOf(0.), yOf(distort(0.)))]
    output->Plots.trace(t => (xOf(t), yOf(distort(sine(t)))), ~steps=200)
    FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(output))
    FxGraph.text(grid, m + 4., m + 10., "a full-scale sine in (dashed) and out: drag up or down for the drive")
  })->ignore

  let ids = [
    "Sat_Type",
    "Sat_Mode",
    "Sat_Oversample",
    "Sat_Pregain",
    "Sat_Limit",
    "Sat_Postgain",
    ...PorridgeParams.shaperParams->Array.map(((i, _)) => i),
  ]
  ids->Array.forEach(i => model->ParamModel.listen(id(i), request))
  let showReset = () => resetShape->setStyle("display", isCustom() ? "" : "none")
  model->ParamModel.listen(id("Sat_Type"), showReset)
  showReset()

  let settings = Panel.make(body, ~x=0., ~y=h + gap, ~w, ~h=settingsHeight)
  let s = Grid.make(ctx, settings.el, ~y=Grid.padBottom, ~cw=Grid.fitColumns(w, 8))
  s->Grid.choice(id("Sat_Type"), 0, 0, "type", ~span=2)
  if placement {
    s->Grid.choice("Sat_Mode", 2, 0, "where", ~span=2)
  } else {
    s->Grid.note("on the whole sound, where it is in the rack", 2, 0, ~span=2)->ignore
  }
  s->Grid.choice(id("Sat_Oversample"), 4, 0, "oversample")
  s->Grid.param(id("Sat_Pregain"), 5, 0, "pregain")
  s->Grid.param(id("Sat_Limit"), 6, 0, "limit")
  s->Grid.param(id("Sat_Postgain"), 7, 0, "postgain")
  ignore(geometry)

  () => redraws->Array.forEach(r => r.now())
}
