// Read-only plots drawn in the signal ink (current waveform, LFO shape), and the SVG
// helpers the graphical editors share.

open! Web

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

// A grid or axis line.
let line = (parent, ~cls="axis", x1, y1, x2, y2) =>
  parent->svgEl(
    "line",
    [("class", Str(cls)), ("x1", Num(x1)), ("y1", Num(y1)), ("x2", Num(x2)), ("y2", Num(y2))],
  )

let pathFrom = points =>
  points
  ->Array.mapWithIndex(((x, y), i) =>
    (i == 0 ? "M" : "L") ++ Float.toFixed(x, ~digits=2) ++ " " ++ Float.toFixed(y, ~digits=2)
  )
  ->Array.join("")

// Adds the curve t => (x, y) for t in (0, 1] to `points`, which already hold its start.
// `steps` even pieces are halved until the curve strays less than a tenth of a pixel from
// each straight line, so that steep bends stay smooth however far a curve is dragged.
let trace = (points, at: float => (float, float), ~steps=16) => {
  let rec piece = (t0: float, p0: (float, float), t1: float, p1: (float, float), depth) => {
    let ((x0, y0), (x1, y1)) = (p0, p1)
    let t = (t0 + t1) / 2.
    let (x, y) as p = at(t)
    // the middle's distance from the straight line
    let (dx, dy) = (x1 - x0, y1 - y0)
    let length2 = dx * dx + dy * dy
    let u = length2 > 0. ? Math.max(0., Math.min(1., ((x - x0) * dx + (y - y0) * dy) / length2)) : 0.
    let (ex, ey) = (x - x0 - u * dx, y - y0 - u * dy)
    if depth < 10 && ex * ex + ey * ey > 0.01 {
      piece(t0, p0, t, p, depth + 1)
      piece(t, p, t1, p1, depth + 1)
    } else {
      points->Array.push(p1)
    }
  }
  let last = ref((0., at(0.)))
  for k in 1 to steps {
    let (t0, p0) = last.contents
    let t1 = Int.toFloat(k) / Int.toFloat(steps)
    let p1 = at(t1)
    piece(t0, p0, t1, p1, 0)
    last := (t1, p1)
  }
}

let userAt = (user, phase) =>
  user->ByteView.getUnsafe(Float.toInt(Math.floor(phase * 512.)) &&& 511)

// The HQ waves drawn band-limited like the oscillator's, though with fewer harmonics than
// it keeps, so that the ripple of the band limit shows at this size.
let hqHarmonics = 24
let hqHint = "HQ: anti-aliased, so high notes stay clean"

let hqSaw = phase => {
  let sum = ref(0.)
  for k in 1 to hqHarmonics {
    let k = Int.toFloat(k)
    sum := sum.contents + Math.sin(2. * Math.Constants.pi * k * phase) / k
  }
  2. / Math.Constants.pi * sum.contents
}

let hqTriangle = phase => {
  let sum = ref(0.)
  for k in 0 to (hqHarmonics - 1) / 2 {
    let k = Int.toFloat(2 * k + 1)
    sum := sum.contents + Math.cos(2. * Math.Constants.pi * k * phase) / (k * k)
  }
  -8. / (Math.Constants.pi * Math.Constants.pi) * sum.contents
}

// One oscillator waveform sample at phase 0..1.
let waveSample = (wave, pw, user, phase) =>
  switch wave {
  | 0 => Math.sin(2. * Math.Constants.pi * phase)
  | 1 => 1. - 2. * phase
  | 2 => phase < pw ? 1. : -1.
  | 3 => phase < 0.5 ? 4. * phase - 1. : 3. - 4. * phase
  | 4 => userAt(user, phase)
  | 5 => 0.5 * (userAt(user, phase) - userAt(user, phase + pw))
  | 6 => hqSaw(phase)
  | 7 => hqSaw(phase) - hqSaw(phase - pw) + 2. * pw - 1.
  | 8 => hqTriangle(phase)
  | _ => 0.
  }

// Whether a waveform is one of the HQ (anti-aliased) ones.
let isHQ = wave => wave >= 6 && wave <= 8

// Oscillator waveform: built-in shapes are drawn analytically, user shapes come from
// the program store (512 points). The HQ shapes carry a badge, and their ripple can rise
// past ±1, so every shape is drawn a little smaller to leave it room.
let wave = (ctx: Ctx.t, parent, osc, box) => {
  let s = svg(parent, box)
  background(s, box)
  s->line(2., box.h / 2., box.w - 2., box.h / 2.)->ignore
  let curve = s->svgEl("path", [("class", Str("curve"))])
  let prefix = osc == 0 ? "O1_" : "O2_"
  let badge = el("span", ~cls="hq plotbadge", ~text="HQ", ~parent)->place(box.x + box.w - 24., box.y + 5.)
  badge->setAttribute("title", Str(hqHint))
  ctx.status->Status.hover(badge, () => hqHint)

  let draw = () => {
    let wave = Float.toInt(ctx.model->ParamModel.get(prefix ++ "Waveform"))
    let pw = ctx.model->ParamModel.get(prefix ++ "PWM_W")
    let user = ctx.programs->ProgramStore.shape(osc == 0 ? Wave1 : Wave2)
    let (w, h) = (box.w - 6., box.h - 8.)
    let scale = 0.5 / 1.2
    let n = Float.toInt(w)
    let points = Array.fromInitializer(~length=n + 1, k => {
      let f = Int.toFloat(k) / Int.toFloat(n)
      let v = waveSample(wave, pw, user, k == n ? 0.99999 : f)
      (3. + f * w, 4. + (0.5 - scale * Float.clamp(v, ~min=-1.2, ~max=1.2)) * h)
    })
    curve->setAttribute("d", Str(pathFrom(points)))
    badge->toggleClass("hidden", !isHQ(wave))
  }

  ctx.model->ParamModel.listenEach([prefix ++ "Waveform", prefix ++ "PWM_W"], draw)
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
    let random = FxDsp.hash(_, Int.toFloat(lfo))
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
      (3. + f * w, 3. + (1. - Float.clamp(v, ~min=0., ~max=1.)) * h)
    })
    curve->setAttribute("d", Str(pathFrom(points)))
  }

  ctx.model->ParamModel.listen(shapeId, draw)
  ctx.programs->ProgramStore.onShapes(draw)
  draw()
}
