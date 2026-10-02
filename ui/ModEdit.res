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

// a name short enough for a small chip
let shortLabel = s => ModMatrix.sources[s]->Option.mapOr("", s => s.short)

// The macro knob source s is (0 the first), if it's one.
let macroOf = s =>
  switch ModMatrix.sources[s] {
  | Some({kind: Macro(i)}) => Some(i)
  | _ => None
  }

let isController = s => ModMatrix.sources[s]->Option.mapOr(false, s => s.kind == Controller)

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
