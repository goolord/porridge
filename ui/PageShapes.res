// Shapes page: the two user oscillator waveforms, with their harmonics, and the two user LFO
// shapes. A sample dropped onto the window or picked with "sample…" becomes a waveform built
// from its harmonics, or an LFO shape from its volume (WaveImport).

open! Web

let hint = "Drag to draw, shift-click for a straight line, ctrl-drag to smooth. Right-click for tools. Click or drag the harmonics to set their levels and phases. Drop a sample to use its harmonics."

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
  // makes a shape from a sample: the shape showing if the page is ('here'), else an
  // oscillator waveform
  importSample: (file, ~here: bool) => unit,
  // what a sample dropped now would make, for the drop zone
  sampleDropText: (~here: bool) => string,
}

let sampleTool = "sample…"
let sampleStatus = "Build this waveform from the harmonics of a sample, or an LFO shape from its volume (WAV, AIFF, FLAC, MP3 or OGG). You can also drop the sample onto the window."

// whether a drag holds a sound file (browsers that don't say what's being dragged give false)
type dragItem
type dragItemList
@get external dragItems: dataTransfer => dragItemList = "items"
@val external itemsToArray: dragItemList => array<dragItem> = "Array.from"
@get external itemKind: dragItem => string = "kind"
@get external itemType: dragItem => string = "type"

let dragHasSample = (ev: Dom.dragEvent) =>
  ev
  ->dataTransfer
  ->Option.mapOr(false, d =>
    d
    ->dragItems
    ->itemsToArray
    ->Array.some(i => i->itemKind == "file" && i->itemType->String.startsWith("audio/"))
  )

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

  //==============================================================================
  // samples

  let analyse = (source, position) =>
    shape().bipolar ? WaveImport.analyse(source, position) : WaveImport.envelope(source)
  // a waveform from a recording or a wavetable can come from other parts of it
  let scrubs = (source: WaveImport.t) =>
    shape().bipolar &&
    switch source.kind {
    | Cycle => false
    | Frames(_) | Recording => true
    }
  let setFromSample = (a: WaveImport.analysis, ~commit) => {
    editor.data->ShapeEditor.blit(a.wave)
    editor->ShapeEditor.draw
    ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit)
    refreshHarmonics()
  }
  let stripRef = ref(None)
  let strip = (~toolbarX) => {
    let s = SampleStrip.make(
      ctx,
      blk,
      {x: 10., y: Grid.padTop, w: toolbarX - Grid.columnGap - 10., h: Style.controlHeight},
      ~onStart=() => editor->ShapeEditor.pushUndo,
      ~onPick=position =>
        stripRef.contents->Option.forEach((s: SampleStrip.t) =>
          s.source->Option.forEach(source =>
            switch analyse(source, position) {
            | Ok(a) =>
              setFromSample(a, ~commit=false)
              s->SampleStrip.update(a)
            | Error(e) => ctx.status->Status.show(e)
            }
          )
        ),
      ~onEnd=() => ctx.programs->ProgramStore.setShape(shape().table, editor.data, ~commit=true),
    )
    stripRef := Some(s)
    s
  }
  let hideStrip = () => stripRef.contents->Option.forEach(SampleStrip.hide)
  ctx.programs->ProgramStore.onChanged(hideStrip)

  // an LFO shape only takes a sample while it's showing
  let sampleTab = (~here) => here || shape().bipolar ? current.contents : 0

  let importSample = async (file, ~here) => {
    let tab = sampleTab(~here)
    let source = (await AudioFile.readFile(file))->Result.flatMap(WaveImport.make(file->fileName, _))
    try {
      switch source {
      | Error(e) => ctx.toast(e)
      | Ok(source) =>
        if current.contents != tab {
          selectRef.contents(tab)
        }
        switch analyse(source, WaveImport.defaultPosition(source)) {
        | Error(e) => ctx.toast(e)
        | Ok(a) =>
          editor->ShapeEditor.pushUndo
          setFromSample(a, ~commit=true)
          stripRef.contents->Option.forEach(s => s->SampleStrip.show(source, a, ~scrubs=scrubs(source)))
        }
      }
    } catch {
    | JsExn(e) => ctx.toast(readError(file, e))
    }
  }

  let pickSample = FilePicker.make(blk, ~accept=AudioFile.accept, file =>
    importSample(file, ~here=true)->Promise.ignore
  )
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
    (sampleTool, pickSample),
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
  // the tools save their own undo steps and commit, as on the toolbar
  editor.menu =
    tools->Array.map(((label, f)) => {ShapeEditor.label, run: _ => f()})

  let select = i => {
    if i != current.contents {
      hideStrip()
    }
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
  // the tools, right-aligned above the drawing; the sample a shape came from, left of them
  let toolWidth = 58.
  let toolbarX = 10. + width + Grid.columnGap - Int.toFloat(Array.length(tools)) * toolWidth
  let toolbar = Grid.make(ctx, blk, ~x=toolbarX, ~cw=toolWidth)
  tools->Array.forEachWithIndex(((label, f), i) =>
    toolbar->Grid.button(label, i, 0, ~status=?label == sampleTool ? Some(sampleStatus) : None, f)
  )
  strip(~toolbarX)->ignore

  ctx.programs->ProgramStore.onShapes(() => {
    editor->ShapeEditor.set(ctx.programs->ProgramStore.shape(shape().table))
    refreshHarmonics()
  })
  select(0)

  {
    select: table => select(Math.Int.max(0, shapes->Array.findIndex(s => s.table == table))),
    refresh: () => select(current.contents),
    importSample: (file, ~here) => importSample(file, ~here)->Promise.ignore,
    sampleDropText: (~here) => {
      let s = shapes->Array.getUnsafe(sampleTab(~here))
      s.bipolar
        ? `Drop to build the ${s.tab} from the sample's harmonics`
        : `Drop to make the ${s.tab} from the sample's volume`
    },
  }
}
