// Modulation from the controls: each source's colour and short name, making a connection from a
// source to a parameter's knob, and the parameter controls a source can be dropped on (ModTray
// drags sources onto them; Controls draws each connection's range on its control in the
// source's colour, and lets an alt-drag change its amount).

open! Web

let sourceColor = s =>
  switch ModMatrix.sources[s]->Option.mapOr("", s => s.key) {
  | "lfo1" => "#1c3c73"
  | "lfo2" => "#4a74b4"
  | "lfo3" => "#7895c8"
  | "modEnv1" => "#2e6b3a"
  | "modEnv2" => "#5c8f3c"
  | "ampEnv" | "filterEnv" | "voiceLevel" => "#3d7a6d"
  | "wander" => "#8a6d3b"
  | "macro1" | "macro2" | "macro3" | "macro4" => "#6a2c70"
  | "cc1" | "cc2" | "cc3" | "cc4" | "cc5" | "cc6" => "#7a5a1e"
  | _ => "#a3501c"
  }

// a name short enough for a small chip
let shortLabel = s =>
  switch ModMatrix.sources[s] {
  | Some({key}) if String.startsWith(key, "cc") => "cc " ++ String.slice(key, ~start=2)
  | Some({key: "slide"}) => "slide"
  | Some({key: "modEnv1"}) => "env 1"
  | Some({key: "modEnv2"}) => "env 2"
  | Some({key: "filterEnv"}) => "filter env"
  | Some({key: "voiceLevel"}) => "level"
  | Some({key: "heldNotes"}) => "held"
  | Some({key: "aftertouch"}) => "touch"
  | Some({key: "modWheel"}) => "wheel"
  | Some({key: "bend"}) => "bend"
  | Some(source) => source.label
  | None => ""
  }

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
      [ModMatrix.holdId(k), ModMatrix.slewId(k), ModMatrix.curveId(k), ModMatrix.viaId(k)]->Array.forEach(id =>
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
