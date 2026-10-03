// Pop-up menus, positioned below an anchor inside the stage. A press anywhere else closes them;
// opening the menu again from the same anchor closes it instead.
//
// Besides plain rows, a menu can be a picker: a row can open a menu of its own beside it (a
// family of values: lowpass > ladder), end in chips that pick its variants (12 dB, 24 dB), carry
// a small badge ("classic"), or wait with the other rare values behind a "more" row.

open! Web

// A chip at the end of a row: a variant of the row's value, which it picks.
type chip = {chip: string, pick: int, about?: string}

// An item may have an icon in front of its label (see Icons), a heading above it that starts
// a group (or a rule above it), a hint the status bar shows while the pointer is over it, a
// check mark (checked: false leaves its place empty), its keyboard shortcut, and be disabled.
// Long menus run in columns.
type rec item = {
  label: string,
  value: int,
  icon?: element,
  heading?: string,
  rule?: bool,
  hint?: string,
  checked?: bool,
  keys?: string,
  disabled?: bool,
  // a small mark after the label
  badge?: string,
  // the row's variants, as chips at its end (the row itself picks its value)
  variants?: array<chip>,
  // a menu beside the row, shown while the pointer is on it (the row itself picks its value)
  sub?: array<item>,
  // left out, with the others like it, behind a "more" row until that is clicked (unless one
  // of them is the current value)
  more?: bool,
}

let rowsPerColumn = 24

type t = {
  root: element,
  status: Status.t,
  // what is open: the menus (the first, and one beside it) in one element
  mutable menu: option<element>,
  mutable anchor: option<element>,
  // stops closing the menu on a press outside it
  mutable closer: option<unit => unit>,
}

let make = (root, ~status) => {root, status, menu: None, anchor: None, closer: None}

let close = t => {
  if Option.isSome(t.menu) {
    t.status->Status.clear
  }
  t.closer->Option.forEach(stop => stop())
  t.closer = None
  t.menu->Option.forEach(remove)
  t.menu = None
  t.anchor = None
}

let isOpenFor = (t, anchor) => t.anchor->Option.mapOr(false, a => a === anchor)

// The values an item offers: its own, or its chips' or those of the menu beside it (with its
// own first if they don't have it).
let rec offers = item => {
  let others = switch (item.sub, item.variants) {
  | (Some(sub), _) => sub->Array.flatMap(offers)
  | (None, Some(chips)) => chips->Array.map(c => c.pick)
  | (None, None) => []
  }
  others->Array.includes(item.value) ? others : [item.value, ...others]
}

// Every value the menu offers, in its order, each once.
let values = items => {
  let seen = Set.make()
  items->Array.flatMap(offers)->Array.filter(v =>
    if seen->Set.has(v) {
      false
    } else {
      seen->Set.add(v)
      true
    }
  )
}

let holds = (item, current) => offers(item)->Array.includes(current)

// A menu's element and its rows, filled with items (sub: a function that opens an item's own
// menu beside its row, or None for a menu beside another).
let fill = (t, m, items, current, onPick, ~openSub) => {
  if items->Array.some(item => item.icon != None) {
    m->addClass("icons")
  }
  if items->Array.some(item => item.checked != None || item.keys != None) {
    m->addClass("rich")
  }
  if items->Array.some(item => item.badge != None || item.variants != None || item.sub != None) {
    m->addClass("pick")
  }
  let withIcons = items->Array.some(item => item.icon != None)
  let withChecks = items->Array.some(item => item.checked != None)
  // the rare ones wait behind "more", unless the current value is one of them
  let hideMore = !(items->Array.some(item => item.more == Some(true) && holds(item, current)))
  let hidden = []
  let moreRow = ref(None)
  let pick = value => {
    close(t)
    onPick(value)
  }
  items->Array.forEach(item => {
    let {label, value, ?icon, ?heading, ?rule, ?hint, ?checked, ?keys, ?disabled, ?badge, ?variants, ?sub} = item
    let hide = hideMore && item.more == Some(true)
    if hide && moreRow.contents == None {
      let row = el("div", ~cls="more", ~text="more…", ~parent=m)
      t.status->Status.hover(row, () => "Show the rarer choices too")
      moreRow := Some(row)
    }
    let mark = e => {
      if hide {
        e->addClass("hid")
        hidden->Array.push(e)
      }
      e
    }
    heading->Option.forEach(text => el("div", ~cls="mh", ~text, ~parent=m)->mark->ignore)
    if rule == Some(true) {
      el("hr", ~parent=m)->mark->ignore
    }
    let row = el("div", ~cls=holds(item, current) ? "cur" : "", ~parent=m)->mark
    if withChecks {
      el("span", ~cls="ck", ~text=checked == Some(true) ? "✓" : "", ~parent=row)->ignore
    }
    switch icon {
    | Some(icon) => row->appendChild(icon)
    | None if withIcons => el("span", ~cls="icw", ~parent=row)->ignore
    | None => ()
    }
    el("span", ~text=label, ~parent=row)->ignore
    badge->Option.forEach(text => el("span", ~cls="bdg", ~text, ~parent=row)->ignore)
    keys->Option.forEach(text => el("span", ~cls="keys", ~text, ~parent=row)->ignore)
    variants->Option.forEach(chips => {
      let tail = el("span", ~cls="tail", ~parent=row)
      chips->Array.forEach(({chip, pick: v, ?about}) => {
        let c = el("span", ~cls=v == current ? "chip cur" : "chip", ~text=chip, ~parent=tail)
        about->Option.forEach(text => t.status->Status.hover(c, () => text))
        c->onPointer(#pointerdown, ev => {
          ev->stopPropagation
          ev->preventDefault
          pick(v)
        })
      })
    })
    if sub != None {
      el("span", ~cls="sa", ~text="›", ~parent=row)->ignore
    }
    hint->Option.forEach(text => t.status->Status.hover(row, () => text))
    openSub->Option.forEach(openSub => row->onMouse(#mouseenter, _ => openSub(row, sub)))
    let disabled = disabled == Some(true)
    row->toggleClass("off", disabled)
    row->onPointer(#pointerdown, ev => {
      ev->stopPropagation
      ev->preventDefault
      if !disabled {
        pick(value)
      }
    })
  })
  (moreRow.contents, hidden)
}

// Places a menu below the anchor (or above it, when there is no room below), inside the stage.
let placeBelow = (t, m, anchor) => {
  let stage = t.root
  let (x, y) = anchor->offsetWithin(stage)
  let y = y + anchor->offsetHeight
  let (width, height) = (stage->offsetWidth, stage->offsetHeight)
  m->place(0., 0.)->ignore
  let (mw, mh) = (m->offsetWidth, m->offsetHeight)
  let x = x + mw > width - 4. ? width - mw - 4. : x
  let y = y + mh > height - 4. ? Math.max(4., y - anchor->offsetHeight - mh) : y
  m->place(x, y)->ignore
}

// Places a menu beside a row of another, on its right if it fits there (else its left).
let placeBeside = (t, m, row, ~parent) => {
  let stage = t.root
  let (px, _) = parent->offsetWithin(stage)
  let (_, ry) = row->offsetWithin(stage)
  let ry = ry - parent->scrollTop
  let (width, height) = (stage->offsetWidth, stage->offsetHeight)
  m->place(0., 0.)->ignore
  let (mw, mh) = (m->offsetWidth, m->offsetHeight)
  let right = px + parent->offsetWidth - 2.
  let x = right + mw > width - 4. ? Math.max(4., px - mw + 2.) : right
  let y = Math.max(4., Math.min(ry - 3., height - mh - 4.))
  m->place(x, y)->ignore
}

let show = (t, anchor, items, current, onPick) =>
  if isOpenFor(t, anchor) {
    close(t)
  } else {
    close(t)
    // (the menus' element has no box of its own: each menu is placed in the stage)
    let holder = el("div", ~cls="menus", ~parent=t.root)
    let m = el("div", ~cls="menu", ~parent=holder)
    t.menu = Some(holder)
    t.anchor = Some(anchor)
    let fitColumns = () => {
      let rows = m->querySelectorAll(":scope > div:not(.hid)")->nodesToArray->Array.length
      m->toggleClass("cols", rows > rowsPerColumn)
      m->setStyle("column-count", rows > rowsPerColumn ? Int.toString((rows + rowsPerColumn - 1) / rowsPerColumn) : "")
    }

    // the menu beside a row: opened a moment after the pointer comes onto the row (so that
    // crossing rows on the way to it doesn't swap it), closed when it moves to a row without one
    let beside = ref(None)
    let timer = ref(None)
    let wait = (ms, f) => {
      timer.contents->Option.forEach(clearTimeout)
      timer := Some(setTimeout(() => {
        timer := None
        if t.menu->Option.mapOr(false, shown => shown === holder) {
          f()
        }
      }, ms))
    }
    let closeBeside = () => {
      beside.contents->Option.forEach(((s, row)) => {
        s->remove
        row->toggleClass("open", false)
      })
      beside := None
    }
    let openSub = (row, sub) =>
      switch (beside.contents, sub) {
      | (Some((_, r)), _) if r === row => timer.contents->Option.forEach(clearTimeout)
      | (_, Some(sub)) =>
        wait(beside.contents == None ? 60 : 200, () => {
          closeBeside()
          let s = el("div", ~cls="menu beside", ~parent=holder)
          fill(t, s, sub, current, onPick, ~openSub=None)->ignore
          s->onMouse(#mouseenter, _ => timer.contents->Option.forEach(clearTimeout))
          row->toggleClass("open", true)
          placeBeside(t, s, row, ~parent=m)
          beside := Some((s, row))
        })
      | (_, None) => wait(200, closeBeside)
      }
    let (moreRow, hidden) = fill(t, m, items, current, onPick, ~openSub=Some(openSub))
    fitColumns()
    placeBelow(t, m, anchor)
    moreRow->Option.forEach(row =>
      row->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        row->remove
        hidden->Array.forEach(e => e->toggleClass("hid", false))
        fitColumns()
        placeBelow(t, m, anchor)
      })
    )

    // presses on the anchor are left to it, so that it can close the menu again
    t.closer = Some(onPressOutside([holder, anchor], () => close(t)))
  }

// Shows a menu at a point inside parent (in its design pixels), as if below an anchor there.
let showAt = (t, parent, ~x, ~y, items, current, onPick) => {
  let anchor = el("div", ~parent)->place(x, y, ~w=1., ~h=1.)
  anchor->setStyle("position", "absolute")
  show(t, anchor, items, current, onPick)
  anchor->remove
}

// Shows a menu at a point on the screen (client coordinates: a pointer's), as if below an anchor
// there.
let showAtClient = (t, ~x, ~y, items, current, onPick) => {
  let r = t.root->getBoundingClientRect
  let s = r.width / t.root->offsetWidth
  showAt(t, t.root, ~x=(x - r.left) / s, ~y=(y - r.top) / s, items, current, onPick)
}
