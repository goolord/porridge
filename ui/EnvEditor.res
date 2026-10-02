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
  // not shown, for a bend point whose stage is skipped or flat
  hidden: bool,
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
  hidden: false,
  curve: None,
  bendSign: 0.,
}

// A stage's bend point, at the middle of its segment.
let bendPoint = (~hidden=false, curve, (x, y), ~rising) => {
  ...point(x, x, y),
  hidden,
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
  // the parameter that scales what the envelope does (the filter's env mod, -1..1), drawn as
  // the envelope at that depth with a label for it, and the label
  depth: option<(string, unit => string)>,
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

// The DSP's stage curves: a stage's progress p along Oatmeal's path, warped by k = 8^curve.
// The inverse is the warp by -curve.
let warp = (p: float, curve: float) => {
  let k = Math.pow(8., ~exp=curve)
  k * p / (1. + (k - 1.) * p)
}

// The envelope a parameter prefix belongs to, as PorridgeParams names it.
let envName = prefix =>
  switch prefix {
  | "" => "Amp"
  | "F_" => "Filter"
  | "M1_" => "Mod1"
  | "OE1_" => PorridgeParams.oscEnvName(1)
  | "OE2_" => PorridgeParams.oscEnvName(2)
  | _ => "Mod2"
  }

// An oscillator's own envelope (PorridgeParams.oscEnvSpecs): its switch.
let switchOf = prefix =>
  switch prefix {
  | "OE1_" | "OE2_" => Some(prefix ++ "On")
  | _ => None
  }

// attack, decay 1, decay 2 and release
let curveIds = prefix => {
  let env = envName(prefix)
  let curve = PorridgeParams.curveId(env, ...)
  [curve("Attack"), PorridgeParams.decay1CurveId(env), curve("Decay"), curve("Release")]
}

// Attack, hold, decay 1 to the breakpoint, decay 2 to sustain, release. The amp envelope (and
// the oscillators', which are like it) is drawn in dB like its readouts; the others are
// linear, like their percentages. The amp envelope's levels are the DSP's renderAmp: smoothed
// by envCubic, and its release rescaled to end at 0. The others are its renderBlock: the
// stages' exponential paths as they are, and the release cut off at -60 dB.
let adsr = (ctx: Ctx.t, prefix, ~w, ~h): shape => {
  let model = ctx.model
  let id = k => prefix ++ k
  let get = k => model->ParamModel.get(id(k))
  let (attackCurve, decay1Curve, decay2Curve, releaseCurve) = switch curveIds(prefix) {
  | [a, d1, d2, r] => (a, d1, d2, r)
  | _ => ("", "", "", "")
  }
  let curve = c => model->ParamModel.get(c)
  let levelDef = model->ParamModel.def(id("Sustain"))
  let decibels = prefix == "" || switchOf(prefix) != None
  let block = prefix != ""
  let (top, bottom) = (margin, bottomOf(h))
  let yOf = v => {
    let f = decibels ? levelDef.toNorm(v) : v
    bottom - Float.clamp(f, ~min=0., ~max=1.) * (bottom - top)
  }
  let fractionAt = y => Float.clamp((bottom - y) / (bottom - top), ~min=0., ~max=1.)
  let levelAt = y => decibels ? levelDef.fromNorm(fractionAt(y)) : fractionAt(y)
  // the DSP treats a breakpoint above 0.998 as "skip decay 1"
  let skipped = () => get("Breakpoint") > 0.998

  let fit = () => {
    let stages = skipped()
      ? ["Attack", "Hold", "Decay2", "Release"]
      : ["Attack", "Hold", "Decay1", "Decay2", "Release"]
    let total = stages->Array.reduce(0., (a, k) => a + units(get(k)))
    {unitPx: (w - 2. * margin - 5. * segmentGap) / niceSpan(total), limit: 1.}
  }

  let layout = f => {
    let after = (x0, k) => x0 + segmentGap + units(get(k)) * f.unitPx
    let skip = skipped()
    let bp = skip ? 1. : Math.max(get("Breakpoint"), block ? 1e-6 : 1e-4)
    let sus = get("Sustain")
    let x0 = margin
    let xa = after(x0, "Attack")
    let xh = after(xa, "Hold")
    let xb = skip ? xh + segmentGap : after(xh, "Decay1")
    // the release starts at the sustain point: the time a note is held has no width
    let xs = after(xb, "Decay2")
    let xr = after(xs, "Release")

    let points = [(x0, yOf(0.))]
    // each sampled segment, and its middle point
    let sample = (xFrom: float, xTo: float, level) => {
      points->Plots.trace(t => (xFrom + (xTo - xFrom) * t, yOf(level(t))))
      ((xFrom + xTo) / 2., yOf(level(0.5)))
    }
    let (ca, cd1, cd2, cr) = (curve(attackCurve), curve(decay1Curve), curve(decay2Curve), curve(releaseCurve))
    let attackMid = sample(x0, xa, t => {
      let a = warp(t, ca)
      block ? a : (2. - a) * a
    })
    points->Array.push((xh, yOf(1.)))
    let decay1Mid = if skip {
      // decay 2 starts from the top, at the hollow breakpoint
      points->Array.push((xb, yOf(1.)))
      ((xh + xb) / 2., yOf(1.))
    } else {
      sample(xh, xb, t => {
        let l = Math.pow(bp, ~exp=warp(t, cd1))
        block ? l : envCubic(l, bp, 1.)
      })
    }
    // A block envelope's decay 2 aims at the sustain level, but no lower than 120 dB under the
    // breakpoint: at a sustain of 0 it falls that far in its time, then stays there.
    let lo = block ? Math.max(sus, bp * 1e-6) : Math.max(sus, 1e-4)
    let decay2At = p => {
      let l = bp * Math.pow(lo / bp, ~exp=warp(p, cd2))
      block ? l : envCubic(l, lo, bp)
    }
    // A sustain at -inf: the amp envelope's decay 2 aims 120 dB under the breakpoint and stops
    // at -80 dB, this fraction of its time (an oscillator's runs all of its time, as above). It
    // falls past the bottom of a dB graph (-60 dB) before that, at progress `floorAt`; the
    // curve is stretched to end there, at the sustain point, and the time axis says when that is.
    let reach = prefix == "" && sus == 0. ? Math.log(lo / bp) / Math.log(1e-6) : 1.
    let floorAt = if decibels && sus < 0.001 && decay2At(0.) > 0.001 {
      let (a, b) = (ref(0.), ref(1.))
      for _i in 1 to 40 {
        let m = (a.contents + b.contents) / 2.
        decay2At(m) > 0.001 ? (a := m) : (b := m)
      }
      b.contents
    } else {
      1.
    }
    let decay2Mid = sample(xb, xs, t => decay2At(t * floorAt))
    points->Array.push((xs, yOf(sus)))
    // The release falls 60 dB in its time, from the sustain level to 0.001, where it ends: this
    // fraction of its time. Its curve warps its progress along that path. The amp's is rescaled
    // to end at 0, and reaches the bottom of its graph (-60 dB) at progress `bottom`; a block
    // envelope's drops to 0 from 0.001, at the end of the path. The curve is stretched to end
    // there, and the time axis says when that is.
    let k = block ? 1. : sus / (sus - 0.001)
    let (path, bottom) = if sus <= 0.001 {
      (1., 1.)
    } else {
      let path = Math.log10(sus / 0.001) / 3.
      (path, block ? 1. : warp(Math.log10(sus / (0.001 / k + 0.001)) / 3. / path, -.cr))
    }
    let fall = Math.min(1., path * bottom)
    let releaseMid = sample(xs, xr, t =>
      sus <= 0.001
        ? 0.
        : (sus * Math.pow(10., ~exp=-3. * path * warp(t * bottom, cr)) - (block ? 0. : 0.001)) * k
    )
    let ta = get("Attack")
    let th = ta + get("Hold")
    let tb = th + (skip ? 0. : get("Decay1"))
    let times = [
      stretch(x0, xa, 0., ta),
      stretch(xa, xh, ta, th),
      stretch(xh, xb, th, tb),
      stretch(xb, xs, tb, tb + get("Decay2") * reach * floorAt),
      stretch(~release=true, xs, xr, 0., get("Release") * fall),
    ]

    let top = yOf(1.)
    let handles = [
      point(~time=id("Attack"), x0, xa, top),
      point(~time=id("Hold"), xa, xh, top),
      point(~time=id("Decay1"), ~level=id("Breakpoint"), ~hollow=skip, xh, xb, yOf(bp)),
      point(~time=id("Decay2"), ~level=id("Sustain"), xb, xs, yOf(sus)),
      point(~time=id("Release"), xs, xr, yOf(0.)),
      bendPoint(attackCurve, attackMid, ~rising=true),
      bendPoint(~hidden=skip, decay1Curve, decay1Mid, ~rising=false),
      bendPoint(~hidden=Math.abs(bp - sus) < 0.02, decay2Curve, decay2Mid, ~rising=sus > bp),
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

  // the filter envelope moves the cutoff by its env mod at the top (up to 8 octaves either way)
  let depth = switch prefix {
  | "F_" =>
    Some((
      "F_EnvMod",
      () =>
        model->ParamModel.get("F_EnvMod") == 0.
          ? "env mod 0: the cutoff stays put"
          : "env mod " ++ model->ParamModel.shortText("F_EnvMod"),
    ))
  | _ => None
  }

  {
    ids: [
      ...["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release"]->Array.map(id),
      ...curveIds(prefix),
      ...depth->Option.mapOr([], ((id, _)) => [id]),
      ...switchOf(prefix)->Option.mapOr([], id => [id]),
    ],
    fit,
    layout,
    setTime,
    setLevel,
    zero: None,
    dimmed: () => switchOf(prefix)->Option.mapOr(false, id => model->ParamModel.get(id) == 0.),
    depth,
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
  let releasePx = 0.16 * (w - 2. * margin)
  let mid = (margin + bottomOf(h)) / 2.
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
      unitPx: (w - 2. * margin - 2. * segmentGap - releasePx) / niceSpan(total),
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
    let xr = xs + releasePx

    let attack = t => (x0 + (xp - x0) * t, yOf(semitones(r0 + (r1 - r0) * t), f))
    let points = [attack(0.)]
    points->Plots.trace(attack)
    points->Array.push((xs, yOf(sustain, f)))
    points->Array.push((xr, yOf(sustain + release, f)))

    let tp = get("PEnv_Attack") * attackFactor()
    let times = [
      stretch(x0, xp, 0., tp),
      stretch(xp, xs, tp, tp + get("PEnv_Decay")),
      stretch(~release=true, xs, xr, 0., 1000.),
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
    depth: None,
  }
}

//==============================================================================
// The editor

// Where a note is on the time axis: ms since its note-on while held (up to the sustain point,
// where held notes wait), since its note-off once released.
let xOfClock = (times: array<stretch>, ms, ~released) => {
  let ts = times->Array.filter(t => t.release == released)
  switch ts->Array.find(t => ms >= t.msFrom && ms <= t.msTo) {
  | Some(t) => Some(t.xFrom + (t.xTo - t.xFrom) * (ms - t.msFrom) / Math.max(t.msTo - t.msFrom, 1e-9))
  | None =>
    switch (ts[0], ts[Array.length(ts) - 1]) {
    | (Some(first), _) if ms < first.msFrom => Some(first.xFrom)
    | (_, Some(last)) => Some(last.xTo)
    | _ => None
    }
  }
}

// fields: the raw parameters shown by the "values" switch, four to a row; clock: where each
// sounding note is on this envelope (VoiceView), for a mark per note
let make = (
  ctx: Ctx.t,
  parent,
  box: box,
  shape: shape,
  ~fields: array<(string, string)>,
  ~name,
  ~clock: option<VoiceView.voice => float>=?,
) => {
  let model = ctx.model
  let ed = NodeEditor.make(ctx, parent, box, ~hint=hintFor(name), ~columns=4)
  let zero = ed.g.under->Plots.line(2., 0., box.w - 2., 0.)
  let fill = FxGraph.path(ed.g.under, ~cls="fill")
  let ticks = FxGraph.group(ed.g.under)
  let curve = FxGraph.path(ed.g.under, ~cls="curve")
  // the envelope at its depth: rising from the bottom, or for a negative depth hanging from the top
  let depthCurve = FxGraph.path(ed.g.under, ~cls="curve depth")
  let depthLabel = svgEl(ed.g.under, "text", [("class", Str("tick depth")), ("text-anchor", Str("end"))])
  fields->Array.forEachWithIndex(((id, label), i) => ed.values->Grid.param(id, mod(i, 4), i / 4, label))

  let frame = ref(shape.fit())
  let handles = ref([])

  let statusFor = h => model->ParamModel.statusText(handleIds(h))
  let readoutFor = h => h->handleIds->Array.map(id => model->ParamModel.shortText(id))->Array.join("  ·  ")

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
            FxGraph.line(ticks, ~cls="axis faint", x, 1., x, box.h - 1.)
            FxGraph.text(ticks, ~anchor=flip ? "end" : "start", flip ? x - 3. : x + 3., box.h - 4., text)
          }
        }
      )
    )
  }

  let startDrag = (i, hit, ev) =>
    handles.contents[i]->Option.forEach(h => {
      let x = ref(h.x)
      let y = ref(h.y)
      let curve0 = h.curve->Option.map(c => model->ParamModel.get(c))->Option.getOr(0.)
      ed->NodeEditor.drag(i, hit, ev, ~ids=handleIds(h), ~onMove=(dx, dy) => {
        x := Float.clamp(x.contents + dx, ~min=h.x0 + segmentGap, ~max=box.w * 4.)
        y := Float.clamp(y.contents + dy, ~min=margin, ~max=bottomOf(box.h))
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

  // every hit area above every dot, so a dot never hides a neighbour's hit area
  let (_, initial, _) = shape.layout(frame.contents)
  let nodes = initial->Array.mapWithIndex((h, i) =>
    ed->NodeEditor.node(
      i,
      ~dot=[("class", Str("node")), ("r", Num(4.))],
      ~hitR=h.curve != None ? 6. : 8.,
      ~cursor=switch (h.time, h.level) {
      | (Some(_), Some(_)) => "move"
      | (Some(_), None) => "ew-resize"
      | _ => "ns-resize"
      },
      ~onDrag=startDrag(i, ...),
      ~onRightClick=() =>
        handles.contents[i]->Option.forEach(h =>
          h->handleIds->Array.forEach(id => model->ParamModel.gestureSet(id, (model->ParamModel.def(id)).init))
        ),
      ~wheel=() => handles.contents[i]->Option.flatMap(h => h.time->Option.orElse(h.level)->Option.orElse(h.curve)),
    )
  )

  // a mark per sounding note, on the curve where its envelope is
  let notes = VoiceView.marks(FxGraph.group(ed.g.under))
  let lastLayout = ref(([], []))
  let drawNotes = () =>
    clock->Option.forEach(clock => {
      let (points, times) = lastLayout.contents
      let voices = parent->offsetParent->Option.isSome ? VoiceView.get(ctx.pc).voices : []
      notes->VoiceView.show(
        voices->Array.filterMap(v =>
          xOfClock(times, clock(v), ~released=v.released)->Option.map(x => (x, VoiceView.yAt(points, x), v.released))
        ),
      )
    })
  if clock != None {
    VoiceView.get(ctx.pc)->VoiceView.listen(drawNotes)
  }

  let draw = () => {
    let (points, hs, times) = shape.layout(frame.contents)
    handles := hs
    lastLayout := (points, times)
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
    switch shape.depth {
    | Some((id, label)) =>
      let amount = Float.clamp(model->ParamModel.get(id), ~min=-1., ~max=1.)
      let (top, bottom) = (margin, bottomOf(box.h))
      let scaled = points->Array.map(((x, y)) => {
        let f = (bottom - y) / (bottom - top) * Math.abs(amount)
        (x, amount >= 0. ? bottom - f * (bottom - top) : top + f * (bottom - top))
      })
      depthCurve->setAttribute("d", Str(Plots.pathFrom(scaled)))
      // (at the top, left of the "values" switch)
      depthLabel->setAttribute("x", Num(amount < 0. ? box.w - 6. : box.w - 58.))
      depthLabel->setAttribute("y", Num(amount < 0. ? bottomOf(box.h) - 4. : margin + 9.))
      depthLabel->setTextContent(label())
    | None => ()
    }
    switch shape.zero {
    | Some(y) =>
      let y = y(frame.contents)
      zero->setAttribute("y1", Num(y))
      zero->setAttribute("y2", Num(y))
    | None => zero->setAttribute("opacity", Num(0.))
    }
    ed.g.svg->toggleClass("off", shape.dimmed())

    nodes->Array.forEachWithIndex((node, i) =>
      hs[i]->Option.forEach(h => {
        node->NodeEditor.place(h.x, h.y)
        [node.dot, node.hit]->Array.forEach(e => e->setAttribute("display", Str(h.hidden ? "none" : "inline")))
        let hot = ed.hover == Some(i) || ed.dragging == Some(i)
        let isBend = h.curve != None
        node.dot->setAttribute(
          "class",
          Str("node" ++ (h.hollow ? " hollow" : "") ++ (isBend ? " bend" : "") ++ (hot ? " hot" : "")),
        )
        node.dot->setAttribute("r", Num(isBend ? (hot ? 4.5 : 3.) : hot ? 5.5 : 4.))
      })
    )

    switch NodeEditor.focus(ed)->Option.flatMap(i => hs[i]) {
    | Some(h) =>
      ctx.status->Status.show(statusFor(h))
      if ed.dragging != None {
        ed.g->FxGraph.readout(~x=h.x, ~y=h.y, ~dx=10., ~above=9., ~below=18., ~nearTop=24., readoutFor(h))
      }
    | None => ()
    }
    if ed.dragging == None {
      ed.g->FxGraph.hideReadout
    }
  }

  // the axis is refitted when a drag ends, never during one
  let refresh = () => {
    if ed.dragging == None {
      frame := shape.fit()
    }
    draw()
  }

  ed->NodeEditor.start(shape.ids, refresh)
}
