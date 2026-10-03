// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes, response curves,
// the convolvers' impulses and the custom shapes' points (StoredParams) live in the patch's
// stored state and must be pushed into the DSP here.
// On a fresh instance it installs the factory bank and loads its first program, like
// Oatmeal does when it starts.

open PatchConnection

// The factory bank, encoded as the stored state keeps it. Converting Oatmeal's bank here
// would take about half a second in the plugin, whose worker runs in QuickJS, so
// tools/bundle.mjs does it (Preset.factoryBank).
let factoryBankPath = "bundle/factory-bank.json"

// Sends tables to the patch, skipping those it was last sent already.
let shapeSender = pc => {
  let sent = Map.make()
  shapes =>
    OatmealFormat.allTables->Array.forEach(table => {
      let data = shapes->OatmealFormat.getTable(table)
      if !(sent->Map.get(table)->Option.mapOr(false, Preset.sameTable(_, data))) {
        sent->Map.set(table, data)
        Bank.sendShape(pc, table, data)
      }
    })
}

// Sends the stored parameters (StoredParams) from a stored-state value, skipping the
// distortions whose points the patch was last sent already.
let storedSender = pc => {
  let sent = Map.make()
  value => {
    let values = StoredParams.decode(value)
    let get = id => values->Map.get(id)->Option.getOr(StoredParams.init(id))
    StoredParams.groups->Array.forEachWithIndex((_, k) => {
      let data = StoredParams.groupValues(k, get)
      if sent->Map.get(k) != Some(data) {
        sent->Map.set(k, data)
        StoredParams.send(pc, k, get)
      }
    })
  }
}

// A new instance: install the factory bank, as Oatmeal does.
let installFactoryBank = async (pc, sendShapes) =>
  switch await Resources.readText(pc, factoryBankPath) {
  | Some(bank) =>
    switch Preset.decodeFirst(bank) {
    | Some(first) =>
      StoredParams.sendProgram(pc, first.values)
      let get = id => first.values->Map.get(id)->Option.getOr(StoredParams.init(id))
      StoredState.send(pc, Params, StoredParams.encode(get))
      sendShapes(first.tables)
      StoredState.send(pc, Shapes, Bank.encodeShapes(first.tables))
      StoredState.send(pc, Program, 0)
      StoredState.send(pc, Bank, bank)
    | None => Console.log("Porridge: the factory bank can't be read")
    }
  | None => Console.log("Porridge: the factory bank is missing (" ++ factoryBankPath ++ ")")
  }

// A host's session from before the rack's slots loads into them (SessionSlots): checked whenever
// the stored parameters arrive (a session's state brings them), once they've settled.
let slotChecker = pc => {
  let pending = ref(false)
  () =>
    if !pending.contents {
      pending := true
      setTimeout(() =>
        pc->requestFullStoredState(state => {
          pending := false
          if SessionSlots.isLegacy(state) {
            SessionSlots.migrate(pc, state)->Array.forEach(w => Console.log("Porridge: " ++ w))
          }
        }), 50)->ignore
    }
}

let default = pc => {
  let checkedBank = ref(false)
  let sendShapes = shapeSender(pc)
  let sendStored = storedSender(pc)
  let checkSlots = slotChecker(pc)
  let sendImpulses = Impulse.sender(pc)

  pc->addStoredStateValueListener(({key, value}) => {
    switch (StoredState.keyOf(key), value) {
    | (Some(Shapes), String(shapes)) => Bank.decodeShapes(shapes)->Option.forEach(sendShapes)
    | (Some(Tuning), String(tuning)) => Bank.sendTuning(pc, Bank.decodeTuning(tuning))
    | (Some(Impulses), String(s)) => sendImpulses(s)
    // (none: a state without custom shapes, whose points are at their defaults)
    | (Some(Params), value) =>
      sendStored(value)
      checkSlots()
    // The patch answers the request below even when there is no bank, which is a new
    // instance. (A host restores a session before the worker starts, or later, replacing
    // the factory bank.)
    | (Some(Bank), bank) if !checkedBank.contents =>
      checkedBank := true
      switch bank {
      | String(bank) if StoredState.isBank(bank) => ()
      // Not from inside this callback: Cmajor replays the replies that came while the worker
      // was starting with a lock held, and storing a value sends it back to the worker,
      // which needs that lock.
      | _ => setTimeout(() => installFactoryBank(pc, sendShapes)->Promise.ignore, 0)->ignore
      }
    | _ => ()
    }
  })
  [StoredState.Bank, Shapes, Tuning, Impulses, Params]->Array.forEach(StoredState.request(pc, _))
}
