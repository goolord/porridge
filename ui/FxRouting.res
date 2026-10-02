// The FX page's routing tab: what isn't about one effect. The signal flow: in every voice, the
// oscillators, the voice lane's effects (VoiceLane) around the filter (with the places
// Oatmeal's distortion can sit) and the amp envelope; then, on the whole sound, the rack of
// effects in the order they run, each with its switch and level; and the output gain. Click a
// distortion place to put it there; drag a voice card, the filter or the amp sideways to move
// it in the voice, or a rack card along the rack; × takes an effect out, right-click for more
// (moving it between the voices and the whole sound), and + adds one; click a card's name to
// open its tab.

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

let hint = "Click a dashed place to put the distortion there (right-click takes it out). Drag a card, the filter or the amp sideways to move it, × takes an effect out, right-click to duplicate it or move it between the voices and the whole sound, + adds one; click a card's name to open it."

// the distortion's places: Sat_Mode's values
type place = Pre | Post | Global

let make = (ctx: Ctx.t, body, ~w, ~h, ops) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let panel = Panel.make(body, ~title="signal flow", ~x=0., ~y=0., ~w, ~h)
  let root = panel.el
  let svg = Plots.svg(root, {x: 0., y: 0., w: w - 2., h: h - 2.})
  svg->setAttribute("class", Str("plot flowsvg"))
  let arrows = FxGraph.group(svg)
  let f = Float.toFixed(_, ~digits=1)

  let hover = (e, text) => ctx.status->Status.hover(e, text)
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

  label("per-voice: each voice runs its own", 12., row1 - 22.)
  node("oscillators", 12., row1, 86.)->ignore
  let filterNode = node("filter", 0., row1, 72.)
  let ampNode = node("amp", 0., row1, 60.)
  let allNode = node("all voices", 0., row1, 86.)
  filterNode->addClass("grab")
  ampNode->addClass("grab")
  hover(filterNode, () => "The filter, with the places the distortion can sit either side: drag it sideways among the voice's effects")
  hover(ampNode, () =>
    "The amp envelope: drag it sideways. The voice's effects after it react to how each note swells and fades, and ring on after the note ends; those before it are shaped by it"
  )

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
  let pre = slot(Pre, 0., row1)
  let post = slot(Post, 0., row1)
  let global = slot(Global, 12., row2)
  [pre, post]->Array.forEach(e => e->setStyle("width", px(96.)))

  Controls.choice(ctx, root, typeId, ~x=12., ~y=row3, ~w=150., ~label="distortion")
  Controls.choice(ctx, root, modeId, ~x=168., ~y=row3, ~w=150., ~label="where")

  //==============================================================================
  // the voice lane's cards: a light, the name and ×, made when an effect first comes into it

  let laneCards = Map.make()
  let laneCard = (e: FxRack.effect) =>
    switch laneCards->Map.get(FxRack.value(e)) {
    | Some(c) => c
    | None =>
      let card = el("div", ~cls="lcard", ~parent=root)
      let led = el("i", ~cls="led", ~parent=card)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          ops.toggle(e)
        }
      )
      hover(led, () => "Click to switch it on or off")
      let title = el("span", ~cls="ctitle", ~parent=card)
      let x = el("b", ~cls="cx", ~text="×", ~parent=card)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        VoiceLane.remove(model, e)
      })
      hover(x, () => "Take it out of the voices (its settings stay)")
      hover(card, () =>
        `${VoiceLane.label(model, e)} in every voice (${FxRack.hostName(e)}'s parameters): ${FxPanels.summary(model, e)->String.replaceAll("\n", ", ")}. Click to open it, drag sideways to move it, right-click to duplicate it or move it to the whole sound`
      )
      card->suppressContextMenu
      let c = (card, title, led)
      laneCards->Map.set(FxRack.value(e), c)
      c
    }

  let laneAdd = el("div", ~cls="addcard", ~text="+", ~parent=root)
  hover(laneAdd, () => "Add a per-voice effect (up to four): each voice runs its own copy")
  laneAdd->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      VoiceLane.addMenu(ctx, laneAdd, ~onAdded=ops.openEffect)
    }
  })

  // the element a lane item is dragged by
  let itemEl = (item: VoiceLane.item) =>
    switch item {
    | Fx(e) =>
      let (c, _, _) = laneCard(e)
      c
    | FilterNode => filterNode
    | AmpNode => ampNode
    }
  let pressItem = (item: VoiceLane.item, ev) =>
    switch ev->button {
    | 0 =>
      ev->preventDefault
      let items = VoiceLane.items(get)
      let others = items->Array.filter(o => o != item)->Array.map(itemEl)
      Reorder.start(ev, itemEl(item), ~others, ~onDrop=pos => VoiceLane.move(model, item, pos), ~onClick=() =>
        switch item {
        | Fx(e) => ops.openEffect(e)
        | _ => ()
        }
      )
    | 2 =>
      switch item {
      | Fx(e) =>
        ev->preventDefault
        VoiceLane.menu(ctx, e, itemEl(item))
      | _ => ()
      }
    | _ => ()
    }
  filterNode->onPointer(#pointerdown, ev => pressItem(FilterNode, ev))
  ampNode->onPointer(#pointerdown, ev => pressItem(AmpNode, ev))
  let laneHooked = Set.make()

  // Lays out the voice row from the lane's items; returns where it ends (the "all voices" node).
  let layoutVoices = () => {
    let gap = 12.
    let y = row1 + nodeH / 2.
    let x = ref(12. + 86.)
    let step = (e, w) => {
      arrow([(x.contents, y), (x.contents + gap - 1., y)])
      e->place(x.contents + gap, row1, ~w, ~h=nodeH)->ignore
      x := x.contents + gap + w
    }
    laneCards->Map.forEach(((c, _, _)) => c->setStyle("display", "none"))
    let lane = FxRack.readLane(get)
    VoiceLane.items(get)->Array.forEach(item =>
      switch item {
      | Fx(e) =>
        let (c, title, led) = laneCard(e)
        if !(laneHooked->Set.has(FxRack.value(e))) {
          laneHooked->Set.add(FxRack.value(e))
          c->onPointer(#pointerdown, ev => pressItem(Fx(e), ev))
        }
        c->setStyle("display", "")
        title->setTextContent(FxRack.label(lane, e))
        let on = FxRack.isOn(e, get)
        led->toggleClass("lit", on)
        c->toggleClass("off", !on)
        step(c, 100.)
      | FilterNode =>
        step(pre, 96.)
        step(filterNode, 72.)
        step(post, 96.)
      | AmpNode => step(ampNode, 60.)
      }
    )
    let full = FxRack.laneFull(lane)
    laneAdd->setStyle("display", full ? "none" : "")
    if !full {
      laneAdd->place(x.contents + gap, row1, ~w=28., ~h=nodeH)->ignore
      x := x.contents + gap + 28.
    }
    step(allNode, 86.)
    x.contents - 43.
  }

  let drawSlots = () => {
    let on = get(typeId) != 0.
    let mode = Float.toInt(get(modeId))
    let typeName = model->ParamModel.shortText(typeId)
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

  // a card per effect, made when it first comes into the rack
  let cards = Map.make()
  let card = (e: FxRack.effect) =>
    switch cards->Map.get(FxRack.value(e)) {
    | Some(c) => c
    | None =>
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
      // the switch (a list, for those that are off at its first value), and the level
      let (label, level) = FxPanels.cardControls(e.kind)
      let on = FxRack.switchId(e)
      if Array.length(Controls.namesOf(model->ParamModel.def(on))) > 2 {
        Controls.choice(ctx, controls, on, ~x=0., ~y=0., ~label)
      } else {
        Controls.toggle(ctx, controls, on, ~x=0., ~y=0., ~w=100., ~label)
      }
      level->Option.forEach(((level, label)) =>
        Controls.param(ctx, controls, FxRack.id(e, level), ~x=0., ~y=Grid.rowHeight, ~label)
      )
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
      sum->setTextContent(FxPanels.summary(model, e))
      arrow([(x - gap + 2., arrowY), (x - 1., arrowY)])
    })
    let end = rackX + gap + Int.toFloat(n) * (cardW + gap)
    let addX = Math.min(end, rackEnd)
    addBox->place(addX, row2, ~w=addW, ~h=nodeH)->ignore
    addBox->setStyle("display", FxRack.addable(rack, ~lane=FxRack.readLane(get)) == [] ? "none" : "")
    // through the voice, into the rack, through it, and down to the output
    let allX = layoutVoices()
    arrow([(allX, row1 + nodeH), (allX, row1 + nodeH + 16.), (87., row1 + nodeH + 16.), (87., row2 - 1.)])
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
    ~text="The distortion's places are Oatmeal's: in every voice (before or after the filter), on the whole sound before the rack, or both (\"double\"). Each voice can also run up to four effects of its own (the filter, distortion, EQ, phaser, flanger and utility, and the key shifter and resonator, which follow each note's pitch). The rack holds up to eight effects on the whole sound, each kind up to four times: the first chorus, delay, reverb and EQ are Oatmeal's, and an Oatmeal export keeps those in Oatmeal's order and leaves the rest out.",
    ~parent=root,
  )->place(12., row3 + 34., ~w=w - 14. - 320. - 24.)->ignore

  hover(root, () => hint)
  let layoutSoon = perFrame(() => if root->offsetParent->Option.isSome {
      layout()
    })
  model->ParamModel.listenAny(_ => layoutSoon())
  layout
}
