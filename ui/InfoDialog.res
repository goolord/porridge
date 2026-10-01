// The program info editor: name, author, category, tags and description of the current
// program, saved with it in Porridge presets.

open! Web

let categories = [
  "bass",
  "lead",
  "pad",
  "keys",
  "pluck",
  "bell",
  "brass",
  "strings",
  "organ",
  "arp",
  "sequence",
  "drum",
  "fx",
  "other",
]

@set external setPlaceholder: (element, string) => unit = "placeholder"
@set external setId: (element, string) => unit = "id"
@set external setList: (element, string) => unit = "list"
@send external setAttributeString: (element, string, string) => unit = "setAttribute"

let show = (ctx: Ctx.t, stage) => {
  let meta = ctx.programs->ProgramStore.meta
  let shade = el("div", ~cls="shade", ~parent=stage)
  let d = el("div", ~cls="dlg", ~parent=shade)
  el("div", ~cls="dttl", ~text="Program info", ~parent=d)->ignore

  let row = (label, input) => {
    let r = el("label", ~cls="drow", ~parent=d)
    el("span", ~text=label, ~parent=r)->ignore
    r->appendChild(input)
    input
  }
  let field = (label, value, ~placeholder="") => {
    let input = el("input")
    input->setValue(value)
    input->setPlaceholder(placeholder)
    row(label, input)
  }

  let name = field("name", meta.name)
  name->setMaxLength(Preset.maxNameLength)
  let author = field("author", meta.author)
  let category = field("category", meta.category, ~placeholder="e.g. pad")
  let list = el("datalist", ~parent=d)
  list->setId("pv-categories")
  categories->Array.forEach(c => el("option", ~parent=list)->setValue(c))
  category->setAttributeString("list", "pv-categories")
  let tags = field("tags", meta.tags->Array.join(", "), ~placeholder="comma separated")
  let description = row("description", el("textarea"))
  description->setValue(meta.description)

  let close = () => shade->remove
  let save = () => {
    ctx.programs->ProgramStore.setMeta({
      name: name->value->String.trim,
      author: author->value->String.trim,
      category: category->value->String.trim,
      tags: tags
      ->value
      ->String.split(",")
      ->Array.map(String.trim)
      ->Array.filter(t => t != ""),
      description: description->value->String.trim,
    })
    close()
  }

  let buttons = el("div", ~cls="dbtns", ~parent=d)
  let ok = el("button", ~cls="btn", ~text="OK", ~parent=buttons)
  ok->onMouse(#click, _ => save())
  let cancel = el("button", ~cls="btn", ~text="Cancel", ~parent=buttons)
  cancel->onMouse(#click, _ => close())

  // keys stay in the dialog (the host may otherwise take them as shortcuts)
  d->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Escape" => close()
    | "Enter" if !(k->target === Obj.magic(description)) => save()
    | _ => ()
    }
  })
  shade->onPointer(#pointerdown, ev =>
    if ev->target === Obj.magic(shade) {
      close()
    }
  )
  name->focus
  name->select
}
