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

// What opens the menu for some parameters that the host lists, at a point in the view
type opener = (array<string>, float, float) => unit

// A right press on a control that has the host's menu: when, where, what puts back the values it
// may change, and what opens the menu if a second press makes it a double one
type press = {at: float, x: float, y: float, restore: unit => unit, listed: array<string>, open_: opener}

type t = {
  channel: HostChannel.t,
  // whether the host can show its menu
  mutable available: bool,
  // stops listening for the press or key that closes the menu, while it may be open
  mutable stopDismiss: option<unit => unit>,
  // the last right press on a control with the host's menu, and the double press's menu, which
  // opens with the context menu event that comes after it
  mutable last: option<press>,
  mutable armed: option<(array<string>, opener)>,
  stopDoubles: unit => unit,
}

// Windows' default double-click time, and how far the second click may be from the first
let doubleClickMs = 500.
let doubleClickPixels = 6.

let make = pc => {
  // A second right press near the first, soon after, is a double one wherever it lands: the first
  // may have moved what it pressed (a graph's point, reset), so the document hears it, before
  // anything in the view does.
  let tRef = ref(None)
  let onPress = ev =>
    tRef.contents->Option.forEach(t =>
      switch t.last {
      | Some(p)
        if ev->button == 2 &&
        Date.now() - p.at <= doubleClickMs &&
        Math.hypot(ev->clientX - p.x, ev->clientY - p.y) <= doubleClickPixels =>
        t.last = None
        t.armed = Some((p.listed, p.open_))
        ev->preventDefault
        ev->stopImmediatePropagation
        p.restore()
      | _ =>
        t.last = None
        t.armed = None
      }
    )
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
    last: None,
    armed: None,
    stopDoubles: () => {
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
  t.stopDoubles()
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

// Opens the menu (also from a control's own menu: Controls) on a double right-click on e, which
// edits the parameters ids() gives: open gets those the host lists, and where it was clicked (a
// graph's point can edit several: Controls.hostMenuFor picks one). The first click has already
// done what a right-click does there (reset the values, step a list...), so the second puts back
// the values from before it, and the control never sees it (make's listeners take it). The menu
// opens with the context menu event, which comes with the release on Windows, as menus do there.
// (Hosts have no menu for the routing and setup parameters, which they don't list:
// ParamInfo.isSetup.)
let attachMany = (t, model, e, ids: unit => array<string>, ~open_: opener) => {
  e->onPointerCapture(#pointerdown, ev => {
    let all = ids()
    let listed = all->Array.filter(id => has(t, id))
    if ev->button == 2 && listed != [] {
      let before = all->Array.map(id => (id, model->ParamModel.get(id)))
      t.last = Some({
        at: Date.now(),
        x: ev->clientX,
        y: ev->clientY,
        restore: () =>
          before->Array.forEach(((id, v)) =>
            if model->ParamModel.get(id) != v {
              model->ParamModel.gestureSet(id, v)
            }
          ),
        listed,
        open_,
      })
    }
  })
  e->onMouse(#contextmenu, preventDefault)
}

// The same for a control of one parameter.
let attach = (t, model, e, id) =>
  attachMany(t, model, e, () => [id], ~open_=(_, x, y) => showAt(t, model, id, ~x, ~y))
