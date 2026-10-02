// The patch view: pages on a fixed-size stage that is scaled to fit the window, a header with
// the page tabs, the program (with its A/B versions) and a menu of the file and program
// commands, the shapes editor over the pages, search (Palette) and a status line. Everywhere but
// in a text field: undo and redo (ParamModel's history) on ctrl+Z and ctrl+shift+Z / ctrl+Y,
// search on ctrl+K or "/", and the arrow keys, Enter and Delete go to the control under the
// pointer when none has the keyboard.

open! Web

@send external onMouseOver: (element, @as("mouseover") _, Dom.mouseEvent => unit) => unit = "addEventListener"
@new
external keyboardEvent: (
  string,
  {"key": string, "shiftKey": bool, "ctrlKey": bool, "metaKey": bool, "altKey": bool},
) => Dom.keyboardEvent = "KeyboardEvent"
@send external dispatchKey: (element, Dom.keyboardEvent) => bool = "dispatchEvent"

type page = [#main | #mod | #fx | #play]

// what showPage can show: a page, or the shapes editor over it
type view = [page | #shapes]

// A page: its tab's label and status text, its hint for the status line, and what builds it.
type pageSpec = {
  page: page,
  label: string,
  title: string,
  hint: string,
  build: (Ctx.t, element) => unit,
}

type t = {
  showPage: view => unit,
  // lets go of the patch connection
  dispose: unit => unit,
}

let oatModeHelp = "Oat mode keeps Oatmeal's MIDI timing (notes, controllers and arpeggiator steps start on the next 64-sample block, not on their own sample) and its legato quirk: a stereo voice's right filter envelopes never start. It is saved with the program."

// two presses of Escape this close together stop every note
let panicMs = 400.

let make = (host, pc) => {
  // A scratch v38 program holding the current values, used as the context for status texts
  // (several texts depend on other fields: octave size, tuning, breakpoint, targets...).
  let context = OatmealFormat.makeDefaultProgram("Init")
  let defs = ParamDefs.makeDefs(~context=() => Some(context))
  Preset.useDefs(defs)
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

  let fontFace = el("style", ~text=Style.fontFace, ~parent=document->documentElement)
  let shadow = host->attachShadow({mode: "open"})
  el("style", ~text=Style.css, ~parent=shadow)->ignore
  let stage = el("div", ~cls="pv-stage", ~parent=shadow)
  let head = el("div", ~cls="pv-head", ~parent=stage)
  let msg = el("div", ~cls="pv-status", ~parent=stage)
  let status = Status.make(msg)
  let menu = Menu.make(stage, ~status)
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
  let progText = el("span", ~parent=progName)
  let pencil = el("span", ~cls="pen", ~text="✎", ~parent=progName)
  el("span", ~cls="arrow", ~text="▾", ~parent=progName)->ignore
  let programs = ProgramStore.make(pc, model, ~onMessage=toast)
  let updateProgramBar = () =>
    progText->setTextContent(
      ProgramStore.number(programs.current) ++ "  " ++ programs->ProgramStore.name(programs.current),
    )
  programs->ProgramStore.onChanged(updateProgramBar)

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
      label: "Play",
      title: "Macros, the arpeggiator, the XY pad, the wheels and the MIDI input",
      hint: PagePlay.hint,
      build: PagePlay.build,
    },
  ]
  let pageEls =
    pages->Array.map(p => (p, el("div", ~cls=p.page == #main ? "pv-page on" : "pv-page", ~parent=stage)))
  let pageButtons: array<(page, element)> = []
  let shownPage = ref((#main: page))
  let pageHint = page => pages->Array.find(p => p.page == page)->Option.mapOr("", p => p.hint)

  // the shapes editor, over the pages
  let overlay = el("div", ~cls="pv-overlay", ~parent=stage)
  let shapes = ref(None)
  let shapesShown = ref(false)
  let shapesOpen = () => shapesShown.contents
  let closeShapes = () =>
    if shapesOpen() {
      shapesShown := false
      overlay->removeClass("on")
      status->Status.setIdle(pageHint(shownPage.contents))
    }
  // (opening it again would clear its undo, so it only redraws when it wasn't open)
  let openShapes = () =>
    if !shapesOpen() {
      shapesShown := true
      menu->Menu.close
      overlay->addClass("on")
      status->Status.setIdle(ShapesOverlay.hint)
      shapes.contents->Option.forEach((s: ShapesOverlay.t) => s.refresh())
    }

  let showPage = page => {
    closeShapes()
    shownPage := page
    pageEls->Array.forEach(((p, e)) => e->toggleClass("on", p.page == page))
    pageButtons->Array.forEach(((p, b)) => b->toggleClass("on", p == page))
    menu->Menu.close
    status->Status.setIdle(pageHint(page))
  }
  // (search goes to a control on its page)
  pageEls->Array.forEach(((p, e)) => Reach.place(e, p.label, () => showPage(p.page)))

  let ctx: Ctx.t = {
    model,
    pc,
    status,
    menu,
    programs,
    hostMenu,
    scale: () => scale.contents,
    openEffect: e => {
      showPage(#fx)
      PageFx.openEffect.contents(e)
    },
    openShape: table => {
      openShapes()
      shapes.contents->Option.forEach((s: ShapesOverlay.t) => s.select(table))
    },
    openPage: showPage,
    toast,
  }

  // (the routes' texts name the macros as the program does)
  model->Modulators.nameMacros(programs)
  pageEls->Array.forEach(((p, e)) => p.build(ctx, e))
  shapes := Some(ShapesOverlay.build(ctx, overlay, ~onClose=closeShapes))
  ModTray.make(ctx, stage)

  //==============================================================================
  // header

  let button = (parent, text, title, onClick) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    b->onMouse(#click, _ => onClick())
    status->Status.hover(b, () => title)
    b
  }
  let iconButton = (parent, icon, title, onClick) => {
    let b = button(parent, "", title, onClick)
    b->addClass("icon")
    b->appendChild(Icons.render(icon))
    b
  }

  el("div", ~cls="brand", ~text="porridge", ~parent=head)->ignore
  let pagesBar = el("div", ~cls="pages", ~parent=head)
  pages->Array.forEach(({page, label, title}) =>
    pageButtons->Array.push((page, button(pagesBar, label, title, () => showPage(page))))
  )
  pageButtons->Array.forEach(((page, b)) => b->toggleClass("on", page == #main))
  // the selected modulation source dims the stage and is counted on the pages' tabs
  model->ModFocus.attach(
    ~stage,
    ~pages=pageEls->Array.filterMap(((p, e)) =>
      pageButtons->Array.find(((page, _)) => page == p.page)->Option.map(((_, b)) => (e, b))
    ),
  )
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

  let renameProgram = () => {
    menu->Menu.close
    Controls.editInPlace(
      progName,
      programs->ProgramStore.name(programs.current),
      ~maxLength=Preset.maxNameLength,
      ~within=stage,
      ~commit=name =>
        if name != programs->ProgramStore.name(programs.current) {
          programs->ProgramStore.rename(programs.current, name)
        },
    )
  }

  let prog = el("div", ~cls="prog", ~parent=head)
  button(prog, "‹", "Previous program", () =>
    programs->ProgramStore.select(programs.current - 1)
  )->ignore
  prog->appendChild(progName)
  progName->onMouse(#click, _ => openProgramMenu())
  progName->onMouse(#dblclick, _ => renameProgram())
  pencil->onMouse(#click, ev => {
    ev->stopPropagation
    renameProgram()
  })
  status->Status.hover(progName, () => "Click to pick a program of the bank; double-click (or the pencil) to rename it")
  button(prog, "›", "Next program", () =>
    programs->ProgramStore.select(programs.current + 1)
  )->ignore

  // A/B: the program's two versions, the live one lit (B is dim until it is made)
  let compareText = () => {
    let live = ProgramStore.slotName(programs->ProgramStore.slot)
    let other = ProgramStore.slotName(ProgramStore.otherSlot(programs->ProgramStore.slot))
    programs->ProgramStore.hasOther
      ? `Compare: ${live} is playing. Click ${other} to hear the other version (undo takes a switch back); ≡ copies ${live} to ${other}. The version that isn't playing is kept until the window closes, not saved.`
      : "Compare: click B to try changes on a copy of this program, then switch between A and B to hear which is better. B is kept until the window closes; what plays is what's saved."
  }
  let compare = el("div", ~cls="ab", ~parent=prog)
  let slotButtons = [ProgramStore.A, B]->Array.map(s => {
    let b = el("span", ~text=ProgramStore.slotName(s), ~parent=compare)
    b->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->Web.button == 0 && programs->ProgramStore.slot != s {
        programs->ProgramStore.switchSlot
      }
    })
    (s, b)
  })
  status->Status.hover(compare, compareText)
  let updateCompare = () => {
    slotButtons->Array.forEach(((s, b)) => b->toggleClass("on", programs->ProgramStore.slot == s))
    compare->toggleClass("two", programs->ProgramStore.hasOther)
  }
  programs->ProgramStore.onChanged(updateCompare)
  updateCompare()

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

  let randomizer = RandomDrawer.make(ctx, stage, settings)
  button(
    head,
    "Random",
    "Make random patches, as wild as you like in each part, and variations of them or of this program",
    () => randomizer.isOpen() ? randomizer.hide() : randomizer.show(),
  )->ignore

  // a sample becomes a shape in the shapes editor
  let importSample = file => {
    let here = shapesOpen()
    openShapes()
    shapes.contents->Option.forEach((s: ShapesOverlay.t) => s.importSample(file, ~here))
  }
  let loadFile = file =>
    AudioFile.isAudio(file->fileName)
      ? importSample(file)
      : programs->ProgramStore.loadUserFile(file)->Promise.ignore
  let pickFile = FilePicker.make(stage, ~accept=[...Preset.extensions, ...Scala.extensions]->Array.join(","), loadFile)

  let panic = () => programs->ProgramStore.panic
  let panicTitle = "Panic: stop every note and clear the effects' tails (or press Escape twice)"
  // (a square, as on a transport's stop button)
  iconButton(head, {width: 14., marks: [Fill("M2.5 3.5 H11.5 V12.5 H2.5 Z")]}, panicTitle, panic)->addClass("panic")

  let undo = () =>
    if shapesOpen() {
      shapes.contents->Option.forEach((s: ShapesOverlay.t) => s.undo())
    } else {
      switch model->ParamModel.undo {
      | Some(label) => toast("Undid " ++ label)
      | None => toast("Nothing to undo")
      }
    }
  let redo = () =>
    if !shapesOpen() {
      switch model->ParamModel.redo {
      | Some(label) => toast("Redid " ++ label)
      | None => toast("Nothing to redo")
      }
    }

  let oatMode = () => model->ParamModel.get("Oat_Mode") != 0.
  let switchOatMode = () => model->ParamModel.gestureSet("Oat_Mode", oatMode() ? 0. : 1.)
  let showSettings = () => SettingsDialog.show(settings, browser.library, stage)
  let compareLabels = () => {
    let live = programs->ProgramStore.slot
    let (a, b) = (ProgramStore.slotName(live), ProgramStore.slotName(ProgramStore.otherSlot(live)))
    (`Switch to ${b}`, `Copy ${a} to ${b}`)
  }

  // search: the menu's commands and the header's, by name
  let palette = Palette.make(ctx, stage, ~commands=() => {
    let command = (label, ~words="", ~keys="", run) => {Palette.label, words, keys, run}
    let (switchLabel, copyLabel) = compareLabels()
    [
      command("undo " ++ model->ParamModel.undoLabel->Option.getOr(""), ~keys="ctrl+Z", undo),
      command("redo " ++ model->ParamModel.redoLabel->Option.getOr(""), ~keys="ctrl+shift+Z", redo),
      command("init program", ~words="reset new patch", () => programs->ProgramStore.initCurrent),
      command("random patches", ~words="randomize generate dice vary", () => randomizer.show()),
      command("browse presets", ~words="browser bank programs find", ~keys="ctrl+F", browse),
      command("load a file", ~words="open import preset bank tuning scala", pickFile),
      command("save program", ~words="download preset", () => programs->ProgramStore.downloadProgram),
      command("save bank", ~words="download", () => programs->ProgramStore.downloadBank),
      command("export program for Oatmeal", ~words="omp", () => programs->ProgramStore.exportOatmealProgram),
      command("export bank for Oatmeal", ~words="omb", () => programs->ProgramStore.exportOatmealBank),
      command("program info", ~words="author category tags description", () => InfoDialog.show(ctx, stage)),
      command("rename program", ~words="name", renameProgram),
      command("new bank", ~words="init programs", () => NewBankDialog.show(ctx, stage)),
      command("next program", () => programs->ProgramStore.select(programs.current + 1)),
      command("previous program", () => programs->ProgramStore.select(programs.current - 1)),
      command(switchLabel, ~words="compare a b ab version", () => programs->ProgramStore.switchSlot),
      command(copyLabel, ~words="compare a b ab version", () => programs->ProgramStore.copyToOther),
      command("shapes editor", ~words="draw user waveform wave lfo shape sample", openShapes),
      command(oatMode() ? "Oat mode off" : "Oat mode on", ~words="oatmeal timing compatibility", switchOatMode),
      command("panic", ~words="stop all notes", ~keys="Esc Esc", panic),
      command("settings", ~words="preferences options interface size midi folders", showSettings),
    ]
  })

  // the menu of everything else: files, the program, the bank, A/B, undo, search, Oat mode and panic
  let menuButton = button(
    head,
    "≡",
    "Load and save, export for Oatmeal, program info, init, compare A/B, undo, search, Oat mode, panic",
    () => (),
  )
  menuButton->addClass("icon")
  menuButton->addClass("menu-btn")
  menuButton->onMouse(#click, _ => {
    let (switchLabel, copyLabel) = compareLabels()
    let undoLabel = model->ParamModel.undoLabel
    let redoLabel = model->ParamModel.redoLabel
    // (every item has a place for a check mark, which Oat mode's takes)
    let item = (label, value, ~rule=false, ~hint=?, ~keys=?, ~disabled=false, ~checked=false) => {
      Menu.label,
      value,
      rule,
      ?hint,
      ?keys,
      disabled,
      checked,
    }
    menu->Menu.show(
      menuButton,
      [
        item(
          "Load…",
          0,
          ~hint="Load a Porridge preset or bank (.porridge), an Oatmeal program or bank (.omp, .omb, .fxp, .fxb, .dat), or a Scala tuning (.scl, .kbm). You can also drop the file onto the window.",
        ),
        item("Save program", 1, ~hint="Save this program as a .porridge file"),
        item("Save bank", 2, ~hint=`Save the whole bank, all ${Int.toString(OatmealFormat.bankPrograms)} programs, as a .porridge file`),
        item("Export program for Oatmeal", 3, ~hint="Save this program as an Oatmeal program (.omp); what Oatmeal can't store is left out"),
        item("Export bank for Oatmeal", 4, ~hint="Save the bank as an Oatmeal bank (.omb); what Oatmeal can't store is left out"),
        item("Program info…", 5, ~rule=true, ~hint="Name, author, category, tags and description of this program"),
        item("Init program", 6, ~hint="Reset this program to the Init patch (undo takes it back)"),
        item(
          `New bank of ${Int.toString(OatmealFormat.bankPrograms)} Init programs…`,
          7,
          ~hint="Start a bank of your own: every program Init, with your name as their author",
        ),
        item(switchLabel, 12, ~rule=true, ~hint=compareText()),
        item(copyLabel, 13, ~hint="Make the other version a copy of this one, to try changes on"),
        item(
          undoLabel->Option.mapOr("Undo", l => "Undo " ++ l),
          8,
          ~rule=true,
          ~keys="ctrl+Z",
          ~disabled=undoLabel == None,
        ),
        item(
          redoLabel->Option.mapOr("Redo", l => "Redo " ++ l),
          9,
          ~keys="ctrl+shift+Z",
          ~disabled=redoLabel == None,
        ),
        item(
          "Search…",
          14,
          ~keys="ctrl+K",
          ~hint="Find any control, page or command by name, and go to it (or press / anywhere)",
        ),
        item("Oat mode", 10, ~rule=true, ~hint=oatModeHelp, ~checked=oatMode()),
        item("Panic", 11, ~rule=true, ~keys="Esc Esc", ~hint=panicTitle),
      ],
      -1,
      i =>
        switch i {
        | 0 => pickFile()
        | 1 => programs->ProgramStore.downloadProgram
        | 2 => programs->ProgramStore.downloadBank
        | 3 => programs->ProgramStore.exportOatmealProgram
        | 4 => programs->ProgramStore.exportOatmealBank
        | 5 => InfoDialog.show(ctx, stage)
        | 6 => programs->ProgramStore.initCurrent
        | 7 => NewBankDialog.show(ctx, stage)
        | 8 => undo()
        | 9 => redo()
        | 10 => switchOatMode()
        | 12 => programs->ProgramStore.switchSlot
        | 13 => programs->ProgramStore.copyToOther
        | 14 => palette.show()
        | _ => panic()
        },
    )
  })

  iconButton(head, Icons.gear, "Settings: interface size, preset browser, bank folders", showSettings)->ignore

  stage->appendChild(toastEl)

  //==============================================================================
  // keys

  // the control under the pointer, which the arrow keys, Enter and Delete go to while no control
  // has the keyboard (Controls: nudge it, type its value, reset it)
  let hovered = ref(None)
  stage->onMouseOver(ev => hovered := Reach.controlAt(ev)->Option.map(Pair.first))
  stage->onMouse(#mouseleave, _ => hovered := None)
  let toHovered = k =>
    switch hovered.contents {
    | Some(e) if Reach.controlAt(k)->Option.isNone && Reach.isConnected(e) && Reach.isShown(e) =>
      k->preventDefault
      e
      ->dispatchKey(
        keyboardEvent(
          "keydown",
          {"key": k->key, "shiftKey": k->shiftKey, "ctrlKey": k->ctrlKey, "metaKey": k->metaKey, "altKey": k->altKey},
        ),
      )
      ->ignore
    | _ => ()
    }

  let lastEscape = ref(0.)
  let onKey = k =>
    if !BrowserChrome.inTextField(k) {
      let key = k->key->String.toLowerCase
      switch key {
      | "k" if k->commandKey =>
        k->preventDefault
        palette.show()
      | "/" if !(k->commandKey) =>
        k->preventDefault
        palette.show()
      | "arrowup" | "arrowdown" | "arrowleft" | "arrowright" | "enter" | "delete" | "backspace" => toHovered(k)
      | "f" if k->commandKey =>
        k->preventDefault
        browse()
      | "z" if k->commandKey =>
        k->preventDefault
        k->shiftKey ? redo() : undo()
      | "y" if k->commandKey =>
        k->preventDefault
        redo()
      | "escape" =>
        // (an Escape that closes something doesn't count towards a panic)
        let now = Date.now()
        if shapesOpen() {
          closeShapes()
          lastEscape := 0.
        } else if menu.menu->Option.isSome {
          menu->Menu.close
          lastEscape := 0.
        } else if model->ModFocus.clear {
          lastEscape := 0.
        } else if now - lastEscape.contents < panicMs {
          panic()
          toast("Panic: every note stopped")
          lastEscape := 0.
        } else {
          lastEscape := now
        }
      | _ => ()
      }
    }
  document->onDocumentKeyDown(onKey)

  //==============================================================================
  // drop zone

  let drop = el("div", ~cls="drop", ~text="Drop a Porridge or Oatmeal program or bank", ~parent=stage)
  let depth = ref(0)
  host->onDrag(#dragenter, e => {
    e->preventDefault
    depth := depth.contents + 1
    drop->setTextContent(
      switch shapes.contents {
      | Some(s) if ShapesOverlay.dragHasSample(e) => s.sampleDropText(~here=shapesOpen())
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
      // a sample goes to the shapes editor; with the browser open, other files are added to it
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
    showPage: v =>
      switch v {
      | #shapes => openShapes()
      | #...page as page => showPage(page)
      },
    dispose: () => {
      disposed := true
      resizeObserver->disconnect
      document->offDocumentKeyDown(onKey)
      restoreBrowserChrome()
      fontFace->remove
      settings->Settings.dispose
      hostMenu->HostMenu.dispose
      randomizer.dispose()
      browser->PresetBrowser.dispose
      model->ParamModel.dispose
      programs->ProgramStore.dispose
      VoiceView.stop(pc)
    },
  }
}
