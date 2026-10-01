// Plays a sound in the view itself, through the browser's audio output rather than the
// plugin's (the matched sample, to compare with the synth playing a candidate): one at a time.

type context
type buffer
type source
type node
@new external makeContext: unit => context = "AudioContext"
@send external createBuffer: (context, int, int, float) => buffer = "createBuffer"
@send external copyToChannel: (buffer, Float32Array.t, int) => unit = "copyToChannel"
@send external createBufferSource: context => source = "createBufferSource"
@set external setBuffer: (source, buffer) => unit = "buffer"
@get external destination: context => node = "destination"
@send external connect: (source, node) => unit = "connect"
@send external start: source => unit = "start"
@send external stopSource: source => unit = "stop"
@set external setOnEnded: (source, unit => unit) => unit = "onended"
@send external resume: context => promise<unit> = "resume"
@send external close: context => promise<unit> = "close"

type t = {mutable context: option<context>, mutable playing: option<source>}

let make = () => {context: None, playing: None}

let stop = t => {
  t.playing->Option.forEach(s =>
    try s->stopSource catch {
    | _ => ()
    }
  )
  t.playing = None
}

let isPlaying = t => t.playing != None

// Plays channels (one or two) at sampleRate; onEnd when it finishes or is stopped by another.
let play = (t, channels: array<Float32Array.t>, ~sampleRate, ~onEnd=() => ()) => {
  stop(t)
  let context = switch t.context {
  | Some(c) => c
  | None =>
    let c = makeContext()
    t.context = Some(c)
    c
  }
  context->resume->ignore
  let n = channels[0]->Option.mapOr(0, TypedArray.length)
  let b = context->createBuffer(Array.length(channels), Math.Int.max(1, n), sampleRate)
  channels->Array.forEachWithIndex((data, i) => b->copyToChannel(data, i))
  let s = context->createBufferSource
  s->setBuffer(b)
  s->connect(context->destination)
  s->setOnEnded(() => {
    if t.playing == Some(s) {
      t.playing = None
    }
    onEnd()
  })
  s->start
  t.playing = Some(s)
}

let dispose = t => {
  stop(t)
  t.context->Option.forEach(c => c->close->ignore)
  t.context = None
}
