// A convolver's impulse response from a file. Each convolver (Cv_, Cv2_) has one, kept with the
// program (Preset), in the stored state for the current program, and sent to the patch in
// chunks (dsp/Types.cmajor ImpulseChunk). Impulses are kept at 48 kHz or less and at most
// maxFrames long: what the convolver can hold. The noise's sample (noiseSlot) is kept and sent
// the same way, mono.

type t = {
  name: string,
  rate: float,
  left: Float32Array.t,
  // a stereo impulse's right channel
  right: option<Float32Array.t>,
}

// one per convolver (PorridgeParams.newKinds convolve: the first and its copy), then the noise's
// sample (noiseSlot: the noise type "sample", dsp/Oscillator.cmajor NoiseSample)
let slots = 3
let noiseSlot = 2
let maxFrames = 131072
let maxRate = 48000.
let chunkFrames = 2048

@get_index external at: (Float32Array.t, int) => float = ""
@set_index external put: (Float32Array.t, int, float) => unit = ""

let frames = imp => TypedArray.length(imp.left)
let seconds = imp => Int.toFloat(frames(imp)) / imp.rate

// Halves the rate until it is 48 kHz or less (a two-tap average against aliasing is enough for
// the reverb tails this is for), then keeps at most maxFrames.
let fit = (data: Float32Array.t, rate) => {
  let rec down = (d: Float32Array.t, r) =>
    if r <= maxRate {
      (d, r)
    } else {
      let n = TypedArray.length(d) / 2
      let out = Float32Array.fromLength(n)
      for i in 0 to n - 1 {
        out->put(i, 0.5 *. (d->at(2 * i) +. d->at(2 * i + 1)))
      }
      down(out, r /. 2.)
    }
  let (d, r) = down(data, rate)
  (TypedArray.length(d) > maxFrames ? d->TypedArray.slice(~start=0, ~end=maxFrames) : d, r)
}

// Leading silence would only delay the sound: the impulse starts at its first sample above
// -60 dB of its peak.
let trimStart = (channels: array<Float32Array.t>) => {
  let peak = channels->Array.reduce(0., (m, d) => {
    let p = ref(m)
    for i in 0 to TypedArray.length(d) - 1 {
      p := Math.max(p.contents, Math.abs(d->at(i)))
    }
    p.contents
  })
  let threshold = peak *. 0.001
  let first = channels->Array.reduce(max_int, (m, d) => {
    let i = ref(0)
    while i.contents < TypedArray.length(d) && Math.abs(d->at(i.contents)) <= threshold {
      i := i.contents + 1
    }
    Math.Int.min(m, i.contents)
  })
  first > 0 && first < max_int ? channels->Array.map(d => d->TypedArray.slice(~start=first, ~end=TypedArray.length(d))) : channels
}

let fromAudio = (name, audio: AudioFile.t): option<t> => {
  let channels = switch audio.sides {
  | Some((l, r)) => [l, r]
  | None => [audio.samples]
  }
  let fitted = channels->trimStart->Array.map(d => fit(d, audio.sampleRate))
  switch fitted {
  | [(left, rate), (right, _)] if TypedArray.length(left) > 0 => Some({name, rate, left, right: Some(right)})
  | [(left, rate)] if TypedArray.length(left) > 0 => Some({name, rate, left, right: None})
  | _ => None
  }
}

// The noise's sample from a file: mono (the channels averaged), from its first sound, fitted as
// an impulse is (2.7 s at 48 kHz at most), its end crossfaded into its start (with equal power,
// as for noise) so that it loops without a click, and as loud (RMS) as the white noise. None
// if it's too short or silent.
let noiseRms = 0.57735027
let loopFade = 2048

let noiseFromAudio = (name, audio: AudioFile.t): option<t> => {
  let (d, rate) = fit(trimStart([audio.samples])->Array.getUnsafe(0), audio.sampleRate)
  let n = TypedArray.length(d)
  let fade = Math.Int.min(loopFade, n / 4)
  if n < 256 {
    None
  } else {
    let m = n - fade
    let out = Float32Array.fromLength(m)
    for i in 0 to m - 1 {
      out->put(i, d->at(i))
    }
    for i in 0 to fade - 1 {
      let a = Math.Constants.pi /. 2. *. Int.toFloat(i) /. Int.toFloat(fade)
      out->put(i, d->at(i) *. Math.sin(a) +. d->at(m + i) *. Math.cos(a))
    }
    let power = ref(0.)
    for i in 0 to m - 1 {
      power := power.contents +. out->at(i) *. out->at(i)
    }
    let rms = Math.sqrt(power.contents /. Int.toFloat(m))
    if rms < 1e-6 {
      None
    } else {
      for i in 0 to m - 1 {
        out->put(i, out->at(i) *. noiseRms /. rms)
      }
      Some({name, rate, left: out, right: None})
    }
  }
}

//==============================================================================
// sending to the patch

type chunkPayload = {
  which: int,
  channels: int,
  length: int,
  offset: int,
  rate: float,
  // the send's id (see send below)
  send: int,
  left: array<float>,
  right: array<float>,
}

let chunkOf = (d: Float32Array.t, offset) => {
  let part = Float32Array.fromLength(chunkFrames)
  let n = Math.Int.min(chunkFrames, TypedArray.length(d) - offset)
  for i in 0 to n - 1 {
    part->put(i, d->at(offset + i))
  }
  Bank.arrayOfFloats(part)
}

// The impulse's chunks, sent a few at a time so that the patch's event queue keeps up. A newer
// send to the same convolver stops an older one from the same sender (the view and the worker
// each have their own; see sender below). Every chunk of a send carries its id, which no other
// send of either sender has, so the patch drops what still comes of an older send to the slot
// once a newer one has started, whichever sent it (dsp/Synth.cmajor impulseIn).
let generation = Array.make(~length=slots, 0)

// Stops this sender's send to the slot, if one is under way.
let stop = which =>
  if which >= 0 && which < slots {
    generation->Array.setUnsafe(which, generation->Array.getUnsafe(which) + 1)
  }

let send = (pc, which, imp: option<t>) =>
  if which >= 0 && which < slots {
    let gen = generation->Array.getUnsafe(which) + 1
    generation->Array.setUnsafe(which, gen)
    // (random: the view and the worker can't count together)
    let send = Math.Int.random(1, 2147483647)
    switch imp {
    | None =>
      // an empty impulse: the file's slot plays silence until one is loaded
      let silence = Bank.arrayOfFloats(Float32Array.fromLength(chunkFrames))
      PatchConnection.sendEventOrValueNow(
        pc,
        "impulseIn",
        {which, channels: 1, length: 0, offset: 0, rate: maxRate, send, left: silence, right: silence},
      )
    | Some(imp) =>
      let length = frames(imp)
      let count = (length + chunkFrames - 1) / chunkFrames
      let rec next = k =>
        if generation->Array.getUnsafe(which) == gen && k < count {
          for j in k to Math.Int.min(count, k + 4) - 1 {
            let offset = j * chunkFrames
            PatchConnection.sendEventOrValueNow(
              pc,
              "impulseIn",
              {
                which,
                channels: imp.right == None ? 1 : 2,
                length,
                offset,
                rate: imp.rate,
                send,
                left: chunkOf(imp.left, offset),
                right: chunkOf(imp.right->Option.getOr(imp.left), offset),
              },
            )
          }
          setTimeout(() => next(k + 4), 10)->ignore
        }
      next(0)
    }
  }

//==============================================================================
// encoding: { "name", "rate", "left": base64 float32, "right"?: ... }

let toJson = (imp: t): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("name", JSON.String(imp.name)),
      ("rate", JSON.Number(imp.rate)),
      ("left", JSON.String(Bank.floatsToBase64(imp.left))),
      ...imp.right->Option.mapOr([], r => [("right", JSON.String(Bank.floatsToBase64(r)))]),
    ]),
  )

let fromJson = (j: JSON.t): option<t> =>
  switch j {
  | Object(d) =>
    switch (d->Dict.get("name"), d->Dict.get("rate"), d->Dict.get("left")) {
    | (Some(String(name)), Some(Number(rate)), Some(String(left))) if rate > 0. =>
      let (left, rate) = fit(Bank.floatsFromBase64(left), rate)
      let right = switch d->Dict.get("right") {
      | Some(String(r)) => Some(fit(Bank.floatsFromBase64(r), rate)->Pair.first)
      | _ => None
      }
      TypedArray.length(left) > 0 ? Some({name, rate, left, right}) : None
    | _ => None
    }
  | _ => None
  }

// Every convolver's impulse, as a JSON array (null where there is none).
let listToJson = (list: array<option<t>>): JSON.t =>
  JSON.Array(list->Array.map(imp => imp->Option.mapOr(JSON.Null, toJson)))

let listFromJson = (j: JSON.t): array<option<t>> =>
  switch j {
  | Array(items) => Array.fromInitializer(~length=slots, i => items[i]->Option.flatMap(fromJson))
  | _ => Array.make(~length=slots, None)
  }

let none = () => Array.make(~length=slots, None)

let isEmpty = (list: array<option<t>>) => list->Array.every(Option.isNone)

// A slot's impulse as JSON text, as the list's encoding has it ("null" for none).
let itemText = (imp: option<t>) => imp->Option.mapOr("null", imp => JSON.stringify(toJson(imp)))

// The encoding of a list whose slots' texts these are.
let encodeTexts = texts => texts->Array.every(x => x == "null") ? "" : `[${texts->Array.join(",")}]`

let encode = list => encodeTexts(list->Array.map(itemText))

let decode = s =>
  s == ""
    ? none()
    : switch JSON.parseOrThrow(s) {
      | j => listFromJson(j)
      | exception _ => none()
      }

// An encoded list's items (null where there is none) and their texts.
let items = s => {
  let items = switch s == "" ? JSON.Null : JSON.parseOrThrow(s) {
  | Array(items) => items
  | _ => []
  | exception _ => []
  }
  Array.fromInitializer(~length=slots, which => {
    let item = items[which]->Option.getOr(JSON.Null)
    (item, JSON.stringify(item))
  })
}

// Who sends the impulses: the view sends the slots it changes as it stores the list (a file
// loaded, an undo, another program), and the worker the slots a stored list changes otherwise
// (a host's session, a session from before the slots), with or without the view open. The
// worker would be slower: from the view storing a 1 MB stereo impulse to the convolver holding
// it took 1.8 s against the view's 1.1 s in the plugin, the worker decoding it in QuickJS
// (0.7 s) and then sending it (0.8 s).
//
// So the view announces the slots it has sent just before it stores the list, and the worker
// skips them in that list. The announcement is a request for a key that is never stored,
// sentPrefix followed by { slots, length } (the slots, and the encoded list's length): the patch
// answers a request by broadcasting the key to every view, the worker too, in order with the
// stores around it, and no session holds it, so a host restoring one has the worker send every
// slot it changes.
let sentPrefix = "impulsesSent?"

type announcement = {slots: array<int>, length: int}

let announceSent = (pc, slots, encoded) =>
  PatchConnection.requestStoredStateValue(
    pc,
    sentPrefix ++ JSON.stringifyAny({slots, length: String.length(encoded)})->Option.getOr(""),
  )

@scope("JSON") external parseAnnouncement: string => announcement = "parse"

// The worker's sender: sends the impulses of encoded lists (as the stored state keeps them) to
// the patch, each only when it differs from what the patch was sent for its slot last (an
// impulse takes a moment to arrive, and sending one again restarts it) and the view hasn't
// sent it. `stored` takes the stored lists, `announced` the view's announcements (keys starting
// with sentPrefix).
type sender = {stored: string => unit, announced: string => unit}

let sender = pc => {
  // each slot's JSON as the patch was last sent it (null: the patch starts with none)
  let sent = Array.make(~length=slots, "null")
  // the slots the view says it sent of the list it stores next
  let fromView = ref(None)
  {
    announced: key =>
      fromView :=
        switch parseAnnouncement(key->String.slice(~start=String.length(sentPrefix))) {
        | a => Some(a)
        | exception _ => None
        },
    stored: s => {
      // (only for the list it was made for: one that changes nothing isn't broadcast)
      let viewSent = switch fromView.contents {
      | Some(a) if a.length == String.length(s) => a.slots
      | _ => []
      }
      fromView := None
      items(s)->Array.forEachWithIndex(((item, text), which) =>
        if sent->Array.getUnsafe(which) != text {
          sent->Array.setUnsafe(which, text)
          if viewSent->Array.includes(which) {
            // (the patch would drop what's left of an older send from here; this saves sending it)
            stop(which)
          } else {
            send(pc, which, fromJson(item))
          }
        }
      )
    },
  }
}

// The envelope of an impulse for drawing: the peak of each of `n` pieces, 0..1.
let envelope = (imp: t, n) => {
  let length = frames(imp)
  Array.fromInitializer(~length=n, k => {
    let (a, b) = (k * length / n, Math.Int.max((k + 1) * length / n, k * length / n + 1))
    let p = ref(0.)
    for i in a to Math.Int.min(b, length) - 1 {
      p := Math.max(p.contents, Math.abs(imp.left->at(i)))
      imp.right->Option.forEach(r => p := Math.max(p.contents, Math.abs(r->at(i))))
    }
    p.contents
  })
}

//==============================================================================
// what the convolvers hold, as the patch reports it (dsp/Types.cmajor ImpulseView): each one's
// impulse, built in or from a file, as its length and the peaks of 512 pieces of it

type view = {seconds: float, peaks: array<float>}

let views: array<option<view>> = Array.make(~length=slots, None)
let viewListeners: array<unit => unit> = []
let watching = ref(false)

@get external viewWhich: JSON.t => int = "which"
@get external viewSeconds: JSON.t => float = "seconds"
@get external viewPeaks: JSON.t => array<float> = "peaks"

// Calls fn whenever a convolver's impulse changes, and asks the patch for them all again.
let watchViews = (pc, fn) => {
  viewListeners->Array.push(fn)
  if !watching.contents {
    watching := true
    PatchConnection.addEndpointListener(pc, "impulseViewOut", j => {
      let which = viewWhich(j)
      if which >= 0 && which < slots {
        views->Array.setUnsafe(which, Some({seconds: viewSeconds(j), peaks: viewPeaks(j)}))
        viewListeners->Array.forEach(f => f())
      }
    })
  }
}

let requestViews = pc => PatchConnection.sendEventOrValue(pc, "impulseView", 1)
