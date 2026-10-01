// Pop-up menus, positioned below an anchor inside the stage. A press anywhere else closes them.

open! Web

type item = {label: string, value: int}

type t = {
  root: element,
  mutable menu: option<element>,
  mutable closer: option<Dom.pointerEvent => unit>,
}

let make = root => {root, menu: None, closer: None}

let close = t => {
  t.closer->Option.forEach(closer => document->offDocumentPointerDownCapture(closer))
  t.closer = None
  t.menu->Option.forEach(remove)
  t.menu = None
}

let show = (t, anchor, items, current, onPick) => {
  close(t)
  let m = el("div", ~cls="menu", ~parent=t.root)
  t.menu = Some(m)
  items->Array.forEach(({label, value}) => {
    let row = el("div", ~cls=value == current ? "cur" : "", ~text=label, ~parent=m)
    row->onPointer(#pointerdown, ev => {
      ev->stopPropagation
      ev->preventDefault
      close(t)
      onPick(value)
    })
  })

  // position below the anchor inside the stage
  let stage = t.root
  let (x, y) = anchor->offsetWithin(stage)
  let y = y + anchor->offsetHeight
  let (width, height) = (stage->offsetWidth, stage->offsetHeight)
  m->place(0., 0.)->ignore
  let (mw, mh) = (m->offsetWidth, m->offsetHeight)
  let x = x + mw > width - 4. ? width - mw - 4. : x
  let y = y + mh > height - 4. ? Math.max(4., y - anchor->offsetHeight - mh) : y
  m->place(x, y)->ignore

  let closer = ev =>
    if !(m->contains(ev->target)) {
      close(t)
    }
  setTimeout(() =>
    // the menu may already be gone
    if t.menu->Option.mapOr(false, open_ => open_ === m) {
      t.closer = Some(closer)
      document->onDocumentPointerDownCapture(closer)
    }
  , 0)->ignore
}
