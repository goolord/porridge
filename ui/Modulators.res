// What moves what, in every system: the modulation matrix's connections (ModMatrix), and
// Oatmeal's own routings, which have their own parameters: the mod envelopes' and the XY pad's
// four target slots each, the assignable controllers' (while a controller is assigned), and
// fixed depths (the LFOs' on the cutoff, resonance, pitch, pan and each other's rate; the filter
// envelope's, the key's, velocity's, aftertouch's and the note's random amounts; the bend range;
// the pitch envelope's switch).
//
// One list of routes (all) serves both questions. What a source moves (from) is shown as chips on
// its panel (Destinations) and as the connections on the Mod page; what moves a parameter (on) is
// shown on every control that shows the parameter, in the sources' colours: Controls' parameter
// rows (a band where a connection's sweep on the knob is known, a mark on the edge for the rest),
// the graphs' points (FxGraph.handle, NodeEditor.node) and the envelopes (EnvEditor). The index
// is worked out once, again (at most once a frame) when a routing changes, and the controls
// watching it refresh then.

open! Web

//==============================================================================
// routes

// What a route moves where no knob of its own shows it. The voice's pitch shows on the voice's
// transpose knob; the envelopes (their speeds, velocity's say in them, and the voice's level,
// which the amp envelope shapes) on their editors, which show these marks (EnvEditor's moved).
let pitchKnob = "GlobalTranspose"
let envMark = key => "env:" ++ key
let ampEnvMark = envMark("ampEnv")
let envMarks = ["ampEnv", "filterEnv", "modEnv1", "modEnv2", ModEdit.pitchEnvKey]->Array.map(envMark)

// How a route leaves its source: a matrix connection (its slot), one of Oatmeal's target slots
// (its target parameter), or one of Oatmeal's fixed depths.
type via = Connection(int) | Slot(string) | Depth

type route = {
  // its source's key (ModMatrix.sources, or ModEdit.pitchEnvKey), and index (-1 for the pitch
  // envelope)
  key: string,
  source: int,
  via: via,
  // what it moves, in its knob's words ("cutoff", "osc 2 transpose")
  label: string,
  // the parameter that holds its amount
  amount: string,
  // the parameters (or envelope marks) it moves; none for the pan
  targets: array<string>,
}

let isBuiltIn = r =>
  switch r.via {
  | Connection(_) => false
  | Slot(_) | Depth => true
  }

let depthIds = (prefix, n) => Array.fromInitializer(~length=n, i => `${prefix}${Int.toString(i + 1)}`)
let lfoDepths = n => {
  let l = `LFO_${Int.toString(n)}_`
  [l ++ "Cutoff_1", l ++ "Cutoff_2", l ++ "Resonance", l ++ "Pitch", l ++ "Pan"]
}

// What a target of Oatmeal's target lists (OatmealParams.xyTargets, modEnvTargets, ccTargets)
// moves, by its name there.
let targetParams = name => {
  let base = String.endsWith(name, " (unipolar)") ? String.slice(name, ~start=0, ~end=String.length(name) - 11) : name
  switch base {
  | "cutoff 1" => ["Cutoff"]
  // (filter 2's cutoff, set as its split from filter 1's)
  | "cutoff 2" => ["F_Split"]
  | "resonance" => ["Resonance"]
  | "filter env mod" => ["F_EnvMod"]
  | "pitch" => [pitchKnob]
  // (more drive: as if the pregain went up)
  | "distortion" => ["Sat_Pregain"]
  | "LFO 1 speed" => ["LFO_1_Speed"]
  | "LFO 2 speed" => ["LFO_2_Speed"]
  | "LFO 1 depth" => lfoDepths(1)
  | "LFO 2 depth" => lfoDepths(2)
  | "1 pulsewidth" => ["O1_PWM_W"]
  | "1 PWM rate" => ["O1_PWM_R"]
  | "1 PWM depth" => ["O1_PWM_D"]
  | "2 pulsewidth" => ["O2_PWM_W"]
  | "2 PWM rate" => ["O2_PWM_R"]
  | "2 PWM depth" => ["O2_PWM_D"]
  | "1 amp" => ["O1_Amp"]
  | "2 amp" => ["O2_Amp"]
  | "noise amp" => ["N_Amp"]
  | "2 pitch" => ["Transpose"]
  | "noise pitch" => ["N_Transpose"]
  | "filter mix" => ["F_Mix"]
  | "noise resonance" => ["N_Resonance"]
  | "ME 1 depth" => depthIds("M1_Depth_", 4)
  | "ME 2 depth" => depthIds("M2_Depth_", 4)
  | "XY depth" => Array.concat(depthIds("XY_H_Depth_", 4), depthIds("XY_V_Depth_", 4))
  | "amp envelope speed" => [ampEnvMark]
  | "filter envelope speed" => [envMark("filterEnv")]
  | "mod envelope speed" => [envMark("modEnv1"), envMark("modEnv2")]
  | "pitch envelope speed" => [envMark(ModEdit.pitchEnvKey)]
  | "Unison detune" => ["U_Detune"]
  | "Unison spread" => ["U_Spread"]
  // (osc 1's pitch and the pan have no knob)
  | _ => []
  }
}

// Oatmeal's target slots, by source: their parameters' prefix and target list.
let slotSets = [
  ("modEnv1", "M1_", OatmealParams.modEnvTargets),
  ("modEnv2", "M2_", OatmealParams.modEnvTargets),
  ("x", "XY_H_", OatmealParams.xyTargets),
  ("y", "XY_V_", OatmealParams.xyTargets),
  ...[1, 2, 3, 4, 5, 6]->Array.map(c => (`cc${Int.toString(c)}`, `CC${Int.toString(c)}_`, OatmealParams.ccTargets)),
]

// a controller's number ("CC1" of "CC1_"), which its slots need to be live
let controllerOf = prefix => String.startsWith(prefix, "CC") ? Some(String.slice(prefix, ~start=0, ~end=3)) : None

// The fixed depths each source has: its amount parameter, what it moves in knob words, and the
// parameters (or envelope marks) that shows on.
let fixedDepths = key =>
  switch key {
  | "lfo1" | "lfo2" =>
    let (n, other) = key == "lfo1" ? ("1", "2") : ("2", "1")
    let l = `LFO_${n}_`
    [
      (l ++ "Cutoff_1", "cutoff", ["Cutoff"]),
      (l ++ "Cutoff_2", "filter split", ["F_Split"]),
      (l ++ "Resonance", "resonance", ["Resonance"]),
      (l ++ "Pitch", "pitch", [pitchKnob]),
      (l ++ "Pan", "pan", []),
      // (its output on the other's rate)
      (l ++ other, `LFO ${other} rate`, [`LFO_${other}_Speed`]),
    ]
  | "filterEnv" => [("F_EnvMod", "cutoff", ["Cutoff"])]
  | "key" => [
      ("F_Track", "cutoff", ["Cutoff"]),
      // (higher notes run every envelope faster or slower, and sit further to one side)
      ("FreqEnv", "envelope speeds", envMarks),
      ("FreqPan", "pan", []),
    ]
  | "velocity" => [
      ("VeloSens", "volume", [ampEnvMark]),
      // (it scales the filter envelope's amount)
      ("F_VeloSens", "filter env amount", ["F_EnvMod"]),
      ("M1_VeloSens", "mod env 1", [envMark("modEnv1")]),
      ("M2_VeloSens", "mod env 2", [envMark("modEnv2")]),
      ("PEnv_VeloSens", "pitch env", [envMark(ModEdit.pitchEnvKey)]),
    ]
  | "aftertouch" => [
      ("F_Aftertouch", "cutoff", ["Cutoff"]),
      ("OscAftertouch", "osc levels", ["O1_Amp", "O2_Amp"]),
      ("O1_Afterpitch", "osc 1 pitch", []),
      ("O2_Afterpitch", "osc 2 transpose", ["Transpose"]),
      ("N_Aftertouch", "noise level", ["N_Amp"]),
    ]
  // (Oatmeal's per-note random pitch, pan and level)
  | "random" => [("RandomFreq", "pitch", [pitchKnob]), ("RandomPan", "pan", []), ("RandomAmp", "volume", [ampEnvMark])]
  | "bend" => [("BendRange", "pitch", [pitchKnob])]
  // (its switch: its stages are in semitones)
  | "pitchEnv" => [("PEnv_On", "pitch", [pitchKnob])]
  | _ => []
  }

// Every source that can have a route, in the menus' order, and the pitch envelope.
let sourceKeys = Lazy.make(() => [
  ...ModEdit.sourceOrder->Array.filterMap(s => ModMatrix.sources[s]->Option.map(s => s.key)),
  ModEdit.pitchEnvKey,
])

// A matrix connection's target as a route moves it: its knob, or for the voice's pitch and
// volume, where those show.
// (a slot's knob: what the slot's kind has there, read with get)
let connectionTargets = (get, t) =>
  switch ModMatrix.targets[t]->Option.map(t => t.law) {
  | Some(Knob(id)) => [id]
  | Some(Slot(_, _)) => SlotParams.targetParam(get, t)->Option.mapOr([], id => [id])
  | Some(Pitch(_)) => [pitchKnob]
  | Some(Volume) => [ampEnvMark]
  | Some(Pan | Retired) | None => []
  }

// The matrix's connections, read with get, in slot order.
let connections = (get: string => float) =>
  ModMatrix.slotNumbers->Array.filterMap(k => {
    let s = ModMatrix.readSlot(get, k)
    switch (ModMatrix.sources[s.source], ModMatrix.targets[s.target]) {
    | (Some(source), Some(_)) if s.source > 0 && s.target > 0 =>
      Some({
        key: source.key,
        source: s.source,
        via: Connection(k),
        label: SlotParams.targetLabel(get, s.target),
        amount: ModMatrix.amountId(k),
        targets: connectionTargets(get, s.target),
      })
    | _ => None
    }
  })

// A fixed depth that Init sets to something other than 0 (the bend range, velocity's say in the
// volume, the note's random pitch and volume) is in every program, so it says nothing about this
// one while it stays there: it's no route of the program's (not listed, counted or marked) until
// it's changed. The Mod page folds those into one row, and the source's own editor shows them
// quietly (atDefaults).
let initOf = id => Lazy.get(ParamDefs.byId)->Map.get(id)->Option.mapOr(0., d => d.init)
let isDefault = (get: string => float, amount) => get(amount) == initOf(amount)

// What source key moves through Oatmeal's own routings, read with get: its slots that have a
// target (a controller's while it's assigned), then its fixed depths that aren't 0 or at their
// Init values.
let builtIns = (get: string => float, key) => {
  let source = ModMatrix.sourceIndex(key)
  let slotRoutes = slotSets->Array.flatMap(((k, prefix, list)) =>
    k != key || controllerOf(prefix)->Option.mapOr(false, cc => get(cc) == 0.)
      ? []
      : [1, 2, 3, 4]->Array.filterMap(i => {
          let n = Int.toString(i)
          let target = `${prefix}Target_${n}`
          switch list[Float.toInt(get(target))] {
          | Some(name) if name != "none" =>
            Some({
              key,
              source,
              via: Slot(target),
              label: OatmealParams.targetName(name),
              amount: `${prefix}Depth_${n}`,
              targets: targetParams(name),
            })
          | _ => None
          }
        })
  )
  let depths = fixedDepths(key)->Array.filterMap(((amount, label, targets)) =>
    get(amount) != 0. && !isDefault(get, amount) ? Some({key, source, via: Depth, label, amount, targets}) : None
  )
  [...slotRoutes, ...depths]
}

// Source key's fixed depths that sit at their Init values, which aren't 0.
let atDefaults = (get: string => float, key) => {
  let source = ModMatrix.sourceIndex(key)
  fixedDepths(key)->Array.filterMap(((amount, label, targets)) =>
    get(amount) != 0. && isDefault(get, amount) ? Some({key, source, via: Depth, label, amount, targets}) : None
  )
}

// Everything source key moves, read with get: Oatmeal's own routings, then the matrix's
// connections from it.
let from = (get, key) => [...builtIns(get, key), ...connections(get)->Array.filter(r => r.key == key)]

// Every route, source by source.
let all = get => {
  let connections = connections(get)
  Lazy.get(sourceKeys)->Array.flatMap(key => [
    ...builtIns(get, key),
    ...connections->Array.filter(r => r.key == key),
  ])
}

// Every fixed depth at its Init value, source by source.
let allAtDefaults = get => Lazy.get(sourceKeys)->Array.flatMap(atDefaults(get, _))

// The parameters that can change what source key moves.
let fromIds = key => [
  ...slotSets->Array.flatMap(((k, prefix, _)) =>
    k != key
      ? []
      : [
          ...controllerOf(prefix)->Option.mapOr([], cc => [cc]),
          ...[1, 2, 3, 4]->Array.flatMap(i => [`${prefix}Target_${Int.toString(i)}`, `${prefix}Depth_${Int.toString(i)}`]),
        ]
  ),
  ...fixedDepths(key)->Array.map(((amount, _, _)) => amount),
  ...ModMatrix.slotNumbers->Array.flatMap(k => [ModMatrix.sourceId(k), ModMatrix.targetId(k), ModMatrix.amountId(k)]),
  // (what the slots hold: what their knobs' connections move)
  ...SlotParams.kindIds,
]

// Whether source key moves anything: a route with an amount.
let movesAnything = (get: string => float, key) => from(get, key)->Array.some(r => get(r.amount) != 0.)

// Every parameter that changes what moves what.
let routingIds = Lazy.make(() =>
  Lazy.get(sourceKeys)->Array.flatMap(fromIds)->Set.fromArray->Set.values->Array.fromIterator
)

//==============================================================================
// the index: what moves each parameter

// a route with an amount, on a parameter: and the knob range it sweeps relative to the knob's
// position, where that is known (a matrix connection on its own knob: ModEdit.rangeOf)
type t = {route: route, range: option<(float, float)>}

let colour = m => ModEdit.keyColour(m.route.key)

// the matrix slot of a connection
let slotOf = m =>
  switch m.route.via {
  | Connection(k) => Some(k)
  | Slot(_) | Depth => None
  }

// a parameter's name as a matrix target ("" for one the matrix can't reach)
let ownLabel = id =>
  switch SlotParams.targetOfParam(id) {
  | _ if PorridgeParams.isSlotParam(id) => SlotParams.slotParamLabel(id)
  | t if t >= 0 => (ModMatrix.targets->Array.getUnsafe(t)).label
  | _ => ""
  }

let build = (model: ParamModel.t) => {
  let get = id => model->ParamModel.get(id)
  let index: Map.t<string, array<t>> = Map.make()
  let add = (id, m) =>
    switch index->Map.get(id) {
    | Some(ms) => ms->Array.push(m)
    | None => index->Map.set(id, [m])
    }
  let routes = all(get)->Array.filter(r => model->ParamModel.has(r.amount) && get(r.amount) != 0.)
  // the matrix's connections first, in slot order (an alt-drag on a knob changes the first's
  // amount), a sweep each where they move a knob of their own
  let slot = r => slotOf({route: r, range: None})->Option.getOr(0)
  routes
  ->Array.filter(r => !isBuiltIn(r))
  ->Array.toSorted((a, b) => Int.toFloat(slot(a) - slot(b)))
  ->Array.forEach(r => {
    let range = switch r.targets {
    | [id] if r.label == ownLabel(id) => Some(ModEdit.rangeOf(get, slot(r)))
    | _ => None
    }
    r.targets->Array.forEach(id => add(id, {route: r, range}))
  })
  routes->Array.filter(isBuiltIn)->Array.forEach(r => r.targets->Array.forEach(id => add(id, {route: r, range: None})))
  index
}

type state = {
  mutable index: option<Map.t<string, array<t>>>,
  watchers: array<unit => unit>,
  // names the macros as the program does
  mutable programs: option<ProgramStore.t>,
}

let states: WeakMap.t<ParamModel.t, state> = WeakMap.make()

let stateOf = model =>
  switch states->WeakMap.get(model) {
  | Some(s) => s
  | None =>
    let s = {index: None, watchers: [], programs: None}
    states->WeakMap.set(model, s)->ignore
    let refresh = perFrame(() => s.watchers->Array.forEach(f => f()))
    model->ParamModel.listenEach(Lazy.get(routingIds)->Array.filter(id => model->ParamModel.has(id)), () => {
      s.index = None
      refresh()
    })
    s
  }

// The program whose macro names the texts use (the view has one).
let nameMacros = (model, programs) => stateOf(model).programs = Some(programs)

// A source's name by key, a macro's as the program names it.
let sourceName = (model, key) =>
  switch stateOf(model).programs {
  | Some(programs) => ModEdit.keyName(programs, key)
  | None => key == ModEdit.pitchEnvKey ? ModEdit.pitchEnvName : ModMatrix.sources->Array.find(s => s.key == key)->Option.mapOr(key, s => s.label)
  }

// What moves parameter id (or an envelope mark), the matrix's connections first.
let on = (model, id) => {
  let s = stateOf(model)
  let index = switch s.index {
  | Some(i) => i
  | None =>
    let i = build(model)
    s.index = Some(i)
    i
  }
  index->Map.get(id)->Option.getOr([])
}

// Calls fn (at most once a frame) whenever what moves what may have changed.
let watch = (model, fn) => stateOf(model).watchers->Array.push(fn)

// A route's amount as its parameter reads it ("+25.0 %", "4.877 oct").
let amountText = (model, r) => (model->ParamModel.def(r.amount)).valueText(model->ParamModel.get(r.amount))

// What a modulator of parameter id does, for status lines: its source and amount, and what it
// moves when that isn't the parameter's own name ("velocity (volume) 50 %").
let text = (model, id, m) => {
  let name = sourceName(model, m.route.key)
  m.route.label == ownLabel(id) ? `${name} ${amountText(model, m.route)}` : `${name} (${m.route.label}) ${amountText(model, m.route)}`
}

// For a status line: what moves these parameters (or marks), after the parameters' own text.
let statusText = (model, ids) =>
  switch ids->Array.flatMap(id => on(model, id)->Array.map(m => text(model, id, m))) {
  | [] => ""
  | texts => `. Moved by ${texts->Array.join(", ")}`
  }

//==============================================================================
// the graphs' points

// Small dots in the modulators' colours around a point on a graph, from the top clockwise, for
// what moves its parameters (ids(), which may change with the point): a group in layer that
// moves with the point (r: the point's largest radius). The group is drawn again only when the
// colours change.
type dots = {group: Dom.element, draw: unit => unit}

let dotsFor = (model, layer, ids: unit => array<string>, ~r) => {
  let group = svgEl(layer, "g", [("class", Str("mdots"))])
  let shown = ref("")
  let draw = () => {
    // (one ring's worth at most)
    let colours = ids()->Array.flatMap(id => on(model, id))->Array.map(colour)->Array.slice(~start=0, ~end=11)
    let key = colours->Array.join(" ")
    if key != shown.contents {
      shown := key
      group->setTextContent("")
      let ring = r + 3.5
      colours->Array.forEachWithIndex((c, i) => {
        let a = -.Math.Constants.pi / 2. + Int.toFloat(i) * 0.55
        svgEl(
          group,
          "circle",
          [("cx", Num(ring * Math.cos(a))), ("cy", Num(ring * Math.sin(a))), ("r", Num(1.7)), ("fill", Str(c))],
        )->ignore
      })
    }
  }
  watch(model, draw)
  draw()
  {group, draw}
}

// Moves the dots to the point at (x, y), and shows them while it shows.
let placeDots = (d, x, y, ~shown=true) => {
  d.draw()
  d.group->setAttribute("transform", Str(`translate(${Float.toString(x)} ${Float.toString(y)})`))
  d.group->setAttribute("display", Str(shown ? "inline" : "none"))
}
