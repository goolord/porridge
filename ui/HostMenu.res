// The host's menu for a parameter, which a double right-click on a control opens, as does
// "Host menu…" in the control's own menu (Controls.contextMenu). In FL Studio it has Create
// automation clip, Link to controller, Edit events and so on.
//
// The CLAP plugin answers stored-state requests whose key starts with "porridge:host?" (see
// tools/clap-patch.mjs): ?get with a "porridge:host" value {menu}, whether the host can show
// its menu (CLAP's context-menu extension); ?menu=<json> {id, x, y, scale} shows it for the
// parameter with that endpoint id, at a point in the view (CSS pixels, and the device pixel
// ratio); ?dismiss closes it. Elsewhere (cmaj play, the UI preview) nothing answers, and a
// double right-click is two right-clicks.
//
// On Windows the host's menu never hears a click or a key in the view, whose window belongs to
// the web view's own process, so it would stay open until a click somewhere else in the host.
// The next press or Escape in the view after the menu opens asks the plugin to close it, which
// it does from inside the host's menu loop (in FL Studio, by posting the WM_CLOSE its menus
// close on; see porridge::dismissHostMenu in tools/clap/PorridgeBridge.h). The press goes on
// to do what it does in the view.

open! Web

type t = {
  channel: HostChannel.t,
  // whether the host can show its menu
  mutable available: bool,
  // stops listening for the press or key that closes the menu, while it may be open
  mutable stopDismiss: option<unit => unit>,
}

// Windows' default double-click time
let doubleClickMs = 500.

let make = pc => {
  let t = {channel: HostChannel.make(pc, "host"), available: false, stopDismiss: None}
  t.channel->HostChannel.listen(reply =>
    t.available = switch reply->Dict.get("menu") {
    | Some(Boolean(menu)) => menu
    | _ => false
    }
  )
  t.channel->HostChannel.request("get")
  t
}

let stopDismissing = t => {
  t.stopDismiss->Option.forEach(stop => stop())
  t.stopDismiss = None
}

let dispose = t => {
  t->stopDismissing
  t.channel->HostChannel.dispose
}

// Closes the menu on the next press or Escape in the view. The menu may have closed already (an
// item was picked), so the press still does what it does.
let dismissOnNextInput = t => {
  t->stopDismissing
  let dismiss = () => {
    t->stopDismissing
    t.channel->HostChannel.request("dismiss")
  }
  let onPress = _ => dismiss()
  let onKey = ev =>
    if ev->key == "Escape" {
      dismiss()
    }
  document->onDocumentPointerDownCapture(onPress)
  document->onDocumentKeyDown(onKey)
  t.stopDismiss = Some(
    () => {
      document->offDocumentPointerDownCapture(onPress)
      document->offDocumentKeyDown(onKey)
    },
  )
}

// Whether the host has a menu for the parameter id: it can show one, and lists the parameter.
let has = (t, id) => t.available && !ParamInfo.isSetup(id)

// Shows the menu for the parameter id at a point in the view (client coordinates).
let showAt = (t, id, ~x, ~y) => {
  t->dismissOnNextInput
  t.channel->HostChannel.request(
    "menu=" ++
    JSON.stringify(
      Object(
        Dict.fromArray([
          ("id", JSON.String(id)),
          ("x", Number(x)),
          ("y", Number(y)),
          ("scale", Number(devicePixelRatio)),
        ]),
      ),
    ),
  )
}

// Opens the menu (also from a control's own menu: Controls) on a double right-click on e, a
// control for the parameter id. The first click
// has already done what a right-click does there (reset the value, step it...), so the second
// puts back the value from before it, and the control never sees it. The menu opens with the
// context menu event, which comes with the release on Windows, as menus do there. (Hosts have
// no menu for the routing and setup parameters, which they don't list: ParamInfo.isSetup.)
let attach = (t, model, e, id) => {
  // the time of the last right press, and the value before it
  let last = ref(None)
  let armed = ref(false)
  e->onPointerCapture(#pointerdown, ev => {
    armed := false
    if ev->button == 2 && has(t, id) {
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
      showAt(t, id, ~x=ev->clientX, ~y=ev->clientY)
    }
  })
}
