// Small inline icons for list values (waveforms, filter types, voice modes, ...) and the arp
// step commands, drawn as strokes in the current text colour.
//
// An icon is drawn on a grid 16 units tall; it is looked up by value list (ValueList) and value
// index (or name, where a list grows), and a value without one simply has none.

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

// (the Oat aliasing waves look like the others)
let waveformByName = name =>
  switch name {
  | "sine" => Some(sine)
  | "saw" | "oat saw" => Some(saw)
  | "saw down" => Some({...saw, mirrored: true})
  | "pulse" | "square" | "oat pulse" => Some(pulse)
  | "triangle" | "oat triangle" => Some(triangle)
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
// distortion: Oatmeal's types as transfer curves, input across, output up; the models
// (DistTypes) as pictures of what they are

let circle = (x, y, r) => {
  let f = Float.toString
  `M${f(x -. r)} ${f(y)} a${f(r)} ${f(r)} 0 1 0 ${f(2. *. r)} 0 a${f(r)} ${f(r)} 0 1 0 ${f(-2. *. r)} 0`
}

let distortion = [
  wide([Line("M3 14 L19 2")]),
  wide([Line("M2 13 H6 L16 3 H20")]),
  wide([Line("M2 13 C6.5 13 8 11 11 8 S15.5 3 20 3")]),
  wide([Line("M1 10 C3 15 5.5 15 8 8 S13 1 15 6 S18.5 13 21 7")]),
  wide([Line("M2 13 C6.5 13 8 11 11 8 L19 2")]),
  // custom shape: a drawn curve and its points
  wide([Line("M2 13 C5 13 6 7 10 8 S15 3 20 3"), Dot(2., 13., 1.3), Dot(10., 8., 1.3), Dot(20., 3., 1.3)]),
  // tube: the glass, the filament and the pins
  wide([Line("M7.5 13.5 V6 A3.5 3.5 0 0 1 14.5 6 V13.5 Z"), Line("M9.5 11.5 V8.5 L11 7 L12.5 8.5 V11.5"), Line("M9 13.5 V15.5 M13 13.5 V15.5")]),
  // tape: two reels and the tape between them
  wide([Line(circle(6., 6.5, 3.5)), Line(circle(16., 6.5, 3.5)), Dot(6., 6.5, 1.), Dot(16., 6.5, 1.), Line("M2.5 6.5 V13.5 H19.5 V6.5")]),
  // saturate: a sine pushed square
  wide([Line("M1 8 C1.5 3.5 3.5 3 6 3 S10.5 3.5 11 8 S12.5 13 16 13 S20.5 12.5 21 8")]),
  // mixer drive: two faders, one pushed up
  wide([Line("M6 1.5 V14.5 M16 1.5 V14.5"), Fill("M3.5 9 h5 v3 h-5 Z"), Fill("M13.5 2.5 h5 v3 h-5 Z")]),
  // 7-stage clip: clips in a row
  wide([Line("M1 12.5 H2.5 L4.5 3.5 H6 M8 12.5 H9.5 L11.5 3.5 H13 M15 12.5 H16.5 L18.5 3.5 H20")]),
  // multiband: the lows and the highs distorted apart
  wide([Line("M1 12 C3 4 6 4 8.5 12"), Dash("M11 1.5 V14.5"), Line("M13 12 L15 4 L17 12 L19 4 L21 12")]),
  // wavefold: a wave folding back at its peaks
  wide([Line("M1 3 L2.5 5.5 L4 3 L8 13 L9.5 10.5 L11 13 L15 3 L16.5 5.5 L18 3 L21 10.5")]),
  // bass amp: a cabinet with one big speaker
  wide([Line("M2.5 1.5 H19.5 V14.5 H2.5 Z"), Line(circle(11., 8., 4.3)), Dot(11., 8., 1.3)]),
  // guitar amp: the head's knobs over a 4x12
  wide([Line("M2.5 1.5 H19.5 V14.5 H2.5 Z M2.5 5 H19.5"), Dot(6., 3.3, 0.8), Dot(9., 3.3, 0.8), Dot(12., 3.3, 0.8), Line(circle(7.5, 9.8, 2.6)), Line(circle(14.5, 9.8, 2.6))]),
  // bitcrush: a wave in coarse steps
  wide([Line("M1 13 H4 V10 H7 V7 H10 V4 H13 V7 H16 V10 H19 V13 H21")]),
  // lo-fi sampler: held samples
  wide([Line("M2 11 H6 V5 H10 V3.5 H14 V9 H18 V12 H21"), Dot(2., 11., 1.2), Dot(6., 5., 1.2), Dot(10., 3.5, 1.2), Dot(14., 9., 1.2), Dot(18., 12., 1.2)]),
]

//==============================================================================
// the rack's effects, by FxRack.key, for the add menu

let rackKind = key =>
  switch key {
  | "distortion" => Some(wide([Line("M1 8 C2 5 3 3 5 3 H7.5 C9 3 10 5 11 8 S13 13 14.5 13 H17 C19 13 20 11 21 8")]))
  | "chorus" =>
    Some(wide([Line("M1 8 C4.3 1.3 7.7 1.3 11 8 S17.7 14.7 21 8"), Dash("M3 8 C6.3 3.3 9.7 3.3 13 8 S19 12 21 10")]))
  | "flanger" => Some(wide([Line("M1 5 L2.5 13 L4 5 L6 13 L8.5 5 L11.5 13 L15.5 5 L21 5")]))
  | "phaser" => Some(phaser(4))
  | "bode" => Some(wide([Line("M2 14 V5 M5.5 14 V8 M9 14 V10"), Line("M12 7 H20 M17.5 4.5 L20 7 L17.5 9.5")]))
  | "delay" => Some(wide([Line("M1 13.5 H21 M3 13.5 V3 M8.5 13.5 V6.5 M14 13.5 V9 M19.5 13.5 V11")]))
  | "reverb" => Some(wide([Line("M1 13 H21 M3 13 V3 M6 13 V6 M8.5 13 V7.5 M11 13 V9 M13.5 13 V10 M16 13 V11 M18.5 13 V12")]))
  | "space" => Some(wide([Line("M2 14.5 V6 L11 2 L20 6 V14.5"), Line("M7 14.5 A4 4 0 0 1 15 14.5 M4.5 14.5 A6.5 6.5 0 0 1 17.5 14.5")]))
  | "ambience" => Some(wide([Line("M4 3.5 H18 V13.5 H4 Z"), Dot(8.5, 9.5, 1.3), Line("M8.5 9.5 L13 6 L16 9 M8.5 9.5 L14 11.5")]))
  // a cabinet: a speaker in its box
  | "cabinet" => Some(wide([Line("M3.5 1.5 H18.5 V14.5 H3.5 Z"), Line(circle(11., 8., 4.3)), Dot(11., 8., 1.3)]))
  | "convolve" => Some(wide([Line("M1 13 H21 M4 13 V2.5"), Line("M6 13 C7.5 13 7.5 8 9 9.5 S11.5 12 13 11 S16.5 12.5 20 12.5")]))
  | "eq" => Some(wide([Line("M1 10 H4.5 C6.5 10 7 3.5 8.5 3.5 S10.5 10 12.5 10 C15.5 10 15.5 5.5 21 5.5")]))
  | "filter" => Some(wide([Line(lp2)]))
  | "air" => Some(wide([Line("M1 11.5 H9 C12.5 11.5 12.5 6 16 6 H21"), Line("M17.5 0.5 V4 M15.75 2.25 H19.25"), Dot(13., 2.5, 0.8), Dot(20.5, 2., 0.8)]))
  | "compressor" => Some(wide([Line("M2 14.5 L10.5 6 C13 3.5 16 3 20 2.6"), Dash("M10.5 6 L15 1.5")]))
  | "utility" => Some(wide([Line("M2 3.5 H20 M2 8 H20 M2 12.5 H20"), Fill("M12.5 1.5 h3 v4 h-3 Z"), Fill("M5 6 h3 v4 h-3 Z"), Fill("M9.5 10.5 h3 v4 h-3 Z")]))
  // the resonator: a struck note ringing away
  | "resonator" =>
    Some(wide([Line("M1 8 Q2.5 -3 4 8 Q5.5 17 7 8 Q8.5 1.2 10 8 Q11.5 12.8 13 8 Q14.5 4.8 16 8 Q17.5 9.8 19 8 L21 8")]))
  // the octaver: a note's cycles (dashed) and the one cycle of the octave below spanning two
  | "octaver" => Some(wide([Dash("M1 6 Q3.5 1 6 6 T11 6 T16 6 T21 6"), Line("M1 10 Q6 0.5 11 10 T21 10")]))
  | _ => None
  }

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
// noise types (ValueList.NoiseType, in its order): the colours as a jittery spectrum along its
// tilt (low frequencies on the left), the others as what they look like in time

let noiseJitter = [0., -2.2, 1.6, -0.8, 2.4, -1.9, 0.6, -2.5, 1.9, -1., 2.2, -1.6, 0.9, -2.3, 1.4, -0.6, 2.5, -1.8, 1.1, -2., 0.4]

// a jagged line from height y0 on the left to y1 on the right
let noisy = (y0, y1, ~scale=1.) => {
  let f = x => Float.toFixed(x, ~digits=2)
  let points = noiseJitter->Array.mapWithIndex((j, i) => {
    let x = 1. +. Int.toFloat(i)
    `${f(x)} ${f(y0 +. (y1 -. y0) *. (x -. 1.) /. 20. +. j *. scale)}`
  })
  wide([Line("M" ++ points->Array.join(" L"))])
}

// bits held one unit each, repeated: a wave from 1 to 21 between the heights 12 (0) and 4 (1)
let bitsPath = (bits, repeats) => {
  let all = Array.fromInitializer(~length=repeats, _ => bits)->Array.flat
  let step = 20. /. Int.toFloat(Array.length(all))
  let f = x => Float.toFixed(x, ~digits=2)
  let y = b => b == 1 ? "4" : "12"
  "M1 " ++
  y(all->Array.getUnsafe(0)) ++
  all
  ->Array.mapWithIndex((b, i) => ` V${y(b)} H${f(1. +. step *. Int.toFloat(i + 1))}`)
  ->Array.join("")
}

let noiseTypes = [
  noisy(8., 8., ~scale=0.55),
  noisy(4.5, 11.5, ~scale=0.45),
  noisy(1.5, 14.5, ~scale=0.45),
  noisy(11.5, 4.5, ~scale=0.45),
  noisy(14.5, 1.5, ~scale=0.45),
  // crackle: sparse clicks on silence
  wide([Line("M1 8 H4 L4.6 2.5 L5.2 12 L5.8 8 H10 L10.5 10.5 L11 6.5 L11.5 8 H15 L15.6 1.5 L16.2 14.5 L16.8 8 H21")]),
  // digital: a shift register's bits, held
  wide([Line(bitsPath([0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1], 1))]),
  // metallic: a short run of bits, over and over
  wide([Line(bitsPath([1, 0, 1, 1, 0, 0], 2))]),
  // sample: a recording's waveform
  wide([Line("M2 6.5 V9.5 M4 4 V12 M6 6 V10 M8 2.5 V13.5 M10 5 V11 M12 3.5 V12.5 M14 6.5 V9.5 M16 4.5 V11.5 M18 6 V10 M20 7 V9")]),
]

//==============================================================================
// the settings button: a solid gear with a hole (wound the other way, so it stays open)

let gear = {width: 16., marks: [Fill("M6.55 2.69L6.69 0.51H9.31L9.45 2.69A5.5 5.5 0 0 1 10.73 3.22L12.37 1.78L14.22 3.63L12.78 5.27A5.5 5.5 0 0 1 13.31 6.55L15.49 6.69V9.31L13.31 9.45A5.5 5.5 0 0 1 12.78 10.73L14.22 12.37L12.37 14.22L10.73 12.78A5.5 5.5 0 0 1 9.45 13.31L9.31 15.49H6.69L6.55 13.31A5.5 5.5 0 0 1 5.27 12.78L3.63 14.22L1.78 12.37L3.22 10.73A5.5 5.5 0 0 1 2.69 9.45L0.51 9.31V6.69L2.69 6.55A5.5 5.5 0 0 1 3.22 5.27L1.78 3.63L3.63 1.78L5.27 3.22A5.5 5.5 0 0 1 6.55 2.69ZM10.3 8A2.3 2.3 0 1 0 5.7 8A2.3 2.3 0 1 0 10.3 8Z")]}

//==============================================================================
// the "draw" buttons (the shapes editor): a pencil, its point at the bottom left
let pencil = {
  width: 15.,
  marks: [
    Line("M2 14 L3.5 9.5 L10.5 2.5 L13.5 5.5 L6.5 12.5 Z"),
    Line("M3.5 9.5 L6.5 12.5"),
    Line("M9 4 L12 7"),
  ],
}

//==============================================================================
// lookup

let byIndex = icons => (index, _) => icons[index]

let chorusModeByName = name =>
  switch name {
  | "off" => Some(flat)
  | "sine" => Some(sine)
  | "ramp" => Some(saw)
  | "fm" => Some(fmWave)
  | "irregular" => Some(smoothRandom)
  | _ => None
  }

// The value lists with icons, and how each finds the icon of a value from its index and its
// lower-case name.
let ofList = (list: ValueList.t) =>
  switch list {
  | Waveform | LfoShape | Lfo3Shape => Some((_, name) => waveformByName(name))
  | FilterType | FxFilterType => Some(filterTypes->byIndex)
  | Filter2Type => Some((index, _) => index == 0 ? Some(sameAsFilter1) : filterTypes[index])
  | FilterDouble => Some(filterDouble->byIndex)
  | DistType => Some(distortion->byIndex)
  | VoiceMode => Some(voiceModes->byIndex)
  | OscMix => Some(oscMix->byIndex)
  | ArpMode => Some(arpModes->byIndex)
  | ChorusMode => Some((_, name) => chorusModeByName(name))
  | NoiseType => Some(noiseTypes->byIndex)
  | DistMode | TouchMode | GlideMode | DelayReverse | LfoUnit | DelayUnit | ArpUnit => None
  }

// How a parameter's values find their icons, if they have any.
let forList = (list: option<ValueList.t>) => list->Option.flatMap(ofList)

// The icon for value `index` (named `name`) of a list (as forList finds it), and the text to
// show beside it.
let forValue = (find, index, name) =>
  find(index, String.toLowerCase(name))->Option.map(icon => {
    let wrap = el("span", ~cls="icw")
    wrap->appendChild(render(icon))
    (wrap, name)
  })

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
