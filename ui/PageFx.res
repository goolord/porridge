// Effects page: a tab per effect, in the order the sound goes through them, after a routing tab
// for what isn't about one effect (the signal flow, where the distortion sits, the rack's order
// and levels, the output gain). Each effect's tab shows what it does as graphs to drag.
//
// The tabs after Oatmeal's distortion are the rack (FxRack): up to eight effects, each kind up to
// four times. Drag a tab sideways to move that effect, × takes it out, right-click duplicates it,
// + adds one.

open! Web

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
  // every tab made so far, by destination
  let tabs: array<(dest, element, element)> = []

  let makeBody = (dest, routing) => {
    let body = el("div", ~cls="fxbody", ~parent=page)->place(x, bodyY, ~w, ~h=bodyH)
    let refresh = switch dest {
    | Routing => routing(body)
    | Distortion => DistEditor.make(ctx, body, ~id=x => x, ~placement=true)
    | Rack(e) =>
      switch e.kind {
      | #chorus => ChorusEditor.make(ctx, body, e)
      | #delay => DelayEditor.make(ctx, body, e)
      | #reverb => ReverbEditor.make(ctx, body, e)
      | #distortion => DistEditor.make(ctx, body, ~id=FxRack.id(e, ...), ~placement=false)
      | #eq =>
        let panel = Panel.make(body, ~title="EQ", ~x=0., ~y=0., ~w, ~h=bodyH)
        panel->Panel.headerToggle(ctx, FxRack.id(e, "EQ_On"), ~label="on")
        EqEditor.make(ctx, panel.el, {x: 8., y: 25., w: w - 18., h: bodyH - 35.}, ~id=FxRack.id(e, ...))
        () => ()
      }
    }
    bodies->Map.set(destKey(dest), (body, refresh))
    (body, refresh)
  }
  let routingMaker = ref(_ => () => ())

  let select = dest => {
    current := dest
    tabs->Array.forEach(((d, t, _)) => t->toggleClass("on", d == dest))
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

  let add = (kind, ~show) => FxRack.free(rack(), kind)->Option.forEach(insert(_, ~show))

  // a copy with the same settings, right after it
  let duplicate = (e: FxRack.effect, ~show) =>
    FxRack.free(rack(), e.kind)->Option.forEach(copy => {
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

  let addMenu = (anchor, ~show) =>
    ctx.menu->Menu.show(
      anchor,
      FxRack.addable(rack())->Array.mapWithIndex((k, i) => {Menu.label: FxRack.kindName(k), value: i}),
      -1,
      i => FxRack.addable(rack())[i]->Option.forEach(add(_, ~show)),
    )

  let effectMenu = (e: FxRack.effect, anchor, ~show) => {
    let canCopy = FxRack.free(rack(), e.kind) != None
    ctx.menu->Menu.show(
      anchor,
      [
        ...canCopy ? [{Menu.label: "duplicate", value: 0}] : [],
        {Menu.label: "remove from the rack", value: 1},
      ],
      -1,
      v => v == 0 ? duplicate(e, ~show) : remove(e),
    )
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

  let tab = (dest, ~removable, ~title: unit => string) => {
    let t = el("div", ~cls="fxtab")
    let led = el("i", ~cls="led", ~parent=t)
    led->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->stopPropagation
        ev->preventDefault
        switch dest {
        | Routing => ()
        | Distortion => toggleSwitch("Sat_Type", ~onValue=2.)
        | Rack(e) => toggle(e)
        }
      }
    )
    led->onMouse(#mouseenter, ev => {
      ev->stopPropagation
      status("Click to switch it on or off")
    })
    el("span", ~parent=t)->ignore
    t->onMouse(#mouseenter, _ => status(title()))
    t->onMouse(#mouseleave, _ => ctx.status->Status.clear)
    if removable {
      let x = el("b", ~cls="x", ~text="×", ~parent=t)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        switch dest {
        | Rack(e) => remove(e)
        | _ => ()
        }
      })
    }
    t->suppressContextMenu
    tabs->Array.push((dest, t, led))
    t
  }
  let setLabel = (t, text) => t->querySelector("span")->Option.forEach(s => s->setTextContent(text))

  let routingTab = tab(Routing, ~removable=false, ~title=() =>
    "The signal flow: where the distortion sits, the rack's order and levels, and the output gain"
  )
  routingTab->setLabel("routing")
  routingTab->querySelector(".led")->Option.forEach(led => led->setStyle("display", "none"))
  routingTab->onPointer(#pointerdown, ev => {
    ev->preventDefault
    select(Routing)
  })
  let distTab = tab(Distortion, ~removable=false, ~title=() =>
    "Oatmeal's distortion: in every voice, or on the whole sound before the rack (see routing)"
  )
  distTab->setLabel("distortion")
  distTab->onPointer(#pointerdown, ev => {
    ev->preventDefault
    select(Distortion)
  })

  // the rack's tabs, made when an effect first comes into it
  let rackTabs = Map.make()
  let rackTab = (e: FxRack.effect) =>
    switch rackTabs->Map.get(FxRack.value(e)) {
    | Some(t) => t
    | None =>
      let t = tab(Rack(e), ~removable=true, ~title=() =>
        `${FxRack.label(rack(), e)} (${FxRack.hostName(e)}'s parameters): click to open, drag sideways to move it, right-click to duplicate it, × takes it out (its settings stay)`
      )
      t->onPointer(#pointerdown, ev =>
        switch ev->button {
        | 0 =>
          ev->preventDefault
          let others =
            rack()->Array.filter(o => o != e)->Array.filterMap(o => rackTabs->Map.get(FxRack.value(o)))
          Reorder.start(ev, t, ~others, ~onDrop=pos => move(e, pos), ~onClick=() => select(Rack(e)))
        | 2 =>
          ev->preventDefault
          effectMenu(e, t, ~show=true)
        | _ => ()
        }
      )
      rackTabs->Map.set(FxRack.value(e), t)
      t
    }

  let addTab = el("div", ~cls="fxtab add", ~text="+")
  addTab->onMouse(#mouseenter, _ => status("Add an effect to the end of the rack: up to eight, each kind up to four times"))
  addTab->onMouse(#mouseleave, _ => ctx.status->Status.clear)
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
    strip->appendChild(distTab)
    list->Array.forEach(e => {
      strip->appendChild(arrow())
      let t = rackTab(e)
      t->setLabel(FxRack.label(list, e))
      strip->appendChild(t)
    })
    if FxRack.addable(list) != [] {
      strip->appendChild(addTab)
    }
  }

  let lights = () =>
    tabs->Array.forEach(((dest, _, led)) =>
      led->toggleClass(
        "lit",
        switch dest {
        | Routing => false
        | Distortion => get("Sat_Type") != 0.
        | Rack(e) => FxRack.isOn(e, get)
        },
      )
    )

  //==============================================================================
  // the routing tab

  routingMaker :=
    body =>
      FxRouting.make(
        ctx,
        body,
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

  let rackIds = Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1))
  [...rackIds, "FX_Order"]->Array.forEach(id =>
    model->ParamModel.listen(id, () => {
      layoutStrip()
      lights()
      // a tab whose effect left the rack (a program change, the host) gives way to routing
      switch current.contents {
      | Rack(e) if !FxRack.holds(rack(), e) => select(Routing)
      | _ => ()
      }
    })
  )
  model->ParamModel.listenAny(_ => lights())

  layoutStrip()
  lights()
  select(Routing)

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
