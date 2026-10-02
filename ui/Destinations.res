// A source's destinations as chips, one per route leaving it in any system (Modulators.from):
// its Oatmeal slots or fixed depths, and the matrix's connections. Each chip, in the source's
// colour, shows what it moves and how much: drag it sideways to change the amount (shift for fine
// steps, double-click to type one, or the arrow keys), × (or Delete) takes the route out. "+"
// offers the source's own targets (Oatmeal's list for its slots, or its fixed depths) and then the
// matrix's, by group. In a narrow column the chips stack; ~wide, they run in rows of columns.

open! Web

// what a new route's amount starts at: a quarter of the knob, up from the middle when it goes
// both ways
let startAmount = (def: ParamDefs.t) => def.fromNorm(def.bipolar ? 0.75 : 0.25)

// Takes a route out: a connection's slot is emptied (its options back to theirs, for the next
// connection there), an Oatmeal slot's target and depth go to none and 0, a depth to 0.
let clear = (model, id) =>
  if model->ParamModel.get(id) != 0. {
    model->ParamModel.gestureSet(id, 0.)
  }

// Empties the matrix's slot k.
let disconnect = (model, k) => {
  [ModMatrix.amountId(k), ModMatrix.viaId(k), ModMatrix.sourceId(k), ModMatrix.targetId(k)]->Array.forEach(clear(model, _))
  [ModMatrix.holdId(k), ModMatrix.slewId(k), ModMatrix.curveId(k), ModMatrix.stepsId(k)]->Array.forEach(clear(model, _))
}

let takeOut = (model, r: Modulators.route) =>
  switch r.via {
  | Connection(k) => disconnect(model, k)
  | Slot(target) =>
    clear(model, r.amount)
    clear(model, target)
  | Depth => clear(model, r.amount)
  }

let make = (ctx: Ctx.t, parent, key, box: box, ~wide=false) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let source = ModMatrix.sourceIndex(key)
  // (a macro by the name its program gives it, which may change)
  let sourceLabel = () => ModEdit.keyName(ctx.programs, key)
  let colour = ModEdit.keyColour(key)
  let root = el("div", ~cls=wide ? "dests wide" : "dests", ~parent)->placeBox(box)
  let dragging = ref(false)

  //==============================================================================
  // adding

  // its Oatmeal slots' list (prefix and names), if it has slots
  let slotSet = Modulators.slotSets->Array.find(((k, _, _)) => k == key)
  let addOwnSlot = (prefix, list: array<string>, i) =>
    switch [1, 2, 3, 4]->Array.find(k => get(`${prefix}Target_${Int.toString(k)}`) == 0.) {
    | Some(k) =>
      let depth = `${prefix}Depth_${Int.toString(k)}`
      model->ParamModel.gestureSet(`${prefix}Target_${Int.toString(k)}`, Int.toFloat(i))
      model->ParamModel.gestureSet(depth, startAmount(model->ParamModel.def(depth)))
    | None =>
      ctx.toast(`${sourceLabel()}'s four slots are in use: take one out, or connect ${list[i]->Option.mapOr("it", OatmealParams.targetName)} through the matrix`)
    }
  let connect = target =>
    switch ModEdit.connect(model, source, target, ~amount=ModEdit.defaultAmount) {
    | Ok(_) => ()
    | Error(why) => ctx.toast(`${sourceLabel()}: ${why}`)
    }

  // the menu's values: its own targets from 0, the matrix's groups from groupBase
  let (depthBase, groupBase) = (1000, 2000)
  let addMenu = anchor => {
    let own = switch slotSet {
    | Some((_, _, list)) =>
      list->Array.filterMap(name => name == "none" ? None : Some(name))->Array.mapWithIndex((name, i) => {
        Menu.label: OatmealParams.targetName(name),
        value: i + 1,
        heading: ?(i == 0 ? Some(`${sourceLabel()}'s own slots`) : None),
      })
    | None =>
      Modulators.fixedDepths(key)
      ->Array.mapWithIndex(((id, label, _), i) => (id, label, i))
      ->Array.filter(((id, _, _)) => get(id) == 0.)
      ->Array.mapWithIndex(((_, label, i), n) => {
        Menu.label: label,
        value: depthBase + i,
        heading: ?(n == 0 ? Some(`${sourceLabel()}'s own depths`) : None),
      })
    }
    // (the pitch envelope isn't one of the matrix's sources)
    let groups =
      source < 0
        ? []
        : ModMatrix.groups->Array.mapWithIndex(((_, title), g) => {
            Menu.label: title ++ " ›",
            value: groupBase + g,
            heading: ?(g == 0 ? Some("the matrix") : None),
          })
    ctx.menu->Menu.show(anchor, [...own, ...groups], -1, v =>
      if v >= groupBase {
        ModMatrix.groups[v - groupBase]->Option.forEach(((group, _)) => {
          let connected = Modulators.from(get, key)->Array.filterMap(r =>
            switch r.via {
            | Connection(k) => Some(ModMatrix.readSlot(get, k).target)
            | _ => None
            }
          )
          let items =
            ModMatrix.targets
            ->Array.mapWithIndex((t, i) => (t, i))
            ->Array.filter(((t, i)) => t.group == group && !(connected->Array.includes(i)))
            ->Array.map(((t, i)) => {Menu.label: t.label, value: i})
          ctx.menu->Menu.show(anchor, items, -1, connect)
        })
      } else if v >= depthBase {
        Modulators.fixedDepths(key)[v - depthBase]->Option.forEach(((id, _, _)) =>
          model->ParamModel.gestureSet(id, startAmount(model->ParamModel.def(id)))
        )
      } else {
        slotSet->Option.forEach(((_, prefix, list)) => addOwnSlot(prefix, list, v))
      }
    )
  }
  let add = el("div", ~cls="dchip add", ~parent=root)
  el("b", ~text="+", ~parent=add)->ignore
  add->setTabIndex(0)
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      addMenu(add)
    }
  })
  add->onActivate(() => addMenu(add))
  ctx.status->Status.hover(add, () => `Make ${sourceLabel()} move something: its own targets, or any of the matrix's`)

  //==============================================================================
  // the chips

  let systemOf = (r: Modulators.route) =>
    switch r.via {
    | Connection(k) => `matrix connection ${Int.toString(k)}`
    | Slot(target) => `Oatmeal's own slot ${String.slice(target, ~start=String.length(target) - 1)}`
    | Depth => "Oatmeal's own depth"
    }
  let chip = (r: Modulators.route) => {
    let def = model->ParamModel.def(r.amount)
    let e = el("div", ~cls="dchip", ~parent=root)
    e->setTabIndex(0)
    el("i", ~cls="sw", ~parent=e)->setStyle("background", colour)
    el("span", ~cls="dl", ~text=r.label, ~parent=e)->ignore
    let value = el("span", ~cls="dv", ~parent=e)
    let track = el("span", ~cls="dt", ~parent=e)
    let fill = el("i", ~parent=track)
    fill->setStyle("background", colour)
    let x = el("b", ~cls="dx", ~text="×", ~parent=e)
    let status = ctx.status->Status.live(e, () =>
      `${sourceLabel()} → ${r.label}: ${def.valueText(get(r.amount))} (${systemOf(r)}). Drag sideways to change it, shift for fine steps, double-click to type it; × takes it out`
    )
    let update = () => {
      let a = get(r.amount)
      value->setTextContent(def.shortText(a))
      let n = Float.clamp(def.toNorm(a), ~min=0., ~max=1.)
      let (lo, hi) = def.bipolar ? (Math.min(n, 0.5), Math.max(n, 0.5)) : (0., n)
      fill->setStyle("left", Float.toString(lo * 100.) ++ "%")
      fill->setStyle("width", Float.toString(Math.max(0.5, (hi - lo) * 100.)) ++ "%")
      e->toggleClass("zero", a == 0.)
      status.refresh()
    }
    x->onPointer(#pointerdown, ev => {
      ev->stopPropagation
      ev->preventDefault
      if ev->button == 0 {
        takeOut(model, r)
      }
    })
    ctx.status->Status.hover(x, () => `Take ${sourceLabel()} → ${r.label} out`)
    e->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->preventDefault
        dragging := true
        status.setDragging(true)
        e->addClass("drag")
        model->ParamModel.beginGesture(r.amount)
        let n = ref(def.toNorm(get(r.amount)))
        Controls.dragBy(
          ctx,
          e,
          ev,
          ~onMove=(dx, _, mv) => {
            let d = dx / 160.
            n := Float.clamp(n.contents + (mv->shiftKey ? d * Controls.fineShift : d), ~min=0., ~max=1.)
            model->ParamModel.set(r.amount, def.fromNorm(n.contents))
          },
          ~onUp=() => {
            dragging := false
            status.setDragging(false)
            e->removeClass("drag")
            model->ParamModel.endGesture(r.amount)
          },
        )
      }
    )
    e->onWheel(ev => Controls.wheelParam(model, r.amount, ev))
    e->onKeyDown(ev => {
      let nudge = d => {
        ev->preventDefault
        let d = ev->shiftKey ? d * 0.1 : d
        model->ParamModel.gestureSet(r.amount, def.fromNorm(Float.clamp(def.toNorm(get(r.amount)) + d, ~min=0., ~max=1.)))
      }
      switch ev->Web.key {
      | "ArrowRight" | "ArrowUp" => nudge(0.01)
      | "ArrowLeft" | "ArrowDown" => nudge(-0.01)
      | "Delete" | "Backspace" => takeOut(model, r)
      | _ => ()
      }
    })
    e->onMouse(#dblclick, ev => {
      ev->preventDefault
      Controls.editInPlace(e, def.shortText(get(r.amount)), ~commit=text =>
        switch def.parse(text) {
        | Some(v) if Float.isFinite(v) => model->ParamModel.gestureSet(r.amount, v)
        | _ => ()
        }
      )
    })
    e->suppressContextMenu
    update()
    update
  }

  // the chips are made again when the routes change, and only their amounts change during a drag
  let shown = ref("")
  let updates = ref([])
  let refresh = () => {
    let routes = Modulators.from(get, key)
    let routeKey = routes->Array.map(r => r.amount ++ ":" ++ r.label)->Array.join(",")
    if routeKey != shown.contents && !dragging.contents {
      shown := routeKey
      root->querySelectorAll(".dchip:not(.add)")->nodesToArray->Array.forEach(remove)
      updates := routes->Array.map(chip)
      // (+ after them)
      root->appendChild(add)
    } else {
      updates.contents->Array.forEach(f => f())
    }
  }
  model->ParamModel.listenEach(Modulators.fromIds(key), perFrame(refresh))
  refresh()
}
