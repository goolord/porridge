// The status bar message: hover texts, or a hint about the current page when idle. A text too
// long for its line is set a little smaller, and if that isn't enough takes two lines, growing
// the bar up over the pages' bottom margin rather than taking height from them.

open! Web

type t = {msg: element, mutable idle: string}

@get external scrollWidth: element => float = "scrollWidth"

let make = msg => {msg, idle: ""}

let setText = (t, text) => {
  let overflows = () => t.msg->scrollWidth > t.msg->clientWidth + 1.
  t.msg->setTextContent(text)
  t.msg->removeClass("small")
  t.msg->removeClass("two")
  if overflows() {
    t.msg->addClass("small")
    if overflows() {
      t.msg->removeClass("small")
      t.msg->addClass("two")
    }
  }
}

let show = (t, text) => {
  setText(t, text)
  t.msg->removeClass("idle")
}

let clear = t => {
  setText(t, t.idle)
  t.msg->addClass("idle")
}

let setIdle = (t, text) => {
  t.idle = text
  clear(t)
}

// Shows text() while the pointer is over e.
let hover = (t, e, text) => {
  e->onMouse(#mouseenter, _ => show(t, text()))
  e->onMouse(#mouseleave, _ => clear(t))
}

// Shows text() while the pointer is over e, and through a drag that started there: refresh
// shows it again after a change, setDragging marks the drag.
type live = {refresh: unit => unit, setDragging: bool => unit}

let live = (t, e, text) => {
  let hover = ref(false)
  let dragging = ref(false)
  let refresh = () =>
    if hover.contents || dragging.contents {
      show(t, text())
    }
  e->onMouse(#mouseenter, _ => {
    hover := true
    show(t, text())
  })
  e->onMouse(#mouseleave, _ => {
    hover := false
    if !dragging.contents {
      clear(t)
    }
  })
  let setDragging = on => {
    dragging := on
    if !on {
      hover.contents ? show(t, text()) : clear(t)
    }
  }
  {refresh, setDragging}
}
