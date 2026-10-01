// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes and response
// curves live in the patch's stored state and must be pushed into the DSP here.
// On a fresh instance it installs the factory bank and loads its first program, like
// Oatmeal does when it starts.

open PatchConnection

// A new instance: install the factory bank, as Oatmeal does.
let installFactoryBank = async pc => {
  let factory = switch await Resources.readBytes(pc, "presets/oatmealprs.dat") {
  | Some(bytes) =>
    switch OatmealFormat.parseFile(bytes) {
    | Ok({programs}) => programs->Array.map(p => p.bytes)
    | Error(e) =>
      Console.log("Porridge: factory bank not available: " ++ e)
      []
    }
  | None => []
  }
  let all = Array.fromInitializer(~length=OatmealFormat.bankPrograms, i =>
    switch factory[i] {
    | Some(bytes) => Preset.fromOatmeal(bytes)
    | None => Preset.make(i == 0 ? "Init" : `Init ${Int.toString(i)}`)
    }
  )

  let first = all->Array.getUnsafe(0)
  Bank.sendValues(pc, first.values)
  Bank.sendShapes(pc, first.tables)
  pc->sendStoredStateValue("shapes", Bank.encodeShapes(first.tables))
  pc->sendStoredStateValue("program", 0)
  pc->sendStoredStateValue("bank", Preset.encodeBank(all))
}

let default = pc => {
  let seen = Map.make()
  let settled = ref(false)

  pc->addStoredStateValueListener(({key, value}) => {
    switch (key, value) {
    | ("shapes", String(shapes)) =>
      Bank.decodeShapes(shapes)->Option.forEach(Bank.sendShapes(pc, _))
    | ("tuning", String(tuning)) => Bank.sendTuning(pc, tuning == "" ? None : Bank.decodeTuning(tuning))
    | _ => ()
    }
    if !settled.contents {
      seen->Map.set(key, value)
    }
  })
  pc->requestStoredStateValue("bank")
  pc->requestStoredStateValue("shapes")
  pc->requestStoredStateValue("tuning")

  // Give the host a moment to answer; if there is no bank in the session this is a
  // new instance.
  setTimeout(() => {
    settled := true
    switch seen->Map.get("bank") {
    | Some(JSON.String(bank)) if String.length(bank) > 1000 => ()
    | _ => installFactoryBank(pc)->Promise.ignore
    }
  }, 400)->ignore
}
