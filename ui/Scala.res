// Microtuning from Scala files: a scale (.scl) and an optional keyboard mapping (.kbm), turned
// into the pitch of every MIDI key. Presets keep both files' text as they were loaded.
//
// .scl: "!" comment lines, a description line, the number of notes N, then N pitches, each in
// cents (has a ".") or a ratio ("3/2", "2"). The last one is the period (usually 1200.0 or 2/1).
// .kbm: map size, first and last key to retune, middle key (scale degree 0), reference key,
// reference frequency, the scale degree that is the formal octave, then map size entries
// (a degree, or "x" for a key that doesn't sound). Map size 0 maps keys to degrees one to one.
// Without a .kbm, middle C (60) is degree 0 and A (69) is 440 Hz.

type source = {scl: string, kbm: string}

// a scale's and a keyboard mapping's, for file dialogs
let extensions = [".scl", ".kbm"]

// A tuning as JSON, as presets and the stored state keep it: {"scl": text, "kbm": text}. A
// missing text reads as "".
let toJson = ({scl, kbm}) =>
  JSON.Object(Dict.fromArray([("scl", JSON.String(scl)), ("kbm", JSON.String(kbm))]))

let fromJson = (json: JSON.t) =>
  switch json {
  | Object(d) =>
    let text = key =>
      switch d->Dict.get(key) {
      | Some(String(s)) => s
      | _ => ""
      }
    Some({scl: text("scl"), kbm: text("kbm")})
  | _ => None
  }

type scale = {description: string, cents: array<float>} // cents of degrees 1..N (the last is the period)

type mapping = {
  size: int,
  first: int,
  last: int,
  middle: int,
  reference: int,
  frequency: float,
  octaveDegree: int,
  degrees: array<option<int>>,
}

let lines = text =>
  text
  ->String.split("\n")
  ->Array.map(l => l->String.replaceRegExp(/\r$/, ""))
  ->Array.filter(l => !String.startsWith(String.trim(l), "!"))

// the first word of a line
let word = l => l->String.trim->String.split(" ")->Array.flatMap(String.split(_, "\t"))->Array.get(0)->Option.getOr("")

let pitchOf = text => {
  let w = word(text)
  if String.includes(w, ".") {
    let c = Float.parseFloat(w)
    Float.isFinite(c) ? Some(c) : None
  } else {
    let (n, d) = switch String.split(w, "/") {
    | [n] => (Float.parseFloat(n), 1.)
    | [n, d] => (Float.parseFloat(n), Float.parseFloat(d))
    | _ => (Float.Constants.nan, 1.)
    }
    n > 0. && d > 0. ? Some(1200. * Math.log2(n / d)) : None
  }
}

let parseScale = (text): result<scale, string> => {
  let ls = lines(text)
  switch (ls[0], ls[1]) {
  | (Some(description), Some(countLine)) =>
    switch Int.fromString(word(countLine)) {
    | Some(n) if n > 0 && n <= 1024 =>
      let pitches = ls->Array.slice(~start=2)->Array.filter(l => String.trim(l) != "")
      if Array.length(pitches) < n {
        Error(`the scale has ${Int.toString(Array.length(pitches))} of its ${Int.toString(n)} notes`)
      } else {
        let cents = pitches->Array.slice(~start=0, ~end=n)->Array.map(pitchOf)
        if cents->Array.some(c => c == None) {
          Error("a pitch isn't a number of cents or a ratio")
        } else {
          Ok({description: String.trim(description), cents: cents->Array.filterMap(c => c)})
        }
      }
    | _ => Error("the note count isn't a number")
    }
  | _ => Error("not a Scala scale")
  }
}

let defaultMapping = n => {
  size: 0,
  first: 0,
  last: 127,
  middle: 60,
  reference: 69,
  frequency: 440.,
  octaveDegree: n,
  degrees: [],
}

let parseMapping = (text, n): result<mapping, string> => {
  let ls = lines(text)->Array.filter(l => String.trim(l) != "")
  let int = i => ls[i]->Option.flatMap(l => Int.fromString(word(l)))
  switch (int(0), int(1), int(2), int(3), int(4), ls[5]->Option.map(l => Float.parseFloat(word(l))), int(6)) {
  | (Some(size), Some(first), Some(last), Some(middle), Some(reference), Some(frequency), Some(octave))
    if size >= 0 && Float.isFinite(frequency) && frequency > 0. =>
    let degrees = ls->Array.slice(~start=7, ~end=7 + size)->Array.map(l => {
      let w = word(l)
      w == "x" || w == "X" ? None : Int.fromString(w)
    })
    Ok({
      size,
      first,
      last,
      middle,
      reference,
      frequency,
      octaveDegree: octave > 0 ? octave : (size > 0 ? size : n),
      degrees: Array.concat(degrees, Array.make(~length=size - Array.length(degrees), None)),
    })
  | _ => Error("not a Scala keyboard mapping")
  }
}

let floorDiv = (a, b) => Float.toInt(Math.floor(Int.toFloat(a) / Int.toFloat(b)))
let floorMod = (a, b) => a - b * floorDiv(a, b)

// The scale degree a key plays, if it plays one.
let degreeOf = (m, key) =>
  if m.size == 0 {
    Some(key - m.middle)
  } else {
    let i = key - m.middle
    m.degrees
    ->Array.get(floorMod(i, m.size))
    ->Option.flatMap(d => d)
    ->Option.map(d => d + floorDiv(i, m.size) * m.octaveDegree)
  }

let centsOf = (s, degree) => {
  let n = Array.length(s.cents)
  let period = s.cents->Array.getUnsafe(n - 1)
  let step = floorMod(degree, n)
  Int.toFloat(floorDiv(degree, n)) * period + (step == 0 ? 0. : s.cents->Array.getUnsafe(step - 1))
}

// What doesn't sound: a key outside the mapping or mapped to "x".
let unmapped = -10000.

type table = {name: string, semitones: array<float>}

// Every key's pitch in semitones from 440 Hz (unmapped keys get `unmapped`).
let table = (src: source): result<table, string> =>
  switch parseScale(src.scl == "" ? "12-tone equal temperament\n12\n" ++ Array.fromInitializer(~length=12, i => Int.toString(i + 1) ++ "00.0")->Array.join("\n") : src.scl) {
  | Error(e) => Error(e)
  | Ok(scale) =>
    let n = Array.length(scale.cents)
    let mapping = String.trim(src.kbm) == "" ? Ok(defaultMapping(n)) : parseMapping(src.kbm, n)
    switch mapping {
    | Error(e) => Error(e)
    | Ok(m) =>
      let refDegree = degreeOf(m, m.reference)->Option.getOr(m.reference - m.middle)
      let refCents = centsOf(scale, refDegree)
      let refSemis = 12. * Math.log2(m.frequency / 440.)
      Ok({
        name: scale.description == "" ? `${Int.toString(n)}-note scale` : scale.description,
        semitones: Array.fromInitializer(~length=128, key =>
          if key < m.first || key > m.last {
            unmapped
          } else {
            switch degreeOf(m, key) {
            | Some(d) => refSemis + (centsOf(scale, d) - refCents) / 100.
            | None => unmapped
            }
          }
        ),
      })
    }
  }
