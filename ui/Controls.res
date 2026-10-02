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
// (more: what the status text says after the parameter's own)
let frame = (ctx: Ctx.t, parent, id, ~cls, ~x, ~y, ~w=?, ~label=?, ~labelCls=?, ~box=false, ~more=() => "") => {
  let e = el("div", ~cls, ~parent)->place(x, y, ~w?)
  let def = ctx.model->ParamModel.def(id)
  let c = {
    ctx,
    id,
    def,
    status: ctx.status->Status.live(e, () => def.longText(ctx.model->ParamModel.get(id)) ++ more()),
  }
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

// What moves a parameter (Modulators), for its status text: and with matrix connections, that
// an alt-drag changes the first's amount.
let modulationText = (ctx: Ctx.t, id) =>
  switch Modulators.on(ctx.model, id) {
  | [] => ""
  | ms =>
    let connections = ms->Array.filter(m => m.slot != None)->Array.length
    Modulators.statusText(ctx.model, [id]) ++ (
      connections == 0
        ? ""
        : `: alt-drag to change ${connections > 1 ? "the first connection's amount" : "the connection's amount"}`
    )
  }

// What moves a control, shown in its sources' colours (Modulators): a band under the track for
// the range each matrix connection sweeps, one under another, and for what has no known range
// on the knob (Oatmeal's own routings), a mark down the left edge, split between them. Any
// control with a track can carry them; the edge marks go into e.
let modMarks = (ctx: Ctx.t, e, track, id, ~norm) => {
  let bands = ref(None)
  let edge = ref(None)
  let lazyEl = (slot, cls, parent) =>
    switch slot.contents {
    | Some(x) => x
    | None =>
      let x = el("span", ~cls, ~parent)
      slot := Some(x)
      x
    }
  let marksIn = (box, tag, count) => {
    let marks = box->querySelectorAll(tag)->nodesToArray
    let made = Array.fromInitializer(~length=count, i =>
      switch marks[i] {
      | Some(m) => m
      | None => el(tag, ~parent=box)
      }
    )
    made->Array.forEach(m => m->setStyle("display", "block"))
    marks->Array.forEachWithIndex((m, i) =>
      if i >= count {
        m->setStyle("display", "none")
      }
    )
    made
  }
  () => {
    let ms = Modulators.on(ctx.model, id)
    let ranged = ms->Array.filterMap(m => m.range->Option.map(r => (m, r)))
    let unranged = ms->Array.filter(m => m.range == None)
    if ranged != [] || bands.contents != None {
      let n = clamp01(norm())
      let box = lazyEl(bands, "mb", track)
      marksIn(box, "em", Array.length(ranged))->Array.forEachWithIndex((band, i) => {
        let (m, (lo, hi)) = ranged->Array.getUnsafe(i)
        let (a, b) = (clamp01(n + lo), clamp01(n + hi))
        band->setStyle("left", Float.toString(a * 100.) ++ "%")
        band->setStyle("width", Float.toString(Math.max(0.5, (b - a) * 100.)) ++ "%")
        band->setStyle("background", Modulators.colour(m))
        // several: one under another
        band->setStyle("top", px(-1. - 2. * Int.toFloat(i)))
      })
    }
    if unranged != [] || edge.contents != None {
      let box = lazyEl(edge, "me", e)
      marksIn(box, "i", Array.length(unranged))->Array.forEachWithIndex((mark, i) =>
        mark->setStyle("background", Modulators.colour(unranged->Array.getUnsafe(i)))
      )
    }
  }
}

// A parameter row: label above-left, value right, position track underneath, and what moves it
// (modMarks). A parameter the modulation matrix reaches shows a tick where each sounding note
// has moved it; an alt-drag changes its first connection's amount, and a source dropped on it
// from the tray (ModTray) connects to it.
let paramControl = (ctx, parent, id, ~x, ~y, ~w=76., ~label=?) => {
  let target = ModMatrix.targetOfParam(id)
  let (c, e) = frame(ctx, parent, id, ~cls="p", ~x, ~y, ~w, ~label?, ~labelCls="l", ~more=() =>
    modulationText(ctx, id)
  )
  let v = el("span", ~cls="v", ~parent=e)
  let track = el("span", ~cls="t", ~parent=e)
  let fill = el("i", ~parent=track)
  // where the sounding notes have moved it to, a tick each (VoiceView)
  let ticks = target >= 0 ? Some(el("span", ~cls="vt", ~parent=track)) : None
  if target >= 0 {
    ModEdit.addDropTarget(e, id, target)
  }

  let norm = () => c.def.toNorm(current(c))
  let setNorm = n => ctx.model->ParamModel.set(id, c.def.fromNorm(clamp01(n)))
  let get = id => ctx.model->ParamModel.get(id)

  let updateModBar = modMarks(ctx, e, track, id, ~norm)

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
    | 0 if ev->altKey && target >= 0 && ModEdit.connectionsTo(get, target) != [] =>
      ev->preventDefault
      switch ModEdit.connectionsTo(get, target)[0] {
      | Some(k) =>
        let amountId = ModMatrix.amountId(k)
        let amountDef = ctx.model->ParamModel.def(amountId)
        let source = ModMatrix.sources[ModMatrix.readSlot(get, k).source]->Option.mapOr("", s => s.label)
        let show = () => ctx.status->Status.show(`${source} → ${c.def.name}: ${amountDef.valueText(get(amountId))}`)
        e->addClass("drag")
        ctx.model->ParamModel.beginGesture(amountId)
        let a = ref(get(amountId))
        show()
        dragBy(
          ctx,
          e,
          ev,
          ~onMove=(dx, dy, mv) => {
            let d = 2. * (dx * 0.35 - dy) / dragPixels
            let d = mv->shiftKey ? d * fineShift : d
            a := Float.clamp(a.contents + d, ~min=-1., ~max=1.)
            ctx.model->ParamModel.set(amountId, a.contents)
            show()
          },
          ~onUp=() => {
            e->removeClass("drag")
            ctx.model->ParamModel.endGesture(amountId)
            refreshStatus(c)
          },
        )
      | None => ()
      }
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

  Modulators.watch(ctx.model, updateModBar)
  ticks->Option.forEach(box => {
    let notes = VoiceView.get(ctx.pc)
    notes->VoiceView.listenTarget(target, e, shown => {
      let positions = shown ? notes->VoiceView.positionsOf(target) : []
      let marks = box->querySelectorAll("b")->nodesToArray
      positions->Array.forEachWithIndex((p, i) => {
        let mark = switch marks[i] {
        | Some(m) => m
        | None => el("b", ~parent=box)
        }
        mark->setStyle("left", Float.toString(clamp01(p) * 100.) ++ "%")
        mark->setStyle("display", "block")
      })
      marks->Array.forEachWithIndex((m, i) =>
        if i >= Array.length(positions) {
          m->setStyle("display", "none")
        }
      )
    })
  })
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
  let icons = Icons.forList(c.def.list)
  let v = el("span", ~cls=icons != None ? "v withicon" : "v", ~parent=e)
  let icon = value =>
    icons->Option.flatMap(find => Icons.forValue(find, value, menuNames[value]->Option.getOr("")))

  let update = () => {
    let x = current(c)
    let i = Float.toInt(x)
    let text = names[i]->Option.getOr(Float.toString(x))
    switch icon(i) {
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

  // (the filter types' and distortion types' menus show their groups)
  let order = ValueList.menu(c.def.list, Array.length(menuNames))
  let step = listInput(ctx, e, id, ~items=() =>
    order->Array.map(((value, heading)) => {
      let label = menuNames[value]->Option.getOr("")
      switch icon(value) {
      | Some((icon, label)) => {Menu.label, value, icon, ?heading}
      | None => {Menu.label, value, ?heading}
      }
    })
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

// An LFO's mode (LFO_n_Sync, LFO_3_Mode: per-voice 0, shared and restarted by each note 1,
// shared and free 2) as two halves: per-voice, or shared. Clicking shared again switches
// between restarting with each note and running free.
let lfoMode = (ctx: Ctx.t, parent, id, ~x, ~y, ~w) => {
  let model = ctx.model
  let def = model->ParamModel.def(id)
  let e = el("div", ~cls="seg", ~parent)->place(x, y, ~w)
  e->setTabIndex(0)
  let each = el("span", ~text="per-voice", ~parent=e)
  let shared = el("span", ~parent=e)
  let c = {
    ctx,
    id,
    def,
    status: ctx.status->Status.live(e, () =>
      switch model->ParamModel.get(id) {
      | 0. => "Per-voice: each voice has its own, starting with its note. Click shared for one that every voice follows."
      | 1. => "Shared by every note, restarted by each new one. Click again to let it run free; click per-voice for one in each voice."
      | _ => "Shared by every note, running free. Click again to restart it with each note; click per-voice for one in each voice."
      }
    ),
  }
  hookHostMenu(c, e)
  let set = x => gestureSet(c, x)
  let update = () => {
    let x = current(c)
    each->toggleClass("on", x == 0.)
    shared->toggleClass("on", x != 0.)
    shared->setTextContent(x == 0. ? "shared" : x == 1. ? "shared, reset" : "shared, free")
    refreshStatus(c)
  }
  each->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      set(0.)
    }
  })
  shared->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      set(current(c) == 1. ? 2. : 1.)
    }
  })
  e->suppressContextMenu
  e->onKeyDown(ev =>
    switch ev->key {
    | "ArrowLeft" => set(0.)
    | "ArrowRight" | " " | "Enter" =>
      ev->preventDefault
      set(current(c) == 1. ? 2. : 1.)
    | _ => ()
    }
  )
  bind(c, update)
}

// (an icon goes in front of the text)
let button = (ctx: Ctx.t, parent, text, ~x, ~y, ~w, ~h=?, ~cls="", ~icon=?, ~status=?, onClick) => {
  let cls = cls == "" ? "btn" : "btn " ++ cls
  let e = switch icon {
  | Some(icon) =>
    let e = el("button", ~cls=cls ++ " withicon", ~parent)
    e->appendChild(Icons.render(icon))
    el("span", ~text, ~parent=e)->ignore
    e
  | None => el("button", ~cls, ~text, ~parent)
  }->place(x, y, ~w, ~h?)
  e->onMouse(#click, _ => onClick())
  status->Option.forEach(status => ctx.status->Status.hover(e, () => status))
  e
}

// A small "?" button, size wide and high at (x, y), that shows text in a tooltip tipW wide while
// the pointer is over it, right-aligned under it.
let help = (parent, text, ~x, ~y, ~size, ~tipW) => {
  let e = el("button", ~cls="btn help", ~text="?", ~parent)->place(x, y, ~w=size, ~h=size)
  let tip = el("div", ~cls="tip", ~text, ~parent)->place(x + size - tipW, y + size + 4., ~w=tipW)
  e->onMouse(#mouseenter, _ => tip->addClass("on"))
  e->onMouse(#mouseleave, _ => tip->removeClass("on"))
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
