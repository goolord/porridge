// The modulation sources' editors: the mod envelopes, the pitch envelope, the LFOs, and the amp
// and filter envelopes as sources. The Synth page's modulation panel shows them in its tabs, and
// the Mod page over its connections when a source is selected; both build them here, for a panel
// w by h (the same layout in each): the source's picture on the left, its controls, and what it
// moves (Destinations) in a column on the right.

open! Web

// the right column (a source's velocity, and what it moves), and the LFOs' controls left of it
let chipsWidth = 176.
let lfoColumn = 82.
let chipsX = w => w - 8. - chipsWidth
let lfoX = w => chipsX(w) - 8. - 3. * lfoColumn

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

// An envelope's editor (each sounding note is marked where it is on the envelopes that have a
// clock).
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
    ~source=?env.source,
  )

// the source's picture, left of its controls
let graphBox = (~right, ~h) => {x: 8., y: 27., w: right - 16., h: h - 37.}

let destinations = (ctx, body, key, ~w, ~y, ~h) =>
  Destinations.make(ctx, body, key, {x: chipsX(w), y, w: chipsWidth, h: h - y - 8.})

// An envelope that is a source (a mod envelope, the amp or filter envelope): its editor, its
// velocity sensitivity, and what it moves.
let envelopeSource = (ctx: Ctx.t, body, env: EnvEditor.envelope, ~velocity, ~w, ~h) => {
  envelope(ctx, body, env, graphBox(~right=chipsX(w), ~h))
  Controls.param(ctx, body, velocity, ~x=chipsX(w), ~y=Grid.padTop, ~w=chipsWidth, ~label="velocity")
  env.source->Option.forEach(key => destinations(ctx, body, key, ~w, ~y=Grid.padTop + Grid.rowHeight, ~h))
}

let modEnvelope = (ctx, body, n, ~w, ~h) => {
  let env = EnvEditor.modEnv(n)
  envelopeSource(ctx, body, env, ~velocity=env.params.prefix ++ "VeloSens", ~w, ~h)
}

let pitchEnvelope = (ctx: Ctx.t, body, ~w, ~h) => {
  let graph = graphBox(~right=chipsX(w), ~h)
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
    ~source=ModEdit.pitchEnvKey,
  )
  let g = Grid.make(ctx, body, ~x=chipsX(w), ~cw=chipsWidth + Grid.columnGap)
  g->Grid.toggle("PEnv_On", 0, 0, "on")
  g->Grid.param("PEnv_VeloSens", 0, 1, "velocity")
}

// The LFOs share a layout: their picture, then shape and mode, rate, delay and fade, and phase,
// in that order as far as each has them, and what they move on the right.
let lfoGrid = (ctx, body, ~w) => Grid.make(ctx, body, ~x=lfoX(w), ~cw=lfoColumn)

// The button in the corner of a plot that opens its table in the shapes editor.
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

let lfo = (ctx: Ctx.t, body, n, ~w, ~h) => {
  let lfo = Int.toString(n)
  let prefix = `LFO_${lfo}_`
  let graph = graphBox(~right=lfoX(w), ~h)
  Plots.lfo(ctx, body, n - 1, graph)
  drawButton(ctx, body, graph, ~status=`Draw LFO ${lfo}'s user shape`, n == 1 ? LfoShape1 : LfoShape2)
  let g = lfoGrid(ctx, body, ~w)
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
  destinations(ctx, body, "lfo" ++ lfo, ~w, ~y=Grid.padTop, ~h)
}

// LFO 3, and the wander source's rate.
let lfo3 = (ctx: Ctx.t, body, ~w, ~h) => {
  Plots.lfo3(ctx, body, graphBox(~right=lfoX(w), ~h))
  let g = lfoGrid(ctx, body, ~w)
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
  g->Grid.help(
    1,
    4,
    "Wander is a source of its own: a slow random drift each voice has, at this rate. Like LFO 3, it moves things through connections.",
    ~tipW=250.,
  )
  let dim = () => rate->toggleClass("dim", ctx.model->ParamModel.get("LFO_3_Sync") != 0.)
  ctx.model->ParamModel.listen("LFO_3_Sync", dim)
  dim()
  destinations(ctx, body, "lfo3", ~w, ~y=Grid.padTop, ~h)
}

// The sources that have an editor here.
let keys = ["lfo1", "lfo2", "lfo3", "modEnv1", "modEnv2", "ampEnv", "filterEnv", ModEdit.pitchEnvKey]

// Source key's editor (one of keys) in body, a panel w by h.
let make = (ctx, body, key, ~w, ~h) =>
  switch key {
  | "lfo1" => lfo(ctx, body, 1, ~w, ~h)
  | "lfo2" => lfo(ctx, body, 2, ~w, ~h)
  | "lfo3" => lfo3(ctx, body, ~w, ~h)
  | "modEnv1" => modEnvelope(ctx, body, 1, ~w, ~h)
  | "modEnv2" => modEnvelope(ctx, body, 2, ~w, ~h)
  | "ampEnv" => envelopeSource(ctx, body, EnvEditor.amp, ~velocity="VeloSens", ~w, ~h)
  | "filterEnv" => envelopeSource(ctx, body, EnvEditor.filter, ~velocity="F_VeloSens", ~w, ~h)
  | "pitchEnv" => pitchEnvelope(ctx, body, ~w, ~h)
  | _ => ()
  }
