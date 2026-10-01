// The 64-program bank, as the view sees it. Programs are Porridge presets (Preset.res); the
// bank and the current program's shapes live in the patch's stored state so the host saves
// them with the session (parameters are saved by the host on their own).

open OatmealFormat

type t = {
  pc: PatchConnection.t,
  model: ParamModel.t,
  message: string => unit,
  shapeListeners: array<unit => unit>,
  // the current program or the bank changed
  changeListeners: array<unit => unit>,
  mutable current: int,
  mutable programs: array<Preset.t>,
  // what the bank calls itself (saved with it, and the name of its file), or ""
  mutable bankName: string,
  mutable shapes: tables,
  // whether the patch is known to hold `shapes` (until then a program sends all its tables)
  mutable shapesKnown: bool,
  mutable tuning: option<Scala.source>,
  mutable impulses: array<option<Impulse.t>>,
  impulseListeners: array<unit => unit>,
  // what the view last stored under each key, to tell the host's echo from a new value
  stored: Map.t<StoredState.key, string>,
  pendingSend: Set.t<table>,
  mutable learning: option<string>,
  mutable listeners: option<(PatchConnection.storedStateEvent => unit, JSON.t => unit)>,
}

let make = (pc, model, ~onMessage) => {
  let programs = Preset.fillBank([])
  {
    pc,
    model,
    message: onMessage,
    shapeListeners: [],
    changeListeners: [],
    current: 0,
    programs,
    bankName: "",
    shapes: Preset.copyTables((programs->Array.getUnsafe(0)).tables),
    shapesKnown: false,
    tuning: None,
    impulses: Impulse.none(),
    impulseListeners: [],
    stored: Map.make(),
    pendingSend: Set.make(),
    learning: None,
    listeners: None,
  }
}

let changed = t => t.changeListeners->Array.forEach(fn => fn())

let onChanged = (t, fn) => t.changeListeners->Array.push(fn)

let fireShapes = t => t.shapeListeners->Array.forEach(fn => fn())

let store = (t, key, value) => {
  t.stored->Map.set(key, value)
  StoredState.send(t.pc, key, value)
}

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  switch (StoredState.keyOf(key), value) {
  | (Some(key), String(s)) if t.stored->Map.get(key) == Some(s) => ()
  | (Some(StoredState.Bank), String(bank)) if StoredState.isBank(bank) =>
    Preset.decodeNamedBank(bank)->Option.forEach(((name, presets)) => {
      t.programs = Preset.fillBank(presets)
      t.bankName = name
      changed(t)
    })
  | (Some(StoredState.Program), Number(i)) if Float.isFinite(i) =>
    let i = Math.Int.max(0, Math.Int.min(bankPrograms - 1, Float.toInt(i)))
    if i != t.current {
      t.current = i
      changed(t)
    }
  | (Some(StoredState.Tuning), String(s)) =>
    t.tuning = Bank.decodeTuning(s)
    changed(t)
  | (Some(StoredState.Impulses), String(s)) =>
    t.impulses = Impulse.decode(s)
    t.impulseListeners->Array.forEach(fn => fn())
  | (Some(StoredState.Shapes), String(shapes)) =>
    Bank.decodeShapes(shapes)->Option.forEach(shapes => {
      t.shapes = shapes
      t.shapesKnown = true
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
  StoredState.all->Array.forEach(key => {
    let key = StoredState.name(key)
    values->Dict.get(key)->Option.forEach(value => onState(t, {key, value}))
  })

let dispose = t =>
  t.listeners->Option.forEach(((stateListener, outListener)) => {
    t.pc->PatchConnection.removeStoredStateValueListener(stateListener)
    t.pc->PatchConnection.removeEndpointListener("ccOut", outListener)
  })

// program i's number as the view shows it: from 01
let number = i => Int.toString(i + 1)->String.padStart(2, "0")

let name = (t, i) => t.programs[i]->Option.mapOr("", Preset.name)
let currentProgram = t => t.programs->Array.getUnsafe(t.current)
let meta = t => currentProgram(t).meta

let shape = (t, table) => t.shapes->getTable(table)
let onShapes = (t, fn) => t.shapeListeners->Array.push(fn)

let storeShapes = t => store(t, StoredState.Shapes, Bank.encodeShapes(t.shapes))

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
    storeShapes(t)
    fireShapes(t)
  }
}

// the current program with the live parameter values and shapes
let captureCurrent = (t): Preset.t => {
  ...currentProgram(t),
  values: Map.fromArray(t.model.values->Map.entries->Array.fromIterator),
  tables: Preset.copyTables(t.shapes),
  tuning: t.tuning,
  impulses: t.impulses,
}

// keeps the live edits in the current program
let keepCurrent = t => t.programs->Array.setUnsafe(t.current, captureCurrent(t))

let storeBank = t => store(t, StoredState.Bank, Preset.encodeBank(t.programs, ~name=t.bankName))

let bankChanged = t => {
  storeBank(t)
  changed(t)
}

let sendTuning = t => {
  Bank.sendTuning(t.pc, t.tuning)
  store(t, StoredState.Tuning, Bank.encodeTuning(t.tuning))
}

let onImpulses = (t, fn) => t.impulseListeners->Array.push(fn)

// Sends the convolvers' impulses to the patch, and stores them.
let sendImpulses = t => {
  t.impulses->Array.forEachWithIndex((imp, which) => Impulse.send(t.pc, which, imp))
  store(t, StoredState.Impulses, Impulse.encode(t.impulses))
  t.impulseListeners->Array.forEach(fn => fn())
}

let apply = (t, preset: Preset.t) => {
  t.tuning = preset.tuning
  sendTuning(t)
  // (an impulse is sent again only when it changes: it takes a moment to arrive)
  let changedImpulses = preset.impulses->Array.someWithIndex((imp, i) => t.impulses[i]->Option.flatMap(x => x) !== imp)
  t.impulses = preset.impulses
  if changedImpulses {
    sendImpulses(t)
  }
  t.model->ParamModel.setAll(preset.values)
  let before = t.shapes
  t.shapes = Preset.copyTables(preset.tables)
  // only the tables that change, once the patch's are known
  allTables->Array.forEach(table => {
    let data = shape(t, table)
    if !t.shapesKnown || !Preset.sameTable(before->getTable(table), data) {
      Bank.sendShape(t.pc, table, data)
    }
  })
  t.shapesKnown = true
  storeShapes(t)
  fireShapes(t)
}

// Switches to program i, first keeping the live edits in the current one (unless
// ~keepEdits=false: the browser has already put the current program back).
let select = (t, i, ~keepEdits=true) => {
  let i = mod(mod(i, bankPrograms) + bankPrograms, bankPrograms)
  if keepEdits {
    keepCurrent(t)
  }
  t.current = i
  apply(t, currentProgram(t))
  StoredState.send(t.pc, StoredState.Program, i)
  bankChanged(t)
}

let rename = (t, i, name) => {
  if i == t.current {
    keepCurrent(t)
  }
  t.programs[i]->Option.forEach(p => t.programs->Array.setUnsafe(i, p->Preset.withName(name)))
  bankChanged(t)
}

let setMeta = (t, meta: Preset.meta) => {
  t.programs->Array.setUnsafe(t.current, {...captureCurrent(t), meta}->Preset.withName(meta.name))
  bankChanged(t)
}

let setMacroName = (t, i, name) => {
  let meta = meta(t)
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
  keepCurrent(t)
  bankChanged(t)
}

// Loads convolver `which`'s impulse from a file (and selects it).
let setImpulse = (t, which, imp) => {
  t.impulses = t.impulses->Array.mapWithIndex((x, i) => i == which ? imp : x)
  sendImpulses(t)
  keepCurrent(t)
  bankChanged(t)
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
  bankChanged(t)
}

// The browser plays presets without storing them: it keeps the current program as it was
// (captureCurrent) and plays others with preview. Then either restore puts the kept one back,
// or the picked preset's bank is loaded and its program selected (loadBank; loadIntoCurrent
// for a lone preset), or its program is selected (keep puts the kept program back into its
// slot, then select with ~keepEdits=false).
let preview = (t, p) => apply(t, p)
let restore = (t, kept: Preset.t) => apply(t, kept)
let keep = (t, kept: Preset.t) => t.programs->Array.setUnsafe(t.current, kept)

// Init keeps the program's author, for someone writing a bank.
let initCurrent = t => {
  let init = Preset.make("Init")
  loadIntoCurrent(t, {...init, meta: {...init.meta, author: meta(t).author}})
}

// A bank of Init programs to start writing one: its name, and the author of every program.
let newBank = (t, ~name, ~author) => {
  t.programs = Preset.fillBank([])->Array.map(p => {...p, meta: {...Preset.emptyMeta("Init"), author}})
  t.bankName = name
  select(t, 0, ~keepEdits=false)
  t.message(`New bank${name == "" ? "" : ` "${name}"`}: ${Int.toString(bankPrograms)} Init programs`)
}

// Replaces the bank with programs and goes to program `index` of them (with more than a bank
// holds, the bank-sized run of them it falls in).
let loadBank = (t, programs, ~name, ~index=0) => {
  let start = index / bankPrograms * bankPrograms
  t.programs = Preset.fillBank(programs->Array.slice(~start, ~end=start + bankPrograms))
  t.bankName = name
  select(t, index - start, ~keepEdits=false)
}

let panic = t => t.pc->PatchConnection.sendEventOrValue("panic", 1)

let isTuningFile = filename =>
  Scala.extensions->Array.some(ext => filename->String.toLowerCase->String.endsWith(ext))

let loadFile = (t, bytes, filename) =>
  if isTuningFile(filename) {
    loadTuningFile(t, Preset.utf8Decode(bytes), filename)
  } else {
    switch Preset.parseForLoading(bytes, filename) {
    | Error(e) => t.message(e)
    | Ok({kind: Single, presets: [p]}) =>
      loadIntoCurrent(t, p)
      t.message(`Loaded "${Preset.name(p)}" into program ${Int.toString(t.current + 1)}`)
    | Ok({presets: programs, name}) =>
      loadBank(t, programs, ~name=name != "" ? name : Web.baseName(filename))
      let count = Array.length(programs)
      t.message(
        count > bankPrograms
          ? `Loaded the first ${Int.toString(bankPrograms)} of the ${Int.toString(count)} programs in ${filename}`
          : `Loaded bank ${filename} (${Int.toString(count)} programs)`,
      )
    }
  }

// A file the user picked or dropped.
let loadUserFile = async (t, file) =>
  switch await Web.readBytes(file) {
  | Ok(bytes) => loadFile(t, bytes, file->Web.fileName)
  | Error(e) => t.message(e)
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
  keepCurrent(t)
  let p = currentProgram(t)
  download(Preset.writePreset(p), safeName(Preset.name(p)) ++ ".porridge")
}

let bankFileName = t => t.bankName == "" ? "porridge bank" : safeName(t.bankName)

let downloadBank = t => {
  keepCurrent(t)
  download(Preset.writeBank(t.programs, ~name=t.bankName), bankFileName(t) ++ ".porridge")
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
  keepCurrent(t)
  let p = currentProgram(t)
  warnOatmeal(t, [p])
  download(writeProgramChunk(Preset.toOatmeal(p)), safeName(Preset.name(p)) ++ ".omp")
}

let exportOatmealBank = t => {
  keepCurrent(t)
  warnOatmeal(t, t.programs)
  download(writeBankChunk(t.programs->Array.map(Preset.toOatmeal)), bankFileName(t) ++ ".omb")
}

let learn = (t, ccId) => {
  t.learning = Some(ccId)
  t.message("Move a controller to assign it to " ++ String.replace(ccId, "CC", "slot "))
}

// An audio file as convolver `which`'s impulse, which it then plays (Cv_Impulse "file").
let loadImpulseFile = async (t, which, file) => {
  let name = file->Web.fileName
  switch await AudioFile.readFile(file) {
  | Error(e) => t.message(e)
  | Ok(audio) =>
    switch Impulse.fromAudio(name, audio) {
    | None => t.message(`${name} is silent`)
    | Some(imp) =>
      setImpulse(t, which, Some(imp))
      let param = which == 0 ? "Cv_Impulse" : PorridgeParams.copyId("Cv_Impulse", which + 1)
      t.model->ParamModel.gestureSet(param, Int.toFloat(PorridgeParams.impulseFile))
      t.message(`Loaded ${name} (${Float.toFixed(Impulse.seconds(imp), ~digits=2)} s) into the convolver`)
    }
  }
}
