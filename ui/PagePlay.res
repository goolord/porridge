// Performance page: the arpeggiator pattern across the top, the XY pad and its targets below.

open! Web

let hint = "Click a step to pick it from a list, right-click to step through them (shift goes back). Drag the XY pad; right-drag keeps its distance from the centre."

let build = (ctx: Ctx.t, page) => {
  let margin = 6.
  let width = Style.designWidth - 2. * margin

  let arpHeight = 27. + 46. + 2. * Grid.rowHeight + Grid.padBottom
  let arp = Panel.make(page, ~title="arpeggiator", ~x=margin, ~y=margin, ~w=width, ~h=arpHeight)
  let inner = width - 18.
  ArpPattern.make(ctx, arp.el, {x: 8., y: 27., w: inner, h: 40.})
  let g = Grid.make(ctx, arp.el, ~y=27. + 46.)
  g->Grid.choice("Arp_Mode", 0, 0, "mode", ~span=2)
  g->Grid.choice("Arp_Unit", 2, 0, "unit", ~span=2)
  g->Grid.param("Arp_Step", 4, 0, "step")
  g->Grid.toggle("Arp_Quantize", 5, 0, "quantize")
  // the extra notes each pattern step plays, and their shifts
  let noteWidth = inner / 7.
  for k in 0 to 6 {
    let x = Grid.padX + Int.toFloat(k) * noteWidth
    let y = g->Grid.cy(1)
    let n = Int.toString(k + 1)
    Controls.toggle(ctx, arp.el, `Arp_Add_${n}_On`, ~x=x + 2., ~y=y + 5., ~label=n)
    Controls.param(ctx, arp.el, `Arp_Add_${n}_Shift`, ~x=x + 24., ~y, ~w=noteWidth - 32., ~label="shift")
  }

  let xyY = arp.y + arp.h + Grid.gap
  let xyHeight = Style.pageHeight - margin - xyY
  let xy = Panel.make(page, ~title="xy", ~x=margin, ~y=xyY, ~w=width, ~h=xyHeight)
  let side = xyHeight - 27. - 10.
  XyPad.make(ctx, xy.el, {x: 8., y: 27., w: side, h: side})
  // the x axis's targets, then the y axis's
  let left = 8. + side + 16.
  let axes = [("H", "XY_X", "x"), ("V", "XY_Y", "y")]
  axes->Array.forEachWithIndex(((axis, position, name), i) => {
    let g = Grid.make(ctx, xy.el, ~x=left + Int.toFloat(i) * (3. * Grid.columnWidth + 30.))
    for k in 1 to 4 {
      let n = Int.toString(k)
      g->Grid.choice(`XY_${axis}_Target_${n}`, 0, k - 1, `${name} target ${n}`, ~span=2)
      g->Grid.param(`XY_${axis}_Depth_${n}`, 2, k - 1, "depth")
    }
    g->Grid.param(position, 0, 5, name)
    g->Grid.param(`XY_${axis}_CC`, 1, 5, name ++ " cc")
  })
  let g = Grid.make(ctx, xy.el, ~x=left)
  g->Grid.param("XY_Var_Radius", 0, 6, "rand radius")
  g->Grid.param("XY_Var_Rate", 1, 6, "rand rate")
}
