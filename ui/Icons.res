// Small inline icons for list values (waveforms, filter types, voice modes, ...) and the arp
// step commands, drawn as strokes in the current text colour.
//
// An icon is drawn on a grid 16 units tall; it is looked up by parameter id and value index
// (or name, where a list grows), and a value without one simply has none.

open! Web

type mark =
  // a stroked path
  | Line(string)
  // a dashed stroked path
  | Dash(string)
  // a filled path
  | Fill(string)
  // a filled dot
  | Dot(float, float, float)
  // a small label (a digit)
  | Text(float, float, string)

// (mirrored: drawn right to left)
type icon = {width: float, marks: array<mark>, mirrored?: bool}

// The icon as an <svg>, 1em tall by default (CSS sets the size).
let render = (icon, ~cls="ic") => {
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str(cls))
  s->setAttribute("viewBox", Str(`0 0 ${Float.toString(icon.width)} 16`))
  s->setAttribute("width", Num(icon.width))
  s->setAttribute("height", Num(16.))
  let marks = s->svgEl(
    "g",
    icon.mirrored == Some(true)
      ? [("transform", Str(`matrix(-1 0 0 1 ${Float.toString(icon.width)} 0)`))]
      : [],
  )
  icon.marks->Array.forEach(mark =>
    switch mark {
    | Line(d) => marks->svgEl("path", [("d", Str(d))])->ignore
    | Dash(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("dash"))])->ignore
    | Fill(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("f"))])->ignore
    | Dot(x, y, r) =>
      marks->svgEl("circle", [("cx", Num(x)), ("cy", Num(y)), ("r", Num(r)), ("class", Str("f"))])->ignore
    | Text(x, y, text) =>
      let t = marks->svgEl("text", [("x", Num(x)), ("y", Num(y))])
      t->setTextContent(text)
    }
  )
  s
}

let wide = marks => {width: 22., marks}

//==============================================================================
// waveforms and LFO shapes: one cycle around the middle line

let sine = wide([Line("M1 8 C4.3 1.3 7.7 1.3 11 8 S17.7 14.7 21 8")])
let saw = wide([Line("M1 13 L11 3 V13 L21 3")])
let pulse = wide([Line("M1 13 V3 H11 V13 H21 V3")])
let triangle = wide([Line("M1 8 L6 3 L16 13 L21 8")])
let drawn = [Line("M1 9 C3 1.5 5.5 3 7 8 S10 14.5 12 9.5 S15.5 2 18 6 L21 5")]
let user = wide(drawn)
let userPwm = wide([...drawn, Dash("M14.5 1.5 V14.5")])
let smoothRandom = wide([Line("M1 10 C4 1.5 6 3 8 9 S12 13 14 6 S19 4 21 10")])
let steppingRandom = wide([Line("M1 10 H5 V4 H9 V12 H13 V6 H17 V11 H21")])
let flat = wide([Line("M1 8 H21")])
let fmWave = wide([Line("M1 8 C2 3 3 3 4 8 S5.5 13 6.5 8 S9 3 10.5 8 S14 13 16 8 S19.5 3 21 8")])

let waveformByName = name =>
  switch name {
  | "sine" => Some(sine)
  | "saw" => Some(saw)
  | "pulse" | "square" => Some(pulse)
  | "triangle" => Some(triangle)
  | "user" => Some(user)
  | "user pwm" => Some(userPwm)
  | "smooth random" => Some(smoothRandom)
  | "stepping random" => Some(steppingRandom)
  | _ => None
  }

//==============================================================================
// filter types: the response, low frequencies on the left, the pass band at the top

let lp1 = "M1 5 H7 C12 5 15 8 21 11.5"
let lp2 = "M1 5 H9 C13 5 14.5 9 17.5 14"
let lp4 = "M1 5 H11 C13.5 5 14 9 15 14"
let bolt = Line("M19.5 0.8 L17 4 H20 L17.5 7.2")
let peak = "M1 6 H8 C10.5 6 10.5 1.5 12 1.5 C13.5 1.5 14 10 16 14"

let phaser = notches => {
  let step = 20. / Int.toFloat(notches)
  let half = Math.min(2.2, step / 2.6)
  let f = x => Float.toFixed(x, ~digits=2)
  let d =
    Array.fromInitializer(~length=notches, i => {
      let c = 1. + (Int.toFloat(i) + 0.5) * step
      `L${f(c - half)} 5 L${f(c)} 13 L${f(c + half)} 5`
    })->Array.join(" ")
  wide([Line(`M1 5 ${d} L21 5`)])
}

let bandpass = "M1 14 C5.5 14 6 5 11 5 S16.5 14 21 14"
let narrowBandpass = "M2 14 C8 14 9 4 11 4 S14 14 20 14"
let peakBell = "M1 10 H6 C9 10 9.5 3 11 3 S13 10 16 10 H21"
let notch = "M1 5 H7 C9.5 5 10 14 11 14 S12.5 5 15 5 H21"
let comb = "M1 13 Q3 1 5 13 Q7 1 9 13 Q11 1 13 13 Q15 1 17 13 Q19 1 21 13"
let formantHumps = "M1 13 C3 13 3.5 3 5.5 3 S7.5 11 9.5 11 S11.5 5 13.5 5 S15.5 12 17 12 S19 9 21 9"
let resonantLowpass = "M8 6 H11 C13 6 13 1.5 14.5 1.5 C16 1.5 16.5 10 19 14"
let morphArrow = "M16 1.5 H21"
let morphHead = "M19.3 0 L21 1.5 L19.3 3"
let ladderMarks = [Line("M1.5 3 V13 M5.5 3 V13 M1.5 5.5 H5.5 M1.5 8 H5.5 M1.5 10.5 H5.5"), Line(resonantLowpass)]
let ladderIcon = slope => wide([Line("M1.5 3 V13 M5.5 3 V13 M1.5 5.5 H5.5 M1.5 8 H5.5 M1.5 10.5 H5.5"), Line("M8 5 H11 C13.5 5 14 8 16 11"), Text(14.5, 15.5, slope)])

let filterTypes = [
  // off: everything passes
  wide([Line("M1 5 H21"), Dash("M1 12 H21")]),
  wide([Line(lp1)]),
  wide([Line(lp2)]),
  wide([Line(lp4)]),
  {width: 22., marks: [Line(lp1)], mirrored: true},
  {width: 22., marks: [Line(lp2)], mirrored: true},
  {width: 22., marks: [Line(lp4)], mirrored: true},
  wide([Line("M1 14 C5.5 14 6 5 11 5 S16.5 14 21 14")]),
  wide([Line("M2 14 C8 14 9 4 11 4 S14 14 20 14")]),
  wide([Line("M3 14 C6.5 14 6.5 5 9 5 H13 C15.5 5 15.5 14 19 14")]),
  wide([Line("M1 5 H7 C9.5 5 10 14 11 14 S12.5 5 15 5 H21")]),
  wide([Line(lp2), bolt]),
  wide([Line(lp4), bolt]),
  phaser(2),
  phaser(4),
  phaser(7),
  // SVF, morphing low pass > band pass > high pass
  wide([Line("M1 5 H5 C9 5 10 9 12 14"), Line("M10 14 C12 9 13 5 17 5 H21"), Line("M7.5 1.5 H14.5"), Line("M12.8 0 L14.5 1.5 L12.8 3")]),
  // ladder: rails and rungs, and a resonant low pass
  wide([Line("M1.5 3 V13 M5.5 3 V13 M1.5 5.5 H5.5 M1.5 8 H5.5 M1.5 10.5 H5.5"), Line("M8 6 H11 C13 6 13 1.5 14.5 1.5 C16 1.5 16.5 10 19 14")]),
  // diode ladder: a diode, and a resonant low pass
  wide([Fill("M1 3.5 L6 8 L1 12.5 Z"), Line("M6.5 3.5 V12.5"), Line("M8 6 H11 C13 6 13 1.5 14.5 1.5 C16 1.5 16.5 10 19 14")]),
  // Sallen-Key: an op-amp, and a low pass with a soft peak
  wide([Line("M1 3 L7 8 L1 13 Z"), Line("M8 6 H11 C13.5 6 13.5 3.5 15 3.5 C16.5 3.5 17 10 19.5 14")]),
  // comb
  wide([Line("M1 13 Q3 1 5 13 Q7 1 9 13 Q11 1 13 13 Q15 1 17 13 Q19 1 21 13")]),
  // formant: vowel humps
  wide([Line(formantHumps)]),
  // bandpass 12 / 24
  wide([Line(bandpass)]),
  wide([Line(narrowBandpass)]),
  // peak 12 / 24
  wide([Line(peakBell)]),
  wide([Line("M1 10 H8 C10 10 10.2 2 11 2 S12 10 14 10 H21")]),
  // notch 12 / 24
  wide([Line(notch)]),
  wide([Line("M1 5 H8 C10 5 10.4 14 11 14 S12 5 14 5 H21")]),
  // the morphing types: one response sliding into the next
  wide([Line(lp4), Line(morphArrow), Line(morphHead)]),
  wide([Line("M1 5 H5 C8 5 9 13 11 13"), Line("M11 13 C13 13 14 5 17 5 H21"), Line(morphArrow), Line(morphHead)]),
  wide([Line("M1 14 C4 14 5 4 7.5 4 S10 14 11 14 C12 14 13 2 14.5 2 S17 14 21 14")]),
  wide([Line("M1 5 H3 C4.5 5 5 13 6 13 S7.5 5 9 5 C10 5 10.5 2 11 2 S12 5 13 5 C14.5 5 15 13 16 13 S17.5 5 19 5 H21")]),
  // MG low 6, 12, 18, 24: the ladder with its slope
  ladderIcon("6"),
  ladderIcon("12"),
  ladderIcon("18"),
  ladderIcon("24"),
  // MG dirty, acid ladder
  wide([...ladderMarks, bolt]),
  wide([Fill("M1 3.5 L6 8 L1 12.5 Z"), Line("M6.5 3.5 V12.5"), Line(resonantLowpass), bolt]),
  // French LP: multimode, German LP: the screaming peak
  wide([Line("M1 3 L7 8 L1 13 Z"), Line(resonantLowpass), Line("M10 14.5 H19")]),
  wide([Line("M1 3 L7 8 L1 13 Z"), Line("M8 7 H11 C13 7 13 0.8 14.5 0.8 C16 0.8 16.5 10 19 14"), bolt]),
  // clean drive, PZ SVF
  wide([Line(lp2), Line("M17 1.5 L19 3.5 L21 1.5")]),
  wide([Line("M1 5 H5 C9 5 10 9 12 14"), Line("M10 14 C12 9 13 5 17 5 H21"), bolt]),
  // comb + / −
  wide([Line(comb)]),
  wide([Line("M1 3 Q3 15 5 3 Q7 15 9 3 Q11 15 13 3 Q15 15 17 3 Q19 15 21 3")]),
  // flanger, + and −: notches, thinning out
  wide([Line("M1 5 L2.5 13 L4 5 L6 13 L8.5 5 L11.5 13 L15.5 5 L21 5")]),
  wide([Line("M1 5 L2.5 13 L4 5 L6 13 L8.5 5 L11.5 13 L15.5 5 L21 5"), Line("M17.5 1.5 H21 M19.25 0 V3")]),
  wide([Line("M1 5 L2.5 13 L4 5 L6 13 L8.5 5 L11.5 13 L15.5 5 L21 5"), Line("M17.5 1.5 H21")]),
  // phaser, + and −
  phaser(3),
  {...phaser(5), marks: [...phaser(5).marks, Line("M17.5 1.5 H21 M19.25 0 V3")]},
  {...phaser(5), marks: [...phaser(5).marks, Line("M17.5 1.5 H21")]},
  // formant I, II, III
  wide([Line("M1 13 C3 13 4 3 6 3 S8 11 10 11 S12 5 14 5 S17 13 21 13")]),
  wide([Line(formantHumps), Text(16.5, 6., "2")]),
  wide([Line(formantHumps), Text(16.5, 6., "3")]),
  // low EQ, band EQ, high EQ
  wide([Line("M1 4 H6 C10 4 10 10 14 10 H21")]),
  wide([Line("M1 10 H6 C9 10 9 4 11 4 S13 10 16 10 H21")]),
  {width: 22., marks: [Line("M1 4 H6 C10 4 10 10 14 10 H21")], mirrored: true},
  // ring mod: a multiplier and a sine
  wide([Line("M5 8 m-4 0 a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0 M2.2 5.2 L7.8 10.8 M7.8 5.2 L2.2 10.8"), Line("M11 8 C12.7 2.5 14.3 2.5 16 8 S19.3 13.5 21 8")]),
  // sample & hold: steps
  wide([Line("M1 12 H4 V7 H7 V10 H10 V4 H13 V8 H16 V5 H19 V11 H21")]),
  // diffusor: a transient smeared out
  wide([Line("M1 13 H3 V3 V13 H21"), Dot(7., 9., 1.), Dot(10., 11., 1.), Dot(12., 8., 1.), Dot(15., 11.5, 1.), Dot(18., 10.5, 1.)]),
  // reverb: a dying train of reflections
  wide([Line("M1 13 H21 M3 13 V3 M6 13 V6 M8.5 13 V7.5 M11 13 V9 M13.5 13 V10 M16 13 V11 M18.5 13 V12")]),
]

// Filter 2's first value follows filter 1
let sameAsFilter1 = wide([Line("M2 6 H8 M2 10 H8"), Line("M13 5 L15.5 3 V13 M12.5 13 H18.5")])

//==============================================================================
// voice modes: notes

let head = (x, y) => Fill(
  `M${Float.toString(x - 2.6)} ${Float.toString(y)} a2.6 1.9 -20 1 0 5.2 0 a2.6 1.9 -20 1 0 -5.2 0`,
)
let stem = (x, y1, y2) => Line(`M${Float.toString(x)} ${Float.toString(y1)} V${Float.toString(y2)}`)

let voiceModes = [
  // mono
  wide([head(10., 12.), stem(12.4, 11.5, 2.)]),
  // poly
  wide([head(10., 13.), head(10., 9.), head(10., 5.), stem(12.4, 12.5, 1.)]),
  // mono legato: two notes under a slur
  wide([head(5., 12.), stem(7.4, 11.5, 4.), head(15., 9.), stem(17.4, 8.5, 1.), Line("M4 15 Q11 18.5 16 12.5")]),
]

//==============================================================================
// oscillator mix

let op = (x, digit) => [Line(`M${Float.toString(x - 3.6)} 8 a3.6 3.6 0 1 0 7.2 0 a3.6 3.6 0 1 0 -7.2 0`), Text(x, 10.4, digit)]

let oscMix = [
  // normal: summed
  wide([Line("M5 8 a6 6 0 1 0 12 0 a6 6 0 1 0 -12 0"), Line("M11 4.5 V11.5 M7.5 8 H14.5")]),
  // hard sync: cycles cut short
  wide([Line("M1 12 C3 3 6 2 8 6 V12 C10 3 13 2 15 6 V12 C17 3 20 2 21 4")]),
  // FM 1 > 2
  wide([...op(4.5, "1"), ...op(17.5, "2"), Line("M8.5 8 H12.5 M10.8 6 L12.8 8 L10.8 10")]),
  // PM 2 > 1
  wide([...op(4.5, "1"), ...op(17.5, "2"), Line("M13.5 8 H9.5 M11.2 6 L9.2 8 L11.2 10")]),
  // PM 1 feedback
  wide([...op(7., "1"), Line("M10.6 8 H14 V2 H7 V4"), Line("M5.5 2.8 L7 4.4 L8.5 2.8")]),
  // ring 1 × 2
  wide([...op(4.5, "1"), ...op(17.5, "2"), Line("M9.3 6.3 L12.7 9.7 M12.7 6.3 L9.3 9.7")]),
  // AM 2 > 1: a wave under an envelope
  wide([Line("M1 8 C2 4 3 4 4 8 S6 14 7 8 S9.5 1 11 8 S13.5 15 15 8 S17 4.5 18 8 S20 10 21 8"), Dash("M1 5 Q11 -2 21 6")]),
]

//==============================================================================
// distortion: transfer curves, input across, output up

let distortion = [
  wide([Line("M3 14 L19 2")]),
  wide([Line("M2 13 H6 L16 3 H20")]),
  wide([Line("M2 13 C6.5 13 8 11 11 8 S15.5 3 20 3")]),
  wide([Line("M1 10 C3 15 5.5 15 8 8 S13 1 15 6 S18.5 13 21 7")]),
  wide([Line("M2 13 C6.5 13 8 11 11 8 L19 2")]),
]

//==============================================================================
// arpeggiator modes

let square = (x, y) => Fill(`M${Float.toString(x)} ${Float.toString(y)} h3 v2.4 h-3 Z`)

let arpModes = [
  wide([Line("M3 8 H19")]),
  // pattern: notes one after another
  wide([square(2., 11.), square(7., 8.), square(12., 5.), square(17., 8.)]),
  // pattern, global subsequence: the same, carried on
  wide([square(2., 11.), square(7., 8.), square(12., 5.), Dash("M17 9 H21")]),
  // chord pattern: chords one after another
  wide([square(2., 11.), square(2., 7.), square(9.5, 9.), square(9.5, 5.), square(17., 11.), square(17., 7.)]),
  // chord
  wide([square(9.5, 12.), square(9.5, 8.), square(9.5, 4.)]),
  // transposed chords
  wide([square(4., 12.), square(4., 8.), square(4., 4.), Line("M15 14 V3 M11.5 6.5 L15 3 L18.5 6.5")]),
]

//==============================================================================
// filter doubling

let filterBox = (x, y) => Line(`M${Float.toString(x)} ${Float.toString(y)} h5 v4 h-5 Z`)

let filterDouble = [
  wide([Line("M1 8 H8.5 M13.5 8 H21"), filterBox(8.5, 6.)]),
  wide([Line("M1 8 H4 M18 8 H21 M4 3.5 V12.5 M18 3.5 V12.5 M4 3.5 H8.5 M13.5 3.5 H18 M4 12.5 H8.5 M13.5 12.5 H18"), filterBox(8.5, 1.5), filterBox(8.5, 10.5)]),
  wide([Line("M1 8 H3 M8 8 H14 M19 8 H21"), filterBox(3., 6.), filterBox(14., 6.)]),
]

//==============================================================================
// lookup

let byIndex = icons => (index, _) => icons[index]

// The parameters with icons, and how each finds the icon of a value from its index and its
// lower-case name (less " hq").
let lookup = id =>
  switch id {
  | "O1_Waveform" | "O2_Waveform" | "LFO_1_Shape" | "LFO_2_Shape" =>
    Some((_, name) => waveformByName(name))
  | "Filter" => Some(filterTypes->byIndex)
  | id if FilterTypes.isFxType(id) => Some(filterTypes->byIndex)
  | "Filter2" => Some((index, _) => index == 0 ? Some(sameAsFilter1) : filterTypes[index])
  | "PolyMode" => Some(voiceModes->byIndex)
  | "OscMix" => Some(oscMix->byIndex)
  | "Sat_Type" => Some(distortion->byIndex)
  | "Arp_Mode" => Some(arpModes->byIndex)
  | "F_Double" => Some(filterDouble->byIndex)
  | "C_Mode" =>
    Some(
      (_, name) =>
        switch name {
        | "off" => Some(flat)
        | "sine" => Some(sine)
        | "ramp" => Some(saw)
        | "fm" => Some(fmWave)
        | "irregular" => Some(smoothRandom)
        | _ => None
        },
    )
  | _ => None
  }

// Whether any value of the parameter has an icon.
let has = id => lookup(id)->Option.isSome

// The icon for value `index` (named `name`) of a list parameter, and the text to show beside
// it (the name, less anything the icon shows).
let forValue = (id, index, name) => {
  let lower = String.toLowerCase(name)
  let hq = String.endsWith(lower, " hq")
  let base = hq ? String.slice(lower, ~start=0, ~end=String.length(lower) - 3) : lower
  lookup(id)
  ->Option.flatMap(find => find(index, base))
  ->Option.map(icon => {
    let wrap = el("span", ~cls="icw")
    wrap->appendChild(render(icon))
    if hq {
      el("b", ~cls="hq", ~text="HQ", ~parent=wrap)->ignore
    }
    (wrap, hq ? String.slice(name, ~start=0, ~end=String.length(name) - 3) : name)
  })
}

//==============================================================================
// arpeggiator step commands, in the synth's order; some are two marks side by side

let narrow = marks => {width: 14., marks}
let up = [Line("M7 14 V2 M2.5 6.5 L7 2 L11.5 6.5")]
let down = [Line("M7 2 V14 M2.5 9.5 L7 14 L11.5 9.5")]
let back = [Line("M13 14 V7 A4.5 4.5 0 0 0 4 7 V12 M1.5 9.5 L4 12 L6.5 9.5")]

let arpSteps = [
  [narrow([Dot(7., 8., 1.8)])],
  [narrow(up)],
  [narrow([Line("M7 14 V4.5 M3 8.5 L7 4.5 L11 8.5 M2 1.5 H12")])],
  [narrow(down)],
  [narrow([Line("M7 2 V11.5 M3 7.5 L7 11.5 L11 7.5 M2 14.5 H12")])],
  [narrow([Line("M7 2 V14 M3.5 5.5 L7 2 L10.5 5.5 M3.5 10.5 L7 14 L10.5 10.5")])],
  [narrow([Line("M7 4 V12 M4 7 L7 4 L10 7 M4 9 L7 12 L10 9 M2 1 H12 M2 15 H12")])],
  [narrow([Line("M2.5 5.5 H11.5 M2.5 10.5 H11.5")])],
  [narrow([Line("M1 8 H13 M8.5 3.5 L13 8 L8.5 12.5")])],
  [{width: 16., marks: [Line("M1 8 H15 M4.5 4.5 L1 8 L4.5 11.5 M11.5 4.5 L15 8 L11.5 11.5")]}],
  [{width: 16., marks: back}],
  [{width: 16., marks: back}, narrow(up)],
  [{width: 16., marks: back}, narrow(down)],
  [narrow([Line("M2 2.5 H12 M7 2.5 V14")])],
  [narrow([Line("M2 13.5 H12 M7 13.5 V2")])],
  [narrow([Line("M3.8 5.5 A3.2 3.2 0 1 1 8.6 8.3 C7.6 8.9 7 9.6 7 11"), Dot(7., 14., 1.2)])],
]

// The step command's icon, bold, for the pattern cells and their menu.
let arpStep = (index, ~cls="ic bold") =>
  arpSteps[index]->Option.map(parts => {
    let wrap = el("span", ~cls="icw")
    parts->Array.forEach(icon => wrap->appendChild(render(icon, ~cls)))
    wrap
  })
