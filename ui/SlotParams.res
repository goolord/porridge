// The slots' parameters and the patch's knobs (PorridgeParams: the slots).
//
// The view, presets and programs know a slot's parameters by name, "Fl_Rate@3" (slot 3's flanger
// rate), as internal values with the kind's own range and law. The patch has knobs instead: slot
// 3's are FX3_1 .. FX3_28, each the knob position (0..1) of the parameter its kind has there,
// which hosts automate whatever the slot holds. Only the slot's own kind's parameters reach the
// knobs; the others the view keeps (a program's values have every kind's for every slot, and
// leave out those at their defaults).

let defsById = ParamDefs.byId

// The kind slot g holds, its value read with get.
let kindAt = (get: string => float, g) =>
  PorridgeParams.entryKind(Float.toInt(get(PorridgeParams.slotKindId(g))))

// Slot g, if this parameter says what one holds (FX_Rack_n, VL_n).
let slotOfKindId = id =>
  Array.fromInitializer(~length=PorridgeParams.slotCount, g => g)->Array.find(g => PorridgeParams.slotKindId(g) == id)

// The knob endpoint a slot's parameter is on while its slot holds its kind, if it is.
let knobOf = (get, id) =>
  PorridgeParams.parseSlotParam(id)->Option.flatMap(((first, g)) =>
    kindAt(get, g)->Option.flatMap(k => {
      let i = PorridgeParams.knobIndex(k, first)
      i >= 0 && i < PorridgeParams.knobCount(g) ? Some(PorridgeParams.knobId(g, i + 1)) : None
    })
  )

// A parameter's knob position for a value, and the value at a knob position.
let toKnob = (d: ParamDefs.t, x) => Math.max(0., Math.min(1., d.toNorm(x)))
let fromKnob = (d: ParamDefs.t, v) => d.clamp(d.fromNorm(Math.max(0., Math.min(1., v))))

// The slot parameter on a knob endpoint, for the kind its slot holds.
let paramOfKnob = (get, knob) =>
  PorridgeParams.parseKnobId(knob)->Option.flatMap(((g, i)) =>
    kindAt(get, g)->Option.flatMap(k =>
      PorridgeParams.knobsOf(k)[i - 1]->Option.map(((first, _)) =>
        PorridgeParams.slotParamId(first, PorridgeParams.slotKey(g))
      )
    )
  )

// Slot g's knobs as its parameters' values (read with get) put them, for the kind it holds.
let knobValues = (~def, get, g) =>
  kindAt(get, g)->Option.mapOr([], k =>
    PorridgeParams.knobsOf(k)->Array.filterMapWithIndex(((first, _), i) =>
      i < PorridgeParams.knobCount(g)
        ? {
            let id = PorridgeParams.slotParamId(first, PorridgeParams.slotKey(g))
            def(id)->Option.map(d => (PorridgeParams.knobId(g, i + 1), toKnob(d, get(id))))
          }
        : None
    )
  )

let lookup = id => Lazy.get(defsById)->Map.get(id)

// Every slot's knobs for a program's values.
let allKnobValues = (~def=lookup, get) =>
  Array.fromInitializer(~length=PorridgeParams.slotCount, g => knobValues(~def, get, g))->Array.flat

// The values of a slot's parameters, from its knobs' endpoint values (raw, by endpoint id; a knob
// not there is at 0) for the kind it holds.
let fromKnobs = (~def=lookup, get, raw: string => option<float>, g) =>
  kindAt(get, g)->Option.mapOr([], k =>
    PorridgeParams.knobsOf(k)->Array.filterMapWithIndex(((first, _), i) =>
      i < PorridgeParams.knobCount(g)
        ? {
            let id = PorridgeParams.slotParamId(first, PorridgeParams.slotKey(g))
            def(id)->Option.map(d => (id, fromKnob(d, raw(PorridgeParams.knobId(g, i + 1))->Option.getOr(0.))))
          }
        : None
    )
  )

//==============================================================================
// the modulation matrix's slot targets (ModMatrix.Slot): a connection to slot 3's knob 2 moves
// what slot 3's kind has there, the parameter "X@3"

// Whether a kind's parameter can be a connection's target (the matrix had a target for it).
let modulatable = Lazy.make(() => ModMatrix.targets->Array.map(t => t.key)->Set.fromArray)
let isModulatable = first => Lazy.get(modulatable)->Set.has(first)

// The kind a slot parameter's first id belongs to.
let kindOfFirst = first =>
  PorridgeParams.rackKinds->Array.find(k => k.params->Array.some(((p, _)) => p == first))

// The target that moves a parameter (a slot's: its slot's knob), or -1.
let targetOfParam = id =>
  switch PorridgeParams.parseSlotParam(id) {
  | Some((first, g)) if isModulatable(first) =>
    kindOfFirst(first)->Option.mapOr(-1, k => {
      let i = PorridgeParams.knobIndex(k, first)
      i >= 0 && i < PorridgeParams.knobCount(g) ? ModMatrix.slotTarget(g, i + 1) : -1
    })
  | Some(_) => -1
  | None => ModMatrix.targetOfParam(id)
  }

// A target by its key, or a slot's parameter ("Fl_Rate@3") as its slot's knob.
let targetIndex = key => PorridgeParams.isSlotParam(key) ? targetOfParam(key) : ModMatrix.targetIndex(key)

// The parameter a target moves, read with get (None: none, or not a parameter).
let targetParam = (get, t) =>
  switch ModMatrix.targets[t] {
  | Some({law: Knob(id)}) => Some(id)
  | Some({law: Slot(g, i)}) =>
    paramOfKnob(get, PorridgeParams.knobId(g, i))->Option.filter(id =>
      PorridgeParams.parseSlotParam(id)->Option.mapOr(false, ((first, _)) => isModulatable(first))
    )
  | _ => None
  }

// A slot parameter's name in a route: "flanger rate (FX 3)".
let slotParamLabel = id =>
  switch PorridgeParams.parseSlotParam(id) {
  | Some((first, g)) =>
    let k = kindOfFirst(first)
    let label = k->Option.flatMap(k => k.params->Array.find(((p, _)) => p == first)->Option.map(((_, l)) => l))->Option.getOr(first)
    let kind = k->Option.mapOr("", k => k.menuName->Option.getOr(String.toLowerCase(k.name)) ++ " ")
    `${kind}${label} (${PorridgeParams.slotTitle(g)})`
  | None => id
  }

// A target's name, read with get: a slot's knob says what it moves ("" while it moves nothing).
let targetLabel = (get, t) =>
  switch ModMatrix.targets[t] {
  | Some({law: Slot(_, _)}) => targetParam(get, t)->Option.mapOr("", slotParamLabel)
  | Some(target) => target.label
  | None => ""
  }

// The ids that say what the slots hold (a change can change what a connection moves).
let kindIds = Array.fromInitializer(~length=PorridgeParams.slotCount, PorridgeParams.slotKindId)
