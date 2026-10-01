// The effects rack (PorridgeParams.rackKinds): up to eight effects on the whole sound, in the
// order they run, each kind up to four times. The first chorus, delay, reverb and EQ are
// Oatmeal's; the others are numbered copies with parameters of their own (D_Wet: D2_Wet ...).
// Porridge's own effects (flanger, phaser, compressor, algo reverb, convolve, bode, filter,
// utility, ambience, air) are numbered the same way from their first (Fl_Rate, Fl2_Rate ...).
//
// The rack is FX_Rack_1..8 together with FX_Order: slots holding one of Oatmeal's four take them
// in FX_Order's order, as the DSP does, so writing the rack writes both.

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
]

let key = (k: kind) =>
  switch k {
  | #chorus => "chorus"
  | #delay => "delay"
  | #reverb => "reverb"
  | #eq => "eq"
  | #distortion => "distortion"
  | #flanger => "flanger"
  | #phaser => "phaser"
  | #compressor => "compressor"
  | #space => "space"
  | #convolve => "convolve"
  | #bode => "bode"
  | #filter => "filter"
  | #utility => "utility"
  | #ambience => "ambience"
  | #air => "air"
  }

let kindName = (k: kind) =>
  switch k {
  | #eq => "EQ"
  | #space => "algo reverb"
  | #bode => "freq shifter"
  | #convolve => "convolution"
  | k => key(k)
  }

// What it does, for the add menu's hover texts.
let about = (k: kind) =>
  switch k {
  | #chorus => "Oatmeal's chorus: detuned copies of the sound"
  | #delay => "Oatmeal's delay: echoes, left and right"
  | #reverb => "Oatmeal's reverb"
  | #eq => "Oatmeal's EQ: five bands"
  | #distortion => "a distortion: Oatmeal's curves, a shape of your own, or the Airwindows models"
  | #flanger => "a flanger: a short swept delay"
  | #phaser => "a phaser: swept notches"
  | #compressor => "a compressor, one band or three (like OTT)"
  | #space => "an algorithmic reverb: hall, plate, nitrous, basin, vintage"
  | #convolve => "a convolver: rooms, cabinets and odd spaces from impulses, or a file of your own"
  | #bode => "a frequency shifter (Bode), and a shifted delay"
  | #filter => "a filter of any of the synth's types"
  | #utility => "gain, pan, width, phase and bass mono"
  | #ambience => "a very small space: a little stereo and tone"
  | #air => "air: lifts or tames the very top (Airwindows Air4)"
  }

// The add menu's groups, in order.
let menuGroups: array<(string, array<kind>)> = [
  ("drive", [#distortion]),
  ("modulation", [#chorus, #flanger, #phaser, #bode]),
  ("echo & space", [#delay, #reverb, #space, #ambience, #convolve]),
  ("tone & dynamics", [#eq, #filter, #air, #compressor, #utility]),
]

// Oatmeal's chorus, delay, reverb and EQ (and its distortion, before the rack)
let isOatmeal = (k: kind) =>
  switch k {
  | #chorus | #delay | #reverb | #eq | #distortion => true
  | _ => false
  }

let kindOfKey = s => kinds->Array.find(k => key(k) == s)

let spec = (k: kind) =>
  PorridgeParams.rackKinds->Array.find(r => r.key == key(k))->Option.getOrThrow

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

// This effect's parameter for the first's (e.g. "D_Wet" for delay copy 3 is "D3_Wet").
let id = (e, first) => e.copy == 1 ? first : PorridgeParams.copyId(first, e.copy)

// Every parameter of this effect.
let params = e => spec(e.kind).params->Array.map(((first, _)) => id(e, first))

// The parameter that switches it on: a switch, or for a chorus or distortion, a list whose first
// value is off.
let switchId = e =>
  switch e.kind {
  | #chorus => id(e, "C_Mode")
  | #delay => id(e, "D_On")
  | #reverb => id(e, "R_On")
  | #distortion => id(e, "Sat_Type")
  | #eq => id(e, "EQ_On")
  | #flanger => id(e, "Fl_On")
  | #phaser => id(e, "Ph_On")
  | #compressor => id(e, "Cp_On")
  | #space => id(e, "Rv_On")
  | #convolve => id(e, "Cv_On")
  | #bode => id(e, "Bd_On")
  | #filter => id(e, "Ff_On")
  | #utility => id(e, "Ut_On")
  | #ambience => id(e, "Am_On")
  | #air => id(e, "Ai_On")
  }

let eqBandTypes = e => [1, 2, 3, 4, 5]->Array.map(b => id(e, `EQ_${Int.toString(b)}_Type`))

let isOn = (e, get: string => float) => get(switchId(e)) != 0.

// The value that switches it on: a chorus as a sine, a distortion as soft clipping.
let onValue = e =>
  switch e.kind {
  | #distortion => 2.
  | _ => 1.
  }

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

// The copy of this kind to use next: the lowest one out of the rack (Oatmeal's first).
let free = (rack, kind) =>
  isFull(rack) ? None : all->Array.find(e => e.kind == kind && !holds(rack, e))

// The kinds that can still be added.
let addable = rack => kinds->Array.filter(k => free(rack, k) != None)

// Its name in the rack: the kind, numbered by its place among those of its kind when there are
// several ("delay 2" is the second delay in the rack, whichever copy it is). The rack's
// distortions count from 2: Oatmeal's distortion, before the rack, is the first.
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
