// Effects page, in signal order: distortion and chorus, delay, reverb, and the EQ as a
// curve to drag.

open! Web

let hint = "Drag or scroll to change a value, shift for fine steps. Double-click to type, right-click to reset. Click a list to pick from it, right-click to step through it."

let build = (ctx: Ctx.t, page) => {
  let (margin, gap) = (6., Grid.gap)
  let columnWidth = 358.
  let x1 = margin + columnWidth + gap
  let x2 = x1 + columnWidth + gap
  let lastWidth = Style.designWidth - margin - x2

  let distortion = Panel.make(
    page,
    ~title="distortion",
    ~x=margin,
    ~y=margin,
    ~w=columnWidth,
    ~h=Grid.panelHeight(2),
  )
  let g = Grid.make(ctx, distortion.el)
  g->Grid.choice("Sat_Type", 0, 0, "type")
  g->Grid.choice("Sat_Mode", 1, 0, "mode", ~span=2)
  g->Grid.choice("Sat_Oversample", 3, 0, "oversample")
  g->Grid.param("Sat_Pregain", 0, 1, "pregain")
  g->Grid.param("Sat_Limit", 1, 1, "limit")
  g->Grid.param("Sat_Postgain", 2, 1, "postgain")

  let chorus = Panel.make(
    page,
    ~title="chorus",
    ~x=margin,
    ~y=distortion->Panel.bottom,
    ~w=columnWidth,
    ~h=Grid.panelHeight(2),
  )
  let g = Grid.make(ctx, chorus.el)
  g->Grid.choice("C_Mode", 0, 0, "mode")
  g->Grid.choice("C_Stereo", 1, 0, "stereo")
  g->Grid.param("C_Rate", 2, 0, "rate")
  g->Grid.param("C_Voices", 3, 0, "voices")
  g->Grid.param("C_MinDelay", 0, 1, "delay")
  g->Grid.param("C_Depth", 1, 1, "range")
  g->Grid.param("C_Feedback", 2, 1, "feedback")
  g->Grid.param("C_Mix", 3, 1, "mix")

  let rowHeight = chorus.y + chorus.h - margin

  let delay = Panel.make(page, ~title="delay", ~x=x1, ~y=margin, ~w=columnWidth, ~h=rowHeight)
  delay->Panel.headerToggle(ctx, "D_On", ~label="on")
  let g = Grid.make(ctx, delay.el)
  g->Grid.choice("D_Unit", 0, 0, "unit")
  g->Grid.toggle("D_Quantize", 1, 0, "quantize")
  g->Grid.param("D_InputPan", 2, 0, "input pan")
  g->Grid.param("D_Rotation", 3, 0, "rotation")
  g->Grid.param("D_LengthL", 0, 1, "length l")
  g->Grid.param("D_FeedbackL", 1, 1, "feedback l")
  g->Grid.choice("D_ReverseL", 2, 1, "reverse l")
  g->Grid.param("D_LP", 3, 1, "lowpass")
  g->Grid.param("D_LengthR", 0, 2, "length r")
  g->Grid.param("D_FeedbackR", 1, 2, "feedback r")
  g->Grid.choice("D_ReverseR", 2, 2, "reverse r")
  g->Grid.param("D_HP", 3, 2, "highpass")
  g->Grid.param("D_Dry", 0, 3, "dry")
  g->Grid.param("D_Wet", 1, 3, "wet")

  let reverb = Panel.make(page, ~title="reverb", ~x=x2, ~y=margin, ~w=lastWidth, ~h=rowHeight)
  reverb->Panel.headerToggle(ctx, "R_On", ~label="on")
  let g = Grid.make(ctx, reverb.el)
  g->Grid.param("R_Size", 0, 0, "room size")
  g->Grid.param("R_Length", 1, 0, "length")
  g->Grid.param("R_Predelay", 2, 0, "predelay")
  g->Grid.param("R_EarlyMix", 3, 0, "early")
  g->Grid.param("R_Dullness", 0, 1, "dull")
  g->Grid.param("R_Brightness", 1, 1, "bright")
  g->Grid.param("R_Dry", 2, 1, "dry")
  g->Grid.param("R_Wet", 3, 1, "wet")
  g->Grid.param("R_1", 0, 2, "angle 1")
  g->Grid.param("R_2", 1, 2, "angle 2")
  g->Grid.param("R_3", 2, 2, "angle 3")
  g->Grid.param("R_Rotation", 3, 2, "rotate")

  let eqY = delay->Panel.bottom
  let eqHeight = Style.pageHeight - margin - eqY
  let eq = Panel.make(
    page,
    ~title="eq",
    ~x=margin,
    ~y=eqY,
    ~w=Style.designWidth - 2. * margin,
    ~h=eqHeight,
  )
  EqEditor.make(ctx, eq.el, {x: 8., y: 25., w: eq.w - 18., h: eqHeight - 25. - 10.})
}
