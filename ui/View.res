// The patch view: pages on a fixed-size stage that is scaled to fit the window, a header
// with the page tabs and the program and file controls, and a status line.

open! Web

type page = [#main | #mod | #fx | #play | #shapes | #midi]

// A page: its tab's label and status text, its hint for the status line, and what builds it.
type pageSpec = {
  page: page,
  label: string,
  title: string,
  hint: string,
  build: (Ctx.t, element) => unit,
}

type t = {
  showPage: page => unit,
  // lets go of the patch connection
  dispose: unit => unit,
}

let make = (host, pc) => {
  // A scratch v38 program holding the current values, used as the context for status texts
  // (several texts depend on other fields: octave size, tuning, breakpoint, targets...).
  let context = OatmealFormat.makeDefaultProgram("Init")
  let defs = ParamDefs.makeDefs(~context=() => Some(context))
  let model = ParamModel.make(pc, defs)
  Bank.writeValues(context, model.values)
  // a change also refreshes the readouts that depend on the parameter
  let dependents = Map.make()
  defs->Array.forEach(d =>
    d.dependsOn->Array.forEach(on =>
      dependents->Map.set(on, [...dependents->Map.get(on)->Option.getOr([]), d.id])
    )
  )
  let refreshing = ref(false)
  model->ParamModel.listenAny(id =>
    if !refreshing.contents {
      Bank.writeValue(context, id, model->ParamModel.get(id))
      refreshing := true
      dependents
      ->Map.get(id)
      ->Option.forEach(ids => ids->Array.forEach(ParamModel.notify(model, _)))
      refreshing := false
    }
  )

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
  let programs = ProgramStore.make(pc, model, ~onMessage=toast)
  let updateProgramBar = () =>
    progName->setTextContent(
      ProgramStore.number(programs.current) ++ "  " ++ programs->ProgramStore.name(programs.current),
    )
  programs->ProgramStore.onChanged(updateProgramBar)

  let shapesPage = ref(None)
  let pages = [
    {
      page: #main,
      label: "Synth",
      title: "Oscillators, filter, envelopes, LFOs and voice settings",
      hint: PageMain.hint,
      build: PageMain.build,
    },
    {
      page: #mod,
      label: "Mod",
      title: "The modulation matrix: connect sources to targets, and the macro knobs",
      hint: PageMod.hint,
      build: PageMod.build,
    },
    {
      page: #fx,
      label: "FX",
      title: "Distortion, chorus, delay, reverb and EQ",
      hint: PageFx.hint,
      build: PageFx.build,
    },
    {
      page: #play,
      label: "Arp / XY",
      title: "Arpeggiator pattern and the XY pad",
      hint: PagePlay.hint,
      build: PagePlay.build,
    },
    {
      page: #shapes,
      label: "Shapes",
      title: "Draw oscillator waveforms and LFO shapes",
      hint: PageShapes.hint,
      build: (ctx, e) => shapesPage := Some(PageShapes.build(ctx, e)),
    },
    {
      page: #midi,
      label: "MIDI",
      title: "MIDI channels, controllers, velocity and aftertouch curves",
      hint: PageMidi.hint,
      build: PageMidi.build,
    },
  ]
  let pageEls =
    pages->Array.map(p => (p, el("div", ~cls=p.page == #main ? "pv-page on" : "pv-page", ~parent=stage)))
  let pageButtons: array<(page, element)> = []
  let shownPage = ref((#main: page))

  let showPage = page => {
    shownPage := page
    pageEls->Array.forEach(((p, e)) => e->toggleClass("on", p.page == page))
    pageButtons->Array.forEach(((p, b)) => b->toggleClass("on", p == page))
    menu->Menu.close
    pages->Array.find(p => p.page == page)->Option.forEach(p => status->Status.setIdle(p.hint))
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

  pageEls->Array.forEach(((p, e)) => p.build(ctx, e))

  //==============================================================================
  // header

  let button = (parent, text, title, onClick) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    b->onMouse(#click, _ => onClick())
    status->Status.hover(b, () => title)
    b
  }

  el("div", ~cls="brand", ~text="porridge", ~parent=head)->ignore
  let pagesBar = el("div", ~cls="pages", ~parent=head)
  pages->Array.forEach(({page, label, title}) =>
    pageButtons->Array.push((page, button(pagesBar, label, title, () => showPage(page))))
  )
  pageButtons->Array.forEach(((page, b)) => b->toggleClass("on", page == #main))
  el("div", ~cls="spacer", ~parent=head)->ignore

  let openProgramMenu = () =>
    menu->Menu.show(
      progName,
      Array.fromInitializer(~length=OatmealFormat.bankPrograms, i => {
        Menu.label: ProgramStore.number(i) ++ "  " ++ programs->ProgramStore.name(i),
        value: i,
      }),
      programs.current,
      i => programs->ProgramStore.select(i),
    )

  let renameProgram = () =>
    Controls.editInPlace(
      progName,
      programs->ProgramStore.name(programs.current),
      ~maxLength=Preset.maxNameLength,
      ~within=stage,
      ~commit=name => programs->ProgramStore.rename(programs.current, name),
    )

  let prog = el("div", ~cls="prog", ~parent=head)
  button(prog, "<", "Previous program", () =>
    programs->ProgramStore.select(programs.current - 1)
  )->ignore
  prog->appendChild(progName)
  progName->onMouse(#click, _ => openProgramMenu())
  progName->onMouse(#dblclick, _ => renameProgram())
  status->Status.hover(progName, () => "Click to pick a program, double-click to rename it")
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

  // a sample becomes a shape on the Shapes page (showing the page again would clear its undo)
  let importSample = file => {
    let here = shownPage.contents == #shapes
    if !here {
      showPage(#shapes)
    }
    shapesPage.contents->Option.forEach((s: PageShapes.t) => s.importSample(file, ~here))
  }
  let loadFile = file =>
    AudioFile.isAudio(file->fileName)
      ? importSample(file)
      : programs->ProgramStore.loadUserFile(file)->Promise.ignore
  let pickFile = FilePicker.make(stage, ~accept=[...Preset.extensions, ...Scala.extensions]->Array.join(","), loadFile)

  button(
    head,
    "Load",
    "Load a Porridge preset or bank (.porridge), an Oatmeal program or bank (.omp, .omb, .fxp, .fxb, .dat), or a Scala tuning (.scl, .kbm). You can also drop the file onto the window.",
    pickFile,
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
      let files = d->transferredFiles->filesToArray
      let sample = files->Array.find(f => AudioFile.isAudio(f->fileName))
      // a sample goes to the Shapes page; with the browser open, other files are added to it
      // instead of replacing the bank
      if sample->Option.isSome {
        sample->Option.forEach(loadFile)
      } else if browser->PresetBrowser.isOpen {
        browser->PresetBrowser.addFiles(files)
      } else {
        files[0]->Option.forEach(loadFile)
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
  updateProgramBar()
  status->Status.setIdle(PageMain.hint)

  // The patch's parameters and stored state arrive in one message (asking for each
  // parameter took about 450 round trips through the plugin's web view).
  let disposed = ref(false)
  pc->PatchConnection.requestFullStoredState(state =>
    if !disposed.contents {
      model->ParamModel.loadParameters(state.parameters->Option.getOr([]))
      programs->ProgramStore.loadState(state.values->Option.getOr(Dict.make()))
    }
  )

  {
    showPage,
    dispose: () => {
      disposed := true
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
