// Performance page: the arpeggiator pattern across the top, the XY pad and its targets below.

open! Web

let hint = "Click a step to pick it from a list, right-click to step through them (shift goes back). Drag the XY pad; right-drag keeps its distance from the centre. The pitch wheel springs back when you let go; the mod wheel stays."

let build = (ctx: Ctx.t, page) => {
  let margin = 6.
  let width = Style.designWidth - 2. * margin

  let arpHeight = 27. + 46. + 2. * Grid.rowHeight + Grid.padBottom
  let arp = Panel.make(page, ~title="arpeggiator", ~x=margin, ~y=margin, ~w=width, ~h=arpHeight)
  ArpPattern.make(ctx, arp.el, {x: 8., y: 27., w: width - 18., h: 40.})
  let g = Grid.make(ctx, arp.el, ~y=27. + 46.)
  g->Grid.choice("Arp_Mode", 0, 0, "mode", ~span=2)
  g->Grid.choice("Arp_Unit", 2, 0, "unit", ~span=2)
  g->Grid.param("Arp_Step", 4, 0, "step")
  g->Grid.toggle("Arp_Quantize", 5, 0, "quantize")
  // the extra notes each pattern step plays, and their shifts: seven groups of four narrow
  // columns, a switch in one and the shift across the other three
  let notes = Grid.make(ctx, arp.el, ~y=g->Grid.cy(1), ~cw=Grid.fitColumns(width, 28))
  for k in 0 to 6 {
    let n = Int.toString(k + 1)
    notes->Grid.toggle(`Arp_Add_${n}_On`, 4 * k, 0, n)
    notes->Grid.param(`Arp_Add_${n}_Shift`, 4 * k + 1, 0, `note ${n} shift`, ~span=3)
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

  // the pitch and mod wheels, at the panel's right edge
  let wheelsWidth = 108.
  Wheels.make(ctx, xy.el, {x: width - 14. - wheelsWidth, y: 27., w: wheelsWidth, h: side})
}
