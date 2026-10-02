// Editing the voice lane (FxRack's lane; dsp/VoiceFx.cmajor): its effects in order with the
// filter and the amp envelope among them, adding and taking out effects, and moving one between
// the lane (in every voice) and the rack (on the whole sound). The FX page's tabs and routing,
// and the synth page's voice FX tab, all edit it through here.

open! Web

// what the lane holds in order: effects, the filter and the amp envelope (the amp never before
// the filter)
type item = Fx(FxRack.effect) | FilterNode | AmpNode

let items = (get: string => float): array<item> => {
  let lane = FxRack.readLane(get)
  let {filterAt, ampAt} = FxRack.readPlaces(get, lane)
  let out = []
  lane->Array.forEachWithIndex((e, i) => {
    if i == filterAt {
      out->Array.push(FilterNode)
    }
    if i == ampAt {
      out->Array.push(AmpNode)
    }
    out->Array.push(Fx(e))
  })
  if filterAt >= Array.length(lane) {
    out->Array.push(FilterNode)
  }
  if ampAt >= Array.length(lane) {
    out->Array.push(AmpNode)
  }
  out
}

// Sets the parameters that differ.
let setAll = (model, values: array<(string, float)>) =>
  values->Array.forEach(((id, v)) =>
    if model->ParamModel.get(id) != v {
      model->ParamModel.gestureSet(id, v)
    }
  )

// Writes the lane as these items say (an amp before the filter goes right after it).
let write = (model, list: array<item>) => {
  let lane = list->Array.filterMap(x =>
    switch x {
    | Fx(e) => Some(e)
    | _ => None
    }
  )
  let before = node => {
    let i = list->Array.findIndex(x => x == node)
    i < 0 ? Array.length(lane) : list->Array.slice(~start=0, ~end=i)->Array.filter(x => x != FilterNode && x != AmpNode)->Array.length
  }
  let filterAt = before(FilterNode)
  setAll(model, FxRack.laneValues(lane, {filterAt, ampAt: Math.Int.max(filterAt, before(AmpNode))}))
}

let get = (model, id) => model->ParamModel.get(id)
let lane = model => FxRack.readLane(get(model, ...))
let rack = model => FxRack.read(get(model, ...))

let switchOn = (model, e: FxRack.effect) => {
  let id = FxRack.switchId(e)
  if get(model, id) == 0. {
    model->ParamModel.gestureSet(id, FxRack.onValue(e))
  }
}

// Adds an effect of this kind at the end of the lane (after the amp), switched on (a filter
// following each note's key fully). Returns it.
let add = (model, kind) =>
  FxRack.free(rack(model), ~lane=lane(model), ~forLane=true, kind)->Option.map(e => {
    write(model, [...items(get(model, ...)), Fx(e)])
    switchOn(model, e)
    if kind == #filter {
      model->ParamModel.gestureSet(FxRack.id(e, "Ff_Track"), 1.)
    }
    e
  })

let remove = (model, e) => write(model, items(get(model, ...))->Array.filter(x => x != Fx(e)))

// Gives effect `to` the settings of `from` (of the same kind).
let copySettings = (model, ~from, ~to) =>
  FxRack.params(from)->Array.forEachWithIndex((id, i) =>
    FxRack.params(to)[i]->Option.forEach(t => model->ParamModel.gestureSet(t, get(model, id)))
  )

// A copy with the same settings, right after it.
let duplicate = (model, e: FxRack.effect) =>
  FxRack.free(rack(model), ~lane=lane(model), ~forLane=true, e.kind)->Option.map(copy => {
    copySettings(model, ~from=e, ~to=copy)
    let list = items(get(model, ...))
    let i = list->Array.findIndex(x => x == Fx(e))
    list->Array.splice(~start=i + 1, ~remove=0, ~insert=[Fx(copy)])
    write(model, list)
    copy
  })

// From the lane to the end of the rack, keeping its settings.
let toRack = (model, e: FxRack.effect) =>
  if !FxRack.laneOnly(e.kind) && !FxRack.isFull(rack(model)) {
    remove(model, e)
    setAll(model, FxRack.values([...rack(model), e]))
    true
  } else {
    false
  }

// From the rack to the end of the lane.
let fromRack = (model, e: FxRack.effect) =>
  if FxRack.canBeInLane(e) && !FxRack.laneFull(lane(model)) {
    setAll(model, FxRack.values(rack(model)->Array.filter(x => x != e)))
    write(model, [...items(get(model, ...)), Fx(e)])
    true
  } else {
    false
  }

// Moves item x to place pos among the others.
let move = (model, x, pos) => {
  let others = items(get(model, ...))->Array.filter(o => o != x)
  others->Array.splice(~start=pos, ~remove=0, ~insert=[x])
  write(model, others)
}

let label = (model, e) => FxRack.label(lane(model), e)

// The add menu's kinds that can be added, in these groups, and its items, each with its icon.
let kindMenu = (~groups, ~addable) => {
  let kinds = groups->Array.flatMap(((title, kinds)) =>
    kinds
    ->Array.filter(k => addable->Array.includes(k))
    ->Array.mapWithIndex((k, i) => (k, i == 0 ? Some(title) : None))
  )
  let items = kinds->Array.mapWithIndex(((k, heading), i) => {
    Menu.label: FxRack.kindName(k),
    value: i,
    icon: ?Icons.rackKind(FxRack.key(k))->Option.map(icon => {
      let wrap = el("span", ~cls="icw")
      wrap->appendChild(Icons.render(icon))
      wrap
    }),
    ?heading,
    hint: FxRack.about(k),
  })
  (kinds->Array.map(Pair.first), items)
}

// The menu of kinds to add to the lane, below an element; onAdded gets the new effect.
let addMenu = (ctx: Ctx.t, anchor, ~onAdded) => {
  let model = ctx.model
  let addable = FxRack.addable(rack(model), ~lane=lane(model), ~forLane=true)
  let (kinds, items) = kindMenu(~groups=FxRack.laneMenuGroups, ~addable)
  if kinds == [] {
    ctx.toast(`Every voice already has ${Int.toString(PorridgeParams.laneSlots)} effects`)
  } else {
    ctx.menu->Menu.show(anchor, items, -1, i => kinds[i]->Option.forEach(k => add(model, k)->Option.forEach(onAdded)))
  }
}

// A lane effect's right-click menu.
let menu = (ctx: Ctx.t, e: FxRack.effect, anchor, ~onRemoved=() => ()) => {
  let model = ctx.model
  let canCopy = FxRack.free(rack(model), ~lane=lane(model), ~forLane=true, e.kind) != None
  let canMove = !FxRack.laneOnly(e.kind) && !FxRack.isFull(rack(model))
  ctx.menu->Menu.show(
    anchor,
    [
      ...canCopy ? [{Menu.label: "duplicate", value: 0}] : [],
      ...canMove ? [{Menu.label: "move to the whole sound", value: 1}] : [],
      {Menu.label: "take out of the voices", value: 2},
    ],
    -1,
    v =>
      switch v {
      | 0 => duplicate(model, e)->ignore
      | 1 =>
        toRack(model, e)->ignore
        onRemoved()
      | _ =>
        remove(model, e)
        onRemoved()
      },
  )
}

// The parameters a change to the lane comes through.
let ids = [
  ...Array.fromInitializer(~length=PorridgeParams.laneSlots, k => PorridgeParams.laneId(k + 1)),
  "VL_FilterAt",
  "VL_AmpAt",
]

let holds = (model, e) => FxRack.holds(lane(model), e)

// A press on a lane item, shown by itemEl: the left button drags it among the others (or clicks
// it), the right opens an effect's menu.
let press = (ctx: Ctx.t, item, ev, ~itemEl, ~vertical=false, ~onClick) =>
  switch ev->button {
  | 0 =>
    ev->preventDefault
    let others = items(get(ctx.model, ...))->Array.filter(o => o != item)->Array.map(itemEl)
    Reorder.start(ev, itemEl(item), ~vertical, ~others, ~onDrop=pos => move(ctx.model, item, pos), ~onClick)
  | 2 =>
    switch item {
    | Fx(e) =>
      ev->preventDefault
      menu(ctx, e, itemEl(item))
    | _ => ()
    }
  | _ => ()
  }
