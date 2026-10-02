// The distortion's types (Sat_Type): off, Oatmeal's four curves and the custom shape, then the
// models, ports of Airwindows plugins (dsp/Airwindows.cmajor). A model takes the distortion's
// drive, tone and character knobs as controls of its own (each type names the ones it uses);
// the mix works on every type.
//
// Values are append only (presets and hosts keep the number), so a type added later goes at
// the end, and its group puts it in its place in the menu.

type knobs = {drive?: string, tone?: string, character?: string}

// The menu's groups, each under a heading (off, first, under none).
type group = Off | Curves | Saturation | Distortion | Amps | LoFi

let heading = group =>
  switch group {
  | Off => None
  | Curves => Some("curves")
  | Saturation => Some("saturation")
  | Distortion => Some("distortion")
  | Amps => Some("amps")
  | LoFi => Some("lo-fi")
  }

type info = {
  name: string,
  // for the narrow value fields
  short: string,
  // the plugin it ports
  source?: string,
  about: string,
  knobs: knobs,
  group: group,
}

let custom = 5
let firstModel = 6

let all: array<info> = [
  {name: "off", short: "off", about: "off", knobs: {}, group: Off},
  {name: "hard clip", short: "hard clip", about: "clips flat at the limit", knobs: {}, group: Curves},
  {name: "soft clip", short: "soft clip", about: "rounds off towards the limit (tanh)", knobs: {}, group: Curves},
  {name: "sine", short: "sine", about: "a sine of the input: folds over past the limit", knobs: {}, group: Curves},
  {
    name: "asymmetric",
    short: "asymmetric",
    about: "bends the two halves of the wave differently",
    knobs: {},
    group: Curves,
  },
  {name: "custom shape", short: "custom", about: "the curve you draw", knobs: {}, group: Curves},
  {
    name: "tube",
    short: "tube",
    source: "Tube",
    about: "a fat tube boost, rounder the more it's driven",
    knobs: {drive: "tube"},
    group: Saturation,
  },
  {
    name: "tape",
    short: "tape",
    source: "Tape",
    about: "tape saturation: softened highs and a bump in the bass",
    knobs: {drive: "slam", tone: "bump"},
    group: Saturation,
  },
  {
    name: "saturate",
    short: "saturate",
    source: "Density",
    about: "sine saturation, stacked for more; below a fifth of the drive it thins the sound out instead",
    knobs: {drive: "density", character: "low cut"},
    group: Saturation,
  },
  {
    name: "mixer drive",
    short: "mixer",
    source: "Mackity",
    about: "the input stage of a small analog mixer, pushed hard",
    knobs: {drive: "input"},
    group: Saturation,
  },
  {
    name: "7-stage clip",
    short: "7-stage",
    source: "Edge",
    about: "seven clips in a row with lowpasses between: dense, and smooth on top",
    knobs: {drive: "gain", tone: "high cut", character: "low cut"},
    group: Distortion,
  },
  {
    name: "multiband",
    short: "multiband",
    source: "MultiBandDistortion",
    about: "the highs and the lows driven apart, each into a sine clip",
    knobs: {drive: "drive", tone: "split", character: "hardness"},
    group: Distortion,
  },
  {
    name: "wavefold",
    short: "wavefold",
    source: "Fracture2",
    about: "folds the wave back over itself past its peak",
    knobs: {drive: "drive", tone: "fold", character: "fracture"},
    group: Distortion,
  },
  {
    name: "bass amp",
    short: "bass amp",
    source: "BassAmp",
    about: "a bass amp: an overdriven top over a clean bass bump and a sub octave",
    knobs: {drive: "high", tone: "dub", character: "sub"},
    group: Amps,
  },
  {
    name: "guitar amp",
    short: "guitar amp",
    source: "GrindAmp",
    about: "a high-gain guitar amp into a 4×12 cabinet",
    knobs: {drive: "gain", tone: "tone"},
    group: Amps,
  },
  {
    name: "bitcrush",
    short: "bitcrush",
    source: "Beam",
    about: "fewer levels, chosen to keep the tone (focus) rather than at random",
    knobs: {drive: "crush", tone: "focus"},
    group: LoFi,
  },
  {
    name: "lo-fi sampler",
    short: "lo-fi",
    source: "BitGlitter",
    about: "an old sampler: a lower sample rate and coarse steps, saturated",
    knobs: {drive: "downsample", tone: "fine steps"},
    group: LoFi,
  },
]

let info = t => all[t]->Option.getOr(all->Array.getUnsafe(0))

let isModel = t => t >= firstModel

// The names Porridge adds after Oatmeal's (ValueList).
let porridgeNames = all->Array.slice(~start=custom)->Array.map(i => i.name)
let porridgeShort = all->Array.slice(~start=custom)->Array.map(i => i.short)

// Every type in menu order, with the heading above it where a group starts: group by group, in
// the order of each group's first type.
let order: array<(int, option<string>)> = {
  let groups = []
  all->Array.forEach(i =>
    if !(groups->Array.includes(i.group)) {
      groups->Array.push(i.group)
    }
  )
  groups->Array.flatMap(group =>
    all
    ->Array.mapWithIndex((i, t) => i.group == group ? Some(t) : None)
    ->Array.filterMap(t => t)
    ->Array.mapWithIndex((t, k) => (t, k == 0 ? heading(group) : None))
  )
}

type knob = [#drive | #tone | #character]

// What a knob does on this type: its label, or None if the type doesn't use it.
let knobLabel = (t, knob: knob) => {
  let k = info(t).knobs
  switch knob {
  | #drive => k.drive
  | #tone => k.tone
  | #character => k.character
  }
}

// A line about the type for the status bar and the graphs.
let describe = t => {
  let i = info(t)
  switch i.source {
  | Some(source) => `${i.name}: ${i.about} (Airwindows ${source})`
  | None => `${i.name}: ${i.about}`
  }
}
