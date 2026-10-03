// Play page: what is played rather than edited. The macro knobs (named per program, with what
// each moves) and the arpeggiator across the top; the XY pad with its targets below, and beside
// it the patch summary (Summary: what the program is made of, each line a link to its editor),
// the pitch and mod wheels, and the MIDI input (MidiInput: MPE, the pedal, the controllers, the
// velocity and aftertouch maps, the channels).

open! Web

let hint = "Drag the XY pad; right-drag keeps its distance from the centre. Double-click a macro's name to rename it. Ctrl+right-click a control for its menu."

let margin = 6.
// the arpeggiator's steps and the length handle under them
let arpPatternHeight = 44.

//==============================================================================
// macros

let macros = (ctx: Ctx.t, page, ~x, ~y, ~w, ~h) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let panel = Panel.make(page, ~title="macros", ~x, ~y, ~w, ~h)
  let cw = Grid.fitColumns(w, 4)
  let g = Grid.make(ctx, panel.el, ~cw)
  // two a row, each with what it moves on a line under it
  let blockHeight = (h - Grid.padTop - Grid.padBottom) / 2.
  let names = Array.fromInitializer(~length=ModMatrix.macros, m => {
    let c = 2 * mod(m, 2)
    let top = Grid.padTop + Int.toFloat(m / 2) * blockHeight
    let name = ModEdit.macroName(ctx.programs, m)
    let knob = Controls.paramControl(
      ctx,
      panel.el,
      ModMatrix.macroId(m + 1),
      ~x=g->Grid.cx(c) + 1.,
      ~y=top,
      ~w=Grid.controlWidth(g, 2),
      ~label=name,
    )
    let label = knob->querySelector(".l")
    label->Option.forEach(l =>
      l->onMouse(#dblclick, ev => {
        ev->preventDefault
        ev->stopPropagation
        Controls.editInPlace(knob, (ctx.programs->ProgramStore.meta).macroNames[m]->Option.getOr(""), ~commit=name =>
          ctx.programs->ProgramStore.setMacroName(m, name)
        )
      })
    )
    let dest = el("div", ~cls="mdest", ~parent=panel.el)->place(
      g->Grid.cx(c) + 3.,
      top + Style.controlHeight + 1.,
      ~w=Grid.controlWidth(g, 2) - 4.,
    )
    (label, dest)
  })

  // what each macro moves: its connections in the matrix
  let source = m => ModMatrix.sourceIndex(`macro${Int.toString(m + 1)}`)
  let routes = m =>
    ModMatrix.slotNumbers->Array.filterMap(k => {
      let s = ModMatrix.readSlot(get, k)
      s.source == source(m) && s.target > 0
        ? ModMatrix.targets[s.target]->Option.map(t => (t.label, k))
        : None
    })
  let update = () =>
    names->Array.forEachWithIndex(((label, dest), m) => {
      label->Option.forEach(l => l->setTextContent(ModEdit.macroName(ctx.programs, m)))
      let r = routes(m)
      dest->setTextContent(r == [] ? "moves nothing yet" : "→ " ++ r->Array.map(((t, _)) => t)->Array.join(", "))
      dest->toggleClass("none", r == [])
    })
  names->Array.forEachWithIndex(((_, dest), m) => {
    ctx.status->Status.hover(dest, () =>
      switch routes(m) {
      | [] => `${ModEdit.macroName(ctx.programs, m)} moves nothing yet. Click to connect it on the Mod page, or drag it from the source tray (mod sources) onto a control.`
      | r =>
        let amount = k => (model->ParamModel.def(ModMatrix.amountId(k))).valueText(get(ModMatrix.amountId(k)))
        `${ModEdit.macroName(ctx.programs, m)} → ` ++
        r->Array.map(((t, k)) => `${t} ${amount(k)}`)->Array.join(", ") ++ ". Click to see them on the Mod page."
      }
    )
    dest->onMouse(#click, _ => ctx.openPage(#mod))
  })
  model->ParamModel.listenEach(ModMatrix.slotNumbers->Array.flatMap(k => [ModMatrix.sourceId(k), ModMatrix.targetId(k)]), update)
  ctx.programs->ProgramStore.onChanged(update)
  update()
}

//==============================================================================
// arpeggiator

let arpeggiator = (ctx: Ctx.t, page, ~x, ~y, ~w, ~h) => {
  let arp = Panel.make(page, ~title="arpeggiator", ~x, ~y, ~w, ~h)
  ArpPattern.make(ctx, arp.el, {x: 8., y: Grid.padTop, w: w - 18., h: 40.})
  let g = Grid.make(ctx, arp.el, ~y=Grid.padTop + arpPatternHeight, ~cw=Grid.fitColumns(w, 8))
  g->Grid.choice("Arp_Mode", 0, 0, "mode", ~span=2)
  g->Grid.choice("Arp_Unit", 2, 0, "unit", ~span=2)
  g->Grid.param("Arp_Step", 4, 0, "step")
  g->Grid.toggle("Arp_Quantize", 5, 0, "quantize")
  // the extra notes each pattern step plays, and their shifts: seven groups of three narrow
  // columns, a switch in one and the shift across the other two
  let notes = Grid.make(ctx, arp.el, ~y=g->Grid.cy(1), ~cw=Grid.fitColumns(w, 21))
  for k in 0 to 6 {
    let n = Int.toString(k + 1)
    notes->Grid.toggle(`Arp_Add_${n}_On`, 3 * k, 0, n)
    notes->Grid.param(`Arp_Add_${n}_Shift`, 3 * k + 1, 0, `note ${n}`, ~span=2)
  }
  // the rest recede while the mode is off
  let rest = arp.el->querySelectorAll(".p, .tg")->nodesToArray->Array.slice(~start=1)
  let dim = () => rest->Array.forEach(e => e->toggleClass("dim", ctx.model->ParamModel.get("Arp_Mode") == 0.))
  ctx.model->ParamModel.listenEach(["Arp_Mode"], dim)
  dim()
}

//==============================================================================
// the XY pad

let xy = (ctx: Ctx.t, page, ~x, ~y, ~w, ~h) => {
  let panel = Panel.make(page, ~title="xy", ~x, ~y, ~w, ~h)
  let side = h - Grid.padTop - 8.
  XyPad.make(ctx, panel.el, {x: 8., y: Grid.padTop, w: side, h: side})
  // its targets on the right: the x axis's, then the y axis's; its settings at the bottom
  let left = 8. + side + 12.
  let cw = (w - left - Grid.padX) / 3.
  let layoutRef = ref(() => ())
  let axis = (a, name) =>
    SlotRows.make(
      ctx,
      panel.el,
      Array.fromInitializer(~length=4, k => {
        let n = Int.toString(k + 1)
        (`XY_${a}_Target_${n}`, `XY_${a}_Depth_${n}`)
      }),
      ~x=left,
      ~cw,
      ~label=name ++ " target",
      ~onChange=() => layoutRef.contents(),
    )
  let xs = axis("H", "x")
  let ys = axis("V", "y")
  let layout = () => {
    xs.place(Grid.padTop)
    ys.place(Grid.padTop + Int.toFloat(xs.rows()) * Grid.rowHeight + 6.)
  }
  layoutRef := layout
  layout()

  let g = Grid.make(ctx, panel.el, ~x=left, ~y=h - Grid.padBottom - 2. * Grid.rowHeight + Style.controlGap, ~cw)
  g->Grid.param("XY_X", 0, 0, "x")
  g->Grid.param("XY_H_CC", 1, 0, "x cc")
  g->Grid.param("XY_Var_Radius", 2, 0, "rand radius")
  g->Grid.param("XY_Y", 0, 1, "y")
  g->Grid.param("XY_V_CC", 1, 1, "y cc")
  // (the wandering's rate, which does nothing while it has no radius)
  let rate = el("div", ~parent=panel.el)
  {...g, el: rate}->Grid.param("XY_Var_Rate", 2, 1, "rand rate")
  let showRate = () => rate->setStyle("display", ctx.model->ParamModel.get("XY_Var_Radius") > 0. ? "" : "none")
  ctx.model->ParamModel.listenEach(["XY_Var_Radius"], showRate)
  showRate()
}

let build = (ctx: Ctx.t, page) => {
  let width = Style.designWidth - 2. * margin
  // (the arpeggiator's pattern and two rows)
  let topHeight = Grid.padTop + arpPatternHeight + 2. * Grid.rowHeight + Grid.padBottom
  let macrosWidth = 354.
  macros(ctx, page, ~x=margin, ~y=margin, ~w=macrosWidth, ~h=topHeight)
  arpeggiator(ctx, page, ~x=margin + macrosWidth + Grid.gap, ~y=margin, ~w=width - macrosWidth - Grid.gap, ~h=topHeight)

  let y = margin + topHeight + Grid.gap
  let h = Style.pageHeight - margin - y
  let xyWidth = 594.
  xy(ctx, page, ~x=margin, ~y, ~w=xyWidth, ~h)

  // beside the pad, the patch summary (a line each); under it the pitch and mod wheels, and the
  // MIDI input
  let rightX = margin + xyWidth + Grid.gap
  let rightWidth = Style.designWidth - margin - rightX
  let summaryHeight = Grid.padTop + 5. * Summary.lineHeight + 8.
  Summary.make(ctx, page, ~x=rightX, ~y, ~w=rightWidth, ~h=summaryHeight)
  let y = y + summaryHeight + Grid.gap
  let h = h - summaryHeight - Grid.gap
  let wheelsWidth = 80.
  let wheels = Panel.make(page, ~title="wheels", ~x=rightX, ~y, ~w=wheelsWidth, ~h)
  Wheels.make(ctx, wheels.el, {x: 8., y: Grid.padTop, w: wheelsWidth - 18., h: h - Grid.padTop - 8.})

  let inputX = rightX + wheelsWidth + Grid.gap
  MidiInput.build(ctx, page, ~x=inputX, ~y, ~w=Style.designWidth - margin - inputX, ~h)
}
