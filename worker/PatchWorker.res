// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes, response curves
// and the convolvers' impulses live in the patch's stored state and must be pushed into the DSP here.
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

// A new instance: install the factory bank, as Oatmeal does.
let installFactoryBank = async (pc, sendShapes) =>
  switch await Resources.readText(pc, factoryBankPath) {
  | Some(bank) =>
    switch Preset.decodeFirst(bank) {
    | Some(first) =>
      Bank.sendValues(pc, first.values)
      sendShapes(first.tables)
      StoredState.send(pc, Shapes, Bank.encodeShapes(first.tables))
      StoredState.send(pc, Program, 0)
      StoredState.send(pc, Bank, bank)
    | None => Console.log("Porridge: the factory bank can't be read")
    }
  | None => Console.log("Porridge: the factory bank is missing (" ++ factoryBankPath ++ ")")
  }

let default = pc => {
  let checkedBank = ref(false)
  let sendShapes = shapeSender(pc)

  pc->addStoredStateValueListener(({key, value}) => {
    switch (StoredState.keyOf(key), value) {
    | (Some(Shapes), String(shapes)) => Bank.decodeShapes(shapes)->Option.forEach(sendShapes)
    | (Some(Tuning), String(tuning)) => Bank.sendTuning(pc, Bank.decodeTuning(tuning))
    | (Some(Impulses), String(s)) =>
      Impulse.decode(s)->Array.forEachWithIndex((imp, which) => Impulse.send(pc, which, imp))
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
  [StoredState.Bank, Shapes, Tuning, Impulses]->Array.forEach(StoredState.request(pc, _))
}
