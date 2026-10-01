// The settings dialog: settings that belong to the user rather than to a program.

open! Web

let percent = zoom => Float.toString(Math.round(zoom * 100.)) ++ " %"

let show = (settings: Settings.t, stage) => {
  let shade = el("div", ~cls="shade", ~parent=stage)
  let d = el("div", ~cls="dlg", ~parent=shade)
  el("div", ~cls="dttl", ~text="Settings", ~parent=d)->ignore

  let row = el("div", ~cls="drow", ~parent=d)
  el("span", ~text="interface size", ~parent=row)->ignore
  let steps = el("div", ~cls="seg", ~parent=row)
  let stepButtons = Settings.zoomSteps->Array.map(zoom => {
    let b = el("button", ~cls="btn", ~text=percent(zoom), ~parent=steps)
    b->onMouse(#click, _ => {
      settings->Settings.setZoom(zoom)
      settings->Settings.save("zoom", Number(zoom))
    })
    (zoom, b)
  })
  let note = el("div", ~cls="dnote", ~parent=d)
  let remember = el("button", ~cls="btn", ~text="Open new windows at this size", ~parent=d)
  remember->onMouse(#click, _ => settings->Settings.save("zoom", Number(settings.zoom)))

  let update = () => {
    let available = settings->Settings.available
    let near = (a: float, b) => Math.abs(a - b) < 0.005
    stepButtons->Array.forEach(((zoom, b)) => {
      b->toggleClass("on", available && near(zoom, settings.zoom))
      b->toggleClass("off", !available)
    })
    let saved = settings->Settings.savedZoom
    note->setTextContent(
      available
        ? `This window is at ${percent(settings.zoom)}, new windows open at ${percent(
              saved,
            )}. Drag the window's corner to scale it in between.`
        : "Here the host sets the size of the window. In the CLAP plugin, this sets the size of the plugin window.",
    )
    remember->setStyle(
      "display",
      available && !near(saved, settings.zoom) ? "inline-block" : "none",
    )
  }
  let stopListening = settings->Settings.listen(update)
  settings->Settings.refresh
  update()

  let buttons = el("div", ~cls="dbtns", ~parent=d)
  let closeButton = el("button", ~cls="btn", ~text="Close", ~parent=buttons)
  let close = () => {
    stopListening()
    shade->remove
  }
  closeButton->onMouse(#click, _ => close())
  d->onKeyDown(k => {
    k->stopPropagation
    if k->key == "Escape" || k->key == "Enter" {
      close()
    }
  })
  shade->onPointer(#pointerdown, ev =>
    if ev->target === Obj.magic(shade) {
      close()
    }
  )
  closeButton->focus
}
