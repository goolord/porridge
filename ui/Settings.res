// User settings, as opposed to a program's: for now the size of the interface.
//
// The CLAP plugin keeps them in a settings file that every instance shares, and answers
// stored-state requests whose key starts with "porridge:settings?" with a "porridge:settings"
// value {settings, zoom}, zoom being this window's size relative to the design size (see
// tools/clap-patch.mjs). Elsewhere (cmaj play, the UI preview) nothing answers: the host
// owns the window size there.

type t = {
  channel: HostChannel.t,
  // the saved settings, once the plugin has answered
  mutable saved: option<Dict.t<JSON.t>>,
  // whether the plugin has answered (a setting saved where nothing answers is kept for the view)
  mutable answered: bool,
  mutable zoom: float,
  mutable listeners: array<unit => unit>,
}

let zoomSteps = [0.75, 1., 1.25, 1.5, 1.75, 2., 2.5, 3.]

let request = (t, what) => t.channel->HostChannel.request(what)

let onReply = (t, reply: dict<JSON.t>) => {
  t.answered = true
  t.saved = switch reply->Dict.get("settings") {
  | Some(Object(saved)) => Some(saved)
  | _ => Some(Dict.make())
  }
  switch reply->Dict.get("zoom") {
  | Some(Number(zoom)) if Float.isFinite(zoom) => t.zoom = zoom
  | _ => ()
  }
  t.listeners->Array.forEach(fn => fn())
}

let make = pc => {
  let t = {channel: HostChannel.make(pc, "settings"), saved: None, answered: false, zoom: 1., listeners: []}
  t.channel->HostChannel.listen(onReply(t, _))
  request(t, "get")
  t
}

let dispose = t => t.channel->HostChannel.dispose

// whether the plugin keeps the settings and sizes the window
let available = t => t.answered

// Calls fn whenever the plugin answers; returns a function that stops it.
let listen = (t, fn) => {
  let wrapped = () => fn()
  t.listeners->Array.push(wrapped)
  () => t.listeners = t.listeners->Array.filter(f => f !== wrapped)
}

let refresh = t => request(t, "get")

let savedValue = (t, key) => t.saved->Option.flatMap(Dict.get(_, key))

// the size new windows open at
let savedZoom = t =>
  switch savedValue(t, "zoom") {
  | Some(Number(zoom)) if Float.isFinite(zoom) => zoom
  | _ => 1.
  }

// a saved switch
let bool = (t, key, ~default) =>
  switch savedValue(t, key) {
  | Some(Boolean(on)) => on
  | _ => default
  }

// asks the host to resize this window
let setZoom = (t, zoom) => request(t, "zoom=" ++ Float.toString(zoom))

let save = (t, key, value) => {
  let saved = t.saved->Option.mapOr(Dict.make(), Dict.copy)
  saved->Dict.set(key, value)
  t.saved = Some(saved)
  request(t, "save=" ++ JSON.stringify(Object(saved)))
}
