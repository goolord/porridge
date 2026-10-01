// The patch's stored state, which the host saves with the session (the parameters it saves on
// its own): the bank (Preset.encodeBank), the current program's index, and the current
// program's shapes (Bank.encodeShapes), microtuning (Bank.encodeTuning) and convolver
// impulses (Impulse.encode).

type key =
  | @as("bank") Bank
  | @as("program") Program
  | @as("shapes") Shapes
  | @as("tuning") Tuning
  | @as("impulses") Impulses

external name: key => string = "%identity"

let all = [Bank, Program, Shapes, Tuning, Impulses]
let keyOf = s => all->Array.find(key => name(key) == s)

let request = (pc, key) => pc->PatchConnection.requestStoredStateValue(name(key))
let send = (pc, key, value) => pc->PatchConnection.sendStoredStateValue(name(key), value)

// Whether a stored bank holds programs (a new instance has none yet).
let isBank = s => String.length(s) > 1000
