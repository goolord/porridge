// Shape editor used for oscillator waveforms (512 points, -1..1), LFO shapes
// (512 points, 0..1) and the velocity/aftertouch curves (64 points, 0..1).
//
// Left-drag draws. Shift-click sets a line from the last point. Ctrl-drag smooths
// locally (more smoothing higher up). Right-click: context menu.

open! Web

@send external blit: (Float32Array.t, Float32Array.t) => unit = "set"

let at = ByteView.getUnsafe
let setAt = TypedArray.set

type rec t = {
  ctx: Ctx.t,
  box: box,
  n: int,
  mutable bipolar: bool,
  mutable gridDivs: int,
  mutable data: Float32Array.t,
  mutable undoStack: array<Float32Array.t>,
  mutable menu: array<menuItem>,
  // the last point drawn, for shift-click lines
  mutable last: option<(int, float)>,
  canvas: element,
  g: context2d,
  // called while drawing (throttled by the caller)
  onEdit: Float32Array.t => unit,
  // called at the end of a stroke or operation
  onCommit: Float32Array.t => unit,
  // status text for point index, pointer value
  statusText: (t, int, float) => string,
}
// (see editItem and undoItem)
and menuItem = {label: string, run: t => unit}

let lo = t => t.bipolar ? -1. : 0.

let fixed4 = x => Float.toFixed(x, ~digits=4)

let defaultStatus = (t, i, v) =>
  `Point ${Int.toString(i + 1)} of ${Int.toString(t.n)}: ${fixed4(
      t.data->at(i),
    )}  (pointer at ${fixed4(v)})`

// point index, value and vertical fraction under the pointer
let valueAt = (t, ev) => {
  let (fx, fy) = t.canvas->pointerFraction(ev)
  let i = Int.clamp(Float.toInt(Math.round(fx * Int.toFloat(t.n - 1))), ~min=0, ~max=t.n - 1)
  let v = t.bipolar ? 1. - 2. * fy : 1. - fy
  (i, Float.clamp(v, ~min=lo(t), ~max=1.), fy)
}

let hoverStatus = (t, ev) => {
  let (i, v, _) = valueAt(t, ev)
  t.ctx.status->Status.show(t.statusText(t, i, v))
}

let draw = t => {
  open Context2d
  let g = t.g
  let (w, h) = CanvasStyle.paper(t.canvas, g)
  let grid = CanvasStyle.shade(0.18)
  let divs = Int.toFloat(t.gridDivs)
  for k in 1 to t.gridDivs - 1 {
    g->CanvasStyle.vline(h, Int.toFloat(k) * w / divs, grid)
  }
  for k in 1 to 3 {
    g->CanvasStyle.hline(w, Int.toFloat(k) * h / 4., t.bipolar && k == 2 ? CanvasStyle.shade(0.4) : grid)
  }
  let py = v => t.bipolar ? (0.5 - 0.5 * v) * (h - 8.) + 4. : (1. - v) * (h - 8.) + 4.
  let px = i => Int.toFloat(i) / Int.toFloat(t.n - 1) * (w - 1.)
  let base = py(0.)
  g->setFillStyle(CanvasStyle.tint(0.16))
  g->beginPath
  g->moveTo(px(0), base)
  for i in 0 to t.n - 1 {
    g->lineTo(px(i), py(t.data->at(i)))
  }
  g->lineTo(px(t.n - 1), base)
  g->closePath
  g->fill
  g->setStrokeStyle(CanvasStyle.ink)
  g->setLineWidth(2.4)
  g->beginPath
  for i in 0 to t.n - 1 {
    i == 0 ? g->moveTo(px(i), py(t.data->at(i))) : g->lineTo(px(i), py(t.data->at(i)))
  }
  g->stroke
  CanvasStyle.border(g, w, h)
}

// Changes the height of the drawing area (in design pixels).
let setHeight = (t, h) => {
  t.canvas->setStyle("height", px(h))
  t.canvas->setCanvasHeight(h * 2.)
}

let set = (t, data) => {
  t.data = TypedArray.copy(data)
  draw(t)
}

let pushUndo = t => {
  t.undoStack->Array.push(TypedArray.copy(t.data))
  if Array.length(t.undoStack) > 40 {
    t.undoStack->Array.shift->ignore
  }
}

let undo = t =>
  t.undoStack
  ->Array.pop
  ->Option.forEach(d => {
    t.data = d
    draw(t)
    t.onCommit(t.data)
  })

// Changes the data in one step that undo takes back, and commits it.
let apply = (t, f) => {
  pushUndo(t)
  f(t.data)
  draw(t)
  t.onCommit(t.data)
}

// Menu items: an operation on the data (one undoable step), and undo.
let editItem = (label, f) => {label, run: t => apply(t, f)}
let undoItem = {label: "undo", run: undo}

let line = (t, (i0, v0), (i1, v1)) => {
  let ((i0, v0), (i1, v1)) = i1 < i0 ? ((i1, v1), (i0, v0)) : ((i0, v0), (i1, v1))
  for i in i0 to i1 {
    t.data->setAt(i, i1 == i0 ? v1 : v0 + (v1 - v0) * Int.toFloat(i - i0) / Int.toFloat(i1 - i0))
  }
}

// waveforms and LFO shapes are periodic; the curves are not
let wrap = (t, j) =>
  if t.bipolar || t.n == 512 {
    Some(mod(mod(j, t.n) + t.n, t.n))
  } else if j < 0 || j >= t.n {
    None
  } else {
    Some(j)
  }

let smoothAt = (t, i, amount) => {
  let radius = Math.Int.max(1, Float.toInt(Math.round(amount * Int.toFloat(t.n) / 16.)))
  let src = TypedArray.copy(t.data)
  let weight = k => 1. - Int.toFloat(Math.Int.abs(k)) / Int.toFloat(radius + 1)
  for k in -radius to radius {
    let j = i + k
    if j >= 0 && j < t.n {
      let s = ref(0.)
      let w = ref(0.)
      for m in -radius to radius {
        wrap(t, j + m)->Option.forEach(q => {
          s := s.contents + src->at(q) * weight(m)
          w := w.contents + weight(m)
        })
      }
      let f = weight(k)
      t.data->setAt(j, src->at(j) * (1. - f) + s.contents / w.contents * f)
    }
  }
}

let onDown = (t, ev) =>
  if ev->button == 0 {
    ev->preventDefault
    pushUndo(t)
    let (i, v, _) = valueAt(t, ev)

    switch t.last {
    | Some((lastI, lastV)) if ev->shiftKey =>
      let v0 = ev->commandKey ? t.data->at(lastI) : lastV
      let v1 = ev->commandKey ? t.data->at(i) : v
      line(t, (lastI, v0), (i, v1))
      t.last = Some((i, v1))
      draw(t)
      t.onCommit(t.data)
    | _ =>
      let smoothing = ev->commandKey
      let previous = ref((i, v))
      let apply = (i, v, fy) => {
        if smoothing {
          smoothAt(t, i, 1. - fy)
        } else {
          line(t, previous.contents, (i, v))
        }
        previous := (i, v)
        t.last = Some((i, v))
        draw(t)
        t.onEdit(t.data)
      }
      apply(i, v, 0.)
      t.canvas->Controls.capturePointer(
        ev,
        ~onMove=mv => {
          let (i, v, fy) = valueAt(t, mv)
          apply(i, v, fy)
          hoverStatus(t, mv)
        },
        ~onUp=() => t.onCommit(t.data),
      )
    }
  }

// The menu, at the pointer.
let openMenu = (t, ev) => {
  let r = t.canvas->getBoundingClientRect
  let s = t.ctx.scale()
  t.canvas
  ->parentElement
  ->Option.forEach(parent =>
    t.ctx.menu->Menu.showAt(
      parent,
      ~x=t.box.x + (ev->clientX - r.left) / s,
      ~y=t.box.y + (ev->clientY - r.top) / s,
      t.menu->Array.mapWithIndex(({label}, value) => {Menu.label, value}),
      -1,
      k => t.menu[k]->Option.forEach(item => item.run(t)),
    )
  )
}

let make = (
  ctx: Ctx.t,
  parent,
  box,
  ~points,
  ~bipolar,
  ~grid=8,
  ~onEdit,
  ~onCommit,
  ~statusText=defaultStatus,
) => {
  let canvas = CanvasStyle.make(parent, box)
  let t = {
    ctx,
    box,
    n: points,
    bipolar,
    gridDivs: grid,
    data: Float32Array.fromLength(points),
    undoStack: [],
    menu: [],
    last: None,
    canvas,
    g: canvas->getContext2d,
    onEdit,
    onCommit,
    statusText,
  }
  canvas->onPointer(#pointerdown, ev => onDown(t, ev))
  canvas->onMouse(#contextmenu, ev => {
    ev->preventDefault
    openMenu(t, ev)
  })
  canvas->onMouse(#mousemove, ev => hoverStatus(t, ev))
  canvas->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  t
}

//==============================================================================
// Shape generators and operations shared by the editors

let sum = (d: Float32Array.t) => d->TypedArray.reduce((a, v) => a + v, 0.)

// Bipolar: remove DC and normalise the peak. Unipolar: stretch to 0..1.
let fix = (d: Float32Array.t, ~bipolar) =>
  if bipolar {
    let mean = sum(d) / Int.toFloat(TypedArray.length(d))
    let peak = ref(0.)
    d->TypedArray.forEachWithIndex((v, i) => {
      d->setAt(i, v - mean)
      peak := Math.max(peak.contents, Math.abs(d->at(i)))
    })
    if peak.contents > 0. {
      d->TypedArray.forEachWithIndex((v, i) => d->setAt(i, v / peak.contents))
    }
  } else {
    let lo = d->TypedArray.reduce((a, v) => Math.min(a, v), Float.Constants.positiveInfinity)
    let hi = d->TypedArray.reduce((a, v) => Math.max(a, v), Float.Constants.negativeInfinity)
    if hi > lo {
      d->TypedArray.forEachWithIndex((v, i) => d->setAt(i, (v - lo) / (hi - lo)))
    }
  }

let soften = (d: Float32Array.t, ~wrap=true) => {
  let s = TypedArray.copy(d)
  let n = TypedArray.length(d)
  for i in 0 to n - 1 {
    let a = wrap ? s->at(mod(i - 1 + n, n)) : s->at(Math.Int.max(0, i - 1))
    let b = wrap ? s->at(mod(i + 1, n)) : s->at(Math.Int.min(n - 1, i + 1))
    d->setAt(i, 0.25 * a + 0.5 * s->at(i) + 0.25 * b)
  }
}

let invert = (d: Float32Array.t, ~bipolar) =>
  d->TypedArray.forEachWithIndex((v, i) => d->setAt(i, bipolar ? -v : 1. - v))

let reverse = (d: Float32Array.t) => d->TypedArray.reverse

type generator = Sine | Saw | Square | Triangle | Random

let genWave = (kind, ~n=512) => {
  let d = Float32Array.fromLength(n)->TypedArray.mapWithIndex((_, i) => {
    let p = Int.toFloat(i) / Int.toFloat(n)
    switch kind {
    | Sine => Math.sin(2. * Math.Constants.pi * p)
    | Saw => 1. - 2. * p
    | Square => p < 0.5 ? 1. : -1.
    | Triangle => p < 0.25 ? 4. * p : p < 0.75 ? 2. - 4. * p : 4. * p - 4.
    | Random => 2. * Math.random() - 1.
    }
  })
  if kind == Random {
    for _ in 1 to 6 {
      soften(d)
    }
    fix(d, ~bipolar=true)
  }
  d
}

let genLfo = (kind, ~n=512) => genWave(kind, ~n)->TypedArray.map(w => 0.5 + 0.5 * w)
