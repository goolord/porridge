// Mod page: the modulation matrix, led by the connections that exist.
//
// Left, the sources: the per-voice ones (each voice its own), then those every voice shares (the macro
// knobs and controllers among them); an LFO moves between the two with its mode. Right, the
// connections, one row each: source, cable, target, amount, "via" source, options (hold, slew,
// curve, steps), remove. Grabbing a source (or "add connection") brings up the targets over the list,
// the per-voice ones apart from those on the whole sound: drop the cable on one, or click it,
// or search for one. A row's source or target can be changed in place. A per-note source on
// the whole sound follows the newest note, or every note by its level (the setting below the
// list); its cable says which.

open! Web

let hint = "Drag a source onto a target to connect them, or click a source and then a target. Click a connection's source or target to change it, its options to hold, slew, bend or step it. Double-click a macro's name to rename it."

let (margin, gap) = (6., Grid.gap)
let sourcesWidth = 342.
let sourceColumns = 3
let headingHeight = 20.
// below the connections: the follow setting
let footerHeight = 36.

// the target picker: its columns, its title row (the targets scroll under it), and the room
// for its scrollbar
let (pickerColumns, pickerTop, scrollbarWidth) = (5, 26., 9.)

let sourceColor = ModEdit.sourceColor

type point = {x: float, y: float}

// a source's element on the left: the chip (or a macro's plug), its jack, and a chip's count of
// connections and label; a macro's knob
type sourceChip = {
  chip: element,
  jack: element,
  count: option<element>,
  label: option<element>,
  knob: option<element>,
}

// what the target picker is for: connecting a source, or moving connection k
type mode = Closed | Connect(int) | Retarget(int)

// A hanging cable from a to b.
let cablePath = (a, b, ~sag) => {
  let dx = b.x - a.x
  let f = x => Float.toFixed(x, ~digits=1)
  `M${f(a.x)} ${f(a.y)} C${f(a.x + dx * 0.3)} ${f(a.y + sag)} ${f(b.x - dx * 0.3)} ${f(b.y + sag)} ${f(b.x)} ${f(b.y)}`
}

let sourceOrder = ModEdit.sourceOrder

// The sources in their groups for menus, by index; sources no group names go in a last group.
let sourceGroups = {
  let grouped = ModMatrix.sourceGroups->Array.map(((title, keys)) => (
    title,
    keys->Array.map(ModMatrix.sourceIndex)->Array.filter(i => i > 0),
  ))
  let named = grouped->Array.flatMap(Pair.second)
  let rest = sourceOrder->Array.filter(i => !(named->Array.includes(i)))
  rest == [] ? grouped : [...grouped, ("other", rest)]
}

let isMacro = s => ModEdit.macroOf(s) != None
let isController = ModEdit.isController

let effectOf = ModScope.effectOf
let copyOf = ModScope.copyOf

// The target groups, by index: an effect's own targets first, then each copy's.
let targetGroups = ModMatrix.groups->Array.map(((key, title)) => (
  title,
  ModMatrix.targets
  ->Array.mapWithIndex((t, i) => (t, i))
  ->Array.filter(((t, i)) => i > 0 && t.group == key)
  ->Array.map(Pair.second)
  ->Array.toSorted((a, b) => Int.toFloat(copyOf(a) - copyOf(b))),
))

// the picker's two sections
let sections: array<(string, ModMatrix.scope, string)> = [
  ("per-voice", EachNote, "Each voice moves these its own way"),
  ("on the whole sound", Shared, "These have one value: a per-note source gives them the newest note's, or every note's by level (below the connections)"),
]

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let slotNumbers = ModMatrix.slotNumbers
  let slot = k => ModMatrix.readSlot(get, k)
  let sourceOf = k => slot(k).source
  let targetOf = k => slot(k).target
  let isUsed = ModEdit.isUsed(get, _)
  let redraw = ref(() => ())

  let macroName = ModEdit.macroName(ctx.programs, _)
  let macroOf = ModEdit.macroOf
  let sourceLabel = s =>
    switch (macroOf(s), ModMatrix.sources[s]) {
    | (Some(i), _) => macroName(i)
    | (None, Some(source)) => source.label
    | (None, None) => ""
    }
  let targetLabel = t => ModMatrix.targets[t]->Option.mapOr("", t => t.label)
  let connectionText = k => {
    let {source, target, amount, via} = slot(k)
    let amountText = (model->ParamModel.def(ModMatrix.amountId(k))).valueText(amount)
    `${sourceLabel(source)} → ${targetLabel(target)}, ${amountText}` ++
    (via > 0 ? ` × ${sourceLabel(via)}` : "")
  }
  let targetText = t =>
    switch ModMatrix.targets->Array.getUnsafe(t) {
    | {law: Knob(id)} => model->ParamModel.longText(id)
    | {label} => label
    }

  let hover = (e, text) => ctx.status->Status.hover(e, text)

  //==============================================================================
  // editing

  let setSlot = (k, source, target, amount, via) => {
    model->ParamModel.gestureSet(ModMatrix.amountId(k), amount)
    model->ParamModel.gestureSet(ModMatrix.viaId(k), via)
    model->ParamModel.gestureSet(ModMatrix.sourceId(k), source)
    model->ParamModel.gestureSet(ModMatrix.targetId(k), target)
  }

  // (a removed connection's options go back to theirs, for the next one in its slot)
  let disconnect = k => {
    setSlot(k, 0., 0., 0., 0.)
    [ModMatrix.holdId(k), ModMatrix.slewId(k), ModMatrix.curveId(k), ModMatrix.stepsId(k)]->Array.forEach(id =>
      if get(id) != 0. {
        model->ParamModel.gestureSet(id, 0.)
      }
    )
  }

  let connect = (source, target) =>
    if slotNumbers->Array.some(k => sourceOf(k) == source && targetOf(k) == target) {
      ctx.toast(`${sourceLabel(source)} already modulates ${targetLabel(target)}`)
    } else {
      switch slotNumbers->Array.find(k => !isUsed(k)) {
      | Some(k) => setSlot(k, Int.toFloat(source), Int.toFloat(target), ModEdit.defaultAmount, 0.)
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
  let listHeight = Style.pageHeight - 2. * margin
  let list = Panel.make(page, ~title="connections", ~x=listX, ~y=margin, ~w=listWidth, ~h=listHeight)
  let count = el("div", ~cls="mcount", ~parent=list.el)
  // the rows scroll between the title and the follow setting
  let rowsBox = el("div", ~cls="mrows", ~parent=list.el)->place(
    0.,
    Grid.padTop - 4.,
    ~w=listWidth - 2.,
    ~h=listHeight - Grid.padTop + 4. - footerHeight,
  )

  // the targets, over the list while a source is being connected: they scroll under the title
  // row when they don't all fit
  let picker = Panel.make(page, ~x=listX, ~y=margin, ~w=listWidth, ~h=list.h)
  picker.el->addClass("picker")
  let pickerTitle = el("div", ~cls="ttl", ~parent=picker.el)
  let picks = el("div", ~cls="picks", ~parent=picker.el)
  picks->setStyle("top", px(pickerTop))
  let wires = Plots.svg(page, {x: 0., y: 0., w: Style.designWidth, h: Style.pageHeight})
  wires->setAttribute("class", Str("wires"))

  //==============================================================================
  // sources

  // by source index
  let sourceChips: Map.t<int, sourceChip> = Map.make()
  let sourceJack = s => sourceChips->Map.get(s)->Option.map(c => c.jack)
  // the macro knobs' labels, by macro
  let macroLabels = []

  let startRef = ref((_: Dom.pointerEvent, _: int, _: element) => ())
  let pickRef = ref((_: int) => ())

  let scopeOf = s => ModScope.sourceScopeOf(get, s)

  sourceOrder->Array.forEach(s => {
    let source = ModMatrix.sources->Array.getUnsafe(s)
    switch macroOf(s) {
    | Some(m) =>
      // a macro: its knob, and a jack to take a cable from
      let knob = Controls.paramControl(ctx, sources.el, ModMatrix.macroId(m + 1), ~x=0., ~y=0., ~w=60., ~label=macroName(m))
      knob
      ->querySelector(".l")
      ->Option.forEach(l => {
        macroLabels->Array.push((m, l))
        l->onMouse(#dblclick, ev => {
          ev->preventDefault
          ev->stopPropagation
          Controls.editInPlace(knob, (ctx.programs->ProgramStore.meta).macroNames[m]->Option.getOr(""), ~commit=name =>
            ctx.programs->ProgramStore.setMacroName(m, name)
          )
        })
      })
      let plug = el("div", ~cls="src plug", ~parent=sources.el)
      plug->setTabIndex(0)
      let jack = el("i", ~cls="jk", ~parent=plug)
      plug->onPointer(#pointerdown, ev => startRef.contents(ev, s, plug))
      plug->onActivate(() => pickRef.contents(s))
      plug->hover(() => `${sourceLabel(s)}: drag to a target to connect it. Double-click the name to rename it.`)
      sourceChips->Map.set(s, {chip: plug, jack, count: None, label: None, knob: Some(knob)})
    | None =>
      let chip = el("div", ~cls="src", ~parent=sources.el)
      chip->setTabIndex(0)
      el("i", ~cls="sw", ~parent=chip)->setStyle("background", sourceColor(s))
      let label = el("span", ~cls="lbl", ~text=sourceLabel(s), ~parent=chip)
      let count = el("b", ~cls="n", ~parent=chip)
      let jack = el("i", ~cls="jk", ~parent=chip)
      chip->onPointer(#pointerdown, ev => startRef.contents(ev, s, chip))
      chip->onActivate(() => pickRef.contents(s))
      chip->hover(() =>
        `${sourceLabel(s)} (${ModScope.scopeHelp(scopeOf(s))}): ${source.help}. Drag it to a target, or click it.`
      )
      sourceChips->Map.set(s, {chip, jack, count: Some(count), label: Some(label), knob: None})
    }
  })

  let heading = (title, help) => {
    let e = el("div", ~cls="grp", ~text=title, ~parent=sources.el)
    e->hover(() => help)
    e
  }
  let eachHeading = heading("per-voice", "Sources each voice has its own of: on something in the voice, every voice moves it its own way")
  let sharedHeading = heading("shared", "Sources every note shares (an LFO is here while its mode is shared)")
  let macroHeading = heading("macros", "Knobs to turn, automate or map: shared by every note")
  let ccHeading = heading("controllers", "The MIDI page's assignable controllers: shared by every note")

  // the groups, laid out again when an LFO's mode, the touch mode or MPE moves a source between them
  let c3 = Grid.fitColumns(sourcesWidth, sourceColumns)
  let c2 = Grid.fitColumns(sourcesWidth, 2)
  let layoutSources = () => {
    let plain = sourceOrder->Array.filter(s => !isMacro(s) && !isController(s))
    let groups = [
      (eachHeading, plain->Array.filter(s => scopeOf(s) == EachNote), c3, sourceColumns),
      (sharedHeading, plain->Array.filter(s => scopeOf(s) == Shared), c3, sourceColumns),
      (macroHeading, sourceOrder->Array.filter(isMacro), c2, 2),
      (ccHeading, sourceOrder->Array.filter(isController), c3, sourceColumns),
    ]
    let y = ref(Grid.padTop - 4.)
    groups->Array.forEach(((head, members, cw, columns)) => {
      head->setStyle("display", members == [] ? "none" : "")
      if members != [] {
        head->place(Grid.padX + 1., y.contents)->ignore
        let g = Grid.make(ctx, sources.el, ~y=y.contents + headingHeight, ~cw)
        members->Array.forEachWithIndex((s, i) => {
          let b = g->Grid.cell(mod(i, columns), i / columns)
          sourceChips
          ->Map.get(s)
          ->Option.forEach(c =>
            switch c.knob {
            | Some(knob) =>
              knob->place(b.x, b.y, ~w=b.w - 24.)->ignore
              c.chip->place(b.x + b.w - 22., b.y, ~w=22., ~h=b.h)->ignore
            | None => c.chip->placeBox(b)->ignore
            }
          )
        })
        let rows = (Array.length(members) + columns - 1) / columns
        y := y.contents + headingHeight + Int.toFloat(rows) * Grid.rowHeight + 4.
      }
    })
  }
  layoutSources()
  model->ParamModel.listenEach(
    ["LFO_1_Sync", "LFO_2_Sync", "LFO_3_Mode", "AftertouchMode", "MPE_On"],
    perFrame(() => {
      layoutSources()
      redraw.contents()
    }),
  )

  //==============================================================================
  // the target picker

  let mode = ref(Closed)
  // by target index
  let targetChips = Map.make()
  let pickTargetRef = ref((_: int) => ())

  // whether the source being connected already reaches target t
  let reaches = t => {
    let s = switch mode.contents {
    | Connect(s) => s
    | Retarget(k) => sourceOf(k)
    | Closed => 0
    }
    slotNumbers->Array.some(k => isUsed(k) && sourceOf(k) == s && targetOf(k) == t)
  }

  targetGroups->Array.forEach(((_, members)) =>
    members->Array.forEach(t => {
      let chip = el("div", ~cls="tgt", ~parent=picks)
      chip->setTabIndex(0)
      el("i", ~cls="jk", ~parent=chip)->ignore
      el("span", ~cls="lbl", ~text=targetLabel(t), ~parent=chip)->ignore
      chip->onPointer(#pointerdown, ev => {
        ev->preventDefault
        if ev->button == 0 {
          pickTargetRef.contents(t)
        }
      })
      chip->onActivate(() => pickTargetRef.contents(t))
      chip->hover(() => targetText(t))
      targetChips->Map.set(t, chip)
    })
  )
  // the sections' headings, and each group's in each section, by section and group
  let sectionHeads = sections->Array.map(((title, _, help)) => {
    let e = el("div", ~cls="psect", ~text=title, ~parent=picks)
    e->hover(() => help)
    e
  })
  let groupHeads = sections->Array.map(_ =>
    targetGroups->Array.map(((title, _)) => el("div", ~cls="grp", ~text=title, ~parent=picks))
  )
  // what the targets scroll over, and what's said when a search finds none
  let picksEnd = el("div", ~parent=picks)
  let nothing = el("div", ~cls="note", ~parent=picks)->place(Grid.padX + 1., 4.)

  let search = el("input", ~cls="psearch", ~parent=picker.el)->place(listWidth - 306., 2., ~w=230.)
  search->setPlaceholder("search, or drop the cable on a target")
  search->setSpellcheck(false)
  // whether to show the targets of the effects that aren't in the rack (a search always does)
  let allEffects = ref(false)
  // the first target a search finds, which Enter picks
  let found = ref(None)

  // Shows the targets a search finds, or else those of the voice and of the effects in the
  // rack: those in each voice, then those on the whole sound, each in their groups, in rows of
  // up to pickerColumns, a copy's on rows of their own.
  let pg = Grid.fitColumns(listWidth - scrollbarWidth, pickerColumns)
  let layoutPicker = () => {
    let words = search->value->String.toLowerCase->String.split(" ")->Array.filter(w => w != "")
    let rack = FxRack.read(get)
    let lane = FxRack.readLane(get)
    let shows = (title, t) =>
      if words == [] {
        allEffects.contents ||
        reaches(t) ||
        effectOf(t)->Option.mapOr(true, e => FxRack.holds(rack, e) || FxRack.holds(lane, e))
      } else {
        let text = String.toLowerCase(`${title} ${targetLabel(t)}`)
        words->Array.every(w => text->String.includes(w))
      }
    found.contents->Option.flatMap(t => targetChips->Map.get(t))->Option.forEach(c => c->removeClass("first"))
    found := None
    targetChips->Map.forEach(c => c->setStyle("display", "none"))
    let y = ref(0.)
    sections->Array.forEachWithIndex(((_, scope, _), si) => {
      let sectionHead = sectionHeads->Array.getUnsafe(si)
      let heads = groupHeads->Array.getUnsafe(si)
      let shownGroups = targetGroups->Array.map(((title, members)) =>
        members->Array.filter(t => ModScope.targetScope(get, t) == scope && shows(title, t))
      )
      heads->Array.forEach(h => h->setStyle("display", "none"))
      if shownGroups->Array.every(g => g == []) {
        sectionHead->setStyle("display", "none")
      } else {
        sectionHead->setStyle("display", "")
        sectionHead->place(Grid.padX + 1., y.contents)->ignore
        y := y.contents + headingHeight + 2.
        shownGroups->Array.forEachWithIndex((shown, i) =>
          if shown != [] {
            let head = heads->Array.getUnsafe(i)
            head->setStyle("display", "")
            head->place(Grid.padX + 1., y.contents)->ignore
            let g = Grid.make(ctx, picks, ~y=y.contents + headingHeight, ~cw=pg)
            let (c, r) = (ref(0), ref(0))
            shown->Array.forEachWithIndex((t, k) => {
              if k > 0 && (c.contents == pickerColumns || copyOf(t) != copyOf(shown->Array.getUnsafe(k - 1))) {
                c := 0
                r := r.contents + 1
              }
              targetChips->Map.get(t)->Option.forEach(chip => {
                chip->setStyle("display", "")
                chip->placeBox(g->Grid.cell(c.contents, r.contents))->ignore
              })
              c := c.contents + 1
            })
            if words != [] && found.contents == None {
              found := shown[0]
            }
            y := y.contents + headingHeight + Int.toFloat(r.contents + 1) * Grid.rowHeight + 6.
          }
        )
        y := y.contents + 4.
      }
    })
    found.contents->Option.flatMap(t => targetChips->Map.get(t))->Option.forEach(c => c->addClass("first"))
    picksEnd->setStyle("height", px(y.contents))
    nothing->setTextContent(y.contents == 0. ? `No target matches “${search->value}”` : "")
  }

  let allButton = Controls.button(
    ctx,
    picker.el,
    "all effects",
    ~x=listWidth - 398.,
    ~y=2.,
    ~w=86.,
    ~status="Show the targets of every effect, not only of those in the rack (a search finds them all)",
    () => (),
  )
  allButton->onMouse(#click, _ => {
    allEffects := !allEffects.contents
    allButton->toggleClass("on", allEffects.contents)
    layoutPicker()
  })
  let cancel = Controls.button(ctx, picker.el, "cancel", ~x=listWidth - 70., ~y=2., ~w=60., () => ())
  pickerTitle->setStyle("width", px(listWidth - 398. - 16.))

  // stops closing the picker on a press outside it
  let closer = ref(None)
  let closePicker = () => {
    mode := Closed
    search->blur
    picker.el->removeClass("on")
    closer.contents->Option.forEach(stop => stop())
    closer := None
    redraw.contents()
  }
  let onEscape = ev =>
    if ev->key == "Escape" && mode.contents != Closed {
      closePicker()
    }
  document->onDocumentKeyDown(onEscape)
  cancel->onMouse(#click, _ => closePicker())

  search->onEvent(#input, _ => {
    picks->setScrollTop(0.)
    layoutPicker()
  })
  // keys stay in the search (the host may otherwise take them as shortcuts)
  search->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Enter" => found.contents->Option.forEach(t => pickTargetRef.contents(t))
    | "Escape" if search->value != "" =>
      search->setValue("")
      layoutPicker()
    | "Escape" => closePicker()
    | _ => ()
    }
  })

  let openPicker = m => {
    let opening = mode.contents == Closed
    mode := m
    pickerTitle->setTextContent(
      switch m {
      | Connect(s) => `connect ${sourceLabel(s)} to …`
      | Retarget(k) => `move ${sourceLabel(sourceOf(k))} → ${targetLabel(targetOf(k))} to …`
      | Closed => ""
      },
    )
    // the targets this source already reaches
    targetChips->Map.forEachWithKey((chip, t) => chip->toggleClass("on", reaches(t)))
    if opening {
      search->setValue("")
    }
    picker.el->addClass("on")
    layoutPicker()
    // from the top, or with the target being moved in view
    switch m {
    | Retarget(k) =>
      targetChips
      ->Map.get(targetOf(k))
      ->Option.forEach(chip => {
        let top = chip->offsetTop - headingHeight
        let bottom = chip->offsetTop + chip->offsetHeight + Grid.padBottom
        let viewTop = picks->scrollTop
        let viewHeight = picks->clientHeight
        if top < viewTop {
          picks->setScrollTop(top)
        } else if bottom > viewTop + viewHeight {
          picks->setScrollTop(bottom - viewHeight)
        }
      })
    | _ if opening => picks->setScrollTop(0.)
    | _ => ()
    }
    search->focus
    // a press outside the picker (and the sources) closes it
    if closer.contents == None {
      closer := Some(onPressOutside([picker.el, sources.el], closePicker))
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
  let within = (e, cx, cy) => {
    let r = e->getBoundingClientRect
    cx >= r.left && cx <= r.left + r.width && cy >= r.top && cy <= r.top + r.height
  }
  // (a target scrolled out of the picker's view isn't there to drop on)
  let targetAt = (cx, cy) =>
    within(picks, cx, cy)
      ? targetChips
        ->Map.entries
        ->Iterator.toArray
        ->Array.find(((_, chip)) => within(chip, cx, cy))
        ->Option.mapOr(-1, Pair.first)
      : -1

  startRef :=
    (ev, s, chip) =>
      if ev->button == 0 {
        ev->preventDefault
        openPicker(Connect(s))
        let start = sourceJack(s)->Option.mapOr({x: 0., y: 0.}, centre)
        let wire = wires->svgEl(
          "path",
          [("class", Str("wire drag")), ("stroke", Str(sourceColor(s))), ("d", Str(""))],
        )
        let (x0, y0) = (ev->clientX, ev->clientY)
        let moved = ref(false)
        let hot = ref(-1)
        let setHot = t => {
          targetChips->Map.get(hot.contents)->Option.forEach(c => c->removeClass("hot"))
          hot := t
          targetChips->Map.get(t)->Option.forEach(c => c->addClass("hot"))
        }
        chip->Controls.capturePointer(
          ev,
          ~onMove=mv => {
            if Math.hypot(mv->clientX - x0, mv->clientY - y0) > 4. {
              moved := true
            }
            let t = targetAt(mv->clientX, mv->clientY)
            setHot(t)
            let p = switch targetChips->Map.get(t) {
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
  // a connection's options: hold, slew, curve and steps, in a box under its button, made the first
  // time it opens

  let optionBoxes: Map.t<int, (element, unit => unit)> = Map.make()
  let openOptions = ref(None)
  let optionsCloser = ref(None)
  let closeOptions = () => {
    openOptions.contents->Option.forEach(k =>
      optionBoxes->Map.get(k)->Option.forEach(((box, _)) => box->removeClass("on"))
    )
    openOptions := None
    optionsCloser.contents->Option.forEach(stop => stop())
    optionsCloser := None
  }
  let optionsWidth = 2. * Grid.columnWidth + 2. * Grid.padX + 2.
  let optionsBox = k => {
    switch optionBoxes->Map.get(k) {
    | Some(b) => b
    | None =>
      let box = el("div", ~cls="mpop", ~parent=page)
      let title = el("div", ~cls="ttl", ~parent=box)
      let g = Grid.make(ctx, box)
      g->Grid.choice(ModMatrix.holdId(k), 0, 0, "hold", ~span=2)
      g->Grid.param(ModMatrix.slewId(k), 0, 1, "slew")
      g->Grid.param(ModMatrix.curveId(k), 1, 1, "curve")
      g->Grid.param(ModMatrix.stepsId(k), 0, 2, "steps")
      // the curve: what the source's value becomes (the line through the middle is straight)
      let plotBox = g->Grid.cell(0, 3, ~span=2, ~rows=2)
      let s = Plots.svg(box, plotBox)
      Plots.background(s, plotBox)
      let straight = s->svgEl("path", [("class", Str("axis"))])
      let curve = s->svgEl("path", [("class", Str("curve"))])
      let note = g->Grid.note("", 0, 5, ~span=2, ~rows=2)
      let draw = () => {
        let {source, target, hold, slew, curve: c, steps} = slot(k)
        let bipolar = ModMatrix.sources[source]->Option.mapOr(false, s => s.bipolar)
        title->setTextContent(`${sourceLabel(source)} → ${targetLabel(target)}`)
        let (w, h) = (plotBox.w - 6., plotBox.h - 7.)
        let at = (x, y) => (3. + w * (bipolar ? (x + 1.) / 2. : x), 3. + h * (bipolar ? (1. - y) / 2. : 1. - y))
        // (finely enough that the steps' risers stand upright)
        let points = Array.fromInitializer(~length=257, i => {
          let x = bipolar ? Int.toFloat(i) / 128. - 1. : Int.toFloat(i) / 256.
          at(x, ModMatrix.stepped(ModMatrix.curved(x, c), steps, ~bipolar))
        })
        curve->setAttribute("d", Str(Plots.pathFrom(points)))
        straight->setAttribute("d", Str(Plots.pathFrom([at(bipolar ? -1. : 0., bipolar ? -1. : 0.), at(1., 1.)])))
        note->setTextContent(
          (hold ? "Each note keeps the value it starts with. " : "") ++
          (slew > 0. ? `Changes take about ${PorridgeParams.slewText(slew)} to arrive. ` : "") ++
          (c == 0. ? "" : c > 0. ? "Small values count for more. " : "Small values count for less. ") ++
          (steps > 0 ? `It snaps to ${Int.toString(steps)} levels. ` : "") ++
          (hold || slew > 0. || c != 0. || steps > 0
            ? ""
            : "Hold latches the value at note-on; slew smooths it; curve bends it; steps snap it to levels."),
        )
      }
      model->ParamModel.listenEach(ModMatrix.slotIds(k), perFrame(draw))
      draw()
      let b = (box, draw)
      optionBoxes->Map.set(k, b)
      b
    }
  }
  let showOptions = (k, anchor) =>
    if openOptions.contents == Some(k) {
      closeOptions()
    } else {
      closeOptions()
      let (box, draw) = optionsBox(k)
      draw()
      let r = anchor->getBoundingClientRect
      let p = toLocal(r.left + r.width, r.top + r.height)
      let h = Grid.padTop + 7. * Grid.rowHeight + Grid.padBottom
      let y = p.y + 2. + h > Style.pageHeight ? p.y - r.height / ctx.scale() - h - 2. : p.y + 2.
      box->place(p.x - optionsWidth, y, ~w=optionsWidth, ~h)->ignore
      box->addClass("on")
      openOptions := Some(k)
      optionsCloser := Some(onPressOutside([box, anchor], closeOptions))
    }

  //==============================================================================
  // the connections

  let rg = Grid.fitColumns(listWidth, 16)
  let rows = slotNumbers->Array.map(k => {
    let row = el("div", ~cls="conn", ~parent=rowsBox)->place(0., 0., ~w=listWidth - 2., ~h=Grid.rowHeight)
    let g = Grid.make(ctx, row, ~y=0., ~cw=rg)

    let source = el("div", ~cls="src", ~parent=row)->placeBox(g->Grid.cell(0, 0, ~span=3))
    source->setTabIndex(0)
    let sw = el("i", ~cls="sw", ~parent=source)
    let sourceName = el("span", ~cls="lbl", ~parent=source)
    el("i", ~cls="jk on", ~parent=source)->ignore
    g->Grid.claim(0, 0, ~span=3, "source")
    source->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        sourceMenu(source, sourceOf(k), s => resource(k, s))
      }
    })
    source->hover(() => connectionText(k) ++ ". Click to change the source.")

    let cableBox = g->Grid.cell(3, 0)
    let cable = Plots.svg(row, cableBox)
    cable->setAttribute("class", Str("wirecell"))
    let wire = cable->svgEl("path", [("class", Str("wire"))])
    // what a per-note source on the whole sound follows
    let follows = el("div", ~cls="mfollow", ~parent=row)->place(cableBox.x - 6., 16., ~w=cableBox.w + 12.)
    g->Grid.claim(3, 0, "cable")

    let target = el("div", ~cls="tgt", ~parent=row)->placeBox(g->Grid.cell(4, 0, ~span=4))
    target->setTabIndex(0)
    el("i", ~cls="jk on", ~parent=target)->ignore
    let targetName = el("span", ~cls="lbl", ~parent=target)
    g->Grid.claim(4, 0, ~span=4, "target")
    target->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        openPicker(Retarget(k))
      }
    })
    target->onActivate(() => openPicker(Retarget(k)))
    target->hover(() => {
      let s = slot(k)
      targetText(targetOf(k)) ++
      (ModScope.followsNotes(get, s)
        ? `. On the whole sound, it follows ${get("MM_Follow") == 0. ? "the newest note" : "every note, by its level"} (see below)`
        : "") ++ ". Click to change the target."
    })

    g->Grid.param(ModMatrix.amountId(k), 8, 0, "amount", ~span=3)
    g->Grid.choice(ModMatrix.viaId(k), 11, 0, "via (scaled by)", ~span=2)
    let options = el("div", ~cls="mopt", ~parent=row)->placeBox(g->Grid.cell(13, 0, ~span=2))
    options->setTabIndex(0)
    g->Grid.claim(13, 0, ~span=2, "options")
    options->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        showOptions(k, options)
      }
    })
    options->onActivate(() => showOptions(k, options))
    options->hover(() => "Hold (latch the value as each note starts), slew and curve")
    g->Grid.button("×", 15, 0, ~status="Remove this connection", () => {
      if openOptions.contents == Some(k) {
        closeOptions()
      }
      disconnect(k)
    })

    row->onMouse(#mouseenter, _ =>
      sourceChips->Map.get(sourceOf(k))->Option.forEach(c => c.chip->addClass("lit"))
    )
    row->onMouse(#mouseleave, _ => sourceChips->Map.forEach(c => c.chip->removeClass("lit")))
    (k, row, sw, sourceName, targetName, wire, follows, options)
  })

  // the last row: add a connection
  let add = el("div", ~cls="addrow", ~parent=rowsBox)
  add->setTabIndex(0)
  el("b", ~text="+", ~parent=add)->ignore
  el("span", ~text="add connection", ~parent=add)->ignore
  el("span", ~cls="sub", ~text="or drag a source from the left onto a target", ~parent=add)->ignore
  let addConnection = () => sourceMenu(add, -1, s => openPicker(Connect(s)))
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    addConnection()
  })
  add->onActivate(addConnection)
  add->hover(() => "Pick a source, then a target")

  let empty = el("div", ~cls="mempty", ~parent=list.el)
  el("div", ~cls="big", ~text="Nothing modulates anything yet.", ~parent=empty)->ignore
  el(
    "div",
    ~text="Drag a source from the left onto a target, or click a source and then a target. Each connection gets an amount, an optional second source that scales it, and options to hold, slew, bend or step it.",
    ~parent=empty,
  )->ignore

  // below the list: what per-note sources follow on the whole sound
  let footer = el("div", ~cls="mfoot", ~parent=list.el)->place(0., listHeight - footerHeight, ~w=listWidth - 2., ~h=footerHeight - 2.)
  Controls.choice(ctx, footer, "MM_Follow", ~x=Grid.padX, ~y=4., ~w=280., ~label="per-note sources on the whole sound follow")
  el(
    "div",
    ~cls="note",
    ~text="Each note has its own LFOs, envelopes and velocity; an effect on the whole sound has one setting, so it takes theirs from the newest note, or from all of them by how loud each is.",
    ~parent=footer,
  )->place(Grid.padX + 290., 2., ~w=listWidth - 2. - 300. - Grid.padX)->ignore

  //==============================================================================
  // drawing

  let draw = () => {
    let used = slotNumbers->Array.filter(isUsed)
    let counts = Map.make()
    used->Array.forEach(k =>
      counts->Map.set(sourceOf(k), counts->Map.get(sourceOf(k))->Option.getOr(0) + 1)
    )
    let followText = ModScope.followText(get)

    // the list, in slot order
    rows->Array.forEach(((k, row, sw, sourceName, targetName, wire, follows, options)) =>
      if isUsed(k) {
        let shown = used->Array.indexOf(k)
        let s = slot(k)
        row->addClass("on")
        row->setStyle("top", px(4. + Int.toFloat(shown) * Grid.rowHeight))
        sw->setStyle("background", sourceColor(s.source))
        sourceName->setTextContent(sourceLabel(s.source))
        targetName->setTextContent(targetLabel(s.target))
        // the cable spans the cell between the two jacks
        let w = rg - Grid.columnGap
        wire->setAttribute("d", Str(cablePath({x: -11., y: 11.}, {x: w + 11., y: 11.}, ~sag=5.)))
        wire->setAttribute("stroke", Str(sourceColor(s.source)))
        wire->setAttribute("class", Str(s.amount == 0. ? "wire muted" : "wire"))
        follows->setTextContent(ModScope.followsNotes(get, s) ? followText : "")
        let parts = [
          s.hold ? Some("latch") : None,
          s.slew > 0. ? Some("slew") : None,
          s.curve != 0. ? Some("curve") : None,
          s.steps > 0 ? Some("steps") : None,
        ]->Array.filterMap(x => x)
        options->setTextContent(parts == [] ? "options" : parts->Array.join(" · "))
        options->toggleClass("set", parts != [])
      } else {
        row->removeClass("on")
      }
    )
    let n = Array.length(used)
    add->setStyle("display", n < ModMatrix.slots ? "flex" : "none")
    add->placeBox({
      x: Grid.padX,
      y: 4. + Int.toFloat(n) * Grid.rowHeight,
      w: listWidth - 2. - 2. * Grid.padX,
      h: Style.controlHeight,
    })->ignore
    empty->setStyle("display", n == 0 ? "block" : "none")
    count->setTextContent(`${Int.toString(n)} of ${Int.toString(ModMatrix.slots)}`)

    // the sources: how many connections each has
    sourceChips->Map.forEachWithKey(({chip, jack, count, label}, s) => {
      let c = counts->Map.get(s)->Option.getOr(0)
      jack->toggleClass("on", c > 0)
      jack->setStyle("background", c > 0 ? sourceColor(s) : "")
      count->Option.forEach(b => {
        b->setTextContent(c > 1 ? Int.toString(c) : "")
        b->setStyle("display", c > 1 ? "block" : "none")
      })
      label->Option.forEach(l => l->setTextContent(sourceLabel(s)))
      let picking = switch mode.contents {
      | Connect(p) => p == s
      | _ => false
      }
      chip->toggleClass("sel", picking)
    })
    macroLabels->Array.forEach(((m, l)) => l->setTextContent(macroName(m)))
  }

  // (a timeout rather than an animation frame: a burst of changes draws once, and the page
  // still updates while the window isn't being painted)
  redraw := coalesce(run => setTimeout(run, 0)->ignore, draw)

  slotNumbers->Array.forEach(k => model->ParamModel.listenEach(ModMatrix.slotIds(k), () => redraw.contents()))
  // what a target's scope depends on: the distortion's place, the rack, and what follows
  model->ParamModel.listenEach(["MM_Follow", "Sat_Mode", ...VoiceLane.ids], () => redraw.contents())
  ctx.programs->ProgramStore.onChanged(() => redraw.contents())
  draw()
}
