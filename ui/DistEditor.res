// The distortion tab: the curve from input to output, and a full-scale sine before and after,
// with the drive, limit, output gain, the mix and the oversampling filters' gain in them. Drag
// the sine up or down for the drive.
//
// The model types (DistTypes) keep state, so they have no fixed curve: their graphs are a
// 110 Hz sine run through the model (AirwindowsSim) until it has settled, its last cycle drawn
// as output against input (a loop where the model's filters shift the output) and over time.
// Their drive, tone and character knobs take the names of the controls they are for the type,
// and are dimmed where it has none.
//
// With the custom shape (like Fruity WaveShaper) the curve is the shape itself, to edit: drag
// a point, click between them to add one, right-click one to take it out, and drag the small
// point in the middle of a segment up or down to bend it. The drive moves the sound across it.
//
// Oatmeal's distortion also says where it sits (per-voice, or on the whole sound before the
// rack); the others run in the rack or the voice lane. Per-voice, the lo-fi sampler can hold its
// samples on multiples of the note (Sat_Track), so that its aliases fall on the note's harmonics:
// that switch shows only there.

open! Web

let hint = "Drag up or down on the sine for more or less drive (pregain), shift for fine steps."
let shapeHint = "The custom shape: drag a point, click between points to add one, right-click a point to take it out, drag a segment's middle point up or down to bend it. Shift for fine steps."

let custom = 5.
let maxPoints = PorridgeParams.shaperPoints

// the sine a model's graphs run
let modelHz = 110.
let modelRate = 48000.

// `id` maps Oatmeal's distortion's parameters to this one's; `placement` shows where Oatmeal's
// sits; perVoice says whether it runs in the voices.
let make = (ctx: Ctx.t, body, ~id: string => string, ~placement, ~perVoice: unit => bool, ~w, ~h) => {
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let gap = Grid.gap
  let settingsHeight = Grid.bareHeight(1)
  let graphHeight = h - settingsHeight - gap
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

  let kind = () => Float.toInt(get("Sat_Type"))
  let isModel = () => DistTypes.isModel(kind())
  let distort = x =>
    FxDsp.distort(
      ~kind=kind(),
      ~oversample=Float.toInt(get("Sat_Oversample")),
      ~pregain=get("Sat_Pregain"),
      ~limit=get("Sat_Limit"),
      ~postgain=get("Sat_Postgain"),
      ~mix=get("Sat_Mix"),
      ~custom=points(),
      x,
    )

  // a model's last cycle of the sine (inputs, outputs), kept until its settings change
  let cycleCache = ref(None)
  let modelCycle = () => {
    let key = [
      get("Sat_Type"),
      get("Sat_Oversample"),
      get("Sat_Pregain"),
      get("Sat_Limit"),
      get("Sat_Postgain"),
      get("Sat_Drive"),
      get("Sat_Tone"),
      get("Sat_Character"),
      get("Sat_Mix"),
    ]
    switch cycleCache.contents {
    | Some((k, v)) if k == key => v
    | _ =>
      let oversample = Float.toInt(get("Sat_Oversample"))
      let os = FxDsp.oversampleGain(oversample)
      // (the model runs at the oversampled rate, up to 4x here)
      let sr = modelRate * Int.toFloat(Math.Int.min(4, Math.Int.max(1, [1, 2, 4, 8][oversample]->Option.getOr(1))))
      let pre = Math.pow(10., ~exp=(get("Sat_Pregain") - get("Sat_Limit")) / 20.)
      let post = Math.pow(10., ~exp=(get("Sat_Limit") + get("Sat_Postgain")) / 20.)
      let mix = get("Sat_Mix")
      let run = AirwindowsSim.model(kind(), ~drive=get("Sat_Drive"), ~tone=get("Sat_Tone"), ~character=get("Sat_Character"), ~sr)
      let v = AirwindowsSim.sineCycle(
        x => mix * os * run(x * pre * os) * post + (1. - mix) * x,
        ~hz=modelHz,
        ~sr,
        ~amp=1.,
        ~settle=0.1,
        ~steps=240,
      )
      cycleCache := Some((key, v))
      v
    }
  }

  let scale = ref(1.)
  let fit = () => {
    let peak = isModel()
      ? modelCycle()->Pair.second->Array.reduce(0., (m, y) => Math.max(m, Math.abs(y)))
      : Array.fromInitializer(~length=201, k => Math.abs(distort(Int.toFloat(k) / 100. - 1.)))->Math.maxMany
    scale := Math.max(1., Math.ceil(peak * 1.1 * 4.) / 4.)
  }

  let pregain = id("Sat_Pregain")
  // the two graphs and their redraws
  let graphs: array<(FxGraph.t, FxGraph.redraw)> = []
  let dragging = () => graphs->Array.some(((g, _)) => g.dragging)
  let request = () => graphs->Array.forEach(((_, r)) => r.request())

  let graph = (~title, ~x, ~drive: unit => bool, draw) => {
    let panel = Panel.make(body, ~title, ~x, ~y=0., ~w=half, ~h=graphHeight)
    let g = FxGraph.inPanel(ctx, panel)
    let grid = FxGraph.group(g.under)
    let layer = FxGraph.group(g.under)
    let redraw = FxGraph.redraw(g, () => {
      if !dragging() {
        fit()
      }
      grid->setTextContent("")
      layer->setTextContent("")
      g.svg->toggleClass("off", get("Sat_Type") == 0.)
      draw(g, grid, layer)
    })
    graphs->Array.push((g, redraw))
    // drag up for more drive
    g.svg->onPointer(#pointerdown, ev =>
      if ev->button == 0 && drive() {
        ev->preventDefault
        g.dragging = true
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
            ctx.status->Status.show(model->ParamModel.longText(pregain))
          },
          ~onUp=() => {
            model->ParamModel.endGesture(pregain)
            g.dragging = false
            request()
          },
        )
      }
    )
    g.svg->onMouse(#mousemove, _ => g.svg->setStyle("cursor", drive() ? "ns-resize" : "crosshair"))
    g.svg->onMouse(#mouseenter, _ => ctx.status->Status.show(drive() ? hint : shapeHint))
    g.svg->onMouse(#mouseleave, _ => if !dragging() {
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
    if isModel() {
      // the model's cycle, output against input
      let (inputs, outputs) = modelCycle()
      let path = inputs->Array.mapWithIndex((x, k) => (xOf(x), yOf(outputs->Array.getUnsafe(k))))
      FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(path))
      DistTypes.info(kind()).source->Option.forEach(source =>
        FxGraph.text(grid, ~anchor="end", g.w - m - 2., g.h - m - 4., `Airwindows ${source}`)
      )
    } else {
      let curve = x => isCustom() ? FxDsp.customShape(points(), x) : distort(x)
      let at = t => {
        let x = t * 2. - 1.
        (xOf(x), yOf(curve(x)))
      }
      let path = [at(0.)]
      path->Plots.trace(at, ~steps=200)
      FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(path))
    }
    shapeLayer.contents->Option.forEach(fn => fn(xOf, yOf))
  })

  // the custom shape's points, and a bend point in the middle of every segment
  let xAt = px => {
    let (cx, rx) = (cg.w / 2., cg.w / 2. - m)
    (px - cx) / rx
  }
  let yAt = py => {
    let (cy, ry) = (cg.h / 2., cg.h / 2. - m)
    (cy - py) / ry
  }
  let pointHandles = Array.fromInitializer(~length=maxPoints, k =>
    FxGraph.handle(
      cg,
      ~ids=[xId(k), yId(k)],
      ~key=`p${Int.toString(k)}`,
      ~statusOnDrag=false,
      ~drag=({x, y}) => {
        let n = count()
        // the ends stay at the ends; the others between their neighbours
        if k > 0 && k < n - 1 {
          let lo = model->ParamModel.get(xId(k - 1)) + 0.005
          let hi = model->ParamModel.get(xId(k + 1)) - 0.005
          model->ParamModel.set(xId(k), FxDsp.clamp(xAt(x), lo, hi))
        }
        model->ParamModel.set(yId(k), FxDsp.clamp(yAt(y), -1., 1.))
      },
      ~finish=request,
      // right-click takes a point out (not the ends)
      ~rightClick=() => {
        let n = count()
        if k > 0 && k < n - 1 {
          setPoints(points()->Array.filterWithIndex((_, i) => i != k))
        }
      },
      ~hover=_ => (),
    )
  )
  let bendHandles = Array.fromInitializer(~length=maxPoints, k => {
    let start = ref(0.)
    FxGraph.handle(
      cg,
      ~cls="node bend",
      ~r=4.,
      ~cursor="ns-resize",
      ~ids=[bendId(k)],
      ~key=`b${Int.toString(k)}`,
      ~statusOnDrag=false,
      ~start=() => start := model->ParamModel.get(bendId(k)),
      ~drag=({dy}) => {
        // up bends towards the later point's level: bend the way the segment rises
        let (_, y0, _) = points()[k - 1]->Option.getOr((0., 0., 0.))
        let (_, y1, _) = points()[k]->Option.getOr((0., 0., 0.))
        let sign = y1 >= y0 ? 1. : -1.
        model->ParamModel.set(bendId(k), FxDsp.clamp(start.contents + dy / 80. * sign, -1., 1.))
      },
      ~finish=request,
      ~hover=_ => (),
    )
  })
  cg.redraw = request

  shapeLayer :=
    Some(
      (xOf, yOf) => {
        let on = isCustom()
        let list = points()
        let n = Array.length(list)
        pointHandles->Array.forEachWithIndex((h, k) => {
          h->FxGraph.show(on && k < n)
          switch list[k] {
          | Some((x, y, _)) =>
            h->FxGraph.place(xOf(x), yOf(y))
          | None => ()
          }
        })
        bendHandles->Array.forEachWithIndex((h, k) => {
          h->FxGraph.show(on && k > 0 && k < n)
          switch (list[k - 1], list[k]) {
          | (Some((x0, _, _)), Some((x1, _, _))) =>
            let x = (x0 + x1) / 2.
            h->FxGraph.place(xOf(x), yOf(FxDsp.customShape(list, x)))
          | _ => ()
          }
        })
        switch cg.focus {
        | Some(key) if on =>
          let k = key->String.slice(~start=1)->Int.fromString->Option.getOr(0)
          let isBend = String.startsWith(key, "b")
          let h = isBend ? bendHandles->Array.getUnsafe(k) : pointHandles->Array.getUnsafe(k)
          let text = switch list[k] {
          | Some((x, y, bend)) =>
            isBend ? `bend ${Float.toFixed(bend * 100., ~digits=0)} %` : `in ${f(x)}  ·  out ${f(y)}`
          | None => ""
          }
          cg->FxGraph.readout(~x=h.x, ~y=h.y, text)
        | _ => cg->FxGraph.hideReadout
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
          let y = FxDsp.customShape(list, x)
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
    if isModel() {
      let (_, outputs) = modelCycle()
      let n = Int.toFloat(Array.length(outputs) - 1)
      let output = outputs->Array.mapWithIndex((y, k) => (xOf(Int.toFloat(k) / n), yOf(y)))
      FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(output))
      FxGraph.text(grid, m + 4., m + 10., DistTypes.describe(kind()))
      FxGraph.text(grid, m + 4., g.h - m - 4., `a full-scale ${Float.toString(modelHz)} Hz sine in (dashed) and out, once the model has settled`)
    } else {
      let output = [(xOf(0.), yOf(distort(0.)))]
      output->Plots.trace(t => (xOf(t), yOf(distort(sine(t)))), ~steps=200)
      FxGraph.path(layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(output))
      FxGraph.text(grid, m + 4., m + 10., kind() == 0 ? "a full-scale sine in (dashed) and out: drag up or down for the drive" : DistTypes.describe(kind()))
    }
  })->ignore

  let ids = [
    "Sat_Type",
    "Sat_Mode",
    "Sat_Oversample",
    "Sat_Pregain",
    "Sat_Limit",
    "Sat_Postgain",
    ...PorridgeParams.distModelParams->Array.map(((i, _)) => i),
    ...PorridgeParams.shaperParams->Array.map(((i, _)) => i),
  ]
  model->ParamModel.listenEach(ids->Array.map(id), request)
  let showReset = () => resetShape->setStyle("display", isCustom() ? "" : "none")
  model->ParamModel.listen(id("Sat_Type"), showReset)
  showReset()

  // (the copies have no "where", and on the whole sound no "on note")
  let first = placement ? 4 : 2
  let tracks = placement || perVoice()
  let settings = Panel.make(body, ~x=0., ~y=graphHeight + gap, ~w, ~h=settingsHeight)
  let s = Grid.make(ctx, settings.el, ~y=Grid.padBottom, ~cw=Grid.fitColumns(w, first + (tracks ? 9 : 8)))
  s->Grid.choice(id("Sat_Type"), 0, 0, "type", ~span=2)
  if placement {
    s->Grid.choice("Sat_Mode", 2, 0, "where", ~span=2)
  }
  s->Grid.choice(id("Sat_Oversample"), first, 0, "oversample")
  s->Grid.param(id("Sat_Pregain"), first + 1, 0, "pregain")
  s->Grid.param(id("Sat_Limit"), first + 2, 0, "limit")
  s->Grid.param(id("Sat_Postgain"), first + 3, 0, "postgain")
  // the model's knobs, named for the type (dimmed where it has no such control), and the mix
  let modelKnob = (knob: DistTypes.knob, c, name) => {
    let e = s->Grid.at(c, 0, id(name), b =>
      Controls.paramControl(ctx, settings.el, id(name), ~x=b.x, ~y=b.y, ~w=b.w, ~label=(knob :> string))
    )
    (knob, e)
  }
  let knobs = [
    modelKnob(#drive, first + 4, "Sat_Drive"),
    modelKnob(#tone, first + 5, "Sat_Tone"),
    modelKnob(#character, first + 6, "Sat_Character"),
  ]
  s->Grid.param(id("Sat_Mix"), first + 7, 0, "mix")
  // the lo-fi sampler's rates on multiples of each voice's note (per-voice only: Oatmeal's shows
  // it while it runs in the voices)
  if tracks {
    let onNote = s->Grid.at(first + 8, 0, id("Sat_Track"), b => {
      let holder = el("div", ~parent=settings.el)
      Controls.toggle(ctx, holder, id("Sat_Track"), ~x=b.x, ~y=b.y, ~w=b.w, ~label="on note")
      holder
    })
    let showOnNote = () => onNote->setStyle("display", perVoice() ? "" : "none")
    model->ParamModel.listen("Sat_Mode", showOnNote)
    showOnNote()
  }
  let nameKnobs = () =>
    knobs->Array.forEach(((knob, e)) => {
      let label = DistTypes.knobLabel(kind(), knob)
      e->toggleClass("dim", label == None)
      e->querySelector(".l")->Option.forEach(l => l->setTextContent(label->Option.getOr((knob :> string))))
    })
  model->ParamModel.listen(id("Sat_Type"), nameKnobs)
  nameKnobs()

  () => graphs->Array.forEach(((_, r)) => r.now())
}
