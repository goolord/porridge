// The patch view: pages on a fixed-size stage that is scaled to fit the window, a header
// with the page tabs and the program and file controls, and a status line.

open! Web

type page = [#main | #mod | #fx | #play | #shapes | #midi]

let hintFor = (page: page) =>
  switch page {
  | #main => PageMain.hint
  | #mod => PageMod.hint
  | #fx => PageFx.hint
  | #play => PagePlay.hint
  | #shapes => PageShapes.hint
  | #midi => PageMidi.hint
  }

type t = {
  showPage: page => unit,
  // lets go of the patch connection
  dispose: unit => unit,
}

let pad2 = i => Int.toString(i)->String.padStart(2, "0")

let make = (host, pc) => {
  // A scratch v38 program holding the current values, used as the context for status texts
  // (several texts depend on other fields: octave size, tuning, breakpoint, targets...).
  let context = OatmealFormat.makeDefaultProgram("Init")
  let model = ParamModel.make(pc, ParamDefs.makeDefs(~context=() => Some(context)))
  Bank.writeValues(context, model.values)
  model->ParamModel.listenAny(id => {
    Bank.writeValues(context, Map.fromArray([(id, model->ParamModel.get(id))]))
    // the cutoff's readout depends on the filter type
    if id == "Filter" {
      model->ParamModel.notify("Cutoff")
    }
  })

  let restoreBrowserChrome = BrowserChrome.install()
  // the page around the view (Cmajor's is black) shows while a host resizes the window
  document->documentElement->setStyle("background", Style.groundColour)
  let settings = Settings.make(pc)
  let hostMenu = HostMenu.make(pc)

  let shadow = host->attachShadow({mode: "open"})
  el("style", ~text=Style.css, ~parent=shadow)->ignore
  let stage = el("div", ~cls="pv-stage", ~parent=shadow)
  let head = el("div", ~cls="pv-head", ~parent=stage)
  let msg = el("div", ~cls="pv-status", ~parent=stage)
  let status = Status.make(msg)
  let menu = Menu.make(stage)
  let scale = ref(1.)

  let toastEl = el("div", ~cls="toast")
  let toastTimer = ref(None)
  let toast = text => {
    toastEl->setTextContent(text)
    toastEl->addClass("on")
    toastTimer.contents->Option.forEach(clearTimeout)
    toastTimer := Some(setTimeout(() => toastEl->removeClass("on"), 3500))
  }

  let progName = el("div", ~cls="name")
  let updateProgramBar = (programs: ProgramStore.t) =>
    progName->setTextContent(
      pad2(programs.current + 1) ++ "  " ++ programs->ProgramStore.name(programs.current),
    )
  let programs = ProgramStore.make(pc, model, ~onChange=updateProgramBar, ~onMessage=toast)

  let pages: array<(page, element)> = [
    (#main, el("div", ~cls="pv-page on", ~parent=stage)),
    (#mod, el("div", ~cls="pv-page", ~parent=stage)),
    (#fx, el("div", ~cls="pv-page", ~parent=stage)),
    (#play, el("div", ~cls="pv-page", ~parent=stage)),
    (#shapes, el("div", ~cls="pv-page", ~parent=stage)),
    (#midi, el("div", ~cls="pv-page", ~parent=stage)),
  ]
  let pageButtons: array<(page, element)> = []
  let shapesPage = ref(None)
  let shownPage = ref((#main: page))

  let showPage = page => {
    shownPage := page
    pages->Array.forEach(((p, e)) => e->toggleClass("on", p == page))
    pageButtons->Array.forEach(((p, b)) => b->toggleClass("on", p == page))
    menu->Menu.close
    status->Status.setIdle(hintFor(page))
    if page == #shapes {
      shapesPage.contents->Option.forEach((s: PageShapes.t) => s.refresh())
    }
  }

  let ctx: Ctx.t = {
    model,
    pc,
    status,
    menu,
    programs,
    hostMenu,
    scale: () => scale.contents,
    openShape: table => {
      showPage(#shapes)
      shapesPage.contents->Option.forEach((s: PageShapes.t) => s.select(table))
    },
    toast,
  }

  pages->Array.forEach(((page, e)) =>
    switch page {
    | #main => PageMain.build(ctx, e)
    | #mod => PageMod.build(ctx, e)
    | #fx => PageFx.build(ctx, e)
    | #play => PagePlay.build(ctx, e)
    | #midi => PageMidi.build(ctx, e)
    | #shapes => shapesPage := Some(PageShapes.build(ctx, e))
    }
  )

  //==============================================================================
  // header

  let button = (parent, text, title, onClick) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    b->onMouse(#click, _ => onClick())
    b->onMouse(#mouseenter, _ => status->Status.show(title))
    b->onMouse(#mouseleave, _ => status->Status.clear)
    b
  }

  el("div", ~cls="brand", ~text="porridge", ~parent=head)->ignore
  let pagesBar = el("div", ~cls="pages", ~parent=head)
  [
    (#main, "Synth", "Oscillators, filter, envelopes, LFOs and voice settings"),
    (#mod, "Mod", "The modulation matrix: connect sources to targets, and the macro knobs"),
    (#fx, "FX", "Distortion, chorus, delay, reverb and EQ"),
    (#play, "Arp / XY", "Arpeggiator pattern and the XY pad"),
    (#shapes, "Shapes", "Draw oscillator waveforms and LFO shapes"),
    (#midi, "MIDI", "MIDI channels, controllers, velocity and aftertouch curves"),
  ]->Array.forEach(((page, text, title)) =>
    pageButtons->Array.push((page, button(pagesBar, text, title, () => showPage(page))))
  )
  pageButtons->Array.forEach(((page, b)) => b->toggleClass("on", page == #main))
  el("div", ~cls="spacer", ~parent=head)->ignore

  let openProgramMenu = () =>
    menu->Menu.show(
      progName,
      Array.fromInitializer(~length=OatmealFormat.bankPrograms, i => {
        Menu.label: pad2(i + 1) ++ "  " ++ programs->ProgramStore.name(i),
        value: i,
      }),
      programs.current,
      i => programs->ProgramStore.select(i),
    )

  let renameProgram = () => {
    let input = el("input", ~cls="entry", ~parent=stage)
    let (x, y) = progName->offsetWithin(stage)
    input->place(x, y, ~w=progName->offsetWidth, ~h=progName->offsetHeight)->ignore
    input->setMaxLength(Preset.maxNameLength)
    input->setValue(programs->ProgramStore.name(programs.current))
    input->select
    input->focus
    let finished = ref(false)
    let finish = ok =>
      if !finished.contents {
        finished := true
        if ok {
          programs->ProgramStore.rename(programs.current, input->value)
        }
        input->remove
      }
    input->onKeyDown(k => {
      k->stopPropagation
      switch k->key {
      | "Enter" => finish(true)
      | "Escape" => finish(false)
      | _ => ()
      }
    })
    input->onEvent(#blur, _ => finish(true))
  }

  let prog = el("div", ~cls="prog", ~parent=head)
  button(prog, "<", "Previous program", () =>
    programs->ProgramStore.select(programs.current - 1)
  )->ignore
  prog->appendChild(progName)
  progName->onMouse(#click, _ => openProgramMenu())
  progName->onMouse(#dblclick, _ => renameProgram())
  progName->onMouse(#mouseenter, _ =>
    status->Status.show("Click to pick a program, double-click to rename it")
  )
  progName->onMouse(#mouseleave, _ => status->Status.clear)
  button(prog, ">", "Next program", () =>
    programs->ProgramStore.select(programs.current + 1)
  )->ignore

  let browser = PresetBrowser.make(ctx, stage, settings)
  let browse = () =>
    if !(browser->PresetBrowser.isOpen) {
      PresetBrowser.show(browser)
    }
  button(
    head,
    "Browse",
    "Search the bank, the bundled banks and files you open by name, category, tags and author (ctrl+F)",
    browse,
  )->ignore
  let onShortcut = k =>
    if k->commandKey && k->key->String.toLowerCase == "f" {
      k->preventDefault
      browse()
    }
  document->onDocumentKeyDown(onShortcut)

  let fileInput = el("input")
  // a sample becomes a shape on the Shapes page (showing the page again would clear its undo)
  let importSample = file => {
    let here = shownPage.contents == #shapes
    if !here {
      showPage(#shapes)
    }
    shapesPage.contents->Option.forEach((s: PageShapes.t) => s.importSample(file, ~here))
  }
  let loadFile = async file =>
    if AudioFile.isAudio(file->fileName) {
      importSample(file)
    } else {
      try {
        let buffer = await file->arrayBuffer
        programs->ProgramStore.loadFile(Uint8Array.fromBuffer(buffer), file->fileName)
      } catch {
      | JsExn(e) => toast(`Couldn't read ${file->fileName}: ${e->JsExn.message->Option.getOr("")}`)
      }
    }

  button(
    head,
    "Load",
    "Load a Porridge preset or bank (.porridge), an Oatmeal program or bank (.omp, .omb, .fxp, .fxb, .dat), or a Scala tuning (.scl, .kbm). You can also drop the file onto the window.",
    () => fileInput->click,
  )->ignore
  let save = ref(None)
  let saveButton = button(head, "Save ▾", "Save this program or the whole bank, or export them for Oatmeal", () =>
    save.contents->Option.forEach(open_ => open_())
  )
  save :=
    Some(
      () =>
        menu->Menu.show(
          saveButton,
          [
            {Menu.label: "Save program (.porridge)", value: 0},
            {Menu.label: "Save bank, all 64 programs (.porridge)", value: 1},
            {Menu.label: "Export program for Oatmeal (.omp)", value: 2},
            {Menu.label: "Export bank for Oatmeal (.omb)", value: 3},
          ],
          -1,
          i =>
            switch i {
            | 0 => programs->ProgramStore.downloadProgram
            | 1 => programs->ProgramStore.downloadBank
            | 2 => programs->ProgramStore.exportOatmealProgram
            | _ => programs->ProgramStore.exportOatmealBank
            },
        ),
    )
  button(head, "Info", "Name, author, category, tags and description of this program", () =>
    InfoDialog.show(ctx, stage)
  )->ignore
  button(head, "Init", "Reset this program to the Init patch", () =>
    programs->ProgramStore.initCurrent
  )->ignore
  button(head, "Panic", "Stop all notes and clear effect tails", () =>
    programs->ProgramStore.panic
  )->ignore
  button(head, "⚙", "Settings: the size of the interface", () =>
    SettingsDialog.show(settings, stage)
  )->addClass("icon")

  stage->appendChild(fileInput)
  fileInput->setInputType("file")
  fileInput->setAccept(".porridge,.json,.omp,.omb,.fxp,.fxb,.dat,.scl,.kbm")
  fileInput->setStyle("display", "none")
  fileInput->onEvent(#change, _ => {
    fileInput->files->Option.flatMap(item(_, 0))->Option.forEach(f => loadFile(f)->Promise.ignore)
    fileInput->setValue("")
  })

  stage->appendChild(toastEl)

  //==============================================================================
  // drop zone

  let drop = el("div", ~cls="drop", ~text="Drop a Porridge or Oatmeal program or bank", ~parent=stage)
  let depth = ref(0)
  host->onDrag(#dragenter, e => {
    e->preventDefault
    depth := depth.contents + 1
    drop->setTextContent(
      switch shapesPage.contents {
      | Some(s) if PageShapes.dragHasSample(e) => s.sampleDropText(~here=shownPage.contents == #shapes)
      | _ =>
        browser->PresetBrowser.isOpen
          ? "Drop Porridge or Oatmeal banks to browse them"
          : "Drop a Porridge or Oatmeal program or bank"
      },
    )
    drop->addClass("on")
  })
  host->onDrag(#dragleave, e => {
    e->preventDefault
    depth := depth.contents - 1
    if depth.contents <= 0 {
      depth := 0
      drop->removeClass("on")
    }
  })
  host->onDrag(#dragover, preventDefault)
  host->onDrag(#drop, e => {
    e->preventDefault
    depth := 0
    drop->removeClass("on")
    e
    ->dataTransfer
    ->Option.forEach(d => {
      let list = d->transferredFiles
      let files = Array.fromInitializer(~length=list->fileCount, i => list->item(i))->Array.filterMap(f => f)
      let sample = files->Array.find(f => AudioFile.isAudio(f->fileName))
      // a sample goes to the Shapes page; with the browser open, other files are added to it
      // instead of replacing the bank
      if sample->Option.isSome {
        sample->Option.forEach(f => loadFile(f)->Promise.ignore)
      } else if browser->PresetBrowser.isOpen {
        browser->PresetBrowser.addFiles(files)
      } else {
        files[0]->Option.forEach(f => loadFile(f)->Promise.ignore)
      }
    })
  })

  //==============================================================================
  // scaling

  let layout = () => {
    let orDesign = (x, design) => x == 0. ? design : x
    let w = host->clientWidth->orDesign(Style.designWidth)
    let h = host->clientHeight->orDesign(Style.designHeight)
    let s = Math.min(w / Style.designWidth, h / Style.designHeight)
    scale := s
    let ox = Math.max(0., (w - Style.designWidth * s) / 2.)
    let oy = Math.max(0., (h - Style.designHeight * s) / 2.)
    stage->setStyle("transform", `translate(${px(ox)}, ${px(oy)}) scale(${Float.toString(s)})`)
  }
  let resizeObserver = makeResizeObserver(layout)
  resizeObserver->observe(host)
  layout()

  programs->ProgramStore.start
  updateProgramBar(programs)
  status->Status.setIdle(PageMain.hint)

  {
    showPage,
    dispose: () => {
      resizeObserver->disconnect
      document->offDocumentKeyDown(onShortcut)
      restoreBrowserChrome()
      settings->Settings.dispose
      hostMenu->HostMenu.dispose
      model->ParamModel.dispose
      programs->ProgramStore.dispose
    },
  }
}
