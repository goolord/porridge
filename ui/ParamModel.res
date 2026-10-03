// Parameter model: the single source of truth for the view. Values are internal
// (preset-struct) values; the patch's endpoints use the same units.
//
// It also keeps the undo history. Every edit through set is recorded; what one gesture does
// (a drag between beginGesture and endGesture, or everything a click sets at once) is one step.
// The program store adds steps of its own (record: loading a program, init, a rename...).
// Values that arrive from the patch (the host's automation, a loaded state) and whole programs
// pushed with setAll are not edits, and are not recorded; nor are the wheels' moves, which are
// playing, not editing (PorridgeParams.isPerformance), and which setAll leaves where they are.

// One thing a step changed: a parameter, or something else that knows how to go back and forth.
type change = Param({id: string, before: float, mutable after: float}) | Action({undo: unit => unit, redo: unit => unit})

type step = {mutable label: string, changes: array<change>, mutable at: float}

type history = {
  mutable undo: array<step>,
  mutable redo: array<step>,
  // the step being made: it ends once no gesture is open, after the event that made it
  mutable pending: option<step>,
  mutable sealing: bool,
  gestures: Set.t<string>,
  // while undoing or redoing, or pushing a program, changes aren't recorded
  mutable quiet: int,
  // undo goes no further back than this many steps while a preview plays (hold)
  mutable floor: option<int>,
}

// how many steps undo keeps
let historyLength = 100
// a scroll or arrow keys on one control within this long are one step
let mergeMs = 800.

type t = {
  pc: PatchConnection.t,
  defs: Map.t<string, ParamDefs.t>,
  values: Bank.values,
  listeners: Map.t<string, array<unit => unit>>,
  anyListeners: array<string => unit>,
  onParam: PatchConnection.parameterEvent => unit,
  history: history,
  // the stored parameters (StoredParams): the distortions whose points changed since they were
  // last sent, and the stored-state values this view sent whose echoes haven't come back yet
  storedDirty: Set.t<int>,
  mutable storedFlushing: bool,
  storedSent: array<string>,
  // the stored-state value as the patch has it, as far as the view knows
  mutable storedValue: option<string>,
  // the slots' knobs' endpoint values as the patch has them, as far as the view knows (what it
  // sent, and what came from the patch): SlotParams
  knobRaw: Map.t<string, float>,
}

let notifyListeners = (listeners, anyListeners, id) => {
  listeners->Map.get(id)->Option.forEach(fns => fns->Array.forEach(fn => fn()))
  anyListeners->Array.forEach(fn => fn(id))
}

let make = (pc, defs: array<ParamDefs.t>) => {
  let defsById = defs->Array.map(d => (d.id, d))->Map.fromArray
  let values = defs->Array.map(d => (d.id, d.init))->Map.fromArray
  let listeners = Map.make()
  let anyListeners = []
  let knobRaw = Map.make()
  let get = id => values->Map.get(id)->Option.getOr(0.)
  let setFromPatch = (id, x) =>
    switch values->Map.get(id) {
    | Some(old) if old == x => ()
    | _ =>
      values->Map.set(id, x)
      notifyListeners(listeners, anyListeners, id)
    }
  // a slot's parameters from its knobs as the patch has them (its kind came from the patch)
  let slotFromKnobs = g =>
    SlotParams.fromKnobs(~def=id => defsById->Map.get(id), get, id => knobRaw->Map.get(id), g)->Array.forEach(((id, x)) =>
      setFromPatch(id, x)
    )

  let onParam = ({endpointID, value}: PatchConnection.parameterEvent) =>
    switch PorridgeParams.parseKnobId(endpointID) {
    // a knob: the parameter its slot's kind has there, unless it's what the view sent
    | Some(_) =>
      if knobRaw->Map.get(endpointID) != Some(value) {
        knobRaw->Map.set(endpointID, value)
        SlotParams.paramOfKnob(get, endpointID)->Option.forEach(id =>
          defsById->Map.get(id)->Option.forEach(d => setFromPatch(id, SlotParams.fromKnob(d, value)))
        )
      }
    | None =>
      defsById
      ->Map.get(endpointID)
      ->Option.forEach(d => {
        let x = d.isInt ? Math.round(value) : value
        switch values->Map.get(d.id) {
        | Some(old) if old == x => ()
        | _ =>
          values->Map.set(d.id, x)
          // (a slot that holds something else now: its knobs mean that kind's parameters)
          SlotParams.slotOfKindId(d.id)->Option.forEach(slotFromKnobs)
          notifyListeners(listeners, anyListeners, d.id)
        }
      })
    }

  pc->PatchConnection.addAllParameterListener(onParam)
  {
    pc,
    defs: defsById,
    values,
    listeners,
    anyListeners,
    onParam,
    history: {
      undo: [],
      redo: [],
      pending: None,
      sealing: false,
      gestures: Set.make(),
      quiet: 0,
      floor: None,
    },
    storedDirty: Set.make(),
    storedFlushing: false,
    storedSent: [],
    storedValue: None,
    knobRaw,
  }
}

// The patch's values, from a full stored state: it lists the parameters that differ from
// their defaults, which the model starts with.
let loadParameters = (t, parameters: array<PatchConnection.namedValue>) =>
  parameters->Array.forEach(({name, value}) => t.onParam({endpointID: name, value}))

let dispose = t => t.pc->PatchConnection.removeAllParameterListener(t.onParam)

let def = (t, id) =>
  switch t.defs->Map.get(id) {
  | Some(d) => d
  | None => JsError.panic("unknown parameter " ++ id)
  }

let get = (t, id) => t.values->Map.get(id)->Option.getOr(0.)

//==============================================================================
// the slots' knobs (SlotParams)

let knobDef = (t, id) => t.defs->Map.get(id)

// Sends a knob's value, unless the patch has it already.
let sendKnob = (t, knob, v, ~now) =>
  if t.knobRaw->Map.get(knob) != Some(v) {
    t.knobRaw->Map.set(knob, v)
    if now {
      t.pc->PatchConnection.sendEventOrValueNow(knob, v)
    } else {
      t.pc->PatchConnection.sendEventOrValue(knob, v)
    }
  }

// Sends slot g's knobs for the kind it holds now.
let sendSlotKnobs = (t, g, ~now) =>
  SlotParams.knobValues(~def=knobDef(t, _), get(t, _), g)->Array.forEach(((knob, v)) => sendKnob(t, knob, v, ~now))

// The endpoint a parameter's changes and gestures go to: its own, or for a slot's parameter the
// knob it is on (None: its slot holds another kind, or it's stored state).
let endpointOf = (t, id) =>
  if StoredParams.isStored(id) {
    None
  } else if PorridgeParams.isSlotParam(id) {
    SlotParams.knobOf(get(t, _), id)
  } else {
    Some(id)
  }

// Whether there is such a parameter.
let has = (t, id) => t.defs->Map.has(id)

// The parameter's value as the status line and the readouts show it.
let longText = (t, id) => def(t, id).longText(get(t, id))
let shortText = (t, id) => def(t, id).shortText(get(t, id))
// Several parameters' long texts, for the status line.
let statusText = (t, ids) => ids->Array.map(longText(t, _))->Array.join("    ")

let listen = (t, id, fn) =>
  switch t.listeners->Map.get(id) {
  | Some(fns) => fns->Array.push(fn)
  | None => t.listeners->Map.set(id, [fn])
  }

// Calls fn whenever one of these parameters changes.
let listenEach = (t, ids, fn) => ids->Array.forEach(id => listen(t, id, fn))

let listenAny = (t, fn) => t.anyListeners->Array.push(fn)

let notify = (t, id) => notifyListeners(t.listeners, t.anyListeners, id)

//==============================================================================
// undo history

// A step's name, for the menu ("Undo cutoff"): what the caller called it, or the parameter it
// changed (the first of several).
let stepLabel = (t, changes) =>
  switch changes->Array.find(c =>
    switch c {
    | Param(_) => true
    | Action(_) => false
    }
  ) {
  | Some(Param({id})) =>
    // (in lower case, as the controls' labels, but for names like "MPE" or "LFO 1 rate")
    let name = t.defs->Map.get(id)->Option.mapOr(id, d => d.name)
    let second = name->String.slice(~start=1, ~end=2)
    let name =
      second == second->String.toLowerCase
        ? name->String.slice(~start=0, ~end=1)->String.toLowerCase ++ name->String.slice(~start=1)
        : name
    let more = changes->Array.length - 1
    more > 0 ? `${name} and ${Int.toString(more)} more` : name
  | _ => "edit"
  }

// Ends the step being made: it goes on the undo stack, unless it changed nothing, and a
// scroll or a key press on the same control as the step before joins that one.
let seal = t => {
  let h = t.history
  h.pending->Option.forEach(step => {
    h.pending = None
    let changes = step.changes->Array.filter(c =>
      switch c {
      | Param({before, after}) => before != after
      | Action(_) => true
      }
    )
    let single = changes =>
      switch changes {
      | [Param({id})] => Some(id)
      | _ => None
      }
    switch (single(changes), h.undo->Array.at(-1)) {
    | (_, _) if Array.length(changes) == 0 => ()
    | (Some(id), Some(last))
      if single(last.changes) == Some(id) && step.at - last.at < mergeMs && h.floor != Some(Array.length(h.undo)) =>
      switch (last.changes, changes) {
      | ([Param(previous)], [Param({after})]) =>
        previous.after = after
        last.at = step.at
      | _ => ()
      }
    | _ =>
      h.undo->Array.push({
        label: step.label == "" ? stepLabel(t, changes) : step.label,
        changes,
        at: step.at,
      })
      let over = Array.length(h.undo) - historyLength
      if over > 0 {
        h.undo->Array.splice(~start=0, ~remove=over, ~insert=[])
        h.floor = h.floor->Option.map(f => Math.Int.max(0, f - over))
      }
    }
  })
}

// Seals the step after the event that is making it, unless a gesture is still open.
let sealSoon = t => {
  let h = t.history
  if !h.sealing {
    h.sealing = true
    Promise.resolve()
    ->Promise.thenResolve(() => {
      h.sealing = false
      if h.gestures->Set.size == 0 {
        seal(t)
      }
    })
    ->ignore
  }
}

let pendingStep = t =>
  switch t.history.pending {
  | Some(step) => step
  | None =>
    let step = {label: "", changes: [], at: Date.now()}
    t.history.pending = Some(step)
    t.history.redo = []
    step
  }

let recordParam = (t, id, before, after) =>
  if t.history.quiet == 0 {
    let step = pendingStep(t)
    switch step.changes->Array.find(c =>
      switch c {
      | Param(p) => p.id == id
      | Action(_) => false
      }
    ) {
    | Some(Param(p)) => p.after = after
    | _ => step.changes->Array.push(Param({id, before, after}))
    }
    step.at = Date.now()
    sealSoon(t)
  }

// Adds something other than a parameter change to the step being made (or a new one), under
// this name: undo calls undo, redo calls redo.
let record = (t, ~label, ~undo, ~redo) =>
  if t.history.quiet == 0 {
    let step = pendingStep(t)
    step.changes->Array.push(Action({undo, redo}))
    step.label = label
    step.at = Date.now()
    sealSoon(t)
  }

// Names the step being made, for the menu.
let nameStep = (t, label) => t.history.pending->Option.forEach(step => step.label = label)

// Runs f without recording what it changes.
let quietly = (t, f) => {
  t.history.quiet = t.history.quiet + 1
  try f() catch {
  | e =>
    t.history.quiet = t.history.quiet - 1
    throw(e)
  }
  t.history.quiet = t.history.quiet - 1
}

// Forgets every step (another state arrived from the host).
let clearHistory = t => {
  let h = t.history
  h.pending = None
  h.undo = []
  h.redo = []
  h.floor = None
}

// While something is only being tried (a program from the browser, a random patch), undo stops
// at what came before it: hold marks that point, and drop forgets the steps made since then.
let hold = t => {
  seal(t)
  t.history.redo = []
  t.history.floor = Some(Array.length(t.history.undo))
}

let drop = t => {
  seal(t)
  let h = t.history
  h.floor->Option.forEach(floor => h.undo->Array.splice(~start=floor, ~remove=Array.length(h.undo) - floor, ~insert=[]))
  h.floor = None
  h.redo = []
}

// What undo and redo would take back or do again, if anything.
let undoLabel = t => {
  seal(t)
  Array.length(t.history.undo) > t.history.floor->Option.getOr(0)
    ? t.history.undo->Array.at(-1)->Option.map(s => s.label)
    : None
}
let redoLabel = t => t.history.redo->Array.at(-1)->Option.map(s => s.label)

//==============================================================================
// the stored parameters: not endpoints, but a shaperIn event per distortion and the stored
// state (StoredParams)

// how many of the view's own stored-state values to wait for the echoes of
let storedEchoes = 8

// Sends the distortions whose points changed, and stores the values.
let flushStored = t => {
  t.storedFlushing = false
  t.storedDirty->Set.forEach(k => StoredParams.send(t.pc, k, get(t, _)))
  t.storedDirty->Set.clear
  let s = StoredParams.encode(get(t, _))
  // (the patch echoes a value only when it changes it)
  if t.storedValue != Some(s) {
    t.storedValue = Some(s)
    t.storedSent->Array.push(s)
    if Array.length(t.storedSent) > storedEchoes {
      t.storedSent->Array.shift->ignore
    }
    StoredState.send(t.pc, StoredState.Params, s)
  }
}

// (once the event that changed them is over: a click may set several points)
let storedChanged = (t, id) =>
  StoredParams.groupOf(id)->Option.forEach(k => {
    t.storedDirty->Set.add(k)
    if !t.storedFlushing {
      t.storedFlushing = true
      Promise.resolve()->Promise.thenResolve(() => flushStored(t))->ignore
    }
  })

// The stored parameters from the patch's stored state (a host's state, or another view's
// edit): set, not sent back, not recorded. The patch echoes what this view stored, in order:
// those are skipped.
let loadStored = (t, value: JSON.t) =>
  switch value {
  | String(s) if t.storedSent[0] == Some(s) => t.storedSent->Array.shift->ignore
  | _ =>
    t.storedSent->Array.splice(~start=0, ~remove=Array.length(t.storedSent), ~insert=[])
    t.storedValue = switch value {
    | String(s) => Some(s)
    | _ => None
    }
    let changed = []
    StoredParams.decode(value)->Map.forEachWithKey((x, id) =>
      t.defs
      ->Map.get(id)
      ->Option.forEach(d => {
        let x = d.load(x)
        if get(t, id) != x {
          t.values->Map.set(id, x)
          changed->Array.push(id)
        }
      })
    )
    t->quietly(() => changed->Array.forEach(id => notify(t, id)))
  }

//==============================================================================
// setting values

let set = (t, id, x) =>
  t.defs
  ->Map.get(id)
  ->Option.forEach(d => {
    let x = d.clamp(x)
    let before = get(t, id)
    if before != x {
      if !PorridgeParams.isPerformance(id) {
        recordParam(t, id, before, x)
      }
      t.values->Map.set(id, x)
      if StoredParams.isStored(id) {
        storedChanged(t, id)
      } else if PorridgeParams.isSlotParam(id) {
        SlotParams.knobOf(get(t, _), id)->Option.forEach(knob => sendKnob(t, knob, SlotParams.toKnob(d, x), ~now=false))
      } else {
        t.pc->PatchConnection.sendEventOrValue(id, x)
        SlotParams.slotOfKindId(id)->Option.forEach(g => sendSlotKnobs(t, g, ~now=false))
      }
      notify(t, id)
    }
  })

let beginGesture = (t, id) => {
  if t.history.quiet == 0 && !PorridgeParams.isPerformance(id) {
    t.history.gestures->Set.add(id)
  }
  endpointOf(t, id)->Option.forEach(e => t.pc->PatchConnection.sendParameterGestureStart(e))
}

let endGesture = (t, id) => {
  endpointOf(t, id)->Option.forEach(e => t.pc->PatchConnection.sendParameterGestureEnd(e))
  if t.history.gestures->Set.delete(id) && t.history.gestures->Set.size == 0 {
    sealSoon(t)
  }
}

let gestureSet = (t, id, x) => {
  beginGesture(t, id)
  set(t, id, x)
  endGesture(t, id)
}

// Takes a step back or does it again: its parameters as gestures the host hears, and its actions
// (in the reverse order going back).
let replay = (t, step, ~back) => {
  let changes = back ? step.changes->Array.toReversed : step.changes
  t->quietly(() =>
    changes->Array.forEach(c =>
      switch c {
      | Param({id, before, after}) => gestureSet(t, id, back ? before : after)
      | Action({undo, redo}) => back ? undo() : redo()
      }
    )
  )
}

// Takes back the last step, and returns its name (None if there was none to take back).
let undo = t => {
  seal(t)
  let h = t.history
  if Array.length(h.undo) > h.floor->Option.getOr(0) {
    h.undo->Array.pop->Option.map(step => {
      replay(t, step, ~back=true)
      h.redo->Array.push(step)
      step.label
    })
  } else {
    None
  }
}

let redo = t => {
  seal(t)
  let h = t.history
  h.redo
  ->Array.pop
  ->Option.map(step => {
    replay(t, step, ~back=false)
    // (a step done again doesn't join the one before it)
    step.at = 0.
    h.undo->Array.push(step)
    step.label
  })
}

// Push a whole set of values (e.g. a loaded program, whose values are kept as it holds them:
// ParamDefs' load). Every endpoint is sent, even if unchanged, so the patch is guaranteed to
// match; listeners hear of the changed ones, once every value is in place. Not an edit: the
// caller records the program it loaded, if that is one.
let setAll = (t, values: Bank.values) => {
  let changed = []
  values->Map.forEachWithKey((x, id) =>
    t.defs
    ->Map.get(id)
    ->Option.filter(_ => !PorridgeParams.isPerformance(id))
    ->Option.forEach(d => {
      let x = d.load(x)
      if get(t, id) != x {
        changed->Array.push(id)
      }
      t.values->Map.set(id, x)
      switch StoredParams.groupOf(id) {
      | Some(k) => t.storedDirty->Set.add(k)
      | None if PorridgeParams.isSlotParam(id) => ()
      | None => t.pc->PatchConnection.sendEventOrValueNow(id, x)
      }
    })
  )
  // (the slots' knobs, for the kinds they hold now: every one, as every endpoint is sent)
  t.knobRaw->Map.clear
  Array.fromInitializer(~length=PorridgeParams.slotCount, g => g)->Array.forEach(g => sendSlotKnobs(t, g, ~now=true))
  // (the stored ones now too, each distortion's in one event)
  if t.storedDirty->Set.size > 0 {
    flushStored(t)
  }
  t->quietly(() => changed->Array.forEach(id => notify(t, id)))
}
