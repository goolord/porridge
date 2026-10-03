// The host's menu for a parameter, which a shift+right-click on a control opens, as does
// "Host menu…" in the control's own menu (Controls.contextMenu). In FL Studio it has Create
// automation clip, Link to controller, Edit events and so on.
//
// The CLAP plugin answers stored-state requests whose key starts with "porridge:host?" (see
// tools/clap-patch.mjs): ?get with a "porridge:host" value {menu}, whether the host can show
// its menu (CLAP's context-menu extension); ?menu=<json> {id, x, y, scale} shows it for the
// parameter with that endpoint id, at a point in the view (CSS pixels, and the device pixel
// ratio); ?dismiss closes it. Elsewhere (cmaj play, the UI preview) nothing answers, and a
// shift+right-click is a right-click.
//
// On Windows the host's menu never hears a click or a key in the view, whose window belongs to
// the web view's own process, so it would stay open until a click somewhere else in the host.
// The next press or Escape in the view after the menu opens asks the plugin to close it, which
// it does from inside the host's menu loop (in FL Studio, by posting the WM_CLOSE its menus
// close on; see porridge::dismissHostMenu in tools/clap/PorridgeBridge.h). The press goes on
// to do what it does in the view.

open! Web

// What opens the menu for some parameters that the host lists, at a point in the view
type opener = (array<string>, float, float) => unit

type t = {
  channel: HostChannel.t,
  // whether the host can show its menu
  mutable available: bool,
  // stops listening for the press or key that closes the menu, while it may be open
  mutable stopDismiss: option<unit => unit>,
  // the menu a shift+right press on a control asked for, which opens with the context menu event
  // that comes after it
  mutable armed: option<(array<string>, opener)>,
  stopPresses: unit => unit,
}

let make = pc => {
  // (every press forgets a menu asked for before it: the document hears it before the control
  // that may ask again)
  let tRef = ref(None)
  let onPress = _ => tRef.contents->Option.forEach(t => t.armed = None)
  let onMenu = ev =>
    tRef.contents->Option.forEach(t =>
      t.armed->Option.forEach(((listed, open_)) => {
        t.armed = None
        ev->preventDefault
        open_(listed, ev->clientX, ev->clientY)
      })
    )
  document->onDocumentPointerDownCapture(onPress)
  document->onDocumentMouse(#contextmenu, onMenu)
  let t = {
    channel: HostChannel.make(pc, "host"),
    available: false,
    stopDismiss: None,
    armed: None,
    stopPresses: () => {
      document->offDocumentPointerDownCapture(onPress)
      document->offDocumentMouse(#contextmenu, onMenu)
    },
  }
  tRef := Some(t)
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
  t.stopPresses()
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

// Shows the menu for the parameter id at a point in the view (client coordinates): for a slot's
// parameter, its knob's (SlotParams), which is what hosts know.
let showAt = (t, model, id, ~x, ~y) => {
  let id = model->ParamModel.endpointOf(id)->Option.getOr(id)
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

// Opens the menu (also from a control's own menu: Controls) on a shift+right-click on e, which
// edits the parameters ids() gives: open gets those the host lists, and where it was clicked (a
// graph's point can edit several: Controls.hostMenuFor picks one). The control never sees the
// press, so it doesn't do what a right-click does there (reset, step a list...): hook this before
// the control's own pointer handlers. The menu opens with the context menu event, which comes
// with the release on Windows, as menus do there. (Hosts have no menu for the routing and setup
// parameters, which they don't list: ParamInfo.isSetup.)
let attachMany = (t, e, ids: unit => array<string>, ~open_: opener) => {
  e->onPointerCapture(#pointerdown, ev =>
    if ev->button == 2 && ev->shiftKey {
      let listed = ids()->Array.filter(id => has(t, id))
      if listed != [] {
        ev->preventDefault
        ev->stopImmediatePropagation
        t.armed = Some((listed, open_))
      }
    }
  )
  e->onMouse(#contextmenu, preventDefault)
}

// The same for a control of one parameter.
let attach = (t, model, e, id) =>
  attachMany(t, e, () => [id], ~open_=(_, x, y) => showAt(t, model, id, ~x, ~y))
