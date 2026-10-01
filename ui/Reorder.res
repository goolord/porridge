// Dragging one of a row of elements sideways to another place in the row (the FX page's tabs and
// rack cards): past a few pixels the element follows the pointer and a mark shows where it will
// land; a press that doesn't move is a click.

open! Web

let threshold = 4.

let start = (ev, item: element, ~others: array<element>, ~onDrop: int => unit, ~onClick: unit => unit) => {
  let startX = ev->clientX
  // css pixels per screen pixel (the view is scaled to the window)
  let k = item->offsetWidth / Math.max(1., (item->getBoundingClientRect).width)
  let moved = ref(false)
  let target = ref(None)
  let centre = e => {
    let r = e->getBoundingClientRect
    r.left + r.width / 2.
  }
  // where it lands among the others: before the first whose middle is right of x
  let landing = x => others->Array.filter(o => centre(o) < x)->Array.length
  let clearMarks = () =>
    others->Array.forEach(o => {
      o->toggleClass("drop-before", false)
      o->toggleClass("drop-after", false)
    })
  item->Controls.capturePointer(
    ev,
    ~onMove=mv => {
      let dx = mv->clientX - startX
      if !moved.contents && Math.abs(dx) > threshold {
        moved := true
        item->toggleClass("drag", true)
      }
      if moved.contents {
        item->setStyle("transform", `translateX(${Float.toString(dx * k)}px)`)
        let pos = landing(mv->clientX)
        target := Some(pos)
        clearMarks()
        switch (others[pos], others[pos - 1]) {
        | (Some(o), _) => o->toggleClass("drop-before", true)
        | (None, Some(o)) => o->toggleClass("drop-after", true)
        | _ => ()
        }
      }
    },
    ~onUp=() => {
      item->toggleClass("drag", false)
      item->setStyle("transform", "")
      clearMarks()
      if moved.contents {
        target.contents->Option.forEach(onDrop)
      } else {
        onClick()
      }
    },
  )
}
