// Synth page: the sound sources, filter and amp on top, modulation and voice settings
// below. Panels with tabs keep one group of controls on screen at a time; envelopes are
// edited by dragging their points.

open! Web

let hint = "Drag or scroll to change a value, shift for fine steps. Double-click to type, right-click to reset. Click a list to pick from it, right-click to step through it."

let (margin, gap) = (6., Grid.gap)
let columnWidth = 358.
let rowHeight = (Style.pageHeight - 2. * margin - gap) / 2.

let envelopeFields = prefix => [
  (prefix ++ "Attack", "attack"),
  (prefix ++ "Hold", "hold"),
  (prefix ++ "Decay1", "decay 1"),
  (prefix ++ "Breakpoint", "breakpoint"),
  (prefix ++ "Decay2", "decay 2"),
  (prefix ++ "Sustain", "sustain"),
  (prefix ++ "Release", "release"),
  ...EnvEditor.curveIds(prefix)->Array.mapWithIndex((id, i) => (
    id,
    ["attack curve", "decay 1 curve", "decay 2 curve", "release curve"]->Array.getUnsafe(i),
  )),
]

// (each sounding note is marked where it is on the amp, filter and mod envelopes)
let envelope = (ctx, parent, prefix, box: box, ~name) =>
  EnvEditor.make(
    ctx,
    parent,
    box,
    EnvEditor.adsr(ctx, prefix, ~w=box.w, ~h=box.h),
    ~fields=envelopeFields(prefix),
    ~name,
    ~clock=?switch prefix {
    | "" => Some((v: VoiceView.voice) => v.ampMs)
    | "F_" => Some(v => v.filterMs)
    | "M1_" => Some(v => v.mod1Ms)
    | "M2_" => Some(v => v.mod2Ms)
    | _ => None
    },
  )

// The button in the corner of a plot that opens its table on the Shapes page.
let drawButton = (ctx: Ctx.t, body, plot: box, ~status, table) =>
  Controls.button(
    ctx,
    body,
    "draw",
    ~x=plot.x + plot.w - 48.,
    ~y=plot.y + plot.h - 23.,
    ~w=44.,
    ~status,
    () => ctx.openShape(table),
  )->ignore

let oscillator = (ctx: Ctx.t, body, n) => {
  let osc = Int.toString(n)
  let prefix = `O${osc}_`
  let plot = {x: 8., y: 27., w: 340., h: 110.}
  Plots.wave(ctx, body, n - 1, plot)
  drawButton(ctx, body, plot, ~status=`Draw oscillator ${osc}'s user waveform`, n == 1 ? Wave1 : Wave2)
  let g = Grid.make(ctx, body, ~y=plot.y + plot.h + 8.)
  g->Grid.choice(prefix ++ "Waveform", 0, 0, "waveform")
  g->Grid.param(prefix ++ "Amp", 1, 0, "amp")
  g->Grid.param(prefix ++ "PWM_W", 2, 0, "pulsewidth")
  g->Grid.param(prefix ++ "Afterpitch", 3, 0, "touch > pitch")
  g->Grid.param(prefix ++ "PWM_R", 0, 1, "pwm rate")
  g->Grid.param(prefix ++ "PWM_D", 1, 1, "pwm depth")
  if n == 2 {
    g->Grid.param("Transpose", 2, 1, "transpose")
    g->Grid.param("Detune", 3, 1, "detune")
  }
  g->Grid.choice("OscMix", 0, 2, "mix", ~span=2)
  g->Grid.param("OscAftertouch", 2, 2, "touch > amp")
  g->Grid.param("PM_Feedback", 3, 2, "pm feedback")
  // its noise: the pitch roughened every sample
  g->Grid.param(prefix ++ "Noise", 0, 3, "noise")
  g->Grid.param(prefix ++ "NoiseColour", 1, 3, "noise colour")
  if n == 2 {
    g->Grid.param("O2_PairMix", 2, 3, "heard in pm")
  }
}

let modEnvelope = (ctx: Ctx.t, body, n, box) => {
  let prefix = `M${Int.toString(n)}_`
  envelope(ctx, body, prefix, box, ~name=`Mod envelope ${Int.toString(n)}`)
  let g = Grid.make(ctx, body, ~x=box.x + box.w + 10.)
  g->Grid.param(prefix ++ "VeloSens", 0, 0, "velocity")
  for k in 1 to 4 {
    let slot = Int.toString(k)
    g->Grid.choice(`${prefix}Target_${slot}`, 0, k, "target " ++ slot, ~span=2)
    g->Grid.param(`${prefix}Depth_${slot}`, 2, k, "depth")
  }
}

let lfo = (ctx: Ctx.t, body, n, box: box) => {
  let lfo = Int.toString(n)
  let prefix = `LFO_${lfo}_`
  Plots.lfo(ctx, body, n - 1, box)
  drawButton(ctx, body, box, ~status=`Draw LFO ${lfo}'s user shape`, n == 1 ? LfoShape1 : LfoShape2)
  let g = Grid.make(ctx, body, ~x=box.x + box.w + 10.)
  g->Grid.choice(prefix ++ "Shape", 0, 0, "shape")
  g->Grid.at(1, 0, ~span=2, prefix ++ "Sync", b => Controls.lfoMode(ctx, body, prefix ++ "Sync", ~x=b.x, ~y=b.y, ~w=b.w))
  g->Grid.choice(prefix ++ "Unit", 0, 1, "unit")
  g->Grid.param(prefix ++ "Speed", 1, 1, "rate")
  g->Grid.toggle(prefix ++ "Quantize", 2, 1, "quantize")
  g->Grid.param(prefix ++ "Cutoff_1", 0, 2, "cut 1")
  g->Grid.param(prefix ++ "Cutoff_2", 1, 2, "cut 2")
  g->Grid.param(prefix ++ "Resonance", 2, 2, "res")
  g->Grid.param(prefix ++ "Pitch", 0, 3, "pitch")
  g->Grid.param(prefix ++ "Pan", 1, 3, "pan")
  g->Grid.param(n == 1 ? "LFO_1_2" : "LFO_2_1", 2, 3, n == 1 ? "rate 2" : "rate 1")
  g->Grid.param(prefix ++ "Delay", 0, 4, "delay")
  g->Grid.param(prefix ++ "Fade", 1, 4, "fade in")
  g->Grid.param(prefix ++ "Slew", 2, 4, "slew")
  g->Grid.choice(prefix ++ "Steps", 0, 5, "s&h steps")
  g->Grid.toggle(prefix ++ "OneShot", 1, 5, "one-shot")
}

// LFO 3, which only the modulation matrix reaches, and the wander source's rate.
let lfo3 = (ctx: Ctx.t, body, box: box) => {
  Plots.lfo3(ctx, body, box)
  let g = Grid.make(ctx, body, ~x=box.x + box.w + 10.)
  g->Grid.choice("LFO_3_Shape", 0, 0, "shape")
  g->Grid.at(1, 0, ~span=2, "LFO_3_Mode", b => Controls.lfoMode(ctx, body, "LFO_3_Mode", ~x=b.x, ~y=b.y, ~w=b.w))
  g->Grid.choice("LFO_3_Sync", 0, 1, "sync")
  // (the rate is the sync's when it has one)
  let rate = g->Grid.at(1, 1, "LFO_3_Rate", b =>
    Controls.paramControl(ctx, body, "LFO_3_Rate", ~x=b.x, ~y=b.y, ~w=b.w, ~label="rate")
  )
  g->Grid.param("LFO_3_Phase", 0, 2, "phase")
  g->Grid.param("LFO_3_PhaseRand", 1, 2, "random phase")
  g->Grid.param("LFO_3_Delay", 0, 3, "delay")
  g->Grid.param("LFO_3_Fade", 1, 3, "fade in")
  g->Grid.param("Wander_Rate", 0, 4, "wander rate")
  g->Grid.note("LFO 3 and wander move things through the Mod page's connections.", 1, 4, ~span=2, ~rows=2)->ignore
  let dim = () => rate->toggleClass("dim", ctx.model->ParamModel.get("LFO_3_Sync") != 0.)
  ctx.model->ParamModel.listen("LFO_3_Sync", dim)
  dim()
}

// The voice lane (VoiceLane): the effects every voice runs its own copy of, in order with the
// filter and the amp envelope, a row each. Drag a row by its name to move it; each effect's row
// has its switch, its level, a button to open its tab and ×.
let voiceFx = (ctx: Ctx.t, body) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let hover = (e, text) => ctx.status->Status.hover(e, text)
  let cw = Grid.fitColumns(columnWidth, 4)
  let rowW = 4. * cw - Grid.columnGap
  let row = (~cls="") => {
    let r = el("div", ~cls="vrow " ++ cls, ~parent=body)->place(Grid.padX, 0., ~w=rowW, ~h=Style.controlHeight)
    r
  }
  // the filter and the amp: fixed rows
  let filterRow = row(~cls="node")
  let filterText = el("span", ~cls="vname", ~parent=filterRow)
  let ampRow = row(~cls="node")
  el("span", ~cls="vname", ~text="amp envelope", ~parent=ampRow)->ignore
  hover(filterRow, () => "The filter (and the distortion's places either side): drag it up or down among the voice's effects")
  hover(ampRow, () =>
    "The amp envelope: effects below it react to how each note swells and fades and ring on after it ends; those above it are shaped by it. Drag it up or down."
  )

  // an effect's row, made when it first comes into the lane
  let rows = Map.make()
  let rowOf = (e: FxRack.effect) =>
    switch rows->Map.get(FxRack.value(e)) {
    | Some(r) => r
    | None =>
      let r = row(~cls="fx")
      let led = el("i", ~cls="led", ~parent=r)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          let id = FxRack.switchId(e)
          model->ParamModel.gestureSet(id, get(id) != 0. ? 0. : FxRack.onValue(e))
        }
      )
      let name = el("span", ~cls="vname", ~parent=r)
      let (_, level) = FxPanels.cardControls(e.kind)
      level->Option.forEach(((id, label)) =>
        Controls.param(ctx, r, FxRack.id(e, id), ~x=1.5 * cw, ~y=0., ~w=1.5 * cw - Grid.columnGap, ~label)
      )
      let opener = Controls.button(ctx, r, "open", ~x=3. * cw, ~y=0., ~w=cw * 0.62, ~h=Style.controlHeight, ~cls="gc", ~status="Open its tab on the FX page", () => ctx.openEffect(e))
      opener->ignore
      let x = el("b", ~cls="vx", ~text="×", ~parent=r)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        VoiceLane.remove(model, e)
      })
      hover(x, () => "Take it out of the voices (its settings stay)")
      hover(name, () =>
        `${VoiceLane.label(model, e)}: each note runs its own (${FxPanels.summary(model, e)->String.replaceAll("\n", ", ")}). Drag to move it, right-click to duplicate it or move it to the whole sound`
      )
      let made = (r, name, led)
      rows->Map.set(FxRack.value(e), made)
      made
    }
  let itemEl = (item: VoiceLane.item) =>
    switch item {
    | Fx(e) =>
      let (r, _, _) = rowOf(e)
      r
    | FilterNode => filterRow
    | AmpNode => ampRow
    }
  let press = (item: VoiceLane.item, ev) =>
    switch ev->button {
    | 0 =>
      ev->preventDefault
      let others = VoiceLane.items(get)->Array.filter(o => o != item)->Array.map(itemEl)
      Reorder.start(ev, itemEl(item), ~vertical=true, ~others, ~onDrop=pos => VoiceLane.move(model, item, pos), ~onClick=() => ())
    | 2 =>
      switch item {
      | Fx(e) =>
        ev->preventDefault
        VoiceLane.menu(ctx, e, itemEl(item))
      | _ => ()
      }
    | _ => ()
    }
  filterText->onPointer(#pointerdown, ev => press(FilterNode, ev))
  ampRow->onPointer(#pointerdown, ev => press(AmpNode, ev))
  filterRow->suppressContextMenu
  ampRow->suppressContextMenu
  let hooked = Set.make()

  let add = el("div", ~cls="addrow vadd", ~parent=body)
  el("b", ~text="+", ~parent=add)->ignore
  el("span", ~text="add an effect to every voice", ~parent=add)->ignore
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      VoiceLane.addMenu(ctx, add, ~onAdded=_ => ())
    }
  })
  hover(add, () => "Up to four: each note runs its own copy, which its LFOs, envelopes and key move for that note alone")
  let note = el(
    "div",
    ~cls="note wrap",
    ~text="Each note runs its own copy of these; the resonator and key shifter follow its pitch. The filter's comb, flanger, phaser, formant, ring mod, S&H, diffusor and reverb types are effects in each note too.",
    ~parent=body,
  )

  let layout = () => {
    rows->Map.forEach(((r, _, _)) => r->setStyle("display", "none"))
    let lane = FxRack.readLane(get)
    let items = VoiceLane.items(get)
    items->Array.forEachWithIndex((item, i) => {
      let y = Grid.padTop + Int.toFloat(i) * Grid.rowHeight
      switch item {
      | Fx(e) =>
        let (r, name, led) = rowOf(e)
        if !(hooked->Set.has(FxRack.value(e))) {
          hooked->Set.add(FxRack.value(e))
          name->onPointer(#pointerdown, ev => press(Fx(e), ev))
          r->suppressContextMenu
          r->onMouse(#contextmenu, ev => ev->preventDefault)
        }
        r->setStyle("display", "")
        r->place(Grid.padX, y)->ignore
        name->setTextContent(FxRack.label(lane, e))
        let on = FxRack.isOn(e, get)
        led->toggleClass("lit", on)
        r->toggleClass("off", !on)
      | FilterNode =>
        filterRow->place(Grid.padX, y)->ignore
        filterText->setTextContent(`filter: ${model->ParamModel.shortText("Filter")}`)
      | AmpNode => ampRow->place(Grid.padX, y)->ignore
      }
    })
    let y = Grid.padTop + Int.toFloat(Array.length(items)) * Grid.rowHeight
    let full = FxRack.laneFull(lane)
    add->setStyle("display", full ? "none" : "flex")
    add->place(Grid.padX, y, ~w=rowW, ~h=Style.controlHeight)->ignore
    note->place(Grid.padX + 2., y + (full ? 0. : Grid.rowHeight) + 4., ~w=rowW - 4.)->ignore
  }
  let soon = perFrame(layout)
  model->ParamModel.listenEach(
    [...VoiceLane.ids, "Filter", ...FxRack.all->Array.map(FxRack.switchId)],
    soon,
  )
  layout()
}

// Microtuning: a Scala scale (and keyboard mapping) instead of the 12 notes above it.
let scale = (ctx: Ctx.t, body, g: Grid.t) => {
  el("div", ~cls="sep", ~parent=body)->place(g->Grid.cx(0) + 3., g->Grid.cy(4) - 1., ~w=4. * g.cw - 8.)->ignore
  g->Grid.claim(0, 4, ~span=2, "the scale name")
  let name = el("div", ~cls="scale", ~parent=body)->placeBox(g->Grid.cell(0, 4, ~span=2))
  let pickScale = FilePicker.make(body, ~accept=Scala.extensions->Array.join(","), file =>
    ctx.programs->ProgramStore.loadUserFile(file)->Promise.ignore
  )
  // the 12 note offsets don't apply while a scale is loaded
  let notes = body->querySelectorAll(".p")->nodesToArray->Array.slice(~start=4)
  g->Grid.button(
    "load scale",
    2,
    4,
    ~status="Load a Scala scale (.scl) or keyboard mapping (.kbm); they're saved with the program",
    pickScale,
  )
  g->Grid.button(
    "clear",
    3,
    4,
    ~status="Back to the 12-note tuning above",
    () => ctx.programs->ProgramStore.setTuning(None),
  )
  let help = g->Grid.note("", 0, 5, ~span=4, ~rows=2)
  let update = () => {
    let scaleName = ctx.programs->ProgramStore.tuningName
    name->setTextContent(scaleName->Option.getOr("12 notes, as above"))
    name->toggleClass("on", scaleName != None)
    notes->Array.forEach(e => e->toggleClass("dim", scaleName != None))
    help->setTextContent(
      scaleName == None
        ? "Load a Scala scale to retune every key. Tune still sets 440 Hz; the keyboard mapping (.kbm) sets which key plays which degree."
        : "The scale replaces the 12 notes above. Tune still moves 440 Hz, so 440 Hz plays the scale as written.",
    )
  }
  ctx.programs->ProgramStore.onChanged(update)
  update()
}

let build = (ctx: Ctx.t, page) => {
  let x0 = margin
  let x1 = x0 + columnWidth + gap
  let x2 = x1 + columnWidth + gap
  let lastWidth = Style.designWidth - margin - x2
  let y0 = margin
  let y1 = y0 + rowHeight + gap

  //==============================================================================
  // sources
  let osc = Panel.make(
    page,
    ~tabs=["osc 1", "osc 2", "noise", "unison", "phase", "osc envs"],
    ~x=x0,
    ~y=y0,
    ~w=columnWidth,
    ~h=rowHeight,
  )
  oscillator(ctx, osc->Panel.body(0), 1)
  oscillator(ctx, osc->Panel.body(1), 2)

  let noise = Grid.make(ctx, osc->Panel.body(2))
  noise->Grid.param("N_Amp", 0, 0, "amp")
  noise->Grid.param("N_Aftertouch", 1, 0, "touch > amp")
  noise->Grid.param("N_Resonance", 2, 0, "resonance")
  noise->Grid.param("N_Transpose", 3, 0, "transpose")

  let unison = Grid.make(ctx, osc->Panel.body(3))
  unison->Grid.param("U_Voices", 0, 0, "voices")
  unison->Grid.param("U_Detune", 1, 0, "detune")
  unison->Grid.param("U_Spread", 2, 0, "spread")
  unison->Grid.param("U_Width", 3, 0, "width")
  unison->Grid.param("U_PitchJitter", 0, 1, "pitch jitter")
  unison->Grid.param("U_PanJitter", 1, 1, "pan jitter")
  unison->Grid.param("U_DetuneCurve", 2, 1, "detune curve")
  unison->Grid.toggle("U_RandomPhase", 3, 1, "rand phase")
  // analog drift: slow random pitch (per unison copy) and cutoff (per voice)
  unison->Grid.param("Drift_Pitch", 0, 2, "drift pitch")
  unison->Grid.param("Drift_Cutoff", 1, 2, "drift cutoff")
  unison->Grid.param("Drift_Rate", 2, 2, "drift rate")

  // each oscillator's own envelope, beside its switch
  let envs = osc->Panel.body(5)
  let envGrid = Grid.make(ctx, envs)
  let envHeight = (rowHeight - Grid.padTop - 10.) / 2.
  [1, 2]->Array.forEach(n => {
    let prefix = PorridgeParams.oscEnvPrefix(n)
    let name = `osc ${Int.toString(n)}`
    let row = 4 * (n - 1)
    envGrid->Grid.toggle(prefix ++ "On", 0, row, name ++ " env")
    envGrid
    ->Grid.note(`${name}'s level follows it, under the amp envelope`, 0, row + 1, ~rows=2)
    ->ignore
    envelope(
      ctx,
      envs,
      prefix,
      {
        x: envGrid->Grid.cx(1) + 4.,
        y: envGrid->Grid.cy(row) + 2.,
        w: columnWidth - Grid.columnWidth - 16.,
        h: envHeight - 6.,
      },
      ~name=`Osc ${Int.toString(n)} envelope`,
    )
  })

  let phase = Grid.make(ctx, osc->Panel.body(4))
  [("Osc", "osc"), ("PWM", "pwm"), ("LFO", "lfo")]->Array.forEachWithIndex(((id, label), r) => {
    phase->Grid.param(id ++ "Phase", 0, r, label)
    phase->Grid.param(id ++ "PhaseRand", 1, r, label ++ " rand")
    phase->Grid.toggle(id ++ "Retrig", 2, r, "retrigger")
  })

  //==============================================================================
  // filter
  let refreshResponse = ref(() => ())
  let refreshPreview = ref(() => ())
  let filterEl = ref(None)
  let filter = Panel.make(
    page,
    ~tabs=["filter", "response", "dual filter", "key EQ", "voice fx"],
    ~onSelect=i => {
      // the response and the voice's effects cover the filter envelope
      filterEl.contents->Option.forEach(e => e->Web.toggleClass("responding", i == 1 || i == 4))
      switch i {
      | 0 => refreshPreview.contents()
      | 1 => refreshResponse.contents()
      | _ => ()
      }
    },
    ~x=x1,
    ~y=y0,
    ~w=columnWidth,
    ~h=rowHeight,
  )
  let main = Grid.make(ctx, filter->Panel.body(0))
  main->Grid.choice("Filter", 0, 0, "type", ~span=2)
  main->Grid.param("Cutoff", 2, 0, "cutoff")
  main->Grid.param("Resonance", 3, 0, "reso")
  main->Grid.param("F_Track", 0, 1, "track")
  main->Grid.param("F_EnvMod", 1, 1, "env mod")
  main->Grid.param("F_VeloSens", 2, 1, "velocity")
  main->Grid.param("F_Aftertouch", 3, 1, "touch")
  let knob = (id, c, label) =>
    main->Grid.at(c, 2, id, b => Controls.paramControl(ctx, filter->Panel.body(0), id, ~x=b.x, ~y=b.y, ~w=b.w, ~label))
  let morphKnob = knob("F_Morph", 0, "morph")
  let driveKnob = knob("F_Drive", 1, "drive")
  // morph and drive are dimmed for the types they do nothing for
  let get = id => ctx.model->ParamModel.get(id)
  let filterType = () => Float.toInt(get("Filter"))
  let describe = () => {
    let t = filterType()
    morphKnob->Web.toggleClass("dim", FilterTypes.morphText(t) == None)
    driveKnob->Web.toggleClass("dim", !FilterTypes.hasDrive(t))
  }
  ctx.model->ParamModel.listen("Filter", describe)
  describe()

  // the response: the type with its cutoff and resonance, as a curve with a point to drag
  // (covering the envelope while it shows), and a small picture of it beside morph and drive
  filterEl := Some(filter.el)
  let response = filter->Panel.body(1)
  response->Web.addClass("cover")
  let resp = Grid.make(ctx, response)
  resp->Grid.choice("Filter", 0, 0, "type", ~span=2)
  resp->Grid.param("Cutoff", 2, 0, "cutoff")
  resp->Grid.param("Resonance", 3, 0, "reso")
  let graphTop = Grid.padTop + Grid.rowHeight + 4.
  let source: FilterGraph.source = {
    typeOf: filterType,
    cutoff: "Cutoff",
    toHz: c => FilterTypes.cutoffHz(~filterType=filterType(), c),
    ofHz: hz => FilterTypes.cutoffOfHz(~filterType=filterType(), hz),
    res: "Resonance",
    morph: "F_Morph",
    drive: "F_Drive",
    mix: None,
    spread: None,
    // filter 2, when doubling: its type (or filter 1's) an octave up per half of the split
    second: () => {
      let t1 = filterType()
      let t2 = Float.toInt(get("Filter2"))
      get("F_Double") == 0.
        ? None
        : Some((
            t2 == 0 ? t1 : t2,
            FilterTypes.cutoffHz(~filterType=t1, get("Cutoff")) * Math.pow(2., ~exp=2. * get("F_Split")),
          ))
    },
    alsoIds: ["Filter", "Filter2", "F_Double", "F_Split"],
  }
  refreshResponse :=
    FilterGraph.make(
      ctx,
      response,
      {x: 8., y: graphTop, w: columnWidth - 18., h: rowHeight - graphTop - 10.},
      source,
      ~voices=true,
    )
  refreshPreview :=
    main->Grid.at(2, 2, ~span=2, "the filter preview", box =>
      FilterGraph.mini(
        ctx,
        filter->Panel.body(0),
        box,
        source,
        ~status=() => {
          let t = filterType()
          let morph = FilterTypes.morphText(t)->Option.mapOr("", m => " · morph: " ++ m)
          `${ctx.model->ParamModel.shortText("Filter")}${morph}${FilterTypes.hasDrive(t)
              ? ""
              : " · no drive"}. Click for the response, to drag the cutoff and resonance.`
        },
        ~onClick=() => filter->Panel.select(1),
      )
    )
  let dual = Grid.make(ctx, filter->Panel.body(2))
  dual->Grid.choice("Filter2", 0, 0, "filter 2", ~span=2)
  dual->Grid.choice("F_Double", 2, 0, "double")
  dual->Grid.param("F_Split", 3, 0, "split")
  dual->Grid.param("F_Mix", 0, 1, "mix")
  dual->Grid.param("F_Speed", 1, 1, "speed ratio")
  // the key EQ: a band on each of the note's harmonics 1, 2, 4 ... 128
  voiceFx(ctx, filter->Panel.body(4))
  let keyEq = Grid.make(ctx, filter->Panel.body(3))
  keyEq->Grid.toggle("KEQ_On", 0, 0, "key EQ")
  keyEq
  ->Grid.note("A low shelf under the note, then octave-wide bands on its harmonics: they move with the key", 1, 0, ~span=3)
  ->ignore
  for k in 1 to PorridgeParams.keyEqBands {
    let label = k == 1 ? "low shelf" : Float.toString(PorridgeParams.keyEqHarmonic(k)) ++ "×"
    keyEq->Grid.param(PorridgeParams.keyEqGainId(k), mod(k - 1, 4), 1 + (k - 1) / 4, label)
  }
  let top = Grid.padTop + 3. * Grid.rowHeight + 6.
  envelope(
    ctx,
    filter.el,
    "F_",
    {x: 8., y: top, w: 340., h: rowHeight - top - 10.},
    ~name="Filter envelope",
  )

  //==============================================================================
  // amp
  let amp = Panel.make(page, ~title="amp", ~x=x2, ~y=y0, ~w=lastWidth, ~h=rowHeight)
  let ampBox = {x: 8., y: 25., w: lastWidth - 18., h: rowHeight - 25. - Grid.rowHeight - 16.}
  envelope(ctx, amp.el, "", ampBox, ~name="Amp envelope")
  let ampGrid = Grid.make(ctx, amp.el, ~y=ampBox.y + ampBox.h + 4.)
  ampGrid->Grid.param("Gain", 0, 0, "output gain")
  ampGrid->Grid.param("VeloSens", 1, 0, "velocity")
  ampGrid->Grid.param("FreqEnv", 2, 0, "freq > env")

  //==============================================================================
  // modulation
  let modulation = Panel.make(
    page,
    ~tabs=["mod env 1", "mod env 2", "pitch env", "lfo 1", "lfo 2", "lfo 3"],
    ~x=x0,
    ~y=y1,
    ~w=2. * columnWidth + gap,
    ~h=rowHeight,
  )
  let graph = {x: 8., y: 27., w: 430., h: rowHeight - 27. - 10.}
  modEnvelope(ctx, modulation->Panel.body(0), 1, graph)
  modEnvelope(ctx, modulation->Panel.body(1), 2, graph)

  let pitchBody = modulation->Panel.body(2)
  EnvEditor.make(
    ctx,
    pitchBody,
    graph,
    EnvEditor.pitch(ctx, ~w=graph.w, ~h=graph.h),
    ~fields=[
      ("PEnv_Start", "start"),
      ("PEnv_Attack", "attack"),
      ("PEnv_Peak", "peak"),
      ("PEnv_Decay", "decay"),
      ("PEnv_Sustain", "sustain"),
      ("PEnv_Release", "release"),
    ],
    ~name="Pitch envelope",
  )
  let pitch = Grid.make(ctx, pitchBody, ~x=graph.x + graph.w + 10.)
  pitch->Grid.toggle("PEnv_On", 0, 0, "on")
  pitch->Grid.param("PEnv_VeloSens", 1, 0, "velocity")

  lfo(ctx, modulation->Panel.body(3), 1, graph)
  lfo(ctx, modulation->Panel.body(4), 2, graph)
  lfo3(ctx, modulation->Panel.body(5), graph)

  //==============================================================================
  // voice
  let voice = Panel.make(page, ~tabs=["voice", "tuning"], ~x=x2, ~y=y1, ~w=lastWidth, ~h=rowHeight)
  let v = Grid.make(ctx, voice->Panel.body(0))
  v->Grid.choice("PolyMode", 0, 0, "voice mode", ~span=2)
  v->Grid.param("Voices", 2, 0, "polyphony")
  v->Grid.param("BendRange", 3, 0, "bend range")
  v->Grid.param("Glide", 0, 1, "glide")
  v->Grid.choice("GlideMode", 1, 1, "glide mode", ~span=2)
  v->Grid.param("GlobalTranspose", 3, 1, "transpose")
  v->Grid.param("RandomFreq", 0, 2, "random freq")
  v->Grid.param("RandomPan", 1, 2, "random pan")
  v->Grid.param("RandomAmp", 2, 2, "random amp")
  v->Grid.param("FreqPan", 3, 2, "freq > pan")
  v->Grid.choice("AftertouchMode", 0, 3, "touch")
  v->Grid.toggle("Oat_Mode", 1, 3, "Oat mode", ~span=2)
  v
  ->Grid.note(
    "Oat mode keeps Oatmeal's MIDI timing: notes, controllers and arpeggiator steps start on the next 64-sample block instead of on their own sample.",
    0,
    4,
    ~span=3,
    ~rows=2,
  )
  ->ignore
  // the pitch and mod wheels, as on the Arp / XY page, side by side in the last column
  v->Grid.at(3, 4, ~rows=4, "the wheels", box => Wheels.make(ctx, voice->Panel.body(0), box, ~gap=Grid.columnGap))

  let tuning = Grid.make(ctx, voice->Panel.body(1))
  tuning->Grid.param("Tune_Main", 0, 0, "tune")
  tuning->Grid.param("Tune_Octave", 1, 0, "octave")
  tuning->Grid.param("Tune_CutReference", 2, 0, "cut ref")
  tuning->Grid.param("Tune_PanReference", 3, 0, "pan ref")
  [
    ("Tune_C", "c"),
    ("Tune_Db", "c#"),
    ("Tune_D", "d"),
    ("Tune_Eb", "d#"),
    ("Tune_E", "e"),
    ("Tune_F", "f"),
    ("Tune_Gb", "f#"),
    ("Tune_G", "g"),
    ("Tune_Ab", "g#"),
    ("Tune_A", "a"),
    ("Tune_Bb", "a#"),
    ("Tune_B", "b"),
  ]->Array.forEachWithIndex(((id, label), i) => tuning->Grid.param(id, mod(i, 4), 1 + i / 4, label))
  scale(ctx, voice->Panel.body(1), tuning)
}
