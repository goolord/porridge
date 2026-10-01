// The host's menu for a parameter, which a double right-click on a control opens. In FL Studio
// it has Create automation clip, Link to controller, Edit events and so on.
//
// The CLAP plugin answers stored-state requests whose key starts with "porridge:host?" (see
// tools/clap-patch.mjs): ?get with a "porridge:host" value {menu}, whether the host can show
// its menu (CLAP's context-menu extension); ?menu=<json> {id, x, y, scale} shows it for the
// parameter with that endpoint id, at a point in the view (CSS pixels, and the device pixel
// ratio). Elsewhere (cmaj play, the UI preview) nothing answers, and a double right-click is
// two right-clicks.

open! Web

type t = {
  pc: PatchConnection.t,
  // whether the host can show its menu
  mutable available: bool,
  mutable stateListener: option<PatchConnection.storedStateEvent => unit>,
}

let requestPrefix = "porridge:host?"
let replyKey = "porridge:host"

// Windows' default double-click time
let doubleClickMs = 500.

let request = (t, what) => t.pc->PatchConnection.requestStoredStateValue(requestPrefix ++ what)

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  switch value {
  | Object(reply) if key == replyKey =>
    t.available = switch reply->Dict.get("menu") {
    | Some(Boolean(menu)) => menu
    | _ => false
    }
  | _ => ()
  }

let make = pc => {
  let t = {pc, available: false, stateListener: None}
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

// Shows the menu for the parameter id where ev happened.
let show = (t, id, ev) =>
  request(
    t,
    "menu=" ++
    JSON.stringify(
      Object(
        Dict.fromArray([
          ("id", JSON.String(id)),
          ("x", Number(ev->clientX)),
          ("y", Number(ev->clientY)),
          ("scale", Number(devicePixelRatio)),
        ]),
      ),
    ),
  )

// Opens the menu on a double right-click on e, a control for the parameter id. The first click
// has already done what a right-click does there (reset the value, step it...), so the second
// puts back the value from before it, and the control never sees it. The menu opens with the
// context menu event, which comes with the release on Windows, as menus do there.
let attach = (t, model, e, id) => {
  // the time of the last right press, and the value before it
  let last = ref(None)
  let armed = ref(false)
  e->onPointerCapture(#pointerdown, ev => {
    armed := false
    if ev->button == 2 && t.available {
      let now = Date.now()
      switch last.contents {
      | Some((at, before)) if now - at <= doubleClickMs =>
        last := None
        armed := true
        ev->preventDefault
        ev->stopImmediatePropagation
        if model->ParamModel.get(id) != before {
          model->ParamModel.gestureSet(id, before)
        }
      | _ => last := Some((now, model->ParamModel.get(id)))
      }
    } else {
      last := None
    }
  })
  e->onMouse(#contextmenu, ev => {
    ev->preventDefault
    if armed.contents {
      armed := false
      show(t, id, ev)
    }
  })
}
