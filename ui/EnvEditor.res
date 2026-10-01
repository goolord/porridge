// Envelope editors, FL Studio style: drag the points to shape the envelope, and the small
// points in the middle of the attack, decay and release up or down to bend them. A "values"
// switch in the corner swaps the graph for the raw parameter fields.
//
// Time runs left to right on a compressed (square-root) axis. Each segment is measured
// from the point before it, so dragging a point changes only its own segment. The axis is
// refitted when a drag ends, never during one, so the point stays under the pointer.

open! Web

let margin = 7. // keeps points at the edges grabbable
let segmentGap = 12. // minimum segment width, so that points never sit on top of each other

let hintFor = name =>
  name ++ ": drag the points to shape it, and the small middle points up or down to bend a stage; shift for fine steps. Scroll over a point to change it, right-click to reset it."

// compressed seconds
let units = ms => Math.sqrt(Math.max(0., ms) / 1000.)
let msOf = u => 1000. * u * u

// A round axis length (in compressed seconds) that leaves room to drag into.
let niceSpan = total =>
  [1.5, 2., 3., 4., 6., 8., 12., 16., 24., 32.]
  ->Array.find(s => s >= total * 1.15)
  ->Option.getOr(32.)

// A draggable point. Dragging it sideways sets `time` from the width of its segment (which
// starts at x0); dragging it up and down sets `level`, or for a bend point, `curve`.
type handle = {
  time: option<string>,
  level: option<string>,
  x0: float,
  x: float,
  y: float,
  // drawn hollow when the stage it ends is skipped
  hollow: bool,
  // a stage's curve (PorridgeParams.curveSpecs), and which way up bends it positive
  curve: option<string>,
  bendSign: float,
}

let point = (~time=?, ~level=?, ~hollow=false, x0, x, y) => {
  time,
  level,
  x0,
  x,
  y,
  hollow,
  curve: None,
  bendSign: 0.,
}

// A stage's bend point, at the middle of its segment.
let bendPoint = (curve, (x, y), ~rising) => {
  ...point(x, x, y),
  curve: Some(curve),
  bendSign: rising ? 1. : -1.,
}

// Scales held for the length of a drag.
type frame = {
  // pixels per compressed second
  unitPx: float,
  // pitch envelope: semitones at the top edge
  limit: float,
}

type shape = {
  ids: array<string>,
  fit: unit => frame,
  // the curve and the points for the current values
  layout: frame => (array<(float, float)>, array<handle>),
  // sets a handle's time from its segment width in pixels
  setTime: (handle, float, frame) => unit,
  // sets a handle's level from a y position
  setLevel: (handle, float, frame) => unit,
  // a zero line
  zero: option<frame => float>,
  dimmed: unit => bool,
}

let handleIds = h => [h.time, h.level, h.curve]->Array.filterMap(id => id)

//==============================================================================
// Shapes

// The DSP's smoothing between the exponential stage level and the output.
let envCubic = (l: float, lo: float, hi: float) =>
  Math.abs(hi - lo) < 1e-6
    ? l
    : (-2. * l * l * l +
      3. * (lo + hi) * l * l -
      6. * lo * hi * l +
      (lo + hi) * lo * hi) / ((hi - lo) * (hi - lo))

// The DSP's stage curves: the distance left to a stage's end level, raised to 8^curve.
let bend = (level: float, from: float, to: float, curve: float) =>
  curve == 0. || from == to
    ? level
    : to +
      (from - to) *
        Math.pow(
          Float.clamp((level - to) / (from - to), ~min=0., ~max=1.),
          ~exp=Math.pow(8., ~exp=curve),
        )

// The envelope a parameter prefix belongs to, as PorridgeParams names it.
let envName = prefix =>
  switch prefix {
  | "" => "Amp"
  | "F_" => "Filter"
  | "M1_" => "Mod1"
  | _ => "Mod2"
  }

let curveIds = prefix =>
  ["Attack", "Decay", "Release"]->Array.map(stage => PorridgeParams.curveId(envName(prefix), stage))

// Attack, hold, decay 1 to the breakpoint, decay 2 to sustain, release. The amp envelope
// is drawn in dB like its readouts; the others are linear, like their percentages.
let adsr = (ctx: Ctx.t, prefix, ~w, ~h): shape => {
  let model = ctx.model
  let id = k => prefix ++ k
  let get = k => model->ParamModel.get(id(k))
  let (attackCurve, decayCurve, releaseCurve) = switch curveIds(prefix) {
  | [a, d, r] => (a, d, r)
  | _ => ("", "", "")
  }
  let curve = c => model->ParamModel.get(c)
  let levelDef = model->ParamModel.def(id("Sustain"))
  let decibels = prefix == ""
  let (top, bottom) = (margin, h - margin)
  let yOf = v => {
    let f = decibels ? levelDef.toNorm(v) : v
    bottom - Float.clamp(f, ~min=0., ~max=1.) * (bottom - top)
  }
  let fractionAt = y => Float.clamp((bottom - y) / (bottom - top), ~min=0., ~max=1.)
  let levelAt = y => decibels ? levelDef.fromNorm(fractionAt(y)) : fractionAt(y)
  let sustainPx = 0.13 * (w - 2. * margin)
  // the DSP treats a breakpoint above 0.998 as "skip decay 1"
  let skipped = () => get("Breakpoint") > 0.998

  let fit = () => {
    let stages = skipped()
      ? ["Attack", "Hold", "Decay2", "Release"]
      : ["Attack", "Hold", "Decay1", "Decay2", "Release"]
    let total = stages->Array.reduce(0., (a, k) => a + units(get(k)))
    {unitPx: (w - 2. * margin - 5. * segmentGap - sustainPx) / niceSpan(total), limit: 1.}
  }

  let layout = f => {
    let after = (x0, k) => x0 + segmentGap + units(get(k)) * f.unitPx
    let skip = skipped()
    let bp = skip ? 1. : Math.max(get("Breakpoint"), 1e-4)
    let sus = get("Sustain")
    let x0 = margin
    let xa = after(x0, "Attack")
    let xh = after(xa, "Hold")
    let xb = skip ? xh + segmentGap : after(xh, "Decay1")
    let xs = after(xb, "Decay2")
    let xr0 = xs + sustainPx
    let xr = after(xr0, "Release")

    let points = [(x0, yOf(0.))]
    // each sampled segment, and its middle point
    let sample = (xFrom: float, xTo: float, level) => {
      for k in 1 to 24 {
        let t = Int.toFloat(k) / 24.
        points->Array.push((xFrom + (xTo - xFrom) * t, yOf(level(t))))
      }
      ((xFrom + xTo) / 2., yOf(level(0.5)))
    }
    let (ca, cd, cr) = (curve(attackCurve), curve(decayCurve), curve(releaseCurve))
    let attackMid = sample(x0, xa, t => {
      let a = bend(t, 0., 1., ca)
      (2. - a) * a
    })
    points->Array.push((xh, yOf(1.)))
    let decay1Mid = skip ? None : Some(sample(xh, xb, t => bend(envCubic(Math.pow(bp, ~exp=t), bp, 1.), 1., bp, cd)))
    let lo = Math.max(sus, 1e-4)
    let decay2Mid = sample(xb, xs, t => bend(envCubic(bp * Math.pow(lo / bp, ~exp=t), lo, bp), bp, lo, cd))
    points->Array.push((xr0, yOf(sus)))
    let releaseMid = sample(xr0, xr, t =>
      sus <= 0.001 ? 0. : bend((sus * Math.pow(10., ~exp=-3. * t) - 0.001) * sus / (sus - 0.001), sus, 0., cr)
    )
    // the decay curve bends both decays; its point sits on whichever one has a drop
    let (decayMid, decayRising) = switch decay1Mid {
    | Some(mid) if Math.abs(bp - sus) < 0.02 => (mid, false)
    | _ => (decay2Mid, sus > bp)
    }

    let top = yOf(1.)
    let handles = [
      point(~time=id("Attack"), x0, xa, top),
      point(~time=id("Hold"), xa, xh, top),
      point(~time=id("Decay1"), ~level=id("Breakpoint"), ~hollow=skip, xh, xb, yOf(bp)),
      point(~time=id("Decay2"), ~level=id("Sustain"), xb, xs, yOf(sus)),
      point(~time=id("Release"), xr0, xr, yOf(0.)),
      bendPoint(attackCurve, attackMid, ~rising=true),
      bendPoint(decayCurve, decayMid, ~rising=decayRising),
      bendPoint(releaseCurve, releaseMid, ~rising=false),
    ]
    (points, handles)
  }

  let setTime = (h, width, f) =>
    h.time->Option.forEach(t =>
      // a skipped decay 1 keeps its time until the breakpoint is pulled down
      if !(t == id("Decay1") && skipped()) {
        model->ParamModel.set(t, msOf(Math.max(0., width) / f.unitPx))
      }
    )

  let setLevel = (h, y, _) =>
    h.level->Option.forEach(l =>
      // the top edge is "skip decay 1" for the breakpoint
      model->ParamModel.set(l, l == id("Breakpoint") && fractionAt(y) > 0.985 ? 1. : levelAt(y))
    )

  {
    ids: [
      ...["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release"]->Array.map(id),
      ...curveIds(prefix),
    ],
    fit,
    layout,
    setTime,
    setLevel,
    zero: None,
    dimmed: () => false,
  }
}

// Pitch envelope in semitones: start, attack to the peak, decay to sustain, and the release
// glide at its st/sec rate (one second of it is shown). The attack is linear in frequency
// ratio, so it bends when drawn in semitones.
let pitch = (ctx: Ctx.t, ~w, ~h): shape => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  // peak, sustain and release scale with the octave size
  let octave = () => Math.log2(Math.max(1e-6, get("Tune_Octave")))
  let floor = -48.
  let semitones = r => r > 0. ? Math.max(floor, 12. * Math.log2(r)) : floor
  let startRatio = () => {
    let start = get("PEnv_Start")
    start <= floor ? 0. : Math.pow(2., ~exp=start / 12.)
  }
  let peakRatio = () => Math.pow(2., ~exp=get("PEnv_Peak") * octave() / 12.)
  // the attack runs at double speed going down
  let attackFactor = () => peakRatio() <= startRatio() ? 0.5 : 1.
  let holdPx = 0.12 * (w - 2. * margin)
  let releasePx = 0.16 * (w - 2. * margin)
  let mid = h / 2.
  let yOf = (st, f) => mid - Float.clamp(st / f.limit, ~min=-1., ~max=1.) * (mid - margin)
  let semitonesAt = (y, f) => Float.clamp((mid - y) / (mid - margin), ~min=-1., ~max=1.) * f.limit

  let fit = () => {
    let o = octave()
    let sustain = get("PEnv_Sustain") * o
    let biggest = Math.maxMany(
      [
        semitones(startRatio()),
        get("PEnv_Peak") * o,
        sustain,
        sustain + get("PEnv_Release") * o,
      ]->Array.map(Math.abs),
    )
    let total = units(get("PEnv_Attack") * attackFactor()) + units(get("PEnv_Decay"))
    {
      unitPx: (w - 2. * margin - 2. * segmentGap - holdPx - releasePx) / niceSpan(total),
      // a step above the biggest value, so that a drag to the edge can go further next time
      limit: Math.min(48., 12. * (Math.floor(biggest / 12.) + 1.)),
    }
  }

  let layout = f => {
    let o = octave()
    let (r0, r1) = (startRatio(), peakRatio())
    let peak = get("PEnv_Peak") * o
    let sustain = get("PEnv_Sustain") * o
    let release = get("PEnv_Release") * o
    let x0 = margin
    let xp = x0 + segmentGap + units(get("PEnv_Attack") * attackFactor()) * f.unitPx
    let xs = xp + segmentGap + units(get("PEnv_Decay")) * f.unitPx
    let xr = xs + holdPx + releasePx

    let points = Array.fromInitializer(~length=25, k => {
      let t = Int.toFloat(k) / 24.
      (x0 + (xp - x0) * t, yOf(semitones(r0 + (r1 - r0) * t), f))
    })
    points->Array.push((xs, yOf(sustain, f)))
    points->Array.push((xs + holdPx, yOf(sustain, f)))
    points->Array.push((xr, yOf(sustain + release, f)))

    let handles = [
      point(~level="PEnv_Start", x0, x0, yOf(semitones(r0), f)),
      point(~time="PEnv_Attack", ~level="PEnv_Peak", x0, xp, yOf(peak, f)),
      point(~time="PEnv_Decay", ~level="PEnv_Sustain", xp, xs, yOf(sustain, f)),
      point(~level="PEnv_Release", xs, xr, yOf(sustain + release, f)),
    ]
    (points, handles)
  }

  let setTime = (h, width, f) =>
    h.time->Option.forEach(t => {
      let ms = msOf(Math.max(0., width) / f.unitPx)
      model->ParamModel.set(t, t == "PEnv_Attack" ? ms / attackFactor() : ms)
    })

  let setLevel = (h, y, f) =>
    h.level->Option.forEach(l => {
      let st = semitonesAt(y, f)
      let o = octave()
      model->ParamModel.set(
        l,
        switch l {
        | "PEnv_Start" => st
        | "PEnv_Release" => st / o - get("PEnv_Sustain")
        | _ => st / o
        },
      )
    })

  {
    ids: [
      "PEnv_On",
      "PEnv_Start",
      "PEnv_Attack",
      "PEnv_Peak",
      "PEnv_Decay",
      "PEnv_Sustain",
      "PEnv_Release",
      "Tune_Octave",
    ],
    fit,
    layout,
    setTime,
    setLevel,
    zero: Some(f => yOf(0., f)),
    dimmed: () => get("PEnv_On") == 0.,
  }
}

//==============================================================================
// The editor

// fields: the raw parameters shown by the "values" switch, four to a row
let make = (ctx: Ctx.t, parent, box: box, shape: shape, ~fields: array<(string, string)>, ~name) => {
  let model = ctx.model
  let ed = NodeEditor.make(ctx, parent, box, ~hint=hintFor(name), ~columns=4)
  let svgEl = svgEl(ed.svg, ...)
  let zero = ed.svg->Plots.line(2., 0., box.w - 2., 0.)
  let fill = svgEl("path", [("class", Str("fill"))])
  let curve = svgEl("path", [("class", Str("curve"))])
  let layer = svgEl("g", [])
  let readout = svgEl("text", [("class", Str("readout"))])
  fields->Array.forEachWithIndex(((id, label), i) => ed.values->Grid.param(id, mod(i, 4), i / 4, label))

  let frame = ref(shape.fit())
  let handles = ref([])
  let nodes = ref([])

  let statusFor = h => h->handleIds->Array.map(id => model->ParamModel.longText(id))->Array.join("    ")
  let readoutFor = h => h->handleIds->Array.map(id => model->ParamModel.shortText(id))->Array.join("  ·  ")

  let draw = () => {
    let (points, hs) = shape.layout(frame.contents)
    handles := hs
    let d = Plots.pathFrom(points)
    curve->setAttribute("d", Str(d))
    switch (points[0], points[Array.length(points) - 1], shape.zero) {
    | (Some((xa, _)), Some((xb, _)), None) =>
      let base = Float.toString(box.h - margin)
      fill->setAttribute(
        "d",
        Str(`${d}L${Float.toString(xb)} ${base}L${Float.toString(xa)} ${base}Z`),
      )
    | _ => fill->setAttribute("d", Str(""))
    }
    switch shape.zero {
    | Some(y) =>
      let y = y(frame.contents)
      zero->setAttribute("y1", Num(y))
      zero->setAttribute("y2", Num(y))
    | None => zero->setAttribute("opacity", Num(0.))
    }
    ed.svg->toggleClass("off", shape.dimmed())

    nodes.contents->Array.forEachWithIndex(((dot, hit), i) =>
      hs[i]->Option.forEach(h => {
        [dot, hit]->Array.forEach(e => {
          e->setAttribute("cx", Num(h.x))
          e->setAttribute("cy", Num(h.y))
        })
        let hot = ed.hover == Some(i) || ed.dragging == Some(i)
        let isBend = h.curve != None
        dot->setAttribute(
          "class",
          Str("node" ++ (h.hollow ? " hollow" : "") ++ (isBend ? " bend" : "") ++ (hot ? " hot" : "")),
        )
        dot->setAttribute("r", Num(isBend ? (hot ? 4.5 : 3.) : hot ? 5.5 : 4.))
      })
    )

    switch NodeEditor.focus(ed)->Option.flatMap(i => hs[i]) {
    | Some(h) =>
      ctx.status->Status.show(statusFor(h))
      if ed.dragging != None {
        ed->NodeEditor.showReadout(
          readout,
          readoutFor(h),
          (h.x, h.y),
          ~dx=10.,
          ~above=9.,
          ~below=18.,
          ~nearTop=24.,
        )
      }
    | None => ()
    }
    if ed.dragging == None {
      readout->setTextContent("")
    }
  }

  // the axis is refitted when a drag ends, never during one
  let refresh = () => {
    if ed.dragging == None {
      frame := shape.fit()
    }
    draw()
  }

  let startDrag = (i, hit, ev) =>
    handles.contents[i]->Option.forEach(h => {
      let x = ref(h.x)
      let y = ref(h.y)
      let curve0 = h.curve->Option.map(c => model->ParamModel.get(c))->Option.getOr(0.)
      ed->NodeEditor.drag(i, hit, ev, ~ids=handleIds(h), ~onMove=(dx, dy) => {
        x := Float.clamp(x.contents + dx, ~min=h.x0 + segmentGap, ~max=box.w * 4.)
        y := Float.clamp(y.contents + dy, ~min=margin, ~max=box.h - margin)
        // the level first: it decides whether decay 1 is skipped
        shape.setLevel(h, y.contents, frame.contents)
        shape.setTime(h, x.contents - h.x0 - segmentGap, frame.contents)
        // a bend point: up or down bends its stage, a full bend per 60 pixels
        h.curve->Option.forEach(c =>
          model->ParamModel.set(
            c,
            Float.clamp(curve0 + h.bendSign * (h.y - y.contents) / 60., ~min=-1., ~max=1.),
          )
        )
      })
    })

  let makeNode = i => {
    let dot = svgEl("circle", [("class", Str("node")), ("r", Num(4.))])
    let hit = svgEl("circle", [("class", Str("hit")), ("r", Num(8.))])
    hit->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 0 => startDrag(i, hit, ev)
      | 2 =>
        handles.contents[i]->Option.forEach(h =>
          h
          ->handleIds
          ->Array.forEach(id => model->ParamModel.gestureSet(id, (model->ParamModel.def(id)).init))
        )
      | _ => ()
      }
    })
    ed->NodeEditor.hookNode(hit, i)
    hit->onWheel(ev => {
      ev->preventDefault
      handles.contents[i]->Option.forEach(h =>
        h.time
        ->Option.orElse(h.level)
        ->Option.orElse(h.curve)
        ->Option.forEach(id => Controls.wheelParam(model, id, ev))
      )
    })
    (dot, hit)
  }

  let (_, initial) = shape.layout(frame.contents)
  nodes := initial->Array.mapWithIndex((h, i) => {
    let (dot, hit) = makeNode(i)
    let cursor = switch (h.time, h.level) {
    | (Some(_), Some(_)) => "move"
    | (Some(_), None) => "ew-resize"
    | _ => "ns-resize"
    }
    let isBend = h.curve != None
    hit->setAttribute("r", Num(isBend ? 6. : 8.))
    hit->setAttribute("style", Str("cursor:" ++ cursor))
    (dot, hit)
  })
  // every hit area above every dot, so a dot never hides a neighbour's hit area
  nodes.contents->Array.forEach(((dot, _)) => layer->appendChild(dot))
  nodes.contents->Array.forEach(((_, hit)) => layer->appendChild(hit))
  layer->appendChild(readout)

  ed->NodeEditor.start(shape.ids, refresh)
}
