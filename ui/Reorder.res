// Dragging one of a row of elements sideways to another place in the row (the FX page's tabs),
// or with ~vertical one of a column up or down: past a few pixels the element follows the
// pointer and a mark shows where it will land; a press that doesn't move is a click. ~markAt
// says where the mark goes for a place, as an element and whether before it, when the places
// aren't simply between the others (Oatmeal's distortion: before or after the filter).

open! Web

let threshold = 4.

let start = (
  ev,
  item: element,
  ~others: array<element>,
  ~onDrop: int => unit,
  ~onClick: unit => unit,
  ~vertical=false,
  ~markAt=?,
) => {
  let along = e => vertical ? e->clientY : e->clientX
  let startX = along(ev)
  // css pixels per screen pixel (the view is scaled to the window)
  let k = item->offsetWidth / Math.max(1., (item->getBoundingClientRect).width)
  let moved = ref(false)
  let target = ref(None)
  let centre = e => {
    let r = e->getBoundingClientRect
    vertical ? r.top + r.height / 2. : r.left + r.width / 2.
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
      let dx = along(mv) - startX
      if !moved.contents && Math.abs(dx) > threshold {
        moved := true
        item->toggleClass("drag", true)
      }
      if moved.contents {
        item->setStyle("transform", `${vertical ? "translateY" : "translateX"}(${Float.toString(dx * k)}px)`)
        let pos = landing(along(mv))
        target := Some(pos)
        clearMarks()
        let mark = switch markAt {
        | Some(at) => at(pos)
        | None =>
          switch (others[pos], others[pos - 1]) {
          | (Some(o), _) => Some((o, true))
          | (None, Some(o)) => Some((o, false))
          | _ => None
          }
        }
        mark->Option.forEach(((o, before)) => o->toggleClass(before ? "drop-before" : "drop-after", true))
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
