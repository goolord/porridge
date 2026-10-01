// The pitch bend and mod wheels: drag them like a keyboard's wheels. They send MIDI to the
// patch on channel 1 (pitch bend, and controller 1), just as a controller would, so they
// drive the bend range, the mod wheel's CC targets and the modulation matrix's sources.
// The pitch wheel springs back to the centre when it's let go; the mod wheel stays put.
// Middle click (or ctrl-click) resets a wheel; scrolling moves the mod wheel.

open! Web

let signal = Str("var(--signal)")

// Where the wheels were left, so they keep their place when the page is rebuilt.
let bend = ref(0.)
let modWheel = ref(0.)

let send = (ctx: Ctx.t, status, data1, data2) =>
  ctx.pc->PatchConnection.sendEventOrValue("midiIn", {"message": status * 65536 + data1 * 256 + data2})

// pitch bend -1..1 as its 14-bit value (centre 8192) on channel 1
let sendBend = (ctx, v) => {
  let b = Math.Int.max(0, Math.Int.min(16383, Float.toInt(Math.round(v * 8192.)) + 8192))
  send(ctx, 0xe0, mod(b, 128), b / 128)
}

let sendMod = (ctx, v) => send(ctx, 0xb0, 1, Float.toInt(Math.round(v * 127.)))

type kind = Pitch | Mod

let wheel = (ctx: Ctx.t, parent, box, kind) => {
  let value = kind == Pitch ? bend : modWheel
  let bipolar = kind == Pitch
  let labelHeight = 16.
  let track = {...box, h: box.h - labelHeight}
  let s = Plots.svg(parent, box)
  s->addClass("draw")
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

  let hover = ref(false)
  let dragging = ref(false)

  let status = () => {
    let v = value.contents
    let text = switch kind {
    | Pitch =>
      let range = ctx.model->ParamModel.get("BendRange")
      let st = v * range
      `Pitch wheel ${v > 0. ? "+" : ""}${Float.toFixed(v, ~digits=3)} (${st > 0. ? "+" : ""}${Float.toFixed(st, ~digits=2)} st)`
    | Mod => `Mod wheel ${Float.toFixed(v * 127., ~digits=0)} of 127`
    }
    ctx.status->Status.show(text)
  }

  let draw = () => {
    let y = toY(value.contents)
    let from = toY(0.)
    fill->setAttribute("y", Num(Math.min(y, from)))
    fill->setAttribute("height", Num(Math.abs(from - y)))
    thumb->setAttribute("y1", Num(y))
    thumb->setAttribute("y2", Num(y))
    if hover.contents || dragging.contents {
      status()
    }
  }

  let set = v => {
    let v = bipolar ? Float.clamp(v, ~min=-1., ~max=1.) : Float.clamp(v, ~min=0., ~max=1.)
    if v != value.contents {
      value := v
      kind == Pitch ? sendBend(ctx, v) : sendMod(ctx, v)
      draw()
    }
  }

  s->onPointer(#pointerdown, ev => {
    ev->preventDefault
    if ev->button == 1 || ev->button == 0 && ev->commandKey {
      set(0.)
    } else if ev->button == 0 {
      dragging := true
      set(under(ev))
      Controls.dragBy(
        ctx,
        s,
        ev,
        ~onMove=(_, _, mv) => set(under(mv)),
        ~onUp=() => {
          dragging := false
          if kind == Pitch {
            set(0.)
          }
          if hover.contents {
            status()
          } else {
            ctx.status->Status.clear
          }
        },
      )
    }
  })
  if kind == Mod {
    s->onWheel(ev => {
      ev->preventDefault
      set(value.contents + (ev->deltaY < 0. ? 1. : -1.) / 127.)
    })
  }
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
  draw()
}

// Both wheels side by side in the box.
let make = (ctx, parent, box) => {
  let gap = 12.
  let w = (box.w - gap) / 2.
  wheel(ctx, parent, {...box, w}, Pitch)
  wheel(ctx, parent, {...box, x: box.x + w + gap, w}, Mod)
}
