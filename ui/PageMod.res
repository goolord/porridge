// Mod page: the modulation matrix as a patch bay. Sources on the left, targets in groups on
// the right; drag from one to the other to connect them, and the connection's cable hangs
// between the two. The connections are listed with their amount and "via" source, and the
// four macro knobs sit below.

open! Web

let hint = "Drag from a source to a target to connect them. Click a cable to select it, right-click it to remove it. Double-click a macro's name to rename it."

let (margin, gap) = (6., Grid.gap)
let patchWidth = 760.
let rowHeight = 19.5
let top = 28.
let sourceJackX = 160.
let columnX = [300., 415., 530., 645.]
let columns = [["voice", "osc"], ["filter", "lfo"], ["fx"], ["eq"]]
let jackRadius = 5.
let defaultAmount = 0.25

type point = {x: float, y: float}

// The jack of each source (1..), at the right end of its row.
let sourceJacks =
  ModMatrix.sources->Array.mapWithIndex((_, i) => {
    x: sourceJackX,
    y: top + Int.toFloat(i - 1) * rowHeight + rowHeight / 2.,
  })

// Target rows: group headings and targets, column by column.
type row = Heading(string) | Target(int)

let targetRows = columns->Array.map(groups =>
  groups->Array.flatMap(group => {
    let title = ModMatrix.groups->Array.find(((key, _)) => key == group)->Option.mapOr(group, Pair.second)
    let members =
      ModMatrix.targets
      ->Array.mapWithIndex((t, i) => (t, i))
      ->Array.filter(((t, _)) => t.group == group)
      ->Array.map(((_, i)) => Target(i))
    [Heading(title), ...members]
  })
)

let targetJacks = {
  let jacks = Array.make(~length=Array.length(ModMatrix.targets), {x: 0., y: 0.})
  targetRows->Array.forEachWithIndex((rows, c) =>
    rows->Array.forEachWithIndex((row, r) =>
      switch row {
      | Target(i) =>
        jacks->Array.setUnsafe(
          i,
          {
            x: columnX->Array.getUnsafe(c),
            y: top + Int.toFloat(r) * rowHeight + rowHeight / 2.,
          },
        )
      | Heading(_) => ()
      }
    )
  )
  jacks
}

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

// A hanging cable from a to b.
let cablePath = (a, b) => {
  let dx = b.x - a.x
  let dy = b.y - a.y
  let sag = 16. + 0.12 * Math.sqrt(dx * dx + dy * dy)
  let f = x => Float.toFixed(x, ~digits=1)
  `M${f(a.x)} ${f(a.y)} C${f(a.x + dx * 0.3)} ${f(a.y + sag)} ${f(b.x - dx * 0.3)} ${f(b.y + sag)} ${f(b.x)} ${f(b.y)}`
}

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let slotNumbers = Array.fromInitializer(~length=ModMatrix.slots, i => i + 1)
  let sourceOf = k => Float.toInt(get(ModMatrix.sourceId(k)))
  let targetOf = k => Float.toInt(get(ModMatrix.targetId(k)))
  let isUsed = k => sourceOf(k) > 0 && targetOf(k) > 0
  let selected = ref(None)
  let redraw = ref(() => ())

  let macroName = i => {
    let name = (ctx.programs->ProgramStore.meta).macroNames[i]->Option.getOr("")
    name == "" ? `macro ${Int.toString(i + 1)}` : name
  }
  let sourceLabel = s =>
    switch ModMatrix.sources[s] {
    | Some({key}) if String.startsWith(key, "macro") => macroName(s - ModMatrix.sourceIndex("macro1"))
    | Some(source) => source.label
    | None => ""
    }
  let targetLabel = t => ModMatrix.targets[t]->Option.mapOr("", t => t.label)
  let connectionText = k => {
    let via = Float.toInt(get(ModMatrix.viaId(k)))
    let amount = model->ParamModel.def(ModMatrix.amountId(k))
    `${sourceLabel(sourceOf(k))} → ${targetLabel(targetOf(k))}, ${amount.valueText(
        get(ModMatrix.amountId(k)),
      )}` ++ (via > 0 ? ` × ${sourceLabel(via)}` : "")
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

  let select = k => {
    selected := k
    redraw.contents()
  }

  let disconnect = k => {
    setSlot(k, 0., 0., 0., 0.)
    if selected.contents == Some(k) {
      selected := None
    }
    redraw.contents()
  }

  let connect = (source, target) =>
    switch slotNumbers->Array.find(k => sourceOf(k) == source && targetOf(k) == target) {
    | Some(k) => select(Some(k))
    | None =>
      switch slotNumbers->Array.find(k => !isUsed(k)) {
      | Some(k) =>
        setSlot(k, Int.toFloat(source), Int.toFloat(target), defaultAmount, 0.)
        select(Some(k))
      | None => ctx.toast(`All ${Int.toString(ModMatrix.slots)} modulation slots are in use`)
      }
    }

  //==============================================================================
  // patch bay

  let patch = Panel.make(page, ~title="patch", ~x=margin, ~y=margin, ~w=patchWidth, ~h=Style.pageHeight - 2. * margin)
  let bay = el("div", ~cls="bay", ~parent=patch.el)->place(0., 0., ~w=patchWidth, ~h=patch.h)

  // source labels (the macro names can change)
  let sourceLabels = ModMatrix.sources->Array.mapWithIndex((source, s) =>
    if s == 0 {
      None
    } else {
      let jack = sourceJacks->Array.getUnsafe(s)
      let e =
        el("div", ~cls="jl src", ~text=sourceLabel(s), ~parent=bay)->place(
          8.,
          jack.y - rowHeight / 2.,
          ~w=sourceJackX - 16.,
          ~h=rowHeight,
        )
      e->hover(() => `${sourceLabel(s)}: ${ModMatrix.sourceHelp(source.key)}`)
      if String.startsWith(source.key, "macro") {
        e->onMouse(#dblclick, ev => {
          ev->preventDefault
          let i = s - ModMatrix.sourceIndex("macro1")
          Controls.editInPlace(e, (ctx.programs->ProgramStore.meta).macroNames[i]->Option.getOr(""), ~commit=name =>
            ctx.programs->ProgramStore.setMacroName(i, name)
          )
        })
      }
      Some(e)
    }
  )

  targetRows->Array.forEachWithIndex((rows, c) =>
    rows->Array.forEachWithIndex((row, r) => {
      let x = columnX->Array.getUnsafe(c)
      let y = top + Int.toFloat(r) * rowHeight
      switch row {
      | Heading(title) =>
        el("div", ~cls="jh", ~text=title, ~parent=bay)->place(x - 6., y, ~w=112., ~h=rowHeight)->ignore
      | Target(t) =>
        let e =
          el("div", ~cls="jl", ~text=targetLabel(t), ~parent=bay)->place(
            x + 9.,
            y,
            ~w=100.,
            ~h=rowHeight,
          )
        e->hover(() =>
          switch ModMatrix.targets->Array.getUnsafe(t) {
          | {law: Knob(id)} => (model->ParamModel.def(id)).longText(get(id))
          | {label} => label
          }
        )
      }
    })
  )

  let svg = Plots.svg(bay, {x: 0., y: 0., w: patchWidth, h: patch.h})
  svg->setAttribute("class", Str("plot cables"))
  let cableLayer = svg->Plots.svgEl("g", [])
  let jackLayer = svg->Plots.svgEl("g", [])
  let dragLayer = svg->Plots.svgEl("g", [])

  let toLocal = ev => {
    let r = svg->getBoundingClientRect
    let s = ctx.scale()
    {x: (ev->clientX - r.left) / s, y: (ev->clientY - r.top) / s}
  }

  let nearest = (jacks: array<point>, p, ~skip) => {
    let best = ref(None)
    jacks->Array.forEachWithIndex((j, i) =>
      if i > 0 && !skip(i) {
        let d = Math.hypot(j.x - p.x, j.y - p.y)
        if d < 14. && best.contents->Option.mapOr(true, ((_, bd)) => d < bd) {
          best := Some((i, d))
        }
      }
    )
    best.contents->Option.map(Pair.first)
  }

  let makeJack = (p: point, cls) =>
    jackLayer->Plots.svgEl(
      "circle",
      [("class", Str(cls)), ("cx", Num(p.x)), ("cy", Num(p.y)), ("r", Num(jackRadius))],
    )

  let sourceJackEls = sourceJacks->Array.mapWithIndex((p, s) => s == 0 ? None : Some(makeJack(p, "jack")))
  let targetJackEls = targetJacks->Array.mapWithIndex((p, t) => t == 0 ? None : Some(makeJack(p, "jack")))

  // dragging a new cable from either end
  let startDrag = (ev, fromSource, index) => {
    ev->preventDefault
    let start = fromSource ? sourceJacks->Array.getUnsafe(index) : targetJacks->Array.getUnsafe(index)
    let color = fromSource ? sourceColor(index) : "#1f1a0e"
    let wire = dragLayer->Plots.svgEl(
      "path",
      [("class", Str("cable drag")), ("stroke", Str(color)), ("d", Str(cablePath(start, start)))],
    )
    let others = fromSource ? targetJacks : sourceJacks
    let otherEls = fromSource ? targetJackEls : sourceJackEls
    let hot = ref(None)
    let setHot = h => {
      hot.contents->Option.forEach(i => otherEls->Array.getUnsafe(i)->Option.forEach(e => e->removeClass("hot")))
      hot := h
      h->Option.forEach(i => otherEls->Array.getUnsafe(i)->Option.forEach(e => e->addClass("hot")))
    }
    let target = ev->target->(t => (Obj.magic(t): element))
    target->Controls.capturePointer(
      ev,
      ~onMove=mv => {
        let p = toLocal(mv)
        let h = nearest(others, p, ~skip=_ => false)
        setHot(h)
        let endPoint = h->Option.mapOr(p, i => others->Array.getUnsafe(i))
        let (a, b) = fromSource ? (start, endPoint) : (endPoint, start)
        wire->setAttribute("d", Str(cablePath(a, b)))
      },
      ~onUp=() => {
        wire->remove
        let h = hot.contents
        setHot(None)
        h->Option.forEach(other => fromSource ? connect(index, other) : connect(other, index))
      },
    )
  }

  sourceJackEls->Array.forEachWithIndex((e, s) =>
    e->Option.forEach(e => {
      e->onPointer(#pointerdown, ev => startDrag(ev, true, s))
      e->hover(() => `${sourceLabel(s)}: drag to a target to connect it`)
    })
  )
  targetJackEls->Array.forEachWithIndex((e, t) =>
    e->Option.forEach(e => {
      e->onPointer(#pointerdown, ev => startDrag(ev, false, t))
      e->hover(() => `${targetLabel(t)}: drag to a source to connect it`)
    })
  )

  //==============================================================================
  // connections list

  let listHeight = Grid.padTop + Int.toFloat(ModMatrix.slots) * 26. + 4.
  let listX = margin + patchWidth + gap
  let listWidth = Style.designWidth - listX - margin
  let list = Panel.make(page, ~title="connections", ~x=listX, ~y=margin, ~w=listWidth, ~h=listHeight)
  let empty = el(
    "div",
    ~cls="note",
    ~text="Nothing connected yet: drag from a source to a target.",
    ~parent=list.el,
  )->place(10., 30.)

  let rows = slotNumbers->Array.map(k => {
    let row = el("div", ~cls="mrow", ~parent=list.el)->place(4., 0., ~w=listWidth - 10., ~h=26.)
    let swatch = el("i", ~cls="sw", ~parent=row)
    let name = el("div", ~cls="mname", ~parent=row)
    name->onPointer(#pointerdown, ev =>
      switch ev->button {
      | 2 => disconnect(k)
      | _ => select(selected.contents == Some(k) ? None : Some(k))
      }
    )
    name->suppressContextMenu
    name->hover(() => connectionText(k) ++ ". Right-click to remove it.")
    Controls.param(ctx, row, ModMatrix.amountId(k), ~x=146., ~y=0., ~w=80., ~label="amount")
    Controls.choice(ctx, row, ModMatrix.viaId(k), ~x=228., ~y=0., ~w=58., ~label="via")
    let del = el("button", ~cls="btn mdel", ~text="×", ~parent=row)
    del->onMouse(#click, _ => disconnect(k))
    del->hover(() => "Remove this connection")
    (k, row, swatch, name)
  })

  //==============================================================================
  // macros

  let macroY = margin + listHeight + gap
  let macros = Panel.make(
    page,
    ~title="macros",
    ~x=listX,
    ~y=macroY,
    ~w=listWidth,
    ~h=Style.pageHeight - margin - macroY,
  )
  let macroControls = Array.fromInitializer(~length=ModMatrix.macros, i =>
    Controls.paramControl(
      ctx,
      macros.el,
      ModMatrix.macroId(i + 1),
      ~x=Grid.padX + Int.toFloat(i) * 78.,
      ~y=Grid.padTop,
      ~w=76.,
      ~label=macroName(i),
    )
  )

  //==============================================================================
  // drawing

  let draw = () => {
    // cables
    cableLayer->setTextContent("")
    let used = slotNumbers->Array.filter(isUsed)
    let sourcesOn = Set.make()
    let targetsOn = Set.make()
    used->Array.forEach(k => {
      let (s, t) = (sourceOf(k), targetOf(k))
      switch (sourceJacks[s], targetJacks[t]) {
      | (Some(a), Some(b)) =>
        sourcesOn->Set.add(s)
        targetsOn->Set.add(t)
        let d = cablePath(a, b)
        let isSelected = selected.contents == Some(k)
        let muted = get(ModMatrix.amountId(k)) == 0.
        cableLayer
        ->Plots.svgEl(
          "path",
          [
            ("class", Str("cable" ++ (isSelected ? " sel" : "") ++ (muted ? " muted" : ""))),
            ("stroke", Str(sourceColor(s))),
            ("d", Str(d)),
          ],
        )
        ->ignore
        let hit = cableLayer->Plots.svgEl("path", [("class", Str("cablehit")), ("d", Str(d))])
        hit->onPointer(#pointerdown, ev => {
          ev->preventDefault
          switch ev->button {
          | 2 => disconnect(k)
          | _ => select(Some(k))
          }
        })
        hit->suppressContextMenu
        hit->hover(() => connectionText(k) ++ ". Right-click to remove it.")
      | _ => ()
      }
    })
    sourceJackEls->Array.forEachWithIndex((e, s) =>
      e->Option.forEach(e => e->toggleClass("on", sourcesOn->Set.has(s)))
    )
    targetJackEls->Array.forEachWithIndex((e, t) =>
      e->Option.forEach(e => e->toggleClass("on", targetsOn->Set.has(t)))
    )

    // the list, in slot order
    let shown = ref(0)
    rows->Array.forEach(((k, row, swatch, name)) =>
      if isUsed(k) {
        row->setStyle("display", "block")
        row->setStyle("top", px(Grid.padTop + Int.toFloat(shown.contents) * 26.))
        row->toggleClass("sel", selected.contents == Some(k))
        swatch->setStyle("background", sourceColor(sourceOf(k)))
        name->setTextContent(`${sourceLabel(sourceOf(k))} → ${targetLabel(targetOf(k))}`)
        shown := shown.contents + 1
      } else {
        row->setStyle("display", "none")
      }
    )
    empty->setStyle("display", shown.contents == 0 ? "block" : "none")

    // macro names
    sourceLabels->Array.forEachWithIndex((e, s) => e->Option.forEach(e => e->setTextContent(sourceLabel(s))))
    macroControls->Array.forEachWithIndex((c, i) =>
      c->querySelector(".l")->Option.forEach(l => l->setTextContent(macroName(i)))
    )
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
