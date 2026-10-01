// Starting a new bank, for someone writing one: 64 Init programs, the bank's name (saved with it,
// and the name of its file) and the author every program starts with.

open! Web

let show = (ctx: Ctx.t, stage) => {
  let programs = ctx.programs
  let dialog = Dialog.make(stage, "New bank")
  let d = dialog.element

  let field = (label, value, ~placeholder) => {
    let r = el("label", ~cls="drow", ~parent=d)
    el("span", ~text=label, ~parent=r)->ignore
    let input = el("input", ~parent=r)
    input->setValue(value)
    input->setPlaceholder(placeholder)
    input
  }
  let name = field("bank name", programs.bankName, ~placeholder="the name of the bank and its file")
  let author = field("author", (programs->ProgramStore.meta).author, ~placeholder="written into every program")
  el(
    "div",
    ~cls="dnote",
    ~text=`Replaces the ${Int.toString(
        OatmealFormat.bankPrograms,
      )} programs in the bank with Init programs. Save the bank first to keep it.`,
    ~parent=d,
  )->ignore

  let close = () => dialog->Dialog.remove
  let create = () => {
    programs->ProgramStore.newBank(~name=name->value->String.trim, ~author=author->value->String.trim)
    close()
  }
  let save = () => programs->ProgramStore.downloadBank

  dialog
  ->Dialog.finish([("New bank", create), ("Save the bank first", save), ("Cancel", close)], ~onEnter=create, ~close)
  ->ignore
  name->focus
  name->select
}
