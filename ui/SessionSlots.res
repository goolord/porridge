// A host's session saved before the rack's slots (October 2026): its effects' copies' parameters
// (D2_Wet, Fl3_Rate, and Porridge's own kinds' firsts, Fl_Rate) aren't the patch's any more, so
// the CLAP wrapper keeps their values in the stored state "params" (tools/clap-patch.mjs), and
// the slots' knobs it never had sit at 0. The worker (worker/PatchWorker.res) loads such a
// session as a program from before the slots would load (Preset.migrateSlots): each effect into
// its slot, its connections with it, and sends the result to the patch.

// The stored value "params" as numbers by id.
let storedNumbers = (values: dict<JSON.t>) =>
  switch values->Dict.get(StoredState.name(Params)) {
  | Some(String(s)) =>
    switch JSON.parseOrThrow(s) {
    | Object(o) => o
    | _ => Dict.make()
    | exception _ => Dict.make()
    }
  | _ => Dict.make()
  }

// Whether a session is from before the slots: it has copies' values, or a slot holds an effect
// whose knobs are all at 0 (no knob of any kind is at 0 for every parameter at its default).
let isLegacy = (state: PatchConnection.fullState) => {
  let params = state.parameters->Option.getOr([])
  let byName = params->Array.map(p => (p.name, p.value))->Map.fromArray
  let get = id => byName->Map.get(id)->Option.getOr(ParamDefs.initOf(id))
  let stored = storedNumbers(state.values->Option.getOr(Dict.make()))
  stored->Dict.keysToArray->Array.some(PorridgeParams.isLegacyId) ||
    Array.fromInitializer(~length=PorridgeParams.slotCount, g => g)->Array.some(g =>
      SlotParams.kindAt(get, g) != None &&
        Array.fromInitializer(~length=PorridgeParams.knobCount(g), i => PorridgeParams.knobId(g, i + 1))->Array.every(knob =>
          byName->Map.get(knob)->Option.getOr(0.) == 0.
        )
    )
}

// The session as a program from before the slots: its parameters (the patch's, and the stored
// copies'), its connections by key (as a file has them) and its impulses; loaded, with what
// loading couldn't keep.
let asProgram = (state: PatchConnection.fullState) => {
  let values = state.values->Option.getOr(Dict.make())
  let params = Dict.make()
  state.parameters
  ->Option.getOr([])
  ->Array.forEach(({name, value}) =>
    if !ModMatrix.isSlotParam(name) && PorridgeParams.parseKnobId(name) == None {
      params->Dict.set(name, JSON.Number(value))
    }
  )
  storedNumbers(values)->Dict.forEachWithKey((x, id) => params->Dict.set(id, x))
  let byName = state.parameters->Option.getOr([])->Array.map(p => (p.name, p.value))->Map.fromArray
  let get = id => byName->Map.get(id)->Option.getOr(ParamDefs.initOf(id))
  let sourceKey = i => ModMatrix.sources[i]->Option.mapOr("none", x => x.key)
  let targetKey = i => ModMatrix.targets[i]->Option.mapOr("none", x => x.key)
  let modulations = ModMatrix.slotNumbers->Array.filterMap(k => {
    let s = ModMatrix.readSlot(get, k)
    s.source > 0 && s.target > 0
      ? Some(
          JSON.Object(
            Dict.fromArray([
              ("source", JSON.String(sourceKey(s.source))),
              ("target", JSON.String(targetKey(s.target))),
              ("amount", JSON.Number(s.amount)),
              ("via", JSON.String(sourceKey(s.via))),
              ("hold", JSON.String(s.hold ? "latch" : "free")),
              ("slew", JSON.Number(s.slew)),
              ("curve", JSON.Number(s.curve)),
              ("steps", JSON.Number(Int.toFloat(s.steps))),
            ]),
          ),
        )
      : None
  })
  let impulses = switch values->Dict.get(StoredState.name(Impulses)) {
  | Some(String(s)) if s != "" =>
    switch JSON.parseOrThrow(s) {
    | j => [("impulses", j)]
    | exception _ => []
    }
  | _ => []
  }
  Preset.fromJsonChecked(
    Dict.fromArray([
      ("name", JSON.String("this session")),
      ("params", JSON.Object(params)),
      ("modulations", JSON.Array(modulations)),
      ...impulses,
    ]),
  )
}

// Loads a session from before the slots into the patch as the slots have it: every parameter (the
// slots' knobs for their kinds'), the custom shapes' points and the stored "params", and the
// impulses if the convolver's moved. Returns what loading it couldn't keep.
let migrate = (pc, state: PatchConnection.fullState) => {
  let (p, warnings) = asProgram(state)
  let get = id => p.values->Map.get(id)->Option.getOr(StoredParams.init(id))
  StoredParams.sendProgram(pc, p.values)
  StoredState.send(pc, Params, StoredParams.encode(get))
  let before = state.values->Option.flatMap(v => v->Dict.get(StoredState.name(Impulses)))
  let now = Impulse.encode(p.impulses)
  // (the worker sends what it changes, as it does any list it's sent)
  if before != Some(JSON.String(now)) && !(before == None && now == "") {
    StoredState.send(pc, Impulses, now)
  }
  warnings
}
