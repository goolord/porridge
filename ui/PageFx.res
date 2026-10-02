// Effects page: a tab per effect, in the order the sound goes through them, after a routing tab
// for what isn't about one effect (the signal flow, where the distortion sits, the rack's order
// and levels, the output gain). Each effect's tab shows what it does as graphs to drag.
//
// The tabs after Oatmeal's distortion are the rack (FxRack): up to eight effects, each kind up to
// four times. Drag a tab sideways to move that effect, × takes it out, right-click duplicates it,
// + adds one. Before them, under "per-voice", the voice lane's (VoiceLane): the effects every
// voice runs its own copy of; right-click moves one between the lane and the rack.

open! Web

// Opens an effect's tab (the synth page's voice FX tab asks), once the page is built.
let openEffect = ref((_: FxRack.effect) => ())

let hint = "Drag a rack tab sideways to move that effect, × takes it out, right-click duplicates it, + adds one. On a graph, drag the points; shift for fine steps, right-click to reset."

type dest = Routing | Distortion | Rack(FxRack.effect)

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let rack = () => FxRack.read(get)
  let (x, w) = (6., Style.designWidth - 12.)
  let bodyY = 34.
  let bodyH = Style.pageHeight - 6. - bodyY
  let strip = el("div", ~cls="fxstrip", ~parent=page)->place(x, 6., ~w, ~h=22.)
  let status = text => ctx.status->Status.show(text)

  let current = ref(Routing)
  // each tab's page, made when it is first shown: the element and its refresh
  let bodies: Map.t<string, (element, unit => unit)> = Map.make()
  let destKey = dest =>
    switch dest {
    | Routing => "routing"
    | Distortion => "distortion"
    | Rack(e) => Int.toString(FxRack.value(e))
    }
  // every tab made so far: its destination, element, light and label
  let tabs: array<(dest, element, option<element>, element)> = []

  let makeBody = (dest, routing) => {
    let body = el("div", ~cls="fxbody", ~parent=page)->place(x, bodyY, ~w, ~h=bodyH)
    let refresh = switch dest {
    | Routing => routing(body)
    | Distortion => DistEditor.make(ctx, body, ~id=x => x, ~placement=true, ~w, ~h=bodyH)
    | Rack(e) =>
      switch e.kind {
      | #chorus => ChorusEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #delay => DelayEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #reverb => ReverbEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #distortion => DistEditor.make(ctx, body, ~id=FxRack.id(e, ...), ~placement=false, ~w, ~h=bodyH)
      | #eq =>
        let panel = Panel.make(body, ~title="EQ", ~x=0., ~y=0., ~w, ~h=bodyH)
        panel->Panel.headerToggle(ctx, FxRack.id(e, "EQ_On"), ~label="on")
        EqEditor.make(ctx, panel.el, {x: 8., y: 25., w: w - 18., h: bodyH - 35.}, ~id=FxRack.id(e, ...))
        () => ()
      | #compressor => CompEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | _ => FxPanels.make(ctx, body, e, ~w, ~h=bodyH)
      }
    }
    bodies->Map.set(destKey(dest), (body, refresh))
    (body, refresh)
  }
  let routingMaker = ref(_ => () => ())

  // a convolver's "load file…" button
  let impulseFor = ref(0)
  let pickImpulse = FilePicker.make(page, ~accept=AudioFile.accept, file =>
    ctx.programs->ProgramStore.loadImpulseFile(impulseFor.contents, file)->Promise.ignore
  )
  FxPanels.loadImpulse :=
    (
      e => {
        impulseFor := e.copy - 1
        pickImpulse()
      }
    )

  let markCurrent = () =>
    tabs->Array.forEach(((d, t, _, _)) => t->toggleClass("on", d == current.contents))
  let select = dest => {
    current := dest
    markCurrent()
    let (shown, refresh) = switch bodies->Map.get(destKey(dest)) {
    | Some(b) => b
    | None => makeBody(dest, routingMaker.contents)
    }
    bodies->Map.forEach(((body, _)) => body->toggleClass("on", body === shown))
    refresh()
    ctx.menu->Menu.close
  }

  //==============================================================================
  // the rack

  let setRack = list =>
    FxRack.values(list)->Array.forEach(((id, v)) =>
      if get(id) != v {
        model->ParamModel.gestureSet(id, v)
      }
    )

  let move = (e, pos) => {
    let others = rack()->Array.filter(o => o != e)
    others->Array.splice(~start=pos, ~remove=0, ~insert=[e])
    setRack(others)
  }

  // an effect comes into the rack switched on, at the end (or after `after`)
  let insert = (e: FxRack.effect, ~after=?, ~show) => {
    let list = rack()
    switch after->Option.map(a => list->Array.findIndex(x => x == a)) {
    | Some(i) if i >= 0 => list->Array.splice(~start=i + 1, ~remove=0, ~insert=[e])
    | _ => list->Array.push(e)
    }
    setRack(list)
    let id = FxRack.switchId(e)
    if get(id) == 0. {
      model->ParamModel.gestureSet(id, FxRack.onValue(e))
    }
    if show {
      select(Rack(e))
    }
  }

  let add = (kind, ~show) => FxRack.free(rack(), ~lane=VoiceLane.lane(model), kind)->Option.forEach(insert(_, ~show))

  // a copy with the same settings, right after it
  let duplicate = (e: FxRack.effect, ~show) =>
    FxRack.free(rack(), ~lane=VoiceLane.lane(model), e.kind)->Option.forEach(copy => {
      FxRack.params(e)->Array.forEachWithIndex((id, i) =>
        FxRack.params(copy)[i]->Option.forEach(to => model->ParamModel.gestureSet(to, get(id)))
      )
      insert(copy, ~after=e, ~show)
    })

  let remove = e => {
    setRack(rack()->Array.filter(o => o != e))
    if current.contents == Rack(e) {
      select(Routing)
    }
  }

  // the kinds that can still be added, in their groups, each with its icon
  let addMenu = (anchor, ~show) => {
    let addable = FxRack.addable(rack(), ~lane=VoiceLane.lane(model))
    let kinds = FxRack.menuGroups->Array.flatMap(((title, kinds)) =>
      kinds
      ->Array.filter(k => addable->Array.includes(k))
      ->Array.mapWithIndex((k, i) => (k, i == 0 ? Some(title) : None))
    )
    ctx.menu->Menu.show(
      anchor,
      kinds->Array.mapWithIndex(((k, heading), i) => {
        Menu.label: FxRack.kindName(k),
        value: i,
        icon: ?Icons.rackKind(FxRack.key(k))->Option.map(icon => {
          let wrap = el("span", ~cls="icw")
          wrap->appendChild(Icons.render(icon))
          wrap
        }),
        ?heading,
        hint: FxRack.about(k),
      }),
      -1,
      i => kinds[i]->Option.forEach(((k, _)) => add(k, ~show)),
    )
  }

  let effectMenu = (e: FxRack.effect, anchor, ~show) => {
    if VoiceLane.holds(model, e) {
      VoiceLane.menu(ctx, e, anchor)
    } else {
      let canCopy = FxRack.free(rack(), ~lane=VoiceLane.lane(model), e.kind) != None
      let canMove = FxRack.canBeInLane(e) && !FxRack.laneFull(VoiceLane.lane(model))
      ctx.menu->Menu.show(
        anchor,
        [
          ...canCopy ? [{Menu.label: "duplicate", value: 0}] : [],
          ...canMove ? [{Menu.label: "move into every voice", value: 2}] : [],
          {Menu.label: "remove from the rack", value: 1},
        ],
        -1,
        v =>
          switch v {
          | 0 => duplicate(e, ~show)
          | 2 => VoiceLane.fromRack(model, e)->ignore
          | _ => remove(e)
          },
      )
    }
  }

  // Switching an effect on and off by its light. A chorus or distortion is off at its list's
  // first value, and comes back on as it was.
  let lastOn: Map.t<string, float> = Map.make()
  let toggleSwitch = (id, ~onValue) => {
    let x = get(id)
    if x != 0. {
      lastOn->Map.set(id, x)
      model->ParamModel.gestureSet(id, 0.)
    } else {
      model->ParamModel.gestureSet(id, lastOn->Map.get(id)->Option.getOr(onValue))
    }
  }
  let toggle = (e: FxRack.effect) => toggleSwitch(FxRack.switchId(e), ~onValue=FxRack.onValue(e))

  //==============================================================================
  // tabs

  // A tab: its light (with ~onToggle) switches the effect, its × (with ~onRemove) takes it out of
  // the rack, and onPress gets the presses on it (and the tab). Returns the tab and its label.
  let tab = (dest, ~label="", ~onToggle=?, ~onRemove=?, ~title: unit => string, onPress) => {
    let t = el("div", ~cls="fxtab")
    let led = onToggle->Option.map(onToggle => {
      let led = el("i", ~cls="led", ~parent=t)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          onToggle()
        }
      )
      led->onMouse(#mouseenter, ev => {
        ev->stopPropagation
        status("Click to switch it on or off")
      })
      led
    })
    let labelEl = el("span", ~text=label, ~parent=t)
    ctx.status->Status.hover(t, title)
    onRemove->Option.forEach(onRemove => {
      let x = el("b", ~cls="x", ~text="×", ~parent=t)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        onRemove()
      })
    })
    t->suppressContextMenu
    t->onPointer(#pointerdown, ev => onPress(ev, t))
    tabs->Array.push((dest, t, led, labelEl))
    (t, labelEl)
  }
  let selectOnPress = (dest, ev, _) => {
    ev->preventDefault
    select(dest)
  }

  let (routingTab, _) = tab(
    Routing,
    ~label="routing",
    ~title=() => "The signal flow: where the distortion sits, the rack's order and levels, and the output gain",
    selectOnPress(Routing, ...),
  )
  let (distTab, _) = tab(
    Distortion,
    ~label="distortion",
    ~onToggle=() => toggleSwitch("Sat_Type", ~onValue=2.),
    ~title=() => "Oatmeal's distortion: in every voice, or on the whole sound before the rack (see routing)",
    selectOnPress(Distortion, ...),
  )

  // the rack's tabs, made when an effect first comes into it: each one's element and label
  let rackTabs = Map.make()
  let rackTab = (e: FxRack.effect) =>
    switch rackTabs->Map.get(FxRack.value(e)) {
    | Some(t) => t
    | None =>
      let made = tab(
        Rack(e),
        ~onToggle=() => toggle(e),
        ~onRemove=() => remove(e),
        ~title=() =>
          `${FxRack.label(rack(), e)} (${FxRack.hostName(e)}'s parameters): click to open, drag sideways to move it, right-click to duplicate it, × takes it out (its settings stay)`,
        (ev, t) =>
          switch ev->button {
          | 0 =>
            ev->preventDefault
            let others =
              rack()
              ->Array.filter(o => o != e)
              ->Array.filterMap(o => rackTabs->Map.get(FxRack.value(o))->Option.map(Pair.first))
            Reorder.start(ev, t, ~others, ~onDrop=pos => move(e, pos), ~onClick=() => select(Rack(e)))
          | 2 =>
            ev->preventDefault
            effectMenu(e, t, ~show=true)
          | _ => ()
          },
      )
      rackTabs->Map.set(FxRack.value(e), made)
      made
    }

  // the voice lane's tabs: drag sideways among themselves, × takes one out of the voices
  let laneTabs = Map.make()
  let laneTab = (e: FxRack.effect) =>
    switch laneTabs->Map.get(FxRack.value(e)) {
    | Some(t) => t
    | None =>
      let made = tab(
        Rack(e),
        ~onToggle=() => toggle(e),
        ~onRemove=() => VoiceLane.remove(model, e),
        ~title=() =>
          `${VoiceLane.label(model, e)} in every voice (${FxRack.hostName(e)}'s parameters): each voice runs its own. Click to open, drag sideways to move it, right-click to duplicate it or move it to the whole sound, × takes it out`,
        (ev, t) =>
          switch ev->button {
          | 0 =>
            ev->preventDefault
            let lane = VoiceLane.lane(model)
            let others =
              lane
              ->Array.filter(o => o != e)
              ->Array.filterMap(o => laneTabs->Map.get(FxRack.value(o))->Option.map(Pair.first))
            Reorder.start(ev, t, ~others, ~onClick=() => select(Rack(e)), ~onDrop=pos => {
              // (among the lane's effects; the filter and amp keep their places by count)
              let list = lane->Array.filter(o => o != e)
              list->Array.splice(~start=pos, ~remove=0, ~insert=[e])
              VoiceLane.setAll(model, FxRack.laneValues(list, FxRack.readPlaces(get, lane)))
            })
          | 2 =>
            ev->preventDefault
            effectMenu(e, t, ~show=true)
          | _ => ()
          },
      )
      laneTabs->Map.set(FxRack.value(e), made)
      made
    }
  let laneAdd = el("div", ~cls="fxtab add", ~text="+")
  ctx.status->Status.hover(laneAdd, () =>
    "Add a per-voice effect: each voice runs its own copy, which its LFOs, envelopes and key move for that note alone"
  )
  laneAdd->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      VoiceLane.addMenu(ctx, laneAdd, ~onAdded=e => select(Rack(e)))
    }
  })
  let groupLabel = (text, help) => {
    let e = el("span", ~cls="fxgrp", ~text)
    ctx.status->Status.hover(e, () => help)
    e
  }
  let eachLabel = groupLabel("per-voice", "The voice lane: effects in every voice, which each voice runs its own copy of")
  let wholeLabel = groupLabel("whole sound", "Oatmeal's distortion and the rack: effects on the sound of every voice together")

  let addTab = el("div", ~cls="fxtab add", ~text="+")
  ctx.status->Status.hover(addTab, () =>
    "Add an effect to the end of the rack: up to eight, each kind up to four times (convolve twice)"
  )
  addTab->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      addMenu(addTab, ~show=true)
    }
  })

  let arrow = () => el("span", ~cls="fxsep", ~text="›")
  let layoutStrip = () => {
    let list = rack()
    strip->setTextContent("")
    strip->appendChild(routingTab)
    strip->appendChild(el("span", ~cls="fxgap"))
    strip->appendChild(eachLabel)
    let lane = VoiceLane.lane(model)
    lane->Array.forEach(e => {
      let (t, label) = laneTab(e)
      label->setTextContent(FxRack.label(lane, e))
      strip->appendChild(t)
    })
    if !FxRack.laneFull(lane) {
      strip->appendChild(laneAdd)
    }
    strip->appendChild(el("span", ~cls="fxgap"))
    strip->appendChild(wholeLabel)
    strip->appendChild(distTab)
    list->Array.forEach(e => {
      strip->appendChild(arrow())
      let (t, label) = rackTab(e)
      label->setTextContent(FxRack.label(list, e))
      strip->appendChild(t)
    })
    if FxRack.addable(list, ~lane=VoiceLane.lane(model)) != [] {
      strip->appendChild(addTab)
    }
    // (a tab made now for the current effect)
    markCurrent()
  }

  let lights = () =>
    tabs->Array.forEach(((dest, _, led, _)) =>
      led->Option.forEach(led =>
        led->toggleClass(
          "lit",
          switch dest {
          | Routing => false
          | Distortion => get("Sat_Type") != 0.
          | Rack(e) => FxRack.isOn(e, get)
          },
        )
      )
    )

  //==============================================================================
  // the routing tab

  routingMaker :=
    body =>
      FxRouting.make(
        ctx,
        body,
        ~w,
        ~h=bodyH,
        {
          rack,
          move,
          add: add(_, ~show=false),
          remove,
          duplicate: duplicate(_, ~show=false),
          toggle,
          menu: (e, anchor) => effectMenu(e, anchor, ~show=false),
          addMenu: addMenu(_, ~show=false),
          openEffect: e => select(Rack(e)),
          openDistortion: () => select(Distortion),
        },
      )

  // (once a frame: a program change sets them all)
  let rackChanged = perFrame(() => {
    layoutStrip()
    lights()
    // a tab whose effect left the rack (a program change, the host) gives way to routing
    switch current.contents {
    | Rack(e) if !FxRack.holds(rack(), e) && !VoiceLane.holds(model, e) => select(Routing)
    | _ => ()
    }
  })
  let rackIds = Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1))
  model->ParamModel.listenEach([...rackIds, "FX_Order", ...VoiceLane.ids], rackChanged)
  model->ParamModel.listenEach(["Sat_Type", ...FxRack.all->Array.map(FxRack.switchId)], perFrame(lights))

  layoutStrip()
  lights()
  select(Routing)
  openEffect := (e => select(Rack(e)))

  // the tabs skip redrawing while the page is hidden: catch up when it shows
  let wasShown = ref(false)
  let observer = makeResizeObserver(() => {
    let shown = page->offsetParent->Option.isSome
    if shown && !wasShown.contents {
      select(current.contents)
    }
    wasShown := shown
  })
  observer->observe(page)
}
