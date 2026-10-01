// A hidden file input: the function it returns opens the file dialog, and onFile gets the
// file picked there.

open! Web

let make = (parent, ~accept, onFile) => {
  let input = el("input", ~parent)
  input->setInputType("file")
  input->setAccept(accept)
  input->setStyle("display", "none")
  input->onEvent(#change, _ => {
    input->files->Option.flatMap(item(_, 0))->Option.forEach(onFile)
    input->setValue("")
  })
  () => input->click
}
