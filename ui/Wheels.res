// The pitch bend and mod wheels: drag them like a keyboard's wheels. Each is a host parameter
// (PorridgeParams.wheelSpecs), which plays as channel 1's pitch bend or controller 1 would, so
// they drive the bend range, the mod wheel's CC targets and the modulation matrix's sources; and
// hosts record a drag (a gesture) as automation, play it back (the wheels follow), and have their
// menu for it on a shift+right-click (in FL Studio: create an automation clip, link a
// controller). They are playing, not the program: moving them is no undo step and no edit.
// The pitch wheel springs back to the centre when it's let go; the mod wheel stays put.
// Middle click (or ctrl-click) resets a wheel; scrolling moves the mod wheel.

open! Web

let signal = Str("var(--signal)")

// A MIDI message to the patch, as a controller would send it (the random drawer plays its notes so).
let send = (ctx: Ctx.t, status, data1, data2) =>
  ctx.pc->PatchConnection.sendEventOrValue("midiIn", {"message": status * 65536 + data1 * 256 + data2})

type kind = Pitch | Mod

let wheel = (ctx: Ctx.t, parent, box, kind) => {
  let model = ctx.model
  let id = kind == Pitch ? PorridgeParams.pitchWheelId : PorridgeParams.modWheelId
  let value = () => model->ParamModel.get(id)
  let bipolar = kind == Pitch
  let labelHeight = 16.
  let track = {...box, h: box.h - labelHeight}
  let s = Plots.svg(parent, box)
  s->addClass("draw")
  // the host's menu for the wheel's parameter on a shift+right-click (before the drags below)
  Controls.hostMenuFor(ctx, s, () => [id])
  let svgEl = svgEl(s, ...)
  Plots.background(s, track)
  if bipolar {
    s->Plots.line(1., track.h / 2., track.w - 1., track.h / 2.)->ignore
  }
  let fill = svgEl("rect", [("x", Num(3.)), ("width", Num(track.w - 6.)), ("fill", Str("var(--signal-soft)"))])
  let thumb = svgEl("line", [("x1", Num(3.)), ("x2", Num(track.w - 3.)), ("stroke", signal), ("stroke-width", Num(2.))])
  let label = svgEl(
    "text",
    [
      ("x", Num(box.w / 2.)),
      ("y", Num(box.h - 4.)),
      ("text-anchor", Str("middle")),
      ("font-size", Num(11.)),
      ("fill", Str("var(--ink-soft)")),
    ],
  )
  label->setTextContent(kind == Pitch ? "pitch" : "mod")

  // the track's travel: value -1..1 (pitch) or 0..1 (mod), bottom to top
  let inset = 4.
  let toY = v => {
    let f = bipolar ? (v + 1.) / 2. : v
    inset + (1. - f) * (track.h - 2. * inset)
  }
  let under = ev => {
    let (_, fy) = s->pointerFraction(ev)
    let f = Float.clamp(1. - (fy * box.h - inset) / (track.h - 2. * inset), ~min=0., ~max=1.)
    bipolar ? 2. * f - 1. : f
  }

  // (the pitch wheel's text gives the bend in semitones by the bend range: ParamDefs)
  let status = ctx.status->Status.live(s, () =>
    `${kind == Pitch ? "Pitch wheel" : "Mod wheel"} ${(model->ParamModel.def(id)).valueText(value())}`
  )

  let draw = () => {
    let y = toY(value())
    let from = toY(0.)
    fill->setAttribute("y", Num(Math.min(y, from)))
    fill->setAttribute("height", Num(Math.abs(from - y)))
    thumb->setAttribute("y1", Num(y))
    thumb->setAttribute("y2", Num(y))
    status.refresh()
  }

  // (ParamModel clamps it, sends it, and every drawing of the wheel follows: listen, below)
  let set = v => model->ParamModel.set(id, v)

  s->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 1 || ev->button == 0 && ev->commandKey {
      model->ParamModel.gestureSet(id, 0.)
    } else if ev->button == 0 {
      status.setDragging(true)
      model->ParamModel.beginGesture(id)
      set(under(ev))
      Controls.dragBy(
        ctx,
        s,
        ev,
        ~onMove=(_, _, mv) => set(under(mv)),
        ~onUp=() => {
          if kind == Pitch {
            set(0.)
          }
          model->ParamModel.endGesture(id)
          status.setDragging(false)
        },
      )
    }
  })
  if kind == Mod {
    s->onWheel(ev => {
      ev->preventDefault
      model->ParamModel.gestureSet(id, value() + (ev->deltaY < 0. ? 1. : -1.) / 127.)
    })
  }
  s->suppressContextMenu
  // (the host's automation, and the other page's drawing, move it too)
  model->ParamModel.listen(id, draw)
  draw()
}

// Both wheels side by side in the box, this far apart.
let make = (ctx, parent, box, ~gap=12.) => {
  let w = (box.w - gap) / 2.
  wheel(ctx, parent, {...box, w}, Pitch)
  wheel(ctx, parent, {...box, x: box.x + w + gap, w}, Mod)
}
