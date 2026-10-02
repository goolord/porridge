// The sound matcher's drawer. A sample dropped on the window (or chosen here) is matched by
// four searches at once (MatchSearch.islands), and their cards fill in as the searches go: how
// close each patch is, a picture of its loudness and spectrum over the sample's, and what it is
// made of.
//
//  - Clicking a card plays it on the synth, at the sample's pitch; the program isn't changed
//    until Keep, and closing the drawer puts back what was playing before (unless the card
//    was edited meanwhile, which keeps the edits). Keep can be undone while the drawer is open.
//  - Vary makes four variations of a card, a little, some or a lot apart, which can be varied
//    in turn; the row above the cards goes back.
//  - The locks keep parts of the chosen card (its oscillators, filter, envelopes, modulation
//    or effects) while re-matching or varying the rest.
//
// The matching itself runs in workers (MatchPool.res), which start the first time it's used.

open! Web

let slotCount = 4
// the renders a match of a long sample has, for the outline and the four searches together (a
// short one has more: MatchSearch.budgetFor)
let budget = 1000
let amounts = [("a little", 0.15), ("some", 0.35), ("a lot", 0.7)]

type card = {
  root: element,
  title: element,
  // "closest", on the card nearest the sample
  best: element,
  badge: element,
  score: element,
  picture: element,
  desc: element,
  play: element,
  keep: element,
  vary: element,
}

// A row of cards: the matches, or variations of one card.
type generation = {
  label: string,
  heads: array<(string, string)>,
  found: array<option<MatchSearch.candidate>>,
  progress: array<float>,
  // what fills it, and its run's number in the pool
  mutable run: option<(MatchRun.t, int)>,
  mutable running: bool,
}

type loaded = {
  target: SoundTarget.t,
  // where the predictor (MatchModel.res) suggests the search starts, best guess first
  suggestions: array<Float64Array.t>,
  // the pool's session for it (MatchPool.session), once it has one
  mutable session: option<int>,
  // the target's picture: loudness and spectrum, dB
  picture: (array<float>, array<float>),
  fileName: string,
}

type t = {
  show: unit => unit,
  hide: unit => unit,
  isOpen: unit => bool,
  loadFile: file => unit,
  dispose: unit => unit,
}

let maxOf = xs => xs->Array.reduce(neg_infinity, Math.max)

// The card's picture: the loudness over time on the left, the average spectrum on the right;
// the sample's as a line, the candidate's filled (at the sample's overall loudness).
let drawPicture = (canvas, (targetEnv, targetSpec), candidate) => {
  open Context2d
  let g = canvas->getContext2d
  let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
  g->clearRect(0., 0., w, h)
  let split = Math.round(w * 0.58)
  let gap = 10.
  g->setFillStyle(Style.rgba(Style.paperRgb, 0.55))
  g->fillRect(0., 0., split - gap / 2., h)
  g->fillRect(split + gap / 2., 0., w - split - gap / 2., h)
  let range = 54.
  let trace = (values: array<float>, ~x0: float, ~x1: float, ~top: float, ~filled) => {
    let n = Array.length(values)
    let y = v => h - 3. - Math.max(0., Math.min(1., (v - (top - range)) / range)) * (h - 8.)
    g->beginPath
    values->Array.forEachWithIndex((v, i) => {
      let x = x0 + (x1 - x0) * Int.toFloat(i) / Int.toFloat(Math.Int.max(1, n - 1))
      i == 0 ? g->moveTo(x, y(v)) : g->lineTo(x, y(v))
    })
    if filled {
      g->lineTo(x1, h)
      g->lineTo(x0, h)
      g->closePath
      g->fill
    } else {
      g->stroke
    }
  }
  let envTop = maxOf(targetEnv) + 3.
  let specTop = maxOf(targetSpec) + 3.
  let (l0, l1) = (2., split - gap / 2. - 2.)
  let (r0, r1) = (split + gap / 2. + 2., w - 2.)
  candidate->Option.forEach(((env, spec)) => {
    g->setFillStyle(CanvasStyle.tint(0.4))
    trace(env, ~x0=l0, ~x1=l1, ~top=envTop, ~filled=true)
    trace(spec, ~x0=r0, ~x1=r1, ~top=specTop, ~filled=true)
  })
  g->setStrokeStyle(CanvasStyle.shade(0.85))
  g->setLineWidth(2.)
  trace(targetEnv, ~x0=l0, ~x1=l1, ~top=envTop, ~filled=false)
  trace(targetSpec, ~x0=r0, ~x1=r1, ~top=specTop, ~filled=false)
}

// The sample's overview: its peaks, mirrored.
let drawWave = (canvas, peaks: array<float>) => {
  open Context2d
  let g = canvas->getContext2d
  let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
  g->clearRect(0., 0., w, h)
  let top = Math.max(1e-6, maxOf(peaks))
  let n = Array.length(peaks)
  g->setFillStyle(CanvasStyle.ink)
  peaks->Array.forEachWithIndex((p, i) => {
    let x = w * Int.toFloat(i) / Int.toFloat(n)
    let a = Math.max(1., p / top * (h / 2. - 1.))
    g->fillRect(x, h / 2. - a, Math.max(1., w / Int.toFloat(n)), 2. * a)
  })
}

let canvasIn = (parent, ~cls, ~w, ~h) => {
  let c = el("canvas", ~cls, ~parent)
  c->setCanvasWidth(w * 2.)
  c->setCanvasHeight(h * 2.)
  c->setStyle("width", px(w))
  c->setStyle("height", px(h))
  c
}

let percent = s => Float.toString(Math.round(s)) ++ "%"

// a padlock, for the locks
let lockIcon: Icons.icon = {
  width: 12.,
  marks: [Line("M3.5 7.5 V5 A2.5 2.5 0 0 1 8.5 5 V7.5"), Fill("M2 7.5 H10 V14 H2 Z")],
}

let make = (ctx: Ctx.t, stage): t => {
  let programs = ctx.programs
  let status = ctx.status

  let root = el("div", ~cls="mt", ~parent=stage)
  let head = el("div", ~cls="mt-head", ~parent=root)
  let bar = el("div", ~cls="mt-bar", ~parent=root)
  let fill = el("div", ~parent=bar)
  let crumbs = el("div", ~cls="mt-crumbs", ~parent=root)
  let row = el("div", ~cls="mt-cards", ~parent=root)
  let empty = el("div", ~cls="mt-empty", ~parent=root)

  // a button whose status text is title() (its click is wired at the end)
  let button = (parent, text, title) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    status->Status.hover(b, title)
    b
  }

  //==============================================================================
  // state

  let opened = ref(false)
  let pool: ref<option<promise<result<MatchPool.t, string>>>> = ref(None)
  let loaded: ref<option<loaded>> = ref(None)
  let generations: array<generation> = []
  let locks: Set.t<Genome.group> = Set.make()
  let runs = ref(0)
  let player = SamplePlayer.make()
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
  let noteTimer = ref(None)
  let playingNote = ref(None)
  let init = Lazy.make(() => Preset.make("Init"))

  let shown = () => generations->Array.at(-1)

  // the pool, once it's running
  let withPool = f =>
    pool.contents->Option.forEach(p => p->Promise.thenResolve(r => r->Result.forEach(f))->ignore)
  let stopRun = ((run, number)) => {
    MatchRun.cancel(run)
    withPool(p => MatchPool.cancelRun(p, number))
  }

  let startPool = () =>
    switch pool.contents {
    | Some(p) => p
    | None =>
      let p = MatchPool.start(ctx.pc)
      pool := Some(p)
      p
    }

  let setup = (l: loaded): MatchProtocol.setup => {
    target: l.target,
    base: Lazy.get(init).values,
    tables: Lazy.get(init).tables,
  }

  //==============================================================================
  // the header

  el("div", ~cls="mt-title", ~text="match a sound", ~parent=head)->ignore
  let targetBox = el("div", ~cls="mt-target", ~parent=head)
  let wave = canvasIn(targetBox, ~cls="mt-wave", ~w=96., ~h=22.)
  let names = el("div", ~cls="mt-tnames", ~parent=targetBox)
  let targetName = el("div", ~cls="mt-tname", ~parent=names)
  let targetInfo = el("div", ~cls="mt-tinfo", ~parent=names)
  status->Status.hover(targetBox, () => "Click to match another sample (or drop one on the window)")

  let playSample = button(head, "▶ sample", () => "Play the sample (through this computer's own audio output)")
  el("div", ~cls="spacer", ~parent=head)->ignore
  let lockLabel = el("div", ~cls="mt-locklabel", ~text="lock", ~parent=head)
  let lockRow = el("div", ~cls="mt-locks", ~parent=head)
  let lockShort = (g: Genome.group) =>
    switch g {
    | #osc => "osc"
    | #filter => "filter"
    | #env => "env"
    | #mod => "mod"
    | #fx => "fx"
    | #eq => "eq"
    }
  let lockChips = Genome.groups->Array.map(g => {
    let chip = el("div", ~cls="mt-lock", ~parent=lockRow)
    chip->appendChild(Icons.render(lockIcon))
    el("span", ~text=lockShort(g), ~parent=chip)->ignore
    status->Status.hover(chip, () =>
      `Keep the chosen card's ${Genome.groupName(g)->String.toLowerCase} when re-matching or varying the rest`
    )
    (g, chip)
  })
  let rematchText = ref(() => "")
  let rematch = button(head, "re-match", () => rematchText.contents())
  [playSample, lockLabel, lockRow, rematch]->Array.forEach(e => e->addClass("mt-loaded"))
  let undoButton = button(head, "undo keep", () => "Put the program back as it was before Keep")
  let close = button(head, "×", () => "Close (a card being played goes back to the program as it was)")
  close->addClass("icon")

  //==============================================================================
  // the cards

  let blurbAt = ref(_ => "")
  let cards = Array.fromInitializer(~length=slotCount, slot => {
    let root = el("div", ~cls="mt-card", ~parent=row)
    let top = el("div", ~cls="mt-ctop", ~parent=root)
    let title = el("div", ~cls="mt-ctitle", ~parent=top)
    let best = el("div", ~cls="mt-best", ~parent=top)
    let badge = el("div", ~cls="mt-badge", ~parent=top)
    let score = el("div", ~cls="mt-score", ~parent=top)
    let picture = canvasIn(root, ~cls="mt-pic", ~w=244., ~h=64.)
    let desc = el("div", ~cls="mt-desc", ~parent=root)
    let buttons = el("div", ~cls="mt-cbtns", ~parent=root)
    let card = {
      root,
      title,
      best,
      badge,
      score,
      picture,
      desc,
      play: el("button", ~cls="btn", ~text="▶ play", ~parent=buttons),
      keep: el("button", ~cls="btn", ~text="keep", ~parent=buttons),
      vary: el("button", ~cls="btn", ~text="vary ▾", ~parent=buttons),
    }
    status->Status.hover(card.play, () => "Play this patch on the synth at the sample's pitch; the program isn't changed until Keep")
    status->Status.hover(card.keep, () => "Put this patch in the current program, named after the sample")
    status->Status.hover(card.vary, () => "Four variations of this patch: a little, some or a lot apart")
    status->Status.hover(card.title, () => blurbAt.contents(slot))
    status->Status.hover(card.best, () => "The closest of these to the sample")
    status->Status.hover(card.score, () => "How close it sounds to the sample")
    status->Status.hover(card.picture, () =>
      "Its loudness over time (left) and its spectrum (right), filled; the sample's as a line"
    )
    card
  })

  //==============================================================================
  // drawing

  let candidateAt = slot => shown()->Option.flatMap(gen => gen.found[slot]->Option.flatMap(c => c))
  blurbAt := slot => shown()->Option.flatMap(gen => gen.heads[slot])->Option.mapOr("", ((_, blurb)) => blurb)

  // the card nearest the sample, once there are two to choose between
  let closestSlot = (gen: generation) => {
    let found = gen.found->Array.filterMap(c => c)
    Array.length(found) < 2
      ? None
      : found->Array.reduce(None, (best, c: MatchSearch.candidate) =>
          switch best {
          | Some(b: MatchSearch.candidate) if b.similarity >= c.similarity => best
          | _ => Some(c)
          }
        )->Option.map(c => c.slot)
  }

  let renderCard = slot => {
    let card = cards->Array.getUnsafe(slot)
    switch (shown(), loaded.contents) {
    | (Some(gen), Some(l)) =>
      card.best->setTextContent(closestSlot(gen) == Some(slot) ? "closest" : "")
      let (title, blurb) = gen.heads[slot]->Option.getOr(("", ""))
      card.title->setTextContent(title)
      let found = candidateAt(slot)
      card.root->toggleClass("empty", found == None)
      card.root->toggleClass("live", chosen.contents == Some(slot) && original.contents != None)
      card.root->toggleClass("kept", keptSlot.contents == Some(slot))
      card.badge->setTextContent(
        keptSlot.contents == Some(slot) ? "kept" : chosen.contents == Some(slot) && original.contents != None ? "playing" : "",
      )
      switch found {
      | Some(c) =>
        card.score->setTextContent(percent(c.similarity))
        card.desc->setTextContent(c.description)
        drawPicture(card.picture, l.picture, Some((c.envelope, c.spectrum)))
      | None =>
        card.score->setTextContent(gen.running ? "…" : "")
        card.desc->setTextContent(gen.running ? blurb : "nothing found")
        drawPicture(card.picture, l.picture, None)
      }
    | _ => ()
    }
  }

  let renderBar = () =>
    switch shown() {
    | Some(gen) if gen.running =>
      let done = gen.progress->Array.reduce(0., (s, p) => s + p) / Int.toFloat(slotCount)
      bar->addClass("on")
      fill->setStyle("width", Float.toString(Math.min(100., 100. * done)) ++ "%")
    | _ => bar->removeClass("on")
    }

  let rec renderCrumbs = () => {
    crumbs->setTextContent("")
    crumbs->toggleClass("on", Array.length(generations) > 1)
    generations->Array.forEachWithIndex((gen, i) => {
      if i > 0 {
        el("span", ~cls="mt-sep", ~text="›", ~parent=crumbs)->ignore
      }
      let last = i == Array.length(generations) - 1
      let c = el("span", ~cls=last ? "mt-crumb on" : "mt-crumb", ~text=gen.label, ~parent=crumbs)
      if !last {
        c->onMouse(#click, _ => {
          // back to that row: what came after it stops
          while Array.length(generations) > i + 1 {
            generations
            ->Array.pop
            ->Option.forEach(g =>
              g.run->Option.forEach(stopRun)
            )
          }
          chosen := None
          keptSlot := None
          renderAll()
        })
      }
    })
  }

  and renderHead = () => {
    let has = loaded.contents != None
    root->toggleClass("loaded", has)
    loaded.contents->Option.forEach(l => {
      targetName->setTextContent(l.fileName)
      targetInfo->setTextContent(
        `${SoundTarget.pitchText(l.target)} · ${l.target.cutOff > 0.05 ? "first " : ""}${Float.toFixed(SoundTarget.seconds(l.target), ~digits=2)} s`,
      )
      drawWave(wave, l.target.overview)
    })
    let running = shown()->Option.mapOr(false, g => g.running)
    rematch->setTextContent(running ? "stop" : "re-match")
    rematch->toggleClass("on", running)
    undoButton->toggleClass("hidden", undo.contents == None)
    let canLock = chosen.contents != None
    lockLabel->toggleClass("off", !canLock)
    lockChips->Array.forEach(((g, chip)) => {
      chip->toggleClass("on", locks->Set.has(g))
      chip->toggleClass("off", !canLock)
    })
  }

  and renderAll = () => {
    renderHead()
    renderCrumbs()
    renderBar()
    Array.fromInitializer(~length=slotCount, i => i)->Array.forEach(renderCard)
  }

  let message = text => {
    empty->setTextContent("")
    el("div", ~cls="big", ~text, ~parent=empty)->ignore
  }

  let showEmpty = () => {
    empty->setTextContent("")
    el("div", ~cls="big", ~text="Drop a sample here, or anywhere on the window", ~parent=empty)->ignore
    el(
      "div",
      ~text=`Porridge listens to it and searches its oscillators, filter, envelopes and effects for patches that sound like it: a detailed one, a simple one, a punchy one and a lush one, the closest marked. The first ${Float.toString(SoundTarget.maxSeconds)} seconds are matched.`,
      ~parent=empty,
    )->ignore
    el("button", ~cls="btn", ~text="choose a sample…", ~parent=empty)->ignore
  }

  //==============================================================================
  // playing cards on the synth

  let noteOff = () => {
    noteTimer.contents->Option.forEach(clearTimeout)
    noteTimer := None
    playingNote.contents->Option.forEach(note => Wheels.send(ctx, 0x80, note, 0))
    playingNote := None
  }

  // a card's note, at the key it matched the sample's pitch with
  let playNote = note =>
    loaded.contents->Option.forEach(l => {
      noteOff()
      Wheels.send(ctx, 0x90, note, MatchEngine.velocity)
      playingNote := Some(note)
      let seconds = Math.max(0.35, Math.min(2.5, SoundTarget.seconds(l.target)))
      noteTimer := Some(setTimeout(noteOff, Float.toInt(seconds * 1000.)))
    })

  let baseName = () =>
    loaded.contents->Option.mapOr("Match", l => Web.baseName(l.fileName)->String.slice(~start=0, ~end=Preset.maxNameLength))

  // A candidate as a program: Init with its values (and the fitted wave, if it plays it),
  // named after the sample.
  let presetOf = (c: MatchSearch.candidate, ~title) => {
    let init = Lazy.get(init)
    let values = Map.fromArray(init.values->Map.entries->Array.fromIterator)
    c.values->Array.forEach(((id, v)) => values->Map.set(id, v))
    let tables = Preset.copyTables(init.tables)
    let preset: Preset.t = {
      ...init,
      values,
      tables: switch loaded.contents {
      | Some(l) if c.fitted => MatchSearch.tablesFor(l.target, tables)
      | _ => tables
      },
      meta: {
        ...init.meta,
        name: baseName(),
        author: ProgramStore.meta(programs).author,
        tags: ["matched"],
        description: loaded.contents->Option.mapOr("", l =>
          `Matched from ${l.fileName} (${title}, ${percent(c.similarity)} close).`
        ),
      },
    }
    preset
  }

  let apply = preset => {
    applying := true
    programs->ProgramStore.preview(preset)
    applying := false
  }

  let tryCard = slot =>
    switch (candidateAt(slot), shown()) {
    | (Some(c), Some(gen)) =>
      if original.contents == None {
        original := Some((ProgramStore.captureCurrent(programs), programs.current))
      }
      if chosen.contents != Some(slot) || !edited.contents {
        let (title, _) = gen.heads[slot]->Option.getOr(("", ""))
        let preset = presetOf(c, ~title)
        apply(preset)
        triedMeta := Some(preset.meta)
        edited := false
      }
      chosen := Some(slot)
      keptSlot := None
      playNote(c.note)
      renderAll()
    | _ => ()
    }

  // Puts the program back as it was before a card was played, unless the card has been
  // edited since, which keeps it with the edits.
  let settle = () => {
    noteOff()
    switch original.contents {
    | Some((before, index)) if index == programs.current =>
      if edited.contents {
        let edits = ProgramStore.captureCurrent(programs)
        programs->ProgramStore.loadIntoCurrent({...edits, meta: triedMeta.contents->Option.getOr(edits.meta)})
        ctx.toast(`Kept your edited match in program ${ProgramStore.number(programs.current)}`)
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

  let keep = slot =>
    switch (candidateAt(slot), shown()) {
    | (Some(c), Some(gen)) =>
      noteOff()
      let (title, _) = gen.heads[slot]->Option.getOr(("", ""))
      let before = switch original.contents {
      | Some((p, index)) if index == programs.current => p
      | _ => ProgramStore.captureCurrent(programs)
      }
      let preset =
        chosen.contents == Some(slot) && edited.contents
          ? {...ProgramStore.captureCurrent(programs), meta: presetOf(c, ~title).meta}
          : presetOf(c, ~title)
      programs->ProgramStore.loadIntoCurrent(preset)
      undo := Some((before, programs.current))
      original := None
      edited := false
      keptSlot := Some(slot)
      ctx.toast(`Kept “${Preset.name(preset)}” in program ${ProgramStore.number(programs.current)}`)
      renderAll()
    | _ => ()
    }

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
  // searching

  let cancelShown = () =>
    shown()->Option.forEach(gen =>
      if gen.running {
        gen.running = false
        gen.run->Option.forEach(stopRun)
      }
    )

  let handlersFor = (gen: generation): MatchRun.handlers => {
    let isShown = () => shown()->Option.mapOr(false, g => g === gen)
    {
      onCandidate: c => {
        gen.found->Array.setUnsafe(c.slot, Some(c))
        if isShown() {
          // (the closest may have moved to it)
          Array.fromInitializer(~length=slotCount, i => i)->Array.forEach(renderCard)
        }
      },
      onProgress: (~island, ~evals, ~budget) => {
        gen.progress->Array.setUnsafe(island, Int.toFloat(evals) / Int.toFloat(Math.Int.max(1, budget)))
        if isShown() {
          renderBar()
        }
      },
      onDone: () => {
        gen.running = false
        if isShown() {
          renderAll()
        }
      },
    }
  }

  let lockedNow = () => chosen.contents == None ? [] : Genome.groups->Array.filter(g => locks->Set.has(g))

  // Shows a new row of cards and starts what fills it, once the workers are going: `start`
  // gets them and how to evaluate genes in this run.
  let push = (gen: generation, l: loaded, start: (MatchPool.t, MatchRun.evaluate) => MatchRun.t) => {
    cancelShown()
    generations->Array.push(gen)
    chosen := None
    keptSlot := None
    renderAll()
    startPool()
    ->Promise.thenResolve(r =>
      switch r {
      | Ok(p) =>
        if gen.running {
          let session = switch l.session {
          | Some(s) => s
          | None =>
            let s = MatchPool.session(p, setup(l))
            l.session = Some(s)
            s
          }
          let run = MatchPool.newRun(p)
          let evaluate = (x, weights, threshold, fit, short) =>
            MatchPool.evaluate(p, ~session, ~run, x, weights, threshold, fit, short)
          gen.run = Some((start(p, evaluate), run))
        }
      | Error(text) =>
        gen.running = false
        ctx.toast(text)
        renderAll()
      }
    )
    ->ignore
  }

  let lockText = locked =>
    switch locked {
    | [] => ""
    | groups => " keeping its " ++ groups->Array.map(lockShort)->Array.join(", ")
    }

  // The four searches, from the sample's seed; or with locks, from the chosen card.
  let startMatch = () =>
    loaded.contents->Option.forEach(l => {
      let locked = lockedNow()
      let reference = locked == [] ? None : chosen.contents->Option.flatMap(candidateAt)
      let starts = switch reference {
      | Some(c) => [Float64Array.fromArray(c.genes)]
      | None => [...Genome.seeds(l.target), ...l.suggestions]
      }
      runs := runs.contents + 1
      let seed = 7919 * runs.contents
      let gen = {
        label: reference == None ? (runs.contents == 1 ? "matches" : "matches again") : "re-matched" ++ lockText(locked),
        heads: MatchSearch.islands->Array.map(i => (i.title, i.blurb)),
        found: Array.make(~length=slotCount, None),
        progress: Array.make(~length=slotCount, 0.),
        run: None,
        running: true,
      }
      push(gen, l, (_, evaluate) =>
        MatchRun.search(
          evaluate,
          MatchSearch.makeMatch(
            ~starts,
            ~fitted=l.target.wave != None,
            ~locks=locked,
            ~reference=reference->Option.map(c => Float64Array.fromArray(c.genes)),
            ~budget=MatchSearch.budgetFor(~base=budget, ~seconds=SoundTarget.seconds(l.target)),
            ~sigma=reference == None ? 0.25 : 0.2,
            ~seed,
          ),
          handlersFor(gen),
        )
      )
    })

  let startVary = (slot, (amountName, amount)) =>
    switch (loaded.contents, candidateAt(slot), shown()) {
    | (Some(l), Some(c), Some(parent)) =>
      let locked = chosen.contents == Some(slot) ? lockedNow() : []
      let (parentTitle, _) = parent.heads[slot]->Option.getOr(("", ""))
      runs := runs.contents + 1
      let gen = {
        label: `${parentTitle->String.toLowerCase}, varied ${amountName}${lockText(locked)}`,
        heads: Array.fromInitializer(~length=slotCount, i => (
          `variation ${Int.toString(i + 1)}`,
          `${parentTitle}, varied ${amountName}`,
        )),
        found: Array.make(~length=slotCount, None),
        progress: Array.make(~length=slotCount, 0.),
        run: None,
        running: true,
      }
      let mutants = MatchSearch.mutants(
        Float64Array.fromArray(c.genes),
        ~fitted=l.target.wave != None,
        ~locks=locked,
        ~amount,
        ~count=slotCount,
        ~seed=104729 * runs.contents,
      )
      push(gen, l, (_, evaluate) => MatchRun.vary(evaluate, mutants, handlersFor(gen)))
    | _ => ()
    }

  //==============================================================================
  // opening and loading

  let show = () =>
    if !opened.contents {
      opened := true
      root->addClass("on")
      if loaded.contents == None {
        showEmpty()
      }
      renderAll()
      // the engine starts loading as soon as the drawer opens
      startPool()->ignore
    }

  let hide = () =>
    if opened.contents {
      opened := false
      cancelShown()
      settle()
      chosen := None
      undo := None
      keptSlot := None
      player->SamplePlayer.stop
      root->removeClass("on")
      ctx.menu->Menu.close
      // the workers go (they hold about 50 MB each); a new match starts them again
      withPool(MatchPool.dispose)
      pool := None
      loaded.contents->Option.forEach(l => l.session = None)
      renderAll()
    }

  let loadFile = file => {
    show()
    let name = file->fileName
    message(`Listening to ${name}…`)
    root->removeClass("loaded")
    (async () => {
      switch await AudioFile.readFile(file) {
      | Error(text) => message(text)
      | Ok(audio) =>
        switch await startPool() {
        | Error(text) => message(text)
        | Ok(p) =>
          switch await MatchPool.prepare(p, ~name, audio) {
          | Error(text) => message(text)
          | Ok((target, envelope, spectrum, suggestions)) =>
            settle()
            cancelShown()
            generations->Array.splice(~start=0, ~remove=Array.length(generations), ~insert=[])
            runs := 0
            undo := None
            loaded := Some({target, suggestions, session: None, picture: (envelope, spectrum), fileName: name})
            startMatch()
          }
        }
      }
    })()->ignore
  }

  let pickFile = FilePicker.make(stage, ~accept=AudioFile.accept, loadFile)

  //==============================================================================
  // wiring

  targetBox->onMouse(#click, _ => pickFile())
  empty->onMouse(#click, _ =>
    if loaded.contents == None {
      pickFile()
    }
  )
  playSample->onMouse(#click, _ =>
    loaded.contents->Option.forEach(l =>
      if player->SamplePlayer.isPlaying {
        player->SamplePlayer.stop
      } else {
        noteOff()
        player->SamplePlayer.play([l.target.samples], ~sampleRate=SoundTarget.sampleRate)
      }
    )
  )
  lockChips->Array.forEach(((g, chip)) =>
    chip->onMouse(#click, _ =>
      if chosen.contents != None {
        locks->Set.has(g) ? locks->Set.delete(g)->ignore : locks->Set.add(g)
        renderHead()
      }
    )
  )
  rematchText := () =>
    shown()->Option.mapOr(false, g => g.running)
      ? "Stop searching; the cards keep what they have"
      : lockedNow() == []
      ? "Search again from the start, for four more"
      : "Search again, keeping the chosen card's " ++ lockedNow()->Array.map(lockShort)->Array.join(", ")
  rematch->onMouse(#click, _ =>
    if shown()->Option.mapOr(false, g => g.running) {
      cancelShown()
      renderAll()
    } else {
      startMatch()
    }
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
      if candidateAt(slot) != None {
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
    loadFile,
    dispose: () => {
      noteOff()
      player->SamplePlayer.dispose
      cancelShown()
      withPool(MatchPool.dispose)
    },
  }
}
