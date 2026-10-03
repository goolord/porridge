// The patch summary on the Play page: what the current program is made of, a line each for its
// oscillators, filter, envelopes, modulation and effects, each a link to where it is edited. The
// first three are PatchGen's descriptions (as the Random drawer's cards have them); modulation
// lists every system's routings (Modulators), Oatmeal's included, and the effects line the ones
// that are on, per-voice first.

open! Web

// the note the filter's cutoff is told relative to (PatchGen's "at 2.5×")
let note = 48

// What each source moves, by source: "LFO 1 > cutoff, resonance; mod env 1 > osc 2 pitch", as the
// Mod page lists them. The filter envelope's amount is the filter line's.
let modText = (ctx: Ctx.t, get) => {
  let name = (s: ModMatrix.source, i) =>
    switch ModEdit.macroOf(i) {
    | Some(m) => ModEdit.macroName(ctx.programs, m)
    | None => s.label
    }
  // a connection's target, with the source that scales it as PatchGen writes it: "cutoff (sweep)"
  let label = (r: Modulators.route) =>
    switch r.via {
    | Connection(k) =>
      let via = ModMatrix.readSlot(get, k).via
      via == 0 ? r.label : `${r.label} (${ModMatrix.sources[via]->Option.mapOr("", s => name(s, via))})`
    | _ => r.label
    }
  let connections = Modulators.connections(get)
  let parts = ModMatrix.sources->Array.filterMapWithIndex((s, i) => {
    // (each target once: an LFO can reach the cutoff by its own depth and by a connection)
    let targets =
      i == 0
        ? []
        : Modulators.fromAmong(get, connections, s.key)
          ->Array.filter(r => get(r.amount) != 0. && r.amount != "F_EnvMod")
          ->Array.map(label)
          ->Array.reduce([], (seen, l) => seen->Array.includes(l) ? seen : [...seen, l])
    targets == [] ? None : Some(`${name(s, i)} > ${targets->Array.join(", ")}`)
  })
  parts == [] ? "none" : parts->Array.join("; ")
}

// The effects that are on, in the order the sound goes through them: per-voice, then the whole
// sound's ("per-voice asymmetric, phaser → chorus, reverb").
let fxText = get => {
  let distName = DistTypes.all[Float.toInt(get("Sat_Type"))]->Option.mapOr("distortion", t => t.name)
  let mode = get("Sat_Mode")
  let distWhole = mode == ParamDefs.choiceValue("Sat_Mode", "global")
  let distBoth = mode == ParamDefs.choiceValue("Sat_Mode", "double (before filter and global)")
  let distOn = FxRack.isOn(FxRack.oatmealDistortion, get)
  let lane = FxRack.readLane(get)
  let rack = FxRack.read(get)
  let on = (list, e) => FxRack.isOn(e, get) ? Some(FxRack.label(list, e)) : None
  let voice = [...distOn && !distWhole ? [distName] : [], ...lane->Array.filterMap(on(lane, _))]
  let whole = [...distOn && (distWhole || distBoth) ? [distName] : [], ...rack->Array.filterMap(on(rack, _))]
  switch (voice, whole) {
  | ([], []) => "dry"
  | ([], whole) => whole->Array.join(", ")
  | (voice, []) => "per-voice " ++ voice->Array.join(", ")
  | (voice, whole) => `per-voice ${voice->Array.join(", ")} → ${whole->Array.join(", ")}`
  }
}

// how long the summary waits after a change before it is written again
let throttleMs = 250
let lineHeight = 19.

let make = (ctx: Ctx.t, parent, ~x, ~y, ~w, ~h) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let panel = Panel.make(parent, ~title="patch", ~x, ~y, ~w, ~h)
  // a line opens the panel that edits it (the one with the control `id`), and draws the eye to it
  let toPanel = id => () =>
    Reach.reach(model, id)->Option.forEach(e => e->Reach.panelOf->Option.forEach(Reach.flash))
  let lines = [
    ("osc", () => PatchGen.oscText(model.values), "the oscillators, on the Synth page", toPanel("O1_Waveform")),
    ("filter", () => PatchGen.filterText(model.values, ~note), "the filter, on the Synth page", toPanel("Filter")),
    ("env", () => PatchGen.envText(model.values), "the amp envelope, on the Synth page", toPanel("VeloSens")),
    ("mod", () => modText(ctx, get), "the connections, on the Mod page", () => ctx.openPage(#mod)),
    ("fx", () => fxText(get), "the effects, on the FX page", () => ctx.openPage(#fx)),
  ]->Array.mapWithIndex(((tag, text, where, open_), i) => {
    let row = el("div", ~cls="psum", ~parent=panel.el)->place(Grid.padX, Grid.padTop + Int.toFloat(i) * lineHeight, ~w=w - 2. * Grid.padX - 2.)
    el("b", ~text=tag, ~parent=row)->ignore
    let span = el("span", ~parent=row)
    ctx.status->Status.hover(row, () => `${tag}: ${text()}. Click to open ${where}.`)
    row->onMouse(#click, _ => open_())
    (span, text)
  })
  let update = () => lines->Array.forEach(((span, text)) => span->setTextContent(text()))
  let pending = ref(false)
  let schedule = () =>
    if !pending.contents {
      pending := true
      setTimeout(() => {
        pending := false
        update()
      }, throttleMs)->ignore
    }
  // (the wheels aren't part of the program)
  model->ParamModel.listenAny(id =>
    if !PorridgeParams.isPerformance(id) {
      schedule()
    }
  )
  ctx.programs->ProgramStore.onChanged(schedule)
  update()
}
