// Shapes page: the two user oscillator waveforms, with their harmonics, and the two user LFO
// shapes.

open! Web

let hint = "Drag to draw, shift-click for a straight line, ctrl-drag to smooth. Right-click for tools. Click or drag the harmonics to set their levels and phases."

type shape = {table: OatmealFormat.table, tab: string, bipolar: bool}

let shapes = [
  {table: Wave1, tab: "osc 1 waveform", bipolar: true},
  {table: Wave2, tab: "osc 2 waveform", bipolar: true},
  {table: LfoShape1, tab: "lfo 1 shape", bipolar: false},
  {table: LfoShape2, tab: "lfo 2 shape", bipolar: false},
]

let clipboard = ref(None)

type t = {
  select: OatmealFormat.table => unit,
  // redraws from the program store
  refresh: unit => unit,
}

let build = (ctx: Ctx.t, page) => {
  let selectRef = ref(_ => ())
  let panel = Panel.make(
    page,
    ~tabs=shapes->Array.map(s => s.tab),
    ~bodies=false,
    ~onSelect=i => selectRef.contents(i),
    ~x=6.,
    ~y=6.,
    ~w=Style.designWidth - 12.,
    ~h=Style.pageHeight - 12.,
  )
  let blk = panel.el
  let width = panel.w - 22.
  let current = ref(0)
  let shape = () => shapes->Array.getUnsafe(current.contents)

  // osc waveforms have their harmonics under them; LFO shapes get the whole height
  let waveBox = {x: 10., y: 54., w: width, h: 232.}
  let lfoHeight = 446.

  let harmonicsRef = ref(None)
  let withHarmonics = f =>
    if shape().bipolar {
      harmonicsRef.contents->Option.forEach(f)
    }
  let refreshHarmonics = () => withHarmonics(HarmonicEditor.refresh)

  let editor = ShapeEditor.make(
    ctx,
    blk,
    waveBox,
    ~points=512,
    ~bipolar=true,
    ~grid=16,
    ~onEdit=d => {
      ctx.programs->ProgramStore.setShape(shape().table, d, ~commit=false)
      // (measured once a frame while drawing)
      withHarmonics(HarmonicEditor.refreshSoon)
    },
    ~onCommit=d => {
      ctx.programs->ProgramStore.setShape(shape().table, d, ~commit=true)
      refreshHarmonics()
    },
  )
  let harmonics = HarmonicEditor.make(
    ctx,
    blk,
    editor,
    ~levels={x: 10., y: 292., w: width, h: 128.},
    ~phases={x: 10., y: 426., w: width, h: 76.},
    ~onEdit=() => ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit=false),
    ~onCommit=() => ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit=true),
  )
  harmonicsRef := Some(harmonics)

  let apply = f => editor->ShapeEditor.apply(f)
  let generate = kind =>
    apply(d =>
      d->ShapeEditor.blit(shape().bipolar ? ShapeEditor.genWave(kind) : ShapeEditor.genLfo(kind))
    )

  let tools = [
    ("sine", () => generate(Sine)),
    ("saw", () => generate(Saw)),
    ("square", () => generate(Square)),
    ("triangle", () => generate(Triangle)),
    ("random", () => generate(Random)),
    ("fix", () => apply(d => ShapeEditor.fix(d, ~bipolar=shape().bipolar))),
    ("soften", () => apply(d => ShapeEditor.soften(d))),
    ("invert", () => apply(d => ShapeEditor.invert(d, ~bipolar=shape().bipolar))),
    ("reverse", () => apply(ShapeEditor.reverse)),
    (
      "copy",
      () => {
        clipboard := Some(TypedArray.copy(editor.data))
        ctx.toast("Copied the shape")
      },
    ),
    ("paste", () => clipboard.contents->Option.forEach(c => apply(d => d->ShapeEditor.blit(c)))),
    ("undo", () => editor->ShapeEditor.undo),
  ]
  editor.menu = tools->Array.map(((label, f)) => {ShapeEditor.label, run: _ => f()})

  let select = i => {
    current := i
    panel->Panel.show(i)
    let s = shape()
    editor.bipolar = s.bipolar
    editor.gridDivs = 16
    editor.undoStack = []
    editor->ShapeEditor.setHeight(s.bipolar ? waveBox.h : lfoHeight)
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(s.table))
    harmonics->HarmonicEditor.setVisible(s.bipolar)
    refreshHarmonics()
  }

  selectRef := select
  // the tools, right-aligned above the drawing
  let toolWidth = 64.
  let toolbar = Grid.make(
    ctx,
    blk,
    ~x=10. + width + Grid.columnGap - Int.toFloat(Array.length(tools)) * toolWidth,
    ~cw=toolWidth,
  )
  tools->Array.forEachWithIndex(((label, f), i) => toolbar->Grid.button(label, i, 0, f))

  ctx.programs->ProgramStore.onShapes(() => {
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(shape().table))
    refreshHarmonics()
  })
  select(0)

  {
    select: table => select(Math.Int.max(0, shapes->Array.findIndex(s => s.table == table))),
    refresh: () => select(current.contents),
  }
}
