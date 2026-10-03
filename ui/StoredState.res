// The patch's stored state, which the host saves with the session (the parameters it saves on
// its own): the bank (Preset.encodeBank), the current program's index, and the current
// program's shapes (Bank.encodeShapes), microtuning (Bank.encodeTuning) and convolver
// impulses (Impulse.encode), and its parameters that aren't endpoints (StoredParams: the custom
// shapes' points).

type key =
  | @as("bank") Bank
  | @as("program") Program
  | @as("shapes") Shapes
  | @as("tuning") Tuning
  | @as("impulses") Impulses
  | @as("params") Params

external name: key => string = "%identity"

let all = [Bank, Program, Shapes, Tuning, Impulses, Params]
let keyOf = s => all->Array.find(key => name(key) == s)

let request = (pc, key) => pc->PatchConnection.requestStoredStateValue(name(key))
let send = (pc, key, value) => pc->PatchConnection.sendStoredStateValue(name(key), value)

// Whether a stored bank holds programs (a new instance has none yet).
let isBank = s => String.length(s) > 1000
