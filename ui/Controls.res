// Panel controls. Every control is bound to one parameter id (the Cmajor endpoint id,
// which is the original skin's action name, e.g. "Cutoff" or "O1_Waveform").
// Values held by the model are *internal* values (the numbers stored in an Oatmeal
// preset); defs translate them to knob positions and to the original display text.

open! Web

let dragPixels = 220. // pixels of vertical travel for the full range
let fineShift = 0.1
let fineCtrl = 0.25

let clamp01 = x => Float.clamp(x, ~min=0., ~max=1.)

let block = (parent, title, ~x, ~y, ~w, ~h) => {
  let e = el("div", ~cls="blk", ~parent)->place(x, y, ~w, ~h)
  if title != "" {
    el("div", ~cls="ttl", ~text=title, ~parent=e)->ignore
  }
  e
}

// A control: its parameter, and the status text it shows while hovered or dragged
type control = {
  ctx: Ctx.t,
  id: string,
  def: ParamDefs.t,
  status: Status.live,
}

let current = c => c.ctx.model->ParamModel.get(c.id)
let gestureSet = (c, x) => c.ctx.model->ParamModel.gestureSet(c.id, x)
let refreshStatus = c => c.status.refresh()

// A double right-click opens the host's menu for the parameter (see HostMenu). Hook it before
// the control's own pointer handlers.
let hookHostMenu = (c, e) => c.ctx.hostMenu->HostMenu.attach(c.ctx.model, e, c.id)

// A control's element: focusable, with its label (after an on/off box, with ~box), showing the
// parameter's status text while hovered, and the host's menu on a double right-click.
let frame = (ctx: Ctx.t, parent, id, ~cls, ~x, ~y, ~w=?, ~label=?, ~labelCls=?, ~box=false) => {
  let e = el("div", ~cls, ~parent)->place(x, y, ~w?)
  let def = ctx.model->ParamModel.def(id)
  let c = {ctx, id, def, status: ctx.status->Status.live(e, () => def.longText(ctx.model->ParamModel.get(id)))}
  e->setTabIndex(0)
  if box {
    el("b", ~parent=e)->ignore
  }
  el("span", ~cls=?labelCls, ~text=label->Option.getOr(c.def.name), ~parent=e)->ignore
  hookHostMenu(c, e)
  (c, e)
}

// Runs update now and whenever the control's parameter changes.
let bind = (c, update) => {
  c.ctx.model->ParamModel.listen(c.id, update)
  update()
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

// Captures the pointer, and calls onMove with how far each move went (right and down, in
// design pixels), and onUp once it is released.
let dragBy = (ctx: Ctx.t, e, ev, ~onMove, ~onUp) => {
  let scale = ctx.scale()
  let last = ref((ev->clientX, ev->clientY))
  e->capturePointer(
    ev,
    ~onMove=mv => {
      let (lastX, lastY) = last.contents
      last := (mv->clientX, mv->clientY)
      onMove((mv->clientX - lastX) / scale, (mv->clientY - lastY) / scale, mv)
    },
    ~onUp,
  )
}

// Scrolling over a parameter: a hundredth of its knob a notch, shift for a tenth of that.
let wheelParam = (model, id, ev) => {
  ev->preventDefault
  let def = model->ParamModel.def(id)
  let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
  let d = ev->shiftKey ? d * fineShift : d
  model->ParamModel.gestureSet(id, def.fromNorm(clamp01(def.toNorm(model->ParamModel.get(id)) + d)))
}

// Replaces e with a text field until Enter, Escape or blur; commit gets the text on Enter or blur.
// The field goes into e's parent, or over e inside ~within.
let editInPlace = (e, text, ~commit, ~maxLength=?, ~within=?) => {
  let input = el("input", ~cls="entry", ~parent=?within->Option.orElse(e->parentElement))
  let (x, y) = switch within {
  | Some(ancestor) => e->offsetWithin(ancestor)
  | None => (e->offsetLeft, e->offsetTop)
  }
  input->place(x, y, ~w=e->offsetWidth, ~h=e->offsetHeight)->ignore
  maxLength->Option.forEach(n => input->setMaxLength(n))
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

// The knob range the modulation connections to a target sweep, relative to its knob position
// (bipolar sources swing both ways), or None if nothing modulates it.
let modulationRange = (model, target) => {
  let (lo, hi, any) = ModMatrix.slotNumbers->Array.reduce((0., 0., false), ((lo, hi, any), k) => {
    let slot = ModMatrix.readSlot(ParamModel.get(model, _), k)
    let amount = slot.amount
    switch ModMatrix.sources[slot.source] {
    | Some(source) if source.key != "none" && slot.target == target && amount != 0. =>
      source.bipolar
        ? (lo - Math.abs(amount), hi + Math.abs(amount), true)
        : (lo + Math.min(amount, 0.), hi + Math.max(amount, 0.), true)
    | _ => (lo, hi, any)
    }
  })
  any ? Some((lo, hi)) : None
}

// The modulation bars of a model's parameter rows, redrawn together (once a frame) when a
// slot changes: one listener per slot parameter rather than one per row.
let modBars: WeakMap.t<ParamModel.t, array<unit => unit>> = WeakMap.make()

let onSlotChange = (model, refresh) =>
  switch modBars->WeakMap.get(model) {
  | Some(refreshers) => refreshers->Array.push(refresh)
  | None =>
    let refreshers = [refresh]
    modBars->WeakMap.set(model, refreshers)->ignore
    let refreshAll = perFrame(() => refreshers->Array.forEach(f => f()))
    ModMatrix.slotNumbers->Array.forEach(k => model->ParamModel.listenEach(ModMatrix.slotIds(k), refreshAll))
  }

// A parameter row: label above-left, value right, position track underneath.
let paramControl = (ctx, parent, id, ~x, ~y, ~w=76., ~label=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="p", ~x, ~y, ~w, ~label?, ~labelCls="l")
  let v = el("span", ~cls="v", ~parent=e)
  let track = el("span", ~cls="t", ~parent=e)
  let fill = el("i", ~parent=track)
  // the range modulation connections sweep, for parameters the matrix can reach
  let target = ModMatrix.targetOfParam(id)
  let modBar = target >= 0 ? Some(el("em", ~parent=track)) : None

  let norm = () => c.def.toNorm(current(c))
  let setNorm = n => ctx.model->ParamModel.set(id, c.def.fromNorm(clamp01(n)))

  let updateModBar = () =>
    modBar->Option.forEach(bar =>
      switch modulationRange(ctx.model, target) {
      | Some((lo, hi)) =>
        let n = clamp01(norm())
        let (a, b) = (clamp01(n + lo), clamp01(n + hi))
        bar->setStyle("display", "block")
        bar->setStyle("left", Float.toString(a * 100.) ++ "%")
        bar->setStyle("width", Float.toString(Math.max(0.5, (b - a) * 100.)) ++ "%")
      | None => bar->setStyle("display", "none")
      }
    )

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
    updateModBar()
    refreshStatus(c)
  }

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
      c.status.setDragging(true)
      e->addClass("drag")
      ctx.model->ParamModel.beginGesture(id)

      let n = ref(norm())
      dragBy(
        ctx,
        e,
        ev,
        ~onMove=(dx, dy, mv) => {
          let d = (dx * 0.35 - dy) / dragPixels
          let d = mv->shiftKey ? d * fineShift : d
          let d = mv->commandKey ? d * fineCtrl : d
          n := clamp01(n.contents + d)
          setNorm(n.contents)
        },
        ~onUp=() => {
          c.status.setDragging(false)
          e->removeClass("drag")
          ctx.model->ParamModel.endGesture(id)
        },
      )
      refreshStatus(c)
    | _ => ()
    }
  )
  e->onWheel(ev => wheelParam(ctx.model, id, ev))
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

  if modBar != None {
    onSlotChange(ctx.model, updateModBar)
  }
  bind(c, update)
  e
}

let param = (ctx, parent, id, ~x, ~y, ~w=?, ~label=?) =>
  paramControl(ctx, parent, id, ~x, ~y, ~w?, ~label?)->ignore

let namesOf = (def: ParamDefs.t) =>
  switch def.names {
  | Some(names) => names
  | None => JsError.panic(def.id ++ " has no value names")
  }

// What the element of a list parameter does: a click opens the menu of items(), a right
// click steps through the values (shift goes back), a middle or ctrl click picks the first.
// Space and the arrow keys step (up goes back, unless upIsNext), Enter opens the menu.
// Returns the step function.
let listInput = (ctx: Ctx.t, e, id, ~items, ~upIsNext=false) => {
  let model = ctx.model
  let count = Int.toFloat(Array.length(namesOf(model->ParamModel.def(id))))
  let current = () => model->ParamModel.get(id)
  let set = x => model->ParamModel.gestureSet(id, x)
  let step = d => set(Float.mod(Float.mod(current() + d, count) + count, count))
  let openMenu = () =>
    ctx.menu->Menu.show(e, items(), Float.toInt(current()), i => set(Int.toFloat(i)))

  e->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 1 => set(0.)
    | 0 if ev->commandKey => set(0.)
    | 0 => openMenu()
    | 2 => step(ev->shiftKey ? -1. : 1.)
    | _ => ()
    }
  })
  e->suppressContextMenu
  let up = upIsNext ? 1. : -1.
  e->onKeyDown(ev => {
    let move = d => {
      step(d)
      ev->preventDefault
    }
    switch ev->key {
    | "ArrowUp" => move(up)
    | "ArrowDown" => move(-.up)
    | "ArrowLeft" if !upIsNext => move(-1.)
    | "ArrowRight" if !upIsNext => move(1.)
    | " " => move(1.)
    | "Enter" => openMenu()
    | _ => ()
    }
  })
  step
}

// A choice: same footprint as a parameter row; click opens the menu, right click steps
// through the values (shift goes back).
let choice = (ctx: Ctx.t, parent, id, ~x, ~y, ~w=76., ~label=?, ~names=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="p ch", ~x, ~y, ~w, ~label?, ~labelCls="l")
  let menuNames = namesOf(c.def)
  let names = names->Option.orElse(c.def.shortNames)->Option.getOr(menuNames)
  let withIcons = Icons.has(id)
  let v = el("span", ~cls=withIcons ? "v withicon" : "v", ~parent=e)
  let icon = value => Icons.forValue(id, value, menuNames[value]->Option.getOr(""))

  let update = () => {
    let x = current(c)
    let i = Float.toInt(x)
    let text = names[i]->Option.getOr(Float.toString(x))
    switch withIcons ? icon(i) : None {
    | Some((mark, _)) =>
      // the short name, less what the icon shows (e.g. "HQ")
      let text = String.endsWith(text, " HQ") ? String.slice(text, ~start=0, ~end=String.length(text) - 3) : text
      v->setTextContent("")
      v->appendChild(mark)
      el("span", ~text, ~parent=v)->ignore
    | None => v->setTextContent(text)
    }
    refreshStatus(c)
  }

  // the filter types' menus show their groups
  let isFilterType = id == "Filter" || id == "Filter2" || FilterTypes.isFxType(id)
  let heading = value => isFilterType && value > 0 ? FilterTypes.heading(value) : None
  let step = listInput(ctx, e, id, ~items=() =>
    menuNames->Array.mapWithIndex((label, value) =>
      switch withIcons ? icon(value) : None {
      | Some((icon, label)) => {Menu.label, value, icon, heading: ?heading(value)}
      | None => {Menu.label, value, heading: ?heading(value)}
      }
    )
  )
  e->onWheel(ev => {
    ev->preventDefault
    step(ev->deltaY < 0. ? -1. : 1.)
  })
  bind(c, update)
}

// An on/off box with a label. With a width, it fills it (as in a grid cell); without, it
// is as wide as its label.
let toggle = (ctx: Ctx.t, parent, id, ~x, ~y, ~w=?, ~label=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="tg", ~x, ~y, ~w?, ~label?, ~box=true)

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
  e->onActivate(flip)
  bind(c, update)
}

let button = (ctx: Ctx.t, parent, text, ~x, ~y, ~w, ~h=?, ~cls="", ~status=?, onClick) => {
  let e = el("button", ~cls=cls == "" ? "btn" : "btn " ++ cls, ~text, ~parent)->place(x, y, ~w, ~h?)
  e->onMouse(#click, _ => onClick())
  status->Option.forEach(status => ctx.status->Status.hover(e, () => status))
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
  ctx.status->Status.hover(e, () => "Switch between the graph and the raw values")
}
