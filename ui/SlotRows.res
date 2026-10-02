// Target slots (a target list and a depth each, like the XY pad's and the controllers'), shown as
// the slots in use, a row each, and a "+" button while one is free: four rows of "none" say
// nothing. Picking "none" in a row's list frees its slot.

open! Web

type t = {
  // how many rows it takes now
  rows: unit => int,
  // puts its first row at y
  place: float => unit,
}

// (a new route's depth: a quarter of the way, as a new connection on the Mod page)
let defaultDepth = (def: ParamDefs.t) => def.fromNorm(def.bipolar ? 0.625 : 0.25)

// The slots, (target id, depth id) each, in columns cw wide from x: a row is the target's list
// over two columns and its depth in the third, label naming the list. The "+" button is the row
// after them, or ~addAt a box in another element (out of the rows). onChange is called when the
// number of rows changes, for the caller to lay out what follows.
let make = (ctx: Ctx.t, parent, slots: array<(string, string)>, ~x, ~cw, ~label, ~addAt=?, ~onChange=() => ()) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let isUsed = ((target, _)) => get(target) != 0.
  let top = ref(0.)
  let rows = slots->Array.map(((target, depth)) => {
    let row = el("div", ~cls="srow", ~parent)
    Controls.choice(ctx, row, target, ~x=0., ~y=0., ~w=2. * cw - Grid.columnGap, ~label)
    Controls.param(ctx, row, depth, ~x=2. * cw, ~y=0., ~w=cw - Grid.columnGap, ~label="depth")
    row
  })

  // the targets to pick from: the slot's list, but none
  let add = (anchor, (target, depth)) => {
    let names = Controls.namesOf(model->ParamModel.def(target))
    ctx.menu->Menu.show(
      anchor,
      names->Array.mapWithIndex((name, value) => {Menu.label: name, value})->Array.filter(i => i.value > 0),
      -1,
      v => {
        model->ParamModel.gestureSet(target, Int.toFloat(v))
        if get(depth) == 0. {
          model->ParamModel.gestureSet(depth, defaultDepth(model->ParamModel.def(depth)))
        }
        model->ParamModel.nameStep(`${label}: ${names[v]->Option.getOr("")}`)
      },
    )
  }
  let (addParent, addBox: box) = switch addAt {
  | Some(at) => at
  | None => (parent, {x, y: 0., w: 3. * cw - Grid.columnGap, h: Style.controlHeight})
  }
  let addButton = Controls.button(
    ctx,
    addParent,
    "+ " ++ label,
    ~x=addBox.x,
    ~y=addBox.y,
    ~w=addBox.w,
    ~h=addBox.h,
    ~cls="add",
    () => (),
  )
  addButton->onMouse(#click, _ => slots->Array.find(s => !isUsed(s))->Option.forEach(add(addButton, _)))
  ctx.status->Status.hover(addButton, () => `Add a ${label}: pick what it moves, then set its depth`)

  let used = () => slots->Array.filter(isUsed)->Array.length
  let full = () => used() == Array.length(slots)
  let count = () => used() + (addAt == None && !full() ? 1 : 0)
  let shown = ref(count())
  let layout = () => {
    let i = ref(0)
    slots->Array.forEachWithIndex((s, k) => {
      let row = rows->Array.getUnsafe(k)
      if isUsed(s) {
        row->place(x, top.contents + Int.toFloat(i.contents) * Grid.rowHeight)->ignore
        row->setStyle("display", "")
        i := i.contents + 1
      } else {
        row->setStyle("display", "none")
      }
    })
    addButton->toggleClass("off", full())
    if addAt == None {
      addButton->setStyle("display", full() ? "none" : "")
      addButton->setStyle("top", px(top.contents + Int.toFloat(i.contents) * Grid.rowHeight))
    }
  }
  model->ParamModel.listenEach(slots->Array.map(((target, _)) => target), () => {
    layout()
    let n = count()
    if n != shown.contents {
      shown := n
      onChange()
    }
  })
  {
    rows: count,
    place: y => {
      top := y
      layout()
    },
  }
}
