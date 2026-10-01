// Arpeggiator pattern: 16 step cells, each showing its command as an icon (Icons.arpStep),
// and a pattern-length handle.
// Click a step to pick its command from the list, right-click to advance it, shift-right-click
// to go back.

open! Web

let stepId = i => "Arp_P" ++ Int.toString(i, ~radix=16)->String.toUpperCase

let make = (ctx: Ctx.t, parent, box) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let cw = Math.floor(box.w / 16.)
  let hoverId = ref(None)
  let railHover = ref(false)

  let status = id => ctx.status->Status.show(model->ParamModel.longText(id))

  let menuItems = id => () =>
    Controls.namesOf(model->ParamModel.def(id))->Array.mapWithIndex((name, value) =>
      switch Icons.arpStep(value) {
      | Some(icon) => {Menu.label: name, value, icon}
      | None => {Menu.label: name, value}
      }
    )

  let cells = Array.fromInitializer(~length=16, i => {
    let id = stepId(i)
    let c =
      el("div", ~cls="cell", ~parent)->place(box.x + Int.toFloat(i) * cw, box.y, ~w=cw - 2., ~h=24.)
    c->setTabIndex(0)
    ctx.hostMenu->HostMenu.attach(model, c, id)
    Controls.listInput(ctx, c, id, ~items=menuItems(id), ~upIsNext=true)->ignore
    c->onMouse(#mouseenter, _ => {
      hoverId := Some(id)
      status(id)
    })
    c->onMouse(#mouseleave, _ => {
      hoverId := None
      ctx.status->Status.clear
    })
    c
  })

  // length handle: a thin rail under the cells
  let rail = el("div", ~cls="draw", ~parent)->place(box.x, box.y + 27., ~w=16. * cw - 2., ~h=12.)
  rail->setStyle("border-bottom", "1px solid var(--edge)")
  let handle = el("div", ~parent=rail)
  handle
  ->style
  ->setCssText(
    "position:absolute;top:2px;width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;border-bottom:8px solid var(--signal)",
  )

  let draw = () => {
    let last = get("Arp_End")
    cells->Array.forEachWithIndex((c, i) => {
      let v = get(stepId(i))
      c->setTextContent("")
      switch Icons.arpStep(Float.toInt(v)) {
      | Some(icon) => c->appendChild(icon)
      | None => c->setTextContent("?")
      }
      c->toggleClass("off", v == 0.)
      c->toggleClass("out", Int.toFloat(i) > last)
    })
    handle->setStyle("left", px(last * cw + cw / 2. - 7.))
    hoverId.contents->Option.forEach(status)
    if railHover.contents {
      status("Arp_End")
    }
  }

  rail->onPointer(#pointerdown, ev => {
    ev->preventDefault
    model->ParamModel.beginGesture("Arp_End")
    let set = ev => {
      let (fx, _) = rail->pointerFraction(ev)
      model->ParamModel.set("Arp_End", Float.clamp(Math.floor(fx * 16.), ~min=0., ~max=15.))
      status("Arp_End")
    }
    set(ev)
    rail->Controls.capturePointer(
      ev,
      ~onMove=set,
      ~onUp=() => model->ParamModel.endGesture("Arp_End"),
    )
  })
  rail->onMouse(#mouseenter, _ => {
    railHover := true
    status("Arp_End")
  })
  rail->onMouse(#mouseleave, _ => {
    railHover := false
    ctx.status->Status.clear
  })

  Array.fromInitializer(~length=16, stepId)->Array.forEach(id => model->ParamModel.listen(id, draw))
  model->ParamModel.listen("Arp_End", draw)
  draw()
}
