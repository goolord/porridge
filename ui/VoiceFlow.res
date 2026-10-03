// The voice's signal flow, a strip of nodes in the order a voice runs them: the oscillators (with
// the noise and unison when they're on), the per-voice effects before the filter (VoiceLane),
// Oatmeal's distortion where Sat_Mode puts it beside the filter, the effects before the amp, the
// amp, those after it and the key EQ; then, on the whole sound, the distortion when it's there and
// the FX page's rack. The voice's part is tinted: each voice runs its own of all of it.
//
// Click a node to open it, drag a per-voice effect, the filter or the amp sideways to move it
// among the voice's effects (right-click an effect for more), and + adds a per-voice effect. A
// node lights while the selected modulation source moves something in it (ModFocus).

open! Web

// the synth page's blocks a node opens
type block = Oscillators | Noise | Unison | Filter | KeyEq | Amp

let make = (ctx: Ctx.t, parent, box: box, ~show: block => unit) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let hover = (e, text) => ctx.status->Status.hover(e, text)
  let strip = Controls.block(parent, "", ~x=box.x, ~y=box.y, ~w=box.w, ~h=box.h)
  strip->addClass("flow")
  let voice = el("div", ~cls="fvoice pervoice", ~parent=strip)
  let whole = el("div", ~cls="fwhole", ~parent=strip)

  let node = (~cls="", text) => el("div", ~cls="fnd " ++ cls, ~text)
  let opener = (e, block) =>
    e->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->preventDefault
        show(block)
      }
    )

  let osc1 = node(~cls="osc", "")
  let osc2 = node(~cls="osc", "")
  let mix = el("span", ~cls="fsep")
  let noise = node("noise")
  let unison = node("")
  let filterNode = node(~cls="grab", "")
  let ampNode = node(~cls="grab", "amp")
  let keyEq = node("key EQ")
  let distNode = () => node(~cls="dist", "")
  let (distPre, distPost, distGlobal) = (distNode(), distNode(), distNode())
  let add = node(~cls="add", "+")
  let fx = node(~cls="fx", "")
  // each block lights while the selected source moves something in it (ModFocus)
  let lights = (e, ids) => model->ModFocus.register(e, ids)
  lights(osc1, () => ["O1_Amp", "O1_PWM_W", "O1_PWM_R", "O1_PWM_D", Modulators.pitchKnob])
  lights(osc2, () => ["O2_Amp", "O2_PWM_W", "O2_PWM_R", "O2_PWM_D", "Transpose", "Detune", Modulators.pitchKnob])
  lights(noise, () => ["N_Amp", "N_Resonance", "N_Transpose", "N_Density"])
  lights(unison, () => ["U_Detune", "U_Spread", "U_Width", "Drift_Pitch"])
  lights(filterNode, () =>
    ["Cutoff", "Resonance", "F_EnvMod", "F_Track", "F_Split", "F_Mix", "F_Morph", "F_Drive", Modulators.envMark("filterEnv")]
  )
  lights(ampNode, () => [Modulators.ampEnvMark, "Gain"])
  opener(osc1, Oscillators)
  opener(osc2, Oscillators)
  opener(noise, Noise)
  opener(unison, Unison)
  opener(keyEq, KeyEq)
  hover(osc1, () => "Oscillator 1: click for the oscillators")
  hover(osc2, () => "Oscillator 2: click for the oscillators")
  hover(noise, () => "The noise generator, beside the oscillators: click for its settings")
  hover(unison, () => "Unison: each oscillator played several times, detuned. Click for its settings")
  hover(keyEq, () => "The key EQ, at the end of each voice: bands on the note's harmonics. Click for it")
  hover(filterNode, () => "The filter: click for it, drag it sideways among the voice's effects")
  hover(ampNode, () =>
    "The amp envelope: drag it sideways. The voice's effects after it react to how each note swells and fades and ring on after it ends; those before it are shaped by it"
  )
  [distPre, distPost, distGlobal]->Array.forEach(e => {
    lights(e, () => FxRack.params(FxRack.oatmealDistortion))
    e->onPointer(#pointerdown, ev =>
      if ev->button == 0 {
        ev->preventDefault
        ctx.openEffect(FxRack.oatmealDistortion)
      }
    )
    hover(e, () =>
      switch e === distGlobal {
      | true => "Oatmeal's distortion, on the whole sound before the rack: click to open it (its \"where\" moves it)"
      | false => "Oatmeal's distortion, in every voice: click to open it (its \"where\" moves it)"
      }
    )
  })
  add->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 0 {
      VoiceLane.addMenu(ctx, add, ~onAdded=_ => ())
    }
  })
  hover(add, () => "Add a per-voice effect (up to four): each voice runs its own copy, which its LFOs, envelopes and key move for that note alone")
  // the rack, by the effects that are on
  let rackOn = () => FxRack.read(get)->Array.filter(e => FxRack.isOn(e, get))
  lights(fx, () => rackOn()->Array.flatMap(FxRack.params))
  fx->onPointer(#pointerdown, ev =>
    if ev->button == 0 {
      ev->preventDefault
      switch (rackOn()[0], FxRack.read(get)[0]) {
      | (Some(e), _) | (None, Some(e)) => ctx.openEffect(e)
      | (None, None) => ()
      }
    }
  )
  hover(fx, () => "The effects on the whole sound, in the order they run: click for the FX page")

  // a per-voice effect's node: its light, its name and ×, made when it first comes into the lane
  let laneNodes = Map.make()
  let itemEl = ref((_: VoiceLane.item) => filterNode)
  let laneNode = (e: FxRack.effect) =>
    switch laneNodes->Map.get(FxRack.value(e)) {
    | Some(n) => n
    | None =>
      let n = node(~cls="lane grab", "")
      lights(n, () => FxRack.params(e))
      let led = el("i", ~cls="led", ~parent=n)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          let id = FxRack.switchId(e)
          model->ParamModel.gestureSet(id, get(id) != 0. ? 0. : FxRack.onValue(e))
        }
      )
      hover(led, () => "Click to switch it on or off")
      let name = el("span", ~parent=n)
      let x = el("b", ~cls="x", ~text="×", ~parent=n)
      x->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        VoiceLane.remove(model, e)
      })
      hover(x, () => "Take it out of the voices (its settings stay)")
      n->onPointer(#pointerdown, ev =>
        VoiceLane.press(ctx, Fx(e), ev, ~itemEl=itemEl.contents, ~onClick=() => ctx.openEffect(e))
      )
      n->suppressContextMenu
      hover(n, () =>
        `${VoiceLane.label(model, e)}, in every voice: ${FxPanels.summary(model, e)->String.replaceAll("\n", ", ")}. Click to open it, drag it sideways to move it, right-click for more`
      )
      let made = (n, name, led)
      laneNodes->Map.set(FxRack.value(e), made)
      made
    }
  itemEl :=
    item =>
      switch item {
      | Fx(e) =>
        let (n, _, _) = laneNode(e)
        n
      | FilterNode => filterNode
      | AmpNode => ampNode
      }
  filterNode->onPointer(#pointerdown, ev =>
    VoiceLane.press(ctx, FilterNode, ev, ~itemEl=itemEl.contents, ~onClick=() => show(Filter))
  )
  ampNode->onPointer(#pointerdown, ev => VoiceLane.press(ctx, AmpNode, ev, ~itemEl=itemEl.contents, ~onClick=() => show(Amp)))
  filterNode->suppressContextMenu
  ampNode->suppressContextMenu

  // what a list shows (Controls.choice), less the "HQ" a wave's icon would show
  let listText = id => {
    let def = model->ParamModel.def(id)
    let i = Float.toInt(get(id))
    let text =
      def.shortNames->Option.orElse(def.names)->Option.flatMap(names => names[i])->Option.getOr(def.shortText(get(id)))
    String.endsWith(text, " HQ") ? String.slice(text, ~start=0, ~end=String.length(text) - 3) : text
  }
  let distMode = label => get("Sat_Mode") == ParamDefs.choiceValue("Sat_Mode", label)

  let layout = () => {
    voice->setTextContent("")
    whole->setTextContent("")
    let put = (box, e) => {
      if box->querySelector(".fnd")->Option.isSome {
        el("span", ~cls="fsep", ~text="›", ~parent=box)->ignore
      }
      box->appendChild(e)
    }
    el("span", ~cls="fgrp", ~text="per-voice", ~parent=voice)->ignore

    // the sources: the oscillators side by side, joined by their mix
    osc1->setTextContent("osc 1 · " ++ listText("O1_Waveform"))
    let transpose = get("Transpose")
    osc2->setTextContent(
      "osc 2 · " ++ listText("O2_Waveform") ++ (transpose != 0. ? " " ++ model->ParamModel.shortText("Transpose") : ""),
    )
    // (an oscillator at no level, simply added, is heard nowhere: Init's osc 2)
    let silent = id => get("OscMix") == 0. && get(id) <= (model->ParamModel.def(id)).min
    osc1->toggleClass("off", silent("O1_Amp"))
    osc2->toggleClass("off", silent("O2_Amp"))
    voice->appendChild(osc1)
    mix->setTextContent(get("OscMix") == 0. ? "+" : listText("OscMix"))
    voice->appendChild(mix)
    voice->appendChild(osc2)
    if get("N_Amp") > 0. {
      // (white, Oatmeal's, is simply noise)
      noise->setTextContent(get("N_Type") == 0. ? "noise" : "noise · " ++ listText("N_Type"))
      el("span", ~cls="fsep", ~text="+", ~parent=voice)->ignore
      voice->appendChild(noise)
    }
    if get("U_Voices") > 1. {
      unison->setTextContent("unison ×" ++ Float.toString(get("U_Voices")))
      el("span", ~cls="fsep", ~text="·", ~parent=voice)->ignore
      voice->appendChild(unison)
    }

    // the lane, with the filter (and the distortion beside it) and the amp among its effects
    let distOn = FxRack.isOn(FxRack.oatmealDistortion, get)
    let distText = "dist · " ++ listText(FxRack.switchId(FxRack.oatmealDistortion))
    let lane = FxRack.readLane(get)
    VoiceLane.items(get)->Array.forEach(item =>
      switch item {
      | Fx(e) =>
        let (n, name, led) = laneNode(e)
        name->setTextContent(FxRack.label(lane, e))
        let on = FxRack.isOn(e, get)
        led->toggleClass("lit", on)
        n->toggleClass("off", !on)
        put(voice, n)
      | FilterNode =>
        if distOn && (distMode("per voice, before filter") || distMode("double (before filter and global)")) {
          distPre->setTextContent(distText)
          put(voice, distPre)
        }
        let filterType = Float.toInt(get("Filter"))
        let cutoff = FilterTypes.cutoffHz(~filterType, get("Cutoff"))
        filterNode->setTextContent(
          filterType == 0
            ? "no filter"
            : `${listText("Filter")} · ${FxGraph.hzText(cutoff)}${get("F_Double") != 0. ? " + 2nd" : ""}`,
        )
        put(voice, filterNode)
        if distOn && distMode("per voice, after filter") {
          distPost->setTextContent(distText)
          put(voice, distPost)
        }
      | AmpNode => put(voice, ampNode)
      }
    )
    if get("KEQ_On") != 0. {
      put(voice, keyEq)
    }
    if !FxRack.laneFull(lane) {
      voice->appendChild(add)
    }

    // the whole sound
    el("span", ~cls="fsep big", ~text="⇒", ~parent=whole)->ignore
    if distOn && (distMode("global") || distMode("double (before filter and global)")) {
      distGlobal->setTextContent(distText)
      put(whole, distGlobal)
    }
    let rack = FxRack.read(get)
    let on = rackOn()
    fx->setTextContent(
      switch on {
      | [] => "FX"
      | on => "FX · " ++ on->Array.map(e => FxRack.label(rack, e))->Array.join(" › ")
      },
    )
    fx->toggleClass("off", on == [])
    put(whole, fx)
  }

  let soon = perFrame(layout)
  model->ParamModel.listenEach(
    [
      ...VoiceLane.ids,
      "O1_Waveform",
      "O2_Waveform",
      "O1_Amp",
      "O2_Amp",
      "Transpose",
      "OscMix",
      "N_Amp",
      "N_Type",
      "U_Voices",
      "Filter",
      "Cutoff",
      "F_Double",
      "KEQ_On",
      "Sat_Mode",
      ...Array.fromInitializer(~length=PorridgeParams.rackSlots, k => PorridgeParams.rackId(k + 1)),
      ...[FxRack.oatmealDistortion, ...FxRack.all]->Array.map(FxRack.switchId),
    ],
    soon,
  )
  layout()
}
