// User settings, as opposed to a program's: for now the size of the interface.
//
// The CLAP plugin keeps them in a settings file that every instance shares, and answers
// stored-state requests whose key starts with "porridge:settings?" with a "porridge:settings"
// value {settings, zoom}, zoom being this window's size relative to the design size (see
// tools/clap-patch.mjs). Elsewhere (cmaj play, the UI preview) nothing answers: the host
// owns the window size there.

type t = {
  pc: PatchConnection.t,
  // the saved settings, once the plugin has answered
  mutable saved: option<Dict.t<JSON.t>>,
  mutable zoom: float,
  mutable listeners: array<unit => unit>,
  mutable stateListener: option<PatchConnection.storedStateEvent => unit>,
}

let zoomSteps = [0.75, 1., 1.25, 1.5, 1.75, 2., 2.5, 3.]

let requestPrefix = "porridge:settings?"
let replyKey = "porridge:settings"

let request = (t, what) => t.pc->PatchConnection.requestStoredStateValue(requestPrefix ++ what)

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  switch (key, value) {
  | (key, Object(reply)) if key == replyKey =>
    t.saved = switch reply->Dict.get("settings") {
    | Some(Object(saved)) => Some(saved)
    | _ => Some(Dict.make())
    }
    switch reply->Dict.get("zoom") {
    | Some(Number(zoom)) if Float.isFinite(zoom) => t.zoom = zoom
    | _ => ()
    }
    t.listeners->Array.forEach(fn => fn())
  | _ => ()
  }

let make = pc => {
  let t = {pc, saved: None, zoom: 1., listeners: [], stateListener: None}
  let listener = ev => onState(t, ev)
  t.stateListener = Some(listener)
  pc->PatchConnection.addStoredStateValueListener(listener)
  request(t, "get")
  t
}

let dispose = t =>
  t.stateListener->Option.forEach(listener =>
    t.pc->PatchConnection.removeStoredStateValueListener(listener)
  )

// whether the plugin keeps the settings and sizes the window
let available = t => t.saved != None

// Calls fn whenever the plugin answers; returns a function that stops it.
let listen = (t, fn) => {
  let wrapped = () => fn()
  t.listeners->Array.push(wrapped)
  () => t.listeners = t.listeners->Array.filter(f => f !== wrapped)
}

let refresh = t => request(t, "get")

// the size new windows open at
let savedZoom = t =>
  switch t.saved->Option.flatMap(Dict.get(_, "zoom")) {
  | Some(Number(zoom)) if Float.isFinite(zoom) => zoom
  | _ => 1.
  }

// asks the host to resize this window
let setZoom = (t, zoom) => request(t, "zoom=" ++ Float.toString(zoom))

let save = (t, key, value) => {
  let saved = t.saved->Option.mapOr(Dict.make(), Dict.copy)
  saved->Dict.set(key, value)
  t.saved = Some(saved)
  request(t, "save=" ++ JSON.stringify(Object(saved)))
}
