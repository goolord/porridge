// Shapes page: the two user oscillator waveforms and the two user LFO shapes.

open! Web

let hint = "Drag to draw, shift-click for a straight line, ctrl-drag to smooth. Right-click for tools."

type shape = {table: OatmealFormat.table, title: string, tab: string, bipolar: bool}

let shapes = [
  {table: Wave1, title: "oscillator 1 waveform", tab: "oscillator 1", bipolar: true},
  {table: Wave2, title: "oscillator 2 waveform", tab: "oscillator 2", bipolar: true},
  {table: LfoShape1, title: "lfo 1 shape", tab: "lfo 1", bipolar: false},
  {table: LfoShape2, title: "lfo 2 shape", tab: "lfo 2", bipolar: false},
]

let clipboard = ref(None)

type t = {
  select: OatmealFormat.table => unit,
  // redraws from the program store
  refresh: unit => unit,
}

let build = (ctx: Ctx.t, page) => {
  let blk = Controls.block(
    page,
    "",
    ~x=6.,
    ~y=6.,
    ~w=Style.designWidth - 12.,
    ~h=Style.designHeight - 30. - 12.,
  )
  let current = ref(0)
  let shape = () => shapes->Array.getUnsafe(current.contents)

  let title = el("div", ~cls="ttl left", ~parent=blk)
  title->setStyle("font-size", "16px")

  let specBox = {x: 10., y: 520., w: 1310., h: 158.}
  let spectrum = el("canvas", ~parent=blk)->placeBox(specBox)
  spectrum->setStyle("position", "absolute")
  spectrum->setCanvasWidth(specBox.w * 2.)
  spectrum->setCanvasHeight(specBox.h * 2.)
  let spectrumNote = el("div", ~cls="note", ~text="harmonics (dB, first 64)")

  let editorRef = ref(None)

  let drawSpectrum = () =>
    editorRef.contents->Option.forEach((editor: ShapeEditor.t) => {
      open Context2d
      let g = spectrum->getContext2d
      let (w, h) = (spectrum->canvasWidth, spectrum->canvasHeight)
      g->clearRect(0., 0., w, h)
      g->setFillStyle("rgba(236,227,196,0.45)")
      g->fillRect(0., 0., w, h)
      g->setStrokeStyle("#6f5f36")
      g->setLineWidth(2.)
      g->strokeRect(1., 1., w - 2., h - 2.)
      let d = editor.data
      let n = TypedArray.length(d)
      let bars = 64
      let barWidth = w / Int.toFloat(bars)
      g->setFillStyle(
        switch spectrum->getComputedStyle->getPropertyValue("--signal")->String.trim {
        | "" => "#1c3c73"
        | ink => ink
        },
      )
      let mean = shape().bipolar ? 0. : ShapeEditor.sum(d) / Int.toFloat(n)
      let magnitudes = Array.fromInitializer(~length=bars, k => {
        let harmonic = Int.toFloat(k + 1)
        let re = ref(0.)
        let im = ref(0.)
        for i in 0 to n - 1 {
          let a = 2. * Math.Constants.pi * harmonic * Int.toFloat(i) / Int.toFloat(n)
          let v = d->ByteView.getUnsafe(i) - mean
          re := re.contents + v * Math.cos(a)
          im := im.contents - v * Math.sin(a)
        }
        2. * Math.hypot(re.contents, im.contents) / Int.toFloat(n)
      })
      let peak = Math.maxMany([1e-9, ...magnitudes])
      magnitudes->Array.forEachWithIndex((m, k) => {
        let db = 20. * Math.log10(Math.max(m / peak, 1e-6))
        let f = Math.max(0., (db + 60.) / 60.)
        g->fillRect(
          Int.toFloat(k) * barWidth + 2.,
          h - 4. - f * (h - 8.),
          barWidth - 4.,
          f * (h - 8.),
        )
      })
    })

  let editor = ShapeEditor.make(
    ctx,
    blk,
    {x: 10., y: 60., w: 1310., h: 430.},
    ~points=512,
    ~bipolar=true,
    ~grid=16,
    ~onEdit=d => ctx.programs->ProgramStore.setShape(shape().table, d, ~commit=false),
    ~onCommit=d => {
      ctx.programs->ProgramStore.setShape(shape().table, d, ~commit=true)
      drawSpectrum()
    },
  )
  editorRef := Some(editor)
  blk->appendChild(spectrum)
  blk->appendChild(spectrumNote)
  spectrumNote->place(12., 500.)->ignore

  let apply = f => {
    editor->ShapeEditor.pushUndo
    f(editor.data)
    editor->ShapeEditor.draw
    ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit=true)
    drawSpectrum()
  }
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
    (
      "undo",
      () => {
        editor->ShapeEditor.undo
        ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit=true)
        drawSpectrum()
      },
    ),
  ]
  editor.menu = tools->Array.map(((label, f)) => {ShapeEditor.label, run: _ => f()})

  let tabs = []

  let select = i => {
    current := i
    let s = shape()
    title->setTextContent(s.title)
    tabs->Array.forEachWithIndex((tab, k) => tab->toggleClass("on", k == i))
    editor.bipolar = s.bipolar
    editor.gridDivs = 16
    editor.undoStack = []
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(s.table))
    let display = s.bipolar ? "block" : "none"
    spectrum->setStyle("display", display)
    spectrumNote->setStyle("display", display)
    drawSpectrum()
  }

  shapes->Array.forEachWithIndex((s, i) =>
    tabs->Array.push(
      Controls.button(ctx, blk, s.tab, ~x=10. + Int.toFloat(i) * 112., ~y=28., ~w=106., () =>
        select(i)
      ),
    )
  )
  let count = Int.toFloat(Array.length(tools))
  tools->Array.forEachWithIndex(((label, f), i) =>
    Controls.button(
      ctx,
      blk,
      label,
      ~x=1320. - (count - Int.toFloat(i)) * 68.,
      ~y=28.,
      ~w=62.,
      f,
    )->ignore
  )

  ctx.programs->ProgramStore.onShapes(() => {
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(shape().table))
    drawSpectrum()
  })
  select(0)

  {
    select: table => select(Math.Int.max(0, shapes->Array.findIndex(s => s.table == table))),
    refresh: () => select(current.contents),
  }
}
