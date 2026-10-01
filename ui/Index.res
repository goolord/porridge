// Patch view entry point: Cmajor calls the default export with a PatchConnection.

open! Web

// A custom element, so that the view can let go of the patch connection when it is removed.
let elementClass: elementClass = %raw(`
  class extends HTMLElement {
    disconnectedCallback() { this.onDisconnect?.(); }
  }
`)

@set external setOnDisconnect: (element, unit => unit) => unit = "onDisconnect"
// For the UI preview: view.showPage("shapes")
@set external setShowPage: (element, View.page => unit) => unit = "showPage"

let default = pc => {
  if getCustomElement("porridge-view")->Option.isNone {
    defineCustomElement("porridge-view", elementClass)
  }
  let host = document->createElement("porridge-view")
  let view = View.make(host, pc)
  host->setOnDisconnect(view.dispose)
  host->setShowPage(view.showPage)
  host
}
