// The order of the effects after the distortion, as a chain of chips in a panel's title
// row: drag a chip and drop it where it should go, right-click to go back to Oatmeal's order (chorus,
// delay, reverb, EQ). The order is one parameter, FX_Order, an index into every
// permutation (PorridgeParams.fxOrder).

open! Web

let id = "FX_Order"
let hint = "Effects order: drag an effect and drop it where it should go in the chain, right-click for Oatmeal's order (chorus, delay, reverb, EQ)."

let make = (ctx: Ctx.t, panel: Panel.t) => {
  let model = ctx.model
  let root = el("div", ~cls="fxorder", ~parent=panel.el)
  el("span", ~cls="lbl", ~text="order: dist", ~parent=root)->ignore
  let chips = PorridgeParams.fxNames->Array.map(name => el("span", ~cls="chip", ~text=name))
  let seps = PorridgeParams.fxNames->Array.map(_ => el("span", ~cls="arrow", ~text="›"))
  let order = () => PorridgeParams.fxOrder(Float.toInt(model->ParamModel.get(id)))

  // appending moves the chips into chain order
  let draw = () =>
    order()->Array.forEachWithIndex((fx, pos) => {
      seps[pos]->Option.forEach(sep => root->appendChild(sep))
      chips[fx]->Option.forEach(chip => root->appendChild(chip))
    })

  let clearMarks = () =>
    chips->Array.forEach(c => {
      c->toggleClass("drop-before", false)
      c->toggleClass("drop-after", false)
    })

  // Drag and drop: the chip follows the pointer, a mark shows where it will land, and the
  // order changes when it's dropped.
  chips->Array.forEachWithIndex((chip, fx) => {
    chip->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 2 => model->ParamModel.gestureSet(id, 0.)
      | 0 =>
        let startX = ev->clientX
        // css pixels per screen pixel (the view is scaled to the window)
        let k = chip->offsetWidth / (chip->getBoundingClientRect).width
        let others = order()->Array.filter(f => f != fx)
        let centre = f =>
          chips[f]->Option.mapOr(0., c => {
            let r = c->getBoundingClientRect
            r.left + r.width / 2.
          })
        // where the chip lands among the others: before the first whose middle is right of x
        let landing = x => others->Array.filter(f => centre(f) < x)->Array.length
        let target = ref(None)
        chip->toggleClass("drag", true)
        chip->Controls.capturePointer(
          ev,
          ~onMove=mv => {
            let x = mv->clientX
            chip->setStyle("transform", `translateX(${Float.toString((x - startX) * k)}px)`)
            let pos = landing(x)
            target := Some(pos)
            clearMarks()
            switch (others[pos], others[pos - 1]) {
            | (Some(f), _) => chips[f]->Option.forEach(c => c->toggleClass("drop-before", true))
            | (None, Some(f)) => chips[f]->Option.forEach(c => c->toggleClass("drop-after", true))
            | _ => ()
            }
          },
          ~onUp=() => {
            chip->toggleClass("drag", false)
            chip->setStyle("transform", "")
            clearMarks()
            target.contents->Option.forEach(pos => {
              let o = others->Array.copy
              o->Array.splice(~start=pos, ~remove=0, ~insert=[fx])
              model->ParamModel.gestureSet(id, Int.toFloat(PorridgeParams.fxOrderIndex(o)))
            })
          },
        )
      | _ => ()
      }
    })
  })

  root->suppressContextMenu
  root->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
  root->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  model->ParamModel.listen(id, draw)
  draw()
}
