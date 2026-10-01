// MIDI page: channel filter, sustain pedal, velocity/aftertouch curves and the six
// assignable controllers.

open! Web

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
    {x: 10., y: 25., w: w - 22., h: h - 35.},
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
  let setChannels = on =>
    for c in 1 to 16 {
      ctx.model->ParamModel.gestureSet("MIDI_Channel_" ++ Int.toString(c), on)
    }

  // channel strip
  let channels = Panel.make(page, ~title="midi input", ~x=x0, ~y=y0, ~w, ~h=Grid.panelHeight(1))
  let g = Grid.make(ctx, channels.el, ~cw=46.)
  for c in 0 to 15 {
    g->Grid.toggle("MIDI_Channel_" ++ Int.toString(c + 1), c, 0, Int.toString(c + 1))
  }
  let bx = g->Grid.cx(16) + 12.
  let by = g->Grid.cy(0)
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

  // controllers: two rows of three along the bottom
  let ccW = (w - 2. * Grid.gap) / 3.
  let ccH = Grid.panelHeight(3)
  let yControllers = Style.pageHeight - y0 - 2. * ccH - Grid.gap

  // curve editors fill the space between
  let y1 = channels->Panel.bottom
  let curveH = yControllers - Grid.gap - y1
  let curveW = (w - Grid.gap) / 2.
  curveBlock(ctx, page, "velocity map", VelocityCurve, ~x=x0, ~y=y1, ~w=curveW, ~h=curveH)
  curveBlock(
    ctx,
    page,
    "aftertouch map",
    AftertouchCurve,
    ~x=x0 + curveW + Grid.gap,
    ~y=y1,
    ~w=curveW,
    ~h=curveH,
  )

  for k in 0 to 5 {
    let n = "CC" ++ Int.toString(k + 1)
    let p = Panel.make(
      page,
      ~title="cc " ++ Int.toString(k + 1),
      ~x=x0 + Int.toFloat(mod(k, 3)) * (ccW + Grid.gap),
      ~y=yControllers + Int.toFloat(k / 3) * (ccH + Grid.gap),
      ~w=ccW,
      ~h=ccH,
    )
    let b = Grid.make(ctx, p.el, ~cw=(ccW - 12.) / 4.)
    b->Grid.param(n, 0, 0, "controller")
    b->Grid.button("learn", 1, 0, ~w=60., ~status="Move a controller to assign it", ~dy=4., () =>
      ctx.programs->ProgramStore.learn(n)
    )
    for t in 0 to 3 {
      let (c, r) = (mod(t, 2) * 2, 1 + t / 2)
      let slot = Int.toString(t + 1)
      b->Grid.choice(`${n}_Target_${slot}`, c, r, "target " ++ slot)
      b->Grid.param(`${n}_Depth_${slot}`, c + 1, r, "depth")
    }
  }
}
