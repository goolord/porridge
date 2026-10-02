// What moves each parameter: the modulation matrix's connections (ModMatrix), and Oatmeal's own
// routings, which have their own parameters: the mod envelopes' and the XY pad's four targets
// each, the assignable controllers' four targets each (while a controller is assigned), the
// LFOs' fixed depths (cutoff, resonance, the other LFO's rate) and the filter's envelope, key,
// velocity and aftertouch amounts.
//
// Every control that shows a parameter can show its modulators the same way, in their sources'
// colours (ModMatrix.sources): Controls' parameter rows (a band where a connection's sweep on the
// knob is known, a mark on the edge for the rest) and the graphs' points (FxGraph.handle,
// NodeEditor.node). The index is worked out once for every parameter, again (at most once a
// frame) when a routing changes, and the controls watching it refresh then.
//
// The other way round, `from` lists what a source moves in every system, which the sources'
// panels show as chips (Destinations).

open! Web

type t = {
  // the source's index in ModMatrix.sources (its colour and name)
  source: int,
  // what it is and how much, for status lines ("mod env 1 +0.50")
  text: string,
  // the knob range it sweeps relative to the knob's position, where that is known (the matrix's
  // connections: ModEdit.rangeOf)
  range: option<(float, float)>,
  // the matrix slot, for a connection
  slot: option<int>,
}

let colour = m => ModEdit.sourceColor(m.source)

//==============================================================================
// Oatmeal's routings

// The parameters a target of Oatmeal's target lists (OatmealParams.xyTargets, modEnvTargets,
// ccTargets) moves; none for those without a control (pitch, pan, the envelopes' speeds but the
// filter envelope's).
let depthIds = (prefix, n) => Array.fromInitializer(~length=n, i => `${prefix}${Int.toString(i + 1)}`)
let lfoDepths = n => {
  let l = `LFO_${Int.toString(n)}_`
  [l ++ "Cutoff_1", l ++ "Cutoff_2", l ++ "Resonance", l ++ "Pitch", l ++ "Pan"]
}

let targetParams = name =>
  switch name {
  | "cutoff 1" | "cutoff 1 (unipolar)" => ["Cutoff"]
  // (filter 2's cutoff, set as its split from filter 1's)
  | "cutoff 2" | "cutoff 2 (unipolar)" => ["F_Split"]
  | "resonance" => ["Resonance"]
  | "filter env mod" => ["F_EnvMod"]
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
  | "2 pitch" | "2 pitch (unipolar)" => ["Transpose"]
  | "noise pitch" | "noise pitch (unipolar)" => ["N_Transpose"]
  | "filter mix" => ["F_Mix"]
  | "noise resonance" => ["N_Resonance"]
  | "ME 1 depth" => depthIds("M1_Depth_", 4)
  | "ME 2 depth" => depthIds("M2_Depth_", 4)
  | "XY depth" => Array.concat(depthIds("XY_H_Depth_", 4), depthIds("XY_V_Depth_", 4))
  | "filter envelope speed" => ["F_Speed"]
  | "Unison detune" => ["U_Detune"]
  | "Unison spread" => ["U_Spread"]
  | _ => []
  }

// A routing: its source (a ModMatrix source key), its depth parameter, the parameters it moves
// (read with get) and whether it's live at all.
type routing = {
  sourceKey: string,
  depth: string,
  targets: (string => float) => array<string>,
  live: (string => float) => bool,
}

let listed = (list: array<string>, id) => (get: string => float) =>
  list[Float.toInt(get(id))]->Option.mapOr([], targetParams)

let always = _ => true

// a slot of four: a mod envelope's, the XY pad's or a controller's
let slots = (sourceKey, prefix, list, ~live=always) =>
  [1, 2, 3, 4]->Array.map(k => {
    let n = Int.toString(k)
    {sourceKey, depth: `${prefix}Depth_${n}`, targets: listed(list, `${prefix}Target_${n}`), live}
  })

let fixed = (sourceKey, depth, targets) => {sourceKey, depth, targets: _ => targets, live: always}

let routings = Lazy.make(() => [
  ...slots("modEnv1", "M1_", OatmealParams.modEnvTargets),
  ...slots("modEnv2", "M2_", OatmealParams.modEnvTargets),
  ...slots("x", "XY_H_", OatmealParams.xyTargets),
  ...slots("y", "XY_V_", OatmealParams.xyTargets),
  ...[1, 2, 3, 4, 5, 6]->Array.flatMap(c => {
    let cc = `CC${Int.toString(c)}`
    slots(`cc${Int.toString(c)}`, cc ++ "_", OatmealParams.ccTargets, ~live=get => get(cc) != 0.)
  }),
  ...[1, 2]->Array.flatMap(n => {
    let l = `LFO_${Int.toString(n)}_`
    [
      fixed(`lfo${Int.toString(n)}`, l ++ "Cutoff_1", ["Cutoff"]),
      fixed(`lfo${Int.toString(n)}`, l ++ "Cutoff_2", ["F_Split"]),
      fixed(`lfo${Int.toString(n)}`, l ++ "Resonance", ["Resonance"]),
    ]
  }),
  // each LFO's output on the other's rate
  fixed("lfo1", "LFO_1_2", ["LFO_2_Speed"]),
  fixed("lfo2", "LFO_2_1", ["LFO_1_Speed"]),
  fixed("filterEnv", "F_EnvMod", ["Cutoff"]),
  fixed("key", "F_Track", ["Cutoff"]),
  // (velocity scales the filter envelope's amount)
  fixed("velocity", "F_VeloSens", ["F_EnvMod"]),
  fixed("aftertouch", "F_Aftertouch", ["Cutoff"]),
  fixed("aftertouch", "OscAftertouch", ["O1_Amp", "O2_Amp"]),
  fixed("aftertouch", "N_Aftertouch", ["N_Amp"]),
  fixed("aftertouch", "O2_Afterpitch", ["Transpose"]),
])

// Every parameter that changes what moves what: the routings' and the matrix slots'.
let routingIds = Lazy.make(() =>
  Array.concat(
    Lazy.get(routings)->Array.flatMap(r =>
      // (a slot's target parameter, and a controller's number: "CC1" of "CC1_Depth_2")
      [r.depth, String.replace(r.depth, "Depth", "Target"), String.slice(r.depth, ~start=0, ~end=3)]
    ),
    ModMatrix.slotNumbers->Array.flatMap(ModMatrix.slotIds),
  )
  ->Set.fromArray
  ->Set.values
  ->Array.fromIterator
)

//==============================================================================
// the index

let build = (model: ParamModel.t) => {
  let get = id => model->ParamModel.get(id)
  let index: Map.t<string, array<t>> = Map.make()
  let add = (id, m) =>
    switch index->Map.get(id) {
    | Some(ms) => ms->Array.push(m)
    | None => index->Map.set(id, [m])
    }
  // the matrix's connections, onto their knobs
  ModMatrix.slotNumbers->Array.forEach(k =>
    if ModEdit.isUsed(get, k) {
      let s = ModMatrix.readSlot(get, k)
      switch ModMatrix.targets[s.target] {
      | Some({law: Knob(id)}) if s.amount != 0. =>
        let label = ModMatrix.sources[s.source]->Option.mapOr("", x => x.label)
        let amount = (model->ParamModel.def(ModMatrix.amountId(k))).valueText(s.amount)
        add(id, {source: s.source, text: `${label} ${amount}`, range: Some(ModEdit.rangeOf(get, k)), slot: Some(k)})
      | _ => ()
      }
    }
  )
  // Oatmeal's routings, by their depths' own names
  Lazy.get(routings)->Array.forEach(r => {
    let depth = get(r.depth)
    let defined = model->ParamModel.has(r.depth)
    if defined && depth != 0. && r.live(get) {
      let d = model->ParamModel.def(r.depth)
      let source = ModMatrix.sourceIndex(r.sourceKey)
      r.targets(get)->Array.forEach(id => add(id, {source, text: `${d.name}: ${d.valueText(depth)}`, range: None, slot: None}))
    }
  })
  index
}

type state = {
  mutable index: option<Map.t<string, array<t>>>,
  watchers: array<unit => unit>,
}

let states: WeakMap.t<ParamModel.t, state> = WeakMap.make()

let stateOf = model =>
  switch states->WeakMap.get(model) {
  | Some(s) => s
  | None =>
    let s = {index: None, watchers: []}
    states->WeakMap.set(model, s)->ignore
    let refresh = perFrame(() => s.watchers->Array.forEach(f => f()))
    model->ParamModel.listenEach(Lazy.get(routingIds)->Array.filter(id => model->ParamModel.has(id)), () => {
      s.index = None
      refresh()
    })
    s
  }

// What moves parameter id, the matrix's connections first.
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

// Calls fn (at most once a frame) whenever what moves the parameters may have changed.
let watch = (model, fn) => stateOf(model).watchers->Array.push(fn)

// For a status line: what moves these parameters, after the parameters' own text.
let statusText = (model, ids) =>
  switch ids->Array.flatMap(id => on(model, id)) {
  | [] => ""
  | ms => `. Moved by ${ms->Array.map(m => m.text)->Array.join(", ")}`
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

//==============================================================================
// what a source moves: the index the other way round

// Oatmeal's target slots, by source: their parameters' prefix and target list (as `routings`).
let slotSets = [
  ("modEnv1", "M1_", OatmealParams.modEnvTargets),
  ("modEnv2", "M2_", OatmealParams.modEnvTargets),
  ("x", "XY_H_", OatmealParams.xyTargets),
  ("y", "XY_V_", OatmealParams.xyTargets),
  ...[1, 2, 3, 4, 5, 6]->Array.map(c => (`cc${Int.toString(c)}`, `CC${Int.toString(c)}_`, OatmealParams.ccTargets)),
]

// The fixed depths each source has, by the name its target has in Oatmeal's lists: the LFOs'
// (cut 1, cut 2, res, pitch, pan and the other's rate), the filter's envelope, key, velocity and
// aftertouch amounts, and the oscillators' and the noise's aftertouch.
let fixedDepths = key =>
  switch key {
  | "lfo1" | "lfo2" =>
    let (n, other) = key == "lfo1" ? ("1", "2") : ("2", "1")
    let l = `LFO_${n}_`
    [
      (l ++ "Cutoff_1", "cutoff 1"),
      (l ++ "Cutoff_2", "cutoff 2"),
      (l ++ "Resonance", "resonance"),
      (l ++ "Pitch", "pitch"),
      (l ++ "Pan", "pan"),
      (l ++ other, `LFO ${other} speed`),
    ]
  | "filterEnv" => [("F_EnvMod", "cutoff 1")]
  | "key" => [("F_Track", "cutoff 1")]
  | "velocity" => [("F_VeloSens", "filter env mod")]
  | "aftertouch" => [
      ("F_Aftertouch", "cutoff 1"),
      ("OscAftertouch", "osc amp"),
      ("O1_Afterpitch", "1 pitch"),
      ("O2_Afterpitch", "2 pitch"),
      ("N_Aftertouch", "noise amp"),
    ]
  | _ => []
  }

// A name from Oatmeal's target lists in the words of the knob it moves, as the matrix's targets
// name it ("1 amp" is "osc 1 amp"), and the rest in the same words.
let targetLabel = name => {
  let unipolar = String.endsWith(name, " (unipolar)")
  let base = unipolar ? String.slice(name, ~start=0, ~end=String.length(name) - 11) : name
  let label = switch base {
  // (filter 2's own cutoff, though the knob it moves is the split)
  | "cutoff 2" => "cutoff 2"
  | "osc amp" => "osc amps"
  | "1 pitch" => "osc 1 pitch"
  | "ME 1 depth" => "mod env 1 depth"
  | "ME 2 depth" => "mod env 2 depth"
  | "amp envelope speed" => "amp env speed"
  | "filter envelope speed" => "filter env speed"
  | "mod envelope speed" => "mod env speed"
  | "pitch envelope speed" => "pitch env speed"
  | _ =>
    switch targetParams(base) {
    | [id] => ModMatrix.targets[ModMatrix.targetOfParam(id)]->Option.mapOr(base, t => t.label)
    | _ => base
    }
  }
  unipolar ? label ++ " (uni)" : label
}

// How a route leaves its source: a matrix connection (its slot), one of Oatmeal's target slots
// (its target parameter), or a fixed depth.
type via = Connection(int) | Slot(string) | Depth

type route = {
  source: int,
  via: via,
  // what it moves, in its knob's words ("cutoff", "osc 2 transpose")
  label: string,
  // the parameter that holds its amount
  amount: string,
  // the parameters it moves (none for pitch, pan ...)
  targets: array<string>,
}

// Everything source key moves, read with get: its Oatmeal slots that have a target (a
// controller's while it's assigned), its fixed depths that aren't 0, then the matrix's
// connections from it.
let from = (get: string => float, key) => {
  let source = ModMatrix.sourceIndex(key)
  let slotRoutes = slotSets->Array.flatMap(((k, prefix, list)) =>
    k != key || String.startsWith(prefix, "CC") && get(String.slice(prefix, ~start=0, ~end=3)) == 0.
      ? []
      : [1, 2, 3, 4]->Array.filterMap(i => {
          let n = Int.toString(i)
          let target = `${prefix}Target_${n}`
          switch list[Float.toInt(get(target))] {
          | Some(name) if name != "none" =>
            Some({source, via: Slot(target), label: targetLabel(name), amount: `${prefix}Depth_${n}`, targets: targetParams(name)})
          | _ => None
          }
        })
  )
  let depths = fixedDepths(key)->Array.filterMap(((amount, name)) =>
    get(amount) != 0. ? Some({source, via: Depth, label: targetLabel(name), amount, targets: targetParams(name)}) : None
  )
  let connections = ModMatrix.slotNumbers->Array.filterMap(k => {
    let s = ModMatrix.readSlot(get, k)
    switch ModMatrix.targets[s.target] {
    | Some(t) if s.source == source && s.target > 0 =>
      Some({
        source,
        via: Connection(k),
        label: t.label,
        amount: ModMatrix.amountId(k),
        targets: switch t.law {
        | Knob(id) => [id]
        | _ => []
        },
      })
    | _ => None
    }
  })
  [...slotRoutes, ...depths, ...connections]
}

// The parameters that can change what source key moves.
let fromIds = key => [
  ...slotSets->Array.flatMap(((k, prefix, _)) =>
    k != key
      ? []
      : [
          String.slice(prefix, ~start=0, ~end=3),
          ...[1, 2, 3, 4]->Array.flatMap(i => [`${prefix}Target_${Int.toString(i)}`, `${prefix}Depth_${Int.toString(i)}`]),
        ]
  ),
  ...fixedDepths(key)->Array.map(Pair.first),
  ...ModMatrix.slotNumbers->Array.flatMap(k => [ModMatrix.sourceId(k), ModMatrix.targetId(k), ModMatrix.amountId(k)]),
]

// Whether source key moves anything: a route with an amount.
let movesAnything = (get: string => float, key) => from(get, key)->Array.some(r => get(r.amount) != 0.)
