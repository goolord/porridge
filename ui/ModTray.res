// The source tray: every modulation source as a small chip, from a switch at the end of the
// status line, over the bottom of any page. Drag a chip onto a parameter to connect the source
// to it (at a quarter of its range; the tray hides while a chip is dragged, so that it covers
// none of them); "vary per note" connects the random source a little, so
// that each note gets the parameter a bit differently. An alt-drag on the parameter then sets
// how much (Controls.paramControl). Click a chip to select its source (ModFocus): what it moves
// lights up on every page.

open! Web

let varyAmount = 0.1

let make = (ctx: Ctx.t, stage) => {
  let model = ctx.model
  let tray = el("div", ~cls="mtray", ~parent=stage)
  let toggle = el("div", ~cls="mtoggle", ~text="mod sources", ~parent=stage)
  ctx.status->Status.hover(toggle, () => "Show the modulation sources, to drag onto any parameter or to see what they move")
  let shown = ref(false)
  toggle->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      shown := !shown.contents
      tray->toggleClass("on", shown.contents)
      toggle->toggleClass("on", shown.contents)
    }
  })

  let name = s => ModEdit.sourceName(ctx.programs, s)

  let toStage = (cx, cy) => {
    let r = stage->getBoundingClientRect
    let s = ctx.scale()
    ((cx - r.left) / s, (cy - r.top) / s)
  }

  let drop = (source, amount, (d: ModEdit.dropTarget)) => {
    let target = (ModMatrix.targets->Array.getUnsafe(d.target)).label
    let route = `${name(source)} → ${target}`
    switch ModEdit.connect(model, source, d.target, ~amount) {
    | Ok(_) =>
      model->ParamModel.nameStep(route)
      ctx.toast(
        amount == varyAmount
          ? `${target} now varies from note to note (alt-drag it to change how much)`
          : `${route} (alt-drag it to change how much)`,
      )
    | Error(e) => ctx.toast(`${route}: ${e}`)
    }
  }

  // a chip: its source, the amount it connects with, and its text; a click (rather than a drag)
  // calls onClick
  let chip = (source, amount, text, ~cls="", ~help, ~onClick) => {
    let c = el("div", ~cls="mchip " ++ cls, ~parent=tray)
    el("i", ~parent=c)->setStyle("background", ModEdit.sourceColor(source))
    let t = el("span", ~text, ~parent=c)
    ctx.status->Status.hover(c, help)
    c->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->preventDefault
        let ghost = el("div", ~cls="mghost", ~text=amount == varyAmount ? "vary per note" : name(source), ~parent=stage)
        ghost->setStyle("borderColor", ModEdit.sourceColor(source))
        ghost->setStyle("display", "none")
        let (x0, y0) = (ev->clientX, ev->clientY)
        let moved = ref(false)
        let hot = ref(None)
        let setHot = (d: option<ModEdit.dropTarget>) => {
          hot.contents->Option.forEach((h: ModEdit.dropTarget) => h.el->removeClass("dropping"))
          hot := d
          d->Option.forEach(d => d.el->addClass("dropping"))
        }
        let move = (cx, cy) => {
          if !moved.contents && Math.hypot(cx - x0, cy - y0) > 4. {
            moved := true
            ghost->setStyle("display", "")
            // out of the way of the parameters under it
            tray->addClass("dragging")
          }
          let (x, y) = toStage(cx, cy)
          ghost->place(x + 8., y - 22.)->ignore
          setHot(ModEdit.dropTargetAt(cx, cy))
          if moved.contents {
            ctx.status->Status.show(
              switch hot.contents {
              | Some(d) => `${name(source)} → ${(ModMatrix.targets->Array.getUnsafe(d.target)).label}: let go to connect`
              | None => "Drop it on a parameter to modulate it"
              },
            )
          }
        }
        move(ev->clientX, ev->clientY)
        c->Controls.capturePointer(
          ev,
          ~onMove=mv => move(mv->clientX, mv->clientY),
          ~onUp=() => {
            ghost->remove
            tray->removeClass("dragging")
            ctx.status->Status.clear
            let d = hot.contents
            setHot(None)
            if moved.contents {
              d->Option.forEach(drop(source, amount, _))
            } else {
              onClick()
            }
          },
        )
      }
    )
    (c, t)
  }

  let random = ModMatrix.sourceIndex("random")
  chip(random, varyAmount, "vary per note", ~cls="vary", ~onClick=() => (), ~help=() =>
    "Drag onto a parameter to make each note get it a little differently (the random source, at 10 %)"
  )->ignore
  let chips = ModEdit.sourceOrder->Array.map(s => {
    let key = (ModMatrix.sources->Array.getUnsafe(s)).key
    let (c, t) = chip(
      s,
      ModEdit.defaultAmount,
      name(s),
      ~onClick=() => ModFocus.toggle(model, key),
      ~help=() => {
        let help = ModMatrix.sources[s]->Option.mapOr("", x => x.help)
        let scope = ModScope.scopeHelp(ModScope.sourceScopeOf(id => model->ParamModel.get(id), s))
        `${name(s)} (${scope}): ${help}. Drag it onto a parameter, or click it to see what it moves.`
      },
    )
    (s, c, t)
  })
  // the macros' names, and the selected source
  ctx.programs->ProgramStore.onChanged(() => chips->Array.forEach(((s, _, t)) => t->setTextContent(name(s))))
  ModFocus.watch(model, () => {
    let selected = ModFocus.current(model)
    chips->Array.forEach(((s, c, _)) =>
      c->toggleClass("sel", selected == ModMatrix.sources[s]->Option.map(x => x.key))
    )
  })
}
