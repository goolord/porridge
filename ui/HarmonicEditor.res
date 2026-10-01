// The harmonics of an oscillator waveform, under its shape editor: the level and the phase
// of the first 64 harmonics, as bars to click or drag. The engine band-limits the 512-point
// waveform through its spectrum, so any level and phase plays as drawn.
//
// Editing a harmonic adds the difference of its sine to the waveform, so everything else in
// it (other harmonics, those above 64, the DC offset) stays as it is. Phases are relative to
// a sine: the saw and square the tools draw have every phase at 0.

open! Web

let count = 64

let at = ByteView.getUnsafe
let setAt = TypedArray.set
let twoPi = 2. * Math.Constants.pi

type scale = Decibels | Linear

// the level scale: 0 dB (an amplitude of 1) at the top, floorDb at the bottom
let floorDb = -60.

type rec t = {
  ctx: Ctx.t,
  shape: ShapeEditor.t,
  levels: element,
  phases: element,
  scaleButton: element,
  labels: array<element>,
  mutable scale: scale,
  // per harmonic (index k - 1): amplitude and phase in radians
  amp: array<float>,
  phase: array<float>,
  mutable hover: option<int>,
  onEdit: unit => unit,
  onCommit: unit => unit,
}

let ink = canvas =>
  switch canvas->getComputedStyle->getPropertyValue("--signal")->String.trim {
  | "" => "#1c3c73"
  | ink => ink
  }

// amplitude -> bar height fraction, and back
let toFraction = (t, a) =>
  switch t.scale {
  | Linear => Math.min(1., a)
  | Decibels => a <= 0. ? 0. : Math.max(0., Math.min(1., 1. - 20. * Math.log10(a) / floorDb))
  }

let fromFraction = (t, f) =>
  if f <= 0.01 {
    0.
  } else {
    switch t.scale {
    | Linear => f
    | Decibels => Math.pow(10., ~exp=(1. - f) * floorDb / 20.)
    }
  }

// Measures the harmonics of the waveform. A harmonic too quiet to have a phase keeps the
// last one it had, so that it comes back with it.
let analyse = t => {
  let d = t.shape.data
  let n = TypedArray.length(d)
  for k in 1 to count {
    let re = ref(0.)
    let im = ref(0.)
    for i in 0 to n - 1 {
      let a = twoPi * Int.toFloat(k * i) / Int.toFloat(n)
      let v = d->at(i)
      re := re.contents + v * Math.cos(a)
      im := im.contents - v * Math.sin(a)
    }
    let amp = 2. * Math.hypot(re.contents, im.contents) / Int.toFloat(n)
    t.amp->Array.setUnsafe(k - 1, amp)
    if amp > 1e-5 {
      t.phase->Array.setUnsafe(k - 1, Math.atan2(~y=re.contents, ~x=-.im.contents))
    }
  }
}

let draw = t => {
  open Context2d
  let signal = ink(t.levels)
  let frame = (canvas, g) => {
    let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
    g->clearRect(0., 0., w, h)
    g->setFillStyle("rgba(236,227,196,0.45)")
    g->fillRect(0., 0., w, h)
    (w, h)
  }
  let gridLine = (g, w, y, ~strong=false) => {
    g->setStrokeStyle(strong ? "rgba(31,26,14,0.35)" : "rgba(31,26,14,0.14)")
    g->setLineWidth(1.)
    g->beginPath
    g->moveTo(0., Math.round(y) + 0.5)
    g->lineTo(w, Math.round(y) + 0.5)
    g->stroke
  }
  let border = (g, w, h) => {
    g->setStrokeStyle("#6f5f36")
    g->setLineWidth(2.)
    g->strokeRect(1., 1., w - 2., h - 2.)
  }
  let barWidth = w => w / Int.toFloat(count)
  let hoverBand = (g, w, h) =>
    t.hover->Option.forEach(k => {
      g->setFillStyle("rgba(28,60,115,0.12)")
      g->fillRect(Int.toFloat(k - 1) * barWidth(w), 0., barWidth(w), h)
    })

  // levels: bars up from the bottom; a cap marks a level above the top
  let g = t.levels->getContext2d
  let (w, h) = frame(t.levels, g)
  let inner = h - 8.
  switch t.scale {
  | Decibels =>
    [-12., -24., -36., -48.]->Array.forEach(db => gridLine(g, w, 4. + db / floorDb * inner))
  | Linear => [0.25, 0.5, 0.75]->Array.forEach(a => gridLine(g, w, 4. + (1. - a) * inner))
  }
  hoverBand(g, w, h)
  g->setFillStyle(signal)
  t.amp->Array.forEachWithIndex((a, i) => {
    let f = toFraction(t, a)
    let x = Int.toFloat(i) * barWidth(w)
    g->fillRect(x + 2., 4. + (1. - f) * inner, barWidth(w) - 4., f * inner)
    if a > 1.001 {
      g->fillRect(x + 1., 1., barWidth(w) - 2., 4.)
    }
  })
  border(g, w, h)

  // phases: bars from the centre line, faint where the harmonic is silent
  let g = t.phases->getContext2d
  let (w, h) = frame(t.phases, g)
  let mid = h / 2.
  gridLine(g, w, 4. + (h - 8.) / 4.)
  gridLine(g, w, h - 4. - (h - 8.) / 4.)
  hoverBand(g, w, h)
  gridLine(g, w, mid, ~strong=true)
  t.phase->Array.forEachWithIndex((p, i) => {
    let audible = t.amp->Array.getUnsafe(i) > 1e-4
    g->setFillStyle(audible ? signal : "rgba(31,26,14,0.22)")
    let y = mid - p / Math.Constants.pi * (h / 2. - 4.)
    let x = Int.toFloat(i) * barWidth(w)
    g->fillRect(x + 2., Math.min(y, mid), barWidth(w) - 4., Math.max(1.5, Math.abs(y - mid)))
  })
  border(g, w, h)
}

let refresh = t => {
  analyse(t)
  draw(t)
}

// Sets harmonic k's amplitude and phase, adding the difference to the waveform.
let setHarmonic = (t, k, amp, phase) => {
  let d = t.shape.data
  let n = TypedArray.length(d)
  let (amp0, phase0) = (t.amp->Array.getUnsafe(k - 1), t.phase->Array.getUnsafe(k - 1))
  for i in 0 to n - 1 {
    let a = twoPi * Int.toFloat(k * i) / Int.toFloat(n)
    d->setAt(i, d->at(i) + amp * Math.sin(a + phase) - amp0 * Math.sin(a + phase0))
  }
  t.amp->Array.setUnsafe(k - 1, amp)
  t.phase->Array.setUnsafe(k - 1, phase)
}

let phaseDegrees = p => {
  let d = Math.round(p * 180. / Math.Constants.pi)
  (d > 0. ? "+" : "") ++ Float.toString(d) ++ "°"
}

let statusText = (t, k) => {
  let a = t.amp->Array.getUnsafe(k - 1)
  let level =
    a < 1e-5
      ? "off"
      : `${Float.toFixed(20. * Math.log10(a), ~digits=1)} dB (${Float.toFixed(a, ~digits=3)})`
  `Harmonic ${Int.toString(k)}: ${level}, phase ${phaseDegrees(
      t.phase->Array.getUnsafe(k - 1),
    )}. Click or drag to set, right-click to clear.`
}

// The harmonic under the pointer, and the pointer's height in the bars' range (0 at the
// bottom). The bars leave 4 canvas pixels free at the top and the bottom.
let pointerAt = (canvas, ev) => {
  let r = canvas->getBoundingClientRect
  let fx = (ev->clientX - r.left) / r.width
  let fy = 1. - (ev->clientY - r.top) / r.height
  let k = Math.Int.max(1, Math.Int.min(count, Float.toInt(Math.floor(fx * Int.toFloat(count))) + 1))
  let margin = 4. / canvas->canvasHeight
  (k, Math.max(0., Math.min(1., (fy - margin) / (1. - 2. * margin))))
}

// Dragging sets every harmonic the pointer passes; clear sets them to their reset value.
let hookCanvas = (t, canvas, ~apply: (int, float, bool) => unit) => {
  let hover = ev => {
    let (k, _) = pointerAt(canvas, ev)
    if t.hover != Some(k) {
      t.hover = Some(k)
      draw(t)
    }
    t.ctx.status->Status.show(statusText(t, k))
  }
  canvas->onMouse(#mousemove, hover)
  canvas->onMouse(#mouseleave, _ => {
    t.hover = None
    draw(t)
    t.ctx.status->Status.clear
  })
  canvas->suppressContextMenu
  canvas->onPointer(#pointerdown, ev =>
    if ev->button == 0 || ev->button == 2 {
      ev->preventDefault
      let clear = ev->button == 2
      t.shape->ShapeEditor.pushUndo
      let last = ref(None)
      let stroke = ev => {
        let (k, f) = pointerAt(canvas, ev)
        let from = last.contents->Option.getOr((k, f))
        let (k0, f0) = from
        // fill in the harmonics between this move and the last one
        let steps = Math.Int.abs(k - k0)
        for s in 0 to steps {
          let j = steps == 0 ? k : k0 + (k > k0 ? s : -s)
          let v = steps == 0 ? f : f0 + (f - f0) * Int.toFloat(s) / Int.toFloat(steps)
          apply(j, v, clear)
        }
        last := Some((k, f))
        t.shape->ShapeEditor.draw
        draw(t)
        t.onEdit()
        t.ctx.status->Status.show(statusText(t, k))
      }
      stroke(ev)
      canvas->Controls.capturePointer(ev, ~onMove=stroke, ~onUp=() => {
        // measure again, so that rounding doesn't build up over strokes
        refresh(t)
        t.onCommit()
      })
    }
  )
}

let setScale = (t, scale) => {
  t.scale = scale
  t.scaleButton->setTextContent(scale == Decibels ? "dB" : "linear")
  draw(t)
}

let make = (
  ctx: Ctx.t,
  parent,
  shape: ShapeEditor.t,
  ~levels: box,
  ~phases: box,
  ~onEdit,
  ~onCommit,
) => {
  let canvas = (b: box) => {
    let c = el("canvas", ~cls="draw", ~parent)->placeBox(b)
    c->setCanvasWidth(b.w * 2.)
    c->setCanvasHeight(b.h * 2.)
    c
  }
  let label = (b: box, text) => el("div", ~cls="hlabel", ~text, ~parent)->place(b.x + 4., b.y + 3.)
  let levelsCanvas = canvas(levels)
  let phasesCanvas = canvas(phases)
  let labels = [label(levels, "harmonics 1-64: level"), label(phases, "phase")]
  let scaleButton = Controls.button(
    ctx,
    parent,
    "dB",
    ~x=levels.x + levels.w - 54.,
    ~y=levels.y + 4.,
    ~w=50.,
    ~status="Show the levels in decibels or linearly",
    () => (),
  )
  scaleButton->addClass("xbtn")
  let t = {
    ctx,
    shape,
    levels: levelsCanvas,
    phases: phasesCanvas,
    scaleButton,
    labels,
    scale: Decibels,
    amp: Array.make(~length=count, 0.),
    phase: Array.make(~length=count, 0.),
    hover: None,
    onEdit,
    onCommit,
  }
  scaleButton->onMouse(#click, _ => setScale(t, t.scale == Decibels ? Linear : Decibels))

  hookCanvas(t, levelsCanvas, ~apply=(k, f, clear) =>
    setHarmonic(t, k, clear ? 0. : fromFraction(t, f), t.phase->Array.getUnsafe(k - 1))
  )
  hookCanvas(t, phasesCanvas, ~apply=(k, f, clear) =>
    setHarmonic(t, k, t.amp->Array.getUnsafe(k - 1), clear ? 0. : (f - 0.5) * twoPi)
  )
  t
}

let setVisible = (t, visible) => {
  let display = visible ? "block" : "none"
  [t.levels, t.phases, t.scaleButton, ...t.labels]->Array.forEach(e =>
    e->setStyle("display", display)
  )
}
