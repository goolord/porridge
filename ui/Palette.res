// Search (ctrl+K, or "/"): a box over the page that finds any parameter by its control's label,
// its name or the panel it is in ("reso", "lfo 2 rate", "delay wet"), any page, tab or effect,
// and the view's commands ("add chorus", "add per-voice phaser", "init program", "undo"). Typing a
// value after a parameter sets it ("cutoff 800"); "connect LFO 1 to cutoff" makes a connection.
// Choosing a parameter goes to it (Reach: its page, tab, effect or values), flashes it and gives
// it the keyboard, so that the arrow keys nudge it and Enter types a value.

open! Web

@get external textContent: element => string = "textContent"
@send external focusQuietly: (element, @as(json`{"preventScroll": true}`) _) => unit = "focus"
@send external scrollIntoView: (element, @as(json`{"block": "nearest"}`) _) => unit = "scrollIntoView"

// A command of the view's: its name, other words it answers to, its keys, what it does.
type command = {label: string, words: string, keys: string, run: unit => unit}

type item = {
  title: string,
  // where it is, or what it is
  detail: string,
  // a parameter's value, or a command's keys
  value: string,
  // the words it answers to, each list with its weight
  fields: array<(array<string>, float)>,
  // what it is called as a whole, for a closer match
  names: array<string>,
  bonus: float,
  // the parameter it goes to, if it is one
  param: option<string>,
  // what choosing it does; with ~keep, the box stays open (a connection's source was chosen)
  run: unit => unit,
  keep: bool,
}

let rows = 12

type t = {show: unit => unit, isOpen: unit => bool}

let words = s =>
  s
  ->String.toLowerCase
  ->String.replaceRegExp(/[^a-z0-9#%+.-]+/g, " ")
  ->String.trim
  ->String.split(" ")
  ->Array.filter(w => w != "")

// the words that mean the same on different controls (Oatmeal's chorus has a "speed", the LFOs a
// "rate"), which an item answers to as well as its own
let synonyms = [("speed", "rate"), ("amp", "level"), ("depth", "amount"), ("wet", "mix")]
let withSynonyms = ws =>
  Array.concat(
    ws,
    ws->Array.filterMap(w =>
      synonyms->Array.findMap(((a, b)) => w == a ? Some(b) : w == b ? Some(a) : None)
    ),
  )

// How well token matches word: the word itself, its start, or (three letters or more) inside it.
let wordScore = (token, word) =>
  if word == token {
    3.
  } else if word->String.startsWith(token) {
    2.
  } else if String.length(token) >= 3 && word->String.includes(token) {
    1.
  } else {
    0.
  }

// How well an item answers the tokens: every token must match one of its words (None if one
// doesn't), and it's better the more of its title they cover ("amp attack" is the attack rather
// than its curve) and when they are its whole name.
let score = (item, tokens) => {
  let query = tokens->Array.join(" ")
  let each = tokens->Array.map(t =>
    item.fields->Array.reduce(0., (best, (ws, weight)) =>
      Math.max(best, ws->Array.reduce(0., (b, w) => Math.max(b, wordScore(t, w))) * weight)
    )
  )
  if tokens == [] || each->Array.some(s => s == 0.) {
    None
  } else {
    let whole = if item.names->Array.some(n => n == query) {
      4.
    } else if item.names->Array.some(n => n->String.startsWith(query)) {
      1.
    } else {
      0.
    }
    let title = words(item.title)
    let covered = title->Array.filter(w => tokens->Array.some(t => wordScore(t, w) >= 2.))->Array.length
    let coverage = title == [] ? 0. : 3. * Int.toFloat(covered) / Int.toFloat(Array.length(title))
    Some(each->Array.reduce(0., (a, b) => a + b) + whole + coverage + item.bonus)
  }
}

// a typed number, with or without its unit: "800", "-6 dB", "50%"
let looksLikeNumber = text => /^[-+]?(\d+\.?\d*|\.\d+)\s*(%|[a-z]+)?$/i->RegExp.test(text)

let make = (ctx: Ctx.t, stage, ~commands: unit => array<command>) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let root = el("div", ~cls="pal", ~parent=stage)
  let input = el("input", ~cls="pal-q", ~parent=root)
  input->setPlaceholder("Find a control, a page or a command")
  input->setSpellcheck(false)
  let list = el("div", ~cls="pal-list", ~parent=root)
  el(
    "div",
    ~cls="pal-foot",
    ~text="↑ ↓ choose   Enter go   Esc close      a value after a control sets it: cutoff 800      connect LFO 1 to cutoff",
    ~parent=root,
  )->ignore

  let closer = ref(None)
  let isOpen = () => closer.contents->Option.isSome
  let close = () => {
    closer.contents->Option.forEach(stop => stop())
    closer := None
    root->removeClass("on")
    input->blur
  }

  //==============================================================================
  // going to things

  // the effect each effect parameter belongs to, which its editor shows once it is open
  let effectOf =
    [FxRack.oatmealDistortion, ...FxRack.all]
    ->Array.flatMap(e => FxRack.params(e)->Array.map(id => (id, e)))
    ->Map.fromArray
  // each parameter's name as a connection's target, which says what it belongs to: "osc 2 transpose"
  let targetNames = ModMatrix.targets->Array.filterMap(t =>
    switch t.law {
    | Knob(id) => Some((id, t.label))
    | _ => None
    }
  )->Map.fromArray
  // (a slot's parameters' names say which slot: "flanger rate (FX 3)")
  let targetNameOf = id => PorridgeParams.isSlotParam(id) ? Some(SlotParams.slotParamLabel(id)) : targetNames->Map.get(id)

  let flashWith = (e, text) => {
    Reach.flash(e)
    ctx.status->Status.show(text)
  }

  // Goes to parameter id's control, flashes it and gives it the keys; or, while it is hidden (it
  // does nothing with the current settings), flashes its panel.
  let reach = id => {
    let def = model->ParamModel.def(id)
    effectOf->Map.get(id)->Option.forEach(ctx.openEffect)
    switch Reach.reach(model, id) {
    | Some(e) if Reach.isShown(e) =>
      e->focusQuietly
      e->scrollIntoView
      flashWith(e, def.longText(get(id)) ++ ": the arrow keys nudge it (shift fine, ctrl coarse), Enter types a value")
    | Some(e) =>
      e->Reach.panelOf->Option.forEach(p => flashWith(p, `${def.name} is hidden: it does nothing with the current settings`))
    | None => ctx.toast(`${def.name} has no control here`)
    }
  }

  let showPlace = (e, p: Reach.place) => {
    Reach.show(e)
    p.show()
    e->Reach.panelOf->Option.forEach(Reach.flash)
  }

  //==============================================================================
  // what it finds, made as the box opens (controls are made as their pages and effects first
  // show, and the effects in use change)

  let item = (~title, ~detail, ~value="", ~also="", ~bonus=0., ~keep=false, run) => {
    title,
    detail,
    value,
    fields: [(words(title ++ " " ++ also), 1.), (words(detail), 0.8)],
    names: [title->String.toLowerCase],
    bonus,
    param: None,
    run,
    keep,
  }

  let rackNow = () => (FxRack.read(get), FxRack.readLane(get))
  let effectLabel = ((rack, lane), e) =>
    if e == FxRack.oatmealDistortion {
      "distortion"
    } else if FxRack.holds(lane, e) {
      "per-voice " ++ FxRack.label(lane, e)
    } else {
      FxRack.label(rack, e)
    }
  let inUse = ((rack, lane), e) => e == FxRack.oatmealDistortion || FxRack.holds(rack, e) || FxRack.holds(lane, e)

  let labelOf = (def: ParamDefs.t, e) =>
    switch e->querySelector(":scope > .l, :scope > b + span")->Option.map(textContent) {
    // (a label of a letter or two, "x" or "3", says little out of its panel)
    | Some(l) if String.length(l) >= 4 => l
    | _ => def.name
    }

  let paramItem = (def: ParamDefs.t, ~title, ~detail) => {
    title,
    detail,
    value: def.shortText(get(def.id)),
    fields: [
      (title, 1.),
      (def.name, 1.),
      (ParamInfo.renamed(def.id)->Option.getOr(""), 0.9),
      (targetNameOf(def.id)->Option.getOr(""), 0.9),
      (detail, 0.8),
    ]->Array.map(((text, weight)) => (withSynonyms(words(text)), weight)),
    names: [title->String.toLowerCase, def.name->String.toLowerCase],
    bonus: 0.,
    param: Some(def.id),
    run: () => reach(def.id),
    keep: false,
  }

  // every parameter with a control (an effect's while it is in use), by its label and where it
  // is; by its name where two would read the same (the two oscillators' envelopes' "decay 2")
  let params = () => {
    let fx = rackNow()
    let found =
      model.defs
      ->Map.values
      ->Array.fromIterator
      ->Array.filterMap(def => {
        let e = Reach.find(model, def.id)
        switch (effectOf->Map.get(def.id), e) {
        | (Some(fxe), _) if !inUse(fx, fxe) => None
        | (Some(fxe), _) => Some((def, e->Option.mapOr(def.name, labelOf(def, _)), "FX › " ++ effectLabel(fx, fxe)))
        | (None, Some(e)) => Some((def, labelOf(def, e), Reach.path(e)))
        | (None, None) => None
        }
      })
    let key = (title, detail) => title ++ " in " ++ detail
    let seen = Map.make()
    found->Array.forEach(((_, title, detail)) =>
      seen->Map.set(key(title, detail), seen->Map.get(key(title, detail))->Option.getOr(0) + 1)
    )
    found->Array.map(((def: ParamDefs.t, title, detail)) =>
      paramItem(def, ~title=seen->Map.get(key(title, detail)) == Some(1) ? title : def.name, ~detail)
    )
  }

  // pages, tabs and panels, and the effects in use
  let places = () => {
    let fx = rackNow()
    let (rack, lane) = fx
    Array.concat(
      Reach.namedPlaces()->Array.map(((e, p)) => {
        let path = Reach.path(e)
        item(~title=p.label, ~detail=path == "" ? "page" : path, () => showPlace(e, p))
      }),
      [FxRack.oatmealDistortion, ...lane, ...rack]->Array.map(e =>
        item(~title=effectLabel(fx, e), ~detail="FX", ~also="effect", () => ctx.openEffect(e))
      ),
    )
  }

  // adding an effect to the end of the whole sound, or per-voice
  let addCommands = () => {
    let (rack, lane) = rackNow()
    let added = (e, name) => {
      model->ParamModel.nameStep("add " ++ name)
      ctx.openEffect(e)
    }
    Array.concat(
      FxRack.addable(rack, ~lane)->Array.filterMap(kind =>
        FxRack.free(rack, ~lane, kind)->Option.map(e => {
          let name = FxRack.kindName(kind)
          item(~title="add " ++ name, ~detail="to the whole sound", ~also="effect", () => {
            VoiceLane.setAll(model, FxRack.values(get, [...rack, e]))
            let e = FxRack.placed([...rack, e])->Array.getUnsafe(Array.length(rack))
            VoiceLane.switchOn(model, e)
            added(e, name)
          })
        })
      ),
      FxRack.addable(rack, ~lane, ~forLane=true)->Array.map(kind => {
        let name = FxRack.kindName(kind)
        item(~title="add per-voice " ++ name, ~detail="each voice runs its own", ~also="effect", () =>
          VoiceLane.add(model, kind)->Option.forEach(e => added(e, "per-voice " ++ name))
        )
      }),
    )
  }

  let viewCommands = () =>
    commands()->Array.map(c => item(~title=c.label, ~detail="command", ~value=c.keys, ~also=c.words, ~bonus=0.5, c.run))

  // "cutoff 800": a value (the last word or three) after words that find a parameter, which it
  // parses as
  let valueItems = (params, raw) => {
    let parts = raw->String.trim->String.splitByRegExp(/\s+/)->Array.filterMap(x => x)
    let n = Array.length(parts)
    Array.fromInitializer(~length=Math.Int.max(0, Math.Int.min(3, n - 1)), i => i + 1)->Array.flatMap(k => {
      let text = parts->Array.slice(~start=n - k)->Array.join(" ")
      let tokens = words(parts->Array.slice(~start=0, ~end=n - k)->Array.join(" "))
      params->Array.filterMap(it =>
        switch (it.param, score(it, tokens)) {
        | (Some(id), Some(s)) =>
          let def = model->ParamModel.def(id)
          let named = def.names->Option.mapOr(false, ns => ns->Array.some(n => n->String.toLowerCase == text->String.toLowerCase))
          (looksLikeNumber(text) || named ? def.parse(text) : None)
          // (a value past the end of the parameter's range, "drift 800", is no answer: what it
          // reads at the end isn't what was typed)
          ->Option.filter(x => {
            let typed = ParamDefs.firstNumber(text)
            let shown = ParamDefs.firstNumber(def.shortText(x))
            let atEnd = x <= def.min || x >= def.max
            Float.isFinite(x) && !(atEnd && Math.abs(typed - shown) > 0.01 * Math.max(1., Math.abs(typed)))
          })
          ->Option.map(x => {
            ...it,
            title: `${it.title} → ${def.shortText(x)}`,
            value: "set",
            // (a number after a name is more likely a value than part of the name)
            bonus: s + 1.5,
            run: () => {
              model->ParamModel.gestureSet(id, x)
              reach(id)
            },
          })
        | _ => None
        }
      )
    })
  }

  // "connect lfo 1 to cutoff": the sources and the targets the words find; with no target yet,
  // the sources, which choosing completes in the box
  let setQuery = ref(_ => ())
  let connectItems = raw => {
    let lower = raw->String.toLowerCase->String.trim
    if !(lower->String.startsWith("connect")) {
      []
    } else {
      let rest = lower->String.slice(~start=7)->String.trim
      let (sourceText, targetText) = switch rest->String.splitByRegExp(/\s+(?:to|>|->|→)\s*/) {
      | [Some(s), Some(t)] => (s, Some(t))
      | _ => (rest, None)
      }
      // (the first of each list is "none"; label "" leaves one out)
      let ranked = (all, text, label) => {
        let tokens = words(text)
        all
        ->Array.filterMapWithIndex((x, i) =>
          i == 0 || label(x) == ""
            ? None
            : (tokens == [] ? Some(0.) : score(item(~title=label(x), ~detail="", () => ()), tokens))->Option.map(s => (s, i, x))
        )
        ->Array.toSorted(((a, _, _), (b, _, _)) => b - a)
      }
      let sources = ranked(ModMatrix.sources, sourceText, (s: ModMatrix.source) => s.label)
      switch targetText {
      | None =>
        sources
        ->Array.slice(~start=0, ~end=rows)
        ->Array.map(((s, _, src)) =>
          item(~title=`connect ${src.label} to …`, ~detail="then type a target", ~bonus=s, ~keep=true, () =>
            setQuery.contents(`connect ${src.label} to `)
          )
        )
      | Some(t) =>
        let named = ModMatrix.targets->Array.mapWithIndex((x, i) => x.group == "slot" ? {...x, label: SlotParams.targetLabel(get, i)} : x)
        let targets = ranked(named, t, (t: ModMatrix.target) => t.group == "retired" ? "" : t.label)
        sources
        ->Array.slice(~start=0, ~end=3)
        ->Array.flatMap(((ss, si, src)) =>
          targets
          ->Array.slice(~start=0, ~end=5)
          ->Array.map(((ts, ti, tgt)) =>
            item(~title=`connect ${src.label} → ${tgt.label}`, ~detail="a new connection", ~bonus=ss + ts, () =>
              switch ModEdit.connect(model, si, ti, ~amount=ModEdit.defaultAmount) {
              | Ok(_) =>
                model->ParamModel.nameStep(`connect ${src.label} to ${tgt.label}`)
                ctx.toast(`Connected ${src.label} to ${tgt.label}`)
                switch tgt.law {
                | ModMatrix.Knob(id) => reach(id)
                | ModMatrix.Slot(_, _) => SlotParams.targetParam(get, ti)->Option.forEach(reach)
                | _ => ctx.openPage(#mod)
                }
              | Error(e) => ctx.toast(`Couldn't connect ${src.label} to ${tgt.label}: ${e}`)
              }
            )
          )
        )
      }
    }
  }

  //==============================================================================
  // the box

  let index = ref([])
  let found = ref([])
  let selected = ref(0)
  let choose = ref(_ => ())

  let markSelected = () =>
    list
    ->querySelectorAll(".pal-row")
    ->nodesToArray
    ->Array.forEachWithIndex((row, i) => {
      row->toggleClass("on", i == selected.contents)
      if i == selected.contents {
        row->scrollIntoView
      }
    })

  let render = () => {
    list->setTextContent("")
    found.contents->Array.forEachWithIndex((it, i) => {
      let row = el("div", ~cls="pal-row", ~parent=list)
      el("span", ~cls="t", ~text=it.title, ~parent=row)->ignore
      el("span", ~cls="d", ~text=it.detail, ~parent=row)->ignore
      el("span", ~cls="v", ~text=it.value, ~parent=row)->ignore
      row->onMouse(#mousemove, _ =>
        if selected.contents != i {
          selected := i
          markSelected()
        }
      )
      row->onPointer(#pointerdown, ev => {
        ev->preventDefault
        choose.contents(it)
      })
    })
    if found.contents == [] {
      el("div", ~cls="pal-none", ~text="Nothing by that name", ~parent=list)->ignore
    }
    markSelected()
  }

  let search = () => {
    let raw = input->value
    let tokens = words(raw)
    let ranked = if tokens == [] {
      // with nothing typed: the pages and the commands
      index.contents->Array.filter(it => it.param->Option.isNone && (it.detail == "page" || it.detail == "command"))
    } else {
      let params = index.contents->Array.filter(it => it.param->Option.isSome)
      Array.concat(
        index.contents->Array.filterMap(it => score(it, tokens)->Option.map(s => (s, it))),
        Array.concat(valueItems(params, raw), connectItems(raw))->Array.map(it => (it.bonus, it)),
      )
      ->Array.toSorted(((a, x), (b, y)) => a == b ? Int.toFloat(String.length(x.title) - String.length(y.title)) : b - a)
      ->Array.map(((_, it)) => it)
    }
    found := ranked->Array.slice(~start=0, ~end=rows)
    selected := 0
    render()
  }

  choose :=
    (
      it => {
        if !it.keep {
          close()
        }
        it.run()
      }
    )
  setQuery :=
    (
      text => {
        input->setValue(text)
        input->focusQuietly
        search()
      }
    )

  let open_ = () =>
    if !isOpen() {
      ctx.menu->Menu.close
      index := Array.concat(Array.concat(params(), places()), Array.concat(addCommands(), viewCommands()))
      root->addClass("on")
      input->setValue("")
      input->focusQuietly
      search()
      closer := Some(onPressOutside([root], close))
    }

  input->onEvent(#input, _ => search())
  // the keys stay in the box (the host may otherwise take them as shortcuts)
  input->onKeyDown(k => {
    k->stopPropagation
    let move = d => {
      k->preventDefault
      let n = Array.length(found.contents)
      if n > 0 {
        selected := mod(selected.contents + d + n, n)
        markSelected()
      }
    }
    switch k->key {
    | "ArrowDown" => move(1)
    | "ArrowUp" => move(-1)
    | "k" if k->commandKey =>
      k->preventDefault
      input->select
    | "Enter" =>
      k->preventDefault
      found.contents[selected.contents]->Option.forEach(choose.contents)
    | "Escape" => close()
    | _ => ()
    }
  })

  {show: open_, isOpen}
}
