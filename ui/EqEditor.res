// EQ editor: the five bands' combined response, with a point per band to drag
// (frequency sideways, gain up and down). Scroll over a point for its slope, right-click
// for its type. A "values" switch swaps the graph for the raw parameter fields.
//
// The response is computed from the same RBJ biquads the patch uses, at 48 kHz.

open! Web

let sampleRate = 48000.
let (fMin, fMax) = (15., 20000.)
let margin = 8.
let fine = 0.1

let hint = "Drag a band's point to set its frequency and gain, shift for fine steps. Scroll over it for the slope, right-click for its type. Grey points are bands that are off: drag one to use it."

let clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x))

// where bands that are off wait to be picked up, spread out so that each can be grabbed
let restingFreqs = [80., 300., 1000., 3500., 10000.]

let ids = b => {
  let n = Int.toString(b + 1)
  (`EQ_${n}_Type`, `EQ_${n}_Freq`, `EQ_${n}_Amp`, `EQ_${n}_Slope`)
}

type biquad = {b0: float, b1: float, b2: float, a0: float, a1: float, a2: float}

// The patch's band filter (peak/notch, low shelf, high shelf).
let coefficients = (kind, freq, amp, slope) => {
  let a = Math.pow(10., ~exp=amp * 0.025)
  let w = Math.min(Math.Constants.pi * freq * 2. / sampleRate, Math.Constants.pi * 0.98)
  let (sn, cs) = (Math.sin(w), Math.cos(w))
  let alpha = sn / (2. * slope)
  let beta = Math.sqrt(a) / slope * sn
  switch kind {
  | 1 => {
      b0: 1. + alpha * a,
      b1: -2. * cs,
      b2: 1. - alpha * a,
      a0: 1. + alpha / a,
      a1: -2. * cs,
      a2: 1. - alpha / a,
    }
  | 2 => {
      b0: a * (a + 1. - (a - 1.) * cs + beta),
      b1: 2. * a * (a - 1. - (a + 1.) * cs),
      b2: a * (a + 1. - (a - 1.) * cs - beta),
      a0: a + 1. + (a - 1.) * cs + beta,
      a1: -2. * (a - 1. + (a + 1.) * cs),
      a2: a + 1. + (a - 1.) * cs - beta,
    }
  | _ => {
      b0: a * (a + 1. + (a - 1.) * cs + beta),
      b1: -2. * a * (a - 1. + (a + 1.) * cs),
      b2: a * (a + 1. + (a - 1.) * cs - beta),
      a0: a + 1. - (a - 1.) * cs + beta,
      a1: 2. * (a - 1. - (a + 1.) * cs),
      a2: a + 1. - (a - 1.) * cs - beta,
    }
  }
}

let gainDb = (q, freq) => {
  let w = 2. * Math.Constants.pi * freq / sampleRate
  let (c1, c2) = (Math.cos(w), Math.cos(2. * w))
  let power = (x0: float, x1: float, x2: float) =>
    x0 * x0 + x1 * x1 + x2 * x2 + 2. * (x0 * x1 + x1 * x2) * c1 + 2. * x0 * x2 * c2
  10. * Math.log10(Math.max(1e-12, power(q.b0, q.b1, q.b2)) / Math.max(1e-12, power(q.a0, q.a1, q.a2)))
}

let make = (ctx: Ctx.t, parent, box: box) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let root = el("div", ~cls="ed", ~parent)->placeBox(box)
  let area = {x: 0., y: 0., w: box.w, h: box.h}
  let s = Plots.svg(root, area)
  Plots.background(s, area)
  let svgEl = (tag, attrs) => Plots.svgEl(s, tag, attrs)

  let (left, right) = (margin, box.w - margin)
  let mid = box.h / 2.
  let xOf = f => left + Math.log(f / fMin) / Math.log(fMax / fMin) * (right - left)
  let freqAt = x => fMin * Math.pow(fMax / fMin, ~exp=clamp((x - left) / (right - left), 0., 1.))
  // dB at the top edge, held for the length of a drag
  let limit = ref(24.)
  let yOf = db => mid - clamp(db / limit.contents, -1., 1.) * (mid - margin)
  let dbAt = y => clamp((mid - y) / (mid - margin), -1., 1.) * limit.contents

  // frequency and gain grid
  let gridLayer = svgEl("g", [])
  let gridLine = (x1, y1, x2, y2) =>
    Plots.svgEl(
      gridLayer,
      "line",
      [("class", Str("axis")), ("x1", Num(x1)), ("y1", Num(y1)), ("x2", Num(x2)), ("y2", Num(y2))],
    )->ignore
  let gridLabel = (x, y, text) =>
    Plots.svgEl(gridLayer, "text", [("class", Str("tick")), ("x", Num(x)), ("y", Num(y))])
    ->setTextContent(text)
  [20., 50., 100., 200., 500., 1000., 2000., 5000., 10000.]->Array.forEach(f => {
    let x = xOf(f)
    gridLine(x, 1., x, box.h - 1.)
    gridLabel(x + 3., box.h - 4., f >= 1000. ? Float.toString(f / 1000.) ++ "k" : Float.toString(f))
  })
  let gainLayer = svgEl("g", [])

  let bandCurve = svgEl("path", [("class", Str("curve faint"))])
  let fill = svgEl("path", [("class", Str("fill"))])
  let curve = svgEl("path", [("class", Str("curve"))])
  let layer = svgEl("g", [])
  let readout = svgEl("text", [("class", Str("readout"))])

  let vals = el("div", ~cls="vals", ~parent=root)
  let g = Grid.make(ctx, vals, ~x=0., ~y=22., ~cw=box.w / 5.)
  for b in 0 to 4 {
    let (kind, freq, amp, slope) = ids(b)
    g->Grid.choice(kind, b, 0, "band " ++ Int.toString(b + 1))
    g->Grid.param(freq, b, 1, "freq")
    g->Grid.param(amp, b, 2, "gain")
    g->Grid.param(slope, b, 3, "slope")
  }
  Controls.expandSwitch(ctx, root)

  let hover = ref(None)
  let dragging = ref(None)

  let bandOn = b => {
    let (kind, _, _, _) = ids(b)
    get(kind) != 0.
  }
  let bandFilter = b => {
    let (kind, freq, amp, slope) = ids(b)
    coefficients(Float.toInt(get(kind)), get(freq), get(amp), get(slope))
  }

  let fit = () => {
    let biggest = Array.fromInitializer(~length=5, b => {
      let (_, _, amp, _) = ids(b)
      bandOn(b) ? Math.abs(get(amp)) : 0.
    })->Math.maxMany
    limit := Math.min(60., Math.max(24., 12. * Math.ceil((biggest + 3.) / 12.)))
    gainLayer->setTextContent("")
    [-1., -0.5, 0.5, 1.]->Array.forEach(k => {
      let db = k * limit.contents
      let y = yOf(db)
      Plots.svgEl(
        gainLayer,
        "line",
        [("class", Str("axis faint")), ("x1", Num(1.)), ("x2", Num(box.w - 1.)), ("y1", Num(y)), ("y2", Num(y))],
      )->ignore
      Plots.svgEl(
        gainLayer,
        "text",
        [("class", Str("tick")), ("x", Num(4.)), ("y", Num(k > 0. ? y + 11. : y - 3.))],
      )->setTextContent((db > 0. ? "+" : "") ++ Float.toString(db) ++ " dB")
    })
    let y0 = yOf(0.)
    Plots.svgEl(
      gainLayer,
      "line",
      [("class", Str("axis")), ("x1", Num(1.)), ("x2", Num(box.w - 1.)), ("y1", Num(y0)), ("y2", Num(y0))],
    )->ignore
  }

  let response = filters => {
    let at = t => {
      let x = left + (right - left) * t
      (x, yOf(filters->Array.reduce(0., (a, q) => a + gainDb(q, freqAt(x)))))
    }
    let points = [at(0.)]
    points->Plots.trace(at, ~steps=160)
    points
  }

  let statusFor = b => {
    let (kind, freq, amp, slope) = ids(b)
    let text = id => (model->ParamModel.def(id)).longText(get(id))
    bandOn(b) ? [kind, freq, amp, slope]->Array.map(text)->Array.join("    ") : text(kind)
  }

  let readoutFor = b => {
    let (kind, freq, amp, slope) = ids(b)
    let short = id => (model->ParamModel.def(id)).shortText(get(id))
    let names = Controls.namesOf(model->ParamModel.def(kind))
    bandOn(b)
      ? `${Int.toString(b + 1)} ${names[Float.toInt(get(kind))]->Option.getOr("")}  ·  ${short(
            freq,
          )}  ·  ${short(amp)}  ·  slope ${short(slope)}`
      : `band ${Int.toString(b + 1)} is off: drag to use it`
  }

  let nodes = Array.fromInitializer(~length=5, b => {
    let dot = svgEl("circle", [("r", Num(7.))])
    let label = svgEl("text", [("class", Str("nodelabel"))])
    label->setTextContent(Int.toString(b + 1))
    let hit = svgEl("circle", [("class", Str("hit")), ("r", Num(11.)), ("style", Str("cursor:move"))])
    (dot, label, hit)
  })
  // hit areas above every dot and label
  nodes->Array.forEach(((dot, label, _)) => {
    layer->appendChild(dot)
    layer->appendChild(label)
  })
  nodes->Array.forEach(((_, _, hit)) => layer->appendChild(hit))
  layer->appendChild(readout)

  let position = b => {
    let (_, freq, amp, _) = ids(b)
    bandOn(b) ? (xOf(get(freq)), yOf(get(amp))) : (xOf(restingFreqs->Array.getUnsafe(b)), mid)
  }

  let draw = () => {
    let on = Array.fromInitializer(~length=5, i => i)->Array.filter(bandOn)
    let total = response(on->Array.map(bandFilter))
    let d = Plots.pathFrom(total)
    curve->setAttribute("d", Str(d))
    let y0 = Float.toString(yOf(0.))
    fill->setAttribute(
      "d",
      Str(`${d}L${Float.toString(right)} ${y0}L${Float.toString(left)} ${y0}Z`),
    )
    let focus = dragging.contents->Option.orElse(hover.contents)
    bandCurve->setAttribute(
      "d",
      Str(
        switch focus {
        | Some(b) if bandOn(b) && Array.length(on) > 1 => Plots.pathFrom(response([bandFilter(b)]))
        | _ => ""
        },
      ),
    )

    nodes->Array.forEachWithIndex(((dot, label, hit), b) => {
      let (x, y) = position(b)
      [dot, hit]->Array.forEach(e => {
        e->setAttribute("cx", Num(x))
        e->setAttribute("cy", Num(y))
      })
      label->setAttribute("x", Num(x))
      label->setAttribute("y", Num(y + 3.5))
      let hot = focus == Some(b)
      dot->setAttribute(
        "class",
        Str("band" ++ (bandOn(b) ? "" : " off") ++ (hot ? " hot" : "")),
      )
      label->setAttribute("class", Str("nodelabel" ++ (bandOn(b) ? "" : " off") ++ (hot ? " hot" : "")))
    })

    switch focus {
    | Some(b) =>
      ctx.status->Status.show(statusFor(b))
      let (x, y) = position(b)
      let leftHalf = x < box.w * 0.6
      readout->setTextContent(readoutFor(b))
      readout->setAttribute("x", Num(leftHalf ? x + 13. : x - 13.))
      readout->setAttribute("y", Num(y < 30. ? y + 22. : y - 12.))
      readout->setAttribute("text-anchor", Str(leftHalf ? "start" : "end"))
    | None => readout->setTextContent("")
    }
  }

  let refresh = () => {
    if dragging.contents == None {
      fit()
    }
    draw()
  }

  // an off band comes on as a flat peak where it was resting
  let wake = b => {
    let (_, freq, amp, _) = ids(b)
    if !bandOn(b) {
      model->ParamModel.gestureSet(freq, restingFreqs->Array.getUnsafe(b))
      model->ParamModel.gestureSet(amp, 0.)
    }
  }

  let typeMenu = (b, ev) => {
    let (kind, _, _, _) = ids(b)
    let (x, y) = position(b)
    let anchor = el("div", ~parent=root)->place(x, y + 8., ~w=1., ~h=1.)
    anchor->setStyle("position", "absolute")
    ctx.menu->Menu.show(
      anchor,
      Controls.namesOf(model->ParamModel.def(kind))->Array.mapWithIndex((label, value) => {
        Menu.label,
        value,
      }),
      Float.toInt(get(kind)),
      v => {
        if v != 0 {
          wake(b)
        }
        model->ParamModel.gestureSet(kind, Int.toFloat(v))
      },
    )
    anchor->remove
    ev->preventDefault
  }

  let startDrag = (b, hit, ev) => {
    let (kind, freq, amp, _) = ids(b)
    if !bandOn(b) {
      wake(b)
      model->ParamModel.gestureSet(kind, 1.)
    }
    dragging := Some(b)
    [freq, amp]->Array.forEach(id => model->ParamModel.beginGesture(id))
    let k = box.w / (s->getBoundingClientRect).width
    let (x0, y0) = position(b)
    let x = ref(x0)
    let y = ref(y0)
    let last = ref((ev->clientX, ev->clientY))
    hit->Controls.capturePointer(
      ev,
      ~onMove=mv => {
        let (lastX, lastY) = last.contents
        last := (mv->clientX, mv->clientY)
        let f = mv->shiftKey ? fine * k : k
        x := clamp(x.contents + (mv->clientX - lastX) * f, left, right)
        y := clamp(y.contents + (mv->clientY - lastY) * f, margin, box.h - margin)
        model->ParamModel.set(freq, freqAt(x.contents))
        model->ParamModel.set(amp, dbAt(y.contents))
      },
      ~onUp=() => {
        [freq, amp]->Array.forEach(id => model->ParamModel.endGesture(id))
        dragging := None
        fit()
        draw()
        if hover.contents == None {
          ctx.status->Status.show(hint)
        }
      },
    )
    draw()
  }

  nodes->Array.forEachWithIndex(((_, _, hit), b) => {
    hit->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 0 => startDrag(b, hit, ev)
      | 2 => typeMenu(b, ev)
      | _ => ()
      }
    })
    hit->onMouse(#mouseenter, _ => {
      hover := Some(b)
      draw()
    })
    hit->onMouse(#mouseleave, _ => {
      hover := None
      draw()
      if dragging.contents == None {
        ctx.status->Status.show(hint)
      }
    })
    hit->onWheel(ev => {
      ev->preventDefault
      let (_, _, _, slope) = ids(b)
      let def = model->ParamModel.def(slope)
      let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
      let d = ev->shiftKey ? d * fine : d
      model->ParamModel.gestureSet(slope, def.fromNorm(clamp(def.toNorm(get(slope)) + d, 0., 1.)))
    })
  })

  s->suppressContextMenu
  s->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  s->onMouse(#mouseleave, _ =>
    if dragging.contents == None {
      ctx.status->Status.clear
    }
  )

  for b in 0 to 4 {
    let (kind, freq, amp, slope) = ids(b)
    [kind, freq, amp, slope]->Array.forEach(id => model->ParamModel.listen(id, refresh))
  }
  refresh()
}
