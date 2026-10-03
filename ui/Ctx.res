// What every control and page gets: the model, the bank, and the shared chrome.

type t = {
  model: ParamModel.t,
  pc: PatchConnection.t,
  status: Status.t,
  menu: Menu.t,
  programs: ProgramStore.t,
  // the host's parameter menu, on a shift+right-click
  hostMenu: HostMenu.t,
  // design-to-screen scale of the stage
  scale: unit => float,
  // opens the shapes editor over the page, on a shape
  openShape: OatmealFormat.table => unit,
  // switches to a page
  openPage: [#main | #mod | #fx | #play] => unit,
  // switches to the FX page and opens an effect's tab
  openEffect: FxRack.effect => unit,
  toast: string => unit,
}
