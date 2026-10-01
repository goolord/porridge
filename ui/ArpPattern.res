// Arpeggiator pattern: 16 step cells and a pattern-length handle.
// Click a step to advance its command, shift-click to go back, right-click for the list.

open! Web

// short glyphs for the 16 step commands, in the synth's order
let glyphs = [
  "·",
  "↑",
  "↑|",
  "↓",
  "↓|",
  "↕",
  "↕|",
  "=",
  "→",
  "↔",
  "⤺",
  "⤺↑",
  "⤺↓",
  "⊤",
  "⊥",
  "?",
]

let stepId = i => "Arp_P" ++ Int.toString(i, ~radix=16)->String.toUpperCase

let make = (ctx: Ctx.t, parent, box) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let cw = Math.floor(box.w / 16.)
  let hoverId = ref(None)
  let railHover = ref(false)

  let status = id => ctx.status->Status.show((model->ParamModel.def(id)).longText(get(id)))

  let step = (id, d) => model->ParamModel.gestureSet(id, Float.mod(get(id) + d + 16., 16.))

  let menu = (anchor, id) =>
    ctx.menu->Menu.show(
      anchor,
      Controls.namesOf(model->ParamModel.def(id))->Array.mapWithIndex((name, value) => {
        Menu.label: glyphs->Array.getUnsafe(value) ++ "  " ++ name,
        value,
      }),
      Float.toInt(get(id)),
      v => model->ParamModel.gestureSet(id, Int.toFloat(v)),
    )

  let cells = Array.fromInitializer(~length=16, i => {
    let id = stepId(i)
    let c =
      el("div", ~cls="cell", ~parent)->place(box.x + Int.toFloat(i) * cw, box.y, ~w=cw - 2., ~h=24.)
    c->setTabIndex(0)
    c->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 2 => menu(c, id)
      | 1 => model->ParamModel.gestureSet(id, 0.)
      | 0 if ev->commandKey => model->ParamModel.gestureSet(id, 0.)
      | 0 => step(id, ev->shiftKey ? -1. : 1.)
      | _ => ()
      }
    })
    c->suppressContextMenu
    c->onMouse(#mouseenter, _ => {
      hoverId := Some(id)
      status(id)
    })
    c->onMouse(#mouseleave, _ => {
      hoverId := None
      ctx.status->Status.clear
    })
    c->onKeyDown(ev =>
      switch ev->key {
      | "ArrowUp" | " " =>
        step(id, 1.)
        ev->preventDefault
      | "ArrowDown" =>
        step(id, -1.)
        ev->preventDefault
      | "Enter" => menu(c, id)
      | _ => ()
      }
    )
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
      c->setTextContent(glyphs[Float.toInt(v)]->Option.getOr("?"))
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
    let set = cx => {
      let r = rail->getBoundingClientRect
      let n = Math.max(0., Math.min(15., Math.floor((cx - r.left) / r.width * 16.)))
      model->ParamModel.set("Arp_End", n)
      status("Arp_End")
    }
    set(ev->clientX)
    rail->Controls.capturePointer(
      ev,
      ~onMove=mv => set(mv->clientX),
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
