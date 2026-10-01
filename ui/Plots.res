// Small read-only plots drawn in the signal ink. They carry information (envelope
// shape, current waveform, LFO shape), so they earn their space.

open! Web

let svgNamespace = "http://www.w3.org/2000/svg"

let svg = (parent, box) => {
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str("plot"))
  s->setAttribute("width", Num(box.w))
  s->setAttribute("height", Num(box.h))
  s->setAttribute("viewBox", Str(`0 0 ${Float.toString(box.w)} ${Float.toString(box.h)}`))
  s->placeBox(box)->ignore
  parent->appendChild(s)
  s
}

let svgEl = (parent, tag, attrs) => {
  let e = document->createElementNS(svgNamespace, tag)
  attrs->Array.forEach(((name, value)) => e->setAttribute(name, value))
  parent->appendChild(e)
  e
}

let background = (s, box) =>
  s
  ->svgEl(
    "rect",
    [
      ("class", Str("bg")),
      ("x", Num(0.5)),
      ("y", Num(0.5)),
      ("width", Num(box.w - 1.)),
      ("height", Num(box.h - 1.)),
    ],
  )
  ->ignore

let pathFrom = points =>
  points
  ->Array.mapWithIndex(((x, y), i) =>
    (i == 0 ? "M" : "L") ++ Float.toFixed(x, ~digits=1) ++ " " ++ Float.toFixed(y, ~digits=1)
  )
  ->Array.join("")

let sum = parts => parts->Array.reduce(0., (a, b) => a + b)

// compressed seconds
let segment = ms => Math.sqrt(Math.max(0., ms) / 1000.)

// Envelope: attack, hold, decay 1 to breakpoint, decay 2 to sustain, (sustain), release.
// Time axis is compressed (sqrt) so that 1 ms and 10 s segments are both readable.
let envelope = (ctx: Ctx.t, parent, prefix, box) => {
  let s = svg(parent, box)
  background(s, box)
  let fill = s->svgEl("path", [("class", Str("fill"))])
  let curve = s->svgEl("path", [("class", Str("curve"))])

  let draw = () => {
    let get = k => ctx.model->ParamModel.get(prefix ++ k)
    let breakpoint = get("Breakpoint")
    let sustain = get("Sustain")
    let skipDecay1 = breakpoint >= 1.

    let hold = 0.35 // visual sustain width
    let parts = [
      segment(get("Attack")),
      segment(get("Hold")),
      skipDecay1 ? 0. : segment(get("Decay1")),
      segment(get("Decay2")),
      hold,
      segment(get("Release")),
    ]
    let total = switch sum(parts) {
    | 0. => 1.
    | total => total
    }
    let (w, h, x0, y0) = (box.w - 4., box.h - 5., 2., 2.)
    let px = t => x0 + t / total * w
    let py = a => y0 + (1. - Math.sqrt(Math.max(0., Math.min(1., a)))) * h // sqrt amplitude reads like loudness

    let t = ref(0.)
    let points = [(px(0.), py(0.))]
    let lineTo = (dt, a) => {
      t := t.contents + dt
      points->Array.push((px(t.contents), py(a)))
    }
    let curveTo = (dt, from: float, to) => {
      let n = 16
      for k in 1 to n {
        let f = Int.toFloat(k) / Int.toFloat(n)
        let a = from + (to - from) * (1. - Math.pow(1. - f, ~exp=3.))
        points->Array.push((px(t.contents + dt * f), py(a)))
      }
      t := t.contents + dt
    }

    let part = i => parts->Array.getUnsafe(i)
    lineTo(part(0), 1.)
    lineTo(part(1), 1.)
    if !skipDecay1 {
      curveTo(part(2), 1., breakpoint)
    }
    curveTo(part(3), skipDecay1 ? 1. : breakpoint, sustain)
    lineTo(part(4), sustain)
    curveTo(part(5), sustain, 0.)

    let d = pathFrom(points)
    curve->setAttribute("d", Str(d))
    let close = `L${Float.toFixed(px(t.contents), ~digits=1)} ${Float.toString(
        py(0.),
      )}L${Float.toString(px(0.))} ${Float.toString(py(0.))}Z`
    fill->setAttribute("d", Str(d ++ close))
  }

  ["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release"]->Array.forEach(k =>
    ctx.model->ParamModel.listen(prefix ++ k, draw)
  )
  draw()
}

// Pitch envelope in semitones against the same compressed time axis. The attack is
// linear in frequency ratio (so it bends when drawn in semitones), the decay is linear in
// semitones, and the release glides at its st/sec rate; one second of it is shown.
let pitchEnvelope = (ctx: Ctx.t, parent, box) => {
  let s = svg(parent, box)
  background(s, box)
  let zero = s->svgEl("line", [("class", Str("axis")), ("x1", Num(2.)), ("x2", Num(box.w - 2.))])
  let curve = s->svgEl("path", [("class", Str("curve"))])

  let draw = () => {
    let get = id => ctx.model->ParamModel.get(id)
    let octave = Math.log2(Math.max(1e-6, get("Tune_Octave")))
    let start = get("PEnv_Start")
    let peak = get("PEnv_Peak") * octave
    let sustain = get("PEnv_Sustain") * octave
    let startRatio = start <= -48. ? 0. : Math.pow(2., ~exp=start / 12.)
    let peakRatio = Math.pow(2., ~exp=peak / 12.)
    let release = get("PEnv_Release") * octave
    let attack = get("PEnv_Attack") * (peakRatio <= startRatio ? 0.5 : 1.)

    let parts = [segment(attack), segment(get("PEnv_Decay")), 0.35, 0.35]
    let total = switch sum(parts) {
    | 0. => 1.
    | total => total
    }

    let floor = -48.
    let semitones = r => r > 0. ? Math.max(floor, 12. * Math.log2(r)) : floor
    let values = [semitones(startRatio), peak, sustain, sustain + release]
    let limit = Math.min(
      48.,
      Math.max(12., 12. * Math.ceil(Math.maxMany(values->Array.map(Math.abs)) / 12.)),
    )

    let (w, h, x0, y0) = (box.w - 4., box.h - 6., 2., 3.)
    let px = t => x0 + t / total * w
    let py = v => y0 + (0.5 - 0.5 * Math.max(-1., Math.min(1., v / limit))) * h

    let part = i => parts->Array.getUnsafe(i)
    let n = 24
    let points = Array.fromInitializer(~length=n + 1, k => {
      let (k, n) = (Int.toFloat(k), Int.toFloat(n))
      (px(part(0) * k / n), py(semitones(startRatio + (peakRatio - startRatio) * k / n)))
    })
    let t = part(0)
    points->Array.push((px(t + part(1)), py(sustain)))
    let t = t + part(1) + part(2)
    points->Array.push((px(t), py(sustain)))
    points->Array.push((px(t + part(3)), py(sustain + release)))

    zero->setAttribute("y1", Num(py(0.)))
    zero->setAttribute("y2", Num(py(0.)))
    curve->setAttribute("d", Str(pathFrom(points)))
    s->toggleClass("off", get("PEnv_On") == 0.)
  }

  ["On", "Start", "Attack", "Peak", "Decay", "Sustain", "Release"]->Array.forEach(k =>
    ctx.model->ParamModel.listen("PEnv_" ++ k, draw)
  )
  ctx.model->ParamModel.listen("Tune_Octave", draw)
  draw()
}

let userAt = (user, phase) =>
  user->ByteView.getUnsafe(Float.toInt(Math.floor(phase * 512.)) &&& 511)

// One oscillator waveform sample at phase 0..1.
let waveSample = (wave, pw, user, phase) =>
  switch wave {
  | 0 => Math.sin(2. * Math.Constants.pi * phase)
  | 1 => 1. - 2. * phase
  | 2 => phase < pw ? 1. : -1.
  | 3 => phase < 0.5 ? 4. * phase - 1. : 3. - 4. * phase
  | 4 => userAt(user, phase)
  | 5 => 0.5 * (userAt(user, phase) - userAt(user, phase + pw))
  | _ => 0.
  }

// Oscillator waveform: built-in shapes are drawn analytically, user shapes come from
// the program store (512 points).
let wave = (ctx: Ctx.t, parent, osc, box) => {
  let s = svg(parent, box)
  background(s, box)
  s
  ->svgEl(
    "line",
    [
      ("class", Str("axis")),
      ("x1", Num(2.)),
      ("x2", Num(box.w - 2.)),
      ("y1", Num(box.h / 2.)),
      ("y2", Num(box.h / 2.)),
    ],
  )
  ->ignore
  let curve = s->svgEl("path", [("class", Str("curve"))])
  let prefix = osc == 0 ? "O1_" : "O2_"

  let draw = () => {
    let wave = Float.toInt(ctx.model->ParamModel.get(prefix ++ "Waveform"))
    let pw = ctx.model->ParamModel.get(prefix ++ "PWM_W")
    let user = ctx.programs->ProgramStore.shape(osc == 0 ? Wave1 : Wave2)
    let (w, h) = (box.w - 6., box.h - 8.)
    let n = 96
    let points = Array.fromInitializer(~length=n + 1, k => {
      let f = Int.toFloat(k) / Int.toFloat(n)
      let v = waveSample(wave, pw, user, k == n ? 0.99999 : f)
      (3. + f * w, 4. + (0.5 - 0.5 * Math.max(-1., Math.min(1., v))) * h)
    })
    curve->setAttribute("d", Str(pathFrom(points)))
  }

  ctx.model->ParamModel.listen(prefix ++ "Waveform", draw)
  ctx.model->ParamModel.listen(prefix ++ "PWM_W", draw)
  ctx.programs->ProgramStore.onShapes(draw)
  draw()
}

// Two cycles of an LFO shape.
let lfo = (ctx: Ctx.t, parent, lfo, box) => {
  let s = svg(parent, box)
  background(s, box)
  let curve = s->svgEl("path", [("class", Str("curve"))])
  let shapeId = `LFO_${Int.toString(lfo + 1)}_Shape`

  let draw = () => {
    let shape = Float.toInt(ctx.model->ParamModel.get(shapeId))
    let user = ctx.programs->ProgramStore.shape(lfo == 0 ? LfoShape1 : LfoShape2)
    let (w, h) = (box.w - 6., box.h - 7.)
    let n = 2 * 64
    // deterministic pseudo-random values for the random shapes' preview
    let random = k => {
      let x = Math.sin(k * 12.9898 + Int.toFloat(lfo) * 78.233) * 43758.5453
      x - Math.floor(x)
    }
    let points = Array.fromInitializer(~length=n + 1, k => {
      let f = Int.toFloat(k) / Int.toFloat(n)
      let phase = Float.mod(f * 2., 1.)
      let cycle = Math.floor(f * 2. - 1e-9)
      let v = switch shape {
      | 0 => 0.5 + 0.5 * Math.sin(2. * Math.Constants.pi * phase)
      | 1 => 1. - phase
      | 2 => phase < 0.5 ? 1. : 0.
      | 3 => phase < 0.5 ? 2. * phase : 2. - 2. * phase
      | 4 =>
        let (a, b) = (random(cycle), random(cycle + 1.))
        a + (b - a) * (0.5 - 0.5 * Math.cos(Math.Constants.pi * phase))
      | 5 => random(cycle)
      | _ => userAt(user, phase)
      }
      (3. + f * w, 3. + (1. - Math.max(0., Math.min(1., v))) * h)
    })
    curve->setAttribute("d", Str(pathFrom(points)))
  }

  ctx.model->ParamModel.listen(shapeId, draw)
  ctx.programs->ProgramStore.onShapes(draw)
  draw()
}
