// MIDI page: channel filter, sustain pedal, velocity/aftertouch curves and the six
// assignable controllers.

open! Web
open! Grid

let hint = "Right-click a curve for presets. Controller moves are smoothed over about 50 ms."

let linear = n =>
  Float32Array.fromLength(n)->TypedArray.mapWithIndex((_, i) => Int.toFloat(i) / Int.toFloat(n - 1))

let curveBlock = (ctx: Ctx.t, page, title, table, ~x, ~y, ~w, ~h) => {
  let b = Controls.block(page, title, ~x, ~y, ~w, ~h)
  let points = OatmealFormat.tableLength(table)
  let fixed2 = x => Float.toFixed(x, ~digits=2)
  let editor = ShapeEditor.make(
    ctx,
    b,
    {x: 10., y: 24., w: w - 20., h: h - 34.},
    ~points,
    ~bipolar=false,
    ~onEdit=d => ctx.programs->ProgramStore.setShape(table, d, ~commit=false),
    ~onCommit=d => ctx.programs->ProgramStore.setShape(table, d, ~commit=true),
    ~statusText=(e, i, _) =>
      `${title}: ${fixed2(100. * Int.toFloat(i) / Int.toFloat(points - 1))} % -> ${fixed2(
          100. * e.data->ByteView.getUnsafe(i),
        )} %`,
  )
  editor.menu = [
    {label: "linear", run: e => e.data->ShapeEditor.blit(linear(points))},
    {label: "soften", run: e => ShapeEditor.soften(e.data, ~wrap=false)},
    {
      label: "scale to the top",
      run: e => {
        let top =
          e.data->TypedArray.reduce((a, v) => Math.max(a, v), Float.Constants.negativeInfinity)
        if top > 0. {
          e.data->TypedArray.forEachWithIndex((v, i) => e.data->TypedArray.set(i, v / top))
        }
      },
    },
    {label: "fit top and bottom", run: e => ShapeEditor.fix(e.data, ~bipolar=false)},
    {label: "undo", run: ShapeEditor.undo},
  ]
  editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(table))
  ctx.programs->ProgramStore.onShapes(() =>
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(table))
  )
}

let build = (ctx: Ctx.t, page) => {
  let (x0, y0, w) = (6., 6., Style.designWidth - 12.)
  let pageHeight = Style.designHeight - 30.
  let setChannels = on =>
    for c in 1 to 16 {
      ctx.model->ParamModel.gestureSet("MIDI_Channel_" ++ Int.toString(c), on)
    }

  // channel strip
  let channels = Grid.make(ctx, page, "midi input", ~x=x0, ~y=y0, ~cols=16, ~rows=1, ~w, ~cw=46.)
  for c in 0 to 15 {
    channels->toggle("MIDI_Channel_" ++ Int.toString(c + 1), c, 0, Int.toString(c + 1))
  }
  let bx = channels->cx(16) + 12.
  let by = cy(0)
  Controls.button(
    ctx,
    channels.el,
    "all",
    ~x=bx,
    ~y=by + 3.,
    ~w=44.,
    ~status="Receive on every channel",
    () => setChannels(1.),
  )->ignore
  Controls.button(
    ctx,
    channels.el,
    "none",
    ~x=bx + 50.,
    ~y=by + 3.,
    ~w=44.,
    ~status="Ignore every channel",
    () => setChannels(0.),
  )->ignore
  Controls.toggle(
    ctx,
    channels.el,
    "SustainPedal",
    ~x=bx + 124.,
    ~y=by + 5.,
    ~label="use sustain pedal (cc 64)",
  )
  el("div", ~cls="note", ~text="channels", ~parent=channels.el)->place(10., 2.)->ignore

  // controllers: two rows of three along the bottom
  let ccW = (w - 2. * gap) / 3.
  let ccH = blockHeight(3)
  let yControllers = pageHeight - 2. * ccH - 2. * gap

  // curve editors fill the space between
  let y1 = channels->bottom
  let curveH = yControllers - gap - y1
  let curveW = (w - gap) / 2.
  curveBlock(ctx, page, "velocity map", VelocityCurve, ~x=x0, ~y=y1, ~w=curveW, ~h=curveH)
  curveBlock(
    ctx,
    page,
    "aftertouch map",
    AftertouchCurve,
    ~x=x0 + curveW + gap,
    ~y=y1,
    ~w=curveW,
    ~h=curveH,
  )

  for k in 0 to 5 {
    let n = "CC" ++ Int.toString(k + 1)
    let b = Grid.make(
      ctx,
      page,
      "cc " ++ Int.toString(k + 1),
      ~x=x0 + Int.toFloat(mod(k, 3)) * (ccW + gap),
      ~y=yControllers + Int.toFloat(k / 3) * (ccH + gap),
      ~cols=4,
      ~rows=3,
      ~w=ccW,
      ~cw=(ccW - 12.) / 4.,
    )
    b->param(n, 0, 0, "controller")
    b->button("learn", 1, 0, ~w=60., ~status="Move a controller to assign it", ~dy=4., () =>
      ctx.programs->ProgramStore.learn(n)
    )
    for t in 0 to 3 {
      let (c, r) = (mod(t, 2) * 2, 1 + t / 2)
      let slot = Int.toString(t + 1)
      b->choice(`${n}_Target_${slot}`, c, r, "target " ++ slot)
      b->param(`${n}_Depth_${slot}`, c + 1, r, "depth")
    }
  }
}
