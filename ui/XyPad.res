// XY pad: drag to set X/Y (-1..1). Right-button drag keeps the distance to the centre
// constant (moves around a circle), middle click centres. The dashed circle shows the
// random-walk radius; the small ring shows where the synth currently is (if the patch
// reports it).

open! Web

let signal = Str("var(--signal)")

// The patch reports its position as a float<2>.
let decodePosition = (json: JSON.t) =>
  switch json {
  | Array([Number(x), Number(y)]) => Some((x, y))
  | Object(fields) =>
    switch (fields->Dict.get("x"), fields->Dict.get("y")) {
    | (Some(Number(x)), Some(Number(y))) => Some((x, y))
    | _ => None
    }
  | _ => None
  }

let make = (ctx: Ctx.t, parent, area) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let side = Math.min(area.w, area.h)
  let box = {x: area.x + (area.w - side) / 2., y: area.y + (area.h - side) / 2., w: side, h: side}
  let s = Plots.svg(parent, box)
  s->addClass("draw")
  let svgEl = svgEl(s, ...)
  Plots.background(s, box)
  s->Plots.line(side / 2., 1., side / 2., side - 1.)->ignore
  s->Plots.line(1., side / 2., side - 1., side / 2.)->ignore
  let radius = svgEl(
    "circle",
    [
      ("r", Num(0.)),
      ("fill", Str("none")),
      ("stroke", signal),
      ("stroke-width", Num(1.)),
      ("stroke-dasharray", Str("2 2")),
      ("opacity", Num(0.8)),
    ],
  )
  let live = svgEl(
    "circle",
    [
      ("r", Num(3.)),
      ("fill", Str("none")),
      ("stroke", signal),
      ("stroke-width", Num(1.)),
      ("opacity", Num(0.)),
    ],
  )
  let hx = svgEl("line", [("stroke", signal), ("stroke-width", Num(1.4))])
  let hy = svgEl("line", [("stroke", signal), ("stroke-width", Num(1.4))])
  let dot = svgEl("circle", [("r", Num(3.2)), ("fill", signal)])

  let hover = ref(false)
  let dragging = ref(false)
  let livePosition = ref(None)

  let toPx = (x, y) => (side / 2. + x * (side / 2. - 3.), side / 2. - y * (side / 2. - 3.))

  let status = () => {
    let (x, y) = (get("XY_X"), get("XY_Y"))
    let r = Math.hypot(x, y)
    let a = Math.atan2(~y, ~x) * 180. / Math.Constants.pi
    let fixed = (v, digits) => Float.toFixed(v, ~digits)
    ctx.status->Status.show(
      `XY pad (${fixed(x, 3)}, ${fixed(y, 3)} / ${fixed(r, 3)}, ${fixed(a, 2)} degrees)`,
    )
  }

  let draw = () => {
    let (px, py) = toPx(get("XY_X"), get("XY_Y"))
    let set = (e, attrs) => attrs->Array.forEach(((name, v)) => e->setAttribute(name, Num(v)))
    dot->set([("cx", px), ("cy", py)])
    hx->set([("x1", px - 6.), ("x2", px + 6.), ("y1", py), ("y2", py)])
    hy->set([("y1", py - 6.), ("y2", py + 6.), ("x1", px), ("x2", px)])
    let r = get("XY_Var_Radius") * (side / 2. - 3.)
    radius->set([("cx", px), ("cy", py), ("r", r)])

    switch livePosition.contents {
    | Some((x, y)) if r > 0. =>
      let (lx, ly) = toPx(x, y)
      live->set([("cx", lx), ("cy", ly), ("opacity", 1.)])
    | _ => live->set([("opacity", 0.)])
    }

    if hover.contents || dragging.contents {
      status()
    }
  }

  let onDown = ev => {
    ev->preventDefault
    if ev->button == 1 {
      model->ParamModel.gestureSet("XY_X", 0.)
      model->ParamModel.gestureSet("XY_Y", 0.)
    } else {
      dragging := true
      model->ParamModel.beginGesture("XY_X")
      model->ParamModel.beginGesture("XY_Y")
      let circular = ev->button == 2
      let r0 = Math.hypot(get("XY_X"), get("XY_Y"))
      let position = ref((get("XY_X"), get("XY_Y")))
      let fine = ev => ev->shiftKey || ev->ctrlKey
      // the position under the pointer
      let under = ev => {
        let (fx, fy) = s->pointerFraction(ev)
        let k = 2. * (side / 2.) / (side / 2. - 3.)
        ((fx - 0.5) * k, (0.5 - fy) * k)
      }

      let apply = ((nx, ny)) => {
        let (nx, ny) = if circular && r0 > 0. {
          let a = Math.atan2(~y=ny, ~x=nx)
          (Math.cos(a) * r0, Math.sin(a) * r0)
        } else {
          (nx, ny)
        }
        let clamp = v => Float.clamp(v, ~min=-1., ~max=1.)
        let (x, y) = (clamp(nx), clamp(ny))
        position := (x, y)
        model->ParamModel.set("XY_X", x)
        model->ParamModel.set("XY_Y", y)
      }

      if !fine(ev) {
        apply(under(ev))
      }
      Controls.dragBy(
        ctx,
        s,
        ev,
        ~onMove=(dx, dy, mv) =>
          if fine(mv) {
            let (x, y) = position.contents
            apply((x + dx / (side / 2.) * 0.15, y - dy / (side / 2.) * 0.15))
          } else {
            apply(under(mv))
          },
        ~onUp=() => {
          dragging := false
          model->ParamModel.endGesture("XY_X")
          model->ParamModel.endGesture("XY_Y")
          if !hover.contents {
            ctx.status->Status.clear
          }
        },
      )
    }
  }

  s->onPointer(#pointerdown, onDown)
  s->suppressContextMenu
  s->onMouse(#mouseenter, _ => {
    hover := true
    status()
  })
  s->onMouse(#mouseleave, _ => {
    hover := false
    if !dragging.contents {
      ctx.status->Status.clear
    }
  })

  ["XY_X", "XY_Y", "XY_Var_Radius"]->Array.forEach(id => model->ParamModel.listen(id, draw))
  // (reported at the patch's rate: drawn once a frame, and only when it moves)
  let drawSoon = perFrame(draw)
  ctx.pc->PatchConnection.addEndpointListener("xyOut", json => {
    let position = decodePosition(json)
    if position != livePosition.contents {
      livePosition := position
      drawSoon()
    }
  })
  draw()
}
