// The 64-program bank, as the view sees it. Programs are v38 Oatmeal chunks; the bank
// and the current program's shapes live in the patch's stored state so the host saves
// them with the session (parameters are saved by the host on their own).

open OatmealFormat

type rec t = {
  pc: PatchConnection.t,
  model: ParamModel.t,
  // the current program or the bank changed
  onChange: t => unit,
  message: string => unit,
  shapeListeners: array<unit => unit>,
  mutable current: int,
  mutable programs: array<Uint8Array.t>,
  mutable shapes: tables,
  pendingSend: Set.t<table>,
  mutable learning: option<string>,
  mutable listeners: option<(PatchConnection.storedStateEvent => unit, JSON.t => unit)>,
}

let make = (pc, model, ~onChange, ~onMessage) => {
  let programs = Array.fromInitializer(~length=bankPrograms, i =>
    makeDefaultProgram(`Init ${Int.toString(i)}`)
  )
  {
    pc,
    model,
    onChange,
    message: onMessage,
    shapeListeners: [],
    current: 0,
    programs,
    shapes: programs->Array.getUnsafe(0)->extractTables,
    pendingSend: Set.make(),
    learning: None,
    listeners: None,
  }
}

let fireShapes = t => t.shapeListeners->Array.forEach(fn => fn())

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  switch (key, value) {
  | ("bank", String(bank)) if String.length(bank) > 1000 =>
    t.programs = Bank.decodeBank(bank)
    t.onChange(t)
  | ("program", Number(i)) if Float.isFinite(i) =>
    t.current = Math.Int.max(0, Math.Int.min(bankPrograms - 1, Float.toInt(i)))
    t.onChange(t)
  | ("shapes", String(shapes)) =>
    Bank.decodeShapes(shapes)->Option.forEach(shapes => {
      t.shapes = shapes
      fireShapes(t)
    })
  | _ => ()
  }

let onControllerSeen = (t, cc: JSON.t) => {
  let controller = switch cc {
  | Number(n) => Some(n)
  | Object(fields) =>
    switch fields->Dict.get("controller") {
    | Some(Number(n)) => Some(n)
    | _ => None
    }
  | _ => None
  }
  switch (t.learning, controller) {
  | (Some(id), Some(n)) if Float.isFinite(n) && n >= 1. && n <= 127. =>
    t.model->ParamModel.gestureSet(id, n)
    t.message(`Assigned controller ${Float.toString(n)}`)
    t.learning = None
  | _ => ()
  }
}

let start = t => {
  let stateListener = ev => onState(t, ev)
  let outListener = cc => onControllerSeen(t, cc)
  t.listeners = Some((stateListener, outListener))
  t.pc->PatchConnection.addStoredStateValueListener(stateListener)
  t.pc->PatchConnection.addEndpointListener("ccOut", outListener)
  t.pc->PatchConnection.requestStoredStateValue("bank")
  t.pc->PatchConnection.requestStoredStateValue("program")
  t.pc->PatchConnection.requestStoredStateValue("shapes")
}

let dispose = t =>
  t.listeners->Option.forEach(((stateListener, outListener)) => {
    t.pc->PatchConnection.removeStoredStateValueListener(stateListener)
    t.pc->PatchConnection.removeEndpointListener("ccOut", outListener)
  })

let name = (t, i) => t.programs[i]->Option.mapOr("", getName)

let shape = (t, table) => t.shapes->getTable(table)
let onShapes = (t, fn) => t.shapeListeners->Array.push(fn)

// live edits are sent immediately (throttled to one event per animation frame);
// committed edits are also written to the stored state
let setShape = (t, table, data, ~commit) => {
  t.shapes = t.shapes->setTable(table, TypedArray.copy(data))
  if !(t.pendingSend->Set.has(table)) {
    t.pendingSend->Set.add(table)
    Web.requestAnimationFrame(_ => {
      t.pendingSend->Set.delete(table)->ignore
      Bank.sendShape(t.pc, table, shape(t, table))
    })
  }
  if commit {
    t.pc->PatchConnection.sendStoredStateValue("shapes", Bank.encodeShapes(t.shapes))
    fireShapes(t)
  }
}

// current program as a chunk, with the live parameter values and shapes folded in
let captureCurrent = t => {
  let bytes = t.programs->Array.getUnsafe(t.current)->TypedArray.copy
  Bank.writeValues(bytes, t.model.values)
  allTables->Array.forEach(table => writeTable(bytes, table, shape(t, table)))
  bytes
}

let storeBank = t => t.pc->PatchConnection.sendStoredStateValue("bank", Bank.encodeBank(t.programs))

let apply = (t, bytes) => {
  t.model->ParamModel.setAll(Bank.programValues(bytes))
  t.shapes = extractTables(bytes)
  Bank.sendShapes(t.pc, t.shapes)
  t.pc->PatchConnection.sendStoredStateValue("shapes", Bank.encodeShapes(t.shapes))
  fireShapes(t)
}

let select = (t, i) => {
  let i = mod(mod(i, bankPrograms) + bankPrograms, bankPrograms)
  t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  t.current = i
  apply(t, t.programs->Array.getUnsafe(i))
  t.pc->PatchConnection.sendStoredStateValue("program", i)
  storeBank(t)
  t.onChange(t)
}

let rename = (t, i, name) => {
  if i == t.current {
    t.programs->Array.setUnsafe(i, captureCurrent(t))
  }
  t.programs[i]->Option.forEach(p => setName(p, name->String.trim->String.slice(~start=0, ~end=23)))
  storeBank(t)
  t.onChange(t)
}

let initCurrent = t => {
  let p = makeDefaultProgram("Init")
  t.programs->Array.setUnsafe(t.current, p)
  apply(t, p)
  storeBank(t)
  t.onChange(t)
}

let panic = t => t.pc->PatchConnection.sendEventOrValue("panic", 1)

let loadFile = (t, bytes, filename) =>
  switch parseFile(bytes) {
  | Error(e) => t.message(`${filename} isn't an Oatmeal program or bank (${e})`)
  | Ok({programs: []}) => t.message(`${filename} has no programs in it`)
  | Ok({kind: Program, programs: [p]}) =>
    let bytes = TypedArray.copy(p.bytes)
    t.programs->Array.setUnsafe(t.current, bytes)
    apply(t, bytes)
    t.message(`Loaded "${getName(p.bytes)}" into program ${Int.toString(t.current + 1)}`)
    storeBank(t)
    t.onChange(t)
  | Ok({programs}) =>
    t.programs = Array.fromInitializer(~length=bankPrograms, i =>
      switch programs[i] {
      | Some(p) => TypedArray.copy(p.bytes)
      | None => makeDefaultProgram(`Init ${Int.toString(i)}`)
      }
    )
    t.current = 0
    apply(t, t.programs->Array.getUnsafe(0))
    t.pc->PatchConnection.sendStoredStateValue("program", 0)
    t.message(`Loaded bank ${filename} (${Int.toString(Array.length(programs))} programs)`)
    storeBank(t)
    t.onChange(t)
  }

let download = (bytes, filename) => {
  open! Web
  let url = createObjectURL(makeBlob([bytes], {mimeType: "application/octet-stream"}))
  let a = el("a", ~parent=document->body)
  a->setHref(url)
  a->setDownload(filename)
  a->click
  setTimeout(() => {
    revokeObjectURL(url)
    a->remove
  }, 1000)->ignore
}

let safeName = s =>
  switch s->String.replaceRegExp(/[^A-Za-z0-9 _.-]+/g, "")->String.trim {
  | "" => "program"
  | name => name
  }

let downloadProgram = t => {
  let bytes = captureCurrent(t)
  t.programs->Array.setUnsafe(t.current, bytes)
  download(writeProgramChunk(bytes), safeName(getName(bytes)) ++ ".omp")
}

let downloadBank = t => {
  t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  download(writeBankChunk(t.programs), "porridge bank.omb")
}

let learn = (t, ccId) => {
  t.learning = Some(ccId)
  t.message("Move a controller to assign it to " ++ String.replace(ccId, "CC", "slot "))
}
