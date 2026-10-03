// The effects rack (PorridgeParams.rackKinds): up to eight effects on the whole sound, in the
// order they run, any kind any number of times but one convolver. Oatmeal's chorus, delay,
// reverb and EQ are fixed effects with their own parameters (C_, D_, R_, EQ_); every other effect
// is in a slot, and its parameters are the slot's ("D_Wet@3": PorridgeParams' slots).
//
// The rack is FX_Rack_1..8 together with FX_Order: slots holding one of Oatmeal's four take them
// in FX_Order's order, as the DSP does, so writing the rack writes both. Every other slot's value
// is a kind and an instance, the state the DSP keeps for it, which moves with it.
//
// The voice lane (VL_1..4, PorridgeParams.laneSpecs) holds the same kinds, in every voice instead
// of on the whole sound: only the kinds a voice can run (laneKinds). The resonator and octaver
// are only for the lane. The lane is kept without gaps; VL_FilterAt and VL_AmpAt say how many of
// it come before the filter and the amp envelope.

type kind = [
  | #chorus
  | #delay
  | #reverb
  | #eq
  | #distortion
  | #flanger
  | #phaser
  | #compressor
  | #space
  | #convolve
  | #bode
  | #filter
  | #utility
  | #ambience
  | #air
  | #resonator
  | #octaver
]

let kinds: array<kind> = [
  #chorus,
  #delay,
  #reverb,
  #eq,
  #distortion,
  #flanger,
  #phaser,
  #compressor,
  #space,
  #convolve,
  #bode,
  #filter,
  #utility,
  #ambience,
  #air,
  #resonator,
  #octaver,
]

let key = (k: kind) => (k :> string)

let kindOfKey = s => kinds->Array.find(k => key(k) == s)

let spec = (k: kind) =>
  PorridgeParams.rackKinds->Array.find(r => r.key == key(k))->Option.getOrThrow

let kindName = (k: kind) => spec(k).menuName->Option.getOr(key(k))

// What it does, for the add menu's hover texts.
let about = (k: kind) => spec(k).about

// An entry of the add menus: what it adds (the first of its kinds that is free), named and
// drawn (Icons.rackKind) as it says, and set up so (the first's parameters, and values).
type addEntry = {name: string, icon: string, about: string, kinds: array<kind>, setup: array<(string, float)>}

let entryOf = k => {name: kindName(k), icon: key(k), about: about(k), kinds: [k], setup: []}

// The add menus' groups, by what the entries do, in order: the per-voice menu and the whole
// sound's show the entries each can take, in the same groups. The four space kinds are one
// "reverb" (its tab's model list has them all: SpaceModels); the convolver's cabinets are a
// tone of their own, all wet.
let menuGroups: array<(string, array<addEntry>)> = [
  (
    "drive",
    [
      entryOf(#distortion),
      {
        name: "cabinet",
        icon: "cabinet",
        about: "a speaker cabinet (or a telephone): the convolver, all wet",
        kinds: [#convolve],
        setup: [("Cv_Impulse", Int.toFloat(PorridgeParams.impulseNames->Array.indexOf("cabinet 1×12"))), ("Cv_Mix", 1.)],
      },
    ],
  ),
  ("tone", [#eq, #filter, #air]->Array.map(entryOf)),
  ("movement", [#chorus, #flanger, #phaser]->Array.map(entryOf)),
  ("pitch", [#bode, #octaver, #resonator]->Array.map(entryOf)),
  ("echo", [entryOf(#delay)]),
  (
    "space",
    [
      {
        name: "reverb",
        icon: "reverb",
        about: "a reverb: halls, plates, rooms, springs and more (its model list has them all)",
        kinds: [#space, #reverb, #ambience, #convolve],
        setup: [],
      },
    ],
  ),
  ("dynamics", [entryOf(#compressor)]),
  ("utility", [entryOf(#utility)]),
]

// The kinds a voice can run.
let laneKinds = kinds->Array.filter(k => spec(k).runsIn != Rack)
let laneOnly = (k: kind) => spec(k).runsIn == LaneOnly

// Oatmeal's chorus, delay, reverb and EQ (and its distortion, before the rack): the kinds whose
// first isn't one of the rack's own entries
let isOatmeal = (k: kind) => !spec(k).firstInRack

// Where an effect is: one of Oatmeal's fixed ones (its chorus, delay, reverb and EQ, wherever
// FX_Order puts them in the rack, and its distortion), a rack slot (0..7), a voice lane slot
// (0..3), or nowhere yet (one about to be added, which its slot gets the kind's defaults for).
type place = Fixed | Rack(int) | Lane(int) | Fresh

// An effect: its kind and where it is. Its parameters are its place's (a slot's: "Fl_Rate@3").
type effect = {kind: kind, place: place}

// Oatmeal's four, by their place in FX_Order's permutations (PorridgeParams.fxNames)
let firsts = [{kind: #chorus, place: Fixed}, {kind: #delay, place: Fixed}, {kind: #reverb, place: Fixed}, {kind: #eq, place: Fixed}]
let isFirst = e => e.place == Fixed && isOatmeal(e.kind) && e.kind != #distortion

// Oatmeal's distortion: in the voices or before the rack (Sat_Mode), never in it.
let oatmealDistortion = {kind: #distortion, place: Fixed}

// The slot an effect is in (PorridgeParams' slot index: the rack's 0..7, the lane's 8..11).
let slotOf = e =>
  switch e.place {
  | Rack(n) => Some(n)
  | Lane(n) => Some(PorridgeParams.rackSlots + n)
  | Fixed | Fresh => None
  }

// This effect's parameter for the kind's (its first's) id: Oatmeal's own, or its slot's ("D_Wet" in
// slot 3 is "D_Wet@3").
let id = (e, first) =>
  switch slotOf(e) {
  | Some(g) => PorridgeParams.slotParamId(first, PorridgeParams.slotKey(g))
  | None => first
  }

// Every parameter of this effect.
let params = e => spec(e.kind).params->Array.map(((first, _)) => id(e, first))

// The parameter that switches it on (every kind's first): a switch, or for a chorus or
// distortion, a list whose first value is off.
let switchId = e => id(e, spec(e.kind).params->Array.getUnsafe(0)->Pair.first)

let eqBandTypes = e => [1, 2, 3, 4, 5]->Array.map(b => id(e, `EQ_${Int.toString(b)}_Type`))

let isOn = (e, get: string => float) => get(switchId(e)) != 0.

// The value that switches it on: a chorus as a sine, a distortion as soft clipping.
let onValue = e => ParamDefs.choiceValue(switchId(e), spec(e.kind).onLabel->Option.getOr("on"))

// The kind a rack or lane value holds.
let kindOfValue = v => PorridgeParams.entryKind(v)->Option.flatMap(k => kindOfKey(k.key))

// The rack's effects in the order they run, read like the DSP reads it, with the slots they're in.
let readSlots = (get: string => float): array<(effect, int)> => {
  let order = PorridgeParams.fxOrder(Float.toInt(get("FX_Order")))
  let taken = ref(0)
  let seen = Set.make()
  Array.fromInitializer(~length=PorridgeParams.rackSlots, n => (n, Float.toInt(get(PorridgeParams.rackId(n + 1)))))
  ->Array.filterMap(((n, v)) =>
    if v >= 1 && v <= 4 {
      let fx = order[taken.contents]->Option.flatMap(i => firsts[i])
      taken := taken.contents + 1
      fx->Option.map(e => (e, n))
    } else if v > 4 && !(seen->Set.has(v)) {
      seen->Set.add(v)
      kindOfValue(v)->Option.filter(k => !laneOnly(k))->Option.map(kind => ({kind, place: Rack(n)}, n))
    } else {
      None
    }
  )
}

let read = get => readSlots(get)->Array.map(Pair.first)

// The rack slot an effect in the rack is in (Oatmeal's four: where FX_Order puts them).
let rackSlotOf = (get, e) => readSlots(get)->Array.find(((x, _)) => x == e)->Option.map(Pair.second)

// Whether the rack holds it (effects are records: compared by value).
let holds = (rack: array<effect>, e) => rack->Array.some(x => x == e)

let isFull = rack => Array.length(rack) >= PorridgeParams.rackSlots

//==============================================================================
// the voice lane

// The lane's effects in order (the slots that hold one a voice runs).
let readLane = (get: string => float): array<effect> =>
  Array.fromInitializer(~length=PorridgeParams.laneSlots, n => (n, Float.toInt(get(PorridgeParams.laneId(n + 1)))))
  ->Array.filterMap(((n, v)) => kindOfValue(v)->Option.filter(k => laneKinds->Array.includes(k))->Option.map(kind => {kind, place: Lane(n)}))

// Where the filter and the amp sit in it: how many of its effects come before each (the amp
// never before the filter).
type places = {filterAt: int, ampAt: int}

let readPlaces = (get: string => float, lane): places => {
  let n = Array.length(lane)
  let filterAt = Math.Int.min(n, Float.toInt(get("VL_FilterAt")))
  {filterAt, ampAt: Math.Int.max(filterAt, Math.Int.min(n, Float.toInt(get("VL_AmpAt"))))}
}

let laneFull = lane => Array.length(lane) >= PorridgeParams.laneSlots

//==============================================================================
// writing the rack and the lane

// The parameter values that put these effects in the rack and the lane in these orders (the rack
// and FX_Order, with the effects of Oatmeal's four that are in the rack first, in rack order;
// the lane and its places), read the rest with get. An effect that changes slot takes its
// parameters (its custom shape's points too) and its connections with it, and keeps its
// instance (so its state: its lines, its LFO) when it stays in the rack; one that comes in
// fresh takes its kind's defaults, and the lowest instance of its kind that's free. Connections
// to a slot that ends up holding nothing else are cleared.
let layout = (get: string => float, ~rack: array<effect>, ~lane: array<effect>, ~places: places) => {
  let out: Map.t<string, float> = Map.make()
  let set = (id, x) => out->Map.set(id, x)
  let present = rack->Array.filter(isFirst)->Array.filterMap(e => firsts->Array.findIndexOpt(f => f == e))
  let absent = [0, 1, 2, 3]->Array.filter(i => !(present->Array.includes(i)))
  set("FX_Order", Int.toFloat(PorridgeParams.fxOrderIndex(Array.concat(present, absent))))
  let defOf = id => Lazy.get(ParamDefs.byId)->Map.get(id)
  // every slot's new effect: (slot, effect)
  let moves = []
  // the instances kept in the rack, by kind
  let kept = Map.make()
  rack->Array.forEachWithIndex((e, n) =>
    switch e.place {
    | Rack(old) =>
      let v = Float.toInt(get(PorridgeParams.rackId(old + 1)))
      let ks = kept->Map.get(e.kind)->Option.getOr([])
      kept->Map.set(e.kind, [...ks, PorridgeParams.rackEntries[v]->Option.flatMap(x => x)->Option.mapOr(0, ((_, i)) => i)])
      set(PorridgeParams.rackId(n + 1), Int.toFloat(v))
    | _ => ()
    }
  )
  Array.fromInitializer(~length=PorridgeParams.rackSlots, n => n)->Array.forEach(n =>
    switch rack[n] {
    | None => set(PorridgeParams.rackId(n + 1), 0.)
    | Some(e) if isFirst(e) => ()
    | Some({place: Rack(_)} as e) => moves->Array.push((n, e))
    | Some(e) =>
      // a free instance of its kind
      let k = spec(e.kind)
      let taken = kept->Map.get(e.kind)->Option.getOr([])
      let inst = PorridgeParams.instanceNumbers(k)->Array.find(i => !(taken->Array.includes(i)))->Option.getOr(PorridgeParams.firstInstance(k))
      kept->Map.set(e.kind, [...taken, inst])
      set(PorridgeParams.rackId(n + 1), Int.toFloat(PorridgeParams.entryValue(k.key, inst)))
      moves->Array.push((n, e))
    }
  )
  // (Oatmeal's four: values 1..4 in rack order, as FX_Order takes them)
  let firstValue = ref(1)
  rack->Array.forEachWithIndex((e, n) =>
    if isFirst(e) {
      set(PorridgeParams.rackId(n + 1), Int.toFloat(firstValue.contents))
      firstValue := firstValue.contents + 1
    }
  )
  let n = Array.length(lane)
  let filterAt = Math.Int.min(places.filterAt, n)
  Array.fromInitializer(~length=PorridgeParams.laneSlots, l => l)->Array.forEach(l =>
    switch lane[l] {
    | None => set(PorridgeParams.laneId(l + 1), 0.)
    | Some(e) =>
      set(PorridgeParams.laneId(l + 1), Int.toFloat(PorridgeParams.laneValue(spec(e.kind))))
      moves->Array.push((PorridgeParams.rackSlots + l, e))
    }
  )
  set("VL_FilterAt", Int.toFloat(filterAt))
  set("VL_AmpAt", Int.toFloat(Math.Int.max(filterAt, Math.Int.min(places.ampAt, n))))

  // the effects' parameters into their slots (read before anything is written)
  let shaper = PorridgeParams.shaperParams->Array.map(Pair.first)
  moves->Array.forEach(((g, e)) =>
    if slotOf(e) != Some(g) {
      let key = PorridgeParams.slotKey(g)
      let ids = [...spec(e.kind).params->Array.map(Pair.first), ...(e.kind == #distortion ? shaper : [])]
      ids
      ->Array.reduce([], (acc, first) => acc->Array.includes(first) ? acc : [...acc, first])
      ->Array.forEach(first => {
        let to = PorridgeParams.slotParamId(first, key)
        switch slotOf(e) {
        | Some(_) => set(to, get(id(e, first)))
        | None => defOf(to)->Option.forEach(d => set(to, d.init))
        }
      })
    }
  )
  // the connections to the slots' knobs follow their effects
  let movedFrom = Map.make()
  moves->Array.forEach(((g, e)) => slotOf(e)->Option.forEach(old => movedFrom->Map.set(old, g)))
  ModMatrix.slotNumbers->Array.forEach(k => {
    let t = Float.toInt(get(ModMatrix.targetId(k)))
    switch ModMatrix.targets[t] {
    | Some({law: Slot(g, i)}) =>
      switch movedFrom->Map.get(g) {
      | Some(to) if to != g =>
        set(ModMatrix.targetId(k), i <= ModMatrix.slotKnobs(to) ? Int.toFloat(ModMatrix.slotTarget(to, i)) : 0.)
      | Some(_) => ()
      // (its effect left the slots: the connection goes with it)
      | None => ModMatrix.slotIds(k)->Array.forEach(id => defOf(id)->Option.forEach(d => set(id, d.init)))
      }
    | _ => ()
    }
  })
  out->Map.entries->Iterator.toArray
}

// The values for this rack (the lane as it is).
let values = (get, rack) => {
  let lane = readLane(get)
  layout(get, ~rack, ~lane, ~places=readPlaces(get, lane))
}

// The values for this lane and these places (the rack as it is).
let laneValues = (get, lane, places) => layout(get, ~rack=read(get), ~lane, ~places)

// Where each of a new rack's (or lane's) effects ends up.
let placed = (list: array<effect>, ~lane=false) =>
  list->Array.mapWithIndex((e, n) => isFirst(e) ? e : {...e, place: lane ? Lane(n) : Rack(n)})

// The effect of this kind to add next, to the rack (~forLane=false) or the lane, if there is room:
// a fresh one (the rack holds any number of each kind but one convolver).
let free = (rack, ~lane=[], ~forLane=false, kind) =>
  if forLane {
    laneFull(lane) || !(laneKinds->Array.includes(kind)) ? None : Some({kind, place: Fresh})
  } else if isFull(rack) || laneOnly(kind) {
    None
  } else if isOatmeal(kind) && kind != #distortion && !holds(rack, {kind, place: Fixed}) {
    // (Oatmeal's own first, while it's out)
    Some({kind, place: Fixed})
  } else if rack->Array.filter(e => e.kind == kind && !isFirst(e))->Array.length >= PorridgeParams.instanceCount(spec(kind)) {
    None
  } else {
    Some({kind, place: Fresh})
  }

// The kinds that can still be added to the rack (or the lane).
let addable = (rack, ~lane=[], ~forLane=false) =>
  (forLane ? laneKinds : kinds)->Array.filter(k => free(rack, ~lane, ~forLane, k) != None)

// Kinds the rack can't take another of while it has room (the convolver: one at a time).
let atLimit = rack =>
  isFull(rack) ? [] : kinds->Array.filter(k => !laneOnly(k) && free(rack, k) == None)

// Whether it can go in the lane at all.
let canBeInLane = e => laneKinds->Array.includes(e.kind) && !isFirst(e)

// Its name in the rack (or the lane): the kind, numbered by its place among those of its kind
// when there are several ("delay 2" is the second delay in the rack). The rack's distortions
// count from 2: Oatmeal's distortion, before the rack, is the first.
let label = (rack, e) => {
  let same = rack->Array.filter(x => x.kind == e.kind)
  let i = Math.Int.max(0, same->Array.findIndex(x => x == e))
  switch e.kind {
  | #distortion => `distortion ${Int.toString(i + 2)}`
  | k => Array.length(same) > 1 ? `${kindName(k)} ${Int.toString(i + 1)}` : kindName(k)
  }
}

// The names of its host parameters, for hover texts: "FX 3 …", "Voice FX 2 …", Oatmeal's "D …".
let hostName = e =>
  switch slotOf(e) {
  | Some(g) => PorridgeParams.slotTitle(g)
  | None => "Oatmeal's " ++ kindName(e.kind)
  }

// A key for an effect that stays the same while it is where it is (its tab, its editor).
let tabKey = e =>
  switch e.place {
  | Fixed => "fixed " ++ key(e.kind)
  | Rack(n) => `rack ${Int.toString(n)} ${key(e.kind)}`
  | Lane(n) => `lane ${Int.toString(n)} ${key(e.kind)}`
  | Fresh => "fresh " ++ key(e.kind)
  }

// Every effect there can be: Oatmeal's, and every kind in every slot that can hold it.
let all =
  [
    ...firsts,
    ...Array.fromInitializer(~length=PorridgeParams.rackSlots, n =>
      kinds->Array.filter(k => !laneOnly(k))->Array.map(kind => {kind, place: Rack(n)})
    )->Array.flat,
    ...Array.fromInitializer(~length=PorridgeParams.laneSlots, n => laneKinds->Array.map(kind => {kind, place: Lane(n)}))->Array.flat,
  ]

// The instance (0..) of its kind the DSP runs a rack effect with (its compressor's meter), read
// with get.
let instance = (get: string => float, e) =>
  switch e.place {
  | Rack(n) =>
    let v = Float.toInt(get(PorridgeParams.rackId(n + 1)))
    PorridgeParams.rackEntries[v]->Option.flatMap(x => x)->Option.mapOr(-1, ((_, i)) => i - PorridgeParams.firstInstance(spec(e.kind)))
  | _ => -1
  }
