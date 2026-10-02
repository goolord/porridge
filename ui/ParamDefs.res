// Parameter definitions for the view, built on the reverse-engineered parameter table
// (OatmealParams, verified against Oatmeal.dll).
//
// Endpoint values are Oatmeal's internal values, except pulse width, which the patch takes
// as a 0..1 fraction (Oatmeal stores it as a 32-bit phase).

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

// The index of value name s, ignoring case.
let nameIndex = (names, s) =>
  names
  ->Array.findIndex(n => String.toLowerCase(n) == String.toLowerCase(String.trim(s)))
  ->(i => i >= 0 ? Some(Int.toFloat(i)) : None)

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
  // the value list it shows, if it's one of those (a rack copy's is its first's)
  list: option<ValueList.t>,
  // value names for menus and the status bar
  names: option<array<string>>,
  // compact value names for the narrow value fields
  shortNames: option<array<string>>,
  init: float,
  min: float,
  max: float,
  bipolar: bool,
  clamp: float => float,
  // what a loaded program's value becomes: clamped, except that Oatmeal's float parameters
  // keep what the program holds, which older versions of Oatmeal wrote outside some knobs'
  // ranges (an F envspeed of 8.78) and which Oatmeal plays as it is
  load: float => float,
  toNorm: float => float,
  fromNorm: float => float,
  // the original's full status-bar text
  longText: float => string,
  valueText: float => string,
  shortText: float => string,
  // Typed values are read in display units.
  parse: string => option<float>,
  // the parameters its readouts also depend on (octave size, tuning, breakpoint, targets...)
  dependsOn: array<string>,
}

// A Porridge parameter (PorridgeParams): plain linear knobs and lists, or a copy of an Oatmeal
// parameter (`like` finds it).
let porridgeDef = (index, spec: PorridgeParams.spec, ~like: string => t) =>
  switch spec.kind {
  | Like(first) | LikeWithDefault(first, _) =>
    let d = like(first)
    {
      ...d,
      id: spec.id,
      index,
      name: spec.name,
      init: switch spec.kind {
      | LikeWithDefault(_, init) => d.clamp(Math.fround(init))
      | _ => d.init
      },
      longText: x => `${spec.name}: ${d.valueText(x)}`,
    }
  | Float({min, max, init, text, ?read}) =>
    // (a float32, as presets and the patch keep it)
    let init = Math.fround(init)
    let clamp = x => Float.isFinite(x) ? Math.max(min, Math.min(max, x)) : init
    {
      id: spec.id,
      index,
      name: spec.name,
      kind: F32,
      isInt: false,
      list: None,
      names: None,
      shortNames: None,
      init,
      min,
      max,
      bipolar: min < 0. && max > 0.,
      dependsOn: [],
      clamp,
      load: clamp,
      toNorm: x => (x - min) / (max - min),
      fromNorm: v => min + (max - min) * v,
      longText: x => `${spec.name}: ${text(x)}`,
      valueText: text,
      shortText: x => compact(text(x)),
      parse: s =>
        switch read {
        | Some(read) => read(s)->Option.map(clamp)
        | None =>
          let x = Float.parseFloat(s)
          Float.isFinite(x) ? Some(clamp(String.includes(text(init), "%") ? x / 100. : x)) : None
        },
    }
  | Choice({names, init, ?list}) =>
    let last = Int.toFloat(Array.length(names) - 1)
    let clamp = x => Float.isFinite(x) ? Math.max(0., Math.min(last, Math.round(x))) : Int.toFloat(init)
    let valueText = x => names[Float.toInt(clamp(x))]->Option.getOr("")
    {
      id: spec.id,
      index,
      name: spec.name,
      kind: I32,
      isInt: true,
      list,
      names: Some(names),
      shortNames: list->Option.flatMap(l => ValueList.info(l).short),
      init: Int.toFloat(init),
      min: 0.,
      max: last,
      bipolar: false,
      dependsOn: [],
      clamp,
      load: clamp,
      toNorm: x => last > 0. ? x / last : 0.,
      fromNorm: v => Math.round(v * last),
      longText: x => `${spec.name}: ${valueText(x)}`,
      valueText,
      shortText: valueText,
      parse: nameIndex(names, _),
    }
  }

// A list with Porridge's values after Oatmeal's: Oatmeal's values read as before, the new
// ones by name, and the knob steps through all of them evenly.
let extend = (def, oatNames, added: ValueList.added) => {
  let {names: extra, short: extraShort} = added
  let oatMax = def.max
  let names = Array.concat(oatNames, extra)
  let short =
    def.shortNames->Option.getOr(oatNames)->Array.slice(~start=0, ~end=Array.length(oatNames))
  let max = oatMax +. Int.toFloat(Array.length(extra))
  let clamp = x => Float.isFinite(x) ? Math.max(def.min, Math.min(max, Math.round(x))) : def.init
  let isNew = x => x > oatMax
  let newName = x => names[Float.toInt(clamp(x))]->Option.getOr("")
  let newShort = x => extraShort[Float.toInt(clamp(x) -. oatMax -. 1.)]->Option.getOr("")
  {
    ...def,
    names: Some(names),
    shortNames: Some(Array.concat(short, extraShort)),
    max,
    clamp,
    load: clamp,
    toNorm: x => (clamp(x) -. def.min) /. (max -. def.min),
    fromNorm: v => clamp(def.min +. v *. (max -. def.min)),
    longText: x => isNew(x) ? `${def.name}: ${newName(x)}` : def.longText(x),
    valueText: x => isNew(x) ? newName(x) : def.valueText(x),
    shortText: x => isNew(x) ? newShort(x) : def.shortText(x),
    parse: s =>
      switch nameIndex(names, s) {
      | Some(i) => Some(i)
      | None => def.parse(s)
      },
  }
}

// The closest value Oatmeal has, for an export: one Porridge added to the list becomes the one
// its list names.
let oatmealValue = (d, x) =>
  switch d.list->Option.flatMap(l => ValueList.info(l).added) {
  | Some(added) =>
    let first = d.max -. Int.toFloat(Array.length(added.names) - 1)
    x >= first ? Int.toFloat(added.toOatmeal(Float.toInt(x -. first))) : x
  | None => x
  }

// context supplies the program that status texts read other fields from (octave size,
// tuning, breakpoint, targets...); Init values without one.
let makeDefs = (~context=() => None) => {
  let init = OatmealFormat.makeDefaultProgram("Init")

  let oatmeal = Fields.all->Array.map(field => {
    let {index, id, name, kind} = field
    let p = OatmealParams.param(index)
    let isPw = kind == Pw
    let isInt = Fields.isInt(field)
    let toF = x => isPw ? OatmealParams.pwToPhase(x) : x
    let fromF = x => isPw ? OatmealParams.pwOfPhase(x) : x

    let list = ValueList.ofOatmeal(id)
    let listInfo = list->Option.map(ValueList.info)
    let names =
      listInfo
      ->Option.flatMap(l => l.names)
      ->Option.orElse(p.labels)
      ->Option.map(names =>
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
    let initValue = Bank.readField(init, field)
    let min = isPw ? 0. : lo
    let max = isPw ? 1. : hi

    let clamp = x => {
      let x = Float.isFinite(x) ? x : initValue
      isInt
        ? Math.max(Math.round(min), Math.min(Math.round(max), Math.round(x)))
        : Math.max(min, Math.min(max, x))
    }
    let load = isInt || isPw ? clamp : x => Float.isFinite(x) ? x : initValue
    let fromNorm = v => fromF(OatmealParams.toInternal(index, Math.max(0., Math.min(1., v))))
    // The cutoff's knob law follows the filter's type: with a zero-delay-feedback filter
    // (Porridge's) it reaches 20 kHz instead of 11 (FilterTypes.cutoffHz).
    let typeOfLaw = id == "Cutoff" ? Some("Filter") : None
    let zdfType = () =>
      switch (typeOfLaw, context()) {
      | (Some(typeId), Some(prog)) =>
        let t = Float.toInt(Bank.readValue(prog, typeId))
        t >= FilterTypes.firstPorridge ? Some(t) : None
      | _ => None
      }
    // the fields the status text reads from the context program (and the cutoff's type)
    let dependsOn =
      p.reads
      ->Array.flatMap(offset => Fields.all->Array.filter(f => f.offset == offset && f.id != id))
      ->Array.map(f => f.id)
      ->Array.concat(typeOfLaw->Option.mapOr([], typeId => [typeId]))
    let valueText = (x: float) =>
      switch zdfType() {
      | Some(filterType) => Float.toFixed(FilterTypes.cutoffHz(~filterType, x), ~digits=2) ++ " Hz"
      | None => OatmealParams.displayText(index, toF(x), ~prog=?context())
      }

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

    let def = {
      id,
      index,
      name,
      kind,
      isInt,
      list,
      names: names->Option.filter(names => !(isInt && Array.length(names) > 40)),
      shortNames: listInfo->Option.flatMap(l => l.short),
      init: initValue,
      min,
      max,
      bipolar: names == None && lo < 0. && hi > 0.,
      clamp,
      load,
      toNorm: x => OatmealParams.toNormalized(index, toF(x)),
      fromNorm,
      longText: x =>
        zdfType() != None
          ? `${name}: ${valueText(x)}`
          : OatmealParams.statusText(
              index,
              OatmealParams.textNormalized(index, toF(x)),
              ~prog=?context(),
            ),
      valueText,
      shortText: x => compact(valueText(x)),
      parse,
      dependsOn,
    }

    switch (listInfo->Option.flatMap(l => l.added), def.names) {
    | (Some(added), Some(oatNames)) => extend(def, oatNames, added)
    | _ => def
    }
  })
  // a copy is like a parameter before it, Oatmeal's or Porridge's
  let byId = oatmeal->Array.map(d => (d.id, d))->Map.fromArray
  let like = id =>
    switch byId->Map.get(id) {
    | Some(d) => d
    | None => JsError.panic("no parameter " ++ id ++ " to copy")
    }
  oatmeal->Array.concat(
    PorridgeParams.all->Array.mapWithIndex((spec, i) => {
      let d = porridgeDef(OatmealParams.paramCount + i, spec, ~like)
      byId->Map.set(d.id, d)
      d
    }),
  )
}

// Every definition, made once without a context program (for names, ranges and laws).
let all = Lazy.make(() => makeDefs())
let byId = Lazy.make(() => Lazy.get(all)->Array.map(d => (d.id, d))->Map.fromArray)

// A list parameter's value by its name, which it must have: choiceValue("Sat_Type", "soft clip")
// is 2. The UI, the tools and the DSP's constants (tools/gen.mjs) all name values this way.
let choiceValue = (id, label) =>
  switch Lazy.get(byId)->Map.get(id)->Option.flatMap(d => d.names)->Option.map(Array.indexOf(_, label)) {
  | Some(i) if i >= 0 => Int.toFloat(i)
  | _ => JsError.panic(`${id} has no choice "${label}"`)
  }
