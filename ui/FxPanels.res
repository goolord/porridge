// The tabs of Porridge's own rack effects (flanger, phaser, algo reverb, convolve, bode,
// filter, utility, ambience, air; the compressor has CompEditor) and the voice lane's shifter,
// resonator and octaver: their controls in panels across the top, and below them a graph of
// what the effect does with these settings. Also each one's level and summary, for the strip's
// hover texts and the synth page.
//
// The graphs follow dsp/FxExtra.cmajor, dsp/Space.cmajor, dsp/Convolve.cmajor and
// dsp/Filter.cmajor closely enough to show what the knobs do; they are not measurements. The
// ambience's are its models run on an impulse (AmbienceSim), the air's its model run on sines
// (AirwindowsSim).

open! Web

let pi = Math.Constants.pi
let (clamp, db) = (FxDsp.clamp, FxDsp.db)
let expValue = PorridgeParams.expValue

type item =
  | Knob(string, string)
  | List(string, string)
  | Switch(string, string)
  // a button, given the effect
  | Button(string, string, FxRack.effect => unit)

type section = {title: string, rows: array<array<item>>}

open! Complex

//==============================================================================
// flanger: the comb at both ends of its sweep

let flangerResponse = (get: string => float, ~delayMs, hz) => {
  let mix = get("Fl_Mix")
  let fb = 0.97 * get("Fl_Feedback")
  let z = expj(-2. * pi * hz * delayMs / 1000.)
  add(scale(one, 1. - mix), scale(div(z, add(one, scale(z, -.fb))), mix))->abs
}

let flangerSweep = (get: string => float) => {
  let d = expValue(0.1, 20., get("Fl_Delay"))
  (d, d * Math.pow(2., ~exp=4. * get("Fl_Depth")))
}

let drawFlanger = (p: FxGraph.plot, get: string => float) => {
  FxGraph.frequencyGrid(p, ~lo=-30., ~hi=12., ~step=6.)
  let (dMin, dMax) = flangerSweep(get)
  FxGraph.response(p, ~cls="curve dim", ~lo=-30., ~hi=12., flangerResponse(get, ~delayMs=dMax, _))
  FxGraph.response(p, ~lo=-30., ~hi=12., flangerResponse(get, ~delayMs=dMin, _))
  let track = get("Fl_Track")
  FxGraph.note(
    p,
    `the comb at both ends of the sweep: ${Float.toFixed(dMin, ~digits=2)} ms (bright) to ${Float.toFixed(dMax, ~digits=2)} ms (dim), ${Float.toFixed(expValue(0.02, 20., get("Fl_Rate")), ~digits=2)} Hz` ++ (
      track > 0. ? `; at middle C, the delay following the note (at 3.82 ms it rings on the note)` : ""
    ),
  )
}

//==============================================================================
// phaser: the notches at the centre and both ends of the sweep

let phaserStages = [2, 4, 6, 8, 12, 16]

let phaserResponse = (get: string => float, ~centre, hz) => {
  let n = phaserStages[Float.toInt(get("Ph_Stages"))]->Option.getOr(6)
  let spread = get("Ph_Spread")
  let mix = get("Ph_Mix")
  let fb = 0.95 * get("Ph_Feedback")
  let phase = ref(0.)
  for k in 0 to n - 1 {
    let place = n > 1 ? Int.toFloat(k) / Int.toFloat(n - 1) - 0.5 : 0.
    let fk = centre * Math.pow(2., ~exp=spread * place * 2.)
    phase := phase.contents - 2. * Math.atan(hz / fk)
  }
  let a = expj(phase.contents)
  add(scale(one, 1. - mix), scale(div(a, add(one, scale(a, -.fb))), mix))->abs
}

let drawPhaser = (p: FxGraph.plot, get: string => float) => {
  FxGraph.frequencyGrid(p, ~lo=-30., ~hi=12., ~step=6.)
  let centre = expValue(20., 20000., get("Ph_Freq"))
  let swing = Math.pow(2., ~exp=3. * get("Ph_Depth"))
  FxGraph.response(p, ~cls="curve dim", ~lo=-30., ~hi=12., phaserResponse(get, ~centre=centre / swing, _))
  FxGraph.response(p, ~cls="curve dim", ~lo=-30., ~hi=12., phaserResponse(get, ~centre=centre * swing, _))
  FxGraph.response(p, ~lo=-30., ~hi=12., phaserResponse(get, ~centre, _))
  let track = get("Ph_Track")
  FxGraph.note(
    p,
    `the notches at the centre and at both ends of the sweep (dim)${track > 0. ? `; the centre follows the note by ${Float.toFixed(track * 100., ~digits=0)} %` : ""}`,
  )
}

//==============================================================================
// algo reverb: the tail's shape over time

// how long the tail takes to build up, by model (seconds at size 0.5)
let reverbBuild = model =>
  switch model {
  | 1 => 0.004
  | 2 => 0.012
  | 3 => 0.3
  | 4 => 0.03
  | _ => 0.04
  }

let reverbModelText = model =>
  switch model {
  | 1 => "plate: dense and bright from the first moment"
  | 2 => "nitrous: bright, dense and airy, a little metallic when small"
  | 3 => "basin: dark and huge, blooming in slowly"
  | 4 => "vintage: an 1980s digital reverb, grainy and band-limited"
  | _ => "hall: a large, smooth room"
  }

let drawSpace = (p: FxGraph.plot, get: string => float) => {
  let (lo, hi) = (-60., 0.)
  let decay = expValue(0.1, 30., get("Rv_Decay"))
  let predelay = get("Rv_Predelay") / 1000.
  let model = Float.toInt(get("Rv_Model"))
  let build = reverbBuild(model) * (0.5 + get("Rv_Size"))
  let until = predelay + build + Math.min(decay, 30.) * 1.1
  let xOf = t => p.left + t / until * (p.right - p.left)
  let step = until > 20. ? 5. : until > 5. ? 1. : until > 1. ? 0.25 : 0.05
  FxGraph.ticks(~until, ~step, t => {
    let x = xOf(t)
    FxGraph.line(p.layer, ~cls="grid", x, p.top, x, p.bottom)
    FxGraph.text(p.layer, ~anchor="middle", x, p.bottom + 12., `${Float.toString(Math.round(t * 100.) / 100.)} s`)
  })
  p->FxGraph.levelLines(~lo, ~hi, [-12., -24., -36., -48., -60.])
  let n = 200
  let level = t =>
    if t < predelay {
      lo - 10.
    } else {
      let u = t - predelay
      let attack = u < build ? db(Math.max(1e-3, u / build)) * 0.5 : 0.
      attack - 60. * Math.max(0., u - build) / decay
    }
  let points = Array.fromInitializer(~length=n + 1, k => {
    let t = until * Int.toFloat(k) / Int.toFloat(n)
    (xOf(t), FxGraph.yOf(p, level(t), lo - 4., hi))
  })
  FxGraph.path(p.layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(points))
  // (top right, clear of the tail, which starts at the top left)
  FxGraph.note(p, ~x=p.right - 6., ~anchor="end", `${reverbModelText(model)}; decays 60 dB in ${PorridgeParams.secondsText(decay)}`)
}

//==============================================================================
// algo reverb: a picture of the space, by model. A sound starts at the source every few
// seconds; its wavefronts spread through the space and fade as the decay says, softer and
// rounder with more damping, wobbling with the modulation; the listeners sit as far apart as
// the width. Size scales the space.

// The scene's elements are kept from frame to frame: each frame asks for them in drawing order,
// and gets the element that had that place in the last frame when it has the same tag (so the
// same attributes, all set again). One that isn't there is made (sooner ones of the tag than
// the last frame's go), and the last frame's left over are removed when the frame ends.
module ScenePool = {
  type rec t = {parent: element, mutable items: array<item>, mutable next: int}
  // (its attributes as last set)
  and item = {tag: string, el: element, mutable inner: option<t>, set: Dict.t<attr>}

  @send external insertBefore: (element, element, Nullable.t<element>) => unit = "insertBefore"

  let make = parent => {parent, items: [], next: 0}

  let takeItem = (p, tag, attrs) => {
    let i = p.next
    let n = Array.length(p.items)
    let rec find = j => j >= n ? None : (p.items->Array.getUnsafe(j)).tag == tag ? Some(j) : find(j + 1)
    let it = switch find(i) {
    | Some(j) =>
      // the ones before it aren't drawn any more
      p.items->Array.slice(~start=i, ~end=j)->Array.forEach(it => it.el->remove)
      p.items->Array.splice(~start=i, ~remove=j - i, ~insert=[])
      p.items->Array.getUnsafe(i)
    | None =>
      let el = document->createElementNS(svgNamespace, tag)
      p.parent->insertBefore(el, p.items[i]->Option.map(it => it.el)->Nullable.fromOption)
      let it = {tag, el, inner: None, set: Dict.make()}
      p.items->Array.splice(~start=i, ~remove=0, ~insert=[it])
      it
    }
    attrs->Array.forEach(((name, value)) =>
      // (undefined while unset)
      if it.set->Dict.getUnsafe(name) !== value {
        it.el->setAttribute(name, value)
        it.set->Dict.set(name, value)
      }
    )
    p.next = i + 1
    it
  }

  // The next element, with these attributes.
  let take = (p, tag, attrs) => takeItem(p, tag, attrs).el

  // The next element, as the pool of the elements inside it.
  let group = (p, tag, attrs) => {
    let it = takeItem(p, tag, attrs)
    switch it.inner {
    | Some(inner) => inner
    | None =>
      let inner = make(it.el)
      it.inner = Some(inner)
      inner
    }
  }

  // The frame is drawn: what it didn't ask for goes, and the next starts from the first again.
  let rec finish = p => {
    p.items->Array.slice(~start=p.next)->Array.forEach(it => it.el->remove)
    p.items->Array.splice(~start=p.next, ~remove=Array.length(p.items) - p.next, ~insert=[])
    p.items->Array.forEach(it => it.inner->Option.forEach(finish))
    p.next = 0
  }
}

@get external textContent: element => string = "textContent"

type scene = {sw: float, sh: float, layer: ScenePool.t}

let sceneCircle = (s, ~cls, x: float, y: float, r: float, ~opacity: float) =>
  s.layer
  ->ScenePool.take(
    "circle",
    [("class", Str(cls)), ("cx", Num(x)), ("cy", Num(y)), ("r", Num(Math.max(0.1, r))), ("opacity", Num(clamp(opacity, 0., 1.)))],
  )
  ->ignore

let scenePath = (s, ~cls, ~opacity=1., d) =>
  s.layer->ScenePool.take("path", [("class", Str(cls)), ("d", Str(d)), ("opacity", Num(clamp(opacity, 0., 1.)))])->ignore

// (as FxGraph.text draws it)
let sceneText = (s, ~cls, x, y, text) => {
  let e = s.layer->ScenePool.take("text", [("class", Str(cls)), ("x", Num(x)), ("y", Num(y)), ("text-anchor", Str("start"))])
  if e->textContent != text {
    e->setTextContent(text)
  }
}

// A group clipped to the outline (a path), for drawing inside it.
let clipped = (s, ~id, outline) => {
  s.layer->ScenePool.group("clipPath", [("id", Str(id))])->ScenePool.take("path", [("d", Str(outline))])->ignore
  {...s, layer: s.layer->ScenePool.group("g", [("clip-path", Str(`url(#${id})`))])}
}

// A wobbly ring: radius r around (x, y), squashed vertically by `squash`, wobbling with the
// modulation.
let ring = (s, ~cls, x: float, y: float, r: float, ~squash=1., ~wobble: float, ~time: float, ~opacity) => {
  let n = 48
  let points = Array.fromInitializer(~length=n + 1, k => {
    let a = 2. * pi * Int.toFloat(k) / Int.toFloat(n)
    let w = 1. + wobble * 0.06 * Math.sin(5. * a + time * 3.) + wobble * 0.03 * Math.sin(9. * a - time * 5.)
    (x + Math.cos(a) * r * w, y + Math.sin(a) * r * w * squash)
  })
  scenePath(s, ~cls, ~opacity, Plots.pathFrom(points) ++ "Z")
}

let drawScene = (s, get: string => float, time: float) => {
  let f = Float.toFixed(_, ~digits=1)
  let model = Float.toInt(get("Rv_Model"))
  let size = get("Rv_Size")
  let decay = expValue(0.1, 30., get("Rv_Decay"))
  let damp = expValue(20., 20000., get("Rv_Damp"))
  let width = get("Rv_Width")
  let wobble = get("Rv_Mod")
  let predelay = get("Rv_Predelay") / 1000.
  let mix = 0.35 + 0.65 * get("Rv_Mix")
  // how dull the loop is: 0 bright .. 1 very damped
  let dull = 1. - clamp(Math.log(damp / 200.) / Math.log(100.), 0., 1.)
  let period = Math.max(2.5, Math.min(decay * 0.8, 8.)) + predelay
  let age = Float.mod(time, period) - predelay
  let fade = (t: float) => t < 0. ? 0. : Math.pow(10., ~exp=-3. * t / decay)
  let (sw, sh) = (s.sw, s.sh)
  let (cx0, cy0) = (sw / 2., sh / 2.)
  let ringCls = dull > 0.6 ? "front dull" : dull > 0.3 ? "front" : "front bright"
  // reflections: a new wavefront leaves the source every `spacing` seconds while the tail
  // lasts, each crossing the space in `travel` seconds, as faint as the tail is by then
  let fronts = (inner, x: float, y: float, ~reach: float, ~travel: float, ~spacing: float, ~squash=1.) =>
    for j in 0 to Float.toInt(travel / spacing) + 60 {
      let born = Int.toFloat(j) * spacing
      let t = age - born
      if t > 0. && t < travel {
        let opacity = fade(born) * (1. - t / travel) * mix
        if opacity > 0.02 {
          ring(inner, ~cls=ringCls, x, y, t / travel * reach, ~squash, ~wobble, ~time, ~opacity)
        }
      }
    }
  let listeners = (lx: float, ly: float, spread: float) =>
    [-1., 1.]->Array.forEach(side => sceneCircle(s, ~cls="listener", lx + side * spread * width, ly, 4., ~opacity=1.))
  switch model {
  | 1 =>
    // plate: a sheet of metal hung by its corners, a driver and two pickups, ripples crossing it
    let (pw, ph) = (sw * (0.45 + 0.4 * size), sh * (0.4 + 0.35 * size))
    let (x0, y0) = (cx0 - pw / 2., cy0 - ph / 2.)
    let skew = pw * 0.12
    let corner = (x, y) => `${f(x)} ${f(y)}`
    let outline = `M${corner(x0 + skew, y0)} L${corner(x0 + pw + skew, y0)} L${corner(x0 + pw - skew, y0 + ph)} L${corner(x0 - skew, y0 + ph)} Z`
    [(x0 + skew, y0), (x0 + pw + skew, y0), (x0 + pw - skew, y0 + ph), (x0 - skew, y0 + ph)]->Array.forEach(((x, y)) =>
      scenePath(s, ~cls="spring", `M${corner(x, y)} L${corner(x + (x < cx0 ? -14. : 14.), y + (y < cy0 ? -14. : 14.))}`)
    )
    scenePath(s, ~cls="plate", outline)
    let inner = clipped(s, ~id="plateclip", outline)
    let (dx, dy) = (x0 + pw * 0.3, y0 + ph * 0.45)
    fronts(inner, dx, dy, ~reach=pw * 1.1, ~travel=0.45, ~spacing=0.045, ~squash=0.75)
    sceneCircle(s, ~cls="source", dx, dy, 5., ~opacity=1.)
    listeners(x0 + pw * 0.7, y0 + ph * 0.55, pw * 0.15)
  | 2 =>
    // nitrous: a dense, sparkling cloud that fills in at once
    let r = Math.min(sw, sh) * (0.25 + 0.25 * size)
    let n = 160
    for k in 0 to n - 1 {
      let kf = Int.toFloat(k)
      let a = 2. * pi * FxDsp.hash(kf, 1.)
      let d = Math.sqrt(FxDsp.hash(kf, 2.)) * r * (1. + 0.4 * width)
      let born = FxDsp.hash(kf, 3.) * 0.12
      let t = age - born
      let twinkle = 0.55 + 0.45 * Math.sin(time * (6. + 8. * FxDsp.hash(kf, 4.)) + kf)
      let x = cx0 + Math.cos(a) * d * (1. + 0.5 * width) + wobble * 3. * Math.sin(time * 4. + kf)
      let y = cy0 + Math.sin(a) * d * 0.7
      if t > 0. {
        sceneCircle(s, ~cls=dull > 0.5 ? "spark dull" : "spark", x, y, 1.2 + 1.6 * FxDsp.hash(kf, 5.), ~opacity=fade(t) * twinkle * mix)
      }
    }
    sceneCircle(s, ~cls="source", cx0, cy0, 5., ~opacity=1.)
  | 3 =>
    // basin: a deep, wide bowl of water; slow, broad swells rise and spread
    let bw = sw * (0.55 + 0.4 * size)
    let depth = sh * (0.35 + 0.3 * size)
    let (left, right, surface) = (cx0 - bw / 2., cx0 + bw / 2., sh * 0.3)
    scenePath(s, ~cls="basin", `M${f(left)} ${f(surface)} Q${f(cx0)} ${f(surface + depth * 2.)} ${f(right)} ${f(surface)}`)
    // the bloom: the swell grows in before it fades
    let bloom = (t: float) => t < 0. ? 0. : Math.min(1., t / 0.25) * fade(t)
    for k in 0 to 5 {
      let t = age - Int.toFloat(k) * 0.12
      if t > 0. {
        let r = Math.min(bw / 2., t * bw * 0.6)
        let amp = 10. * bloom(t)
        let points = Array.fromInitializer(~length=81, j => {
          let x = left + bw * Int.toFloat(j) / 80.
          let d = Math.abs(x - cx0)
          let lift = d < r ? amp * Math.cos((d - r) / 18. + time * (1. + wobble)) * (1. - d / (bw / 2.)) : 0.
          (x, surface - lift - Int.toFloat(k) * 3.)
        })
        scenePath(s, ~cls=dull > 0.3 ? "front dull" : "front", ~opacity=bloom(t) * mix, Plots.pathFrom(points))
      }
    }
    sceneCircle(s, ~cls="source", cx0, surface - 30. + Math.min(30., Math.max(0., age) * 200.), 5., ~opacity=age < 0.15 ? 1. : 0.3)
    listeners(cx0, surface + depth * 0.6, bw * 0.3)
  | 4 =>
    // vintage: a rack unit's display, its delay network drawn in coarse steps
    let (uw, uh) = (sw * 0.8, sh * 0.62)
    let (x0, y0) = (cx0 - uw / 2., cy0 - uh / 2.)
    scenePath(s, ~cls="unit", `M${f(x0)} ${f(y0)} h${f(uw)} v${f(uh)} h${f(-.uw)} Z`)
    let (dx, dy, dw, dh) = (x0 + 16., y0 + 16., uw - 32., uh - 32.)
    scenePath(s, ~cls="display", `M${f(dx)} ${f(dy)} h${f(dw)} v${f(dh)} h${f(-.dw)} Z`)
    // the tail as a stepped, grainy bar graph
    let bars = 40
    for k in 0 to bars - 1 {
      let t = Int.toFloat(k) / Int.toFloat(bars) * period
      let level = t < predelay ? 0. : fade(t - predelay)
      let grain = 0.8 + 0.2 * FxDsp.hash(Int.toFloat(k) + Math.floor(time * 8. * (0.3 + wobble)), 6.)
      let hgt = Math.round(level * grain * (dh - 8.) / 6.) * 6.
      let lit = t <= Math.max(0., age + predelay)
      let x = dx + 4. + Int.toFloat(k) * (dw - 8.) / Int.toFloat(bars)
      scenePath(
        s,
        ~cls=lit ? "pixel lit" : "pixel",
        `M${f(x)} ${f(dy + dh - 4. - hgt)} h${f((dw - 8.) / Int.toFloat(bars) - 2.)} v${f(hgt)} h${f(-.((dw - 8.) / Int.toFloat(bars) - 2.))} Z`,
      )
    }
    sceneText(s, ~cls="lcd", dx + 8., dy + 18., `${Float.toFixed(decay, ~digits=1)} s  ${Float.toFixed(size * 100., ~digits=0)} %`)
  | _ =>
    // hall: a floor plan: the stage, the listeners, the first reflections and the wavefront
    let (rw, rh) = (sw * (0.5 + 0.45 * size), sh * (0.45 + 0.45 * size))
    let (x0, y0) = (cx0 - rw / 2., cy0 - rh / 2.)
    let outline = `M${f(x0)} ${f(y0)} h${f(rw)} v${f(rh)} h${f(-.rw)} Z`
    scenePath(s, ~cls="room", outline)
    let inner = clipped(s, ~id="hallclip", outline)
    let (sx, sy) = (x0 + rw * 0.15, cy0)
    let (lx, ly) = (x0 + rw * 0.72, cy0)
    // first reflections: off the walls, by the image sources
    [(sx, 2. * y0 - sy), (sx, 2. * (y0 + rh) - sy), (2. * x0 - sx, sy), (2. * (x0 + rw) - sx, sy)]->Array.forEachWithIndex(((ix, iy), k) => {
      // where the line from the image to the listener crosses the wall
      let t = k < 2 ? (iy < y0 ? (y0 - iy) / (ly - iy) : (y0 + rh - iy) / (ly - iy)) : (ix < x0 ? (x0 - ix) / (lx - ix) : (x0 + rw - ix) / (lx - ix))
      let (wx, wy) = (ix + (lx - ix) * t, iy + (ly - iy) * t)
      let opacity = (age > 0. && age < 1.2 ? 1. : 0.25) * (1. - 0.6 * dull)
      scenePath(inner, ~cls="hallray", ~opacity, `M${f(sx)} ${f(sy)} L${f(wx)} ${f(wy)} L${f(lx)} ${f(ly)}`)
    })
    fronts(inner, sx, sy, ~reach=rw * 1.1, ~travel=0.9 + 0.6 * size, ~spacing=0.12)
    sceneCircle(s, ~cls="source", sx, sy, 5., ~opacity=1.)
    listeners(lx, ly, rh * 0.18)
  }
  ScenePool.finish(s.layer)
}

//==============================================================================
// convolve: the impulse as the convolver holds it, on a time axis: the predelay, the part
// Length keeps (fading out at its end) and the part it cuts (dim), reversed if so, as levels in
// dB from the peak; beside it, the tone the low and high cuts and the gain leave the wet

let builtInText = impulse =>
  switch impulse {
  | 0 => "a small room"
  | 1 => "a concert hall"
  | 2 => "a cathedral, with long echoes"
  | 3 => "a plate: bright and dense"
  | 4 => "a spring: boings and drips"
  | 5 => "a 1×12 guitar cabinet"
  | 6 => "a 4×12 guitar cabinet, darker"
  | 7 => "a metal tank's ringing modes"
  | 8 => "a telephone line"
  | 9 => "a swell, rising like a reversed reverb"
  | _ => "a slowly blooming noise cloud"
  }

// The part of the kept impulse its end fades over, with a half cosine (dsp/Convolve.cmajor):
// 5 % of it at full length, more as Length shortens it.
let convolveFade = (length: float) => 0.05 + 0.3 * (1. - length)

let drawConvolve = (p: FxGraph.plot, get: string => float, ~which, ~file: option<Impulse.t>) => {
  let kind = Float.toInt(get("Cv_Impulse"))
  let isFile = kind == PorridgeParams.impulseFile
  let length = get("Cv_Length")
  let reverse = get("Cv_Reverse") > 0.
  let predelay = get("Cv_Predelay") / 1000.
  let (floorDb, peakDb) = (-60., 0.)
  // the impulse: the patch's report, or the file's own envelope until it comes
  let view = switch Impulse.views[which]->Option.flatMap(v => v) {
  | Some(v) if v.seconds > 0. => Some(v)
  | _ => file->Option.filter(_ => isFile)->Option.map(imp => ({seconds: Impulse.seconds(imp), peaks: Impulse.envelope(imp, 512)}: Impulse.view))
  }
  let text = isFile
    ? file->Option.mapOr("no file loaded: load one, or drop it on the graph", imp => `file: ${imp.name}`)
    : builtInText(kind)

  // the impulse on the left, the tone on the right
  let split = p.left + (p.right - p.left) * 0.72
  let tone = {...p, left: split + 46., right: p.right}
  let ip = {...p, right: split}
  switch view {
  | None => FxGraph.note(ip, ~y=(p.top + p.bottom) / 2., text ++ (isFile ? "" : " (being built)"))
  | Some({seconds, peaks}) =>
    let n = Array.length(peaks)
    let peak = peaks->Array.reduce(1e-9, Math.max)
    let kept = Math.Int.max(1, Float.toInt(Math.round(Int.toFloat(n) * length)))
    let fadeFrom = Int.toFloat(kept) * (1. - convolveFade(length))
    let piece = seconds / Int.toFloat(n)
    let total = Math.max(predelay + seconds, 0.001)
    let xOf = t => ip.left + t / total * (ip.right - ip.left)
    // time ticks
    FxGraph.ticks(~until=total +. 1e-9, ~step=FxGraph.niceStep(total, 6.), t => {
      let x = xOf(t)
      FxGraph.line(ip.layer, ~cls="grid", x, ip.top, x, ip.bottom)
      FxGraph.text(ip.layer, ~anchor="middle", x, ip.bottom + 12., FxGraph.msText(t * 1000.))
    })
    ip->FxGraph.levelLines(~lo=floorDb, ~hi=peakDb, [-12., -24., -36., -48.])
    // a piece's level, kept or cut, faded at the kept part's end, in playing order
    let level = k => {
      let v = peaks->Array.getUnsafe(k) / peak
      let fade =
        Int.toFloat(k) >= fadeFrom
          ? 0.5 + 0.5 * Math.cos(pi * (Int.toFloat(k) - fadeFrom + 0.5) / Math.max(1., Int.toFloat(kept) - fadeFrom))
          : 1.
      v * fade
    }
    let shape = (~cls, from, until, at) => {
      let points = Array.fromInitializer(~length=until - from, j => {
        let k = from + j
        (xOf(predelay + at(k) * piece), FxGraph.yOf(ip, db(level(k)), floorDb, peakDb))
      })
      if Array.length(points) > 0 {
        let (x0, _) = points->Array.getUnsafe(0)
        let (x1, _) = points->Array.getUnsafe(Array.length(points) - 1)
        let base = ip.bottom
        FxGraph.path(ip.layer, ~cls)->FxGraph.setPath(
          Plots.pathFrom([(x0, base), ...points, (x1, base)]) ++ "Z",
        )
      }
    }
    // the kept part as it plays (reversed: from its end), and the cut part dim where it was
    shape(~cls="curve fill", 0, kept, k => reverse ? Int.toFloat(kept - 1 - k) : Int.toFloat(k))
    if kept < n {
      let points = Array.fromInitializer(~length=n - kept, j => {
        let k = kept + j
        (xOf(predelay + Int.toFloat(k) * piece), FxGraph.yOf(ip, db(peaks->Array.getUnsafe(k) / peak), floorDb, peakDb))
      })
      FxGraph.path(ip.layer, ~cls="curve dim")->FxGraph.setPath(Plots.pathFrom(points))
      let x = xOf(predelay + Int.toFloat(kept) * piece)
      FxGraph.line(ip.layer, ~cls="mark", x, ip.top, x, ip.bottom)
      FxGraph.text(ip.layer, x + 4., ip.bottom - 6., "cut")
    }
    if predelay > 0. {
      let x = xOf(predelay)
      FxGraph.line(ip.layer, ~cls="mark", x, ip.top, x, ip.bottom)
      FxGraph.text(ip.layer, ~anchor="end", x - 4., ip.bottom - 6., "predelay")
    }
    FxGraph.note(ip, `${text}${reverse ? ", reversed" : ""}: ${PorridgeParams.secondsText(seconds * length)} of ${PorridgeParams.secondsText(seconds)}`)
  }

  // the tone: the cuts' 12 dB/oct slopes and the gain
  let lowCut = expValue(20., 20000., get("Cv_LowCut"))
  let highCut = expValue(20., 20000., get("Cv_HighCut"))
  let gain = Math.pow(10., ~exp=get("Cv_Gain") / 20.)
  tone->FxGraph.frequencyLines([100., 1000., 10000.])
  tone->FxGraph.levelLines(~lo=-36., ~hi=24., [12., 0., -12., -24.])
  FxGraph.response(tone, ~lo=-36., ~hi=24., hz => {
    let s = Complex.make(0., hz / lowCut)
    let hp = lowCut <= 21. ? 1. : Complex.abs(Complex.div(Complex.mul(s, s), Complex.add(Complex.add(Complex.mul(s, s), Complex.scale(s, Math.sqrt(2.))), Complex.one)))
    let s2 = Complex.make(0., hz / highCut)
    let lp = highCut >= 19000. ? 1. : Complex.abs(Complex.div(Complex.one, Complex.add(Complex.add(Complex.mul(s2, s2), Complex.scale(s2, Math.sqrt(2.))), Complex.one)))
    hp * lp * gain
  })
  FxGraph.text(tone.layer, tone.left + 4., tone.top + 12., `wet tone · width ${Float.toFixed(get("Cv_Width") * 100., ~digits=0)} %`)
}

//==============================================================================
// bode: a note's partials before (dim) and after the shift

let drawBode = (p: FxGraph.plot, get: string => float) => {
  FxGraph.frequencyGrid(p, ~lo=-30., ~hi=0., ~step=10.)
  let shift = PorridgeParams.bodeShift(get("Bd_Shift"))
  let mode = Float.toInt(get("Bd_Mode"))
  let base = 220.
  let partial = (cls, f: float, k) => {
    let x = FxGraph.xOfHz(p, Math.abs(f))
    let y = FxGraph.yOf(p, -20. * Math.log10(Int.toFloat(k)), -30., 0.)
    if Math.abs(f) >= 20. && Math.abs(f) <= 20000. {
      FxGraph.line(p.layer, ~cls, x, p.bottom, x, y)
    }
  }
  for k in 1 to 12 {
    let f = base * Int.toFloat(k)
    partial("mark", f, k)
    switch mode {
    | 0 => partial("curve", f + shift, k)
    | 1 => partial("curve", f - shift, k)
    | _ =>
      partial("curve", f + shift, k)
      partial(mode == 2 ? "curve alt" : "curve", f - shift, k)
    }
  }
  let fb = get("Bd_Feedback")
  FxGraph.note(
    p,
    `a 220 Hz note's partials (dim) shifted by ${PorridgeParams.bodeShiftText(get("Bd_Shift"))}` ++ (
      mode == 2 ? ": up on the left, down on the right" : mode == 3 ? ": both ways, as ring modulation" : ""
    ) ++ (fb > 0. ? `; each echo shifts again (${Float.toFixed(fb * 100., ~digits=0)} % feedback)` : ""),
  )
}

//==============================================================================
// shifter: two notes' partials before (dim) and after the shift, which follows the key

let drawShifter = (p: FxGraph.plot, get: string => float) => {
  FxGraph.frequencyGrid(p, ~lo=-30., ~hi=0., ~step=10.)
  let ratioOf = v => 2. * v * v * v
  let hzOf = v => 1000. * v * v * v
  let ratio = ratioOf(get("Sh_Ratio"))
  let offset = hzOf(get("Sh_Hz"))
  let mode = Float.toInt(get("Sh_Mode"))
  let partial = (cls, f: float, k, ~level) => {
    let x = FxGraph.xOfHz(p, Math.abs(f))
    let y = FxGraph.yOf(p, level - 20. * Math.log10(Int.toFloat(k)), -30., 0.)
    if Math.abs(f) >= 20. && Math.abs(f) <= 20000. {
      FxGraph.line(p.layer, ~cls, x, p.bottom, x, y)
    }
  }
  // a low note and one two octaves up: each moves by the same share of its own pitch
  [(110., 0.), (440., -6.)]->Array.forEach(((base, level)) => {
    let shift = base * ratio + offset
    for k in 1 to 10 {
      let f = base * Int.toFloat(k)
      partial("mark", f, k, ~level)
      switch mode {
      | 0 => partial("curve", f + shift, k, ~level)
      | 1 => partial("curve", f - shift, k, ~level)
      | _ =>
        partial("curve", f + shift, k, ~level)
        partial(mode == 2 ? "curve alt" : "curve", f - shift, k, ~level)
      }
    }
  })
  FxGraph.note(
    p,
    `110 Hz and 440 Hz notes' partials (dim), each shifted by ${PorridgeParams.shifterRatioText(get("Sh_Ratio"))}` ++
    (offset != 0. ? ` ${PorridgeParams.shifterHzText(get("Sh_Hz"))}` : "") ++
    (mode == 2 ? ": up on the left, down on the right" : mode == 3 ? ": both ways, as ring modulation" : ""),
  )
}

//==============================================================================
// resonator: its four resonances for a 220 Hz note, over the note's partials

let resonatorRatios = [
  [1., 2., 3., 4.],
  [1., 3., 5., 7.],
  [1., 1.5, 2., 3.],
  [1., 2.756, 5.404, 8.933],
  [1., 2., 2.4, 3.],
  [1., 1.593, 2.136, 2.296],
]

let drawResonator = (p: FxGraph.plot, get: string => float) => {
  FxGraph.frequencyGrid(p, ~lo=-36., ~hi=6., ~step=12.)
  let base = 220. * Math.pow(2., ~exp=get("Rs_Pitch") / 12.)
  let decay = expValue(10., 10000., get("Rs_Decay")) / 1000.
  let bright = get("Rs_Bright")
  let gain = Math.pow(10., ~exp=get("Rs_Gain") / 20.)
  let ratios = resonatorRatios[Float.toInt(get("Rs_Model"))]->Option.getOr([1., 2., 3., 4.])
  let sr = 48000.
  // each mode as the DSP makes it: a two-pole resonance of this decay, weighted
  let modes = ratios->Array.map(ratio => {
    let hz = base * ratio
    let t = decay / Math.sqrt(ratio)
    let r = Math.exp(-6.907755 / (t * sr))
    (hz, r, Math.pow(ratio, ~exp=2. * bright - 1.5))
  })
  let total = modes->Array.reduce(0., (s, (hz, _, w)) => hz < 0.45 * sr ? s + w : s)
  for k in 1 to 12 {
    let f = 220. * Int.toFloat(k)
    let x = FxGraph.xOfHz(p, f)
    if f <= 20000. {
      FxGraph.line(p.layer, ~cls="mark", x, p.bottom, x, FxGraph.yOf(p, -20. * Math.log10(Int.toFloat(k)), -36., 6.))
    }
  }
  let n = Float.toInt(p.right - p.left)
  let points = Array.fromInitializer(~length=n + 1, i => {
    let x = p.left + Int.toFloat(i)
    let hz = FxGraph.hzAt(p, x)
    let w = 2. * pi * hz / sr
    let wet = modes->Array.reduce(Complex.make(0., 0.), (sum, (mhz, r, weight)) =>
      if mhz >= 0.45 * sr {
        sum
      } else {
        let wm = 2. * pi * mhz / sr
        // (1 - r^2) / 2 (1 - z^-2) / (1 - 2 r cos wm z^-1 + r^2 z^-2)
        let z1 = Complex.expj(-.w)
        let z2 = Complex.expj(-2. * w)
        let num = Complex.scale(Complex.add(Complex.one, Complex.scale(z2, -1.)), (1. - r * r) / 2.)
        let den = Complex.add(Complex.add(Complex.one, Complex.scale(z1, -2. * r * Math.cos(wm))), Complex.scale(z2, r * r))
        Complex.add(sum, Complex.scale(Complex.div(num, den), weight / total * 2. * gain))
      }
    )
    (x, FxGraph.yOf(p, Math.max(-36., db(Complex.abs(wet))), -36., 6.))
  })
  FxGraph.path(p.layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(points))
  FxGraph.note(
    p,
    `its resonances for a 220 Hz note (its partials dim), ringing for ${PorridgeParams.msText(decay * 1000.)}: each note gets its own`,
  )
}

//==============================================================================
// octaver: four cycles of a note (dim) and what comes out: the octave down flips the sound's
// sign on every other cycle, the octave up is the sound rectified (less its average)

let drawOctaver = (p: FxGraph.plot, get: string => float) => {
  let (sub, up, dry) = (get("Oc_Sub"), get("Oc_Up"), get("Oc_Dry"))
  let (lo, hi) = (-2., 2.)
  let cycles = 4.
  let n = Float.toInt(p.right - p.left)
  // a soft saw: its first six partials
  let wave = t => {
    let s = ref(0.)
    for k in 1 to 6 {
      s := s.contents + Math.sin(2. * pi * Int.toFloat(k) * t) / Int.toFloat(k)
    }
    0.6 * s.contents
  }
  let rectifiedMean = {
    let s = ref(0.)
    for i in 0 to 255 {
      s := s.contents + Math.abs(wave(Int.toFloat(i) / 256.))
    }
    s.contents / 256.
  }
  let xOf = i => p.left + Int.toFloat(i)
  let tOf = i => cycles * Int.toFloat(i) / Int.toFloat(n)
  FxGraph.line(p.layer, ~cls="grid", p.left, FxGraph.yOf(p, 0., lo, hi), p.right, FxGraph.yOf(p, 0., lo, hi))
  for c in 1 to Float.toInt(cycles) - 1 {
    let x = p.left + Int.toFloat(c) / cycles * (p.right - p.left)
    FxGraph.line(p.layer, ~cls="grid", x, p.top, x, p.bottom)
  }
  let input = Array.fromInitializer(~length=n + 1, i => (xOf(i), FxGraph.yOf(p, wave(tOf(i)), lo, hi)))
  let output = Array.fromInitializer(~length=n + 1, i => {
    let t = tOf(i)
    let x = wave(t)
    let flip = mod(Float.toInt(Math.floor(t)), 2) == 0 ? 1. : -1.
    let y = dry * x + sub * flip * x + up * (Math.abs(x) - rectifiedMean)
    (xOf(i), FxGraph.yOf(p, clamp(y, lo, hi), lo, hi))
  })
  FxGraph.path(p.layer, ~cls="curve dim")->FxGraph.setPath(Plots.pathFrom(input))
  FxGraph.path(p.layer, ~cls="curve")->FxGraph.setPath(Plots.pathFrom(output))
  FxGraph.note(p, "four cycles of a note (dim) and the octaver's output: each note finds its own cycles")
}

//==============================================================================
// utility: where a left, centre and right sound end up

let utilityMatrix = (get: string => float) => {
  // [ [ll, rl], [lr, rr] ]: output L and R from input L and R
  let swap = get("Ut_Swap") > 0.
  let (ll, lr, rl, rr) = swap ? (0., 1., 1., 0.) : (1., 0., 0., 1.)
  let il = get("Ut_InvL") > 0. ? -1. : 1.
  let ir = get("Ut_InvR") > 0. ? -1. : 1.
  let (ll, lr, rl, rr) = (ll * il, lr * il, rl * ir, rr * ir)
  // width: mid/side
  let w = get("Ut_Width")
  let (a, b) = ((1. + w) / 2., (1. - w) / 2.)
  let (ll, lr, rl, rr) = (a * ll + b * rl, a * lr + b * rr, b * ll + a * rl, b * lr + a * rr)
  let pan = get("Ut_Pan")
  let (gl, gr) = (Math.min(1., 1. - pan), Math.min(1., 1. + pan))
  let g = Math.pow(10., ~exp=get("Ut_Gain") / 20.)
  (ll * gl * g, lr * gl * g, rl * gr * g, rr * gr * g)
}

let drawUtility = (p: FxGraph.plot, get: string => float) => {
  let (cxp, cyp) = ((p.left + p.right) / 2., (p.top + p.bottom) / 2. + 10.)
  let r = (p.bottom - p.top) / 2. - 14.
  // a goniometer: mid up, side across (left to the left)
  let at = ((l: float, rr: float)) => (cxp + (rr - l) / 2. * r, cyp - (l + rr) / 2. * r)
  [(1., 0.), (0., 1.), (1., 1.), (-1., 0.), (0., -1.)]->Array.forEach(v => {
    let (x, y) = at(v)
    FxGraph.line(p.layer, ~cls="grid", cxp, cyp, x, y)
  })
  // (below the axes' ends, where the sounds' labels, above their dots, can't cover them)
  FxGraph.text(p.layer, ~anchor="middle", Pair.first(at((1., 0.))), Pair.second(at((1., 0.))) + 16., "L")
  FxGraph.text(p.layer, ~anchor="middle", Pair.first(at((0., 1.))), Pair.second(at((0., 1.))) + 16., "R")
  let (ll, lr, rl, rr) = utilityMatrix(get)
  [("left", 1., 0.), ("centre", 1., 1.), ("right", 0., 1.)]->Array.forEach(((label, l, rin)) => {
    let out = (ll * l + rl * rin, lr * l + rr * rin)
    let (x, y) = at(out)
    FxGraph.line(p.layer, ~cls="curve", cxp, cyp, x, y)
    svgEl(p.layer, "circle", [("class", Str("dot")), ("cx", Num(x)), ("cy", Num(y)), ("r", Num(3.5))])->ignore
    FxGraph.text(p.layer, x + 6., y - 4., label)
  })
  let bass = get("Ut_BassMono")
  FxGraph.note(
    p,
    `where a sound on the left, in the centre and on the right ends up` ++ (
      bass > 0. ? `; below ${PorridgeParams.hzText(expValue(20., 1000., bass))} everything is mono` : ""
    ),
  )
}

//==============================================================================
// ambience: what an impulse in the centre comes out as on each side, and the tone that leaves
// with the dry sound

let ambienceSettings = (get: string => float): AmbienceSim.settings => {
  model: Float.toInt(get("Am_Model")),
  size: get("Am_Size"),
  time: get("Am_Time"),
  density: get("Am_Density"),
  highTime: get("Am_HighTime"),
  highFreq: expValue(20., 20000., get("Am_HighFreq")),
  lowTime: get("Am_LowTime"),
  lowFreq: expValue(20., 20000., get("Am_LowFreq")),
  highCut: expValue(20., 20000., get("Am_HighCut")),
}

// the last impulse, by its settings (the tone and the impulse graphs draw from the same one)
let ambienceCache: ref<option<(AmbienceSim.settings, (Float32Array.t, Float32Array.t))>> = ref(None)

let ambienceImpulse = (get: string => float) => {
  let s = ambienceSettings(get)
  switch ambienceCache.contents {
  | Some((k, v)) if k == s => v
  | _ =>
    let v = AmbienceSim.impulse(s, ~seconds=0.15 + 1.35 * s.time)
    ambienceCache := Some((s, v))
    v
  }
}

// the wet as the width leaves it: (own side, other side)
let ambienceWidth = (get: string => float) => {
  let side = 1. + get("Am_Width")
  (0.5 * (1. + side), 0.5 * (1. - side))
}

let ambienceModelText = (get: string => float) =>
  switch Float.toInt(get("Am_Model")) {
  | 1 =>
    let (seats, a, b) = AmbienceSim.clearCoatRooms->Array.getUnsafe(AmbienceSim.clearCoatRoom(get("Am_Size")))
    `clear coat (Airwindows): a ${Int.toString(seats)}-seat room, ${Int.toString(a)} to ${Int.toString(b)} ms`
  | 2 => "verb tiny (Airwindows): a small reverb fed across the sides"
  | _ => "room: a few milliseconds of diffusion, different on each side"
  }

let drawAmbience = (p: FxGraph.plot, get: string => float) => {
  let (lo, hi) = (-18., 6.)
  FxGraph.frequencyGrid(p, ~lo, ~hi, ~step=6.)
  let (l, r) = ambienceImpulse(get)
  let n = Math.Int.min(TypedArray.length(l), 16384)
  let mix = get("Am_Mix")
  let (wetG, dryG) = (Math.sin(mix * pi / 2.), Math.cos(mix * pi / 2.))
  let (own, other) = ambienceWidth(get)
  // each side's response, smoothed over a sixth of an octave
  let steps = 240
  let hzOf = k => 20. * Math.pow(1000., ~exp=Int.toFloat(k) / Int.toFloat(steps))
  let side = (a: Float32Array.t, b: Float32Array.t) => {
    let power = Array.fromInitializer(~length=steps + 1, k => {
      // the DFT at this frequency, the phasor turned one sample at a time
      let w = 2. * pi * hzOf(k) / AmbienceSim.sr
      let (c, sn) = (Math.cos(w), -.Math.sin(w))
      let (re, im, pr, pi) = (ref(0.), ref(0.), ref(1.), ref(0.))
      for i in 0 to n - 1 {
        let x = own * a->ByteView.getUnsafe(i) + other * b->ByteView.getUnsafe(i)
        re := re.contents + x * pr.contents
        im := im.contents + x * pi.contents
        let r = pr.contents * c - pi.contents * sn
        pi := pr.contents * sn + pi.contents * c
        pr := r
      }
      FxDsp.sq(dryG + wetG * re.contents) + FxDsp.sq(wetG * im.contents)
    })
    Array.fromInitializer(~length=steps + 1, k => {
      let (from, until) = (Math.Int.max(0, k - 7), Math.Int.min(steps, k + 7))
      let sum = ref(0.)
      for j in from to until {
        sum := sum.contents + power->Array.getUnsafe(j)
      }
      Math.sqrt(sum.contents / Int.toFloat(until - from + 1))
    })
  }
  [(side(l, r), "curve"), (side(r, l), "curve alt")]->Array.forEach(((mags, cls)) => {
    let points = mags->Array.mapWithIndex((m, k) => (FxGraph.xOfHz(p, hzOf(k)), FxGraph.yOf(p, db(m), lo, hi)))
    FxGraph.path(p.layer, ~cls)->FxGraph.setPath(Plots.pathFrom(points))
  })
  let t = AmbienceSim.decayTime(l, r)
  FxGraph.note(
    p,
    `${ambienceModelText(get)}; left and right (lighter) with the dry; 60 dB down after ${PorridgeParams.msText(t * 1000.)}`,
  )
}

// The impulse: the left side above, the right below, each pixel the span of its samples.
let drawAmbienceImpulse = (p: FxGraph.plot, get: string => float) => {
  let (l, r) = ambienceImpulse(get)
  let (own, other) = ambienceWidth(get)
  let length = Int.toFloat(TypedArray.length(l)) / AmbienceSim.sr
  let until = Math.max(0.004, Math.min(AmbienceSim.decayTime(l, r) * 0.6, length))
  let n = Math.Int.min(TypedArray.length(l), Float.toInt(until * AmbienceSim.sr) + 1)
  let peak = ref(1e-6)
  for i in 0 to n - 1 {
    peak := Math.max(peak.contents, Math.abs(l->ByteView.getUnsafe(i)) + Math.abs(r->ByteView.getUnsafe(i)))
  }
  let mid = (p.top + p.bottom) / 2.
  let half = (p.bottom - p.top) / 4.
  let step = until > 0.2 ? 0.05 : until > 0.05 ? 0.01 : until > 0.01 ? 0.002 : 0.001
  FxGraph.ticks(~until, ~step, t => {
    let x = p.left + t / until * (p.right - p.left)
    FxGraph.line(p.layer, ~cls="grid", x, p.top, x, p.bottom)
    FxGraph.text(p.layer, ~anchor="middle", x, p.bottom + 12., PorridgeParams.msText(t * 1000.))
  })
  FxGraph.line(p.layer, ~cls="axis", p.left, mid - half, p.right, mid - half)
  FxGraph.line(p.layer, ~cls="axis", p.left, mid + half, p.right, mid + half)
  FxGraph.text(p.layer, ~anchor="end", p.left - 4., mid - half + 4., "L")
  FxGraph.text(p.layer, ~anchor="end", p.left - 4., mid + half + 4., "R")
  let columns = Math.Int.max(1, Float.toInt(p.right - p.left))
  let k = half * 1.8 / peak.contents
  [(l, r, mid - half), (r, l, mid + half)]->Array.forEach(((a, b, y0)) => {
    let d = ref("")
    for px in 0 to columns - 1 {
      let i0 = px * n / columns
      let i1 = Math.Int.max(i0 + 1, (px + 1) * n / columns)
      let (lo, hi) = (ref(0.), ref(0.))
      for i in i0 to Math.Int.min(i1, n) - 1 {
        let v = own * a->ByteView.getUnsafe(i) + other * b->ByteView.getUnsafe(i)
        lo := Math.min(lo.contents, v)
        hi := Math.max(hi.contents, v)
      }
      let x = p.left + Int.toFloat(px) + 0.5
      d :=
        d.contents ++
        `M${Float.toFixed(x, ~digits=1)} ${Float.toFixed(y0 - hi.contents * k, ~digits=1)}V${Float.toFixed(
            y0 - lo.contents * k + 0.5,
            ~digits=1,
          )}`
    }
    FxGraph.path(p.layer, ~cls="curve")->FxGraph.setPath(d.contents)
  })
}

//==============================================================================
// air: the tone it leaves at two levels, from Air4 run on sines; its darkening (Sinew) slows
// down loud, fast sounds more than quiet ones

let airHz = Array.fromInitializer(~length=49, k => 20. * Math.pow(1000., ~exp=Int.toFloat(k) / 48.))

// the last curves, by their settings
let airCache: ref<option<((float, float, float, float), (array<float>, array<float>))>> = ref(None)

let airCurves = (get: string => float) => {
  let key = (get("Ai_Air"), get("Ai_Body"), get("Ai_DarkFreq"), get("Ai_Darken"))
  switch airCache.contents {
  | Some((k, v)) if k == key => v
  | _ =>
    let (air, body, darkFreq, darken) = key
    let make = () => AirwindowsSim.air(~air, ~body, ~darkFreq, ~darken, ~sr=48000.)
    let v = (
      AirwindowsSim.response(make, ~sr=48000., ~amp=0.03, airHz),
      AirwindowsSim.response(make, ~sr=48000., ~amp=0.7, airHz),
    )
    airCache := Some((key, v))
    v
  }
}

let drawAir = (p: FxGraph.plot, get: string => float) => {
  let (lo, hi) = (-24., 24.)
  FxGraph.frequencyGrid(p, ~lo, ~hi, ~step=6.)
  let (quiet, loud) = airCurves(get)
  [(loud, "curve dim"), (quiet, "curve")]->Array.forEach(((gains, cls)) => {
    let points = gains->Array.mapWithIndex((g, k) => (
      FxGraph.xOfHz(p, airHz->Array.getUnsafe(k)),
      FxGraph.yOf(p, db(Math.max(g, 1e-4)), lo, hi),
    ))
    FxGraph.path(p.layer, ~cls)->FxGraph.setPath(Plots.pathFrom(points))
  })
  FxGraph.note(p, "the tone of a quiet sound, and of one near full scale (dim), which the darkening slows down more")
}

//==============================================================================
// the kinds

let loadImpulse = ref((_: FxRack.effect) => ())

let sections = (k: FxRack.kind) =>
  switch k {
  | #flanger => [
      {title: "flanger", rows: [[Knob("Fl_Rate", "rate"), Knob("Fl_Depth", "depth"), Knob("Fl_Delay", "delay")], [Knob("Fl_Feedback", "feedback"), Knob("Fl_Phase", "stereo phase"), Knob("Fl_Mix", "mix")]]},
      {title: "note", rows: [[Knob("Fl_Track", "delay track"), Knob("Fl_RateTrack", "rate track")], [Knob("Fl_PhaseRand", "random start")]]},
    ]
  | #phaser => [
      {title: "phaser", rows: [[Knob("Ph_Rate", "rate"), Knob("Ph_Depth", "depth"), Knob("Ph_Freq", "frequency"), Knob("Ph_Feedback", "feedback")], [List("Ph_Stages", "stages"), Knob("Ph_Spread", "spread"), Knob("Ph_Phase", "stereo phase"), Knob("Ph_Mix", "mix")]]},
      {title: "note", rows: [[Knob("Ph_Track", "note track"), Knob("Ph_RateTrack", "rate track")], [Knob("Ph_PhaseRand", "random start")]]},
    ]
  | #space => [
      {title: "algo reverb", rows: [[List("Rv_Model", "model"), Knob("Rv_Size", "size"), Knob("Rv_Decay", "decay"), Knob("Rv_Predelay", "predelay")], [Knob("Rv_Damp", "damping"), Knob("Rv_LowCut", "low cut"), Knob("Rv_Width", "width"), Knob("Rv_Mod", "modulation")]]},
      {title: "level", rows: [[Knob("Rv_Mix", "mix")]]},
    ]
  | #convolve => [
      {title: "impulse", rows: [[List("Cv_Impulse", "impulse"), Button("load file…", "Load an impulse response from a WAV, AIFF or other audio file (you can also drop one on the graph)", e => loadImpulse.contents(e))], [Knob("Cv_Length", "length"), Switch("Cv_Reverse", "reverse")]]},
      {title: "wet", rows: [[Knob("Cv_Predelay", "predelay"), Knob("Cv_LowCut", "low cut"), Knob("Cv_HighCut", "high cut")], [Knob("Cv_Width", "width"), Knob("Cv_Gain", "gain"), Knob("Cv_Mix", "mix")]]},
    ]
  | #bode => [
      {title: "frequency shifter", rows: [[Knob("Bd_Shift", "shift"), List("Bd_Mode", "mode"), Knob("Bd_Mix", "mix")], [Knob("Bd_Feedback", "feedback"), Knob("Bd_Delay", "delay")]]},
    ]
  | #filter => [
      {title: "filter", rows: [[List("Ff_Type", "type"), Knob("Ff_Cutoff", "cutoff"), Knob("Ff_Resonance", "resonance")], [Knob("Ff_Morph", "morph"), Knob("Ff_Drive", "drive"), Knob("Ff_Spread", "stereo spread")]]},
      {title: "level & key", rows: [[Knob("Ff_Mix", "mix")], [Knob("Ff_Track", "note track")]]},
    ]
  | #shifter => [
      {title: "key shifter", rows: [[Knob("Sh_Ratio", "ratio of the note"), Knob("Sh_Hz", "offset"), List("Sh_Mode", "mode")], [Knob("Sh_Mix", "mix")]]},
    ]
  | #resonator => [
      {title: "resonator", rows: [[List("Rs_Model", "model"), Knob("Rs_Pitch", "pitch"), Knob("Rs_Decay", "decay")], [Knob("Rs_Bright", "brightness")]]},
      {title: "level", rows: [[Knob("Rs_Gain", "gain")], [Knob("Rs_Mix", "mix")]]},
    ]
  | #octaver => [
      {title: "octaver", rows: [[Knob("Oc_Sub", "octave down"), Knob("Oc_Up", "octave up")], [Knob("Oc_Dry", "dry")]]},
    ]
  | #utility => [
      {title: "utility", rows: [[Knob("Ut_Gain", "gain"), Knob("Ut_Pan", "pan"), Knob("Ut_Width", "width")], [Switch("Ut_InvL", "invert L"), Switch("Ut_InvR", "invert R"), Switch("Ut_Swap", "swap L/R")]]},
      {title: "bass", rows: [[Knob("Ut_BassMono", "mono below")]]},
    ]
  | #ambience => [
      {title: "ambience", rows: [[List("Am_Model", "model"), Knob("Am_Size", "size"), Knob("Am_Time", "time"), Knob("Am_Density", "density")], [Knob("Am_Predelay", "predelay"), Knob("Am_HighCut", "high cut"), Knob("Am_Width", "width"), Knob("Am_Mix", "mix")]]},
      {title: "room's loops", rows: [[Knob("Am_HighTime", "high time"), Knob("Am_HighFreq", "high freq")], [Knob("Am_LowTime", "low time"), Knob("Am_LowFreq", "low freq")]]},
    ]
  | #air => [
      {title: "air", rows: [[Knob("Ai_Air", "air"), Knob("Ai_Body", "body")]]},
      {title: "darken", rows: [[Knob("Ai_Darken", "darken"), Knob("Ai_DarkFreq", "dark freq")]]},
    ]
  | _ => []
  }

// Controls that do something only per-voice (each note's random start) or only on the whole
// sound (bass mono, which the voices' utility leaves out), shown only there.
let perVoiceOnly = ["Ph_PhaseRand", "Fl_PhaseRand"]
let wholeSoundOnly = ["Ut_BassMono"]
let shows = (item, ~perVoice) =>
  switch item {
  | Knob(p, _) | List(p, _) | Switch(p, _) =>
    let elsewhere = perVoice ? wholeSoundOnly : perVoiceOnly
    !(elsewhere->Array.includes(p))
  | Button(_) => true
  }

let graphTitle = (k: FxRack.kind) =>
  switch k {
  | #flanger | #phaser => "response"
  | #filter => "response: drag the point for cutoff and resonance"
  | #space => "tail"
  | #convolve => "impulse"
  | #bode => "partials"
  | #utility => "stereo"
  | #ambience | #air => "tone"
  | #shifter => "partials: each note moves by a share of its own pitch"
  | #resonator => "response for a 220 Hz note"
  | #octaver => "waveform"
  | _ => ""
  }

//==============================================================================
// the tab

// perVoice: whether it is in the voice lane (or the rack).
let make = (ctx: Ctx.t, body, e: FxRack.effect, ~perVoice, ~w, ~h) => {
  let id = FxRack.id(e, ...)
  let model = ctx.model
  let get = x => model->ParamModel.get(id(x))
  let secs = sections(e.kind)->Array.filterMap(s =>
    switch s.rows->Array.map(row => row->Array.filter(shows(_, ~perVoice)))->Array.filter(row => row != []) {
    | [] => None
    | rows => Some({...s, rows})
    }
  )
  let gap = Grid.gap
  let cols = s => s.rows->Array.reduce(1, (n, row) => Math.Int.max(n, Array.length(row)))
  let totalCols = secs->Array.reduce(0, (n, s) => n + cols(s))
  let count = Int.toFloat(Array.length(secs))
  let frame = 2. + 2. * Grid.padX - Grid.columnGap
  let cw = Math.min(150., (w - gap * (count - 1.) - count * frame) / Int.toFloat(totalCols))
  let rows = secs->Array.reduce(1, (n, s) => Math.Int.max(n, Array.length(s.rows)))
  let topH = Grid.panelHeight(rows)
  let x = ref(0.)
  secs->Array.forEachWithIndex((s, i) => {
    let last = i == Array.length(secs) - 1
    let pw = last ? w - x.contents : Int.toFloat(cols(s)) * cw + frame
    let panel = Panel.make(body, ~title=s.title, ~x=x.contents, ~y=0., ~w=pw, ~h=topH)
    let g = Grid.make(ctx, panel.el, ~cw)
    s.rows->Array.forEachWithIndex((row, r) =>
      row->Array.forEachWithIndex((item, c) =>
        switch item {
        | Knob(p, label) => g->Grid.param(id(p), c, r, label)
        | List(p, label) => g->Grid.choice(id(p), c, r, label)
        | Switch(p, label) => g->Grid.toggle(id(p), c, r, label)
        | Button(label, status, f) => g->Grid.button(label, c, r, ~status, () => f(e))
        }
      )
    )
    x := x.contents + pw + gap
  })

  let gy = topH + gap
  let gh = h - gy
  // the algo reverb shows its space beside its tail (a picture, so the smaller), the ambience its
  // impulse beside its tone
  let sceneW = switch e.kind {
  | #space => Math.round(w * 0.3)
  | #ambience => Math.round(w * 0.46)
  | _ => 0.
  }
  let graphX = sceneW > 0. ? sceneW + gap : 0.
  let panel = Panel.make(body, ~title=graphTitle(e.kind), ~x=graphX, ~y=gy, ~w=w - graphX, ~h=gh)
  let graphBox = {x: 8., y: 25., w: w - graphX - 18., h: gh - 35.}
  // the filter has its own graph, with the point to drag
  let filterGraph =
    e.kind == #filter
      ? Some(
          FilterGraph.make(
            ctx,
            panel.el,
            graphBox,
            {
              typeOf: () => Float.toInt(get("Ff_Type")),
              cutoff: id("Ff_Cutoff"),
              toHz: v => expValue(20., 20000., v),
              ofHz: hz => clamp(PorridgeParams.expPos(20., 20000., hz), 0., 1.),
              res: id("Ff_Resonance"),
              morph: id("Ff_Morph"),
              drive: id("Ff_Drive"),
              mix: Some(id("Ff_Mix")),
              spread: Some(id("Ff_Spread")),
              second: () => None,
              alsoIds: [id("Ff_Type")],
            },
          ),
        )
      : None
  let fg = FxGraph.make(ctx, panel.el, e.kind == #filter ? {...graphBox, h: 0.} : graphBox)
  let layer = FxGraph.group(fg.svg)
  let p: FxGraph.plot = {layer, left: 40., right: fg.w - 16., top: 8., bottom: fg.h - 18.}
  let impulse = () => ctx.programs.impulses[e.copy - 1]->Option.flatMap(x => x)
  let draw = () => {
    layer->setTextContent("")
    switch e.kind {
    | #flanger => drawFlanger(p, get)
    | #phaser => drawPhaser(p, get)
    | #space => drawSpace(p, get)
    | #convolve => drawConvolve(p, get, ~which=e.copy - 1, ~file=impulse())
    | #bode => drawBode(p, get)
    | #utility => drawUtility(p, get)
    | #ambience => drawAmbience(p, get)
    | #air => drawAir(p, get)
    | #shifter => drawShifter(p, get)
    | #resonator => drawResonator(p, get)
    | #octaver => drawOctaver(p, get)
    | _ => ()
    }
  }
  let redraw = FxGraph.redraw(fg, draw)
  model->ParamModel.listenEach(FxRack.params(e), redraw.request)

  // the ambience's impulse, drawn when its settings change
  let impulseGraph = if e.kind == #ambience {
    let ip = Panel.make(body, ~title="impulse in the centre", ~x=0., ~y=gy, ~w=sceneW, ~h=gh)
    let ig = FxGraph.inPanel(ctx, ip)
    let ilayer = FxGraph.group(ig.svg)
    let iplot: FxGraph.plot = {layer: ilayer, left: 22., right: ig.w - 10., top: 8., bottom: ig.h - 18.}
    let r = FxGraph.redraw(ig, () => {
      ilayer->setTextContent("")
      drawAmbienceImpulse(iplot, get)
    })
    model->ParamModel.listenEach(FxRack.params(e), r.request)
    Some(r)
  } else {
    None
  }

  // the space, animated while it shows (about 30 frames a second)
  let startScene = if e.kind == #space {
    let sp = Panel.make(body, ~title="space", ~x=0., ~y=gy, ~w=sceneW, ~h=gh)
    let sg = FxGraph.inPanel(ctx, sp)
    let scene = {sw: sg.w, sh: sg.h, layer: ScenePool.make(FxGraph.group(sg.svg))}
    let origin = Date.now()
    FxGraph.animate(sg, ~everyOther=true, _ => drawScene(scene, get, (Date.now() - origin) / 1000.))
  } else {
    () => ()
  }
  if e.kind == #convolve {
    ctx.programs->ProgramStore.onImpulses(redraw.request)
    Impulse.watchViews(ctx.pc, redraw.request)
    // an audio file dropped on the graph becomes this convolver's impulse
    fg.root->onDrag(#dragover, ev => {
      ev->preventDefault
      ev->stopPropagation
    })
    fg.root->onDrag(#drop, ev => {
      ev->preventDefault
      ev->stopPropagation
      ev
      ->dataTransfer
      ->Option.flatMap(d => d->transferredFiles->item(0))
      ->Option.forEach(f => ctx.programs->ProgramStore.loadImpulseFile(e.copy - 1, f)->Promise.ignore)
    })
  }
  () => {
    redraw.now()
    filterGraph->Option.forEach(f => f())
    impulseGraph->Option.forEach(r => r.now())
    if e.kind == #convolve {
      Impulse.requestViews(ctx.pc)
    }
    startScene()
  }
}

//==============================================================================
// an effect in brief: a summary of its settings (for hover texts)

let summary = (model, e: FxRack.effect) => {
  let id = FxRack.id(e, ...)
  let s = x => model->ParamModel.shortText(id(x))
  switch e.kind {
  | #chorus => `${s("C_Voices")}, ${s("C_Rate")}\n${s("C_MinDelay")} + ${s("C_Depth")}`
  | #delay =>
    let get = x => model->ParamModel.get(id(x))
    let n = x => Float.toString(Math.round(get(x) * 100.) / 100.)
    let percent = x => Float.toFixed(get(x) * 100., ~digits=0)
    `${n("D_LengthL")} / ${n("D_LengthR")} × ${s("D_Unit")}\nfeedback ${percent("D_FeedbackL")} / ${percent("D_FeedbackR")} %`
  | #reverb => `${s("R_Size")} room, ${s("R_Length")}\npredelay ${s("R_Predelay")}`
  | #eq =>
    switch FxRack.eqBandTypes(e)->Array.filter(i => model->ParamModel.get(i) != 0.)->Array.length {
    | 0 => "every band off"
    | 1 => "1 band on"
    | n => `${Int.toString(n)} bands on`
    }
  | #distortion =>
    DistTypes.isModel(Float.toInt(model->ParamModel.get(id("Sat_Type"))))
      ? `drive ${s("Sat_Drive")}, mix ${s("Sat_Mix")}\npregain ${s("Sat_Pregain")}`
      : `pregain ${s("Sat_Pregain")}\nlimit ${s("Sat_Limit")}`
  | #flanger => `${s("Fl_Rate")}, ${s("Fl_Delay")}\nfeedback ${s("Fl_Feedback")}`
  | #phaser => `${s("Ph_Stages")} stages, ${s("Ph_Rate")}\n${s("Ph_Freq")}, fb ${s("Ph_Feedback")}`
  | #compressor => `${s("Cp_Bands")}\namount ${s("Cp_Depth")}, mix ${s("Cp_Mix")}`
  | #space => `${s("Rv_Model")}, ${s("Rv_Decay")}\nsize ${s("Rv_Size")}`
  | #convolve => `${s("Cv_Impulse")}\nlength ${s("Cv_Length")}`
  | #bode => `${s("Bd_Shift")} ${s("Bd_Mode")}\nfeedback ${s("Bd_Feedback")}`
  | #filter => `${s("Ff_Type")}\nres ${s("Ff_Resonance")}`
  | #utility => `width ${s("Ut_Width")}, pan ${s("Ut_Pan")}\n${s("Ut_Gain")}`
  | #ambience => `${s("Am_Model")}, size ${s("Am_Size")}\ntime ${s("Am_Time")}`
  | #air => `air ${s("Ai_Air")}, body ${s("Ai_Body")}\ndarken ${s("Ai_Darken")}`
  | #shifter => `${s("Sh_Ratio")} ${s("Sh_Mode")}\noffset ${s("Sh_Hz")}`
  | #resonator => `${s("Rs_Model")}, ${s("Rs_Pitch")}\ndecay ${s("Rs_Decay")}`
  | #octaver => `down ${s("Oc_Sub")}, up ${s("Oc_Up")}\ndry ${s("Oc_Dry")}`
  }
}
