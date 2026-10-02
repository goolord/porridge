// Where every control lives, so that search (Palette) and the patch summary can take you to it.
// Each parameter control registers its element as it is made (Controls), and each container that
// can hide what it holds registers what it is called and how to show it: the pages (View), the
// panels' tabs (Panel), the graphical editors' raw values (NodeEditor). Reaching a control shows
// its containers, outermost first, and flashes it; its path ("Synth › lfo 2") is their names.
// Nothing is worked out until something is looked for.

open! Web

@get external isConnected: element => bool = "isConnected"
@send external hasClass: (classList, string) => bool = "contains"

type place = {label: string, show: unit => unit}

// the controls made so far, by parameter (a parameter can show in more than one place), per view
let controls: WeakMap.t<ParamModel.t, Map.t<string, array<element>>> = WeakMap.make()
let places: WeakMap.t<element, place> = WeakMap.make()
// each control's parameter, to tell which one the pointer is over
let params: WeakMap.t<element, string> = WeakMap.make()

let byId = model =>
  switch controls->WeakMap.get(model) {
  | Some(m) => m
  | None =>
    let m = Map.make()
    controls->WeakMap.set(model, m)->ignore
    m
  }

// Registers a control: e shows parameter id.
let control = (model, id, e) => {
  let m = byId(model)
  m->Map.set(id, [...m->Map.get(id)->Option.getOr([]), e])
  params->WeakMap.set(e, id)->ignore
}

// every named container, to be found by its name
let named: array<element> = []

// Registers a container: e holds controls, is called label ("" for none), and show shows it.
let place = (e, label, show) => {
  places->WeakMap.set(e, {label, show})->ignore
  if label != "" {
    named->Array.push(e)
  }
}

// The named containers still in the view, and what each is.
let namedPlaces = () => {
  let live = named->Array.filter(isConnected)
  named->Array.splice(~start=0, ~remove=Array.length(named), ~insert=live)
  live->Array.filterMap(e => places->WeakMap.get(e)->Option.map(p => (e, p)))
}

// The parameters that have a control, and a parameter's controls that are still in the view.
let ids = model => byId(model)->Map.keys->Array.fromIterator
let elements = (model, id) => {
  let m = byId(model)
  let live = m->Map.get(id)->Option.getOr([])->Array.filter(isConnected)
  m->Map.set(id, live)
  live
}

// The control the event happened in, and its parameter, if it was in one.
let controlAt = ev =>
  ev
  ->composedPath
  ->Array.findMap(t => {
    let e: element = Obj.magic(t)
    params->WeakMap.get(e)->Option.map(id => (e, id))
  })

let rec ancestors = e =>
  switch e->parentElement {
  | Some(p) => [p, ...ancestors(p)]
  | None => []
  }

// e's containers that registered, outermost first.
let containers = e => ancestors(e)->Array.filterMap(n => places->WeakMap.get(n))->Array.toReversed

// Where e is, as the names of its containers: "Synth › filter".
let path = e =>
  containers(e)->Array.filterMap(p => p.label == "" ? None : Some(p.label))->Array.join(" › ")

let isShown = e => e->offsetParent->Option.isSome

// Shows e's containers, outermost first.
let show = e => containers(e)->Array.forEach(p => p.show())

// A control of parameter id (one already showing, if any).
let find = (model, id) => {
  let all = elements(model, id)
  all->Array.find(isShown)->Option.orElse(all[0])
}

// A control of parameter id, with its containers shown.
let reach = (model, id) =>
  find(model, id)->Option.map(e => {
    show(e)
    e
  })

// Draws the eye to e (a control, or a panel).
let flash = e => {
  e->removeClass("found")
  requestAnimationFrame(_ => e->addClass("found"))
  setTimeout(() => e->removeClass("found"), 1300)->ignore
}

// The panel e is in.
let panelOf = e => ancestors(e)->Array.find(n => n->classList->hasClass("blk"))
