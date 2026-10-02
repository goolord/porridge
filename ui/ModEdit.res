// Modulation from the controls: each source's colour and short name, making a connection from a
// source to a parameter's knob, and the parameter controls a source can be dropped on (ModTray
// drags sources onto them; Controls draws each connection's range on its control in the
// source's colour, and lets an alt-drag change its amount).

open! Web

// how much a new connection modulates its target
let defaultAmount = 0.25

// Every source but none, in the menus' order (ModMatrix.sourceGroups, then any it leaves out).
let sourceOrder = {
  let named = ModMatrix.sourceGroups->Array.flatMap(((_, keys)) => keys->Array.map(ModMatrix.sourceIndex))->Array.filter(i => i > 0)
  let rest = ModMatrix.sources->Array.mapWithIndex((_, i) => i)->Array.filter(i => i > 0 && !(named->Array.includes(i)))
  Array.concat(named, rest)
}

// Macro i's name: the one the program gives it, or "macro n".
let macroName = (programs, i) => {
  let name = (programs->ProgramStore.meta).macroNames[i]->Option.getOr("")
  name == "" ? `macro ${Int.toString(i + 1)}` : name
}

let sourceColor = s => ModMatrix.sources[s]->Option.mapOr(ModMatrix.playColour, s => s.colour)

// The macro knob source s is (0 the first), if it's one.
let macroOf = s =>
  switch ModMatrix.sources[s] {
  | Some({kind: Macro(i)}) => Some(i)
  | _ => None
  }

// A source's name, the same in every list of sources and routes: a macro's as its program names
// it ("tone", not "macro 2"), the others by their labels.
let sourceName = (programs, s) =>
  switch (macroOf(s), ModMatrix.sources[s]) {
  | (Some(i), _) => macroName(programs, i)
  | (None, Some(source)) => source.label
  | (None, None) => ""
  }

// The pitch envelope: a source of Oatmeal's own routing (to the pitch) that the matrix can't
// connect, so it has no index there. Routes and source chips know it by this key.
let pitchEnvKey = "pitchEnv"
let pitchEnvName = "pitch env"

// a source's name and colour by its key (ModMatrix.sources, or the pitch envelope)
let keyName = (programs, key) => key == pitchEnvKey ? pitchEnvName : sourceName(programs, ModMatrix.sourceIndex(key))
let keyColour = key => key == pitchEnvKey ? ModMatrix.envColour : sourceColor(ModMatrix.sourceIndex(key))

let isController = s => ModMatrix.sources[s]->Option.mapOr(false, s => s.kind == Controller)

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

// a swatch in a source's colour, for menus
let swatch = colour => {
  let e = el("span", ~cls="icw")
  el("i", ~cls="msw", ~parent=e)->setStyle("background", colour)
  e
}

// A menu of every source by group (each item's value its index), named as the program names
// them; with ~taken, those it holds for are checked and can't be picked.
let sourceItems = (programs, ~taken=?) =>
  sourceGroups->Array.flatMap(((title, members)) =>
    members->Array.mapWithIndex((s, i) => {
      Menu.label: sourceName(programs, s),
      value: s,
      icon: swatch(sourceColor(s)),
      heading: ?(i == 0 ? Some(title) : None),
      checked: ?taken->Option.map(taken => taken(s)),
      disabled: taken->Option.mapOr(false, taken => taken(s)),
    })
  )

let isUsed = (get, k) => {
  let s = ModMatrix.readSlot(get, k)
  s.source > 0 && s.target > 0
}

// The connections that reach a target, in slot order.
let connectionsTo = (get, target) =>
  ModMatrix.slotNumbers->Array.filter(k => isUsed(get, k) && ModMatrix.readSlot(get, k).target == target)

// The knob range connection k sweeps, relative to the knob's position: both ways for a bipolar
// source (or a curve that leaves its sign), one way for the others.
let rangeOf = (get, k) => {
  let s = ModMatrix.readSlot(get, k)
  let bipolar = ModMatrix.sources[s.source]->Option.mapOr(false, x => x.bipolar)
  bipolar ? (-.Math.abs(s.amount), Math.abs(s.amount)) : (Math.min(s.amount, 0.), Math.max(s.amount, 0.))
}

// Connects source to target with this amount in the first free slot, unless it's connected
// already. Returns the slot, or what went wrong.
let connect = (model, source, target, ~amount): result<int, string> => {
  let get = id => model->ParamModel.get(id)
  if connectionsTo(get, target)->Array.some(k => ModMatrix.readSlot(get, k).source == source) {
    Error("already connected")
  } else {
    switch ModMatrix.slotNumbers->Array.find(k => !isUsed(get, k)) {
    | Some(k) =>
      [ModMatrix.holdId(k), ModMatrix.slewId(k), ModMatrix.curveId(k), ModMatrix.stepsId(k), ModMatrix.viaId(k)]->Array.forEach(id =>
        if get(id) != 0. {
          model->ParamModel.gestureSet(id, 0.)
        }
      )
      model->ParamModel.gestureSet(ModMatrix.amountId(k), amount)
      model->ParamModel.gestureSet(ModMatrix.sourceId(k), Int.toFloat(source))
      model->ParamModel.gestureSet(ModMatrix.targetId(k), Int.toFloat(target))
      Ok(k)
    | None => Error(`all ${Int.toString(ModMatrix.slots)} modulation slots are in use`)
    }
  }
}

//==============================================================================
// where a source can be dropped: every parameter control the matrix can reach

type dropTarget = {el: element, id: string, target: int}

let dropTargets: array<dropTarget> = []

let addDropTarget = (el, id, target) => dropTargets->Array.push({el, id, target})

// The shown control under a point (client coordinates), if any.
let dropTargetAt = (x, y) =>
  dropTargets->Array.find(d =>
    d.el->offsetParent->Option.isSome && {
        let r = d.el->getBoundingClientRect
        x >= r.left && x <= r.left + r.width && y >= r.top && y <= r.top + r.height
      }
  )
