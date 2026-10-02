// The settings dialog: settings that belong to the user rather than to a program: the size of
// the interface, whether the preset browser plays a program when it's clicked, and the folders
// the plugin looks in for banks.

open! Web

let percent = zoom => Float.toString(Math.round(zoom * 100.)) ++ " %"

// a row: its label, and a column for its controls and notes
let row = (d, label) => {
  let r = el("div", ~cls="drow", ~parent=d)
  el("span", ~cls="dlbl", ~text=label, ~parent=r)->ignore
  el("div", ~cls="dcol", ~parent=r)
}

// the last part of a folder's path
let folderName = folder =>
  folder->String.split("/")->Array.flatMap(String.split(_, "\\"))->Array.findLast(p => p != "")->Option.getOr(folder)

let show = (settings: Settings.t, library: BankLibrary.t, stage) => {
  let dialog = Dialog.make(stage, "Settings")
  let d = dialog.element
  d->addClass("wide")

  //==============================================================================
  // interface size

  let size = row(d, "interface size")
  let steps = el("div", ~cls="seg", ~parent=size)
  let stepButtons = Settings.zoomSteps->Array.map(zoom => {
    let b = el("button", ~cls="btn", ~text=percent(zoom), ~parent=steps)
    b->onMouse(#click, _ => {
      settings->Settings.setZoom(zoom)
      settings->Settings.save("zoom", Number(zoom))
    })
    (zoom, b)
  })
  let sizeNote = el("div", ~cls="dnote", ~parent=size)
  let remember = el("button", ~cls="btn", ~text="Open new windows at this size", ~parent=size)
  remember->onMouse(#click, _ => settings->Settings.save("zoom", Number(settings.zoom)))

  //==============================================================================
  // preset browser

  let browser = row(d, "preset browser")
  let play = el("div", ~cls="tg", ~parent=browser)
  el("b", ~parent=play)->ignore
  el("span", ~text="Play a program when it's clicked", ~parent=play)->ignore
  play->onMouse(#click, _ => {
    settings->Settings.save(PresetBrowser.previewSetting, Boolean(!PresetBrowser.previewOn(settings)))
    // where nothing answers (cmaj play), the listeners aren't called
    play->toggleClass("on", PresetBrowser.previewOn(settings))
  })

  //==============================================================================
  // bank folders

  let banks = row(d, "bank folders")
  let folderList = el("div", ~cls="dfolders", ~parent=banks)
  let addRow = el("div", ~cls="daddrow", ~parent=banks)
  let folderInput = el("input", ~parent=addRow)
  folderInput->setPlaceholder("Paste a folder's path")
  folderInput->setSpellcheck(false)
  let addFolder = () => {
    library->BankLibrary.addFolder(folderInput->value)
    folderInput->setValue("")
  }
  let addButton = el("button", ~cls="btn", ~text="Add", ~parent=addRow)
  addButton->onMouse(#click, _ => addFolder())
  let rescan = el("button", ~cls="btn", ~text="Look again", ~parent=addRow)
  rescan->onMouse(#click, _ => library->BankLibrary.scan)
  let banksNote = el("div", ~cls="dnote", ~parent=banks)

  let close = ref(() => ())

  let renderFolders = () => {
    folderList->setTextContent("")
    library
    ->BankLibrary.folders
    ->Array.forEach(folder => {
      let r = el("div", ~cls="dfolder", ~parent=folderList)
      r->setAttribute("title", Str(folder))
      el("b", ~text=folderName(folder), ~parent=r)->ignore
      el("span", ~text=folder, ~parent=r)->ignore
      let x = el("button", ~cls="btn", ~text="✕", ~parent=r)
      x->setAttribute("title", Str("Stop looking in this folder"))
      x->onMouse(#click, _ => library->BankLibrary.removeFolder(folder))
    })
  }

  let update = () => {
    let available = settings->Settings.available
    let near = (a: float, b) => Math.abs(a - b) < 0.005
    stepButtons->Array.forEach(((zoom, b)) => {
      b->toggleClass("on", available && near(zoom, settings.zoom))
      b->toggleClass("off", !available)
    })
    let saved = settings->Settings.savedZoom
    sizeNote->setTextContent(
      available
        ? `This window is at ${percent(settings.zoom)}, new windows open at ${percent(
              saved,
            )}. Drag the window's corner to scale it in between.`
        : "Here the host sets the size of the window. In the CLAP plugin, this sets the size of the plugin window.",
    )
    remember->setStyle("display", available ? "" : "none")
    remember->toggleClass("off", near(saved, settings.zoom))

    play->toggleClass("on", PresetBrowser.previewOn(settings))

    renderFolders()
    addRow->setStyle("display", available ? "" : "none")
    rescan->setStyle("display", library->BankLibrary.folders != [] ? "" : "none")
    banksNote->setTextContent(
      available
        ? library.scanning
            ? "Looking for banks…"
            : "The preset browser lists the programs and banks in these folders and the folders inside them."
        : "Only the CLAP plugin keeps bank folders.",
    )
  }

  folderInput->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Enter" => addFolder()
    | "Escape" if folderInput->value != "" => folderInput->setValue("")
    | "Escape" => close.contents()
    | _ => ()
    }
  })

  let stopListening = settings->Settings.listen(update)
  let stopLibrary = library->BankLibrary.listen(update)
  settings->Settings.refresh
  update()

  close :=
    () => {
      stopListening()
      stopLibrary()
      dialog->Dialog.remove
    }
  let close = () => close.contents()
  dialog->Dialog.finish([("Close", close)], ~onEnter=close, ~close)->Array.forEach(focus)
}
