// Main page. Block arrangement follows the original default skin's reading order:
// sound sources top-left, filter and envelopes next to them, modulation in the middle,
// global settings right, effects and performance controls along the bottom.

open Grid

let hint = "Drag or scroll to change a value, shift for fine steps. Double-click to type, right-click to reset."

let envelopeRows = (g, prefix, row) => {
  g->param(prefix ++ "Attack", 0, row, "attack")
  g->param(prefix ++ "Hold", 1, row, "hold")
  g->param(prefix ++ "Decay1", 2, row, "decay 1")
  g->param(prefix ++ "Breakpoint", 3, row, "breakpoint")
  g->param(prefix ++ "Decay2", 0, row + 1, "decay 2")
  g->param(prefix ++ "Sustain", 1, row + 1, "sustain")
  g->param(prefix ++ "Release", 2, row + 1, "release")
}

let modEnvelope = (ctx, page, title, prefix, ~x, ~y) => {
  let g = Grid.make(ctx, page, title, ~x, ~y, ~cols=4, ~rows=4)
  envelopeRows(g, prefix, 0)
  g->param(prefix ++ "VeloSens", 3, 1, "velocity")
  for k in 0 to 3 {
    let (c, r) = (mod(k, 2) * 2, 2 + k / 2)
    let n = Int.toString(k + 1)
    g->choice(`${prefix}Target_${n}`, c, r, "target " ++ n)
    g->param(`${prefix}Depth_${n}`, c + 1, r, "depth")
  }
  g
}

let lfo = (ctx: Ctx.t, page, n, ~x, ~y) => {
  let lfo = Int.toString(n)
  let prefix = `LFO_${lfo}_`
  let g = Grid.make(ctx, page, "lfo " ++ lfo, ~x, ~y, ~cols=3, ~rows=5)
  g->choice(prefix ++ "Shape", 0, 0, "shape")
  g->choice(prefix ++ "Sync", 1, 0, "mode", ~span=2)
  g->choice(prefix ++ "Unit", 0, 1, "unit")
  g->param(prefix ++ "Speed", 1, 1, "rate")
  g->toggle(prefix ++ "Quantize", 2, 1, "quantize")
  g->param(prefix ++ "Cutoff_1", 0, 2, "cut 1")
  g->param(prefix ++ "Cutoff_2", 1, 2, "cut 2")
  g->param(prefix ++ "Resonance", 2, 2, "res")
  g->param(prefix ++ "Pitch", 0, 3, "pitch")
  g->param(prefix ++ "Pan", 1, 3, "pan")
  g->param(n == 1 ? "LFO_1_2" : "LFO_2_1", 2, 3, n == 1 ? "rate 2" : "rate 1")
  Plots.lfo(ctx, g.el, n - 1, g->box(0, 4, 2, 1))
  g->button("edit", 2, 4, ~w=52., ~status=`Draw LFO ${lfo}'s user shape`, () =>
    ctx.openShape(n == 1 ? LfoShape1 : LfoShape2)
  )
  g
}

let build = (ctx: Ctx.t, page) => {
  let block = (title, ~x, ~y, ~cols, ~rows, ~w=?) =>
    Grid.make(ctx, page, title, ~x, ~y, ~cols, ~rows, ~w?)
  let (x0, y0) = (6., 6.)

  //==============================================================================
  // column 1: oscillators, noise, unison
  let osc = block("oscs", ~x=x0, ~y=y0, ~cols=3, ~rows=8)
  osc->choice("O1_Waveform", 0, 0, "1 waveform")
  osc->param("O1_Amp", 0, 1, "amp")
  osc->param("O1_Afterpitch", 0, 2, "touch > pitch")
  osc->param("O1_PWM_W", 1, 0, "pulsewidth")
  osc->param("O1_PWM_R", 1, 1, "pwm rate")
  osc->param("O1_PWM_D", 1, 2, "pwm depth")
  Plots.wave(ctx, osc.el, 0, osc->box(2, 0, 1, 2))
  osc->button("edit", 2, 2, ~w=52., ~status="Draw oscillator 1's user waveform", () =>
    ctx.openShape(Wave1)
  )
  Web.el("div", ~cls="sep", ~parent=osc.el)
  ->Web.style
  ->Web.setCssText(`left:${Web.px(padX)};right:${Web.px(padX)};top:${Web.px(cy(3) - 1.)}`)
  osc->choice("O2_Waveform", 0, 3, "2 waveform")
  osc->param("O2_Amp", 0, 4, "amp")
  osc->param("O2_Afterpitch", 0, 5, "touch > pitch")
  osc->param("O2_PWM_W", 1, 3, "pulsewidth")
  osc->param("O2_PWM_R", 1, 4, "pwm rate")
  osc->param("O2_PWM_D", 1, 5, "pwm depth")
  Plots.wave(ctx, osc.el, 1, osc->box(2, 3, 1, 2))
  osc->button("edit", 2, 5, ~w=52., ~status="Draw oscillator 2's user waveform", () =>
    ctx.openShape(Wave2)
  )
  osc->param("Transpose", 0, 6, "2 transpose")
  osc->param("Detune", 1, 6, "2 detune")
  osc->param("OscAftertouch", 2, 6, "touch > amp")
  osc->choice("OscMix", 0, 7, "mix", ~span=2)

  let noise = block("noise", ~x=x0, ~y=osc->bottom, ~cols=3, ~rows=2)
  noise->param("N_Amp", 0, 0, "amp")
  noise->param("N_Aftertouch", 1, 0, "touch > amp")
  noise->param("N_Resonance", 0, 1, "resonance")
  noise->param("N_Transpose", 1, 1, "transpose")

  let unison = block("unison", ~x=x0, ~y=noise->bottom, ~cols=3, ~rows=2)
  unison->param("U_Voices", 0, 0, "voices")
  unison->param("U_Detune", 1, 0, "detune")
  unison->param("U_Spread", 2, 0, "spread")
  unison->param("U_PitchJitter", 0, 1, "pitch jitter")
  unison->param("U_PanJitter", 1, 1, "pan jitter")

  //==============================================================================
  // column 2: filter, amp envelope, distortion
  let x1 = osc->right
  let filter = block("filter", ~x=x1, ~y=y0, ~cols=4, ~rows=7)
  filter->choice("Filter", 0, 0, "type", ~span=2)
  filter->choice("Filter2", 2, 0, "filter 2", ~span=2)
  filter->param("Cutoff", 0, 1, "cutoff")
  filter->param("F_Track", 1, 1, "track")
  filter->param("Resonance", 2, 1, "reso")
  filter->param("F_Aftertouch", 3, 1, "touch")
  filter->choice("F_Double", 0, 2, "double")
  filter->param("F_Split", 1, 2, "split")
  filter->param("F_Mix", 2, 2, "mix")
  filter->param("F_Speed", 3, 2, "speed ratio")
  filter->param("F_EnvMod", 0, 3, "env mod")
  filter->param("F_VeloSens", 1, 3, "velocity")
  Plots.envelope(ctx, filter.el, "F_", filter->box(2, 3, 2, 1))
  envelopeRows(filter, "F_", 4)

  let amp = block("envelope", ~x=x1, ~y=filter->bottom, ~cols=4, ~rows=3)
  envelopeRows(amp, "", 0)
  Plots.envelope(ctx, amp.el, "", amp->box(0, 2, 4, 1))

  let distortion = block("distortion", ~x=x1, ~y=amp->bottom, ~cols=4, ~rows=2)
  distortion->choice("Sat_Type", 0, 0, "type")
  distortion->choice("Sat_Mode", 1, 0, "mode", ~span=2)
  distortion->choice("Sat_Oversample", 3, 0, "oversample")
  distortion->param("Sat_Pregain", 0, 1, "pregain")
  distortion->param("Sat_Limit", 1, 1, "limit")
  distortion->param("Sat_Postgain", 2, 1, "postgain")

  //==============================================================================
  // column 3: mod envelopes, pitch envelope
  let x2 = filter->right
  let mod1 = modEnvelope(ctx, page, "mod env 1", "M1_", ~x=x2, ~y=y0)
  let mod2 = modEnvelope(ctx, page, "mod env 2", "M2_", ~x=x2, ~y=mod1->bottom)

  let pitch = block("pitch env", ~x=x2, ~y=mod2->bottom, ~cols=4, ~rows=4)
  pitch->param("PEnv_Start", 0, 0, "start")
  pitch->param("PEnv_Attack", 1, 0, "attack")
  pitch->param("PEnv_Peak", 2, 0, "peak")
  pitch->param("PEnv_Decay", 3, 0, "decay")
  pitch->param("PEnv_Sustain", 0, 1, "sustain")
  pitch->param("PEnv_Release", 1, 1, "release")
  pitch->param("PEnv_VeloSens", 2, 1, "velocity")
  pitch->toggle("PEnv_On", 3, 1, "on")

  //==============================================================================
  // column 4: LFOs, phase
  let x3 = mod1->right
  let lfo1 = lfo(ctx, page, 1, ~x=x3, ~y=y0)
  let lfo2 = lfo(ctx, page, 2, ~x=x3, ~y=lfo1->bottom)

  let phase = block("phase", ~x=x3, ~y=lfo2->bottom, ~cols=3, ~rows=3)
  phase->param("OscPhase", 0, 0, "osc")
  phase->param("OscPhaseRand", 1, 0, "osc rand")
  phase->toggle("OscRetrig", 2, 0, "retrigger")
  phase->param("PWMPhase", 0, 1, "pwm")
  phase->param("PWMPhaseRand", 1, 1, "pwm rand")
  phase->toggle("PWMRetrig", 2, 1, "retrigger")
  phase->param("LFOPhase", 0, 2, "lfo")
  phase->param("LFOPhaseRand", 1, 2, "lfo rand")
  phase->toggle("LFORetrig", 2, 2, "retrigger")

  //==============================================================================
  // column 5: voice ("hodgepodge"), tuning
  let x4 = lfo1->right
  let voice = block("hodgepodge", ~x=x4, ~y=y0, ~cols=3, ~rows=5)
  voice->param("Gain", 0, 0, "output gain")
  voice->param("VeloSens", 1, 0, "velocity")
  voice->choice("AftertouchMode", 2, 0, "touch")
  voice->choice("PolyMode", 0, 1, "voice mode", ~span=2)
  voice->param("Voices", 2, 1, "polyphony")
  voice->param("Glide", 0, 2, "glide")
  voice->choice("GlideMode", 1, 2, "glide mode", ~span=2)
  voice->param("BendRange", 0, 3, "bend range")
  voice->param("GlobalTranspose", 1, 3, "transpose")
  voice->param("RandomFreq", 2, 3, "random freq")
  voice->param("RandomPan", 0, 4, "random pan")
  voice->param("RandomAmp", 1, 4, "random amp")
  voice->param("FreqPan", 2, 4, "freq > pan")

  let tuning = block("tuning", ~x=x4, ~y=voice->bottom, ~cols=3, ~rows=6)
  tuning->param("Tune_Main", 0, 0, "tune")
  tuning->param("Tune_Octave", 1, 0, "octave")
  tuning->param("FreqEnv", 2, 0, "freq > env")
  tuning->param("Tune_CutReference", 0, 1, "cut ref")
  tuning->param("Tune_PanReference", 1, 1, "pan ref")
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
  ]->Array.forEachWithIndex(((id, label), i) => tuning->param(id, mod(i, 3), 2 + i / 3, label))

  //==============================================================================
  // bottom band: XY, arpeggiator, effects
  let columns = [unison, distortion, pitch, phase, tuning]
  let yb = Math.maxMany(columns->Array.map(bottom))
  columns->Array.forEach(b => b->stretchTo(yb))
  Plots.pitchEnvelope(
    ctx,
    pitch.el,
    {...pitch->box(0, 2, 4, 2), h: pitch.h - cy(2) - padBottom - 6.},
  )

  let xy = block("xy", ~x=x0, ~y=yb, ~cols=6, ~rows=5)
  XyPad.make(
    ctx,
    xy.el,
    {x: padX + 2., y: padTop + 2., w: 2. * columnWidth - 6., h: 4. * rowHeight - 6.},
  )
  for k in 1 to 4 {
    let n = Int.toString(k)
    xy->choice(`XY_H_Target_${n}`, 2, k - 1, "x target " ++ n)
    xy->param(`XY_H_Depth_${n}`, 3, k - 1, "depth")
    xy->choice(`XY_V_Target_${n}`, 4, k - 1, "y target " ++ n)
    xy->param(`XY_V_Depth_${n}`, 5, k - 1, "depth")
  }
  xy->param("XY_Var_Radius", 0, 4, "rand radius")
  xy->param("XY_Var_Rate", 1, 4, "rand rate")
  xy->param("XY_X", 2, 4, "x")
  xy->param("XY_H_CC", 3, 4, "x cc")
  xy->param("XY_Y", 4, 4, "y")
  xy->param("XY_V_CC", 5, 4, "y cc")

  let arp = block("arp", ~x=xy->right, ~y=yb, ~cols=6, ~rows=5)
  ArpPattern.make(
    ctx,
    arp.el,
    {x: padX + 2., y: padTop + 2., w: 6. * columnWidth - 6., h: 2. * rowHeight - 4.},
  )
  arp->choice("Arp_Mode", 0, 2, "mode", ~span=2)
  arp->choice("Arp_Unit", 2, 2, "unit", ~span=2)
  arp->param("Arp_Step", 4, 2, "step")
  arp->toggle("Arp_Quantize", 5, 2, "quantize")
  for k in 0 to 6 {
    let x = arp->cx(0) + Int.toFloat(mod(k, 4)) * 111.
    let y = cy(3 + k / 4)
    let n = Int.toString(k + 1)
    Controls.toggle(ctx, arp.el, `Arp_Add_${n}_On`, ~x=x + 3., ~y=y + 5., ~label=n)
    Controls.param(ctx, arp.el, `Arp_Add_${n}_Shift`, ~x=x + 26., ~y, ~w=80., ~label="shift")
  }

  let chorus = block("chorus", ~x=arp->right, ~y=yb, ~cols=2, ~rows=5)
  chorus->choice("C_Mode", 0, 0, "mode")
  chorus->choice("C_Stereo", 1, 0, "stereo")
  chorus->param("C_Rate", 0, 1, "rate")
  chorus->param("C_Voices", 1, 1, "voices")
  chorus->param("C_MinDelay", 0, 2, "delay")
  chorus->param("C_Depth", 1, 2, "range")
  chorus->param("C_Feedback", 0, 3, "feedback")
  chorus->param("C_Mix", 1, 3, "mix")

  let delay = block("delay", ~x=chorus->right, ~y=yb, ~cols=3, ~rows=5)
  delay->toggle("D_On", 0, 0, "on")
  delay->choice("D_Unit", 1, 0, "unit")
  delay->toggle("D_Quantize", 2, 0, "quantize")
  delay->param("D_LengthL", 0, 1, "length l")
  delay->param("D_FeedbackL", 1, 1, "feedback l")
  delay->choice("D_ReverseL", 2, 1, "reverse l")
  delay->param("D_LengthR", 0, 2, "length r")
  delay->param("D_FeedbackR", 1, 2, "feedback r")
  delay->choice("D_ReverseR", 2, 2, "reverse r")
  delay->param("D_InputPan", 0, 3, "input pan")
  delay->param("D_Rotation", 1, 3, "rotation")
  delay->param("D_LP", 2, 3, "lowpass")
  delay->param("D_Dry", 0, 4, "dry")
  delay->param("D_Wet", 1, 4, "wet")
  delay->param("D_HP", 2, 4, "highpass")

  let yc = xy->bottom
  let eq = block("eq", ~x=x0, ~y=yc, ~cols=10, ~rows=2)
  for b in 0 to 4 {
    let n = Int.toString(b + 1)
    eq->choice(`EQ_${n}_Type`, 2 * b, 0, "band " ++ n)
    eq->param(`EQ_${n}_Freq`, 2 * b + 1, 0, "freq")
    eq->param(`EQ_${n}_Amp`, 2 * b, 1, "amp")
    eq->param(`EQ_${n}_Slope`, 2 * b + 1, 1, "slope")
  }

  let reverb = block(
    "reverb",
    ~x=eq->right,
    ~y=yc,
    ~cols=7,
    ~rows=2,
    ~w=delay.x + delay.w - eq->right,
  )
  reverb->toggle("R_On", 0, 0, "on")
  reverb->param("R_Size", 1, 0, "room size")
  reverb->param("R_Length", 2, 0, "length")
  reverb->param("R_Predelay", 3, 0, "predelay")
  reverb->param("R_EarlyMix", 4, 0, "early")
  reverb->param("R_Dry", 5, 0, "dry")
  reverb->param("R_Wet", 6, 0, "wet")
  reverb->param("R_Dullness", 0, 1, "dull")
  reverb->param("R_Brightness", 1, 1, "bright")
  reverb->param("R_1", 2, 1, "angle 1")
  reverb->param("R_2", 3, 1, "angle 2")
  reverb->param("R_3", 4, 1, "angle 3")
  reverb->param("R_Rotation", 5, 1, "rotate")
}
