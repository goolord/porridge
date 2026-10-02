// Mod page: every route from every source, Oatmeal's own included, as one list of connections.
//
// Left, the sources, a bay of chips with jacks: the per-voice ones (each voice its own), then
// those every voice shares (the macro knobs and controllers among them); an LFO moves between the
// two with its mode. Grab a source's jack (or "add connection") and the targets come up over the
// list, the per-voice ones apart from those on the whole sound: drop the cable on one, or click
// it, or search for one. Click a source's name to select it (ModFocus): its editor opens over the
// lower part of the list (the one the Synth page has: SourceEditors), its rows stand out, and
// what it moves lights up on every page. Escape, or its name again, closes it.
//
// Right, the connections, a row each, source by source: source, cable, target, amount, and for a
// connection of the matrix its "via" source and its options (hold, slew, curve, steps) once
// they're set, which "⋯" adds. Oatmeal's own routings (Modulators: the mod envelopes', the XY
// pad's and the controllers' target slots, and its fixed depths) are rows too, with an "Oatmeal"
// badge: they edit their own parameters, a slot's target picks from Oatmeal's list, and × sets
// the depth to 0 (and frees a slot). The count says how many of the matrix's slots are in use. A
// per-note source on the whole sound follows the newest note, or every note by its level (the
// setting below the list); its cable says which.

open! Web

let hint = "Drag a source's jack onto a target to connect it, or click the jack and then a target. Click a source's name to edit it and light up what it moves. Ctrl+right-click any control for its menu."

let (margin, gap) = (6., Grid.gap)
let sourcesWidth = 342.
let sourceColumns = 3
let headingHeight = 20.
// below the connections: the follow setting
let footerHeight = 36.
// a row's columns, and the selected source's editor's height (as the Synth page's)
let rowColumns = 17
let editorHeight = 235.

// the target picker: its columns, its title row (the targets scroll under it), and the room
// for its scrollbar
let (pickerColumns, pickerTop, scrollbarWidth) = (5, 26., 9.)

let sourceColor = ModEdit.sourceColor

type point = {x: float, y: float}

// a source's element on the left: the chip (or a macro's plug), its jack (none for the pitch
// envelope, which the matrix can't use), and a chip's count of routes and label; a macro's knob
type sourceChip = {
  chip: element,
  jack: option<element>,
  count: option<element>,
  label: option<element>,
  knob: option<element>,
}

// what the target picker is for: connecting a source, or moving connection k
type mode = Closed | Connect(int) | Retarget(int)

// a row of the list, shown for a route at a place in it
type row = {el: element, show: (Modulators.route, int) => unit}

// A hanging cable from a to b.
let cablePath = (a, b, ~sag) => {
  let dx = b.x - a.x
  let f = x => Float.toFixed(x, ~digits=1)
  `M${f(a.x)} ${f(a.y)} C${f(a.x + dx * 0.3)} ${f(a.y + sag)} ${f(b.x - dx * 0.3)} ${f(b.y + sag)} ${f(b.x)} ${f(b.y)}`
}

let sourceOrder = ModEdit.sourceOrder

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

let followHelp = "Each note has its own LFOs, envelopes and velocity; an effect on the whole sound has one setting, so it takes theirs from the newest note, or from all of them by how loud each is."
let emptyHelp = "Each connection gets an amount, and can be scaled by a second source (via) and held, slewed, bent or stepped (⋯). Oatmeal's own routings (the mod envelopes' and XY pad's targets, the LFOs' depths, velocity, aftertouch...) are listed here too as they're set."

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  // (the page shows the selection its own way: ModFocus doesn't dim it)
  page->addClass("modp")
  let slotNumbers = ModMatrix.slotNumbers
  let slot = k => ModMatrix.readSlot(get, k)
  let sourceOf = k => slot(k).source
  let targetOf = k => slot(k).target
  let isUsed = ModEdit.isUsed(get, _)
  let redraw = ref(() => ())

  let macroName = ModEdit.macroName(ctx.programs, _)
  let macroOf = ModEdit.macroOf
  let sourceLabel = s => ModEdit.sourceName(ctx.programs, s)
  let keyLabel = key => ModEdit.keyName(ctx.programs, key)
  let targetLabel = t => ModMatrix.targets[t]->Option.mapOr("", t => t.label)
  let connectionText = k => {
    let {source, target, amount, via} = slot(k)
    let amountText = (model->ParamModel.def(ModMatrix.amountId(k))).valueText(amount)
    `${sourceLabel(source)} → ${targetLabel(target)}, ${amountText}` ++ (via > 0 ? ` × ${sourceLabel(via)}` : "")
  }
  // (in the route's words, not the parameter's own name)
  let targetText = t =>
    switch ModMatrix.targets->Array.getUnsafe(t) {
    | {law: Knob(id), label} => `${label}: ${(model->ParamModel.def(id)).valueText(get(id))}`
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

  let connect = (source, target) =>
    if slotNumbers->Array.some(k => sourceOf(k) == source && targetOf(k) == target) {
      ctx.toast(`${sourceLabel(source)} already modulates ${targetLabel(target)}`)
    } else {
      switch slotNumbers->Array.find(k => !isUsed(k)) {
      | Some(k) =>
        setSlot(k, Int.toFloat(source), Int.toFloat(target), ModEdit.defaultAmount, 0.)
        model->ParamModel.nameStep(`${sourceLabel(source)} → ${targetLabel(target)}`)
      | None => ctx.toast(`All ${Int.toString(ModMatrix.slots)} modulation slots are in use`)
      }
    }

  let retarget = (k, target) => model->ParamModel.gestureSet(ModMatrix.targetId(k), Int.toFloat(target))
  let resource = (k, source) => model->ParamModel.gestureSet(ModMatrix.sourceId(k), Int.toFloat(source))

  let sourceMenu = (anchor, current, onPick) => ctx.menu->Menu.show(anchor, ModEdit.sourceItems(ctx.programs), current, onPick)

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
  hover(count, () => "How many of the matrix's connections are in use (Oatmeal's own routings don't count)")
  // the rows scroll between the title and the follow setting (or the selected source's editor)
  let rowsTop = Grid.padTop - 4.
  let rowsBox = el("div", ~cls="mrows", ~parent=list.el)->place(0., rowsTop, ~w=listWidth - 2.)
  let fitRows = (~editor) =>
    rowsBox->setStyle("height", px((editor ? listHeight - editorHeight : listHeight - footerHeight) - rowsTop - 2.))
  fitRows(~editor=false)

  // the targets, over the list while a source is being connected: they scroll under the title
  // row when they don't all fit
  let picker = Panel.make(page, ~x=listX, ~y=margin, ~w=listWidth, ~h=list.h)
  picker.el->addClass("picker")
  let pickerTitle = el("div", ~cls="ttl", ~parent=picker.el)
  let picks = el("div", ~cls="picks", ~parent=picker.el)
  picks->setStyle("top", px(pickerTop))

  // the selected source's editor, over the lower part of the list (the cables draw over it)
  let editor = Controls.block(page, "", ~x=listX, ~y=margin + listHeight - editorHeight, ~w=listWidth, ~h=editorHeight)
  editor->addClass("srced")
  let editorTitle = el("div", ~cls="ttl", ~parent=editor)

  let wires = Plots.svg(page, {x: 0., y: 0., w: Style.designWidth, h: Style.pageHeight})
  wires->setAttribute("class", Str("wires"))

  //==============================================================================
  // sources

  // the bay's sources, by key: the matrix's, and the pitch envelope
  let bayKeys = Lazy.get(Modulators.sourceKeys)
  let indexOf = key => ModMatrix.sourceIndex(key)
  let sourceChips: Map.t<string, sourceChip> = Map.make()
  // the macro knobs' labels, by macro
  let macroLabels = []

  // (a press on a source: on its jack, or not)
  let pressRef = ref((_: Dom.pointerEvent, _: string, _: element, _: bool) => ())
  let pickRef = ref((_: int) => ())

  let scopeOf = key => key == ModEdit.pitchEnvKey ? ModMatrix.EachNote : ModScope.sourceScopeOf(get, indexOf(key))
  let helpOf = key =>
    key == ModEdit.pitchEnvKey
      ? "the pitch envelope (the Synth page's pitch env): Oatmeal's own, on the pitch alone"
      : ModMatrix.sources[indexOf(key)]->Option.mapOr("", s => s.help)

  bayKeys->Array.forEach(key => {
    let s = indexOf(key)
    switch macroOf(s) {
    | Some(m) =>
      // a macro: its knob (whose name selects it), and a jack to take a cable from
      let knob = Controls.paramControl(ctx, sources.el, ModMatrix.macroId(m + 1), ~x=0., ~y=0., ~w=60., ~label=macroName(m))
      knob
      ->querySelector(".l")
      ->Option.forEach(l => {
        macroLabels->Array.push((m, l))
        l->onMouse(#click, _ => ModFocus.select(model, key))
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
      plug->onPointer(#pointerdown, ev => pressRef.contents(ev, key, plug, true))
      plug->onActivate(() => pickRef.contents(s))
      plug->hover(() => `${sourceLabel(s)}: drag to a target to connect it. Click its name to see what it moves; double-click the name to rename it.`)
      sourceChips->Map.set(key, {chip: plug, jack: Some(jack), count: None, label: None, knob: Some(knob)})
    | None =>
      let chip = el("div", ~cls="src", ~parent=sources.el)
      chip->setTabIndex(0)
      el("i", ~cls="sw", ~parent=chip)->setStyle("background", ModEdit.keyColour(key))
      let label = el("span", ~cls="lbl", ~text=keyLabel(key), ~parent=chip)
      let count = el("b", ~cls="n", ~parent=chip)
      let jack = s > 0 ? Some(el("i", ~cls="jk", ~parent=chip)) : None
      chip->toggleClass("nojack", jack == None)
      chip->onPointer(#pointerdown, ev =>
        pressRef.contents(ev, key, chip, jack->Option.mapOr(false, j => j->contains(ev->originalTarget)))
      )
      chip->onActivate(() => ModFocus.toggle(model, key))
      chip->hover(() =>
        `${keyLabel(key)} (${ModScope.scopeHelp(scopeOf(key))}): ${helpOf(key)}. ` ++ (
          jack == None ? "Click to edit it." : "Click its name to edit it and see what it moves; drag its jack to a target."
        )
      )
      sourceChips->Map.set(key, {chip, jack, count: Some(count), label: Some(label), knob: None})
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
  let ccHeading = heading("controllers", "The Play page's assignable controllers: shared by every note")

  // the groups, laid out again when an LFO's mode, the touch mode or MPE moves a source between them
  let c3 = Grid.fitColumns(sourcesWidth, sourceColumns)
  // (the macros in a row of four)
  let c4 = Grid.fitColumns(sourcesWidth, ModMatrix.macros)
  let layoutSources = () => {
    let kind = f => bayKeys->Array.filter(key => f(indexOf(key)))
    let plain = kind(s => !isMacro(s) && !isController(s))
    let groups = [
      (eachHeading, plain->Array.filter(key => scopeOf(key) == EachNote), c3, sourceColumns),
      (sharedHeading, plain->Array.filter(key => scopeOf(key) == Shared), c3, sourceColumns),
      (macroHeading, kind(isMacro), c4, ModMatrix.macros),
      (ccHeading, kind(isController), c3, sourceColumns),
    ]
    let y = ref(Grid.padTop - 4.)
    groups->Array.forEach(((head, members, cw, columns)) => {
      head->setStyle("display", members == [] ? "none" : "")
      if members != [] {
        head->place(Grid.padX + 1., y.contents)->ignore
        let g = Grid.make(ctx, sources.el, ~y=y.contents + headingHeight, ~cw)
        members->Array.forEachWithIndex((key, i) => {
          let b = g->Grid.cell(mod(i, columns), i / columns)
          sourceChips
          ->Map.get(key)
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
  // (an Escape that closes the picker is spent: it leaves the selected source alone)
  let onEscape = ev =>
    if ev->key == "Escape" && mode.contents != Closed {
      ev->stopImmediatePropagation
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
  // pressing a source: its jack takes a cable to a target (a click opens the targets to click
  // one), its name selects it, unless the press goes on to drag a cable from there

  let toLocal = (cx, cy) => {
    let r = wires->getBoundingClientRect
    let s = ctx.scale()
    {x: (cx - r.left) / s, y: (cy - r.top) / s}
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

  // A cable from source s, with the targets up: where it goes as the pointer moves, and what
  // letting go does (dropped on nothing, it closes them; a click leaves them open, to click one).
  let cable = s => {
    openPicker(Connect(s))
    let start =
      sourceChips
      ->Map.get((ModMatrix.sources->Array.getUnsafe(s)).key)
      ->Option.flatMap(c => c.jack)
      ->Option.mapOr({x: 0., y: 0.}, jack => {
        let r = jack->getBoundingClientRect
        toLocal(r.left + r.width / 2., r.top + r.height / 2.)
      })
    let wire = wires->svgEl("path", [("class", Str("wire drag")), ("stroke", Str(sourceColor(s))), ("d", Str(""))])
    let hot = ref(-1)
    let setHot = t => {
      targetChips->Map.get(hot.contents)->Option.forEach(c => c->removeClass("hot"))
      hot := t
      targetChips->Map.get(t)->Option.forEach(c => c->addClass("hot"))
    }
    let move = (cx, cy) => {
      let t = targetAt(cx, cy)
      setHot(t)
      let p = switch targetChips->Map.get(t) {
      | Some(c) => {
          let r = c->getBoundingClientRect
          toLocal(r.left + 13. * ctx.scale(), r.top + r.height / 2.)
        }
      | None => toLocal(cx, cy)
      }
      wire->setAttribute("d", Str(cablePath(start, p, ~sag=18.)))
    }
    let up = (~clicked) => {
      wire->remove
      let t = hot.contents
      setHot(-1)
      if t > 0 {
        pickTargetRef.contents(t)
      } else if !clicked {
        closePicker()
      }
    }
    (move, up)
  }

  pressRef :=
    (ev, key, chip, onJack) =>
      if ev->button == 0 {
        ev->preventDefault
        let s = indexOf(key)
        let (x0, y0) = (ev->clientX, ev->clientY)
        let moved = ref(false)
        // the cable, once there is one: from the jack at once, from the name once it moves
        let drag = ref(onJack && s > 0 ? Some(cable(s)) : None)
        chip->Controls.capturePointer(
          ev,
          ~onMove=mv => {
            if Math.hypot(mv->clientX - x0, mv->clientY - y0) > 4. {
              moved := true
              if drag.contents == None && s > 0 {
                drag := Some(cable(s))
              }
            }
            drag.contents->Option.forEach(((move, _)) => move(mv->clientX, mv->clientY))
          },
          ~onUp=() =>
            switch drag.contents {
            | Some((_, up)) => up(~clicked=!moved.contents)
            | None => ModFocus.toggle(model, key)
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
    redraw.contents()
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
      box->place(Math.max(p.x - optionsWidth, listX), y, ~w=optionsWidth, ~h)->ignore
      box->addClass("on")
      openOptions := Some(k)
      optionsCloser := Some(onPressOutside([box, anchor], closeOptions))
      redraw.contents()
    }

  //==============================================================================
  // the rows

  let rg = Grid.fitColumns(listWidth, rowColumns)
  let selected = () => ModFocus.current(model)

  // What every row has: its source, the cable, and its target, in their cells of grid g. The
  // returned function shows a route in them.
  let rowFrame = (row, g: Grid.t) => {
    let source = el("div", ~cls="src", ~parent=row)->placeBox(g->Grid.cell(0, 0, ~span=3))
    source->setTabIndex(0)
    let sw = el("i", ~cls="sw", ~parent=source)
    let sourceName = el("span", ~cls="lbl", ~parent=source)
    el("i", ~cls="jk on", ~parent=source)->ignore
    g->Grid.claim(0, 0, ~span=3, "source")

    let cableBox = g->Grid.cell(3, 0)
    let cableSvg = Plots.svg(row, cableBox)
    cableSvg->setAttribute("class", Str("wirecell"))
    let wire = cableSvg->svgEl("path", [("class", Str("wire"))])
    // what a per-note source on the whole sound follows
    let follows = el("div", ~cls="mfollow", ~parent=row)->place(cableBox.x - 6., 16., ~w=cableBox.w + 12.)
    g->Grid.claim(3, 0, "cable")

    let target = el("div", ~cls="tgt", ~parent=row)->placeBox(g->Grid.cell(4, 0, ~span=4))
    target->setTabIndex(0)
    el("i", ~cls="jk on", ~parent=target)->ignore
    let targetName = el("span", ~cls="lbl", ~parent=target)
    g->Grid.claim(4, 0, ~span=4, "target")

    let show = (r: Modulators.route, i, ~muted, ~follow) => {
      let colour = ModEdit.keyColour(r.key)
      row->addClass("on")
      row->setStyle("top", px(4. + Int.toFloat(i) * Grid.rowHeight))
      row->toggleClass("sel", selected() == Some(r.key))
      sw->setStyle("background", colour)
      sourceName->setTextContent(keyLabel(r.key))
      targetName->setTextContent(r.label)
      // the cable spans the cell between the two jacks
      let w = rg - Grid.columnGap
      wire->setAttribute("d", Str(cablePath({x: -11., y: 11.}, {x: w + 11., y: 11.}, ~sag=5.)))
      wire->setAttribute("stroke", Str(colour))
      wire->setAttribute("class", Str(muted ? "wire muted" : "wire"))
      follows->setTextContent(follow)
    }
    (source, target, show)
  }

  // a connection of the matrix, in slot k
  let matrixRow = k => {
    let row = el("div", ~cls="conn", ~parent=rowsBox)->place(0., 0., ~w=listWidth - 2., ~h=Grid.rowHeight)
    let g = Grid.make(ctx, row, ~y=0., ~cw=rg)
    let (source, target, showFrame) = rowFrame(row, g)
    source->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        sourceMenu(source, sourceOf(k), s => resource(k, s))
      }
    })
    source->hover(() => connectionText(k) ++ ". Click to change the source.")
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
    // the via source and the options, while they're set (or the options' box is open); the via
    // source by the name its program gives a macro
    let viaId = ModMatrix.viaId(k)
    let via = el("div", ~cls="p ch", ~parent=row)->placeBox(g->Grid.cell(11, 0, ~span=2))
    via->setTabIndex(0)
    g->Grid.claim(11, 0, ~span=2, "via")
    el("span", ~cls="l", ~text="via (scaled by)", ~parent=via)->ignore
    let viaName = el("span", ~cls="v", ~parent=via)
    let pickVia = anchor =>
      ctx.menu->Menu.show(anchor, [{Menu.label: "none", value: 0}, ...ModEdit.sourceItems(ctx.programs)], slot(k).via, s =>
        model->ParamModel.gestureSet(viaId, Int.toFloat(s))
      )
    via->onPointer(#pointerdown, ev => {
      ev->preventDefault
      switch ev->button {
      | 0 => pickVia(via)
      | 2 => model->ParamModel.gestureSet(viaId, 0.)
      | _ => ()
      }
    })
    via->suppressContextMenu
    via->onActivate(() => pickVia(via))
    via->hover(() =>
      `Scaled by ${sourceLabel(slot(k).via)}: the amount times its value. Click to change it, right-click for none.`
    )
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
    options->hover(() => "Hold (latch the value as each note starts), slew, curve and steps")
    // "⋯": the via source and the options, to add them
    let more = el("div", ~cls="mopt mmore", ~text="⋯", ~parent=row)->placeBox(g->Grid.cell(15, 0))
    more->setTabIndex(0)
    g->Grid.claim(15, 0, "more")
    let moreMenu = () =>
      ctx.menu->Menu.show(
        more,
        [
          {
            Menu.label: "Scale it by another source (via) ›",
            value: 0,
            hint: "The connection's amount is multiplied by a second source: the mod wheel, velocity, an envelope...",
          },
          {Menu.label: "Hold, slew, curve, steps…", value: 1, hint: "Latch it at note-on, smooth it, bend it or step it"},
        ],
        -1,
        v =>
          v == 0 ? pickVia(more) : showOptions(k, options->offsetParent == None ? more : options),
      )
    more->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        moreMenu()
      }
    })
    more->onActivate(moreMenu)
    more->hover(() => "Scale it by a second source (via), or hold, slew, bend or step it")
    g->Grid.button("×", 16, 0, ~status="Remove this connection", () => {
      if openOptions.contents == Some(k) {
        closeOptions()
      }
      Destinations.disconnect(model, k)
    })

    let show = (r: Modulators.route, i) => {
      let s = slot(k)
      showFrame(r, i, ~muted=s.amount == 0., ~follow=ModScope.followsNotes(get, s) ? ModScope.followText(get) : "")
      via->setStyle("display", s.via > 0 ? "" : "none")
      viaName->setTextContent(sourceLabel(s.via))
      let parts = [
        s.hold ? Some("latch") : None,
        s.slew > 0. ? Some("slew") : None,
        s.curve != 0. ? Some("curve") : None,
        s.steps > 0 ? Some("steps") : None,
      ]->Array.filterMap(x => x)
      options->setTextContent(parts == [] ? "options" : parts->Array.join(" · "))
      options->toggleClass("set", parts != [])
      options->setStyle("display", parts != [] || openOptions.contents == Some(k) ? "" : "none")
    }
    {el: row, show}
  }
  let matrixRows = slotNumbers->Array.map(k => (k, matrixRow(k)))->Map.fromArray

  // one of Oatmeal's own routings, by its amount parameter (made when it's first shown)
  let builtInRow = amount => {
    let row = el("div", ~cls="conn builtin", ~parent=rowsBox)->place(0., 0., ~w=listWidth - 2., ~h=Grid.rowHeight)
    let g = Grid.make(ctx, row, ~y=0., ~cw=rg)
    let (source, target, showFrame) = rowFrame(row, g)
    let current = ref(None)
    let routeText = (r: Modulators.route) =>
      `${keyLabel(r.key)} → ${r.label}: ${Modulators.amountText(model, r)}`
    source->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        current.contents->Option.forEach((r: Modulators.route) => ModFocus.toggle(model, r.key))
      }
    })
    source->hover(() =>
      current.contents->Option.mapOr("", r => routeText(r) ++ `. Click to select ${keyLabel(r.key)}.`)
    )
    // a slot's target picks from Oatmeal's list
    let pickTarget = () =>
      current.contents->Option.forEach((r: Modulators.route) =>
        switch r.via {
        | Slot(id) =>
          let names = Controls.namesOf(model->ParamModel.def(id))
          ctx.menu->Menu.show(
            target,
            names->Array.mapWithIndex((label, value) => {Menu.label, value})->Array.filter(i => i.value > 0),
            Float.toInt(get(id)),
            v => model->ParamModel.gestureSet(id, Int.toFloat(v)),
          )
        | Depth | Connection(_) => ()
        }
      )
    target->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        pickTarget()
      }
    })
    target->onActivate(pickTarget)
    target->hover(() =>
      current.contents->Option.mapOr("", (r: Modulators.route) =>
        switch r.via {
        | Slot(_) => `${r.label}: one of ${keyLabel(r.key)}'s own target slots. Click to pick another from Oatmeal's list.`
        | _ => `${r.label}: ${keyLabel(r.key)}'s own depth on it, which only its amount changes`
        }
      )
    )
    g->Grid.at(8, 0, ~span=3, amount, b => {
      let def = model->ParamModel.def(amount)
      // (the pitch envelope's is its switch)
      def.names != None
        ? Controls.toggle(ctx, row, amount, ~x=b.x, ~y=b.y, ~w=b.w, ~label="on")
        : Controls.param(ctx, row, amount, ~x=b.x, ~y=b.y, ~w=b.w, ~label="amount")
    })
    g->Grid.at(11, 0, ~span=2, "the badge", b => {
      let badge = el("div", ~cls="mbadge", ~text="Oatmeal", ~parent=row)->place(b.x + 2., b.y + 4.)
      hover(badge, () => "Oatmeal's own routing: it has a parameter of its own, which Oatmeal programs keep")
    })
    g->Grid.button("×", 16, 0, ~status="Take it out: its amount to 0, and a slot freed", () =>
      current.contents->Option.forEach(r => Destinations.takeOut(model, r))
    )
    let show = (r: Modulators.route, i) => {
      current := Some(r)
      showFrame(r, i, ~muted=get(r.amount) == 0., ~follow="")
      target->toggleClass("fixed", r.via == Depth)
    }
    {el: row, show}
  }
  let builtInRows: Map.t<string, row> = Map.make()
  let builtInRowOf = amount =>
    switch builtInRows->Map.get(amount) {
    | Some(r) => r
    | None =>
      let r = builtInRow(amount)
      builtInRows->Map.set(amount, r)
      r
    }

  // the last row: add a connection
  let add = el("div", ~cls="addrow", ~parent=rowsBox)
  add->setTabIndex(0)
  el("b", ~text="+", ~parent=add)->ignore
  el("span", ~text="add connection", ~parent=add)->ignore
  el("span", ~cls="sub", ~text="or drag a source's jack onto a target", ~parent=add)->ignore
  let addConnection = () => sourceMenu(add, -1, s => openPicker(Connect(s)))
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    addConnection()
  })
  add->onActivate(addConnection)
  add->hover(() => "Pick a source, then a target")

  let empty = el("div", ~cls="mempty", ~parent=list.el)
  el("div", ~cls="big", ~text="Nothing moves anything yet.", ~parent=empty)->ignore
  let emptyLine = el("div", ~cls="msub", ~parent=empty)
  el("span", ~text="Drag a source's jack onto a target.", ~parent=emptyLine)->ignore
  let emptyHelpButton = el("button", ~cls="btn help", ~text="?", ~parent=emptyLine)
  let emptyTip = el("div", ~cls="tip", ~text=emptyHelp, ~parent=empty)
  emptyHelpButton->onMouse(#mouseenter, _ => emptyTip->addClass("on"))
  emptyHelpButton->onMouse(#mouseleave, _ => emptyTip->removeClass("on"))

  // below the list: what per-note sources follow on the whole sound
  let footer = el("div", ~cls="mfoot", ~parent=list.el)->place(0., listHeight - footerHeight, ~w=listWidth - 2., ~h=footerHeight - 2.)
  Controls.choice(ctx, footer, "MM_Follow", ~x=Grid.padX, ~y=4., ~w=280., ~label="per-note sources on the whole sound follow")
  Controls.help(footer, followHelp, ~x=Grid.padX + 284., ~y=4., ~size=Style.controlHeight, ~tipW=360., ~left=true, ~above=true)

  //==============================================================================
  // the selected source's editor

  let editorBodies: Map.t<string, element> = Map.make()
  let editorBody = key =>
    switch editorBodies->Map.get(key) {
    | Some(b) => b
    | None =>
      let body = el("div", ~cls="pbody", ~parent=editor)
      if SourceEditors.keys->Array.includes(key) {
        SourceEditors.make(ctx, body, key, ~w=listWidth, ~h=editorHeight)
      } else {
        // what it is, and what it moves
        let s = indexOf(key)
        el(
          "div",
          ~cls="note wrap mdesc",
          ~text=`${String.toUpperCase(String.slice(helpOf(key), ~start=0, ~end=1))}${String.slice(helpOf(key), ~start=1)} (${ModScope.scopeHelp(scopeOf(key))}).`,
          ~parent=body,
        )->place(Grid.padX + 2., Grid.padTop - 2., ~w=listWidth - 2. * Grid.padX - 4.)->ignore
        let top = Grid.padTop + 20.
        let top = if isController(s) {
          // (the controller it listens to, as on the Play page)
          let cc = "CC" ++ String.slice(key, ~start=2)
          Controls.param(ctx, body, cc, ~x=Grid.padX, ~y=top, ~w=SourceEditors.chipsWidth, ~label="MIDI controller")
          top + Grid.rowHeight
        } else {
          top
        }
        Destinations.make(
          ctx,
          body,
          key,
          {x: Grid.padX, y: top, w: listWidth - 2. * Grid.padX - 2., h: editorHeight - top - 8.},
          ~wide=true,
        )
      }
      editorBodies->Map.set(key, body)
      body
    }
  let editorClose = Controls.button(ctx, editor, "×", ~x=listWidth - 30., ~y=2., ~w=22., ~cls="xclose", ~status="Close it (Escape)", () =>
    ModFocus.clear(model)->ignore
  )
  editorClose->setStyle("zIndex", "3")
  let shownKey = ref(None)
  let syncSelection = () => {
    let key = selected()->Option.filter(key => bayKeys->Array.includes(key))
    if key != shownKey.contents {
      shownKey := key
      editorBodies->Map.forEach(b => b->removeClass("on"))
      switch key {
      | Some(key) =>
        editorBody(key)->addClass("on")
        editorTitle->setTextContent(keyLabel(key))
        editor->addClass("on")
        fitRows(~editor=true)
      | None =>
        editor->removeClass("on")
        fitRows(~editor=false)
      }
    }
    redraw.contents()
  }
  ModFocus.watch(model, syncSelection)

  //==============================================================================
  // drawing

  // (the rows the selected source has, to scroll them into view when it's newly selected)
  let scrolledFor = ref(None)
  let draw = () => {
    let routes = Modulators.all(get)
    rowsBox->querySelectorAll(":scope > .conn")->nodesToArray->Array.forEach(r => r->removeClass("on"))
    routes->Array.forEachWithIndex((r, i) =>
      switch r.via {
      | Connection(k) => matrixRows->Map.get(k)->Option.forEach(row => row.show(r, i))
      | Slot(_) | Depth => builtInRowOf(r.amount).show(r, i)
      }
    )
    let n = Array.length(routes)
    let used = slotNumbers->Array.filter(isUsed)->Array.length
    add->setStyle("display", used < ModMatrix.slots ? "flex" : "none")
    add->placeBox({
      x: Grid.padX,
      y: 4. + Int.toFloat(n) * Grid.rowHeight,
      w: listWidth - 2. - 2. * Grid.padX,
      h: Style.controlHeight,
    })->ignore
    empty->setStyle("display", n == 0 ? "block" : "none")
    count->setTextContent(`${Int.toString(used)} of ${Int.toString(ModMatrix.slots)}`)
    let picked = selected()
    rowsBox->toggleClass("focus", picked != None)
    if picked != scrolledFor.contents {
      scrolledFor := picked
      picked->Option.forEach(key =>
        switch routes->Array.findIndex(r => r.key == key) {
        | i if i >= 0 => rowsBox->setScrollTop(Int.toFloat(i) * Grid.rowHeight)
        | _ => ()
        }
      )
    }

    // the sources: how many routes each has
    let counts = Map.make()
    routes->Array.forEach(r => counts->Map.set(r.key, counts->Map.get(r.key)->Option.getOr(0) + 1))
    sourceChips->Map.forEachWithKey(({chip, jack, count, label}, key) => {
      let c = counts->Map.get(key)->Option.getOr(0)
      jack->Option.forEach(jack => {
        jack->toggleClass("on", c > 0)
        jack->setStyle("background", c > 0 ? ModEdit.keyColour(key) : "")
      })
      count->Option.forEach(b => {
        b->setTextContent(c > 1 ? Int.toString(c) : "")
        b->setStyle("display", c > 1 ? "block" : "none")
      })
      label->Option.forEach(l => l->setTextContent(keyLabel(key)))
      let picking = switch mode.contents {
      | Connect(p) => indexOf(key) == p
      | _ => false
      }
      chip->toggleClass("pick", picking)
      chip->toggleClass("sel", picked == Some(key))
    })
    macroLabels->Array.forEach(((m, l)) => l->setTextContent(macroName(m)))
    shownKey.contents->Option.forEach(key => editorTitle->setTextContent(keyLabel(key)))
  }

  // (a timeout rather than an animation frame: a burst of changes draws once, and the page
  // still updates while the window isn't being painted)
  redraw := coalesce(run => setTimeout(run, 0)->ignore, draw)

  model->ParamModel.listenEach(Lazy.get(Modulators.routingIds), () => redraw.contents())
  slotNumbers->Array.forEach(k => model->ParamModel.listenEach(ModMatrix.slotIds(k), () => redraw.contents()))
  // what a target's scope depends on: the distortion's place, the rack, and what follows
  model->ParamModel.listenEach(["MM_Follow", "Sat_Mode", ...VoiceLane.ids], () => redraw.contents())
  ctx.programs->ProgramStore.onChanged(() => redraw.contents())
  draw()
}
