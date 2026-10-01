// Mod page: the modulation matrix, led by the connections that exist.
//
// Left, the sources in groups (the macro knobs among them). Right, the connections, one row
// each: source, cable, target, amount, "via" source, remove. Grabbing a source (or "add
// connection") brings up the targets in their groups over the list: drop the cable on one, or
// click it. A row's source or target can be changed in place.

open! Web

let hint = "Drag a source onto a target to connect them, or click a source and then a target. Click a connection's source or target to change it. Double-click a macro's name to rename it."

let (margin, gap) = (6., Grid.gap)
let sourcesWidth = 300.
let defaultAmount = 0.25
let headingHeight = 20.

// the target groups' columns in the picker
let targetColumns = [["voice", "filter"], ["osc"], ["lfo"], ["fx"], ["eq"], ["rack"]]

let sourceColor = s =>
  switch ModMatrix.sources[s]->Option.mapOr("", s => s.key) {
  | "lfo1" => "#1c3c73"
  | "lfo2" => "#4a74b4"
  | "modEnv1" => "#2e6b3a"
  | "modEnv2" => "#5c8f3c"
  | "ampEnv" | "filterEnv" => "#3d7a6d"
  | "macro1" | "macro2" | "macro3" | "macro4" => "#6a2c70"
  | "cc1" | "cc2" | "cc3" | "cc4" | "cc5" | "cc6" => "#7a5a1e"
  | _ => "#a3501c"
  }

type point = {x: float, y: float}

// what the target picker is for: connecting a source, or moving connection k
type mode = Closed | Connect(int) | Retarget(int)

// A hanging cable from a to b.
let cablePath = (a, b, ~sag) => {
  let dx = b.x - a.x
  let f = x => Float.toFixed(x, ~digits=1)
  `M${f(a.x)} ${f(a.y)} C${f(a.x + dx * 0.3)} ${f(a.y + sag)} ${f(b.x - dx * 0.3)} ${f(b.y + sag)} ${f(b.x)} ${f(b.y)}`
}

// The sources in their groups, by index; sources no group names go in a last group.
let sourceGroups = {
  let grouped = ModMatrix.sourceGroups->Array.map(((title, keys)) => (
    title,
    keys->Array.map(ModMatrix.sourceIndex)->Array.filter(i => i > 0),
  ))
  let named = grouped->Array.flatMap(Pair.second)
  let rest =
    ModMatrix.sources
    ->Array.mapWithIndex((_, i) => i)
    ->Array.filter(i => i > 0 && !(named->Array.includes(i)))
  rest == [] ? grouped : [...grouped, ("other", rest)]
}

// The target groups in their picker columns; groups no column names go in the shortest.
let pickerColumns = {
  let members = group =>
    ModMatrix.targets
    ->Array.mapWithIndex((t, i) => (t, i))
    ->Array.filter(((t, _)) => t.group == group)
    ->Array.map(Pair.second)
  let title = group =>
    ModMatrix.groups->Array.find(((key, _)) => key == group)->Option.mapOr(group, Pair.second)
  let columns = targetColumns->Array.map(groups => groups->Array.map(g => (title(g), members(g))))
  let placed = targetColumns->Array.flat
  ModMatrix.groups->Array.forEach(((key, _)) =>
    if !(placed->Array.includes(key)) {
      let size = column => column->Array.reduce(0, (n, (_, ts)) => n + 1 + Array.length(ts))
      let shortest = columns->Array.reduceWithIndex(0, (best, column, i) =>
        size(column) < size(columns->Array.getUnsafe(best)) ? i : best
      )
      columns->Array.getUnsafe(shortest)->Array.push((title(key), members(key)))
    }
  )
  columns
}

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let slotNumbers = Array.fromInitializer(~length=ModMatrix.slots, i => i + 1)
  let sourceOf = k => Float.toInt(get(ModMatrix.sourceId(k)))
  let targetOf = k => Float.toInt(get(ModMatrix.targetId(k)))
  let isUsed = k => sourceOf(k) > 0 && targetOf(k) > 0
  let redraw = ref(() => ())

  let macroName = i => {
    let name = (ctx.programs->ProgramStore.meta).macroNames[i]->Option.getOr("")
    name == "" ? `macro ${Int.toString(i + 1)}` : name
  }
  let macroOf = s =>
    switch ModMatrix.sources[s] {
    | Some({key}) if String.startsWith(key, "macro") => Some(s - ModMatrix.sourceIndex("macro1"))
    | _ => None
    }
  let sourceLabel = s =>
    switch (macroOf(s), ModMatrix.sources[s]) {
    | (Some(i), _) => macroName(i)
    | (None, Some(source)) => source.label
    | (None, None) => ""
    }
  let targetLabel = t => ModMatrix.targets[t]->Option.mapOr("", t => t.label)
  let connectionText = k => {
    let via = Float.toInt(get(ModMatrix.viaId(k)))
    let amount = model->ParamModel.def(ModMatrix.amountId(k))
    `${sourceLabel(sourceOf(k))} → ${targetLabel(targetOf(k))}, ${amount.valueText(
        get(ModMatrix.amountId(k)),
      )}` ++ (via > 0 ? ` × ${sourceLabel(via)}` : "")
  }
  let targetText = t =>
    switch ModMatrix.targets->Array.getUnsafe(t) {
    | {law: Knob(id)} => (model->ParamModel.def(id)).longText(get(id))
    | {label} => label
    }

  let show = text => ctx.status->Status.show(text)
  let clear = () => ctx.status->Status.clear
  let hover = (e, text) => {
    e->onMouse(#mouseenter, _ => show(text()))
    e->onMouse(#mouseleave, _ => clear())
  }

  //==============================================================================
  // editing

  let setSlot = (k, source, target, amount, via) => {
    model->ParamModel.gestureSet(ModMatrix.amountId(k), amount)
    model->ParamModel.gestureSet(ModMatrix.viaId(k), via)
    model->ParamModel.gestureSet(ModMatrix.sourceId(k), source)
    model->ParamModel.gestureSet(ModMatrix.targetId(k), target)
  }

  let disconnect = k => setSlot(k, 0., 0., 0., 0.)

  let connect = (source, target) =>
    if slotNumbers->Array.some(k => sourceOf(k) == source && targetOf(k) == target) {
      ctx.toast(`${sourceLabel(source)} already modulates ${targetLabel(target)}`)
    } else {
      switch slotNumbers->Array.find(k => !isUsed(k)) {
      | Some(k) => setSlot(k, Int.toFloat(source), Int.toFloat(target), defaultAmount, 0.)
      | None => ctx.toast(`All ${Int.toString(ModMatrix.slots)} modulation slots are in use`)
      }
    }

  let retarget = (k, target) => model->ParamModel.gestureSet(ModMatrix.targetId(k), Int.toFloat(target))
  let resource = (k, source) => model->ParamModel.gestureSet(ModMatrix.sourceId(k), Int.toFloat(source))

  // a swatch in the source's colour, for menus
  let swatch = s => {
    let e = el("span", ~cls="icw")
    el("i", ~cls="msw", ~parent=e)->setStyle("background", sourceColor(s))
    e
  }
  let sourceMenu = (anchor, current, onPick) =>
    ctx.menu->Menu.show(
      anchor,
      sourceGroups->Array.flatMap(((_, members)) =>
        members->Array.map(s => {Menu.label: sourceLabel(s), value: s, icon: swatch(s)})
      ),
      current,
      onPick,
    )

  //==============================================================================
  // panels

  let sources = Panel.make(
    page,
    ~title="sources",
    ~x=margin,
    ~y=margin,
    ~w=sourcesWidth,
    ~h=Style.pageHeight - 2. * margin,
  )
  let listX = sources->Panel.right
  let listWidth = Style.designWidth - margin - listX
  let list = Panel.make(
    page,
    ~title="connections",
    ~x=listX,
    ~y=margin,
    ~w=listWidth,
    ~h=Style.pageHeight - 2. * margin,
  )
  let count = el("div", ~cls="mcount", ~parent=list.el)

  // the targets, over the list while a source is being connected
  let picker = Panel.make(page, ~x=listX, ~y=margin, ~w=listWidth, ~h=list.h)
  picker.el->addClass("picker")
  let pickerTitle = el("div", ~cls="ttl", ~parent=picker.el)
  let wires = Plots.svg(page, {x: 0., y: 0., w: Style.designWidth, h: Style.pageHeight})
  wires->setAttribute("class", Str("wires"))

  //==============================================================================
  // sources

  let sourceChips = Array.make(~length=Array.length(ModMatrix.sources), None)
  let sourceJack = s =>
    sourceChips[s]
    ->Option.flatMap(x => x)
    ->Option.map(((_, jack)) => jack)

  let startRef = ref((_: Dom.pointerEvent, _: int, _: element) => ())
  let pickRef = ref((_: int) => ())

  let cg = Grid.fitColumns(sourcesWidth, 2)
  let y = ref(Grid.padTop - 4.)
  sourceGroups->Array.forEach(((title, members)) => {
    el("div", ~cls="grp", ~text=title, ~parent=sources.el)->place(Grid.padX + 1., y.contents)->ignore
    let g = Grid.make(ctx, sources.el, ~y=y.contents + headingHeight, ~cw=cg)
    members->Array.forEachWithIndex((s, i) => {
      let (c, r) = (mod(i, 2), i / 2)
      g->Grid.claim(c, r, sourceLabel(s))
      let b = g->Grid.cell(c, r)
      let source = ModMatrix.sources->Array.getUnsafe(s)
      switch macroOf(s) {
      | Some(m) =>
        // a macro: its knob, and a jack to take a cable from
        let knob = Controls.paramControl(
          ctx,
          sources.el,
          ModMatrix.macroId(m + 1),
          ~x=b.x,
          ~y=b.y,
          ~w=b.w - 24.,
          ~label=macroName(m),
        )
        knob
        ->querySelector(".l")
        ->Option.forEach(l => {
          l->onMouse(#dblclick, ev => {
            ev->preventDefault
            ev->stopPropagation
            Controls.editInPlace(knob, (ctx.programs->ProgramStore.meta).macroNames[m]->Option.getOr(""), ~commit=name =>
              ctx.programs->ProgramStore.setMacroName(m, name)
            )
          })
        })
        let plug = el("div", ~cls="src plug", ~parent=sources.el)->place(
          b.x + b.w - 22.,
          b.y,
          ~w=22.,
          ~h=b.h,
        )
        plug->setTabIndex(0)
        let jack = el("i", ~cls="jk", ~parent=plug)
        plug->onPointer(#pointerdown, ev => startRef.contents(ev, s, plug))
        plug->onKeyDown(ev =>
          if ev->key == "Enter" || ev->key == " " {
            ev->preventDefault
            pickRef.contents(s)
          }
        )
        plug->hover(() => `${sourceLabel(s)}: drag to a target to connect it. Double-click the name to rename it.`)
        sourceChips->Array.setUnsafe(s, Some((plug, jack)))
      | None =>
        let chip = el("div", ~cls="src", ~parent=sources.el)->placeBox(b)
        chip->setTabIndex(0)
        el("i", ~cls="sw", ~parent=chip)->setStyle("background", sourceColor(s))
        el("span", ~cls="lbl", ~text=sourceLabel(s), ~parent=chip)->ignore
        el("b", ~cls="n", ~parent=chip)->ignore
        let jack = el("i", ~cls="jk", ~parent=chip)
        chip->onPointer(#pointerdown, ev => startRef.contents(ev, s, chip))
        chip->onKeyDown(ev =>
          if ev->key == "Enter" || ev->key == " " {
            ev->preventDefault
            pickRef.contents(s)
          }
        )
        chip->hover(() =>
          `${sourceLabel(s)}: ${ModMatrix.sourceHelp(source.key)}. Drag it to a target, or click it.`
        )
        sourceChips->Array.setUnsafe(s, Some((chip, jack)))
      }
    })
    y := y.contents + headingHeight + Int.toFloat((Array.length(members) + 1) / 2) * Grid.rowHeight + 4.
  })

  //==============================================================================
  // the target picker

  let mode = ref(Closed)
  let targetChips = Array.make(~length=Array.length(ModMatrix.targets), None)
  let pickTargetRef = ref((_: int) => ())

  let pg = Grid.fitColumns(listWidth, Array.length(pickerColumns))
  pickerColumns->Array.forEachWithIndex((groups, c) => {
    let y = ref(Grid.padTop - 4.)
    groups->Array.forEach(((title, members)) => {
      el("div", ~cls="grp", ~text=title, ~parent=picker.el)
      ->place(Grid.padX + Int.toFloat(c) * pg + 1., y.contents)
      ->ignore
      let g = Grid.make(ctx, picker.el, ~y=y.contents + headingHeight, ~cw=pg)
      members->Array.forEachWithIndex((t, r) => {
        g->Grid.claim(c, r, targetLabel(t))
        let chip = el("div", ~cls="tgt", ~parent=picker.el)->placeBox(g->Grid.cell(c, r))
        chip->setTabIndex(0)
        el("i", ~cls="jk", ~parent=chip)->ignore
        el("span", ~cls="lbl", ~text=targetLabel(t), ~parent=chip)->ignore
        chip->onPointer(#pointerdown, ev => {
          ev->preventDefault
          if ev->button == 0 {
            pickTargetRef.contents(t)
          }
        })
        chip->onKeyDown(ev =>
          if ev->key == "Enter" || ev->key == " " {
            ev->preventDefault
            pickTargetRef.contents(t)
          }
        )
        chip->hover(() => targetText(t))
        targetChips->Array.setUnsafe(t, Some(chip))
      })
      y := y.contents + headingHeight + Int.toFloat(Array.length(members)) * Grid.rowHeight + 6.
    })
  })
  let cancel = Controls.button(ctx, picker.el, "cancel", ~x=listWidth - 70., ~y=2., ~w=60., () => ())
  let pickerHint = el(
    "div",
    ~cls="note",
    ~text="Drop the cable on a target, or click one. Esc cancels.",
    ~parent=picker.el,
  )
  pickerHint->place(listWidth - 80. - 290., 4., ~w=280.)->ignore
  pickerHint->setStyle("text-align", "right")

  let closer = ref(None)
  let closePicker = () => {
    mode := Closed
    picker.el->removeClass("on")
    closer.contents->Option.forEach(f => document->offDocumentPointerDownCapture(f))
    closer := None
    redraw.contents()
  }
  let onEscape = ev =>
    if ev->key == "Escape" && mode.contents != Closed {
      closePicker()
    }
  document->onDocumentKeyDown(onEscape)
  cancel->onMouse(#click, _ => closePicker())

  let openPicker = m => {
    mode := m
    let (title, source) = switch m {
    | Connect(s) => (`connect ${sourceLabel(s)} to …`, s)
    | Retarget(k) => (`move ${sourceLabel(sourceOf(k))} → ${targetLabel(targetOf(k))} to …`, sourceOf(k))
    | Closed => ("", 0)
    }
    pickerTitle->setTextContent(title)
    // the targets this source already reaches
    targetChips->Array.forEachWithIndex((chip, t) =>
      chip->Option.forEach(chip =>
        chip->toggleClass(
          "on",
          slotNumbers->Array.some(k => isUsed(k) && sourceOf(k) == source && targetOf(k) == t),
        )
      )
    )
    picker.el->addClass("on")
    // a press outside the picker (and the sources) closes it
    if closer.contents == None {
      let f = ev => {
        let target = ev->originalTarget
        if !(picker.el->contains(target)) && !(sources.el->contains(target)) {
          closePicker()
        }
      }
      setTimeout(() =>
        if mode.contents != Closed && closer.contents == None {
          closer := Some(f)
          document->onDocumentPointerDownCapture(f)
        }
      , 0)->ignore
    }
    redraw.contents()
  }

  pickTargetRef :=
    t => {
      switch mode.contents {
      | Connect(s) => connect(s, t)
      | Retarget(k) => retarget(k, t)
      | Closed => ()
      }
      closePicker()
    }
  pickRef := s => openPicker(Connect(s))

  //==============================================================================
  // dragging a cable from a source

  let toLocal = (cx, cy) => {
    let r = wires->getBoundingClientRect
    let s = ctx.scale()
    {x: (cx - r.left) / s, y: (cy - r.top) / s}
  }
  let centre = e => {
    let r = e->getBoundingClientRect
    toLocal(r.left + r.width / 2., r.top + r.height / 2.)
  }
  let targetAt = (cx, cy) =>
    targetChips->Array.findIndex(chip =>
      chip->Option.mapOr(false, chip => {
        let r = chip->getBoundingClientRect
        cx >= r.left && cx <= r.left + r.width && cy >= r.top && cy <= r.top + r.height
      })
    )

  startRef :=
    (ev, s, chip) =>
      if ev->button == 0 {
        ev->preventDefault
        openPicker(Connect(s))
        let start = sourceJack(s)->Option.mapOr({x: 0., y: 0.}, centre)
        let wire = wires->Plots.svgEl(
          "path",
          [("class", Str("wire drag")), ("stroke", Str(sourceColor(s))), ("d", Str(""))],
        )
        let (x0, y0) = (ev->clientX, ev->clientY)
        let moved = ref(false)
        let hot = ref(-1)
        let setHot = t => {
          targetChips[hot.contents]->Option.flatMap(x => x)->Option.forEach(c => c->removeClass("hot"))
          hot := t
          targetChips[t]->Option.flatMap(x => x)->Option.forEach(c => c->addClass("hot"))
        }
        chip->Controls.capturePointer(
          ev,
          ~onMove=mv => {
            if Math.hypot(mv->clientX - x0, mv->clientY - y0) > 4. {
              moved := true
            }
            let t = targetAt(mv->clientX, mv->clientY)
            setHot(t)
            let p = switch targetChips[t]->Option.flatMap(x => x) {
            | Some(c) => {
                let r = c->getBoundingClientRect
                toLocal(r.left + 13. * ctx.scale(), r.top + r.height / 2.)
              }
            | None => toLocal(mv->clientX, mv->clientY)
            }
            wire->setAttribute("d", Str(cablePath(start, p, ~sag=18.)))
          },
          ~onUp=() => {
            wire->remove
            let t = hot.contents
            setHot(-1)
            if t > 0 {
              pickTargetRef.contents(t)
            } else if moved.contents {
              // dropped on nothing
              closePicker()
            }
            // a click leaves the picker open, to click a target
          },
        )
      }

  //==============================================================================
  // the connections

  let rg = Grid.fitColumns(listWidth, 16)
  let rows = slotNumbers->Array.map(k => {
    let row = el("div", ~cls="conn", ~parent=list.el)->place(0., 0., ~w=listWidth - 2., ~h=Grid.rowHeight)
    let g = Grid.make(ctx, row, ~y=0., ~cw=rg)

    let source = el("div", ~cls="src", ~parent=row)->placeBox(g->Grid.cell(0, 0, ~span=4))
    source->setTabIndex(0)
    let sw = el("i", ~cls="sw", ~parent=source)
    let sourceName = el("span", ~cls="lbl", ~parent=source)
    el("i", ~cls="jk on", ~parent=source)->ignore
    g->Grid.claim(0, 0, ~span=4, "source")
    source->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        sourceMenu(source, sourceOf(k), s => resource(k, s))
      }
    })
    source->hover(() => connectionText(k) ++ ". Click to change the source.")

    let cable = Plots.svg(row, g->Grid.cell(4, 0))
    cable->setAttribute("class", Str("wirecell"))
    let wire = cable->Plots.svgEl("path", [("class", Str("wire"))])
    g->Grid.claim(4, 0, "cable")

    let target = el("div", ~cls="tgt", ~parent=row)->placeBox(g->Grid.cell(5, 0, ~span=4))
    target->setTabIndex(0)
    el("i", ~cls="jk on", ~parent=target)->ignore
    let targetName = el("span", ~cls="lbl", ~parent=target)
    g->Grid.claim(5, 0, ~span=4, "target")
    target->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        openPicker(Retarget(k))
      }
    })
    target->onKeyDown(ev =>
      if ev->key == "Enter" {
        openPicker(Retarget(k))
      }
    )
    target->hover(() => targetText(targetOf(k)) ++ ". Click to change the target.")

    g->Grid.param(ModMatrix.amountId(k), 9, 0, "amount", ~span=4)
    g->Grid.choice(ModMatrix.viaId(k), 13, 0, "via (scaled by)", ~span=2)
    g->Grid.button("×", 15, 0, ~status="Remove this connection", () => disconnect(k))

    row->onMouse(#mouseenter, _ =>
      sourceChips[sourceOf(k)]->Option.flatMap(x => x)->Option.forEach(((c, _)) => c->addClass("lit"))
    )
    row->onMouse(#mouseleave, _ =>
      sourceChips->Array.forEach(c => c->Option.forEach(((c, _)) => c->removeClass("lit")))
    )
    (k, row, sw, sourceName, targetName, wire)
  })

  // the last row: add a connection
  let add = el("div", ~cls="addrow", ~parent=list.el)
  add->setTabIndex(0)
  el("b", ~text="+", ~parent=add)->ignore
  el("span", ~text="add connection", ~parent=add)->ignore
  el("span", ~cls="sub", ~text="or drag a source from the left onto a target", ~parent=add)->ignore
  let addConnection = () => sourceMenu(add, -1, s => openPicker(Connect(s)))
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    addConnection()
  })
  add->onKeyDown(ev =>
    if ev->key == "Enter" {
      addConnection()
    }
  )
  add->hover(() => "Pick a source, then a target")

  let empty = el("div", ~cls="mempty", ~parent=list.el)
  el("div", ~cls="big", ~text="Nothing modulates anything yet.", ~parent=empty)->ignore
  el(
    "div",
    ~text="Drag a source from the left onto a target, or click a source and then a target. Each connection gets an amount, and an optional second source that scales it.",
    ~parent=empty,
  )->ignore

  //==============================================================================
  // drawing

  let draw = () => {
    let used = slotNumbers->Array.filter(isUsed)
    let counts = Map.make()
    used->Array.forEach(k =>
      counts->Map.set(sourceOf(k), counts->Map.get(sourceOf(k))->Option.getOr(0) + 1)
    )

    // the list, in slot order
    rows->Array.forEach(((k, row, sw, sourceName, targetName, wire)) =>
      if isUsed(k) {
        let shown = used->Array.indexOf(k)
        let (s, t) = (sourceOf(k), targetOf(k))
        row->addClass("on")
        row->setStyle("top", px(Grid.padTop + Int.toFloat(shown) * Grid.rowHeight))
        sw->setStyle("background", sourceColor(s))
        sourceName->setTextContent(sourceLabel(s))
        targetName->setTextContent(targetLabel(t))
        // the cable spans the cell between the two jacks
        let w = rg - Grid.columnGap
        wire->setAttribute(
          "d",
          Str(cablePath({x: -11., y: 13.}, {x: w + 11., y: 13.}, ~sag=7.)),
        )
        wire->setAttribute("stroke", Str(sourceColor(s)))
        wire->setAttribute("class", Str(get(ModMatrix.amountId(k)) == 0. ? "wire muted" : "wire"))
      } else {
        row->removeClass("on")
      }
    )
    let n = Array.length(used)
    add->setStyle("display", n < ModMatrix.slots ? "flex" : "none")
    add->placeBox({
      x: Grid.padX,
      y: Grid.padTop + Int.toFloat(n) * Grid.rowHeight,
      w: listWidth - 2. - 2. * Grid.padX,
      h: Style.controlHeight,
    })->ignore
    empty->setStyle("display", n == 0 ? "block" : "none")
    count->setTextContent(`${Int.toString(n)} of ${Int.toString(ModMatrix.slots)}`)

    // the sources: how many connections each has
    sourceChips->Array.forEachWithIndex((chip, s) =>
      chip->Option.forEach(((chip, jack)) => {
        let c = counts->Map.get(s)->Option.getOr(0)
        jack->toggleClass("on", c > 0)
        jack->setStyle("background", c > 0 ? sourceColor(s) : "")
        chip->querySelector(".n")->Option.forEach(b => {
          b->setTextContent(c > 1 ? Int.toString(c) : "")
          b->setStyle("display", c > 1 ? "block" : "none")
        })
        chip->querySelector(".lbl")->Option.forEach(l => l->setTextContent(sourceLabel(s)))
        let picking = switch mode.contents {
        | Connect(p) => p == s
        | _ => false
        }
        chip->toggleClass("sel", picking)
      })
    )
    sources.el
    ->querySelectorAll(".p .l")
    ->nodesToArray
    ->Array.forEachWithIndex((l, i) => l->setTextContent(macroName(i)))
  }

  let pending = ref(false)
  redraw :=
    () =>
      if !pending.contents {
        pending := true
        // (a timeout rather than an animation frame: a burst of changes draws once, and
        // the page still updates while the window isn't being painted)
        setTimeout(() => {
          pending := false
          draw()
        }, 0)->ignore
      }

  slotNumbers->Array.forEach(k =>
    [ModMatrix.sourceId(k), ModMatrix.targetId(k), ModMatrix.amountId(k), ModMatrix.viaId(k)]->Array.forEach(
      id => model->ParamModel.listen(id, () => redraw.contents())
    )
  )
  ctx.programs->ProgramStore.onChanged(() => redraw.contents())
  draw()
}
