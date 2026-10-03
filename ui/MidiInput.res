// The Play page's MIDI input panel: MPE, the sustain pedal and the assignable controllers in use
// (of six), each with the targets it moves; the velocity and aftertouch maps and the channels a program
// listens on, which few programs change, are on tabs of their own.

open! Web

let linear = n =>
  Float32Array.fromLength(n)->TypedArray.mapWithIndex((_, i) => Int.toFloat(i) / Int.toFloat(n - 1))

let isLinear = (data: Float32Array.t) => {
  let n = TypedArray.length(data)
  data->TypedArray.everyWithIndex((v, i) => Math.abs(v - Int.toFloat(i) / Int.toFloat(n - 1)) < 1e-4)
}

let curveEditor = (ctx: Ctx.t, parent, title, table, box: box) => {
  let points = OatmealFormat.tableLength(table)
  let fixed2 = x => Float.toFixed(x, ~digits=2)
  let editor = ShapeEditor.make(
    ctx,
    parent,
    box,
    ~points,
    ~bipolar=false,
    ~onEdit=d => ctx.programs->ProgramStore.setShape(table, d, ~commit=false),
    ~onCommit=d => ctx.programs->ProgramStore.setShape(table, d, ~commit=true),
    ~statusText=(e, i, _) =>
      `${title}: ${fixed2(100. * Int.toFloat(i) / Int.toFloat(points - 1))} % -> ${fixed2(
          100. * e.data->ByteView.getUnsafe(i),
        )} %. Right-click for presets.`,
  )
  editor.menu = [
    ShapeEditor.editItem("linear", d => d->ShapeEditor.blit(linear(points))),
    ShapeEditor.editItem("soften", d => ShapeEditor.soften(d, ~wrap=false)),
    ShapeEditor.editItem("scale to the top", d => {
      let top = d->TypedArray.reduce((a, v) => Math.max(a, v), Float.Constants.negativeInfinity)
      if top > 0. {
        d->TypedArray.forEachWithIndex((v, i) => d->TypedArray.set(i, v / top))
      }
    }),
    ShapeEditor.editItem("fit top and bottom", d => ShapeEditor.fix(d, ~bipolar=false)),
    ShapeEditor.undoItem,
  ]
  editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(table))
  ctx.programs->ProgramStore.onShapes(() =>
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(table))
  )
  el("div", ~cls="hlabel", ~text=title, ~parent)->place(box.x + 4., box.y + 3.)->ignore
}

let mpeHelp = "MPE: channel 1 is the master channel. A note on channels 2-16 gets that channel's pitch bend (note bend sets its range), pressure (as aftertouch, when touch isn't ignored) and slide (CC 74, a modulation source). The channel switches don't apply."

let build = (ctx: Ctx.t, parent, ~x, ~y, ~w, ~h) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let panel = Panel.make(parent, ~tabs=["midi in", "curves", "channels"], ~x, ~y, ~w, ~h)
  // (leaving the controllers' list room for its scroll bar)
  let cw = Grid.fitColumns(w - 6., 4)

  //==============================================================================
  // midi in: MPE, the pedal, the controllers

  let body = panel->Panel.body(0)
  let g = Grid.make(ctx, body, ~cw)
  g->Grid.at(0, 0, "MPE_On", b => {
    let size = Style.controlHeight
    Controls.toggle(ctx, body, "MPE_On", ~x=b.x, ~y=b.y, ~w=b.w - size - Grid.columnGap, ~label="MPE")
    Controls.help(body, mpeHelp, ~x=b.x + b.w - size, ~y=b.y, ~size, ~tipW=Grid.controlWidth(g, 3))
  })
  g->Grid.param("MPE_BendRange", 1, 0, "note bend")
  g->Grid.toggle("SustainPedal", 2, 0, "sustain pedal (cc 64)", ~span=2)

  // the controllers scroll under the first row when their targets don't fit
  let listTop = g->Grid.cy(1)
  let list = el("div", ~cls="slist", ~parent=body)->place(0., listTop, ~w=w - 2., ~h=h - listTop - 2.)
  let ccRows = Array.fromInitializer(~length=6, k => {
    let n = "CC" ++ Int.toString(k + 1)
    let head = el("div", ~cls="srow", ~parent=list)
    Controls.param(ctx, head, n, ~x=0., ~y=0., ~w=cw - Grid.columnGap, ~label="controller " ++ Int.toString(k + 1))
    Controls.button(ctx, head, "learn", ~x=cw, ~y=0., ~w=cw - Grid.columnGap, ~status="Move a controller to assign it", () =>
      ctx.programs->ProgramStore.learn(n)
    )->ignore
    let layoutRef = ref(() => ())
    let targets = SlotRows.make(
      ctx,
      list,
      Array.fromInitializer(~length=4, t => {
        let slot = Int.toString(t + 1)
        (`${n}_Target_${slot}`, `${n}_Depth_${slot}`)
      }),
      ~x=Grid.padX + cw,
      ~cw,
      ~label="target",
      ~addAt=(head, {x: 2. * cw, y: 0., w: 2. * cw - Grid.columnGap, h: Style.controlHeight}),
      ~onChange=() => layoutRef.contents(),
    )
    (head, targets, layoutRef)
  })
  // The controllers in use (a number set, or a target), and those "+ controller" showed since the
  // program changed: six rows of "---" say nothing.
  let ccIds = Array.fromInitializer(~length=6, k => "CC" ++ Int.toString(k + 1))
  let added = Set.make()
  let isShown = k => {
    let (_, targets: SlotRows.t, _) = ccRows->Array.getUnsafe(k)
    added->Set.has(k) || get(ccIds->Array.getUnsafe(k)) != 0. || targets.rows() > 0
  }
  let addLayout = ref(() => ())
  let addController = Controls.button(ctx, list, "+ controller", ~x=Grid.padX, ~y=0., ~w=2. * cw - Grid.columnGap, ~cls="add", () =>
    switch Array.fromInitializer(~length=6, k => k)->Array.find(k => !isShown(k)) {
    | Some(k) =>
      added->Set.add(k)
      addLayout.contents()
    | None => ()
    }
  )
  ctx.status->Status.hover(addController, () =>
    "Add an assignable controller: set its number, or click learn and move it, then pick what it moves"
  )
  // a controller's row with its "+ target" button, then the targets it moves; "+ controller" after
  // them while one is free
  let layoutControllers = () => {
    let y = ref(0.)
    ccRows->Array.forEachWithIndex(((head, targets: SlotRows.t, _), k) =>
      if isShown(k) {
        head->setStyle("display", "")
        head->place(Grid.padX, y.contents)->ignore
        targets.place(y.contents + Grid.rowHeight)
        y := y.contents + Int.toFloat(1 + targets.rows()) * Grid.rowHeight
      } else {
        head->setStyle("display", "none")
        // (which hides its rows: it has none in use)
        targets.place(0.)
      }
    )
    let free = Array.fromInitializer(~length=6, k => k)->Array.some(k => !isShown(k))
    addController->setStyle("display", free ? "" : "none")
    addController->setStyle("top", px(y.contents))
  }
  addLayout := layoutControllers
  ccRows->Array.forEach(((_, _, layoutRef)) => layoutRef := layoutControllers)
  model->ParamModel.listenEach(ccIds, layoutControllers)
  ctx.programs->ProgramStore.onChanged(() => {
    added->Set.clear
    layoutControllers()
  })
  layoutControllers()

  //==============================================================================
  // curves

  let curves = panel->Panel.body(1)
  let curveW = (w - 2. * Grid.padX - Grid.gap) / 2.
  let curveBox = i => {x: Grid.padX + Int.toFloat(i) * (curveW + Grid.gap), y: Grid.padTop, w: curveW, h: h - Grid.padTop - Grid.padBottom}
  curveEditor(ctx, curves, "velocity", VelocityCurve, curveBox(0))
  curveEditor(ctx, curves, "aftertouch", AftertouchCurve, curveBox(1))

  //==============================================================================
  // channels

  let channels = panel->Panel.body(2)
  let c = Grid.make(ctx, channels, ~cw)
  for ch in 0 to 15 {
    let id = "MIDI_Channel_" ++ Int.toString(ch + 1)
    c->Grid.toggle(id, mod(ch, 4), ch / 4, "channel " ++ Int.toString(ch + 1))
  }
  let setChannels = on => {
    for ch in 1 to 16 {
      model->ParamModel.gestureSet("MIDI_Channel_" ++ Int.toString(ch), on)
    }
    model->ParamModel.nameStep(on == 1. ? "every channel" : "no channel")
  }
  c->Grid.button("all", 0, 4, ~status="Receive on every channel", () => setChannels(1.))
  c->Grid.button("none", 1, 4, ~status="Ignore every channel", () => setChannels(0.))

  // the tabs say when what's on them isn't as an Init program has it
  let channelIds = Array.fromInitializer(~length=16, ch => "MIDI_Channel_" ++ Int.toString(ch + 1))
  let mark = () => {
    let curved =
      [OatmealFormat.VelocityCurve, AftertouchCurve]->Array.some(t => !isLinear(ctx.programs->ProgramStore.shape(t)))
    panel.tabs[1]->Option.forEach(tab => tab->toggleClass("mark", curved))
    panel.tabs[2]->Option.forEach(tab => tab->toggleClass("mark", channelIds->Array.some(id => get(id) == 0.)))
  }
  model->ParamModel.listenEach(channelIds, mark)
  ctx.programs->ProgramStore.onShapes(mark)
  mark()
}
