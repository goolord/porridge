// The random patches' drawer: four patches at a time (PatchGen.res), each area as wild as its
// knob above the cards says, and variations of them or of the program as it is.
//
//  - Generate makes four patches of a kind (or of four kinds). Clicking a card plays it on the
//    synth at its kind's note; the program isn't changed until Keep, and closing the drawer puts
//    back what was playing before (unless the card was edited meanwhile, which keeps the edits).
//    Keep can be undone while the drawer is open.
//  - Vary makes four variations of a card, a little, some or a lot apart, which can be varied in
//    turn; the row above the cards goes back. "Vary program" does the same to the program as it
//    is, whatever made it.
//  - The wildness knobs say how far each area may go from the usual: the oscillators, the
//    filter, the envelopes, the modulation and the effects (saved with the settings).
//  - The locks keep areas of what is playing (the chosen card, or else the program) while the
//    rest is made again or varied.
//  - Every card plays at the same loudness: the first time it plays (or is kept), its note is
//    played silently while the plugin meters it (dsp/Synth.cmajor's levelOut: K-weighted, as a
//    loudness meter hears it), and its output gain is set from what was heard. Variations of
//    the program are set to the program's own loudness, measured the same way. Without a meter
//    (the browser preview) the output gain is PatchGen's estimate.

open! Web

@get external textContent: element => string = "textContent"

let slotCount = 4
let amounts = [("a little", 0.15), ("some", 0.35), ("a lot", 0.7)]
// the rows of cards kept to go back to
let maxRows = 8
let settingsKey = "random"

type card = {
  root: element,
  title: element,
  badge: element,
  lines: array<element>,
  play: element,
  keep: element,
  vary: element,
}

// A card's patch: its values, the program it goes into (Init, or the program it varies, for its
// shapes, tuning and impulses), its kind and name, and where it came from (for the program's
// description); the level it is to play at (dB at the output, as a loudness meter hears it: the
// variations of a program play as loud as it does), and whether its output gain has been set from
// a measurement of how loud it plays (until then it is the estimate's).
type patch = {
  values: Bank.values,
  base: Preset.t,
  kind: PatchGen.kind,
  name: string,
  origin: string,
  target: option<float>,
  measured: bool,
}

// A row of cards: new patches, or variations of one.
type generation = {label: string, patches: array<patch>}

type t = {
  show: unit => unit,
  hide: unit => unit,
  isOpen: unit => bool,
  dispose: unit => unit,
}

// a padlock, for the locks
let lockIcon: Icons.icon = {
  width: 12.,
  marks: [Line("M3.5 7.5 V5 A2.5 2.5 0 0 1 8.5 5 V7.5"), Fill("M2 7.5 H10 V14 H2 Z")],
}

// how a wildness reads
let wildWord = w =>
  if w < 0.12 {
    "tame"
  } else if w < 0.38 {
    "mild"
  } else if w < 0.62 {
    "bold"
  } else if w < 0.88 {
    "wild"
  } else {
    "feral"
  }

// what each area's knob does, from tame to wild
let wildHelp = (a: PatchGen.area) =>
  switch a {
  | #osc => "a wave or two, a little unison; wilder: sync, FM, PM, ring and AM at odd ratios, noise, roughness, wide unison"
  | #filter => "a lowpass with a modest envelope; wilder: formants, combs and the rest, more resonance, deeper sweeps, a second filter"
  | #env => "envelopes as the kind of patch has them; wilder: any times, two-stage decays, pitch sweeps"
  | #mod => "none at all; then vibrato and gentle note-to-note variation; wilder: wobbles, blips, sample & hold, growls"
  | #fx => "dry; then a space, an echo or a chorus; wilder: more of the rack, drive, frequency shifting, odd rooms"
  }

let make = (ctx: Ctx.t, stage, settings: Settings.t): t => {
  let programs = ctx.programs
  let status = ctx.status

  let root = el("div", ~cls="rd", ~parent=stage)
  let head = el("div", ~cls="rd-head", ~parent=root)
  let knobs = el("div", ~cls="rd-knobs", ~parent=root)
  let crumbs = el("div", ~cls="rd-crumbs", ~parent=root)
  let row = el("div", ~cls="rd-cards", ~parent=root)

  // a button whose status text is title() (its click is wired at the end)
  let button = (parent, text, title) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    status->Status.hover(b, title)
    b
  }

  //==============================================================================
  // state

  let opened = ref(false)
  let generations: array<generation> = []
  let locks: Set.t<PatchGen.area> = Set.make()
  let wild = ref(PatchGen.defaultWildness)
  let kind: ref<option<PatchGen.kind>> = ref(None)
  // the card being played, in the shown generation
  let chosen = ref(None)
  // the program as it was before a card was played on the synth, and its number
  let original: ref<option<(Preset.t, int)>> = ref(None)
  let edited = ref(false)
  // the meta a played card goes in with, for keeping it when it has been edited
  let triedMeta = ref(None)
  let applying = ref(false)
  // what Keep replaced, to undo it
  let undo: ref<option<(Preset.t, int)>> = ref(None)
  let keptSlot = ref(None)
  // the card being measured, before it plays
  let measuring = ref(None)
  let noteTimer = ref(None)
  let playingNote = ref(None)
  let init = Lazy.make(() => Preset.make("Init"))

  let shown = () => generations->Array.at(-1)
  let patchAt = slot => shown()->Option.flatMap(gen => gen.patches[slot])

  // the knobs and the kind, as the settings keep them
  let load = () =>
    switch settings->Settings.savedValue(settingsKey) {
    | Some(Object(saved)) =>
      wild := PatchGen.areas->Array.reduce(PatchGen.defaultWildness, (w, a) =>
        switch saved->Dict.get(PatchGen.areaShort(a)) {
        | Some(Number(x)) if Float.isFinite(x) => PatchGen.withWild(w, a, Math.max(0., Math.min(1., x)))
        | _ => w
        }
      )
      kind :=
        switch saved->Dict.get("kind") {
        | Some(String(k)) => PatchGen.kinds->Array.find(x => PatchGen.kindName(x) == k)
        | _ => None
        }
    | _ => ()
    }
  let saveTimer = ref(None)
  let rec saveSoon = () => {
    saveTimer.contents->Option.forEach(clearTimeout)
    saveTimer := Some(setTimeout(save, 500))
  }
  and save = () => {
    saveTimer.contents->Option.forEach(clearTimeout)
    saveTimer := None
    let w = wild.contents
    settings->Settings.save(
      settingsKey,
      Object(
        Dict.fromArray([
          ...PatchGen.areas->Array.map(a => (PatchGen.areaShort(a), JSON.Number(PatchGen.wildOf(w, a)))),
          ("kind", String(kind.contents->Option.mapOr("any", PatchGen.kindName))),
        ]),
      ),
    )
  }

  //==============================================================================
  // the header

  el("div", ~cls="rd-title", ~text="random patches", ~parent=head)->ignore
  let generate = button(head, "generate", () =>
    locks->Set.size > 0
      ? "Four new patches, keeping the playing patch's " ++ PatchGen.areas->Array.filter(a => locks->Set.has(a))->Array.map(PatchGen.areaShort)->Array.join(", ")
      : "Four new patches, each part as wild as its knob says"
  )
  generate->addClass("go")
  let kindButton = button(head, "", () => "The kind of patch: its envelopes, its tone and the note it plays at; any makes four kinds")
  let varyProgram = button(head, "vary program ▾", () =>
    "Four variations of the program as it is (whatever made it), a little, some or a lot apart"
  )
  el("div", ~cls="spacer", ~parent=head)->ignore
  let lockLabel = el("div", ~cls="rd-locklabel", ~text="lock", ~parent=head)
  status->Status.hover(lockLabel, () => "Keep parts of the playing patch while making or varying the rest")
  let lockRow = el("div", ~cls="rd-locks", ~parent=head)
  let lockChips = PatchGen.areas->Array.map(a => {
    let chip = el("div", ~cls="rd-lock", ~parent=lockRow)
    chip->appendChild(Icons.render(lockIcon))
    el("span", ~text=PatchGen.areaShort(a), ~parent=chip)->ignore
    status->Status.hover(chip, () =>
      `Keep the playing patch's ${PatchGen.areaName(a)} (the chosen card's, or the program's) when making or varying the rest`
    )
    (a, chip)
  })
  let undoButton = button(head, "undo keep", () => "Put the program back as it was before Keep")
  let close = button(head, "×", () => "Close (a card being played goes back to the program as it was)")
  close->addClass("icon")

  //==============================================================================
  // the wildness knobs

  el("div", ~cls="rd-klabel", ~text="wildness", ~parent=knobs)->ignore
  let knobControls = PatchGen.areas->Array.map(a => {
    let box = el("div", ~cls="rd-knob", ~parent=knobs)
    el("span", ~cls="rd-kname", ~text=PatchGen.areaShort(a), ~parent=box)->ignore
    let track = el("div", ~cls="rd-track", ~parent=box)
    let fill = el("div", ~cls="rd-fill", ~parent=track)
    let word = el("span", ~cls="rd-kword", ~parent=box)
    let render = () => {
      let w = PatchGen.wildOf(wild.contents, a)
      fill->setStyle("width", Float.toString(100. * w) ++ "%")
      word->setTextContent(wildWord(w))
    }
    let name = PatchGen.areaName(a)
    let text = () => {
      let w = PatchGen.wildOf(wild.contents, a)
      `${String.charAt(name, 0)->String.toUpperCase}${String.slice(name, ~start=1)} ${Float.toString(Math.round(100. * w))}% wild. Tame: ${wildHelp(a)}. Drag, scroll, or double-click for the default`
    }
    let live = status->Status.live(box, text)
    let set = x => {
      wild := PatchGen.withWild(wild.contents, a, Math.max(0., Math.min(1., x)))
      render()
      live.refresh()
    }
    let fromPointer = ev => {
      let (x, _) = pointerFraction(track, ev)
      set(x)
    }
    track->onPointer(#pointerdown, ev => {
      fromPointer(ev)
      live.setDragging(true)
      track->Controls.capturePointer(ev, ~onMove=fromPointer, ~onUp=() => {
        live.setDragging(false)
        save()
      })
    })
    box->onWheel(ev => {
      ev->preventDefault
      set(PatchGen.wildOf(wild.contents, a) + (ev->deltaY < 0. ? 0.05 : -0.05))
      saveSoon()
    })
    box->onMouse(#dblclick, _ => {
      set(PatchGen.wildOf(PatchGen.defaultWildness, a))
      save()
    })
    render
  })

  //==============================================================================
  // the cards

  let cards = Array.fromInitializer(~length=slotCount, _ => {
    let root = el("div", ~cls="rd-card", ~parent=row)
    let top = el("div", ~cls="rd-ctop", ~parent=root)
    let title = el("div", ~cls="rd-ctitle", ~parent=top)
    let badge = el("div", ~cls="rd-badge", ~parent=top)
    let desc = el("div", ~cls="rd-desc", ~parent=root)
    let lines = PatchGen.areas->Array.map(a => {
      let line = el("div", ~cls="rd-line", ~parent=desc)
      el("span", ~cls="rd-area", ~text=PatchGen.areaShort(a), ~parent=line)->ignore
      let what = el("span", ~cls="rd-what", ~parent=line)
      // (the whole of a line cut short)
      status->Status.hover(line, () => `${PatchGen.areaName(a)}: ${what->textContent}`)
      what
    })
    let buttons = el("div", ~cls="rd-cbtns", ~parent=root)
    let card = {
      root,
      title,
      badge,
      lines,
      play: el("button", ~cls="btn", ~text="▶ play", ~parent=buttons),
      keep: el("button", ~cls="btn", ~text="keep", ~parent=buttons),
      vary: el("button", ~cls="btn", ~text="vary ▾", ~parent=buttons),
    }
    status->Status.hover(card.play, () => "Play this patch on the synth; the program isn't changed until Keep")
    status->Status.hover(card.keep, () => "Put this patch in the current program")
    status->Status.hover(card.vary, () => "Four variations of this patch, a little, some or a lot apart")
    card
  })

  //==============================================================================
  // drawing

  let renderCard = slot => {
    let card = cards->Array.getUnsafe(slot)
    switch patchAt(slot) {
    | Some(p) =>
      card.root->removeClass("empty")
      card.title->setTextContent(p.name)
      card.root->toggleClass("live", chosen.contents == Some(slot) && original.contents != None)
      card.root->toggleClass("kept", keptSlot.contents == Some(slot))
      card.badge->setTextContent(
        measuring.contents == Some(slot)
          ? "measuring"
          : keptSlot.contents == Some(slot)
          ? "kept"
          : chosen.contents == Some(slot) && original.contents != None
          ? "playing"
          : "",
      )
      let note = PatchGen.profile(p.kind).note
      PatchGen.describe(p.values, ~note)->Array.forEachWithIndex(((_, text), i) =>
        card.lines[i]->Option.forEach(line => line->setTextContent(text))
      )
    | None =>
      card.root->addClass("empty")
      card.title->setTextContent("")
      card.badge->setTextContent("")
      card.lines->Array.forEach(line => line->setTextContent(""))
    }
  }

  let rec renderCrumbs = () => {
    crumbs->setTextContent("")
    crumbs->toggleClass("on", Array.length(generations) > 1)
    generations->Array.forEachWithIndex((gen, i) => {
      if i > 0 {
        el("span", ~cls="rd-sep", ~text="›", ~parent=crumbs)->ignore
      }
      let last = i == Array.length(generations) - 1
      let c = el("span", ~cls=last ? "rd-crumb on" : "rd-crumb", ~text=gen.label, ~parent=crumbs)
      if !last {
        c->onMouse(#click, _ => {
          // back to that row
          generations->Array.splice(~start=i + 1, ~remove=Array.length(generations) - i - 1, ~insert=[])
          chosen := None
          keptSlot := None
          renderAll()
        })
      }
    })
  }

  and renderHead = () => {
    kindButton->setTextContent(kind.contents->Option.mapOr("any kind", PatchGen.kindName) ++ " ▾")
    undoButton->toggleClass("hidden", undo.contents == None)
    lockChips->Array.forEach(((a, chip)) => chip->toggleClass("on", locks->Set.has(a)))
    knobControls->Array.forEach(render => render())
  }

  and renderAll = () => {
    renderHead()
    renderCrumbs()
    Array.fromInitializer(~length=slotCount, i => i)->Array.forEach(renderCard)
  }

  //==============================================================================
  // playing cards on the synth

  let noteOff = () => {
    noteTimer.contents->Option.forEach(clearTimeout)
    noteTimer := None
    playingNote.contents->Option.forEach(note => Wheels.send(ctx, 0x80, note, 0))
    playingNote := None
  }

  // a card's note, long enough to hear its attack and some of its decay
  let playNote = (p: patch) => {
    noteOff()
    let note = PatchGen.profile(p.kind).note
    Wheels.send(ctx, 0x90, note, 100)
    playingNote := Some(note)
    let get = id => p.values->Map.get(id)->Option.getOr(0.)
    let ms = get("Attack") + Math.min(1200., get("Decay2")) + 300.
    noteTimer := Some(setTimeout(noteOff, Float.toInt(Math.max(600., Math.min(2500., ms)))))
  }

  // A card's patch as a program: the program it was made from with its values, named for it.
  let presetOf = (p: patch): Preset.t => {
    let note = PatchGen.profile(p.kind).note
    let made = PatchGen.describe(p.values, ~note)->Array.map(((_, text)) => text)->Array.join("; ")
    {
      ...p.base,
      values: PatchGen.copy(p.values),
      tables: Preset.copyTables(p.base.tables),
      meta: {
        ...p.base.meta,
        name: p.name->String.slice(~start=0, ~end=Preset.maxNameLength),
        author: ProgramStore.meta(programs).author,
        category: p.base === Lazy.get(init) ? PatchGen.kindName(p.kind) : p.base.meta.category,
        tags: Array.concat(p.base.meta.tags->Array.filter(t => t != "random"), ["random"]),
        description: `${p.origin}: ${made}.`,
      },
    }
  }

  let apply = preset => {
    applying := true
    programs->ProgramStore.preview(preset)
    applying := false
  }

  //==============================================================================
  // measuring how loud a card plays

  // The meter's readings (dsp/Synth.cmajor's levelOut: the output's K-weighted power before the
  // output gain, every 512 frames) while a measurement asks for them, and whether the plugin
  // gives any (the browser preview doesn't, nor a host that isn't running the plugin).
  let readings: array<float> = []
  let meterWorks = ref(true)
  ctx.pc->PatchConnection.addEndpointListener("levelOut", j =>
    switch j {
    | Number(x) => readings->Array.push(x)
    | _ => ()
    }
  )
  // the measurement under way, if any (a newer one, a new row or closing the drawer stops it,
  // and puts back what was playing: the measured patch was on, silent)
  let probe = ref(0)
  let probing = ref(false)
  let stopProbe = () => {
    probe := probe.contents + 1
    measuring := None
    if probing.contents {
      probing := false
      noteOff()
      ctx.pc->PatchConnection.sendEventOrValue("levelRequest", 0)
      original.contents->Option.forEach(((before, index)) =>
        if index == programs.current {
          apply(before)
        }
      )
    }
  }
  // (readings of 512 frames are about 11 ms: 27 of them make 300 ms)
  let windowReadings = 27
  let db = p => 10. * Math.log10(Math.max(p, 1e-12))

  // how long a patch's note is measured for: past its attack, within reason
  let probeMs = (values: Bank.values) =>
    Math.max(450., Math.min(700., values->Map.get("Attack")->Option.getOr(5.) + 350.))

  // Plays a program's note silently (with the output gain at 0, after clearing what was still
  // sounding) and gives how loud it was: the mean power of its loudest 300 ms and its loudest
  // reading, dB before the output gain; None if the meter gave too little. Nothing comes if
  // something else starts meanwhile.
  let measure = (preset: Preset.t, ~note, ~ms, done) => {
    stopProbe()
    let token = probe.contents
    probing := true
    noteOff()
    let silent = PatchGen.copy(preset.values)
    silent->Map.set("Gain", 0.)
    apply({...preset, values: silent})
    programs->ProgramStore.panic
    readings->Array.splice(~start=0, ~remove=Array.length(readings), ~insert=[])
    ctx.pc->PatchConnection.sendEventOrValue("levelRequest", Float.toInt(ms / 10.) + 20)
    let later = (wait, f) => setTimeout(() => probe.contents == token ? f() : (), wait)->ignore
    later(40, () => {
      Wheels.send(ctx, 0x90, note, 100)
      playingNote := Some(note)
      later(Float.toInt(ms), () => {
        probing := false
        noteOff()
        ctx.pc->PatchConnection.sendEventOrValue("levelRequest", 0)
        let n = Array.length(readings)
        if n < 10 {
          meterWorks := false
          done(None)
        } else {
          let w = Math.Int.min(windowReadings, n)
          let sum = ref(readings->Array.slice(~start=0, ~end=w)->Array.reduce(0., (s, x) => s + x))
          let best = ref(sum.contents)
          for i in w to n - 1 {
            sum := sum.contents + readings->Array.getUnsafe(i) - readings->Array.getUnsafe(i - w)
            best := Math.max(best.contents, sum.contents)
          }
          done(Some((db(best.contents / Int.toFloat(w)), db(readings->Array.reduce(0., Math.max)))))
        }
      })
    })
  }

  // How loud a patch's whole note plays (dB before the output gain) and its loudest moment, from
  // a measurement of its first `ms`: the estimate adds what comes later (a slow attack's loudest
  // moments are past the measurement), never less.
  let wholeNote = (values, ~kind, ~ms, (level, loudest)) => {
    let note = PatchGen.profile(kind).note
    let (later, laterLoudest) = PatchGen.simulated(values, ~note)
    let (early, earlyLoudest) = PatchGen.simulated(values, ~note, ~within=ms)
    (level + Math.max(0., later - early), loudest + Math.max(0., laterLoudest - earlyLoudest))
  }

  // Sets a card's output gain from a measurement of how loud it plays, the first time (unless it
  // has no level to keep to, or there's no meter), then goes on.
  let withMeasured = (slot, next) =>
    switch (shown(), patchAt(slot)) {
    | (Some(gen), Some(p)) if !p.measured && p.target != None && meterWorks.contents =>
      if original.contents == None {
        original := Some((ProgramStore.captureCurrent(programs), programs.current))
      }
      let ms = probeMs(p.values)
      measure(presetOf(p), ~note=PatchGen.profile(p.kind).note, ~ms, result => {
        measuring := None
        switch (result, p.target) {
        | (Some(heard), Some(target)) =>
          let (level, loudest) = wholeNote(p.values, ~kind=p.kind, ~ms, heard)
          let values = PatchGen.copy(p.values)
          let gainDb = Math.min(target - level, PatchGen.ceilingDb - loudest)
          values->Map.set("Gain", Math.min(2., PatchGen.ampOfDb(gainDb)))
          if gen.patches[slot]->Option.mapOr(false, q => q === p) {
            gen.patches->Array.setUnsafe(slot, {...p, values, measured: true})
          }
        | _ => ()
        }
        // (the measured note's tail goes, before the card plays)
        programs->ProgramStore.panic
        setTimeout(next, 30)->ignore
      })
      measuring := Some(slot)
      renderAll()
    | _ => next()
    }

  let tryCard = slot =>
    patchAt(slot)->Option.forEach(_ => {
      if original.contents == None {
        original := Some((ProgramStore.captureCurrent(programs), programs.current))
      }
      // (a card played and edited goes on with the edits)
      let fresh = chosen.contents != Some(slot) || !edited.contents
      chosen := Some(slot)
      keptSlot := None
      renderAll()
      let play = () =>
        patchAt(slot)->Option.forEach(p => {
          if fresh {
            let preset = presetOf(p)
            apply(preset)
            triedMeta := Some(preset.meta)
            edited := false
          }
          playNote(p)
          renderAll()
        })
      fresh ? withMeasured(slot, play) : play()
    })

  // Puts the program back as it was before a card was played, unless the card has been
  // edited since, which keeps it with the edits.
  let settle = () => {
    noteOff()
    switch original.contents {
    | Some((before, index)) if index == programs.current =>
      if edited.contents {
        let edits = ProgramStore.captureCurrent(programs)
        programs->ProgramStore.loadIntoCurrent({...edits, meta: triedMeta.contents->Option.getOr(edits.meta)})
        ctx.toast(`Kept your edited patch in program ${ProgramStore.number(programs.current)}`)
      } else {
        applying := true
        programs->ProgramStore.restore(before)
        applying := false
      }
    | _ => ()
    }
    original := None
    edited := false
  }

  let keepNow = slot =>
    patchAt(slot)->Option.forEach(p => {
      noteOff()
      let before = switch original.contents {
      | Some((b, index)) if index == programs.current => b
      | _ => ProgramStore.captureCurrent(programs)
      }
      let preset =
        chosen.contents == Some(slot) && edited.contents
          ? {...ProgramStore.captureCurrent(programs), meta: presetOf(p).meta}
          : presetOf(p)
      programs->ProgramStore.loadIntoCurrent(preset)
      undo := Some((before, programs.current))
      original := None
      edited := false
      keptSlot := Some(slot)
      ctx.toast(`Kept “${Preset.name(preset)}” in program ${ProgramStore.number(programs.current)}`)
      renderAll()
    })

  // (a card that was never played is measured first, so that it goes in at its level)
  let keep = slot =>
    chosen.contents == Some(slot) && edited.contents ? keepNow(slot) : withMeasured(slot, () => keepNow(slot))

  let undoKeep = () =>
    undo.contents->Option.forEach(((before, index)) => {
      if index == programs.current {
        programs->ProgramStore.loadIntoCurrent(before)
        ctx.toast(`Program ${ProgramStore.number(index)} is back as it was`)
      }
      undo := None
      keptSlot := None
      renderAll()
    })

  ctx.model->ParamModel.listenAny(_ =>
    if !applying.contents && original.contents != None {
      edited := true
    }
  )
  // another program, picked from the header or the browser: nothing to put back any more
  programs->ProgramStore.onChanged(() =>
    switch original.contents {
    | Some((_, index)) if index != programs.current =>
      original := None
      chosen := None
      renderAll()
    | _ => ()
    }
  )

  //==============================================================================
  // making patches

  let lockedNow = () => PatchGen.areas->Array.filter(a => locks->Set.has(a))

  // what is playing: the chosen card (with any edits), or the program (the locks keep its areas)
  let playing = () =>
    switch (chosen.contents, original.contents) {
    | (Some(slot), Some(_)) =>
      patchAt(slot)->Option.map(p => (edited.contents ? ProgramStore.captureCurrent(programs).values : p.values, p.kind))
    | _ => None
    }->Option.getOr({
      let values = ProgramStore.captureCurrent(programs).values
      (values, PatchGen.kindOf(values))
    })

  // A new row of cards, after the rows before it (the last few of them, to go back to).
  let push = (gen: generation) => {
    stopProbe()
    generations->Array.push(gen)
    if Array.length(generations) > maxRows {
      generations->Array.splice(~start=0, ~remove=Array.length(generations) - maxRows, ~insert=[])
    }
    chosen := None
    keptSlot := None
    renderAll()
  }

  // distinct names within a row ("Wide Pad", "Wide Pad 2")
  let distinct = (names: array<string>) =>
    names->Array.mapWithIndex((name, i) => {
      let before = names->Array.slice(~start=0, ~end=i)->Array.filter(n => n == name)->Array.length
      before == 0 ? name : `${name} ${Int.toString(before + 1)}`
    })

  let named = (patches: array<patch>) => {
    let names = distinct(patches->Array.map(p => p.name))
    patches->Array.mapWithIndex((p, i) => {...p, name: names->Array.getUnsafe(i)})
  }

  let lockText = locked =>
    switch locked {
    | [] => ""
    | areas => ", keeping " ++ areas->Array.map(PatchGen.areaShort)->Array.join(", ")
    }

  let startGenerate = () => {
    let r: PatchGen.rng = Math.random
    let locked = lockedNow()
    let (reference, referenceKind) = playing()
    let keep = locked == [] ? None : Some((reference, locked))
    // with locks, the kind of what is playing; with none chosen, four different kinds
    let kinds = switch (kind.contents, locked) {
    | (Some(k), _) => Array.make(~length=slotCount, k)
    | (None, []) =>
      let left = ref(PatchGen.kinds)
      Array.fromInitializer(~length=slotCount, _ => {
        let k = PatchGen.weighted(r, left.contents->Array.map(k => (k, k == #bell || k == #brass ? 0.6 : 1.)))
        left := left.contents->Array.filter(x => x != k)
        k
      })
    | (None, _) => Array.make(~length=slotCount, referenceKind)
    }
    let patches = kinds->Array.map(k => {
      let values = PatchGen.generate(~wild=wild.contents, ~kind=k, ~random=r, ~keep?)
      {
        values,
        base: Lazy.get(init),
        kind: k,
        name: PatchGen.nameOf(values, ~kind=k, ~random=r),
        origin: "Made at random",
        target: Some(PatchGen.targetDb),
        measured: false,
      }
    })
    let label = switch kind.contents {
    | Some(k) => "new " ++ PatchGen.kindName(k)
    | None => "new patches"
    }
    push({label: label ++ lockText(locked), patches: named(patches)})
  }

  let variations = (from: patch, (amountName, amount), ~title) => {
    let r: PatchGen.rng = Math.random
    let locked = lockedNow()
    let patches = Array.fromInitializer(~length=slotCount, i => {
      let values = PatchGen.vary(from.values, ~amount, ~wild=wild.contents, ~locks=locked, ~kind=from.kind, ~random=r)
      {
        ...from,
        values,
        name: from.base === Lazy.get(init) ? PatchGen.nameOf(values, ~kind=from.kind, ~random=r) : `${from.name} ${Int.toString(i + 1)}`,
        origin: `${from.origin}, varied ${amountName}`,
        measured: false,
      }
    })
    push({label: `${title}, varied ${amountName}${lockText(locked)}`, patches: named(patches)})
  }

  // (a card played and edited is varied with the edits)
  let startVary = (slot, amount) =>
    patchAt(slot)->Option.forEach(p => {
      let edits = chosen.contents == Some(slot) && edited.contents && original.contents != None
      let from = edits ? {...p, values: ProgramStore.captureCurrent(programs).values} : p
      variations(from, amount, ~title=p.name->String.toLowerCase)
    })

  // The program as it is, before any card was played on it: measured first (silently), so that
  // its variations play as loud as it does (as they're estimated to, without a meter).
  let startVaryProgram = amount => {
    settle()
    let program = ProgramStore.captureCurrent(programs)
    let name = Preset.name(program)
    let kind = PatchGen.kindOf(program.values)
    let vary = target =>
      variations(
        {values: program.values, base: program, kind, name, origin: `Varied from ${name}`, target, measured: false},
        amount,
        ~title=name,
      )
    if meterWorks.contents {
      original := Some((program, programs.current))
      let ms = probeMs(program.values)
      measure(program, ~note=PatchGen.profile(kind).note, ~ms, result => {
        // (the program goes back on as it was)
        settle()
        let gain = program.values->Map.get("Gain")->Option.getOr(0.1)
        vary(
          result->Option.map(heard => {
            let (level, _) = wholeNote(program.values, ~kind, ~ms, heard)
            level + PatchGen.dbOfAmp(gain)
          }),
        )
      })
    } else {
      vary(None)
    }
  }

  //==============================================================================
  // opening

  let show = () =>
    if !opened.contents {
      opened := true
      load()
      root->addClass("on")
      if generations == [] {
        startGenerate()
      }
      renderAll()
    }

  let hide = () =>
    if opened.contents {
      opened := false
      if saveTimer.contents != None {
        save()
      }
      stopProbe()
      settle()
      chosen := None
      undo := None
      keptSlot := None
      root->removeClass("on")
      ctx.menu->Menu.close
      renderAll()
    }

  //==============================================================================
  // wiring

  generate->onMouse(#click, _ => startGenerate())
  kindButton->onMouse(#click, _ =>
    ctx.menu->Menu.show(
      kindButton,
      Array.concat(
        [{Menu.label: "any kind (four kinds)", value: -1}],
        PatchGen.kinds->Array.mapWithIndex((k, i) => {Menu.label: PatchGen.kindName(k), value: i}),
      ),
      kind.contents->Option.mapOr(-1, k => PatchGen.kinds->Array.findIndex(x => x == k)),
      i => {
        kind := PatchGen.kinds[i]
        save()
        renderHead()
      },
    )
  )
  varyProgram->onMouse(#click, _ =>
    ctx.menu->Menu.show(
      varyProgram,
      amounts->Array.mapWithIndex(((name, _), i) => {Menu.label: "vary " ++ name, value: i}),
      -1,
      i => amounts[i]->Option.forEach(startVaryProgram),
    )
  )
  lockChips->Array.forEach(((a, chip)) =>
    chip->onMouse(#click, _ => {
      locks->Set.has(a) ? locks->Set.delete(a)->ignore : locks->Set.add(a)
      renderHead()
    })
  )
  undoButton->onMouse(#click, _ => undoKeep())
  close->onMouse(#click, _ => hide())

  cards->Array.forEachWithIndex((card, slot) => {
    card.root->onMouse(#click, _ => tryCard(slot))
    card.play->onMouse(#click, ev => {
      ev->stopPropagation
      tryCard(slot)
    })
    card.keep->onMouse(#click, ev => {
      ev->stopPropagation
      keep(slot)
    })
    card.vary->onMouse(#click, ev => {
      ev->stopPropagation
      if patchAt(slot) != None {
        ctx.menu->Menu.show(
          card.vary,
          amounts->Array.mapWithIndex(((name, _), i) => {Menu.label: "vary " ++ name, value: i}),
          -1,
          i => amounts[i]->Option.forEach(a => startVary(slot, a)),
        )
      }
    })
  })

  {
    show,
    hide,
    isOpen: () => opened.contents,
    dispose: () => {
      noteOff()
      saveTimer.contents->Option.forEach(clearTimeout)
    },
  }
}
