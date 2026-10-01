// What every control and page gets: the model, the bank, and the shared chrome.

type t = {
  model: ParamModel.t,
  pc: PatchConnection.t,
  status: Status.t,
  menu: Menu.t,
  programs: ProgramStore.t,
  // design-to-screen scale of the stage
  scale: unit => float,
  // switches to the shapes page and selects a shape
  openShape: OatmealFormat.table => unit,
  toast: string => unit,
}
