// Parameter definitions for the view, built on the reverse-engineered parameter table
// (OatmealParams, verified against Oatmeal.dll).
//
// Endpoint values are Oatmeal's internal values, except pulse width, which the patch takes
// as a 0..1 fraction (Oatmeal stores it as a 32-bit phase).

let filterNames = [
  "off",
  "1P lowpass",
  "2P lowpass",
  "4P lowpass",
  "1P highpass",
  "2P highpass",
  "4P highpass",
  "2P wide bandpass",
  "2P narrow bandpass",
  "4P bandpass",
  "2P notch",
  "nonlinear 2P lowpass",
  "nonlinear 4P lowpass",
  "phaser, 4 stages",
  "phaser, 12 stages",
  "phaser, 36 stages",
]

// Compact names for the narrow value fields (the full names appear in menus and the status bar).
let shortNamesFor = id =>
  switch id {
  | "Filter" =>
    Some([
      "off",
      "1P LP",
      "2P LP",
      "4P LP",
      "1P HP",
      "2P HP",
      "4P HP",
      "2P BP wide",
      "2P BP narrow",
      "4P BP",
      "2P notch",
      "2P LP drive",
      "4P LP drive",
      "phaser 4",
      "phaser 12",
      "phaser 36",
    ])
  | "Filter2" =>
    Some([
      "as filter 1",
      "1P LP",
      "2P LP",
      "4P LP",
      "1P HP",
      "2P HP",
      "4P HP",
      "2P BP wide",
      "2P BP narrow",
      "4P BP",
      "2P notch",
      "2P LP drive",
      "4P LP drive",
      "phaser 4",
      "phaser 12",
      "phaser 36",
    ])
  | "Sat_Mode" => Some(["global", "voice, post-filter", "voice, pre-filter", "double"])
  | "PolyMode" => Some(["mono", "poly", "mono legato"])
  | "AftertouchMode" => Some(["ignore", "channel", "poly"])
  | "OscMix" => Some(["normal", "hardsync", "FM 1 > 2"])
  | "GlideMode" =>
    Some(["P", "P·o", "P/o", "P·(o+1/o)", "P·(1+o)", "P·(1+1/o)", "P·(1+o+1/o)"])
  | "Arp_Mode" =>
    Some(["off", "pattern", "global subseq", "chord pattern", "chord", "transp. chords"])
  | "D_ReverseL" | "D_ReverseR" => Some(["normal", "rev. out", "rev. fb"])
  | _ => None
  }

let unitShort = word =>
  switch word {
  | "semitones" | "semitone" => "st"
  | "octaves" | "octave" => "oct"
  | "seconds" | "sec" => "s"
  | word => word
  }

// "1392.50 Hz (*3.1648)" -> "1392.5 Hz"; "-6.02 dB (50.00 %)" -> "-6.02 dB"; "0.00 semitones" -> "0.00 st"
let compact = s => {
  let s = switch String.indexOf(s, " (") {
  | i if i > 0 => String.slice(s, ~start=0, ~end=i)
  | _ => s
  }
  s
  ->String.trim
  ->String.replaceRegExpBy0Unsafe(/[a-z]+/g, (~match, ~offset as _, ~input as _) =>
    unitShort(match)
  )
  // keep at most five significant digits so the readout fits its field
  ->String.replaceRegExpBy3Unsafe(/^(-?)(\d+)\.(\d+)/, (
    ~match,
    ~group1 as sign,
    ~group2 as whole,
    ~group3 as fraction,
    ~offset as _,
    ~input as _,
  ) => {
    let digits = String.length(whole)
    if digits >= 5 {
      sign ++ whole
    } else if digits + String.length(fraction) > 5 {
      sign ++ whole ++ "." ++ String.slice(fraction, ~start=0, ~end=5 - digits)
    } else {
      match
    }
  })
}

let firstNumber = s =>
  switch /-?\d+(\.\d+)?/->RegExp.exec(String.replace(s, "-inf", "-1e9")) {
  | Some(m) => Float.parseFloat(RegExp.Result.fullMatch(m))
  | None => Float.Constants.nan
  }

type t = {
  id: string,
  index: int,
  name: string,
  kind: Fields.kind,
  isInt: bool,
  // value names for menus and the status bar
  names: option<array<string>>,
  // compact value names for the narrow value fields
  shortNames: option<array<string>>,
  init: float,
  min: float,
  max: float,
  bipolar: bool,
  clamp: float => float,
  toNorm: float => float,
  fromNorm: float => float,
  // the original's full status-bar text
  longText: float => string,
  valueText: float => string,
  shortText: float => string,
  // Typed values are read in display units.
  parse: string => option<float>,
}

let pw32 = 4294967296.

// A Porridge parameter (PorridgeParams): plain linear knobs and lists.
let porridgeDef = (index, spec: PorridgeParams.spec) =>
  switch spec.kind {
  | Float({min, max, init, text}) =>
    let clamp = x => Float.isFinite(x) ? Math.max(min, Math.min(max, x)) : init
    {
      id: spec.id,
      index,
      name: spec.name,
      kind: F32,
      isInt: false,
      names: None,
      shortNames: None,
      init,
      min,
      max,
      bipolar: min < 0. && max > 0.,
      clamp,
      toNorm: x => (x - min) / (max - min),
      fromNorm: v => min + (max - min) * v,
      longText: x => `${spec.name}: ${text(x)}`,
      valueText: text,
      shortText: x => compact(text(x)),
      parse: s => {
        let x = Float.parseFloat(s)
        Float.isFinite(x) ? Some(clamp(String.includes(text(init), "%") ? x / 100. : x)) : None
      },
    }
  | Choice({names, init}) =>
    let last = Int.toFloat(Array.length(names) - 1)
    let clamp = x => Float.isFinite(x) ? Math.max(0., Math.min(last, Math.round(x))) : Int.toFloat(init)
    let valueText = x => names[Float.toInt(clamp(x))]->Option.getOr("")
    {
      id: spec.id,
      index,
      name: spec.name,
      kind: I32,
      isInt: true,
      names: Some(names),
      shortNames: None,
      init: Int.toFloat(init),
      min: 0.,
      max: last,
      bipolar: false,
      clamp,
      toNorm: x => last > 0. ? x / last : 0.,
      fromNorm: v => Math.round(v * last),
      longText: x => `${spec.name}: ${valueText(x)}`,
      valueText,
      shortText: valueText,
      parse: s =>
        names
        ->Array.findIndex(n => String.toLowerCase(n) == String.toLowerCase(String.trim(s)))
        ->(i => i >= 0 ? Some(Int.toFloat(i)) : None),
    }
  }

// context supplies the program that status texts read other fields from (octave size,
// tuning, breakpoint, targets...); Init values without one.
let makeDefs = (~context=() => None) => {
  let init = OatmealFormat.makeDefaultProgram("Init")

  Fields.all->Array.map(field => {
    let {index, id, name, kind} = field
    let p = OatmealParams.param(index)
    let isPw = kind == Pw
    let isInt = Fields.isInt(field)
    let toF = x => isPw ? ByteView.toUint32(Math.round(x * pw32)) : x
    let fromF = x => isPw ? x / pw32 : x

    let names = switch kind {
    | Filter1 => Some(filterNames)
    | Filter2 => Some(["same as filter 1", ...filterNames->Array.slice(~start=1)])
    | _ => p.labels
    }->Option.map(names =>
      switch p.states {
      | Some(states) if Array.length(names) < states =>
        let n = Array.length(names)
        Array.concat(names, Array.fromInitializer(~length=states - n, i => Int.toString(n + i)))
      | _ => names
      }
    )

    let (lo, hi) = switch kind {
    | Filter1 | Filter2 => (0., 15.)
    | _ => (fromF(Math.min(p.min, p.max)), fromF(Math.max(p.min, p.max)))
    }
    let initValue = fromF(OatmealParams.readInternal(init, index))
    let min = isPw ? 0. : lo
    let max = isPw ? 1. : hi

    let clamp = x => {
      let x = Float.isFinite(x) ? x : initValue
      isInt
        ? Math.max(Math.round(min), Math.min(Math.round(max), Math.round(x)))
        : Math.max(min, Math.min(max, x))
    }
    let fromNorm = v => fromF(OatmealParams.toInternal(index, Math.max(0., Math.min(1., v))))
    let valueText = x => OatmealParams.displayText(index, toF(x), ~prog=?context())

    // Find the knob position whose displayed number matches.
    let parse = text => {
      let want = Float.parseFloat(text)
      let at = v => firstNumber(valueText(fromNorm(v)))
      let (fa, fb) = (at(0.), at(1.))
      if !Float.isFinite(want) || !Float.isFinite(fa) || !Float.isFinite(fb) || fa == fb {
        None
      } else {
        let up = fb > fa
        if up ? want <= fa : want >= fa {
          Some(fromNorm(0.))
        } else if up ? want >= fb : want <= fb {
          Some(fromNorm(1.))
        } else {
          let rec bisect = (k, a: float, b) =>
            if k == 40 {
              (a + b) / 2.
            } else {
              let m = (a + b) / 2.
              let fm = at(m)
              Float.isFinite(fm) && (up ? fm < want : fm > want)
                ? bisect(k + 1, m, b)
                : bisect(k + 1, a, m)
            }
          Some(fromNorm(bisect(0, 0., 1.)))
        }
      }
    }

    {
      id,
      index,
      name,
      kind,
      isInt,
      names: names->Option.filter(names => !(isInt && Array.length(names) > 40)),
      shortNames: shortNamesFor(id),
      init: initValue,
      min,
      max,
      bipolar: names == None && lo < 0. && hi > 0.,
      clamp,
      toNorm: x => OatmealParams.toNormalized(index, toF(x)),
      fromNorm,
      longText: x =>
        OatmealParams.statusText(
          index,
          OatmealParams.textNormalized(index, toF(x)),
          ~prog=?context(),
        ),
      valueText,
      shortText: x => compact(valueText(x)),
      parse,
    }
  })->Array.concat(
    PorridgeParams.all->Array.mapWithIndex((spec, i) =>
      porridgeDef(OatmealParams.paramCount + i, spec)
    ),
  )
}
