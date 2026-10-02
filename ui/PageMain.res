// Synth page: the voice, as a signal path. Its flow runs along the top (VoiceFlow); below it the
// oscillators, the filter and the amp, then the modulation sources (each with what it moves, as
// chips: Destinations) and the voice's settings. What a sound is made of shows; the rest waits in
// tabs, each marked while what it holds is in use (Features), and controls that do nothing for
// the current settings (pulse width without a pulse wave, a filter type's unused morph) stay
// hidden. Graphs are the main controls of what they draw: drag their points.

open! Web

let hint = "Drag or scroll to change a value, shift for fine steps. Double-click to type, right-click to reset. Click a list to pick from it, right-click to step through it."

let (margin, gap) = (6., Grid.gap)
let flowHeight = 30.
let top = margin + flowHeight + gap
let rowHeight = (Style.pageHeight - top - margin - gap) / 2.
let (oscWidth, filterWidth) = (380., 400.)
let lastWidth = Style.designWidth - 2. * margin - 2. * gap - oscWidth - filterWidth
let modWidth = oscWidth + gap + filterWidth

// the modulation panel's right column (a source's velocity, and what it moves), and the LFOs'
// controls left of it
let chipsWidth = 176.
let chipsX = modWidth - 8. - chipsWidth
let lfoColumn = 82.
let lfoX = chipsX - 8. - 3. * lfoColumn

let envelopeFields = (env: EnvEditor.envelope) => {
  let prefix = env.params.prefix
  [
    (prefix ++ "Attack", "attack"),
    (prefix ++ "Hold", "hold"),
    (prefix ++ "Decay1", "decay 1"),
    (prefix ++ "Breakpoint", "breakpoint"),
    (prefix ++ "Decay2", "decay 2"),
    (prefix ++ "Sustain", "sustain"),
    (prefix ++ "Release", "release"),
    ...EnvEditor.curveIds(env)->Array.mapWithIndex((id, i) => (
      id,
      ["attack curve", "decay 1 curve", "decay 2 curve", "release curve"]->Array.getUnsafe(i),
    )),
  ]
}

// (each sounding note is marked where it is on the envelopes that have a clock)
let envelope = (ctx, parent, env: EnvEditor.envelope, box: box, ~columns=?) =>
  EnvEditor.make(
    ctx,
    parent,
    box,
    EnvEditor.adsr(ctx, env, ~w=box.w, ~h=box.h),
    ~fields=envelopeFields(env),
    ~columns?,
    ~name=env.title,
    ~clock=?env.clock,
  )

// Controls on grid g that show only while shown() holds, because they do nothing otherwise: make
// places them (on the grid it's given), and whether they show is checked again whenever one of
// ids changes. Their cells stay theirs.
let shownWhile = (ctx: Ctx.t, g: Grid.t, ids, shown, make: Grid.t => unit) => {
  let wrap = el("div", ~parent=g.el)
  make({...g, el: wrap})
  let update = () => wrap->setStyle("display", shown() ? "" : "none")
  ctx.model->ParamModel.listenEach(ids, update)
  update()
}

// A "?" filling a grid cell's height at its right end, with text in a tooltip tipW wide (from
// its left, with ~left).
let help = (g: Grid.t, c, r, text, ~tipW=260., ~left=?) => {
  let size = Style.controlHeight
  g->Grid.at(c, r, "a help button", b => Controls.help(g.el, text, ~x=b.x + b.w - size, ~y=b.y, ~size, ~tipW, ~left?))
}

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

//==============================================================================
// the oscillators

// the waves with a pulse width (Pulse, User PWM, Pulse HQ)
let isPulse = wave => wave == 2. || wave == 5. || wave == 7.

// Both oscillators, a row each: a picture of the wave (click it to draw the user wave), the
// wave, its level and osc 2's pitch, and the pulse width and its modulation under a pulse wave.
// Then the mix, with osc 1's PM feedback and how much of osc 2 is heard for the modes that have
// them.
let oscillators = (ctx: Ctx.t, body) => {
  let get = id => ctx.model->ParamModel.get(id)
  let g = Grid.make(ctx, body, ~cw=Grid.fitColumns(oscWidth, 6))
  [1, 2]->Array.forEach(n => {
    let osc = Int.toString(n)
    let prefix = `O${osc}_`
    let r = 2 * (n - 1)
    g->Grid.at(0, r, ~rows=2, "the wave", box => {
      let plot = Plots.wave(ctx, body, n - 1, box, ~badge=false)
      plot->addClass("thumb")
      // a pencil in the corner
      svgEl(
        plot,
        "path",
        [
          ("class", Str("pencil")),
          ("d", Str(`M${Float.toString(box.w - 12.)} ${Float.toString(box.h - 3.)}l1-3 6-6 2 2-6 6z`)),
        ],
      )->ignore
      plot->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->preventDefault
          ctx.openShape(n == 1 ? Wave1 : Wave2)
        }
      )
      ctx.status->Status.hover(plot, () => `Osc ${osc}'s wave: click to draw its user waveform`)
    })
    g->Grid.choice(prefix ++ "Waveform", 1, r, "osc " ++ osc, ~span=2)
    g->Grid.param(prefix ++ "Amp", 3, r, "level")
    if n == 2 {
      g->Grid.param("Transpose", 4, r, "transpose")
      g->Grid.param("Detune", 5, r, "detune")
    }
    shownWhile(ctx, g, [prefix ++ "Waveform"], () => isPulse(get(prefix ++ "Waveform")), g => {
      g->Grid.param(prefix ++ "PWM_W", 1, r + 1, "pulse width")
      g->Grid.param(prefix ++ "PWM_R", 2, r + 1, "pwm rate")
      g->Grid.param(prefix ++ "PWM_D", 3, r + 1, "pwm depth")
    })
  })
  g->Grid.choice("OscMix", 0, 4, "mix", ~span=3)
  // (the modes: PatchGen's pm, pmFeedback, ring and am)
  let mode = () => Float.toInt(get("OscMix"))
  shownWhile(ctx, g, ["OscMix"], () => mode() == 3 || mode() == 4, g =>
    g->Grid.param("PM_Feedback", 3, 4, "pm feedback")
  )
  shownWhile(ctx, g, ["OscMix"], () => mode() == 3 || mode() == 5 || mode() == 6, g =>
    g->Grid.param("O2_PairMix", 4, 4, "osc 2 heard")
  )
}

let oscPanel = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let osc = Panel.make(
    page,
    ~tabs=["oscillators", "noise", "unison", "phase", "osc envs"],
    ~x=margin,
    ~y=top,
    ~w=oscWidth,
    ~h=rowHeight,
  )
  oscillators(ctx, osc->Panel.body(0))
  osc->Panel.mark(model, 1, [Features.noise, Features.oscNoise])->ignore
  osc->Panel.mark(model, 2, [Features.unison, Features.drift])->ignore
  osc->Panel.mark(model, 3, [Features.oscPhase])->ignore
  osc->Panel.mark(model, 4, [Features.oscEnv(1), Features.oscEnv(2)])->ignore

  // the noise generator, and each oscillator's roughness (its pitch moved by noise)
  let cw = Grid.fitColumns(oscWidth, 4)
  let noise = Grid.make(ctx, osc->Panel.body(1), ~cw)
  noise->Grid.param("N_Amp", 0, 0, "noise level")
  noise->Grid.param("N_Resonance", 1, 0, "resonance")
  noise->Grid.param("N_Transpose", 2, 0, "transpose")
  noise->Grid.param("N_Aftertouch", 3, 0, "touch > level")
  noise->Grid.param("O1_Noise", 0, 1, "osc 1 rough")
  noise->Grid.param("O1_NoiseColour", 1, 1, "colour")
  noise->Grid.param("O2_Noise", 2, 1, "osc 2 rough")
  noise->Grid.param("O2_NoiseColour", 3, 1, "colour")

  let unison = Grid.make(ctx, osc->Panel.body(2), ~cw)
  unison->Grid.param("U_Voices", 0, 0, "voices")
  unison->Grid.param("U_Detune", 1, 0, "detune")
  unison->Grid.param("U_Spread", 2, 0, "spread")
  unison->Grid.param("U_Width", 3, 0, "width")
  unison->Grid.param("U_PitchJitter", 0, 1, "pitch jitter")
  unison->Grid.param("U_PanJitter", 1, 1, "pan jitter")
  unison->Grid.param("U_DetuneCurve", 2, 1, "detune curve")
  unison->Grid.toggle("U_RandomPhase", 3, 1, "rand phase")
  // analog drift: slow random pitch, per unison copy (its cutoff drift is the filter's)
  unison->Grid.param("Drift_Pitch", 0, 2, "drift pitch")
  unison->Grid.param("Drift_Rate", 1, 2, "drift rate")

  let phase = Grid.make(ctx, osc->Panel.body(3), ~cw)
  [("Osc", "osc"), ("PWM", "pwm")]->Array.forEachWithIndex(((id, label), r) => {
    phase->Grid.param(id ++ "Phase", 0, r, label ++ " phase")
    phase->Grid.param(id ++ "PhaseRand", 1, r, label ++ " rand")
    phase->Grid.toggle(id ++ "Retrig", 2, r, "retrigger")
  })

  // each oscillator's own envelope, beside its switch
  let envs = osc->Panel.body(4)
  let envHeight = (rowHeight - Grid.padTop - 6.) / 2.
  [1, 2]->Array.forEach(n => {
    let env = EnvEditor.oscEnv(n)
    let g = Grid.make(ctx, envs, ~y=Grid.padTop + Int.toFloat(n - 1) * envHeight, ~cw)
    env.switchId->Option.forEach(id => g->Grid.toggle(id, 0, 0, `osc ${Int.toString(n)} env`))
    envelope(ctx, envs, env, {x: g->Grid.cx(1) + 4., y: g->Grid.cy(0) + 2., w: oscWidth - cw - 16., h: envHeight - 6.})
    if n == 1 {
      help(
        g,
        0,
        1,
        "While its envelope is on, an oscillator's level follows it, under the amp envelope (which still ends the note).",
        ~tipW=240.,
        ~left=true,
      )
    }
  })
  osc
}

//==============================================================================
// the filter

let filterPanel = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let refreshResponse = ref(() => ())
  let filter = Panel.make(
    page,
    ~tabs=["filter", "dual filter", "key EQ"],
    ~onSelect=i => i == 0 ? refreshResponse.contents() : (),
    ~x=margin + oscWidth + gap,
    ~y=top,
    ~w=filterWidth,
    ~h=rowHeight,
  )
  filter->Panel.mark(model, 1, [Features.dualFilter])->ignore
  filter->Panel.mark(model, 2, [Features.keyEq])->ignore

  // what the filter is, and what moves its cutoff; morph and drive for the types that have them
  let body = filter->Panel.body(0)
  let main = Grid.make(ctx, body, ~cw=Grid.fitColumns(filterWidth, 6))
  let filterType = () => Float.toInt(get("Filter"))
  main->Grid.choice("Filter", 0, 0, "type", ~span=2)
  main->Grid.param("Cutoff", 2, 0, "cutoff")
  main->Grid.param("Resonance", 3, 0, "reso")
  shownWhile(ctx, main, ["Filter"], () => FilterTypes.morphText(filterType()) != None, g =>
    g->Grid.param("F_Morph", 4, 0, "morph")
  )
  shownWhile(ctx, main, ["Filter"], () => FilterTypes.hasDrive(filterType()), g =>
    g->Grid.param("F_Drive", 5, 0, "drive")
  )
  main->Grid.param("F_Track", 0, 1, "track")
  main->Grid.param("F_EnvMod", 1, 1, "env")
  main->Grid.param("F_VeloSens", 2, 1, "velocity")
  main->Grid.param("F_Aftertouch", 3, 1, "touch")
  main->Grid.param("Drift_Cutoff", 4, 1, "drift")

  // the response, with a point to drag for the cutoff and resonance, beside the envelope
  let graphTop = main->Grid.cy(2) + 2.
  let graphW = (filterWidth - 2. - 22.) / 2.
  let graphH = rowHeight - graphTop - 10.
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
  refreshResponse := FilterGraph.make(ctx, body, {x: 8., y: graphTop, w: graphW, h: graphH}, source, ~voices=true)
  envelope(ctx, body, EnvEditor.filter, {x: 14. + graphW, y: graphTop, w: graphW, h: graphH}, ~columns=3)

  let dual = Grid.make(ctx, filter->Panel.body(1), ~cw=Grid.fitColumns(filterWidth, 4))
  dual->Grid.choice("Filter2", 0, 0, "filter 2", ~span=2)
  dual->Grid.choice("F_Double", 2, 0, "double")
  dual->Grid.param("F_Split", 3, 0, "split")
  dual->Grid.param("F_Mix", 0, 1, "mix")
  dual->Grid.param("F_Speed", 1, 1, "speed ratio")

  // the key EQ: a band on each of the note's harmonics 1, 2, 4 ... 128
  let keyEq = Grid.make(ctx, filter->Panel.body(2), ~cw=Grid.fitColumns(filterWidth, 4))
  keyEq->Grid.toggle("KEQ_On", 0, 0, "key EQ")
  help(
    keyEq,
    3,
    0,
    "A low shelf under each note, then octave-wide bands on its harmonics: the curve moves with the key.",
  )
  for k in 1 to PorridgeParams.keyEqBands {
    let label = k == 1 ? "low shelf" : Float.toString(PorridgeParams.keyEqHarmonic(k)) ++ "×"
    keyEq->Grid.param(PorridgeParams.keyEqGainId(k), mod(k - 1, 4), 1 + (k - 1) / 4, label)
  }
  filter
}

//==============================================================================
// the modulation sources

let modEnvelope = (ctx: Ctx.t, body, n) => {
  let env = EnvEditor.modEnv(n)
  envelope(ctx, body, env, {x: 8., y: 27., w: chipsX - 16., h: rowHeight - 37.})
  Controls.param(ctx, body, env.params.prefix ++ "VeloSens", ~x=chipsX, ~y=Grid.padTop, ~w=chipsWidth, ~label="velocity")
  Destinations.make(
    ctx,
    body,
    `modEnv${Int.toString(n)}`,
    {x: chipsX, y: Grid.padTop + Grid.rowHeight, w: chipsWidth, h: rowHeight - Grid.padTop - Grid.rowHeight - 8.},
  )
}

let pitchEnvelope = (ctx: Ctx.t, body) => {
  let graph = {x: 8., y: 27., w: chipsX - 16., h: rowHeight - 37.}
  EnvEditor.make(
    ctx,
    body,
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
  let g = Grid.make(ctx, body, ~x=chipsX, ~cw=chipsWidth + Grid.columnGap)
  g->Grid.toggle("PEnv_On", 0, 0, "on")
  g->Grid.param("PEnv_VeloSens", 0, 1, "velocity")
}

// The LFOs share a layout: their picture, then shape and mode, rate, delay and fade, and phase,
// in that order as far as each has them, and what they move on the right.
let lfoGraph = {x: 8., y: 27., w: lfoX - 16., h: rowHeight - 37.}
let lfoGrid = (ctx, body) => Grid.make(ctx, body, ~x=lfoX, ~cw=lfoColumn)
let lfoDestinations = (ctx, body, key) =>
  Destinations.make(ctx, body, key, {x: chipsX, y: Grid.padTop, w: chipsWidth, h: rowHeight - Grid.padTop - 8.})

let lfo = (ctx: Ctx.t, body, n) => {
  let lfo = Int.toString(n)
  let prefix = `LFO_${lfo}_`
  Plots.lfo(ctx, body, n - 1, lfoGraph)
  drawButton(ctx, body, lfoGraph, ~status=`Draw LFO ${lfo}'s user shape`, n == 1 ? LfoShape1 : LfoShape2)
  let g = lfoGrid(ctx, body)
  g->Grid.choice(prefix ++ "Shape", 0, 0, "shape")
  g->Grid.at(1, 0, ~span=2, prefix ++ "Sync", b => Controls.lfoMode(ctx, body, prefix ++ "Sync", ~x=b.x, ~y=b.y, ~w=b.w))
  g->Grid.choice(prefix ++ "Unit", 0, 1, "unit")
  g->Grid.param(prefix ++ "Speed", 1, 1, "rate")
  g->Grid.toggle(prefix ++ "Quantize", 2, 1, "quantize")
  g->Grid.param(prefix ++ "Delay", 0, 2, "delay")
  g->Grid.param(prefix ++ "Fade", 1, 2, "fade in")
  g->Grid.param(prefix ++ "Slew", 2, 2, "slew")
  // (one phase for both LFOs, as Oatmeal has it)
  g->Grid.param("LFOPhase", 0, 3, "phase 1+2")
  g->Grid.param("LFOPhaseRand", 1, 3, "rand 1+2")
  g->Grid.toggle("LFORetrig", 2, 3, "retrig 1+2")
  g->Grid.choice(prefix ++ "Steps", 0, 4, "s&h steps")
  g->Grid.toggle(prefix ++ "OneShot", 1, 4, "one-shot")
  lfoDestinations(ctx, body, "lfo" ++ lfo)
}

// LFO 3, and the wander source's rate.
let lfo3 = (ctx: Ctx.t, body) => {
  Plots.lfo3(ctx, body, lfoGraph)
  let g = lfoGrid(ctx, body)
  g->Grid.choice("LFO_3_Shape", 0, 0, "shape")
  g->Grid.at(1, 0, ~span=2, "LFO_3_Mode", b => Controls.lfoMode(ctx, body, "LFO_3_Mode", ~x=b.x, ~y=b.y, ~w=b.w))
  g->Grid.choice("LFO_3_Sync", 0, 1, "sync")
  // (the rate is the sync's when it has one)
  let rate = g->Grid.at(1, 1, "LFO_3_Rate", b =>
    Controls.paramControl(ctx, body, "LFO_3_Rate", ~x=b.x, ~y=b.y, ~w=b.w, ~label="rate")
  )
  g->Grid.param("LFO_3_Delay", 0, 2, "delay")
  g->Grid.param("LFO_3_Fade", 1, 2, "fade in")
  g->Grid.param("LFO_3_Phase", 0, 3, "phase")
  g->Grid.param("LFO_3_PhaseRand", 1, 3, "random phase")
  g->Grid.param("Wander_Rate", 0, 4, "wander rate")
  help(
    g,
    1,
    4,
    "Wander is a source of its own: a slow random drift each voice has, at this rate. Like LFO 3, it moves things through connections.",
    ~tipW=250.,
  )
  let dim = () => rate->toggleClass("dim", ctx.model->ParamModel.get("LFO_3_Sync") != 0.)
  ctx.model->ParamModel.listen("LFO_3_Sync", dim)
  dim()
  lfoDestinations(ctx, body, "lfo3")
}

//==============================================================================
// the voice

// Microtuning: a Scala scale (and keyboard mapping) instead of the 12 notes above it.
let scale = (ctx: Ctx.t, body, g: Grid.t) => {
  el("div", ~cls="sep", ~parent=body)->place(g->Grid.cx(0) + 3., g->Grid.cy(4) - 1., ~w=4. * g.cw - 8.)->ignore
  // the scale's name, and a "?" at the end of its cells
  g->Grid.claim(0, 4, ~span=2, "the scale name")
  let cell = g->Grid.cell(0, 4, ~span=2)
  let size = Style.controlHeight
  let name = el("div", ~cls="scale", ~parent=body)->placeBox({...cell, w: cell.w - size - 4.})
  Controls.help(
    body,
    "A Scala scale retunes every key in place of the 12 notes above (tune still sets 440 Hz); a keyboard mapping (.kbm) sets which key plays which degree.",
    ~x=cell.x + cell.w - size,
    ~y=cell.y,
    ~size,
    ~tipW=280.,
  )
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
  let update = () => {
    let scaleName = ctx.programs->ProgramStore.tuningName
    name->setTextContent(scaleName->Option.getOr("12 notes"))
    name->toggleClass("on", scaleName != None)
    notes->Array.forEach(e => e->toggleClass("dim", scaleName != None))
  }
  ctx.programs->ProgramStore.onChanged(update)
  update()
}

let voicePanel = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let voice = Panel.make(
    page,
    ~tabs=["voice", "touch", "random", "tuning"],
    ~x=Style.designWidth - margin - lastWidth,
    ~y=top + rowHeight + gap,
    ~w=lastWidth,
    ~h=rowHeight,
  )
  voice->Panel.mark(model, 1, [Features.touch])->ignore
  voice->Panel.mark(model, 2, [Features.random])->ignore
  let markTuning = voice->Panel.mark(model, 3, [Features.tuning], ~also=() =>
    ctx.programs->ProgramStore.tuningName != None
  )
  ctx.programs->ProgramStore.onChanged(markTuning)

  let cw = Grid.fitColumns(lastWidth, 3)
  let v = Grid.make(ctx, voice->Panel.body(0), ~cw)
  v->Grid.choice("PolyMode", 0, 0, "voice mode", ~span=2)
  v->Grid.param("Voices", 2, 0, "polyphony")
  v->Grid.param("Glide", 0, 1, "glide")
  shownWhile(ctx, v, ["Glide"], () => model->ParamModel.get("Glide") > 0., g =>
    g->Grid.choice("GlideMode", 1, 1, "glide mode", ~span=2)
  )
  v->Grid.param("BendRange", 0, 2, "bend range")
  v->Grid.param("GlobalTranspose", 1, 2, "transpose")

  // what aftertouch does to the oscillators (the noise's and the filter's are theirs)
  let touch = Grid.make(ctx, voice->Panel.body(1), ~cw)
  touch->Grid.choice("AftertouchMode", 0, 0, "mode")
  touch->Grid.param("OscAftertouch", 1, 0, "touch > level")
  touch->Grid.param("O1_Afterpitch", 0, 1, "touch > osc 1")
  touch->Grid.param("O2_Afterpitch", 1, 1, "touch > osc 2")

  let random = Grid.make(ctx, voice->Panel.body(2), ~cw)
  random->Grid.param("RandomFreq", 0, 0, "random freq")
  random->Grid.param("RandomPan", 1, 0, "random pan")
  random->Grid.param("RandomAmp", 2, 0, "random amp")
  random->Grid.param("FreqPan", 0, 1, "freq > pan")

  let tuning = Grid.make(ctx, voice->Panel.body(3), ~cw=Grid.fitColumns(lastWidth, 4))
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
  scale(ctx, voice->Panel.body(3), tuning)
}

//==============================================================================

// Draws the eye to a panel a flow node opened.
let flash = (p: Panel.t) => {
  p.el->removeClass("flash")
  requestAnimationFrame(_ => p.el->addClass("flash"))
  setTimeout(() => p.el->removeClass("flash"), 800)->ignore
}

let build = (ctx: Ctx.t, page) => {
  let model = ctx.model
  let osc = oscPanel(ctx, page)
  let filter = filterPanel(ctx, page)

  let ampX = margin + oscWidth + gap + filterWidth + gap
  let amp = Panel.make(page, ~title="amp", ~x=ampX, ~y=top, ~w=lastWidth, ~h=rowHeight)
  let ampBox = {x: 8., y: 25., w: lastWidth - 18., h: rowHeight - 25. - Grid.rowHeight - 12.}
  envelope(ctx, amp.el, EnvEditor.amp, ampBox)
  let ampGrid = Grid.make(ctx, amp.el, ~y=ampBox.y + ampBox.h + 4., ~cw=Grid.fitColumns(lastWidth, 3))
  ampGrid->Grid.param("Gain", 0, 0, "output gain")
  ampGrid->Grid.param("VeloSens", 1, 0, "velocity")
  ampGrid->Grid.param("FreqEnv", 2, 0, "freq > env")

  let modulation = Panel.make(
    page,
    ~tabs=["mod env 1", "mod env 2", "pitch env", "lfo 1", "lfo 2", "lfo 3"],
    ~x=margin,
    ~y=top + rowHeight + gap,
    ~w=modWidth,
    ~h=rowHeight,
  )
  [Features.modEnv1, Features.modEnv2, Features.pitchEnv, Features.lfo1, Features.lfo2, Features.lfo3]->Array.forEachWithIndex(
    (f, i) => modulation->Panel.mark(model, i, [f])->ignore,
  )
  modEnvelope(ctx, modulation->Panel.body(0), 1)
  modEnvelope(ctx, modulation->Panel.body(1), 2)
  pitchEnvelope(ctx, modulation->Panel.body(2))
  lfo(ctx, modulation->Panel.body(3), 1)
  lfo(ctx, modulation->Panel.body(4), 2)
  lfo3(ctx, modulation->Panel.body(5))

  voicePanel(ctx, page)

  VoiceFlow.make(
    ctx,
    page,
    {x: margin, y: margin, w: Style.designWidth - 2. * margin, h: flowHeight},
    ~show=block => {
      let (panel, tab) = switch block {
      | Oscillators => (osc, Some(0))
      | Noise => (osc, Some(1))
      | Unison => (osc, Some(2))
      | Filter => (filter, Some(0))
      | KeyEq => (filter, Some(2))
      | Amp => (amp, None)
      }
      tab->Option.forEach(i => panel->Panel.select(i))
      flash(panel)
    },
  )
}
