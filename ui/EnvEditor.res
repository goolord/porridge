// Envelope editors, FL Studio style: drag the points to shape the envelope, and the small
// points in the middle of the attack, decay and release up or down to bend them. A "values"
// switch in the corner swaps the graph for the raw parameter fields.
//
// Time runs left to right on a compressed (square-root) axis. Each segment is measured
// from the point before it, so dragging a point changes only its own segment. The axis is
// refitted when a drag ends, never during one, so the point stays under the pointer.

open! Web

let margin = 7. // keeps points at the edges grabbable
let axisHeight = 12. // the time axis labels, under the curve
let bottomOf = h => h - margin - axisHeight
let segmentGap = 12. // minimum segment width, so that points never sit on top of each other
let fine = 0.1 // shift-drag factor

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

let clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x))

// time axis ticks, 1 ms to 500 s: the roundest first, so they win the room
let tickTimes = [1., 5., 2.]->Array.flatMap(m =>
  [1., 10., 100., 1000., 10000., 100000.]->Array.map(d => m * d)
)
let tickText = ms => ms < 1000. ? `${Float.toString(ms)} ms` : `${Float.toString(ms / 1000.)} s`

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

// A stretch of the time axis: xFrom to xTo covers msFrom to msTo, timed from the note-on,
// or for a release, from the note-off. Time is linear within a stretch, as the curve is.
type stretch = {
  xFrom: float,
  xTo: float,
  msFrom: float,
  msTo: float,
  release: bool,
}

let stretch = (~release=false, xFrom, xTo, msFrom, msTo) => {xFrom, xTo, msFrom, msTo, release}

type shape = {
  ids: array<string>,
  fit: unit => frame,
  // the curve, the points and the time axis for the current values
  layout: frame => (array<(float, float)>, array<handle>, array<stretch>),
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
    : to + (from - to) * Math.pow(clamp((level - to) / (from - to), 0., 1.), ~exp=Math.pow(8., ~exp=curve))

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
  let (top, bottom) = (margin, bottomOf(h))
  let yOf = v => {
    let f = decibels ? levelDef.toNorm(v) : v
    bottom - clamp(f, 0., 1.) * (bottom - top)
  }
  let fractionAt = y => clamp((bottom - y) / (bottom - top), 0., 1.)
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
      points->Plots.trace(t => (xFrom + (xTo - xFrom) * t, yOf(level(t))))
      ((xFrom + xTo) / 2., yOf(level(0.5)))
    }
    let (ca, cd, cr) = (curve(attackCurve), curve(decayCurve), curve(releaseCurve))
    let attackMid = sample(x0, xa, t => {
      let a = bend(t, 0., 1., ca)
      (2. - a) * a
    })
    points->Array.push((xh, yOf(1.)))
    let decay1Mid = if skip {
      // decay 2 starts from the top, at the hollow breakpoint
      points->Array.push((xb, yOf(1.)))
      None
    } else {
      Some(sample(xh, xb, t => bend(envCubic(Math.pow(bp, ~exp=t), bp, 1.), 1., bp, cd)))
    }
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

    let ta = get("Attack")
    let th = ta + get("Hold")
    let tb = th + (skip ? 0. : get("Decay1"))
    let times = [
      stretch(x0, xa, 0., ta),
      stretch(xa, xh, ta, th),
      stretch(xh, xb, th, tb),
      stretch(xb, xs, tb, tb + get("Decay2")),
      stretch(~release=true, xr0, xr, 0., get("Release")),
    ]

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
    (points, handles, times)
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
  let mid = (margin + bottomOf(h)) / 2.
  let yOf = (st, f) => mid - clamp(st / f.limit, -1., 1.) * (mid - margin)
  let semitonesAt = (y, f) => clamp((mid - y) / (mid - margin), -1., 1.) * f.limit

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

    let attack = t => (x0 + (xp - x0) * t, yOf(semitones(r0 + (r1 - r0) * t), f))
    let points = [attack(0.)]
    points->Plots.trace(attack)
    points->Array.push((xs, yOf(sustain, f)))
    points->Array.push((xs + holdPx, yOf(sustain, f)))
    points->Array.push((xr, yOf(sustain + release, f)))

    let tp = get("PEnv_Attack") * attackFactor()
    let times = [
      stretch(x0, xp, 0., tp),
      stretch(xp, xs, tp, tp + get("PEnv_Decay")),
      stretch(~release=true, xs + holdPx, xr, 0., 1000.),
    ]

    let handles = [
      point(~level="PEnv_Start", x0, x0, yOf(semitones(r0), f)),
      point(~time="PEnv_Attack", ~level="PEnv_Peak", x0, xp, yOf(peak, f)),
      point(~time="PEnv_Decay", ~level="PEnv_Sustain", xp, xs, yOf(sustain, f)),
      point(~level="PEnv_Release", xs, xr, yOf(sustain + release, f)),
    ]
    (points, handles, times)
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
  let hint = hintFor(name)
  let root = el("div", ~cls="ed", ~parent)->placeBox(box)
  let area = {x: 0., y: 0., w: box.w, h: box.h}
  let s = Plots.svg(root, area)
  Plots.background(s, area)
  let svgEl = Plots.svgEl(s, ...)
  let zero = svgEl("line", [("class", Str("axis")), ("x1", Num(2.)), ("x2", Num(box.w - 2.))])
  let fill = svgEl("path", [("class", Str("fill"))])
  let ticks = svgEl("g", [])
  let curve = svgEl("path", [("class", Str("curve"))])
  let layer = svgEl("g", [])
  let readout = svgEl("text", [("class", Str("readout"))])

  let vals = el("div", ~cls="vals", ~parent=root)
  let g = Grid.make(ctx, vals, ~x=0., ~y=22., ~cw=box.w / 4.)
  fields->Array.forEachWithIndex(((id, label), i) => g->Grid.param(id, mod(i, 4), i / 4, label))

  Controls.expandSwitch(ctx, root)

  let frame = ref(shape.fit())
  let handles = ref([])
  let nodes = ref([])
  let hover = ref(None)
  let dragging = ref(None)

  let statusFor = h =>
    h
    ->handleIds
    ->Array.map(id => (model->ParamModel.def(id)).longText(model->ParamModel.get(id)))
    ->Array.join("    ")

  let readoutFor = h =>
    h
    ->handleIds
    ->Array.map(id => (model->ParamModel.def(id)).shortText(model->ParamModel.get(id)))
    ->Array.join("  ·  ")

  // a faint line and a label at each tick time that has room, the release's counted from
  // the note-off
  let drawTicks = (times: array<stretch>) => {
    ticks->setTextContent("")
    // the room each tick takes, line and label; the note-on and note-off keep a little
    let taken = times->Array.filterMap(t => t.msFrom == 0. ? Some((t.xFrom - 6., t.xFrom + 16.)) : None)
    tickTimes->Array.forEach(ms =>
      times->Array.forEach(t =>
        if ms > t.msFrom && ms <= t.msTo {
          let x = t.xFrom + (t.xTo - t.xFrom) * (ms - t.msFrom) / (t.msTo - t.msFrom)
          let text = (t.release ? "+" : "") ++ tickText(ms)
          let width = 5. * Int.toFloat(String.length(text))
          // near the right edge, the label sits left of its line
          let flip = x + 3. + width > box.w - 4.
          let (left, right) = flip ? (x - 3. - width, x) : (x, x + 3. + width)
          if left > 2. && taken->Array.every(((l, r)) => right + 8. < l || left - 8. > r) {
            taken->Array.push((left, right))
            Plots.svgEl(
              ticks,
              "line",
              [("class", Str("axis faint")), ("x1", Num(x)), ("x2", Num(x)), ("y1", Num(1.)), ("y2", Num(box.h - 1.))],
            )->ignore
            Plots.svgEl(
              ticks,
              "text",
              [
                ("class", Str("tick")),
                ("x", Num(flip ? x - 3. : x + 3.)),
                ("y", Num(box.h - 4.)),
                ("text-anchor", Str(flip ? "end" : "start")),
              ],
            )->setTextContent(text)
          }
        }
      )
    )
  }

  let draw = () => {
    let (points, hs, times) = shape.layout(frame.contents)
    handles := hs
    drawTicks(times)
    let d = Plots.pathFrom(points)
    curve->setAttribute("d", Str(d))
    switch (points[0], points[Array.length(points) - 1], shape.zero) {
    | (Some((xa, _)), Some((xb, _)), None) =>
      let base = Float.toString(bottomOf(box.h))
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
    s->toggleClass("off", shape.dimmed())

    nodes.contents->Array.forEachWithIndex(((dot, hit), i) =>
      hs[i]->Option.forEach(h => {
        [dot, hit]->Array.forEach(e => {
          e->setAttribute("cx", Num(h.x))
          e->setAttribute("cy", Num(h.y))
        })
        let hot = hover.contents == Some(i) || dragging.contents == Some(i)
        let isBend = h.curve != None
        dot->setAttribute(
          "class",
          Str("node" ++ (h.hollow ? " hollow" : "") ++ (isBend ? " bend" : "") ++ (hot ? " hot" : "")),
        )
        dot->setAttribute("r", Num(isBend ? (hot ? 4.5 : 3.) : hot ? 5.5 : 4.))
      })
    )

    switch dragging.contents->Option.orElse(hover.contents)->Option.flatMap(i => hs[i]) {
    | Some(h) =>
      ctx.status->Status.show(statusFor(h))
      if dragging.contents != None {
        let leftHalf = h.x < box.w * 0.6
        readout->setTextContent(readoutFor(h))
        readout->setAttribute("x", Num(leftHalf ? h.x + 10. : h.x - 10.))
        readout->setAttribute("y", Num(h.y < 24. ? h.y + 18. : h.y - 9.))
        readout->setAttribute("text-anchor", Str(leftHalf ? "start" : "end"))
      }
    | None => ()
    }
    if dragging.contents == None {
      readout->setTextContent("")
    }
  }

  let refresh = () => {
    if dragging.contents == None {
      frame := shape.fit()
    }
    draw()
  }

  let startDrag = (i, hit, ev) => {
    handles.contents[i]->Option.forEach(h => {
      dragging := Some(i)
      let ids = handleIds(h)
      ids->Array.forEach(id => model->ParamModel.beginGesture(id))
      // svg pixels per screen pixel
      let k = box.w / (s->getBoundingClientRect).width
      let x = ref(h.x)
      let y = ref(h.y)
      let curve0 = h.curve->Option.map(c => model->ParamModel.get(c))->Option.getOr(0.)
      let last = ref((ev->clientX, ev->clientY))
      hit->Controls.capturePointer(
        ev,
        ~onMove=mv => {
          let (lastX, lastY) = last.contents
          last := (mv->clientX, mv->clientY)
          let f = mv->shiftKey ? fine * k : k
          x := clamp(x.contents + (mv->clientX - lastX) * f, h.x0 + segmentGap, box.w * 4.)
          y := clamp(y.contents + (mv->clientY - lastY) * f, margin, bottomOf(box.h))
          // the level first: it decides whether decay 1 is skipped
          shape.setLevel(h, y.contents, frame.contents)
          shape.setTime(h, x.contents - h.x0 - segmentGap, frame.contents)
          // a bend point: up or down bends its stage, a full bend per 60 pixels
          h.curve->Option.forEach(c =>
            model->ParamModel.set(c, clamp(curve0 + h.bendSign * (h.y - y.contents) / 60., -1., 1.))
          )
          draw()
        },
        ~onUp=() => {
          ids->Array.forEach(id => model->ParamModel.endGesture(id))
          dragging := None
          frame := shape.fit()
          draw()
          if hover.contents == None {
            ctx.status->Status.show(hint)
          }
        },
      )
      draw()
    })
  }

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
    hit->onMouse(#mouseenter, _ => {
      hover := Some(i)
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
      handles.contents[i]->Option.forEach(h =>
        h.time
        ->Option.orElse(h.level)
        ->Option.orElse(h.curve)
        ->Option.forEach(id => {
          let def = model->ParamModel.def(id)
          let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
          let d = ev->shiftKey ? d * fine : d
          let n = def.toNorm(model->ParamModel.get(id))
          model->ParamModel.gestureSet(id, def.fromNorm(clamp(n + d, 0., 1.)))
        })
      )
    })
    (dot, hit)
  }

  let (_, initial, _) = shape.layout(frame.contents)
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

  s->suppressContextMenu
  s->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  s->onMouse(#mouseleave, _ =>
    if dragging.contents == None {
      ctx.status->Status.clear
    }
  )

  shape.ids->Array.forEach(id => model->ParamModel.listen(id, refresh))
  refresh()
}
