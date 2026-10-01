// The delay's stereo feedback as a diagram: the input splits between the two lines by the
// input pan, and the rotation turns each line's feedback toward the other line. Arrow widths
// show how much goes where; dashed arrows are inverted. Drag the input point sideways for the
// pan, and the point on the dial around for the rotation.

open! Web

let hint = "Drag the input point sideways for the input pan, the point on the dial around for the rotation (shift for fine steps, right-click to reset). Arrow widths show how much of each line's feedback goes where; dashed is inverted."

// A graph filling the panel.
let make = (ctx: Ctx.t, panel, ~pan, ~rotation, ~feedbackL, ~feedbackR) => {
  let g = FxGraph.inPanel(ctx, panel, ~hint)
  let get = id => FxGraph.get(g, id)
  let f = Float.toFixed(_, ~digits=1)

  let boxW = 46.
  let boxH = 22.
  let boxY = 38.
  let (lx, rx) = (10., g.w - 10. - boxW)
  let (cx, cy, radius) = (g.w / 2., boxY + boxH / 2., 17.)
  let (trackL, trackR, trackY) = (lx + boxW / 2., rx + boxW / 2., 10.)

  let arrows = FxGraph.group(g.under)
  let fixed = FxGraph.group(g.under)
  [lx, rx]->Array.forEachWithIndex((x, side) => {
    svgEl(
      fixed,
      "rect",
      [("class", Str("dline")), ("x", Num(x)), ("y", Num(boxY)), ("width", Num(boxW)), ("height", Num(boxH)), ("rx", Num(2.))],
    )->ignore
    FxGraph.text(fixed, ~cls="dlabel", ~anchor="middle", x + boxW / 2., boxY + 15., side == 0 ? "line L" : "line R")
  })
  FxGraph.line(fixed, ~cls="axis", trackL, trackY, trackR, trackY)
  FxGraph.text(fixed, ~anchor="middle", cx, trackY - 2., "in")
  svgEl(fixed, "circle", [("class", Str("dial")), ("cx", Num(cx)), ("cy", Num(cy)), ("r", Num(radius))])->ignore
  let needle = svgEl(fixed, "line", [("class", Str("needle"))])

  let panHandle = FxGraph.handle(
    g,
    ~cursor="ew-resize",
    ~ids=[pan],
    ~statusOnDrag=false,
    ~drag=({x}) => FxGraph.set(g, pan, (x - trackL) / (trackR - trackL)),
    ~wheel=pan,
  )
  let rotHandle = FxGraph.handle(
    g,
    ~r=5.,
    ~cursor="grab",
    ~ids=[rotation],
    ~statusOnDrag=false,
    // 0 points up, positive turns clockwise
    ~drag=({x, y}) => FxGraph.set(g, rotation, Math.atan2(~y=x - cx, ~x=-.(y - cy))),
    ~wheel=rotation,
  )

  // A curve from (x0, y0) to (x1, y1) through two control points, with a head at its end.
  let arrow = (~width, ~dashed, (x0, y0), (c1x, c1y), (c2x, c2y), (x1, y1)) => {
    let cls = "flow" ++ (dashed ? " neg" : "") ++ (width < 0.05 ? " none" : "")
    let w = 0.8 + Math.min(2., width) * 1.6
    svgEl(
      arrows,
      "path",
      [
        ("class", Str(cls)),
        ("stroke-width", Num(w)),
        ("d", Str(`M${f(x0)} ${f(y0)}C${f(c1x)} ${f(c1y)} ${f(c2x)} ${f(c2y)} ${f(x1)} ${f(y1)}`)),
      ],
    )->ignore
    let (dx, dy) = (x1 - c2x, y1 - c2y)
    let len = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy))
    let (ux, uy) = (dx / len, dy / len)
    let s = 4. + w
    let (ax, ay) = (x1 - ux * s - uy * s * 0.55, y1 - uy * s + ux * s * 0.55)
    let (bx, by) = (x1 - ux * s + uy * s * 0.55, y1 - uy * s - ux * s * 0.55)
    svgEl(
      arrows,
      "path",
      [("class", Str("flowhead" ++ (width < 0.05 ? " none" : ""))), ("d", Str(`M${f(ax)} ${f(ay)}L${f(x1)} ${f(y1)}L${f(bx)} ${f(by)}`))],
    )->ignore
  }

  let draw = () => {
    arrows->setTextContent("")
    let p = get(pan)
    let (panL, panR) = (2. - 2. * p, 2. * p)
    let r = get(rotation)
    let (fbL, fbR) = (get(feedbackL), get(feedbackR))
    let (c, s) = (Math.cos(r), Math.sin(r))
    // the feedback matrix: L->L, R->L, L->R, R->R
    let (a, b, cc, d) = (c * fbL, -.s * fbR, s * fbL, c * fbR)
    let ix = trackL + p * (trackR - trackL)
    panHandle->FxGraph.place(ix, trackY)
    // input into each line
    arrow(~width=panL / 2., ~dashed=false, (ix, trackY + 4.), (ix - 10., trackY + 18.), (lx + boxW / 2., boxY - 14.), (lx + boxW / 2., boxY - 1.))
    arrow(~width=panR / 2., ~dashed=false, (ix, trackY + 4.), (ix + 10., trackY + 18.), (rx + boxW / 2., boxY - 14.), (rx + boxW / 2., boxY - 1.))
    let bottom = boxY + boxH
    // each line back into itself, under it
    arrow(~width=Math.abs(a), ~dashed=a < 0., (lx + 8., bottom + 1.), (lx - 4., bottom + 30.), (lx + boxW + 4., bottom + 30.), (lx + boxW - 8., bottom + 2.))
    arrow(~width=Math.abs(d), ~dashed=d < 0., (rx + boxW - 8., bottom + 1.), (rx + boxW + 4., bottom + 30.), (rx - 4., bottom + 30.), (rx + 8., bottom + 2.))
    // and across, under the dial
    arrow(~width=Math.abs(cc), ~dashed=cc < 0., (lx + boxW, bottom - 4.), (cx - 20., bottom + 16.), (cx + 20., bottom + 16.), (rx - 1., bottom - 4.))
    arrow(~width=Math.abs(b), ~dashed=b < 0., (rx, bottom + 6.), (cx + 20., bottom + 32.), (cx - 20., bottom + 32.), (lx + boxW + 1., bottom + 6.))
    let (nx, ny) = (cx + Math.sin(r) * radius, cy - Math.cos(r) * radius)
    needle->setAttribute("x1", Num(cx))
    needle->setAttribute("y1", Num(cy))
    needle->setAttribute("x2", Num(nx))
    needle->setAttribute("y2", Num(ny))
    rotHandle->FxGraph.place(nx, ny)
    switch g.focus {
    | Some(id) =>
      let h = id == pan ? panHandle : rotHandle
      let text =
        id == pan
          ? `input pan ${FxGraph.short(g, pan)}`
          : `rotation ${FxGraph.short(g, rotation)}: L > R ${Float.toFixed(cc * 100., ~digits=0)} %, R > L ${Float.toFixed(b * 100., ~digits=0)} %`
      g->FxGraph.readout(~x=h.x, ~y=h.y + (id == pan ? 22. : 0.), text)
    | None => g->FxGraph.hideReadout
    }
  }
  g.redraw = draw

  let redraw = FxGraph.redraw(g, draw)
  g->FxGraph.listen([pan, rotation, feedbackL, feedbackR], redraw.request)
  redraw
}
