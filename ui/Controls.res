// Panel controls. Every control is bound to one parameter id (the Cmajor endpoint id,
// which is the original skin's action name, e.g. "Cutoff" or "O1_Waveform").
// Values held by the model are *internal* values (the numbers stored in an Oatmeal
// preset); defs translate them to knob positions and to the original display text.

open! Web

let dragPixels = 220. // pixels of vertical travel for the full range
let fineShift = 0.1
let fineCtrl = 0.25

let clamp01 = x => Math.max(0., Math.min(1., x))

let block = (parent, title, ~x, ~y, ~w, ~h, ~titleLeft=false) => {
  let e = el("div", ~cls="blk", ~parent)->place(x, y, ~w, ~h)
  if title != "" {
    el("div", ~cls=titleLeft ? "ttl left" : "ttl", ~text=title, ~parent=e)->ignore
  }
  e
}

// Shared hover/drag/status handling
type control = {
  ctx: Ctx.t,
  id: string,
  def: ParamDefs.t,
  mutable hover: bool,
  mutable dragging: bool,
}

let control = (ctx: Ctx.t, id) => {
  ctx,
  id,
  def: ctx.model->ParamModel.def(id),
  hover: false,
  dragging: false,
}

let current = c => c.ctx.model->ParamModel.get(c.id)
let gestureSet = (c, x) => c.ctx.model->ParamModel.gestureSet(c.id, x)
let statusText = c => c.def.longText(current(c))

let refreshStatus = c =>
  if c.hover || c.dragging {
    c.ctx.status->Status.show(statusText(c))
  }

let hookStatus = (c, e) => {
  e->onMouse(#mouseenter, _ => {
    c.hover = true
    c.ctx.status->Status.show(statusText(c))
  })
  e->onMouse(#mouseleave, _ => {
    c.hover = false
    if !c.dragging {
      c.ctx.status->Status.clear
    }
  })
}

// Calls onMove for every move of a captured pointer, and onUp once it is released.
let capturePointer = (e, ev, ~onMove, ~onUp) => {
  e->setPointerCapture(ev->pointerId)
  let rec up = _ => {
    e->offPointer(#pointermove, onMove)
    e->offPointer(#pointerup, up)
    e->offPointer(#pointercancel, up)
    onUp()
  }
  e->onPointer(#pointermove, onMove)
  e->onPointer(#pointerup, up)
  e->onPointer(#pointercancel, up)
}

// Replaces e with a text field until Enter, Escape or blur; commit gets the text on Enter or blur.
let editInPlace = (e, text, ~commit) => {
  let input = el("input", ~cls="entry", ~parent=?e->parentElement)
  input->place(e->offsetLeft, e->offsetTop, ~w=e->offsetWidth, ~h=e->offsetHeight)->ignore
  input->setValue(text)
  input->select
  input->focus

  let finished = ref(false)
  let finish = ok =>
    if !finished.contents {
      finished := true
      if ok {
        commit(input->value)
      }
      input->remove
      e->focus
    }
  input->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Enter" => finish(true)
    | "Escape" => finish(false)
    | _ => ()
    }
  })
  input->onEvent(#blur, _ => finish(true))
}

// The knob range a parameter's modulation connections sweep, relative to its knob position
// (bipolar sources swing both ways), or None if nothing modulates it.
let modulationRange = (model, id) => {
  let target = ModMatrix.targetOfParam(id)
  if target < 0 {
    None
  } else {
    let get = id => model->ParamModel.get(id)
    let (lo, hi, any) = Array.fromInitializer(~length=ModMatrix.slots, i => i + 1)->Array.reduce(
      (0., 0., false),
      ((lo, hi, any), k) => {
        let source = ModMatrix.sources[Float.toInt(get(ModMatrix.sourceId(k)))]
        let amount = get(ModMatrix.amountId(k))
        switch source {
        | Some(source)
          if source.key != "none" && Float.toInt(get(ModMatrix.targetId(k))) == target && amount != 0. =>
          source.bipolar
            ? (lo - Math.abs(amount), hi + Math.abs(amount), true)
            : (lo + Math.min(amount, 0.), hi + Math.max(amount, 0.), true)
        | _ => (lo, hi, any)
        }
      },
    )
    any ? Some((lo, hi)) : None
  }
}

// A parameter row: label above-left, value right, position track underneath.
let paramControl = (ctx, parent, id, ~x, ~y, ~w=76., ~label=?) => {
  let c = control(ctx, id)
  let e = el("div", ~cls="p", ~parent)->place(x, y, ~w)
  e->setTabIndex(0)
  el("span", ~cls="l", ~text=label->Option.getOr(c.def.name), ~parent=e)->ignore
  let v = el("span", ~cls="v", ~parent=e)
  let track = el("span", ~cls="t", ~parent=e)
  let fill = el("i", ~parent=track)
  // the range modulation connections sweep, for parameters the matrix can reach
  let modBar = ModMatrix.targetOfParam(id) >= 0 ? Some(el("em", ~parent=track)) : None
  hookStatus(c, e)

  let update = () => {
    let x = current(c)
    v->setTextContent(c.def.shortText(x))
    let n = clamp01(c.def.toNorm(x))
    if c.def.bipolar {
      let (a, b) = (Math.min(n, 0.5), Math.max(n, 0.5))
      fill->setStyle("left", Float.toString(a * 100.) ++ "%")
      fill->setStyle(
        "width",
        b - a < 0.004 ? "1px" : Float.toString(Math.max(1., (b - a) * 100.)) ++ "%",
      )
    } else {
      fill->setStyle("left", "0")
      fill->setStyle("width", Float.toString(n * 100.) ++ "%")
    }
    modBar->Option.forEach(bar =>
      switch modulationRange(ctx.model, id) {
      | Some((lo, hi)) =>
        let (a, b) = (clamp01(n + lo), clamp01(n + hi))
        bar->setStyle("display", "block")
        bar->setStyle("left", Float.toString(a * 100.) ++ "%")
        bar->setStyle("width", Float.toString(Math.max(0.5, (b - a) * 100.)) ++ "%")
      | None => bar->setStyle("display", "none")
      }
    )
    refreshStatus(c)
  }

  let norm = () => c.def.toNorm(current(c))
  let setNorm = n => ctx.model->ParamModel.set(id, c.def.fromNorm(clamp01(n)))

  let edit = () =>
    editInPlace(e, c.def.shortText(current(c)), ~commit=text =>
      switch c.def.parse(text) {
      | Some(x) if Float.isFinite(x) => gestureSet(c, x)
      | _ => ()
      }
    )

  e->onPointer(#pointerdown, ev =>
    switch ev->button {
    | 2 =>
      gestureSet(c, c.def.init)
      ev->preventDefault
    | 1 =>
      gestureSet(c, c.def.fromNorm(0.5))
      ev->preventDefault
    | 0 =>
      ev->preventDefault
      c.dragging = true
      e->addClass("drag")
      ctx.model->ParamModel.beginGesture(id)

      let last = ref((ev->clientX, ev->clientY))
      let n = ref(norm())
      let scale = ctx.scale()
      e->capturePointer(
        ev,
        ~onMove=mv => {
          let (lastX, lastY) = last.contents
          let dy = (lastY - mv->clientY) / scale
          let dx = (mv->clientX - lastX) / scale
          last := (mv->clientX, mv->clientY)
          let d = (dy + dx * 0.35) / dragPixels
          let d = mv->shiftKey ? d * fineShift : d
          let d = mv->commandKey ? d * fineCtrl : d
          n := clamp01(n.contents + d)
          setNorm(n.contents)
        },
        ~onUp=() => {
          c.dragging = false
          e->removeClass("drag")
          ctx.model->ParamModel.endGesture(id)
          if !c.hover {
            ctx.status->Status.clear
          }
        },
      )
      refreshStatus(c)
    | _ => ()
    }
  )
  e->onWheel(ev => {
    ev->preventDefault
    let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
    let d = ev->shiftKey ? d * fineShift : d
    let n = norm()
    ctx.model->ParamModel.beginGesture(id)
    setNorm(n + d)
    ctx.model->ParamModel.endGesture(id)
  })
  e->onMouse(#dblclick, ev => {
    ev->preventDefault
    edit()
  })
  e->suppressContextMenu
  e->onKeyDown(ev => {
    let step = ev->shiftKey ? 0.001 : 0.01
    switch ev->key {
    | "ArrowUp" | "ArrowRight" =>
      setNorm(norm() + step)
      ev->preventDefault
    | "ArrowDown" | "ArrowLeft" =>
      setNorm(norm() - step)
      ev->preventDefault
    | "Enter" =>
      ev->preventDefault
      edit()
    | "Delete" | "Backspace" => gestureSet(c, c.def.init)
    | _ => ()
    }
  })

  ctx.model->ParamModel.listen(id, update)
  if modBar != None {
    Array.fromInitializer(~length=ModMatrix.slots, i => i + 1)->Array.forEach(k =>
      [ModMatrix.sourceId(k), ModMatrix.targetId(k), ModMatrix.amountId(k)]->Array.forEach(slotId =>
        ctx.model->ParamModel.listen(slotId, update)
      )
    )
  }
  update()
  e
}

let param = (ctx, parent, id, ~x, ~y, ~w=?, ~label=?) =>
  paramControl(ctx, parent, id, ~x, ~y, ~w?, ~label?)->ignore

let namesOf = (def: ParamDefs.t) =>
  switch def.names {
  | Some(names) => names
  | None => JsError.panic(def.id ++ " has no value names")
  }

// A choice: same footprint as a parameter row; click opens the menu, right click steps
// through the values (shift goes back).
let choice = (ctx: Ctx.t, parent, id, ~x, ~y, ~w=76., ~label=?, ~names=?) => {
  let c = control(ctx, id)
  let menuNames = namesOf(c.def)
  let names = names->Option.orElse(c.def.shortNames)->Option.getOr(menuNames)
  let count = Int.toFloat(Array.length(menuNames))
  let e = el("div", ~cls="p ch", ~parent)->place(x, y, ~w)
  e->setTabIndex(0)
  el("span", ~cls="l", ~text=label->Option.getOr(c.def.name), ~parent=e)->ignore
  let v = el("span", ~cls="v", ~parent=e)
  hookStatus(c, e)

  let update = () => {
    let x = current(c)
    v->setTextContent(names[Float.toInt(x)]->Option.getOr(Float.toString(x)))
    refreshStatus(c)
  }

  let step = d => gestureSet(c, Float.mod(Float.mod(current(c) + d, count) + count, count))

  let openMenu = () =>
    ctx.menu->Menu.show(
      e,
      menuNames->Array.mapWithIndex((label, value) => {Menu.label, value}),
      Float.toInt(current(c)),
      i => gestureSet(c, Int.toFloat(i)),
    )

  e->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 1 => gestureSet(c, 0.)
    | 0 if ev->commandKey => gestureSet(c, 0.)
    | 0 => openMenu()
    | 2 => step(ev->shiftKey ? -1. : 1.)
    | _ => ()
    }
  })
  e->suppressContextMenu
  e->onWheel(ev => {
    ev->preventDefault
    step(ev->deltaY < 0. ? -1. : 1.)
  })
  e->onKeyDown(ev =>
    switch ev->key {
    | "ArrowUp" | "ArrowLeft" =>
      step(-1.)
      ev->preventDefault
    | "ArrowDown" | "ArrowRight" | " " =>
      step(1.)
      ev->preventDefault
    | "Enter" => openMenu()
    | _ => ()
    }
  )

  ctx.model->ParamModel.listen(id, update)
  update()
}

// An on/off box with a label.
let toggle = (ctx: Ctx.t, parent, id, ~x, ~y, ~label=?) => {
  let c = control(ctx, id)
  let e = el("div", ~cls="tg", ~parent)->place(x, y)
  e->setTabIndex(0)
  el("b", ~parent=e)->ignore
  el("span", ~text=label->Option.getOr(c.def.name), ~parent=e)->ignore
  hookStatus(c, e)

  let flip = () => gestureSet(c, current(c) != 0. ? 0. : 1.)
  let update = () => {
    e->toggleClass("on", current(c) != 0.)
    refreshStatus(c)
  }

  e->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 0 => flip()
    | 1 | 2 => gestureSet(c, 0.)
    | _ => ()
    }
  })
  e->suppressContextMenu
  e->onKeyDown(ev =>
    switch ev->key {
    | " " | "Enter" =>
      flip()
      ev->preventDefault
    | _ => ()
    }
  )

  ctx.model->ParamModel.listen(id, update)
  update()
}

let button = (ctx: Ctx.t, parent, text, ~x, ~y, ~w, ~status=?, onClick) => {
  let e = el("button", ~cls="btn", ~text, ~parent)->place(x, y, ~w)
  e->onMouse(#click, _ => onClick())
  status->Option.forEach(status => {
    e->onMouse(#mouseenter, _ => ctx.status->Status.show(status))
    e->onMouse(#mouseleave, _ => ctx.status->Status.clear)
  })
  e
}

// The corner switch of a graphical editor: swaps the graph for the raw values by toggling
// the editor's "expanded" class.
let expandSwitch = (ctx: Ctx.t, editor) => {
  let e = el("button", ~cls="btn xbtn", ~text="values", ~parent=editor)
  let expanded = ref(false)
  e->onMouse(#click, _ => {
    expanded := !expanded.contents
    editor->toggleClass("expanded", expanded.contents)
    e->setTextContent(expanded.contents ? "graph" : "values")
  })
  e->onMouse(#mouseenter, _ => ctx.status->Status.show("Switch between the graph and the raw values"))
  e->onMouse(#mouseleave, _ => ctx.status->Status.clear)
}
