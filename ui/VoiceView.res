// The sounding notes, as the DSP reports them about 25 times a second while the view is open
// (voiceView / voiceViewOut, dsp/Types.cmajor's VoiceView): for each note, newest first, where
// it is on each envelope and LFO, its filter's cutoff, and the knob positions the modulation
// matrix moves its first targets to. The graphs and controls draw a mark per note from it, so
// that each note's own movement shows.

open! Web

type voice = {
  key: int,
  released: bool,
  // the time on each envelope's clock, ms (since the note-on, or the note-off once released)
  ampMs: float,
  filterMs: float,
  mod1Ms: float,
  mod2Ms: float,
  level: float,
  // phases 0..1
  lfo1: float,
  lfo2: float,
  lfo3: float,
  cutoff: float,
}

// the report as it arrives
type raw = {
  count: int,
  key: array<int>,
  released: array<bool>,
  ampMs: array<float>,
  filterMs: array<float>,
  mod1Ms: array<float>,
  mod2Ms: array<float>,
  level: array<float>,
  lfo1: array<float>,
  lfo2: array<float>,
  lfo3: array<float>,
  cutoff: array<float>,
  numTargets: int,
  targets: array<int>,
  positions: array<float>,
}
external asRaw: JSON.t => raw = "%identity"

let targetsPerVoice = 16

type t = {
  mutable voices: array<voice>,
  // each modulated target's knob position in each note, by target index
  mutable positions: Map.t<int, array<float>>,
  listeners: array<unit => unit>,
  // by target: what redraws its controls' marks
  targetListeners: Map.t<int, array<unit => unit>>,
}

let views: WeakMap.t<PatchConnection.t, t> = WeakMap.make()

let at = (a, i) => a[i]->Option.getOr(0.)

let receive = (t, json) => {
  let r = asRaw(json)
  let n = r.count
  t.voices = Array.fromInitializer(~length=n, i => {
    key: r.key[i]->Option.getOr(0),
    released: r.released[i]->Option.getOr(false),
    ampMs: r.ampMs->at(i),
    filterMs: r.filterMs->at(i),
    mod1Ms: r.mod1Ms->at(i),
    mod2Ms: r.mod2Ms->at(i),
    level: r.level->at(i),
    lfo1: r.lfo1->at(i),
    lfo2: r.lfo2->at(i),
    lfo3: r.lfo3->at(i),
    cutoff: r.cutoff->at(i),
  })
  let before = t.positions
  let positions = Map.make()
  for k in 0 to r.numTargets - 1 {
    r.targets[k]->Option.forEach(target =>
      positions->Map.set(
        target,
        Array.fromInitializer(~length=n, i => r.positions->at(i * targetsPerVoice + k))->Array.filter(x => x >= 0.),
      )
    )
  }
  t.positions = positions
  t.listeners->Array.forEach(f => f())
  // the targets in this report or the last
  let touched = Set.make()
  before->Map.forEachWithKey((_, k) => touched->Set.add(k))
  positions->Map.forEachWithKey((_, k) => touched->Set.add(k))
  touched->Set.forEach(k => t.targetListeners->Map.get(k)->Option.forEach(fs => fs->Array.forEach(f => f())))
}

// The connection's notes, asked for the first time one is wanted.
let get = pc =>
  switch views->WeakMap.get(pc) {
  | Some(t) => t
  | None =>
    let t = {voices: [], positions: Map.make(), listeners: [], targetListeners: Map.make()}
    views->WeakMap.set(pc, t)->ignore
    pc->PatchConnection.addEndpointListener("voiceViewOut", json => receive(t, json))
    pc->PatchConnection.sendEventOrValue("voiceView", 1)
    t
  }

// The view is going: no more reports.
let stop = pc =>
  if views->WeakMap.has(pc) {
    pc->PatchConnection.sendEventOrValue("voiceView", 0)
  }

let listen = (t, f) => t.listeners->Array.push(f)

let listenTarget = (t, target, f) =>
  switch t.targetListeners->Map.get(target) {
  | Some(fs) => fs->Array.push(f)
  | None => t.targetListeners->Map.set(target, [f])
  }

// the knob positions the notes have moved a target's knob to (none while nothing moves it)
let positionsOf = (t, target) => t.positions->Map.get(target)->Option.getOr([])

// A group of marks in an SVG layer, one per note, made as needed: show places each (x, y) and
// hides the rest; released notes are drawn hollow.
type marks = {layer: Dom.element, dots: array<Dom.element>}

let marks = layer => {layer, dots: []}

let show = (m, points: array<(float, float, bool)>) => {
  points->Array.forEachWithIndex(((x, y, released), i) => {
    let dot = switch m.dots[i] {
    | Some(d) => d
    | None =>
      let d = m.layer->svgEl("circle", [("class", Str("vdot")), ("r", Num(3.2))])
      m.dots->Array.push(d)
      d
    }
    dot->setAttribute("cx", Num(x))
    dot->setAttribute("cy", Num(y))
    dot->setAttribute("display", Str("inline"))
    dot->toggleClass("rel", released)
  })
  m.dots->Array.forEachWithIndex((d, i) =>
    if i >= Array.length(points) {
      d->setAttribute("display", Str("none"))
    }
  )
}

// The y of a polyline at x (its points left to right), between xFrom and xTo.
let yAt = (points: array<(float, float)>, x) => {
  let n = Array.length(points)
  let rec go = i =>
    if i >= n - 1 {
      points[n - 1]->Option.mapOr(0., Pair.second)
    } else {
      let (x0, y0) = points->Array.getUnsafe(i)
      let (x1, y1) = points->Array.getUnsafe(i + 1)
      if x <= x1 || i == n - 2 {
        x1 == x0 ? y1 : y0 + (y1 - y0) * Float.clamp((x - x0) / (x1 - x0), ~min=0., ~max=1.)
      } else {
        go(i + 1)
      }
    }
  n == 0 ? 0. : go(0)
}
