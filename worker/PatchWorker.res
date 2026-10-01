// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes and response
// curves live in the patch's stored state and must be pushed into the DSP here.
// On a fresh instance it installs the factory bank and loads its first program, like
// Oatmeal does when it starts.

open PatchConnection

// The factory bank, encoded as the stored state keeps it. Converting Oatmeal's bank here
// would take about half a second in the plugin, whose worker runs in QuickJS, so
// tools/bundle.mjs does it (Preset.factoryBank).
let factoryBankPath = "bundle/factory-bank.json"

// A new instance: install the factory bank, as Oatmeal does.
let installFactoryBank = async pc =>
  switch await Resources.readText(pc, factoryBankPath) {
  | Some(bank) =>
    switch Preset.decodeFirst(bank) {
    | Some(first) =>
      Bank.sendValues(pc, first.values)
      Bank.sendShapes(pc, first.tables)
      pc->sendStoredStateValue("shapes", Bank.encodeShapes(first.tables))
      pc->sendStoredStateValue("program", 0)
      pc->sendStoredStateValue("bank", bank)
    | None => Console.log("Porridge: the factory bank can't be read")
    }
  | None => Console.log("Porridge: the factory bank is missing (" ++ factoryBankPath ++ ")")
  }

let default = pc => {
  let checkedBank = ref(false)

  pc->addStoredStateValueListener(({key, value}) => {
    switch (key, value) {
    | ("shapes", String(shapes)) =>
      Bank.decodeShapes(shapes)->Option.forEach(Bank.sendShapes(pc, _))
    | ("tuning", String(tuning)) => Bank.sendTuning(pc, tuning == "" ? None : Bank.decodeTuning(tuning))
    // The patch answers the request below even when there is no bank, which is a new
    // instance. (A host restores a session before the worker starts, or later, replacing
    // the factory bank.)
    | ("bank", bank) if !checkedBank.contents =>
      checkedBank := true
      switch bank {
      | String(bank) if String.length(bank) > 1000 => ()
      // Not from inside this callback: Cmajor replays the replies that came while the worker
      // was starting with a lock held, and storing a value sends it back to the worker,
      // which needs that lock.
      | _ => setTimeout(() => installFactoryBank(pc)->Promise.ignore, 0)->ignore
      }
    | _ => ()
    }
  })
  pc->requestStoredStateValue("bank")
  pc->requestStoredStateValue("shapes")
  pc->requestStoredStateValue("tuning")
}
