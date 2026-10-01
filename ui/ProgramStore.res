// The 64-program bank, as the view sees it. Programs are Porridge presets (Preset.res); the
// bank and the current program's shapes live in the patch's stored state so the host saves
// them with the session (parameters are saved by the host on their own).

open OatmealFormat

type rec t = {
  pc: PatchConnection.t,
  model: ParamModel.t,
  // the current program or the bank changed
  onChange: t => unit,
  message: string => unit,
  shapeListeners: array<unit => unit>,
  // the current program or the bank changed
  changeListeners: array<unit => unit>,
  mutable current: int,
  mutable programs: array<Preset.t>,
  mutable shapes: tables,
  mutable tuning: option<Scala.source>,
  pendingSend: Set.t<table>,
  mutable learning: option<string>,
  mutable listeners: option<(PatchConnection.storedStateEvent => unit, JSON.t => unit)>,
}

let make = (pc, model, ~onChange, ~onMessage) => {
  let programs = Array.fromInitializer(~length=bankPrograms, i =>
    Preset.make(`Init ${Int.toString(i)}`)
  )
  {
    pc,
    model,
    onChange,
    message: onMessage,
    shapeListeners: [],
    changeListeners: [],
    current: 0,
    programs,
    shapes: Preset.copyTables((programs->Array.getUnsafe(0)).tables),
    tuning: None,
    pendingSend: Set.make(),
    learning: None,
    listeners: None,
  }
}

let changed = t => {
  t.onChange(t)
  t.changeListeners->Array.forEach(fn => fn())
}

let onChanged = (t, fn) => t.changeListeners->Array.push(fn)

let fireShapes = t => t.shapeListeners->Array.forEach(fn => fn())

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  switch (key, value) {
  | ("bank", String(bank)) if String.length(bank) > 1000 =>
    Preset.decodeBank(bank)->Option.forEach(presets => {
      t.programs = Array.fromInitializer(~length=bankPrograms, i =>
        presets[i]->Option.getOr(Preset.make(`Init ${Int.toString(i)}`))
      )
      changed(t)
    })
  | ("program", Number(i)) if Float.isFinite(i) =>
    t.current = Math.Int.max(0, Math.Int.min(bankPrograms - 1, Float.toInt(i)))
    changed(t)
  | ("tuning", String(s)) =>
    t.tuning = s == "" ? None : Bank.decodeTuning(s)
    changed(t)
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
}

// The bank, program, shapes and tuning, from a full stored state.
let loadState = (t, values) =>
  ["bank", "program", "shapes", "tuning"]->Array.forEach(key =>
    values->Dict.get(key)->Option.forEach(value => onState(t, {key, value}))
  )

let dispose = t =>
  t.listeners->Option.forEach(((stateListener, outListener)) => {
    t.pc->PatchConnection.removeStoredStateValueListener(stateListener)
    t.pc->PatchConnection.removeEndpointListener("ccOut", outListener)
  })

let name = (t, i) => t.programs[i]->Option.mapOr("", Preset.name)
let meta = t => (t.programs->Array.getUnsafe(t.current)).meta

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

// the current program with the live parameter values and shapes
let captureCurrent = (t): Preset.t => {
  ...t.programs->Array.getUnsafe(t.current),
  values: Map.fromArray(t.model.values->Map.entries->Array.fromIterator),
  tables: Preset.copyTables(t.shapes),
  tuning: t.tuning,
}

let storeBank = t =>
  t.pc->PatchConnection.sendStoredStateValue("bank", Preset.encodeBank(t.programs))

let sendTuning = t => {
  Bank.sendTuning(t.pc, t.tuning)
  t.pc->PatchConnection.sendStoredStateValue("tuning", Bank.encodeTuning(t.tuning))
}

let apply = (t, preset: Preset.t) => {
  t.tuning = preset.tuning
  sendTuning(t)
  t.model->ParamModel.setAll(preset.values)
  t.shapes = Preset.copyTables(preset.tables)
  Bank.sendShapes(t.pc, t.shapes)
  t.pc->PatchConnection.sendStoredStateValue("shapes", Bank.encodeShapes(t.shapes))
  fireShapes(t)
}

// Switches to program i, first keeping the live edits in the current one (unless
// ~keepEdits=false: the browser has already put the current program back).
let select = (t, i, ~keepEdits=true) => {
  let i = mod(mod(i, bankPrograms) + bankPrograms, bankPrograms)
  if keepEdits {
    t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  }
  t.current = i
  apply(t, t.programs->Array.getUnsafe(i))
  t.pc->PatchConnection.sendStoredStateValue("program", i)
  storeBank(t)
  changed(t)
}

let rename = (t, i, name) => {
  if i == t.current {
    t.programs->Array.setUnsafe(i, captureCurrent(t))
  }
  t.programs[i]->Option.forEach(p => t.programs->Array.setUnsafe(i, p->Preset.withName(name)))
  storeBank(t)
  changed(t)
}

let setMeta = (t, meta: Preset.meta) => {
  t.programs->Array.setUnsafe(t.current, {...captureCurrent(t), meta}->Preset.withName(meta.name))
  storeBank(t)
  changed(t)
}

let setMacroName = (t, i, name) => {
  let meta = (t.programs->Array.getUnsafe(t.current)).meta
  setMeta(
    t,
    {
      ...meta,
      macroNames: meta.macroNames->Array.mapWithIndex((n, k) => k == i ? String.trim(name) : n),
    },
  )
}

let setTuning = (t, tuning) => {
  t.tuning = tuning
  sendTuning(t)
  t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  storeBank(t)
  changed(t)
}

let tuningName = t =>
  t.tuning->Option.flatMap(src =>
    switch Scala.table(src) {
    | Ok({name}) => Some(name)
    | Error(_) => None
    }
  )

// A .scl replaces the scale and keeps the keyboard mapping; a .kbm the other way round.
let loadTuningFile = (t, text, filename) => {
  let isMapping = filename->String.toLowerCase->String.endsWith(".kbm")
  let current = t.tuning->Option.getOr({Scala.scl: "", kbm: ""})
  let next: Scala.source = isMapping ? {...current, kbm: text} : {...current, scl: text}
  switch Scala.table(next) {
  | Ok({name}) =>
    setTuning(t, Some(next))
    t.message(isMapping ? `Keyboard mapping ${filename} loaded` : `Tuned to ${name}`)
  | Error(e) => t.message(`${filename}: ${e}`)
  }
}

// Replaces the current program with a preset (a preset file, or one picked in the browser).
let loadIntoCurrent = (t, p) => {
  t.programs->Array.setUnsafe(t.current, p)
  apply(t, p)
  storeBank(t)
  changed(t)
}

// The browser plays presets without storing them: it keeps the current program as it was
// (captureCurrent) and plays others with preview. Then either restore puts the kept one back,
// or the picked preset is loaded (loadIntoCurrent), or its program is selected (keep puts the
// kept program back into its slot, then select with ~keepEdits=false).
let preview = (t, p) => apply(t, p)
let restore = (t, kept: Preset.t) => apply(t, kept)
let keep = (t, kept: Preset.t) => t.programs->Array.setUnsafe(t.current, kept)

let initCurrent = t => {
  let p = Preset.make("Init")
  t.programs->Array.setUnsafe(t.current, p)
  apply(t, p)
  storeBank(t)
  changed(t)
}

let panic = t => t.pc->PatchConnection.sendEventOrValue("panic", 1)

let isTuningFile = filename =>
  [".scl", ".kbm"]->Array.some(ext => filename->String.toLowerCase->String.endsWith(ext))

let loadFile = (t, bytes, filename) =>
  if isTuningFile(filename) {
    loadTuningFile(t, Preset.utf8Decode(bytes), filename)
  } else {
    switch Preset.parseFile(bytes) {
    | Error(e) => t.message(`${filename} isn't a Porridge or Oatmeal program or bank (${e})`)
    | Ok({presets: []}) => t.message(`${filename} has no programs in it`)
    | Ok({kind: Single, presets: [p]}) =>
      loadIntoCurrent(t, p)
      t.message(`Loaded "${Preset.name(p)}" into program ${Int.toString(t.current + 1)}`)
    | Ok({presets: programs}) =>
      t.programs = Array.fromInitializer(~length=bankPrograms, i =>
        switch programs[i] {
        | Some(p) => p
        | None => Preset.make(`Init ${Int.toString(i)}`)
        }
      )
      t.current = 0
      apply(t, t.programs->Array.getUnsafe(0))
      t.pc->PatchConnection.sendStoredStateValue("program", 0)
      t.message(`Loaded bank ${filename} (${Int.toString(Array.length(programs))} programs)`)
      storeBank(t)
      changed(t)
    }
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
  let p = captureCurrent(t)
  t.programs->Array.setUnsafe(t.current, p)
  download(Preset.writePreset(p), safeName(Preset.name(p)) ++ ".porridge")
}

let downloadBank = t => {
  t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  download(Preset.writeBank(t.programs), "porridge bank.porridge")
}

let warnOatmeal = (t, presets) => {
  let lost =
    presets
    ->Array.flatMap(Preset.porridgeOnly)
    ->Array.reduce([], (acc, x) => acc->Array.includes(x) ? acc : [...acc, x])
  if Array.length(lost) > 0 {
    t.message("Oatmeal can't store " ++ lost->Array.join(", ") ++ "; they're left out")
  }
}

let exportOatmealProgram = t => {
  let p = captureCurrent(t)
  warnOatmeal(t, [p])
  t.programs->Array.setUnsafe(t.current, p)
  download(writeProgramChunk(Preset.toOatmeal(p)), safeName(Preset.name(p)) ++ ".omp")
}

let exportOatmealBank = t => {
  t.programs->Array.setUnsafe(t.current, captureCurrent(t))
  warnOatmeal(t, t.programs)
  download(writeBankChunk(t.programs->Array.map(Preset.toOatmeal)), "porridge bank.omb")
}

let learn = (t, ccId) => {
  t.learning = Some(ccId)
  t.message("Move a controller to assign it to " ++ String.replace(ccId, "CC", "slot "))
}
