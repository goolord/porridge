// Editing the voice lane (FxRack's lane; dsp/VoiceFx.cmajor): its effects in order with the
// filter and the amp envelope among them, adding and taking out effects, and moving one between
// the lane (per-voice) and the rack (the whole sound). The FX page's strip and the synth page
// edit it through here.

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

let get = (model, id) => model->ParamModel.get(id)
let lane = model => FxRack.readLane(get(model, ...))
let rack = model => FxRack.read(get(model, ...))

// The lane's effects and places as these items say (an amp before the filter goes right after it).
let laneOf = (list: array<item>) => {
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
  (lane, {FxRack.filterAt, ampAt: Math.Int.max(filterAt, before(AmpNode))})
}

// Writes the lane as these items say, and the rack as this list (as it is if left out).
let write = (model, list: array<item>, ~rack=?) => {
  let (lane, places) = laneOf(list)
  let rack = rack->Option.getOr(FxRack.read(get(model, ...)))
  setAll(model, FxRack.layout(get(model, ...), ~rack, ~lane, ~places))
}

// Where the lane's effect at index i is once written.
let placedAt = i => ({kind}: FxRack.effect) => {FxRack.kind, place: Lane(i)}

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
    let e = placedAt(Array.length(lane(model)))(e)
    write(model, [...items(get(model, ...)), Fx({...e, place: Fresh})])
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
  FxRack.free(rack(model), ~lane=lane(model), ~forLane=true, e.kind)->Option.map(fresh => {
    let list = items(get(model, ...))
    let i = list->Array.findIndex(x => x == Fx(e))
    list->Array.splice(~start=i + 1, ~remove=0, ~insert=[Fx(fresh)])
    write(model, list)
    let n = lane(model)->Array.findIndex(x => x == e)
    let copy = placedAt(n + 1)(e)
    copySettings(model, ~from=e, ~to=copy)
    copy
  })

// From the lane to the end of the rack, keeping its settings.
let toRack = (model, e: FxRack.effect) => {
  let r = rack(model)
  if !FxRack.laneOnly(e.kind) && FxRack.free(r, e.kind) != None {
    write(model, items(get(model, ...))->Array.filter(x => x != Fx(e)), ~rack=[...r, e])
    true
  } else {
    false
  }
}

// From the rack to the end of the lane.
let fromRack = (model, e: FxRack.effect) =>
  if FxRack.canBeInLane(e) && !FxRack.laneFull(lane(model)) {
    write(model, [...items(get(model, ...)), Fx(e)], ~rack=rack(model)->Array.filter(x => x != e))
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

// An add menu's entries that can be added, in their groups (FxRack.menuGroups): what each adds
// (the first of its kinds that can be added, and how to set it up), and the menu's items, each
// with its icon.
// (atLimit: the kinds the rack can't take another of, shown greyed out with why: the convolver,
// one at a time)
let kindMenu = (~addable, ~atLimit=[]) => {
  let entries = FxRack.menuGroups->Array.flatMap(((title, entries)) =>
    entries
    ->Array.filterMap((entry: FxRack.addEntry) =>
      switch entry.kinds->Array.find(k => addable->Array.includes(k)) {
      | Some(k) => Some((entry, k, false))
      | None => entry.kinds->Array.find(k => atLimit->Array.includes(k))->Option.map(k => (entry, k, true))
      }
    )
    ->Array.mapWithIndex(((entry, k, full), i) => (entry, k, full, i == 0 ? Some(title) : None))
  )
  let items = entries->Array.mapWithIndex(((entry, _, full, heading), i) => {
    Menu.label: full ? entry.name ++ " (one at a time)" : entry.name,
    value: i,
    disabled: full,
    icon: ?Icons.rackKind(entry.icon)->Option.map(icon => {
      let wrap = el("span", ~cls="icw")
      wrap->appendChild(Icons.render(icon))
      wrap
    }),
    ?heading,
    hint: full ? `Porridge runs one ${FxRack.kindName(Array.getUnsafe(entry.kinds, 0))} at a time (its impulse and spectra are most of its memory), and the rack has one` : entry.about,
  })
  (entries->Array.map(((entry, k, _, _)) => (k, entry.setup)), items)
}

// Sets an effect up as its add menu entry says.
let setUp = (model, e, setup) =>
  setup->Array.forEach(((first, x)) => model->ParamModel.gestureSet(FxRack.id(e, first), x))

// The menu of kinds to add to the lane, below an element; onAdded gets the new effect.
let addMenu = (ctx: Ctx.t, anchor, ~onAdded) => {
  let model = ctx.model
  let addable = FxRack.addable(rack(model), ~lane=lane(model), ~forLane=true)
  let (picks, items) = kindMenu(~addable)
  if picks == [] {
    ctx.toast(`There are already ${Int.toString(PorridgeParams.laneSlots)} per-voice effects`)
  } else {
    ctx.menu->Menu.show(anchor, items, -1, i =>
      picks[i]->Option.forEach(((k, setup)) =>
        add(model, k)->Option.forEach(e => {
          setUp(model, e, setup)
          onAdded(e)
        })
      )
    )
  }
}

// A lane effect's right-click menu.
let menu = (ctx: Ctx.t, e: FxRack.effect, anchor, ~onRemoved=() => ()) => {
  let model = ctx.model
  let canCopy = FxRack.free(rack(model), ~lane=lane(model), ~forLane=true, e.kind) != None
  let canMove = !FxRack.laneOnly(e.kind) && FxRack.free(rack(model), e.kind) != None
  ctx.menu->Menu.show(
    anchor,
    [
      ...canCopy ? [{Menu.label: "duplicate", value: 0}] : [],
      ...canMove ? [{Menu.label: "move to the whole sound", value: 1}] : [],
      {Menu.label: "remove", value: 2},
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
