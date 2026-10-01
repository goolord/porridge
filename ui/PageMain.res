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
    ["attack curve", "decay curve", "release curve"]->Array.getUnsafe(i),
  )),
]

let envelope = (ctx, parent, prefix, box: box, ~name) =>
  EnvEditor.make(
    ctx,
    parent,
    box,
    EnvEditor.adsr(ctx, prefix, ~w=box.w, ~h=box.h),
    ~fields=envelopeFields(prefix),
    ~name,
  )

let oscillator = (ctx: Ctx.t, body, n) => {
  let osc = Int.toString(n)
  let prefix = `O${osc}_`
  let plot = {x: 8., y: 27., w: 340., h: 110.}
  Plots.wave(ctx, body, n - 1, plot)
  Controls.button(
    ctx,
    body,
    "draw",
    ~x=plot.x + plot.w - 48.,
    ~y=plot.y + plot.h - 23.,
    ~w=44.,
    ~status=`Draw oscillator ${osc}'s user waveform`,
    () => ctx.openShape(n == 1 ? Wave1 : Wave2),
  )->ignore
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
  Controls.button(
    ctx,
    body,
    "draw",
    ~x=box.x + box.w - 48.,
    ~y=box.y + box.h - 23.,
    ~w=44.,
    ~status=`Draw LFO ${lfo}'s user shape`,
    () => ctx.openShape(n == 1 ? LfoShape1 : LfoShape2),
  )->ignore
  let g = Grid.make(ctx, body, ~x=box.x + box.w + 10.)
  g->Grid.choice(prefix ++ "Shape", 0, 0, "shape")
  g->Grid.choice(prefix ++ "Sync", 1, 0, "mode", ~span=2)
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

// Microtuning: a Scala scale (and keyboard mapping) instead of the 12 notes above it.
let scale = (ctx: Ctx.t, body, g: Grid.t) => {
  el("div", ~cls="sep", ~parent=body)->place(g->Grid.cx(0) + 3., g->Grid.cy(4) - 1., ~w=4. * g.cw - 8.)->ignore
  g->Grid.claim(0, 4, ~span=2, "the scale name")
  let name = el("div", ~cls="scale", ~parent=body)->placeBox(g->Grid.cell(0, 4, ~span=2))
  let picker = el("input", ~parent=body)
  picker->setInputType("file")
  picker->setAccept(".scl,.kbm")
  picker->setStyle("display", "none")
  picker->onEvent(#change, _ => {
    picker
    ->files
    ->Option.flatMap(item(_, 0))
    ->Option.forEach(file =>
      file
      ->arrayBuffer
      ->Promise.thenResolve(buffer =>
        ctx.programs->ProgramStore.loadTuningFile(
          Preset.utf8Decode(Uint8Array.fromBuffer(buffer)),
          file->fileName,
        )
      )
      ->Promise.ignore
    )
    picker->setValue("")
  })
  // the 12 note offsets don't apply while a scale is loaded
  let notes = body->querySelectorAll(".p")->nodesToArray->Array.slice(~start=4)
  g->Grid.button(
    "load scale",
    2,
    4,
    ~status="Load a Scala scale (.scl) or keyboard mapping (.kbm); they're saved with the program",
    () => picker->click,
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
    ~tabs=["osc 1", "osc 2", "noise", "unison", "phase"],
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

  let phase = Grid.make(ctx, osc->Panel.body(4))
  [("Osc", "osc"), ("PWM", "pwm"), ("LFO", "lfo")]->Array.forEachWithIndex(((id, label), r) => {
    phase->Grid.param(id ++ "Phase", 0, r, label)
    phase->Grid.param(id ++ "PhaseRand", 1, r, label ++ " rand")
    phase->Grid.toggle(id ++ "Retrig", 2, r, "retrigger")
  })

  //==============================================================================
  // filter
  let filter = Panel.make(page, ~tabs=["filter", "dual filter"], ~x=x1, ~y=y0, ~w=columnWidth, ~h=rowHeight)
  let main = Grid.make(ctx, filter->Panel.body(0))
  main->Grid.choice("Filter", 0, 0, "type", ~span=2)
  main->Grid.param("Cutoff", 2, 0, "cutoff")
  main->Grid.param("Resonance", 3, 0, "reso")
  main->Grid.param("F_Track", 0, 1, "track")
  main->Grid.param("F_EnvMod", 1, 1, "env mod")
  main->Grid.param("F_VeloSens", 2, 1, "velocity")
  main->Grid.param("F_Aftertouch", 3, 1, "touch")
  main->Grid.param("F_Morph", 0, 2, "morph")
  main->Grid.note("morph: SVF LP › BP › HP · comb + › − · formant vowel", 1, 2, ~span=3)->ignore
  let dual = Grid.make(ctx, filter->Panel.body(1))
  dual->Grid.choice("Filter2", 0, 0, "filter 2", ~span=2)
  dual->Grid.choice("F_Double", 2, 0, "double")
  dual->Grid.param("F_Split", 3, 0, "split")
  dual->Grid.param("F_Mix", 0, 1, "mix")
  dual->Grid.param("F_Speed", 1, 1, "speed ratio")
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
    ~tabs=["mod env 1", "mod env 2", "pitch env", "lfo 1", "lfo 2"],
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
    ~span=4,
    ~rows=2,
  )
  ->ignore

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
