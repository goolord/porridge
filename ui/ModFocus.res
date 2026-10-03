// Source focus: one modulation source selected (its chip on the Mod page or in the source tray,
// or a control's "show modulators"), whose targets light up in its colour on every page while
// the other controls dim a little. The page tabs count what it moves on each page, and the
// panels' tabs and the voice's flow strip mark where. Escape, or selecting it again, lets it go.
//
// What can light registers itself: the parameter rows (Controls), the envelopes (EnvEditor, by
// their marks: Modulators.envMark) and the flow strip's blocks (VoiceFlow).

open! Web

@send @return(nullable) external closest: (element, string) => option<element> = "closest"

// an element and what it shows (parameters, or envelope marks); counted: a control, which its
// page's tab counts
type entry = {el: element, ids: unit => array<string>, counted: bool}

type state = {
  // the selected source's key (ModMatrix.sources, or ModEdit.pitchEnvKey)
  mutable key: option<string>,
  entries: array<entry>,
  watchers: array<unit => unit>,
  // the stage, which dims, and the pages with their tabs, which count (View)
  mutable stage: option<element>,
  mutable pages: array<(element, element)>,
  // the panels' tabs lit now
  mutable litTabs: array<element>,
  mutable schedule: unit => unit,
}

let states: WeakMap.t<ParamModel.t, state> = WeakMap.make()

// The tab of the panel (Panel) whose body holds e, if it's in one with tabs.
let tabOf = e =>
  e
  ->closest(".pbody")
  ->Option.flatMap(body =>
    body
    ->parentElement
    ->Option.flatMap(panel => {
      let bodies = panel->querySelectorAll(":scope > .pbody")->nodesToArray
      panel->querySelectorAll(":scope > .ptabs > .ptab")->nodesToArray->Array.get(bodies->Array.indexOf(body))
    })
  )

// What source key moves, as the parameters and marks that show it: its routes with an amount.
let targetsOf = (model, key) => {
  let get = id => model->ParamModel.get(id)
  Modulators.from(get, key)
  ->Array.filter(r => model->ParamModel.has(r.amount) && get(r.amount) != 0.)
  ->Array.flatMap(r => r.targets)
  ->Set.fromArray
}

let apply = (model, s) => {
  let targets = s.key->Option.mapOr(Set.make(), targetsOf(model, _))
  let colour = s.key->Option.mapOr("", ModEdit.keyColour)
  s.litTabs->Array.forEach(tab => tab->removeClass("mlit"))
  s.litTabs = []
  // by page: the parameters it moves there
  let counts = s.pages->Array.map(_ => Set.make())
  s.entries->Array.forEach(entry => {
    let moved = s.key == None ? [] : entry.ids()->Array.filter(id => targets->Set.has(id))
    let lit = moved != []
    entry.el->toggleClass("mlit", lit)
    if lit {
      entry.el->style->setProperty("--mc", colour)
      entry.el
      ->tabOf
      ->Option.forEach(tab => {
        tab->addClass("mlit")
        tab->style->setProperty("--mc", colour)
        s.litTabs->Array.push(tab)
      })
      // (a route's amount in the Mod page's list lights, but isn't counted: the page where the
      // parameter has its own control counts it)
      if entry.counted && entry.el->closest(".conn") == None {
        let page = entry.el->closest(".pv-page")
        s.pages->Array.forEachWithIndex(((p, _), i) =>
          if page->Option.mapOr(false, page => page === p) {
            moved->Array.forEach(id => counts->Array.getUnsafe(i)->Set.add(id))
          }
        )
      }
    }
  })
  s.stage->Option.forEach(stage => {
    stage->toggleClass("mfocus", s.key != None)
    stage->style->setProperty("--mc", colour)
  })
  s.pages->Array.forEachWithIndex(((_, tab), i) => {
    let n = counts->Array.getUnsafe(i)->Set.size
    let badge = switch tab->querySelector(".pcount") {
    | Some(b) => b
    | None => el("b", ~cls="pcount", ~parent=tab)
    }
    badge->setTextContent(n > 0 ? "·" ++ Int.toString(n) : "")
    badge->style->setProperty("color", colour)
  })
  s.watchers->Array.forEach(f => f())
}

let stateOf = model =>
  switch states->WeakMap.get(model) {
  | Some(s) => s
  | None =>
    let s = {key: None, entries: [], watchers: [], stage: None, pages: [], litTabs: [], schedule: () => ()}
    states->WeakMap.set(model, s)->ignore
    s.schedule = perFrame(() => apply(model, s))
    // (what it moves may change while it's selected)
    Modulators.watch(model, () =>
      if s.key != None {
        s.schedule()
      }
    )
    s
  }

// The selected source's key.
let current = model => stateOf(model).key

// Lights e while the selected source moves any of ids() (read again each time it changes).
let register = (model, e, ids, ~counted=false) => {
  let s = stateOf(model)
  s.entries->Array.push({el: e, ids, counted})
  if s.key != None {
    s.schedule()
  }
}

// Calls fn whenever the selection or what it moves changes.
let watch = (model, fn) => stateOf(model).watchers->Array.push(fn)

let select = (model, key) => {
  let s = stateOf(model)
  s.key = Some(key)
  apply(model, s)
}

// Lets go of the selection; whether there was one.
let clear = model => {
  let s = stateOf(model)
  let had = s.key != None
  if had {
    s.key = None
    apply(model, s)
  }
  had
}

// Selects source key, or lets go of it if it's the one selected.
let toggle = (model, key) => current(model) == Some(key) ? clear(model)->ignore : select(model, key)

// The stage that dims around the selection, and the pages whose tabs count it.
let attach = (model, ~stage, ~pages) => {
  let s = stateOf(model)
  s.stage = Some(stage)
  s.pages = pages
}
