// The FX page's routing tab: what isn't about one effect. The signal flow: in every voice, the
// oscillators, the filter and the places the distortion can sit; then, on the whole sound, the
// rack of effects in the order they run, each with its switch and level; and the output gain.
// Click a distortion place to put it there; drag a rack card sideways to move the effect, ×
// takes it out of the rack, right-click for more, and + adds one; click a card's name to open
// its tab.

open! Web

type ops = {
  rack: unit => array<FxRack.effect>,
  // moves an effect to this place among the others
  move: (FxRack.effect, int) => unit,
  add: FxRack.kind => unit,
  remove: FxRack.effect => unit,
  duplicate: FxRack.effect => unit,
  // switches it on or off
  toggle: FxRack.effect => unit,
  // the right-click menu of an effect, below an element
  menu: (FxRack.effect, element) => unit,
  // the menu of effects to add, below an element
  addMenu: element => unit,
  openEffect: FxRack.effect => unit,
  openDistortion: unit => unit,
}

let hint = "Click a dashed place to put the distortion there (right-click takes it out). Drag a rack card sideways to move that effect, × takes it out of the rack, right-click to duplicate it, + adds one; click a card's name to open it."

// the distortion's places: Sat_Mode's values
type place = Pre | Post | Global

let make = (ctx: Ctx.t, body, ops) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let def = id => model->ParamModel.def(id)
  let short = id => (def(id)).shortText(get(id))
  let w = Style.designWidth - 12.
  let h = Style.pageHeight - 6. - 34.
  let panel = Panel.make(body, ~title="signal flow", ~x=0., ~y=0., ~w, ~h)
  let root = panel.el
  let svg = Plots.svg(root, {x: 0., y: 0., w: w - 2., h: h - 2.})
  svg->setAttribute("class", Str("plot flowsvg"))
  let arrows = FxGraph.group(svg)
  let f = Float.toFixed(_, ~digits=1)

  let hover = (e, text) => {
    e->onMouse(#mouseenter, _ => ctx.status->Status.show(text()))
    e->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  }
  let label = (text, x, y) => el("div", ~cls="grp", ~text, ~parent=root)->place(x, y)->ignore
  let node = (text, x, y, w) => el("div", ~cls="fnode", ~text, ~parent=root)->place(x, y, ~w, ~h=30.)

  let nodeH = 30.
  let row1 = 52.
  let row2 = 136.
  let cardH = 150.
  let arrowY = row2 + nodeH / 2.
  let row3 = row2 + cardH + 36.

  // An arrow from (x0, y0) to (x1, y1), along the given corners.
  let arrow = (points: array<(float, float)>) => {
    let d = points->Array.mapWithIndex(((x, y), i) => (i == 0 ? "M" : "L") ++ f(x) ++ " " ++ f(y))->Array.join("")
    svgEl(arrows, "path", [("class", Str("flow")), ("d", Str(d))])->ignore
    switch (points[Array.length(points) - 2], points[Array.length(points) - 1]) {
    | (Some((px, py)), Some((x, y))) =>
      let (dx, dy) = (x - px, y - py)
      let len = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy))
      let (ux, uy) = (dx / len, dy / len)
      let s = 6.
      svgEl(
        arrows,
        "path",
        [
          ("class", Str("flowhead")),
          ("d", Str(`M${f(x - ux * s - uy * s * 0.6)} ${f(y - uy * s + ux * s * 0.6)}L${f(x)} ${f(y)}L${f(x - ux * s + uy * s * 0.6)} ${f(y - uy * s - ux * s * 0.6)}`)),
        ],
      )->ignore
    | _ => ()
    }
  }

  //==============================================================================
  // in every voice

  label("in every voice", 12., row1 - 22.)
  node("oscillators", 12., row1, 110.)->ignore
  node("filter", 316., row1, 110.)->ignore
  node("all voices", 620., row1, 110.)->ignore

  let typeId = "Sat_Type"
  let modeId = "Sat_Mode"
  let slot = (where, x, y) => {
    let e = el("div", ~cls="fslot", ~parent=root)->place(x, y, ~w=150., ~h=nodeH)
    e->onPointer(#pointerdown, ev => {
      ev->preventDefault
      let mode = switch where {
      | Pre => get(modeId) == 3. ? 3. : 2.
      | Post => 1.
      | Global => get(modeId) == 3. ? 3. : 0.
      }
      switch ev->button {
      | 0 =>
        if get(typeId) == 0. {
          model->ParamModel.gestureSet(typeId, 2.)
        }
        model->ParamModel.gestureSet(modeId, mode)
      | 2 => model->ParamModel.gestureSet(typeId, 0.)
      | _ => ()
      }
    })
    e->onMouse(#dblclick, _ => ops.openDistortion())
    e->suppressContextMenu
    hover(e, () =>
      switch where {
      | Pre => "Distortion in every voice, before the filter: click to put it here, double-click to open it, right-click to take it out"
      | Post => "Distortion in every voice, after the filter and amp envelope: click to put it here, double-click to open it, right-click to take it out"
      | Global => "Distortion on the whole sound, before the rack: click to put it here, double-click to open it, right-click to take it out"
      }
    )
    e
  }
  let pre = slot(Pre, 154., row1)
  let post = slot(Post, 458., row1)
  let global = slot(Global, 12., row2)

  let distortionControls = 762.
  Controls.choice(ctx, root, typeId, ~x=distortionControls, ~y=row1 + 2., ~w=150., ~label="distortion")
  Controls.choice(ctx, root, modeId, ~x=distortionControls + 156., ~y=row1 + 2., ~w=150., ~label="where")

  let drawSlots = () => {
    let on = get(typeId) != 0.
    let mode = Float.toInt(get(modeId))
    let typeName = short(typeId)
    [(pre, mode == 2 || mode == 3), (post, mode == 1), (global, mode == 0 || mode == 3)]->Array.forEach(((
      e,
      here,
    )) => {
      e->toggleClass("on", here && on)
      e->toggleClass("idle", here && !on)
      e->setTextContent(here ? (on ? "distortion: " ++ typeName : "distortion: off") : "")
    })
  }

  //==============================================================================
  // on the whole sound: the rack

  label("on the whole sound", 12., row2 - 22.)
  let rackX = 186.
  let addW = 30.
  let rackEnd = w - 14. - addW

  let summary = (e: FxRack.effect) => {
    let id = FxRack.id(e, ...)
    let s = x => short(id(x))
    switch e.kind {
    | #chorus => `${s("C_Voices")}, ${s("C_Rate")}\n${s("C_MinDelay")} + ${s("C_Depth")}`
    | #delay =>
      let n = x => Float.toString(Math.round(get(id(x)) * 100.) / 100.)
      let percent = x => Float.toFixed(get(id(x)) * 100., ~digits=0)
      `${n("D_LengthL")} / ${n("D_LengthR")} × ${s("D_Unit")}\nfeedback ${percent("D_FeedbackL")} / ${percent("D_FeedbackR")} %`
    | #reverb => `${s("R_Size")} room, ${s("R_Length")}\npredelay ${s("R_Predelay")}`
    | #eq =>
      switch FxRack.eqBandTypes(e)->Array.filter(i => get(i) != 0.)->Array.length {
      | 0 => "every band off"
      | 1 => "1 band on"
      | n => `${Int.toString(n)} bands on`
      }
    | #distortion => `pregain ${s("Sat_Pregain")}\nlimit ${s("Sat_Limit")}`
    }
  }

  // a card per effect, made when it first comes into the rack
  let cards = Map.make()
  let card = (e: FxRack.effect) =>
    switch cards->Map.get(FxRack.value(e)) {
    | Some(c) => c
    | None =>
      let id = FxRack.id(e, ...)
      let card = el("div", ~cls="card", ~parent=root)
      let head = el("div", ~cls="chead", ~parent=card)
      let led = el("i", ~cls="led", ~parent=head)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          ops.toggle(e)
        }
      )
      hover(led, () => "Click to switch it on or off")
      let title = el("span", ~cls="ctitle", ~parent=head)
      let x = el("b", ~cls="cx", ~text="×", ~parent=head)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        ops.remove(e)
      })
      hover(x, () => "Take it out of the rack (its settings stay)")
      hover(head, () =>
        `${FxRack.label(ops.rack(), e)} (${FxRack.hostName(e)}'s parameters): click to open it, drag sideways to move it, right-click to duplicate or remove it`
      )
      let controls = el("div", ~cls="cctl", ~parent=card)
      switch e.kind {
      | #chorus =>
        Controls.choice(ctx, controls, id("C_Mode"), ~x=0., ~y=0., ~label="mode")
        Controls.param(ctx, controls, id("C_Mix"), ~x=0., ~y=Grid.rowHeight, ~label="mix")
      | #delay =>
        Controls.toggle(ctx, controls, id("D_On"), ~x=0., ~y=0., ~w=100., ~label="on")
        Controls.param(ctx, controls, id("D_Wet"), ~x=0., ~y=Grid.rowHeight, ~label="wet")
      | #reverb =>
        Controls.toggle(ctx, controls, id("R_On"), ~x=0., ~y=0., ~w=100., ~label="on")
        Controls.param(ctx, controls, id("R_Wet"), ~x=0., ~y=Grid.rowHeight, ~label="wet")
      | #eq => Controls.toggle(ctx, controls, id("EQ_On"), ~x=0., ~y=0., ~w=100., ~label="on")
      | #distortion =>
        Controls.choice(ctx, controls, id("Sat_Type"), ~x=0., ~y=0., ~label="type")
        Controls.param(ctx, controls, id("Sat_Postgain"), ~x=0., ~y=Grid.rowHeight, ~label="postgain")
      }
      let sum = el("div", ~cls="csum", ~parent=card)
      head->onPointer(#pointerdown, ev =>
        switch ev->button {
        | 0 =>
          ev->preventDefault
          let others =
            ops.rack()
            ->Array.filter(o => o != e)
            ->Array.filterMap(o => cards->Map.get(FxRack.value(o))->Option.map(((c, _, _, _, _)) => c))
          Reorder.start(ev, card, ~others, ~onDrop=pos => ops.move(e, pos), ~onClick=() => ops.openEffect(e))
        | 2 =>
          ev->preventDefault
          ops.menu(e, head)
        | _ => ()
        }
      )
      head->suppressContextMenu
      let c = (card, title, led, controls, sum)
      cards->Map.set(FxRack.value(e), c)
      c
    }

  let addBox = el("div", ~cls="addcard", ~text="+", ~parent=root)
  hover(addBox, () => "Add an effect to the end of the rack: up to eight, each kind up to four times")

  let outputX = w - 14. - 300.
  let output = el("div", ~cls="fnode out", ~parent=root)->place(outputX, row3, ~w=210., ~h=58.)
  el("div", ~cls="olabel", ~text="output", ~parent=output)->ignore
  Controls.param(ctx, output, "Gain", ~x=6., ~y=24., ~w=196., ~label="gain")
  let outText = node("out", w - 14. - 64., row3 + 14., 64.)
  outText->addClass("end")

  addBox->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      ops.addMenu(addBox)
    }
  })

  let layout = () => {
    arrows->setTextContent("")
    let rack = ops.rack()
    let n = Array.length(rack)
    let gap = n > 6 ? 16. : 26.
    let space = rackEnd - gap - rackX
    let cardW = n == 0 ? 0. : Math.min(170., (space - Int.toFloat(n) * gap) / Int.toFloat(n))
    let compact = cardW < 80.
    cards->Map.forEach(((c, _, _, _, _)) => c->setStyle("display", "none"))
    rack->Array.forEachWithIndex((e, i) => {
      let (c, title, led, controls, sum) = card(e)
      let x = rackX + gap + Int.toFloat(i) * (cardW + gap)
      c->setStyle("display", "")
      c->place(x, row2, ~w=cardW, ~h=cardH)->ignore
      c->toggleClass("compact", compact)
      title->setTextContent(FxRack.label(rack, e))
      controls->querySelectorAll(".p, .tg")->nodesToArray->Array.forEach(c => c->setStyle("width", px(cardW - 12.)))
      let on = FxRack.isOn(e, get)
      led->toggleClass("lit", on)
      c->toggleClass("off", !on)
      sum->setTextContent(summary(e))
      arrow([(x - gap + 2., arrowY), (x - 1., arrowY)])
    })
    let end = rackX + gap + Int.toFloat(n) * (cardW + gap)
    let addX = Math.min(end, rackEnd)
    addBox->place(addX, row2, ~w=addW, ~h=nodeH)->ignore
    addBox->setStyle("display", FxRack.addable(rack) == [] ? "none" : "")
    // into the rack, through it, and down to the output
    arrow([(122., row1 + nodeH / 2.), (153., row1 + nodeH / 2.)])
    arrow([(304., row1 + nodeH / 2.), (315., row1 + nodeH / 2.)])
    arrow([(426., row1 + nodeH / 2.), (457., row1 + nodeH / 2.)])
    arrow([(608., row1 + nodeH / 2.), (619., row1 + nodeH / 2.)])
    arrow([(675., row1 + nodeH), (675., row1 + nodeH + 16.), (87., row1 + nodeH + 16.), (87., row2 - 1.)])
    if n == 0 {
      arrow([(162., arrowY), (addX - 1., arrowY)])
    } else {
      arrow([(162., arrowY), (rackX + gap - 1., arrowY)])
    }
    let outX = outputX + 105.
    let from = n == 0 ? addX + addW : end - gap
    arrow([(from, arrowY), (from + 10., arrowY), (from + 10., row2 + cardH + 18.), (outX, row2 + cardH + 18.), (outX, row3 - 1.)])
    arrow([(outputX + 210., row3 + 29.), (w - 14. - 65., row3 + 29.)])
    drawSlots()
  }

  el(
    "div",
    ~cls="note wrap",
    ~text="The distortion above is Oatmeal's: in every voice (before or after the filter), on the whole sound before the rack, or both (\"double\"). The rack holds up to eight effects in any order, each kind up to four times: the first chorus, delay, reverb and EQ are Oatmeal's, and an Oatmeal export keeps those in Oatmeal's order and leaves the rest out.",
    ~parent=root,
  )->place(12., row3 + 4., ~w=w - 14. - 320. - 24.)->ignore

  root->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  root->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  model->ParamModel.listenAny(_ => if root->offsetParent->Option.isSome {
      layout()
    })
  layout
}
