// Parameters the patch keeps in its stored state instead of as endpoints: the custom shape's
// points (PorridgeParams.shaperParams: the count, then each point's in, out and bend) of the
// distortion and of its rack copies, 49 numbers each, which nothing automates or modulates.
//
// Everywhere else they are parameters like any other: ParamModel holds them, programs, presets,
// undo and A/B keep them by id. Only the way to the patch differs: a distortion's 49 values go
// to the DSP as one shaperIn event (dsp/ParamStore.cmajor puts them in their slots), and the
// host saves them with the session under the stored-state key "params", as a JSON object of
// the values that differ from their defaults. (A state saved while they were endpoints names
// them as parameters; the CLAP wrapper moves those into "params" when it loads one.)

let shaperIds = PorridgeParams.shaperParams->Array.map(Pair.first)

// The distortions in shaperIn's order (`which`): Oatmeal's, then every slot's (a slot holding a
// distortion keeps its points as "Sat_X1@3" ...), the rack's then the lane's.
let groups = [
  shaperIds,
  ...PorridgeParams.slotKeys->Array.map(key => shaperIds->Array.map(PorridgeParams.slotParamId(_, key))),
]

let ids = groups->Array.flat

let groupById = groups->Array.flatMapWithIndex((g, k) => g->Array.map(id => (id, k)))->Map.fromArray

let isStored = id => groupById->Map.has(id)

// which distortion a stored parameter belongs to
let groupOf = id => groupById->Map.get(id)

let endpoint = "shaperIn"

let init = ParamDefs.initOf

type payload = {which: int, values: array<float>}

// distortion k's values, each from get
let groupValues = (k, get: string => float) => groups[k]->Option.getOr([])->Array.map(get)

// Sends distortion k's points to the patch, each value from get.
let send = (pc, k, get) =>
  pc->PatchConnection.sendEventOrValueNow(endpoint, {which: k, values: groupValues(k, get)})

// A program's values to the patch: the endpoints', and the stored ones in their events.
let sendProgram = (pc, values: Map.t<string, float>) => {
  values->Map.forEachWithKey((x, id) =>
    if !isStored(id) && !PorridgeParams.isSlotParam(id) {
      pc->PatchConnection.sendEventOrValueNow(id, x)
    }
  )
  let get = id => values->Map.get(id)->Option.getOr(init(id))
  // (the slots' parameters are their knobs to the patch: SlotParams)
  SlotParams.allKnobValues(get)->Array.forEach(((knob, v)) => pc->PatchConnection.sendEventOrValueNow(knob, v))
  groups->Array.forEachWithIndex((_, k) => send(pc, k, get))
}

// The stored-state value: the values that differ from their defaults, as a JSON object.
let encode = (get: string => float) => {
  let o = Dict.make()
  ids->Array.forEach(id => {
    let x = get(id)
    if x != init(id) {
      o->Dict.set(id, JSON.Number(x))
    }
  })
  JSON.stringify(JSON.Object(o))
}

// Every stored parameter's value from a stored-state value (its default where it has none, or
// when there is no value at all: a state that has no custom shapes).
let decode = (value: JSON.t): Map.t<string, float> => {
  let o = switch value {
  | String(s) =>
    switch JSON.parseOrThrow(s) {
    | Object(o) => o
    | _ => Dict.make()
    | exception _ => Dict.make()
    }
  | _ => Dict.make()
  }
  ids
  ->Array.map(id => (
    id,
    switch o->Dict.get(id) {
    | Some(Number(x)) if Float.isFinite(x) => x
    | _ => init(id)
    },
  ))
  ->Map.fromArray
}
