// Parameters Porridge has and Oatmeal doesn't. They follow Oatmeal's 342 parameters as host
// parameters, and live in the synth's parameter mirror from slot `firstSlot` on.
// Append only: hosts and presets know parameters by id, and the order fixes the host order.
// Every default leaves the sound exactly as Oatmeal's.

type kind =
  | Float({min: float, max: float, init: float, text: float => string, unit?: string})
  | Choice({names: array<string>, init: int})

type spec = {id: string, name: string, kind: kind}

let firstSlot = 2600

let percent = x => Float.toFixed(x * 100., ~digits=1) ++ " %"
let signedPercent = x => (x > 0. ? "+" : "") ++ Float.toFixed(x * 100., ~digits=1) ++ " %"

let macroSpecs = Array.fromInitializer(~length=ModMatrix.macros, i => {
  id: ModMatrix.macroId(i + 1),
  name: `Macro ${Int.toString(i + 1)}`,
  kind: Float({min: 0., max: 1., init: 0., text: percent}),
})

let sourceNames = ModMatrix.sources->Array.map(s => s.label)
let targetNames = ModMatrix.targets->Array.map(t => t.label)

let slotSpecs = Array.fromInitializer(~length=ModMatrix.slots, i => {
  let k = i + 1
  let n = Int.toString(k)
  [
    {id: ModMatrix.sourceId(k), name: `Mod ${n} source`, kind: Choice({names: sourceNames, init: 0})},
    {id: ModMatrix.targetId(k), name: `Mod ${n} target`, kind: Choice({names: targetNames, init: 0})},
    {
      id: ModMatrix.amountId(k),
      name: `Mod ${n} amount`,
      kind: Float({min: -1., max: 1., init: 0., text: signedPercent}),
    },
    {id: ModMatrix.viaId(k), name: `Mod ${n} via`, kind: Choice({names: sourceNames, init: 0})},
  ]
})->Array.flat

let semitones = x => Float.toFixed(x, ~digits=1) ++ " st"

let mpeSpecs = [
  {id: "MPE_On", name: "MPE", kind: Choice({names: ["off", "on"], init: 0})},
  {
    id: "MPE_BendRange",
    name: "MPE note bend range",
    kind: Float({min: 0., max: 96., init: 48., text: semitones}),
  },
]

let all = [...macroSpecs, ...slotSpecs, ...mpeSpecs]

let slotOf = i => firstSlot + i
