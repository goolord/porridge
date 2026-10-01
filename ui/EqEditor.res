// EQ editor: the five bands' combined response, with a point per band to drag
// (frequency sideways, gain up and down). Scroll over a point for its slope, right-click
// for its type. A "values" switch swaps the graph for the raw parameter fields.
//
// The response is computed from the same RBJ biquads the patch uses, at 48 kHz.

open! Web

let sampleRate = 48000.
let (fMin, fMax) = (15., 20000.)
let margin = 8.

let hint = "Drag a band's point to set its frequency and gain, shift for fine steps. Scroll over it for the slope, right-click for its type. Grey points are bands that are off: drag one to use it."

// where bands that are off wait to be picked up, spread out so that each can be grabbed
let restingFreqs = [80., 300., 1000., 3500., 10000.]

// band b's parameters; `id` maps the first EQ's to another's
let ids = (id, b) => {
  let n = Int.toString(b + 1)
  (id(`EQ_${n}_Type`), id(`EQ_${n}_Freq`), id(`EQ_${n}_Amp`), id(`EQ_${n}_Slope`))
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

let make = (ctx: Ctx.t, parent, box: box, ~id=x => x) => {
  let ids = ids(id, ...)
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let ed = NodeEditor.make(ctx, parent, box, ~hint, ~columns=5)
  let svgEl = svgEl(ed.svg, ...)

  let (left, right) = (margin, box.w - margin)
  let mid = box.h / 2.
  let xOf = f => left + Math.log(f / fMin) / Math.log(fMax / fMin) * (right - left)
  let freqAt = x =>
    fMin * Math.pow(fMax / fMin, ~exp=Float.clamp((x - left) / (right - left), ~min=0., ~max=1.))
  // dB at the top edge, held for the length of a drag
  let limit = ref(24.)
  let yOf = db => mid - Float.clamp(db / limit.contents, ~min=-1., ~max=1.) * (mid - margin)
  let dbAt = y => Float.clamp((mid - y) / (mid - margin), ~min=-1., ~max=1.) * limit.contents

  // frequency and gain grid
  let gridLayer = svgEl("g", [])
  let gridLabel = (layer, x, y, text) =>
    layer->Web.svgEl("text", [("class", Str("tick")), ("x", Num(x)), ("y", Num(y))])->setTextContent(text)
  [20., 50., 100., 200., 500., 1000., 2000., 5000., 10000.]->Array.forEach(f => {
    let x = xOf(f)
    gridLayer->Plots.line(x, 1., x, box.h - 1.)->ignore
    gridLayer->gridLabel(
      x + 3.,
      box.h - 4.,
      f >= 1000. ? Float.toString(f / 1000.) ++ "k" : Float.toString(f),
    )
  })
  let gainLayer = svgEl("g", [])
  // the limit the gain grid is drawn for
  let gainLimit = ref(0.)

  let bandCurve = svgEl("path", [("class", Str("curve faint"))])
  let fill = svgEl("path", [("class", Str("fill"))])
  let curve = svgEl("path", [("class", Str("curve"))])
  let layer = svgEl("g", [])
  let readout = svgEl("text", [("class", Str("readout"))])

  for b in 0 to 4 {
    let (kind, freq, amp, slope) = ids(b)
    ed.values->Grid.choice(kind, b, 0, "band " ++ Int.toString(b + 1))
    ed.values->Grid.param(freq, b, 1, "freq")
    ed.values->Grid.param(amp, b, 2, "gain")
    ed.values->Grid.param(slope, b, 3, "slope")
  }

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
    limit := Float.clamp(12. * Math.ceil((biggest + 3.) / 12.), ~min=24., ~max=60.)
    if limit.contents != gainLimit.contents {
      gainLimit := limit.contents
      gainLayer->setTextContent("")
      [-1., -0.5, 0.5, 1.]->Array.forEach(k => {
        let db = k * limit.contents
        let y = yOf(db)
        gainLayer->Plots.line(~cls="axis faint", 1., y, box.w - 1., y)->ignore
        gainLayer->gridLabel(
          4.,
          k > 0. ? y + 11. : y - 3.,
          (db > 0. ? "+" : "") ++ Float.toString(db) ++ " dB",
        )
      })
      let y0 = yOf(0.)
      gainLayer->Plots.line(1., y0, box.w - 1., y0)->ignore
    }
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
    let text = id => model->ParamModel.longText(id)
    bandOn(b) ? [kind, freq, amp, slope]->Array.map(text)->Array.join("    ") : text(kind)
  }

  let readoutFor = b => {
    let (kind, freq, amp, slope) = ids(b)
    let short = id => model->ParamModel.shortText(id)
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
    let focus = NodeEditor.focus(ed)
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
      ed->NodeEditor.showReadout(
        readout,
        readoutFor(b),
        position(b),
        ~dx=13.,
        ~above=12.,
        ~below=22.,
        ~nearTop=30.,
      )
    | None => readout->setTextContent("")
    }
  }

  // the gain axis is refitted when a drag ends, never during one
  let refresh = () => {
    if ed.dragging == None {
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

  let typeMenu = b => {
    let (kind, _, _, _) = ids(b)
    let (x, y) = position(b)
    ctx.menu->Menu.showAt(
      ed.root,
      ~x,
      ~y=y + 8.,
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
  }

  let startDrag = (b, hit, ev) => {
    let (kind, freq, amp, _) = ids(b)
    if !bandOn(b) {
      wake(b)
      model->ParamModel.gestureSet(kind, 1.)
    }
    let (x0, y0) = position(b)
    let x = ref(x0)
    let y = ref(y0)
    ed->NodeEditor.drag(b, hit, ev, ~ids=[freq, amp], ~onMove=(dx, dy) => {
      x := Float.clamp(x.contents + dx, ~min=left, ~max=right)
      y := Float.clamp(y.contents + dy, ~min=margin, ~max=box.h - margin)
      model->ParamModel.set(freq, freqAt(x.contents))
      model->ParamModel.set(amp, dbAt(y.contents))
    })
  }

  nodes->Array.forEachWithIndex(((_, _, hit), b) => {
    hit->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 0 => startDrag(b, hit, ev)
      | 2 => typeMenu(b)
      | _ => ()
      }
    })
    ed->NodeEditor.hookNode(hit, b)
    hit->onWheel(ev => {
      let (_, _, _, slope) = ids(b)
      Controls.wheelParam(model, slope, ev)
    })
  })

  ed->NodeEditor.start(
    Array.fromInitializer(~length=5, b => {
      let (kind, freq, amp, slope) = ids(b)
      [kind, freq, amp, slope]
    })->Array.flat,
    refresh,
  )
}
