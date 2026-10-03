// The effects rack (PorridgeParams.rackKinds): up to eight effects on the whole sound, in the
// order they run, each kind up to three times. The first chorus, delay, reverb and EQ are
// Oatmeal's; the others are numbered copies with parameters of their own (D_Wet: D2_Wet ...).
// Porridge's own effects (flanger, phaser, compressor, algo reverb, convolve, bode, filter,
// utility, ambience, air) are numbered the same way from their first (Fl_Rate, Fl2_Rate ...).
//
// The rack is FX_Rack_1..8 together with FX_Order: slots holding one of Oatmeal's four take them
// in FX_Order's order, as the DSP does, so writing the rack writes both.
//
// The voice lane (VL_1..4, PorridgeParams.laneSpecs) holds the same effects, in every voice
// instead of on the whole sound: only the kinds a voice can run (laneKinds), and an effect is in
// the rack or the lane, not both. The shifter, resonator and octaver are only for the lane. The lane is
// kept without gaps; VL_FilterAt and VL_AmpAt say how many of it come before the filter and the
// amp envelope.

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
  | #shifter
  | #resonator
  | #octaver
]

// copy 1 is Oatmeal's for its four, or the first of Porridge's own (the rack's distortions start
// at 2: Oatmeal's distortion isn't in it)
type effect = {kind: kind, copy: int}

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
  #shifter,
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
  ("pitch", [#bode, #shifter, #octaver, #resonator]->Array.map(entryOf)),
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

// every effect, by the value a rack slot holds for it (0 is empty)
let entries: array<option<effect>> = PorridgeParams.rackEntries->Array.map(entry =>
  entry->Option.flatMap(((k, copy)) => kindOfKey(k)->Option.map(kind => {kind, copy}))
)
let all = entries->Array.filterMap(e => e)

let value = e => entries->Array.findIndex(x => x == Some(e))
let ofValue = v => entries[v]->Option.flatMap(e => e)

// Oatmeal's four, by their place in FX_Order's permutations (PorridgeParams.fxNames)
let firsts = [{kind: #chorus, copy: 1}, {kind: #delay, copy: 1}, {kind: #reverb, copy: 1}, {kind: #eq, copy: 1}]
let isFirst = e => e.copy == 1 && isOatmeal(e.kind)

// Oatmeal's distortion: in the voices or before the rack (Sat_Mode), never in it.
let oatmealDistortion = {kind: #distortion, copy: 1}

// This effect's parameter for the first's (e.g. "D_Wet" for delay copy 3 is "D3_Wet").
let id = (e, first) => e.copy == 1 ? first : PorridgeParams.copyId(first, e.copy)

// Every parameter of this effect.
let params = e => spec(e.kind).params->Array.map(((first, _)) => id(e, first))

// The parameter that switches it on (every kind's first): a switch, or for a chorus or
// distortion, a list whose first value is off.
let switchId = e => id(e, spec(e.kind).params->Array.getUnsafe(0)->Pair.first)

let eqBandTypes = e => [1, 2, 3, 4, 5]->Array.map(b => id(e, `EQ_${Int.toString(b)}_Type`))

let isOn = (e, get: string => float) => get(switchId(e)) != 0.

// The value that switches it on: a chorus as a sine, a distortion as soft clipping.
let onValue = e => ParamDefs.choiceValue(switchId(e), spec(e.kind).onLabel->Option.getOr("on"))

// The rack's effects in the order they run, read like the DSP reads it.
let read = (get: string => float): array<effect> => {
  let order = PorridgeParams.fxOrder(Float.toInt(get("FX_Order")))
  let taken = ref(0)
  let seen = Set.make()
  Array.fromInitializer(~length=PorridgeParams.rackSlots, k =>
    Float.toInt(get(PorridgeParams.rackId(k + 1)))
  )->Array.filterMap(v =>
    switch ofValue(v) {
    | Some(e) if isFirst(e) =>
      let fx = order[taken.contents]->Option.flatMap(i => firsts[i])
      taken := taken.contents + 1
      fx
    | Some(e) if !(seen->Set.has(v)) =>
      seen->Set.add(v)
      Some(e)
    | _ => None
    }
  )
}

// The parameter values that make the rack hold these effects in this order: the slots, and
// FX_Order with the effects of Oatmeal's four that are in the rack first, in rack order.
let values = (rack: array<effect>): array<(string, float)> => {
  let present = rack->Array.filter(isFirst)->Array.filterMap(e => firsts->Array.findIndexOpt(f => f == e))
  let absent = [0, 1, 2, 3]->Array.filter(i => !(present->Array.includes(i)))
  let order = PorridgeParams.fxOrderIndex(Array.concat(present, absent))
  Array.fromInitializer(~length=PorridgeParams.rackSlots, k => (
    PorridgeParams.rackId(k + 1),
    rack[k]->Option.mapOr(0., e => Int.toFloat(value(e))),
  ))->Array.concat([("FX_Order", Int.toFloat(order))])
}

// Whether the rack holds it (effects are records: compared by value).
let holds = (rack: array<effect>, e) => rack->Array.some(x => x == e)

let isFull = rack => Array.length(rack) >= PorridgeParams.rackSlots

//==============================================================================
// the voice lane

// The lane's effects in order (the slots that hold one a voice runs).
let readLane = (get: string => float): array<effect> =>
  Array.fromInitializer(~length=PorridgeParams.laneSlots, k => Float.toInt(get(PorridgeParams.laneId(k + 1))))
  ->Array.filterMap(ofValue)
  ->Array.filter(e => laneKinds->Array.includes(e.kind))

// Where the filter and the amp sit in it: how many of its effects come before each (the amp
// never before the filter).
type places = {filterAt: int, ampAt: int}

let readPlaces = (get: string => float, lane): places => {
  let n = Array.length(lane)
  let filterAt = Math.Int.min(n, Float.toInt(get("VL_FilterAt")))
  {filterAt, ampAt: Math.Int.max(filterAt, Math.Int.min(n, Float.toInt(get("VL_AmpAt"))))}
}

// The parameter values for this lane and these places.
let laneValues = (lane: array<effect>, places: places): array<(string, float)> => {
  let n = Array.length(lane)
  let filterAt = Math.Int.min(places.filterAt, n)
  Array.fromInitializer(~length=PorridgeParams.laneSlots, k => (
    PorridgeParams.laneId(k + 1),
    lane[k]->Option.mapOr(0., e => Int.toFloat(value(e))),
  ))->Array.concat([
    ("VL_FilterAt", Int.toFloat(filterAt)),
    ("VL_AmpAt", Int.toFloat(Math.Int.max(filterAt, Math.Int.min(places.ampAt, n)))),
  ])
}

let laneFull = lane => Array.length(lane) >= PorridgeParams.laneSlots

// The copy of this kind to use next, for the rack (~lane=false) or the lane: the lowest one in
// neither (the lane takes Porridge's own kinds' and the rack's copies, not Oatmeal's firsts).
let free = (rack, ~lane=[], ~forLane=false, kind) =>
  (forLane ? laneFull(lane) || !(laneKinds->Array.includes(kind)) : isFull(rack) || laneOnly(kind))
    ? None
    : all->Array.find(e => e.kind == kind && !holds(rack, e) && !holds(lane, e) && !(forLane && isFirst(e)))

// The kinds that can still be added to the rack (or the lane).
let addable = (rack, ~lane=[], ~forLane=false) =>
  (forLane ? laneKinds : kinds)->Array.filter(k => free(rack, ~lane, ~forLane, k) != None)

// Whether it can go in the lane at all.
let canBeInLane = e => laneKinds->Array.includes(e.kind) && !isFirst(e)

// Its name in the rack (or the lane): the kind, numbered by its place among those of its kind
// when there are several ("delay 2" is the second delay in the rack, whichever copy it is). The
// rack's distortions count from 2: Oatmeal's distortion, before the rack, is the first.
let label = (rack, e) => {
  let same = rack->Array.filter(x => x.kind == e.kind)
  let i = Math.Int.max(0, same->Array.findIndex(x => x == e))
  switch e.kind {
  | #distortion => `distortion ${Int.toString(i + 2)}`
  | k => Array.length(same) > 1 ? `${kindName(k)} ${Int.toString(i + 1)}` : kindName(k)
  }
}

// The names of its host parameters, for hover texts: "Delay 3 …", Oatmeal's "D …", "Flanger …".
let hostName = e =>
  switch e.copy {
  | 1 if isOatmeal(e.kind) => "Oatmeal's " ++ kindName(e.kind)
  | 1 => spec(e.kind).name
  | n => `${spec(e.kind).name} ${Int.toString(n)}`
  }
