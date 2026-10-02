// Effects page: the strip at the top is the signal path, a tab per effect in the order the sound
// goes through them, and below it the open effect's editor, with graphs to drag.
//
// The strip has two parts. Per-voice: the voice lane's effects (VoiceLane), which every voice runs
// its own copy of, around the filter and the amp envelope, with Oatmeal's distortion right before
// or after the filter when it runs in the voices (Sat_Mode). Whole sound: Oatmeal's distortion
// when it runs there (or there too, "double"), then the rack (FxRack), up to eight effects in the
// order they run; then out, through the output gain (the synth page's amp panel).
//
// A tab's light is its effect's one switch, and an effect that is off shrinks to its icon. Drag a
// tab sideways to move that effect (the filter and the amp too, among the per-voice effects, and
// Oatmeal's distortion between its places), × takes one out, right-click for more (duplicating,
// moving between per-voice and the whole sound, the distortion's places), + adds one.

open! Web

@get external scrollWidth: element => float = "scrollWidth"

// Opens an effect's tab (the synth page asks), once the page is built: Oatmeal's distortion
// (FxRack.oatmealDistortion) or any per-voice or whole sound effect.
let openEffect = ref((_: FxRack.effect) => ())

let hint = "A tab's light switches its effect. Drag a tab sideways to move it, × takes it out, right-click for more, + adds one. On a graph, drag the points; shift for fine steps, right-click to reset."

type dest = Distortion | Rack(FxRack.effect)

// Oatmeal's distortion's places: Sat_Mode's values by name, and what its menu calls them
type place = Pre | Post | Global | Both
let places = [
  (Pre, "per voice, before filter", "per-voice, before the filter"),
  (Post, "per voice, after filter", "per-voice, after the filter"),
  (Global, "global", "whole sound"),
  (Both, "double (before filter and global)", "both: per-voice before the filter, and whole sound"),
]
let modeId = "Sat_Mode"

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let rack = () => FxRack.read(get)
  let (x, w) = (6., Style.designWidth - 12.)
  let bodyY = 34.
  let bodyH = Style.pageHeight - 6. - bodyY
  let strip = el("div", ~cls="fxstrip", ~parent=page)->place(x, 4., ~w, ~h=26.)
  let status = text => ctx.status->Status.show(text)
  let hover = (e, text) => ctx.status->Status.hover(e, text)
  let dist = FxRack.oatmealDistortion

  let modeOf = p => places->Array.find(((q, _, _)) => q == p)->Option.mapOr(0., ((_, name, _)) => ParamDefs.choiceValue(modeId, name))
  let placeNow = () => {
    let mode = get(modeId)
    places->Array.find(((p, _, _)) => modeOf(p) == mode)->Option.mapOr(Global, ((p, _, _)) => p)
  }
  let setPlace = p =>
    if get(modeId) != modeOf(p) {
      model->ParamModel.gestureSet(modeId, modeOf(p))
    }

  let inLane = e => VoiceLane.holds(model, e)
  let current = ref(Distortion)
  // each tab's editor, made when it is first shown: the element and its refresh, by destKey (an
  // effect has one editor per-voice and one on the whole sound, as their controls differ)
  let bodies: Map.t<string, (element, unit => unit)> = Map.make()
  let destKey = dest =>
    switch dest {
    | Distortion => "distortion"
    | Rack(e) => Int.toString(FxRack.value(e)) ++ (inLane(e) ? " per-voice" : "")
    }
  let shownKey = ref("")
  // every tab made so far, and its destination
  let tabs: array<(dest, element)> = []

  let makeBody = dest => {
    let body = el("div", ~cls="fxbody", ~parent=page)->place(x, bodyY, ~w, ~h=bodyH)
    let refresh = switch dest {
    | Distortion =>
      DistEditor.make(ctx, body, ~id=x => x, ~placement=true, ~perVoice=() => placeNow() != Global, ~w, ~h=bodyH)
    | Rack(e) =>
      let perVoice = inLane(e)
      switch e.kind {
      | #chorus => ChorusEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #delay => DelayEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #reverb => ReverbEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | #distortion =>
        DistEditor.make(ctx, body, ~id=FxRack.id(e, ...), ~placement=false, ~perVoice=() => perVoice, ~w, ~h=bodyH)
      | #eq =>
        let panel = Panel.make(body, ~title="EQ", ~x=0., ~y=0., ~w, ~h=bodyH)
        EqEditor.make(ctx, panel.el, {x: 8., y: 25., w: w - 18., h: bodyH - 35.}, ~id=FxRack.id(e, ...))
        () => ()
      | #compressor => CompEditor.make(ctx, body, e, ~w, ~h=bodyH)
      | _ => FxPanels.make(ctx, body, e, ~perVoice, ~w, ~h=bodyH)
      }
    }
    bodies->Map.set(destKey(dest), (body, refresh))
    (body, refresh)
  }

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

  let markCurrent = () => tabs->Array.forEach(((d, t)) => t->toggleClass("on", d == current.contents))
  let select = dest => {
    current := dest
    markCurrent()
    let key = destKey(dest)
    shownKey := key
    let (shown, refresh) = switch bodies->Map.get(key) {
    | Some(b) => b
    | None => makeBody(dest)
    }
    bodies->Map.forEach(((body, _)) => body->toggleClass("on", body === shown))
    refresh()
    ctx.menu->Menu.close
  }

  //==============================================================================
  // the rack and the lane

  let setRack = list => VoiceLane.setAll(model, FxRack.values(list))

  let move = (e, pos) => {
    let others = rack()->Array.filter(o => o != e)
    others->Array.splice(~start=pos, ~remove=0, ~insert=[e])
    setRack(others)
  }

  // an effect comes into the rack switched on, at the end (or after `after`)
  let insert = (e: FxRack.effect, ~after=?) => {
    let list = rack()
    switch after->Option.map(a => list->Array.findIndex(x => x == a)) {
    | Some(i) if i >= 0 => list->Array.splice(~start=i + 1, ~remove=0, ~insert=[e])
    | _ => list->Array.push(e)
    }
    setRack(list)
    VoiceLane.switchOn(model, e)
    select(Rack(e))
  }

  let add = (kind, ~setup) =>
    FxRack.free(rack(), ~lane=VoiceLane.lane(model), kind)->Option.forEach(e => {
      insert(e)
      VoiceLane.setUp(model, e, setup)
    })

  // a copy with the same settings, right after it
  let duplicate = (e: FxRack.effect) =>
    FxRack.free(rack(), ~lane=VoiceLane.lane(model), e.kind)->Option.forEach(copy => {
      VoiceLane.copySettings(model, ~from=e, ~to=copy)
      insert(copy, ~after=e)
    })

  let remove = e => setRack(rack()->Array.filter(o => o != e))

  // what the whole sound can still take, in its groups, each with its icon
  let addMenu = anchor => {
    let (picks, items) = VoiceLane.kindMenu(~addable=FxRack.addable(rack(), ~lane=VoiceLane.lane(model)))
    ctx.menu->Menu.show(anchor, items, -1, i => picks[i]->Option.forEach(((k, setup)) => add(k, ~setup)))
  }

  // a whole sound effect's right-click menu
  let rackMenu = (e: FxRack.effect, anchor) => {
    let canCopy = FxRack.free(rack(), ~lane=VoiceLane.lane(model), e.kind) != None
    let canMove = FxRack.canBeInLane(e) && !FxRack.laneFull(VoiceLane.lane(model))
    ctx.menu->Menu.show(
      anchor,
      [
        ...canCopy ? [{Menu.label: "duplicate", value: 0}] : [],
        ...canMove ? [{Menu.label: "move to per-voice", value: 2}] : [],
        {Menu.label: "remove", value: 1},
      ],
      -1,
      v =>
        switch v {
        | 0 => duplicate(e)
        | 2 => VoiceLane.fromRack(model, e)->ignore
        | _ => remove(e)
        },
    )
  }

  // Oatmeal's distortion's places
  let distMenu = anchor => {
    let now = placeNow()
    ctx.menu->Menu.show(
      anchor,
      places->Array.mapWithIndex(((_, _, label), i) => {Menu.label, value: i}),
      places->Array.findIndex(((p, _, _)) => p == now),
      i => places[i]->Option.forEach(((p, _, _)) => setPlace(p)),
    )
  }

  // Switching an effect on and off by its light. A chorus or distortion is off at its list's
  // first value, and comes back on as it was.
  let lastOn: Map.t<string, float> = Map.make()
  let toggle = (e: FxRack.effect) => {
    let id = FxRack.switchId(e)
    let x = get(id)
    if x != 0. {
      lastOn->Map.set(id, x)
      model->ParamModel.gestureSet(id, 0.)
    } else {
      model->ParamModel.gestureSet(id, lastOn->Map.get(id)->Option.getOr(FxRack.onValue(e)))
    }
  }

  //==============================================================================
  // the strip's pieces

  // An effect's tab: its light (the switch), its icon (shown alone while it is off, or when the
  // strip is full), its name and, with onRemove, × to take it out. onPress gets the presses on it.
  let effectTab = (e: FxRack.effect, ~dest, ~onRemove=?, ~title, onPress) => {
    let t = el("div", ~cls="fxtab")
    let led = el("i", ~cls="led", ~parent=t)
    led->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->stopPropagation
        ev->preventDefault
        toggle(e)
      }
    )
    led->onMouse(#mouseenter, ev => {
      ev->stopPropagation
      status("Click to switch it on or off")
    })
    let icon = el("span", ~cls="fxic", ~parent=t)
    Icons.rackKind(FxRack.key(e.kind))->Option.forEach(i => icon->appendChild(Icons.render(i)))
    let label = el("span", ~cls="fxname", ~parent=t)
    onRemove->Option.forEach(onRemove => {
      let x = el("b", ~cls="x", ~text="×", ~parent=t)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        onRemove()
      })
    })
    hover(t, title)
    t->suppressContextMenu
    t->onPointer(#pointerdown, ev => onPress(ev, t))
    tabs->Array.push((dest, t))
    (t, led, label)
  }

  let summary = e => FxPanels.summary(model, e)->String.replaceAll("\n", ", ")

  // the filter and the amp envelope among the per-voice effects
  let node = (text, title) => {
    let n = el("div", ~cls="fxnode", ~text)
    hover(n, title)
    n->suppressContextMenu
    n
  }
  let filterNode = node("filter", () =>
    "The voice's filter: drag it sideways among the per-voice effects. Oatmeal's distortion goes right before or after it."
  )
  let ampNode = node("amp", () =>
    "The amp envelope: drag it sideways. Per-voice effects after it react to how each note swells and fades, and ring on after it ends."
  )
  let zoneLabel = (text, title) => {
    let e = el("span", ~cls="fxgrp", ~text)
    hover(e, title)
    e
  }
  let voiceLabel = zoneLabel("per-voice", () =>
    "Per-voice: each voice runs its own copy of these, which its LFOs, envelopes and key move for that note alone"
  )
  let wholeLabel = zoneLabel("whole sound", () => "Whole sound: effects on all the voices together, in this order")
  let voiceZone = el("div", ~cls="fxzone voice")
  let wholeZone = el("div", ~cls="fxzone")
  let into = el("span", ~cls="fxsep into", ~text="⇒")
  let out = el("span", ~cls="fxsep out", ~text="→ out")
  hover(out, () => "Then out, through the output gain (in the amp panel on the synth page)")

  // the lane's and the rack's tabs, made when an effect first comes into either: one per effect
  let effectTabs = Map.make()
  let rec itemEl = (item: VoiceLane.item) =>
    switch item {
    | Fx(e) =>
      let (t, _, _) = tabOf(e)
      t
    | FilterNode => filterNode
    | AmpNode => ampNode
    }
  and pressItem = (item, ev) =>
    VoiceLane.press(ctx, item, ev, ~itemEl, ~onClick=() =>
      switch item {
      | VoiceLane.Fx(e) => select(Rack(e))
      | _ => ()
      }
    )
  and tabOf = (e: FxRack.effect) =>
    switch effectTabs->Map.get(FxRack.value(e)) {
    | Some(t) => t
    | None =>
      let made = effectTab(
        e,
        ~dest=Rack(e),
        ~onRemove=() => inLane(e) ? VoiceLane.remove(model, e) : remove(e),
        ~title=() =>
          inLane(e)
            ? `${VoiceLane.label(model, e)}, per-voice (${FxRack.hostName(e)}'s parameters): ${summary(e)}. Drag it sideways to move it, right-click to duplicate it or move it to the whole sound.`
            : `${FxRack.label(rack(), e)}, whole sound (${FxRack.hostName(e)}'s parameters): ${summary(e)}. Drag it sideways to move it, right-click to duplicate it or move it to per-voice.`,
        (ev, t) =>
          if inLane(e) {
            pressItem(Fx(e), ev)
          } else {
            switch ev->button {
            | 0 =>
              ev->preventDefault
              let others =
                rack()
                ->Array.filter(o => o != e)
                ->Array.filterMap(o => effectTabs->Map.get(FxRack.value(o))->Option.map(((t, _, _)) => t))
              Reorder.start(ev, t, ~others, ~onDrop=pos => move(e, pos), ~onClick=() => select(Rack(e)))
            | 2 =>
              ev->preventDefault
              rackMenu(e, t)
            | _ => ()
            }
          },
      )
      effectTabs->Map.set(FxRack.value(e), made)
      made
    }
  filterNode->onPointer(#pointerdown, ev => pressItem(FilterNode, ev))
  ampNode->onPointer(#pointerdown, ev => pressItem(AmpNode, ev))

  // Oatmeal's distortion: dragged before or after the filter, or into the whole sound. With
  // "double" it shows in both, the whole sound's an echo of the per-voice one, without a light.
  let dragDist = (ev, t, ~from) => {
    ev->preventDefault
    let landing = [Pre, Post, Global]
    Reorder.start(
      ev,
      t,
      ~others=[filterNode, wholeLabel],
      ~markAt=pos =>
        switch pos {
        | 0 => Some((filterNode, true))
        | 1 => Some((filterNode, false))
        | _ => Some((wholeLabel, false))
        },
      ~onDrop=pos =>
        landing[pos]->Option.forEach(p =>
          // (dropped where it already was, a double one stays double)
          if p != from {
            setPlace(p)
          }
        ),
      ~onClick=() => select(Distortion),
    )
  }
  let distTitle = () => {
    let where = switch placeNow() {
    | Pre => "per-voice, before the filter"
    | Post => "per-voice, after the filter"
    | Global => "on the whole sound"
    | Both => "per-voice before the filter, and again on the whole sound (\"double\")"
    }
    `Oatmeal's distortion, ${where}: drag it before or after the filter, or into the whole sound; right-click for its places`
  }
  let (distTab, distLed, distLabel) = effectTab(dist, ~dest=Distortion, ~title=distTitle, (ev, t) =>
    switch ev->button {
    | 0 => dragDist(ev, t, ~from=placeNow() == Both ? Pre : placeNow())
    | 2 =>
      ev->preventDefault
      distMenu(t)
    | _ => ()
    }
  )
  distLabel->setTextContent("distortion")
  let distEcho = el("div", ~cls="fxtab echo")
  let echoIcon = el("span", ~cls="fxic", ~parent=distEcho)
  Icons.rackKind("distortion")->Option.forEach(i => echoIcon->appendChild(Icons.render(i)))
  el("span", ~cls="fxname", ~text="distortion", ~parent=distEcho)->ignore
  hover(distEcho, () =>
    "Oatmeal's distortion again, on the whole sound (\"double\"): its light is on the per-voice one. Drag it out of here to have it per-voice only."
  )
  distEcho->suppressContextMenu
  distEcho->onPointer(#pointerdown, ev =>
    switch ev->button {
    | 0 => dragDist(ev, distEcho, ~from=Global)
    | 2 =>
      ev->preventDefault
      distMenu(distEcho)
    | _ => ()
    }
  )
  tabs->Array.push((Distortion, distEcho))

  let addButton = (title, onPress) => {
    let a = el("div", ~cls="fxtab add", ~text="+")
    hover(a, title)
    a->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        onPress(a)
      }
    })
    a
  }
  let laneAdd = addButton(
    () => "Add a per-voice effect: each voice runs its own copy, which its LFOs, envelopes and key move for that note alone",
    a => VoiceLane.addMenu(ctx, a, ~onAdded=e => select(Rack(e))),
  )
  let rackAdd = addButton(() => "Add an effect to the end of the whole sound", addMenu)

  //==============================================================================
  // laying out the strip

  let arrow = () => el("span", ~cls="fxsep", ~text="›")
  // an effect's light and size: an effect that is off shrinks to its icon
  let showState = ((t, led, _), on) => {
    led->toggleClass("lit", on)
    t->toggleClass("idle", !on)
  }
  let layoutStrip = () => {
    strip->setTextContent("")
    voiceZone->setTextContent("")
    wholeZone->setTextContent("")
    let lane = VoiceLane.lane(model)
    let list = rack()
    let place = placeNow()
    let distOn = FxRack.isOn(dist, get)
    showState((distTab, distLed, distLabel), distOn)
    distEcho->toggleClass("idle", !distOn)

    // per-voice: the lane's items in order, the distortion beside the filter
    let chain = (zone, pieces) =>
      pieces->Array.forEachWithIndex((p, i) => {
        if i > 0 {
          zone->appendChild(arrow())
        }
        zone->appendChild(p)
      })
    voiceZone->appendChild(voiceLabel)
    chain(
      voiceZone,
      VoiceLane.items(get)->Array.flatMap(item =>
        switch item {
        | Fx(e) =>
          let made = tabOf(e)
          let (t, _, label) = made
          label->setTextContent(FxRack.label(lane, e))
          showState(made, FxRack.isOn(e, get))
          [t]
        | FilterNode =>
          switch place {
          | Pre | Both => [distTab, filterNode]
          | Post => [filterNode, distTab]
          | Global => [filterNode]
          }
        | AmpNode => [ampNode]
        }
      ),
    )
    if !FxRack.laneFull(lane) {
      voiceZone->appendChild(laneAdd)
    }

    // the whole sound: the distortion when it runs there, then the rack
    wholeZone->appendChild(wholeLabel)
    chain(
      wholeZone,
      [
        ...switch place {
        | Global => [distTab]
        | Both => [distEcho]
        | Pre | Post => []
        },
        ...list->Array.map(e => {
          let made = tabOf(e)
          let (t, _, label) = made
          label->setTextContent(FxRack.label(list, e))
          showState(made, FxRack.isOn(e, get))
          t
        }),
      ],
    )
    if FxRack.addable(list, ~lane) != [] {
      wholeZone->appendChild(rackAdd)
    }
    [voiceZone, into, wholeZone, out]->Array.forEach(e => strip->appendChild(e))

    // when it all doesn't fit, the effects that aren't open show their icons only
    strip->toggleClass("tight", false)
    if strip->scrollWidth > strip->clientWidth + 1. {
      strip->toggleClass("tight", true)
    }
    markCurrent()
  }

  // The first effect that is on, per-voice then on the whole sound; or Oatmeal's distortion.
  let firstOn = () =>
    [...VoiceLane.lane(model)->Array.map(e => Rack(e)), Distortion, ...rack()->Array.map(e => Rack(e))]
    ->Array.find(d =>
      switch d {
      | Distortion => FxRack.isOn(dist, get)
      | Rack(e) => FxRack.isOn(e, get)
      }
    )
    ->Option.getOr(Distortion)

  // (once a frame: a program change sets them all)
  let changed = perFrame(() => {
    layoutStrip()
    switch current.contents {
    // an effect that left (a program change, the host) gives way to the first that is on
    | Rack(e) if !FxRack.holds(rack(), e) && !inLane(e) => select(firstOn())
    // one that moved between per-voice and the whole sound gets the editor for there
    | d if destKey(d) != shownKey.contents => select(d)
    | _ => ()
    }
  })
  let rackIds = Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1))
  model->ParamModel.listenEach(
    [...rackIds, "FX_Order", modeId, ...VoiceLane.ids, ...[dist, ...FxRack.all]->Array.map(FxRack.switchId)],
    changed,
  )

  layoutStrip()
  select(firstOn())
  openEffect :=
    (
      e =>
        if e == dist {
          select(Distortion)
        } else {
          select(Rack(e))
        }
    )

  // the tabs skip redrawing while the page is hidden: catch up when it shows (and fit the
  // strip, which can only be measured then)
  let wasShown = ref(false)
  let observer = makeResizeObserver(() => {
    let shown = page->offsetParent->Option.isSome
    if shown && !wasShown.contents {
      layoutStrip()
      select(current.contents)
    }
    wasShown := shown
  })
  observer->observe(page)
}
