// The source tray: every modulation source as a small chip, from a switch at the end of the
// status line, over the bottom of any page. Drag a chip onto a parameter to connect the source
// to it (at a quarter of its range); "vary per note" connects the random source a little, so
// that each note gets the parameter a bit differently. An alt-drag on the parameter then sets
// how much (Controls.paramControl).

open! Web

let varyAmount = 0.1

let make = (ctx: Ctx.t, stage) => {
  let model = ctx.model
  let tray = el("div", ~cls="mtray", ~parent=stage)
  let toggle = el("div", ~cls="mtoggle", ~text="mod sources", ~parent=stage)
  ctx.status->Status.hover(toggle, () => "Show the modulation sources, to drag onto any parameter")
  let shown = ref(false)
  toggle->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      shown := !shown.contents
      tray->toggleClass("on", shown.contents)
      toggle->toggleClass("on", shown.contents)
    }
  })

  let label = s =>
    switch ModMatrix.sources[s] {
    | Some({key}) if String.startsWith(key, "macro") => ModEdit.macroName(ctx.programs, s - ModMatrix.sourceIndex("macro1"))
    | _ => ModEdit.shortLabel(s)
    }
  let longLabel = s => ModMatrix.sources[s]->Option.mapOr("", s => s.label)

  let toStage = (cx, cy) => {
    let r = stage->getBoundingClientRect
    let s = ctx.scale()
    ((cx - r.left) / s, (cy - r.top) / s)
  }

  let drop = (source, amount, (d: ModEdit.dropTarget)) => {
    let name = (model->ParamModel.def(d.id)).name
    switch ModEdit.connect(model, source, d.target, ~amount) {
    | Ok(_) =>
      ctx.toast(
        amount == varyAmount
          ? `${name} now varies from note to note (alt-drag it to change how much)`
          : `${longLabel(source)} → ${name} (alt-drag it to change how much)`,
      )
    | Error(e) => ctx.toast(`${longLabel(source)} → ${name}: ${e}`)
    }
  }

  // a chip: its source, the amount it connects with, and its text
  let chip = (source, amount, text, ~cls="", ~help) => {
    let c = el("div", ~cls="mchip " ++ cls, ~parent=tray)
    el("i", ~parent=c)->setStyle("background", ModEdit.sourceColor(source))
    let t = el("span", ~text, ~parent=c)
    ctx.status->Status.hover(c, help)
    c->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->preventDefault
        let ghost = el("div", ~cls="mghost", ~text=amount == varyAmount ? "vary per note" : label(source), ~parent=stage)
        ghost->setStyle("borderColor", ModEdit.sourceColor(source))
        let hot = ref(None)
        let setHot = (d: option<ModEdit.dropTarget>) => {
          hot.contents->Option.forEach((h: ModEdit.dropTarget) => h.el->removeClass("dropping"))
          hot := d
          d->Option.forEach(d => d.el->addClass("dropping"))
        }
        let move = (cx, cy) => {
          let (x, y) = toStage(cx, cy)
          ghost->place(x + 8., y - 22.)->ignore
          setHot(ModEdit.dropTargetAt(cx, cy))
          ctx.status->Status.show(
            switch hot.contents {
            | Some(d) => `${longLabel(source)} → ${(model->ParamModel.def(d.id)).name}: let go to connect`
            | None => "Drop it on a parameter to modulate it"
            },
          )
        }
        move(ev->clientX, ev->clientY)
        c->Controls.capturePointer(
          ev,
          ~onMove=mv => move(mv->clientX, mv->clientY),
          ~onUp=() => {
            ghost->remove
            ctx.status->Status.clear
            let d = hot.contents
            setHot(None)
            d->Option.forEach(drop(source, amount, _))
          },
        )
      }
    )
    (c, t)
  }

  let random = ModMatrix.sourceIndex("random")
  chip(random, varyAmount, "vary per note", ~cls="vary", ~help=() =>
    "Drag onto a parameter to make each note get it a little differently (the random source, at 10 %)"
  )->ignore
  let chips = ModEdit.sourceOrder->Array.map(s => {
    let (_, t) = chip(s, ModEdit.defaultAmount, label(s), ~help=() => {
      let help = ModMatrix.sources[s]->Option.mapOr("", x => x.help)
      let scope = ModScope.scopeHelp(ModScope.sourceScopeOf(id => model->ParamModel.get(id), s))
      `${longLabel(s)} (${scope}): ${help}. Drag it onto a parameter.`
    })
    (s, t)
  })
  // the macros' names
  ctx.programs->ProgramStore.onChanged(() => chips->Array.forEach(((s, t)) => t->setTextContent(label(s))))
}
