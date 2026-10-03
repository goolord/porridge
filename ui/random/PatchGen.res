// Random patches, and variations of any patch.
//
// A patch is made from Init in five areas, each with a wildness from tame (0) to wild (1):
//
//   osc     a wave or two (often a drawn one, played plainly or as a pulse, as most of Oatmeal's
//           programs do) and some unison; wilder, stranger drawn waves, sync, FM, PM, ring and AM
//           at odd ratios with an envelope on their depth, noise, roughness and wide unison
//   filter  a lowpass that follows the keys, with a modest envelope; wilder, every kind of type
//           (formants, combs, phasers), more resonance, deeper and stranger envelopes, a second
//           filter and drive
//   env     the amp envelope as the patch's kind has it; wilder, any times, two-stage decays and
//           a pitch envelope
//   mod     none at 0; a gentle routing or two (vibrato, velocity and note-to-note variation,
//           slow sweeps) and now and then the XY pad routed, to play; wilder, more and deeper
//           ones: wobbles, blips, sample & hold, growls, and the pad wandering on its own
//   fx      dry at 0; a space, a delay or a chorus; wilder, more of the rack, an effect in every
//           voice (each note running its own), drive, frequency shifting and odd impulses
//
// A wildness widens each range from the tame one towards the whole of it (`within`), lets in
// the wilder options (types, modes, routings, effects) as it passes their thresholds (`tiered`),
// and makes the optional parts likelier. The tame ranges come from the patch's kind (bass,
// lead, pad, keys, pluck, bell, brass), which also sets the note it is auditioned at.
//
// `vary` moves any patch's settings by an amount: each continuous one in musical terms (times
// and rates on a log scale, levels in dB), now and then a choice picked again, and, more often
// the wilder its area may go, a part made again, added or taken away (osc 2 and the mix mode, a
// drawn wave, the filter type, the pitch envelope, a routing, the XY pad, an effect). Locked
// areas stay as they are.
//
// A patch is its values and its tables: the oscillators' drawn waves are the osc area's.
//
// The output gain follows an estimate of how loud the patch plays (`loudness`: K-weighted, as a
// loudness meter hears it), so that new patches and variations come out at about the same
// level; the drawer then measures each card as it first plays, and sets it from that.

type area = [#osc | #filter | #env | #mod | #fx]

let areas: array<area> = [#osc, #filter, #env, #mod, #fx]

let areaName = (a: area) =>
  switch a {
  | #osc => "oscillators"
  | #filter => "filter"
  | #env => "envelopes"
  | #mod => "modulation"
  | #fx => "effects"
  }

let areaShort = (a: area) => (a :> string)

// how wild each area may go, 0..1
type wildness = {osc: float, filter: float, env: float, mod: float, fx: float}

let wildOf = (w: wildness, a: area) =>
  switch a {
  | #osc => w.osc
  | #filter => w.filter
  | #env => w.env
  | #mod => w.mod
  | #fx => w.fx
  }

let withWild = (w: wildness, a: area, x) =>
  switch a {
  | #osc => {...w, osc: x}
  | #filter => {...w, filter: x}
  | #env => {...w, env: x}
  | #mod => {...w, mod: x}
  | #fx => {...w, fx: x}
  }

let defaultWildness = {osc: 0.3, filter: 0.3, env: 0.25, mod: 0.3, fx: 0.3}

type kind = [#bass | #lead | #pad | #keys | #pluck | #bell | #brass]

let kinds: array<kind> = [#bass, #lead, #pad, #keys, #pluck, #bell, #brass]

let kindName = (k: kind) => (k :> string)

//==============================================================================
// Chance

type rng = unit => float

// mulberry32: the same patches from the same seed (for the tests)
let seeded: int => rng = %raw(`seed => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}`)

let between = (r: rng, lo: float, hi: float) => lo + (hi - lo) * r()
let logBetween = (r: rng, lo: float, hi: float) => lo * Math.pow(hi / lo, ~exp=r())
let chance = (r: rng, p) => r() < p
let sign = r => chance(r, 0.5) ? 1. : -1.
let pick = (r: rng, xs: array<'a>) => {
  let n = Array.length(xs)
  xs->Array.getUnsafe(Math.Int.min(n - 1, Float.toInt(r() * Int.toFloat(n))))
}
let weighted = (r: rng, xs: array<('a, float)>) => {
  let total = xs->Array.reduce(0., (s, (_, w)) => s + w)
  let x = ref(r() * total)
  let i = ref(0)
  let weightAt = i => Pair.second(xs->Array.getUnsafe(i))
  while i.contents < Array.length(xs) - 1 && x.contents >= weightAt(i.contents) {
    x := x.contents - weightAt(i.contents)
    i := i.contents + 1
  }
  Pair.first(xs->Array.getUnsafe(i.contents))
}
let gaussian = (r: rng) =>
  Math.sqrt(-2. * Math.log(Math.max(r(), 1e-12))) * Math.cos(2. * Math.Constants.pi * r())

// the tame range opened towards the whole one as w goes from 0 to 1 (slowly at first: the whole
// of a range, a 4 s attack or a 30 dB drive, is for the wildest)
let widen = (w: float, (lo: float, hi: float), (wlo: float, whi: float)) => {
  let w = Math.pow(w, ~exp=1.5)
  (lo + (wlo - lo) * w, hi + (whi - hi) * w)
}
let within = (r, w, tame, whole) => {
  let (lo, hi) = widen(w, tame, whole)
  between(r, lo, hi)
}
// the same on a log scale (times, rates, ratios)
let logWithin = (r, w, (lo, hi), (wlo, whi)) => {
  let (a, b) = widen(w, (Math.log(lo), Math.log(hi)), (Math.log(wlo), Math.log(whi)))
  Math.exp(between(r, a, b))
}
// one of the options whose threshold w has reached (value, threshold, weight); the first must
// have threshold 0
let tiered = (r, w, options: array<('a, float, float)>) =>
  weighted(r, options->Array.filterMap(((v, from, weight)) => w >= from ? Some((v, weight)) : None))

//==============================================================================
// Values

let def = id => Lazy.get(Preset.defsById)->Map.get(id)->Option.getOrThrow
let get = (m: Bank.values, id) => m->Map.get(id)->Option.getOr(0.)
let put = (m: Bank.values, id, v) => m->Map.set(id, def(id).clamp(v))

let initValues = Lazy.make(() => Preset.make("Init").values)
let copy = (m: Bank.values): Bank.values => Map.fromArray(m->Map.entries->Array.fromIterator)
// puts these parameters back as Init has them
let reset = (m, ids: array<string>) => ids->Array.forEach(id => m->Map.set(id, get(Lazy.get(initValues), id)))

// A patch: its values and its tables (Oatmeal's: the oscillators' drawn waves, which patches made
// here draw, and the LFO shapes and curves, which they keep as they came). A table is replaced
// when it's drawn again, never changed in place.
type patch = {values: Bank.values, mutable tables: OatmealFormat.tables}

let initTables = Lazy.make(() => Preset.make("Init").tables)
let copyPatch = t => {values: copy(t.values), tables: t.tables}

let ampOfDb = db => Math.pow(10., ~exp=db / 20.)
let dbOfAmp = a => 20. * Math.log10(Math.max(a, 1e-9))
let noteHz = n => 440. * Math.pow(2., ~exp=(Int.toFloat(n) - 69.) / 12.)

// the waves
let sine = 0.
let saw = 6.
let pulse = 7.
let triangle = 8.
// the mix modes (OscMix)
let normal = 0
let sync = 1
let fm = 2
let pm = 3
let pmFeedback = 4
let ring = 5
let am = 6
let modulating = mode => mode == fm || mode == pm || mode == ring || mode == am
// the level that is the modulator's depth: osc 1's in FM (where osc 2 is what's heard), osc 2's
// in PM, ring and AM
let depthOf = mode => mode == fm ? "O1_Amp" : "O2_Amp"
let mixMode = m => Float.toInt(get(m, "OscMix"))
let secondSounds = m => get(m, "O2_Amp") > 0. || mixMode(m) != normal
let isPulse = v => v == 2. || v == pulse
// the drawn waves: played plainly, or as a pulse (the wave less itself further on in its cycle)
let drawn = 4.
let drawnPulse = 5.
let isDrawn = v => v == drawn || v == drawnPulse
// the waves with a pulse width
let hasWidth = v => isPulse(v) || v == drawnPulse

// a table's value at x, between its points (and its end ones beyond them)
let interpolate = (xs: array<float>, ys: array<float>, x) => {
  let n = Array.length(xs)
  let at = (a, i) => a->Array.getUnsafe(i)
  if x <= at(xs, 0) {
    at(ys, 0)
  } else if x >= at(xs, n - 1) {
    at(ys, n - 1)
  } else {
    let i = ref(0)
    while x > at(xs, i.contents + 1) {
      i := i.contents + 1
    }
    let k = i.contents
    at(ys, k) + (at(ys, k + 1) - at(ys, k)) * (x - at(xs, k)) / (at(xs, k + 1) - at(xs, k))
  }
}
let rowOf = (rows: array<array<float>>, t) => rows[t]->Option.getOr(rows->Array.getUnsafe(0))

// a filter type's level (dB, LevelTables) with its cutoff at these octaves above the note, for a
// saw's spectrum or a sine's
let filterLevel = (rows, t, octaves) => interpolate(LevelTables.octaves, rowOf(rows, t), octaves)

// what its resonance adds with the cutoff there (steeper past 0.85, where the lowpasses begin
// to ring), and its drive
let resonanceLevel = (t, res, octaves) => {
  let row = rowOf(LevelTables.resonance, t)
  let at = pair =>
    switch (row[2 * pair], row[2 * pair + 1]) {
    | (Some(r50), Some(r85)) => interpolate([0., 0.5, 0.85, 1.], [0., r50, r85, r85 + 6. * (r85 - r50) * 0.15 / 0.35], res)
    | _ => 0.
    }
  interpolate(LevelTables.resonanceOctaves, LevelTables.resonanceOctaves->Array.mapWithIndex((_, i) => at(i)), octaves)
}
let filterDriveLevel = (t, drive) => 2. * drive * LevelTables.filterDrive[t]->Option.getOr(0.)

// A distortion type's output level (dB, LevelTables) for an input at x dB, before its postgain:
// between the measured points, following the input below them and the last slope above.
let driveCurve = (t, x) => {
  let xs = LevelTables.driveInputs
  let ys = rowOf(LevelTables.drive, t)
  let n = Array.length(xs)
  let at = (a, i) => a->Array.getUnsafe(i)
  if t == 0 {
    x
  } else if x < at(xs, 0) {
    at(ys, 0) + x - at(xs, 0)
  } else if x > at(xs, n - 1) {
    at(ys, n - 1) + (x - at(xs, n - 1)) * (at(ys, n - 1) - at(ys, n - 2)) / (at(xs, n - 1) - at(xs, n - 2))
  } else {
    interpolate(xs, ys, x)
  }
}

// the level a voice has going into its distortion in a usual patch (a saw at 0 dB)
let usualInput = LevelTables.waves[6]->Option.getOr(-12.)

// The postgain that leaves a usual voice as loud as it is without the distortion: a clipper
// holds its output under its ceiling and needs less taking down than its pregain; a bitcrusher
// only raises the level, all of which comes off again.
let neutralPostgain = (t, pregain) => usualInput - driveCurve(t, usualInput + pregain)

// The cutoff's frequency at a note (as dsp/Synth.cmajor's cutoffHz has it, without envelopes and
// modulation), with its knob where it is or at `knob`.
let cutoffAt = (m, ~note, ~knob=?) => {
  let t = Float.toInt(get(m, "Filter"))
  let hz = FilterTypes.cutoffHz(~filterType=t, knob->Option.getOr(get(m, "Cutoff")))
  hz *
  Math.pow(noteHz(note) / 440., ~exp=get(m, "F_Track")) *
  Math.pow(2., ~exp=get(m, "Tune_CutReference") / 12.)
}

// Which area a parameter belongs to (locked areas keep theirs). Osc 2's envelope (mod env 1) is
// the oscillators': it sweeps their interval or depth.
let rackParams = Lazy.make(() => Set.fromArray(FxRack.all->Array.flatMap(FxRack.params)))
let owner = (id: string): option<area> => {
  let starts = prefixes => prefixes->Array.some(p => String.startsWith(id, p))
  let is = ids => ids->Array.includes(id)
  if starts(["O1_", "O2_", "N_", "U_", "M1_", "Curve_Mod1_", "OE1_", "OE2_", "Curve_Osc", "Drift_"]) ||
  is(["Transpose", "Detune", "OscMix", "PM_Feedback", "OscPhase", "OscPhaseRand", "OscRetrig", "PWMPhase", "PWMPhaseRand", "PWMRetrig"]) {
    Some(#osc)
  } else if starts(["F_", "Curve_Filter_"]) || is(["Filter", "Filter2", "Cutoff", "Resonance", "Tune_CutReference"]) {
    Some(#filter)
  } else if starts(["PEnv_", "Curve_Amp_"]) ||
  is(["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release", "VeloSens", "PolyMode", "Glide", "GlideMode"]) {
    Some(#env)
  } else if starts(["LFO_", "M2_", "Curve_Mod2_", "XY_"]) || ModMatrix.isSlotParam(id) || is(["LFOPhase", "LFOPhaseRand", "LFORetrig"]) {
    Some(#mod)
  } else if starts(["Sat_", "FX_", "VL_", "C_", "D_", "R_", "EQ_"]) || Lazy.get(rackParams)->Set.has(id) {
    Some(#fx)
  } else {
    None
  }
}

//==============================================================================
// Kinds

type profile = {
  // the note a patch is auditioned at
  note: int,
  // the amp envelope, tame: ms, and the sustain level 0..1
  attack: (float, float),
  decay: (float, float),
  sustain: (float, float),
  release: (float, float),
  // the cutoff as a multiple of the note's frequency, the filter envelope's depth (octaves),
  // attack and decay (ms)
  bright: (float, float),
  envOctaves: (float, float),
  filterAttack: (float, float),
  filterDecay: (float, float),
  // osc 1's waves (weighted), how likely osc 2 is, and its intervals (semitones, weighted)
  waves: array<(float, float)>,
  second: float,
  intervals: array<(float, float)>,
  unison: float,
  // how likely it plays mono with glide, and without a filter
  mono: float,
  unfiltered: float,
}

let profile = (k: kind) =>
  switch k {
  | #bass => {
      note: 36,
      attack: (0.3, 4.),
      decay: (150., 900.),
      sustain: (0.35, 0.9),
      release: (25., 160.),
      bright: (1.5, 6.),
      envOctaves: (1., 3.5),
      filterAttack: (0.2, 3.),
      filterDecay: (90., 500.),
      waves: [(saw, 3.), (pulse, 2.), (triangle, 0.5), (sine, 0.4)],
      second: 0.6,
      intervals: [(-12., 3.), (0., 2.), (12., 1.), (7., 0.4)],
      unison: 0.15,
      mono: 0.6,
      unfiltered: 0.,
    }
  | #lead => {
      note: 64,
      attack: (1., 20.),
      decay: (300., 1500.),
      sustain: (0.6, 1.),
      release: (60., 300.),
      bright: (4., 16.),
      envOctaves: (0.5, 2.5),
      filterAttack: (0.5, 20.),
      filterDecay: (200., 1200.),
      waves: [(saw, 3.), (pulse, 2.), (triangle, 0.5)],
      second: 0.65,
      intervals: [(0., 2.), (12., 1.5), (7., 1.), (-12., 1.), (19., 0.4)],
      unison: 0.35,
      mono: 0.6,
      unfiltered: 0.05,
    }
  | #pad => {
      note: 60,
      attack: (250., 1500.),
      decay: (800., 4000.),
      sustain: (0.6, 1.),
      release: (800., 3000.),
      bright: (2., 8.),
      envOctaves: (0., 1.5),
      filterAttack: (300., 2000.),
      filterDecay: (800., 4000.),
      waves: [(saw, 3.), (pulse, 1.5), (triangle, 1.)],
      second: 0.8,
      intervals: [(0., 3.), (12., 1.5), (7., 1.), (-12., 1.), (19., 0.3)],
      unison: 0.75,
      mono: 0.,
      unfiltered: 0.05,
    }
  | #keys => {
      note: 60,
      attack: (0.5, 5.),
      decay: (700., 3000.),
      sustain: (0., 0.35),
      release: (150., 600.),
      bright: (2., 8.),
      envOctaves: (1., 3.),
      filterAttack: (0.2, 5.),
      filterDecay: (300., 1500.),
      waves: [(triangle, 2.), (pulse, 2.), (saw, 1.5), (sine, 1.)],
      second: 0.5,
      intervals: [(12., 2.), (0., 1.5), (19., 0.7), (24., 0.5)],
      unison: 0.2,
      mono: 0.,
      unfiltered: 0.15,
    }
  | #pluck => {
      note: 60,
      attack: (0.2, 3.),
      decay: (150., 700.),
      sustain: (0., 0.),
      release: (100., 500.),
      bright: (1.5, 5.),
      envOctaves: (2., 4.5),
      filterAttack: (0.2, 2.),
      filterDecay: (60., 400.),
      waves: [(saw, 3.), (pulse, 2.), (triangle, 1.)],
      second: 0.4,
      intervals: [(12., 2.), (0., 2.), (7., 0.7), (-12., 0.7)],
      unison: 0.3,
      mono: 0.,
      unfiltered: 0.,
    }
  | #bell => {
      note: 72,
      attack: (0.2, 3.),
      decay: (1500., 5000.),
      sustain: (0., 0.),
      release: (800., 3000.),
      bright: (6., 24.),
      envOctaves: (0., 2.),
      filterAttack: (0.2, 5.),
      filterDecay: (500., 3000.),
      waves: [(sine, 3.), (triangle, 1.)],
      second: 1.,
      intervals: [(12., 1.)],
      unison: 0.05,
      mono: 0.,
      unfiltered: 0.5,
    }
  | #brass => {
      note: 60,
      attack: (30., 120.),
      decay: (400., 1500.),
      sustain: (0.6, 0.9),
      release: (100., 300.),
      bright: (1., 3.),
      envOctaves: (1.5, 3.),
      filterAttack: (40., 150.),
      filterDecay: (300., 1000.),
      waves: [(saw, 4.), (pulse, 1.)],
      second: 0.6,
      intervals: [(0., 3.), (12., 1.), (-12., 0.5)],
      unison: 0.4,
      mono: 0.15,
      unfiltered: 0.,
    }
  }

// What a patch most likely is, from its amp envelope and oscillators (for one that wasn't made here).
let kindOf = (m): kind => {
  let sustain = get(m, "Sustain")
  if get(m, "Attack") > 150. {
    #pad
  } else if sustain < 0.05 {
    get(m, "Decay2") < 900. ? #pluck : modulating(mixMode(m)) ? #bell : #keys
  } else if get(m, "F_Attack") > 25. && get(m, "F_EnvMod") > 0. {
    #brass
  } else if get(m, "PolyMode") != 1. {
    get(m, "Transpose") < 0. ? #bass : #lead
  } else {
    #lead
  }
}

//==============================================================================
// Drawn waves

// What Oatmeal's own programs draw (three in four of them play a drawn wave, as often as a pulse
// as plainly): mostly a rich, saw-like spectrum, then a few drawbars, odd harmonics, a sine with
// a little colour; wilder, a formant's hump, a few high partials alone, or a shape drawn by hand.
type recipe = Rich | Drawbars | Odd | NearSine | Hump | Sparse | ByHand

// (recipe, threshold, weight)
let recipes = (k: kind) => [
  (Rich, 0., k == #bell ? 0.3 : 3.),
  (Drawbars, 0., k == #keys || k == #pad || k == #bell ? 2. : 1.),
  (Odd, 0., k == #bass || k == #lead ? 1.5 : 1.),
  (NearSine, 0., k == #bell ? 2. : 0.6),
  (Hump, 0.3, k == #brass || k == #lead || k == #pad ? 1. : 0.6),
  (Sparse, 0.55, k == #bell ? 1. : 0.4),
  (ByHand, 0.6, 0.5),
]

let drawbarHarmonics = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]

// A wave of this recipe: its harmonics' levels (phases at 0, as the harmonic editor draws a saw),
// a little uneven the wilder it is; or a shape by hand, a line through a few random points.
// 512 points, peak 1.
let drawWave = (r, w, recipe) => {
  let count = 64
  let s = WaveImport.emptySpectrum(WaveImport.harmonics)
  let set = (k, a) => s.amp->Array.setUnsafe(k - 1, a)
  let uneven = () => Math.exp(gaussian(r) * (0.1 + 0.3 * w))
  let falling = (p, k) => Math.pow(Int.toFloat(k), ~exp=-.p) * uneven()
  switch recipe {
  | Rich =>
    let p = within(r, w, (0.9, 1.3), (0.5, 2.))
    for k in 1 to count {
      set(k, falling(p, k))
    }
  | Drawbars =>
    set(1, 1.)
    drawbarHarmonics->Array.forEach(k => k > 1 && chance(r, 0.45) ? set(k, between(r, 0.1, 0.8)) : ())
  | Odd =>
    let p = within(r, w, (1., 1.6), (0.6, 2.2))
    let evens = chance(r, w) ? 0.15 : 0.
    for k in 1 to count {
      set(k, mod(k, 2) == 1 ? falling(p, k) : evens * falling(p, k))
    }
  | NearSine =>
    set(1, 1.)
    for _ in 1 to 3 {
      set(Float.toInt(between(r, 2., 6.99)), between(r, 0.03, 0.25))
    }
  | Hump =>
    let centre = logBetween(r, 3., 16.)
    let width = between(r, 1.5, 4.)
    for k in 1 to count {
      let d = (Int.toFloat(k) - centre) / width
      set(k, Math.exp(-0.5 * d * d))
    }
    set(1, between(r, 0.3, 1.))
  | Sparse =>
    set(1, between(r, 0., 0.3))
    for _ in 1 to 1 + Float.toInt(r() * 2.99) {
      set(Float.toInt(between(r, 2., 16.99)), between(r, 0.5, 1.))
    }
  | ByHand => ()
  }
  let wave = if recipe == ByHand {
    // (DC taken out: the engine would play it as an offset)
    let points = 4 + Float.toInt(r() * 9.)
    let ys = Array.fromInitializer(~length=points, _ => between(r, -1., 1.))
    let at = i => {
      let x = Int.toFloat(i * points) / 512.
      let k = Float.toInt(x)
      let f = x - Int.toFloat(k)
      ys->Array.getUnsafe(k) * (1. - f) + ys->Array.getUnsafe(mod(k + 1, points)) * f
    }
    let mean = Array.fromInitializer(~length=512, at)->Array.reduce(0., (s, y) => s + y) / 512.
    let line = Array.fromInitializer(~length=512, i => at(i) - mean)
    let peak = line->Array.reduce(1e-6, (p, y) => Math.max(p, Math.abs(y)))
    Some(Float32Array.fromArray(line->Array.map(y => y / peak)))
  } else {
    WaveImport.synthesise(s)
  }
  wave->Option.getOr(Lazy.get(initTables).wave1)
}

// A drawn wave for an oscillator (its table: Wave1 or Wave2), of a recipe that suits the kind.
let drawFor = (r, w, k, t: patch, table) =>
  t.tables = t.tables->OatmealFormat.setTable(table, drawWave(r, w, tiered(r, w, recipes(k))))

// how likely an oscillator plays a drawn wave
let drawnOdds = w => 0.4 + 0.3 * w

// A drawn wave's power against the sine Init has drawn (what LevelTables measured the drawn
// waves with), as its fundamental's and the rest's: played plainly, or as a pulse of this width
// (the wave less itself that far on: each harmonic k by 2 sin(pi k width); Init's sine at Init's
// half width doubles).
let drawnPower = (table: Float32Array.t, ~width=?) => {
  let amps = WaveImport.spectrumOfCycle(table, ~start=0, ~n=512, ~count=32).amp
  let through = k =>
    width->Option.mapOr(1., pw => {
      let s = Math.sin(Math.Constants.pi * Int.toFloat(k) * pw)
      4. * s * s
    })
  let reference = width == None ? 0.5 : 2.
  let power = k => {
    let a = amps->Array.getUnsafe(k - 1)
    a * a / 2. * through(k) / reference
  }
  let rest = ref(0.)
  for k in 2 to 32 {
    rest := rest.contents + power(k)
  }
  (power(1), rest.contents)
}

//==============================================================================
// Oscillators

let oscModeIds = [
  "OscMix",
  "O1_Amp",
  "O2_Amp",
  "O2_Waveform",
  "O2_PWM_W",
  "Transpose",
  "Detune",
  "PM_Feedback",
  "O2_PairMix",
  "O2_Noise",
  "O2_NoiseColour",
  "M1_Attack",
  "M1_Hold",
  "M1_Decay1",
  "M1_Breakpoint",
  "M1_Decay2",
  "M1_Sustain",
  "M1_Release",
  "M1_VeloSens",
  "M1_Target_1",
  "M1_Depth_1",
]

let pulseWidth = (r, w) => within(r, w, (0.3, 0.5), (0.06, 0.5))

// osc 1's wave (often a drawn one), and its pulse width modulation
let oscWave = (r, w, k, p, t) => {
  let m = t.values
  reset(m, ["O1_Waveform", "O1_PWM_W", "O1_PWM_R", "O1_PWM_D"])
  let wave = if modulating(mixMode(m)) && chance(r, 0.4) {
    weighted(r, [(sine, 2.), (triangle, 1.)])
  } else if chance(r, drawnOdds(w)) {
    drawFor(r, w, k, t, Wave1)
    chance(r, 0.5) ? drawnPulse : drawn
  } else {
    weighted(r, Array.concat(p.waves, w > 0.5 ? [(sine, 0.5)] : []))
  }
  put(m, "O1_Waveform", wave)
  if wave == pulse || wave == drawnPulse {
    put(m, "O1_PWM_W", pulseWidth(r, w))
    if chance(r, 0.3 + 0.3 * w) {
      put(m, "O1_PWM_R", logWithin(r, w, (0.15, 1.2), (0.05, 7.)))
      put(m, "O1_PWM_D", within(r, w, (0.05, 0.2), (0.05, 0.45)))
    }
  }
}

// The mix mode and osc 2: at its interval and level, or as the modulator (its ratio and depth),
// with mod env 1 sweeping the depth or the synced interval. Osc 2 playing osc 1's drawn wave plays
// it from its own table; now and then it draws one of its own.
let oscPair = (r, w, k: kind, p, t) => {
  let m = t.values
  reset(m, oscModeIds)
  let mode = if k == #bell {
    weighted(r, [(pm, 3.), (fm, 1.5), (ring, 0.5 + w), (am, 0.3 + w)])
  } else if chance(r, w < 0.15 ? 0. : 0.1 + 0.6 * (w - 0.15) / 0.85) {
    tiered(
      r,
      w,
      [
        (sync, 0., k == #lead ? 2. : 1.),
        (pm, 0., 1.),
        (fm, 0.35, 0.8),
        (pmFeedback, 0.4, 0.6),
        (ring, 0.5, 0.6),
        (am, 0.55, 0.5),
      ],
    )
  } else {
    normal
  }
  put(m, "OscMix", Int.toFloat(mode))
  let second = mode != normal || chance(r, Math.min(1., p.second + 0.2 * w))
  if second {
    let wave1 = get(m, "O1_Waveform")
    let wave2 = if modulating(mode) {
      tiered(r, w, [(sine, 0., 4.), (triangle, 0.3, 1.), (saw, 0.5, 1.), (pulse, 0.6, 0.7)])
    } else if chance(r, 0.6) {
      if isDrawn(wave1) {
        t.tables = t.tables->OatmealFormat.setTable(Wave2, t.tables.wave1)
      }
      wave1
    } else if chance(r, 0.5 * drawnOdds(w)) {
      drawFor(r, w, k, t, Wave2)
      chance(r, 0.5) ? drawnPulse : drawn
    } else {
      weighted(r, p.waves)
    }
    put(m, "O2_Waveform", wave2)
    if hasWidth(wave2) {
      put(m, "O2_PWM_W", pulseWidth(r, w))
    }
    let semis = if mode == sync {
      chance(r, 1. - w) ? pick(r, [7., 12., 19.]) : between(r, 2., 12. + 24. * w)
    } else if modulating(mode) {
      let ratio = tiered(
        r,
        w,
        [
          (1., 0., 2.),
          (2., 0., 2.),
          (3., 0., 1.),
          (4., 0.2, 0.7),
          (0.5, 0.3, 0.5),
          (1.5, 0.5, 0.5),
          (3.5, 0.55, 0.6),
          (1.41, 0.65, 0.5),
          (2.76, 0.65, 0.5),
          (7., 0.7, 0.4),
          (5.19, 0.75, 0.4),
          (0.71, 0.8, 0.3),
        ],
      )
      12. * Math.log2(ratio)
    } else if chance(r, Math.max(0.4, 1. - w)) {
      weighted(r, p.intervals)
    } else {
      pick(r, [-12., -5., 3., 4., 5., 7., 10., 12., 17., 19., 24., 31.])
    }
    put(m, "Transpose", semis / 12.)
    let detune = modulating(mode)
      ? chance(r, 0.25 * w) ? between(r, 0.1, 2.) : 0.
      : logWithin(r, w, (0.2, 1.5), (0.1, 12.))
    put(m, "Detune", sign(r) * detune)
    if mode == sync {
      // the synced osc 2 is what's heard
      put(m, "O1_Amp", ampOfDb(between(r, -14., -6.)))
      put(m, "O2_Amp", 1.)
    } else if mode == fm {
      // osc 1 is silent, its level the depth
      put(m, "O1_Amp", ampOfDb(within(r, w, (-18., -6.), (-24., 10.))))
      put(m, "O2_Amp", 1.)
    } else if modulating(mode) {
      put(m, "O1_Amp", 1.)
      // (in PM osc 1 keeps its level whatever the depth; ring and AM past 0 dB grow louder)
      put(m, "O2_Amp", ampOfDb(within(r, w, (-18., -6.), (-24., mode == pm ? 6. : 0.))))
    } else {
      put(m, "O1_Amp", 1.)
      put(m, "O2_Amp", ampOfDb(within(r, w, (-9., -2.), (-18., 0.))))
    }
    if mode == pmFeedback {
      put(m, "PM_Feedback", within(r, w, (0.1, 0.35), (0.1, 0.95)))
    } else if mode == pm && chance(r, 0.25 + 0.35 * w) {
      put(m, "PM_Feedback", within(r, w, (0., 0.2), (0., 0.8)))
    }
    if (mode == pm || mode == ring || mode == am) && chance(r, 0.35) {
      put(m, "O2_PairMix", between(r, 0.1, 0.35 + 0.5 * w))
    }
    if (mode == sync || modulating(mode)) && chance(r, k == #bell ? 0.9 : 0.3 + 0.4 * w) {
      put(m, "M1_Attack", 0.2)
      put(m, "M1_Decay1", 10.)
      put(m, "M1_Breakpoint", 1.)
      put(m, "M1_Decay2", logWithin(r, w, k == #bell ? (400., 2500.) : (120., 1000.), (20., 6000.)))
      put(m, "M1_Sustain", within(r, w, (0., 0.25), (0., 0.8)))
      put(m, "M1_Release", 300.)
      put(m, "M1_VeloSens", between(r, 0.2, 0.6))
      if mode == sync {
        // osc 2's pitch, from up to two octaves above (unipolar: 24 semitones at 1)
        put(m, "M1_Target_1", 26.)
        put(m, "M1_Depth_1", within(r, w, (5., 12.), (3., 24.)) / 24.)
      } else {
        // the modulator's level: 60 dB down as the envelope falls, at 1
        put(m, "M1_Target_1", mode == fm ? 4. : 5.)
        put(m, "M1_Depth_1", within(r, w, (0.15, 0.4), (0.1, 0.8)))
      }
    }
  } else {
    put(m, "O1_Amp", 1.)
    put(m, "O2_Amp", 0.)
  }
}

let unisonIds = ["U_Voices", "U_Detune", "U_Spread", "U_Width", "U_RandomPhase"]

let oscUnison = (r, w, p, m) => {
  reset(m, unisonIds)
  if chance(r, Math.min(0.95, p.unison + 0.25 * w)) {
    put(m, "U_Voices", tiered(r, w, [(2., 0., 2.), (3., 0., 1.5), (4., 0., 1.), (5., 0.4, 0.6), (6., 0.5, 0.5), (8., 0.65, 0.5)]))
    put(m, "U_Detune", logWithin(r, w, (5., 14.), (3., 80.)))
    let u = r()
    put(m, "U_Spread", 0.35 + (0.8 - 0.35) * u)
    put(m, "U_Width", within(r, w, (1., 1.2), (0.8, 1.8)))
    // the random phase: mostly the whole cycle (the copies' attacks differ from note to note);
    // less keeps them closer to the oscillator's own start phase, for a firmer attack. (Its
    // number comes from the spread's draw, the digits it didn't use, so that the patches made
    // after it stay as they were.)
    let (lo, hi) = widen(w, (0.7, 1.), (0.2, 1.))
    put(m, "U_RandomPhase", lo + (hi - lo) * Float.mod(u * 7919., 1.))
  }
}

// The noise as the oscillators' description says it: "noise", "pink noise", "crackle".
let noiseText = m =>
  switch Float.toInt(get(m, "N_Type")) {
  | 0 => "noise"
  | t if t == PorridgeParams.noiseCrackle => "crackle"
  | t if t == PorridgeParams.noiseSample => "sampled noise"
  | t => PorridgeParams.noiseTypes[t]->Option.mapOr("noise", name => name ++ " noise")
  }

let noiseIds = ["N_Amp", "N_Resonance", "N_Transpose", "N_Type", "N_Density", "O1_Noise", "O1_NoiseColour", "O2_Noise", "O2_NoiseColour"]

// The noise type's level against white's (LevelTables.noiseTypes; the crackle's grows with its
// density, from the 20 a second it was measured at; the sample's is a file's, as loud as white).
let noiseTypeDb = m => {
  let t = Float.toInt(get(m, "N_Type"))
  let white = LevelTables.noiseTypes->Array.getUnsafe(0)
  let db = LevelTables.noiseTypes[t]->Option.mapOr(0., x => x - white)
  t == PorridgeParams.noiseCrackle
    ? db + 10. * Math.log10(PorridgeParams.expValue(1., 4000., get(m, "N_Density")) / 20.)
    : db
}

// the noise source (now and then a colour, crackle or 8-bit noise: never the sample, which is a
// file's), and roughness (each oscillator's pitch moved by its own noise)
let oscNoise = (r, w, k: kind, m) => {
  reset(m, noiseIds)
  if chance(r, 0.06 + 0.35 * w + (k == #pluck || k == #keys ? 0.08 : 0.)) {
    // (a resonant noise rings much louder: 15 dB more at 0.9)
    let res = within(r, w, (0., 0.3), (0., 0.85))
    put(m, "N_Resonance", res)
    if chance(r, 0.15 + 0.25 * w) {
      // pink, brown, blue, violet, crackle, digital, metallic
      let t = weighted(r, [(1., 1.), (2., 0.7), (3., 0.25), (4., 0.15), (5., 0.6), (6., 0.4), (7., 0.3)])
      put(m, "N_Type", t)
      if t == Int.toFloat(PorridgeParams.noiseCrackle) {
        put(m, "N_Density", PorridgeParams.expPos(1., 4000., logWithin(r, w, (8., 60.), (2., 1500.))))
      }
    }
    // as loud as white noise would be (the crackle's clicks up to 12 dB louder, not as loud: its
    // level is in its few clicks)
    put(m, "N_Amp", ampOfDb(within(r, w, (-34., -24.), (-32., -10.)) - 18. * res * res - Math.max(-12., noiseTypeDb(m))))
    if res > 0.5 {
      put(m, "N_Transpose", pick(r, [0., 12., 19., 24.]))
    }
  }
  if w > 0.3 && chance(r, 0.05 + 0.4 * (w - 0.3) / 0.7) {
    put(m, "O1_Noise", within(r, w, (0.05, 0.15), (0.05, 0.6)))
    put(m, "O1_NoiseColour", r())
    if secondSounds(m) && chance(r, 0.5) {
      put(m, "O2_Noise", within(r, w, (0.05, 0.15), (0.05, 0.6)))
      put(m, "O2_NoiseColour", r())
    }
  }
}

let makeOsc = (r, w, k, t) => {
  let m = t.values
  let p = profile(k)
  oscWave(r, w, k, p, t)
  oscPair(r, w, k, p, t)
  // (a modulating mode leans towards a sine carrier)
  if modulating(mixMode(m)) {
    oscWave(r, w, k, p, t)
  }
  oscUnison(r, w, p, m)
  oscNoise(r, w, k, m)
  reset(m, ["Drift_Pitch"])
  if chance(r, 0.5) {
    put(m, "Drift_Pitch", between(r, 0.5, 2.5 + 10. * w))
  }
}

//==============================================================================
// Filter

type family = Low | High | Band | Formant | Comb | Odd

// (name, family, threshold, weight)
let filterChoices = (k: kind) => [
  ("4P lowpass", Low, 0., 2.),
  ("2P lowpass", Low, 0., 1.),
  ("ladder", Low, 0., 1.5),
  ("MG low 24", Low, 0., 1.),
  ("MG low 12", Low, 0., 1.),
  ("Sallen-Key", Low, 0., 0.8),
  ("nonlinear 4P lowpass", Low, 0., 0.6),
  ("SVF LP > BP > HP", Low, 0., 0.6),
  ("French LP", Low, 0.1, 0.5),
  ("German LP", Low, 0.1, 0.5),
  ("diode ladder", Low, 0.25, 0.6),
  ("acid ladder", Low, 0.3, 0.6),
  ("MG dirty", Low, 0.3, 0.5),
  ("clean drive", Low, 0.3, 0.4),
  ("PZ SVF", Low, 0.3, 0.4),
  ("L/B/H 24 (morph)", Low, 0.35, 0.5),
  ("2P wide bandpass", Band, 0.3, 0.4),
  ("bandpass 12 dB", Band, 0.35, 0.4),
  ("2P highpass", High, 0.35, k == #bass ? 0. : 0.4),
  ("formant", Formant, 0.5, 0.6),
  ("formant I", Formant, 0.55, 0.35),
  ("formant II", Formant, 0.55, 0.35),
  ("formant III", Formant, 0.55, 0.35),
  ("comb", Comb, 0.55, 0.5),
  ("comb +", Comb, 0.6, 0.3),
  ("phaser, 12 stages", Comb, 0.6, 0.3),
  ("flanger", Comb, 0.65, 0.3),
  ("peak 12 dB", Band, 0.6, 0.25),
  ("B/P/B (morph)", Band, 0.6, 0.3),
  ("2P notch", Odd, 0.6, 0.25),
  ("ring mod", Odd, 0.85, 0.2),
  ("sample & hold", Odd, 0.85, 0.2),
  ("diffusor", Odd, 0.9, 0.15),
]

// any type's family, by its name (a program's filter may be any of them)
let familyOf = t => {
  let name = FilterTypes.all[t]->Option.getOr("")
  let has = words => words->Array.some(w => String.includes(name, w))
  if has(["highpass"]) {
    High
  } else if has(["formant"]) {
    Formant
  } else if has(["comb", "flanger", "phaser"]) {
    Comb
  } else if has(["bandpass", "peak", "B/P/B"]) {
    Band
  } else if has(["notch", "N/P/N", "ring", "sample", "diffusor", "reverb", "EQ"]) {
    Odd
  } else {
    Low
  }
}

let morphs = ["SVF LP > BP > HP", "PZ SVF", "L/B/H 24 (morph)", "B/P/B (morph)"]

let filterTypeIds = ["Filter", "Filter2", "Cutoff", "Resonance", "F_Track", "Tune_CutReference", "F_Morph", "F_Double", "F_Split", "F_Mix", "F_Drive"]

// The type, the cutoff (a multiple of the note's frequency at the audition note, followed by the
// keys from there), the resonance, a second filter and the drive.
let filterType = (r, w, k: kind, m) => {
  reset(m, filterTypeIds)
  let p = profile(k)
  if chance(r, p.unfiltered * (1. - 0.5 * w)) {
    put(m, "Filter", 0.)
  } else {
    let choices = filterChoices(k)->Array.map(((name, family, from, weight)) => ((name, family), from, weight))
    let (name, family) = tiered(r, w, choices)
    let t = FilterTypes.index(name)
    put(m, "Filter", Int.toFloat(t))
    let bright = switch family {
    | Low => logWithin(r, w, p.bright, (0.6, 48.))
    | High => logBetween(r, 0.4, 2.5)
    | Band | Formant => logBetween(r, 1., 10.)
    | Comb => logBetween(r, 0.5, 4.)
    | Odd => logBetween(r, 1., 16.)
    }
    let track = within(r, w, (0.4, 0.9), (0., 1.2))
    let f0 = noteHz(p.note)
    let hz = Math.max(30., Math.min(16000., bright * f0)) / Math.pow(f0 / 440., ~exp=track)
    put(m, "F_Track", track)
    put(m, "Tune_CutReference", 0.)
    put(m, "Cutoff", FilterTypes.cutoffOfHz(~filterType=t, hz))
    put(
      m,
      "Resonance",
      switch family {
      | Comb => within(r, w, (0.2, 0.5), (0.1, 0.75))
      | Formant => within(r, w, (0.3, 0.6), (0.2, 0.85))
      | _ => within(r, w, (0.05, 0.35), (0., 0.85))
      },
    )
    // (the lowpasses that morph are let lean towards a bandpass, no further)
    if morphs->Array.includes(name) {
      put(m, "F_Morph", family == Low ? within(r, w, (0., 0.15), (0., 0.4)) : r())
    }
    // a second filter beside the first (one after it, both ringing, is too loud or too quiet
    // to foresee)
    if w > 0.4 && chance(r, 0.6 * (w - 0.4)) {
      put(m, "F_Double", 1.)
      put(m, "F_Split", within(r, w, (0.2, 0.5), (0., 1.)))
      put(m, "F_Mix", 0.5)
      if w > 0.6 && chance(r, 0.5) {
        let (other, _) = tiered(r, w, choices)
        put(m, "Filter2", Int.toFloat(FilterTypes.index(other)))
      }
    }
    if chance(r, 0.15 + 0.35 * w) {
      put(m, "F_Drive", within(r, w, (0.05, 0.25), (0., 0.8)))
    }
  }
}

let filterEnvIds = [
  "F_EnvMod",
  "F_Attack",
  "F_Hold",
  "F_Decay1",
  "F_Breakpoint",
  "F_Decay2",
  "F_Sustain",
  "F_Release",
  "F_VeloSens",
  "Curve_Filter_Decay",
]

let filterEnv = (r, w, k: kind, m) => {
  reset(m, filterEnvIds)
  let p = profile(k)
  // (F_EnvMod's ±1 is ±8 octaves)
  put(m, "F_EnvMod", within(r, w, p.envOctaves, (-3., 6.)) / 8.)
  put(m, "F_Attack", logWithin(r, w, p.filterAttack, (0.2, 3000.)))
  put(m, "F_Breakpoint", 1.)
  put(m, "F_Decay2", logWithin(r, w, p.filterDecay, (30., 8000.)))
  put(m, "F_Sustain", within(r, w, (0., 0.35), (0., 1.)))
  put(m, "F_Release", logBetween(r, 100., 1200.))
  put(m, "F_VeloSens", between(r, 0.1, 0.6))
  put(m, "Curve_Filter_Decay", within(r, w, (0., 0.4), (-0.5, 0.8)))
}

// A lowpass's cutoff raised, if need be, until a saw at the audition note keeps at least `floor`
// dB through it where its envelope takes it lowest: one far under the note, or closed further by
// its envelope, would leave little to hear.
let liftCutoff = (m, ~note, ~floor) => {
  let t = Float.toInt(get(m, "Filter"))
  if t != 0 && familyOf(t) == Low {
    let lowest = () => Math.log2(cutoffAt(m, ~note) / noteHz(note)) + Math.min(0., 8. * get(m, "F_EnvMod"))
    while filterLevel(LevelTables.saw, t, lowest()) < floor && get(m, "Cutoff") < 1. {
      let hz = FilterTypes.cutoffHz(~filterType=t, get(m, "Cutoff"))
      put(m, "Cutoff", Math.min(1., FilterTypes.cutoffOfHz(~filterType=t, hz * Math.pow(2., ~exp=0.25)) + 1e-4))
    }
  }
}

let makeFilter = (r, w, k, m) => {
  filterType(r, w, k, m)
  filterEnv(r, w, k, m)
  liftCutoff(m, ~note=profile(k).note, ~floor=-8. - 10. * w)
}

//==============================================================================
// Envelopes

let ampEnvIds = ["Attack", "Hold", "Decay1", "Breakpoint", "Decay2", "Sustain", "Release", "Curve_Amp_Decay", "Curve_Amp_Release", "VeloSens"]

let ampEnv = (r, w, k: kind, m) => {
  reset(m, ampEnvIds)
  let p = profile(k)
  put(m, "Attack", logWithin(r, w, p.attack, (0.2, 4000.)))
  put(m, "Decay2", logWithin(r, w, p.decay, (60., 15000.)))
  put(m, "Sustain", within(r, w, p.sustain, (0., 1.)))
  put(m, "Release", logWithin(r, w, p.release, (15., 8000.)))
  if chance(r, 0.1 + 0.35 * w) {
    put(m, "Breakpoint", between(r, 0.25, 0.7))
    put(m, "Decay1", logBetween(r, 30., 400.))
  }
  put(m, "Curve_Amp_Decay", within(r, w, (0., 0.35), (-0.6, 0.8)))
  put(m, "Curve_Amp_Release", within(r, w, (0., 0.3), (-0.5, 0.7)))
  put(m, "VeloSens", between(r, 0.4, 0.8))
}

let pitchEnvIds = ["PEnv_On", "PEnv_Start", "PEnv_Attack", "PEnv_Peak", "PEnv_Decay", "PEnv_Sustain", "PEnv_Release"]

// a sweep to the note, mostly from above
let pitchEnv = (r, w, k: kind, m) => {
  reset(m, pitchEnvIds)
  if chance(r, 0.5 * w + (k == #bass || k == #pluck ? 0.08 : 0.)) {
    let st = within(r, w, (2., 12.), (1., 36.)) * (chance(r, 0.75) ? 1. : -1.)
    put(m, "PEnv_On", 1.)
    put(m, "PEnv_Start", st)
    put(m, "PEnv_Attack", 0.2)
    put(m, "PEnv_Peak", st)
    put(m, "PEnv_Decay", logWithin(r, w, (15., 80.), (10., 2500.)))
    put(m, "PEnv_Sustain", 0.)
    put(m, "PEnv_Release", 0.)
  }
}

let monoIds = ["PolyMode", "Glide"]

let mono = (r, w, k: kind, m) => {
  reset(m, monoIds)
  if chance(r, profile(k).mono) {
    put(m, "PolyMode", 2.)
    put(m, "Glide", logWithin(r, w, (15., 80.), (5., 400.)))
  }
}

let makeEnv = (r, w, k, m) => {
  ampEnv(r, w, k, m)
  pitchEnv(r, w, k, m)
  mono(r, w, k, m)
}

//==============================================================================
// Effects

let driveIds = ["Sat_Type", "Sat_Mode", "Sat_Pregain", "Sat_Postgain", "Sat_Drive", "Sat_Tone", "Sat_Character"]

// the distortion's types by threshold: soft ones first, folds and crushers last
let driveTypes = [
  (2., 0., 2.),
  (6., 0., 1.5),
  (7., 0., 1.2),
  (8., 0.1, 1.),
  (9., 0.25, 0.8),
  (4., 0.3, 0.8),
  (1., 0.4, 0.6),
  (10., 0.4, 0.6),
  (13., 0.45, 0.5),
  (11., 0.5, 0.5),
  (14., 0.5, 0.4),
  (3., 0.6, 0.5),
  (12., 0.65, 0.5),
  (15., 0.75, 0.4),
  (16., 0.8, 0.3),
]

// A distortion's type and gains, by the ids of its copy (`id`): its pregain made up for after,
// as far as that type changes a usual voice's level, and the models' own knobs near their
// middles (their tone and character are filters on some models, which would leave little).
let distortion = (r, w, m, id) => {
  let t = tiered(r, w, driveTypes)
  let pregain = within(r, w, (2., 9.), (0., 24.))
  put(m, id("Sat_Type"), t)
  put(m, id("Sat_Pregain"), pregain)
  put(m, id("Sat_Postgain"), neutralPostgain(Float.toInt(t), pregain))
  if t >= Int.toFloat(DistTypes.firstModel) {
    put(m, id("Sat_Drive"), within(r, w, (0.4, 0.6), (0.25, 0.8)))
    put(m, id("Sat_Tone"), within(r, w, (0.45, 0.55), (0.35, 0.65)))
    put(m, id("Sat_Character"), 0.25 * r() * w)
  }
}

// the voice's own distortion, after the filter (or before it, now and then when wild)
let drive = (r, w, k: kind, m) => {
  reset(m, driveIds)
  let odds = w < 0.05 ? 0. : 0.08 + 0.45 * w + (k == #bass ? 0.15 : k == #lead ? 0.1 : 0.)
  if chance(r, odds) {
    distortion(r, w, m, id => id)
    put(m, "Sat_Mode", w > 0.5 && chance(r, 0.3) ? 2. : 1.)
  }
}

// One effect's settings, by its copy's parameters.
let effectSettings = (r, w, m, e: FxRack.effect, ~lane=false) => {
  let s = (first, v) => put(m, FxRack.id(e, first), v)
  let level = (tame, whole) => ampOfDb(within(r, w, tame, whole))
  switch e.kind {
  | #chorus =>
    s("C_Mode", tiered(r, w, [(1., 0., 2.), (4., 0., 1.), (2., 0.5, 0.5), (3., 0.6, 0.5)]))
    s("C_Stereo", chance(r, 0.5) ? 1. : 2.)
    s("C_Voices", Math.floor(within(r, w, (2., 3.99), (2., 5.99))))
    s("C_Rate", logWithin(r, w, (0.1, 0.6), (0.02, 4.)))
    s("C_MinDelay", logWithin(r, w, (3., 8.), (0.5, 30.)))
    s("C_Depth", logWithin(r, w, (2., 8.), (0.5, 25.)))
    s("C_Feedback", within(r, w, (0., 0.2), (-0.5, 0.5)))
    s("C_Mix", within(r, w, (0.25, 0.45), (0.2, 0.65)))
  | #delay =>
    // in sixteenths: a dotted eighth, a quarter, an eighth, or apart on each side
    let (left, right) = tiered(
      r,
      w,
      [((3., 3.), 0., 2.), ((4., 4.), 0., 1.), ((2., 2.), 0., 0.6), ((3., 4.), 0., 1.), ((4., 6.), 0.2, 0.7), ((6., 6.), 0.2, 0.6), ((1., 1.), 0.5, 0.3), ((5., 7.), 0.6, 0.4)],
    )
    s("D_Unit", 5.)
    s("D_Quantize", 0.)
    s("D_LengthL", left)
    s("D_LengthR", right)
    let feedback = within(r, w, (0.2, 0.45), (0.1, 0.85))
    s("D_FeedbackL", feedback)
    s("D_FeedbackR", feedback)
    s("D_LP", within(r, w, (0.45, 0.75), (0.2, 1.)))
    s("D_HP", within(r, w, (0., 0.25), (0., 0.6)))
    s("D_ReverseL", 0.)
    s("D_ReverseR", w > 0.75 && chance(r, 0.25) ? 1. : 0.)
    s("D_Rotation", 0.)
    s("D_InputPan", 0.5)
    s("D_Dry", 1.)
    s("D_Wet", level((-20., -12.), (-18., -4.)))
  | #reverb =>
    s("R_Size", logWithin(r, w, (25., 60.), (10., 200.)))
    s("R_Length", logWithin(r, w, (1., 3.), (0.4, 15.)))
    s("R_Dullness", between(r, 0.4, 0.8))
    s("R_Brightness", between(r, 0.1, 0.4))
    s("R_Predelay", between(r, 0., 30.))
    s("R_Dry", 1.)
    s("R_Wet", level((-20., -12.), (-18., -8.)))
  | #space =>
    s("Rv_Model", tiered(r, w, [(0., 0., 2.), (1., 0., 1.5), (4., 0., 1.), (2., 0.5, 0.7), (3., 0.5, 0.7)]))
    s("Rv_Size", within(r, w, (0.3, 0.7), (0.05, 1.)))
    s("Rv_Decay", within(r, w, (0.35, 0.6), (0.15, 0.95)))
    s("Rv_Damp", between(r, 0.6, 0.9))
    s("Rv_Predelay", between(r, 0., 30.))
    s("Rv_Mod", within(r, w, (0.2, 0.4), (0., 1.)))
    s("Rv_Mix", within(r, w, (0.12, 0.25), (0.1, 0.6)))
  | #ambience =>
    s("Am_Model", pick(r, [0., 1., 2.]))
    s("Am_Size", within(r, w, (0.1, 0.4), (0.05, 0.9)))
    s("Am_Time", within(r, w, (0., 0.4), (0., 1.)))
    s("Am_Mix", within(r, w, (0.15, 0.35), (0.1, 0.6)))
  | #compressor =>
    // a single band's glue (three bands, squashed up as well as down, lift a quiet sound too far
    // for the output gain to follow)
    s("Cp_Bands", 0.)
    s("Cp_Depth", within(r, w, (0.3, 0.6), (0.3, 0.9)))
    s("Cp_Mix", 1.)
    s("Cp_Attack", between(r, 0.4, 0.7))
    s("Cp_Release", between(r, 0.4, 0.6))
    s("Cp_InGain", between(r, 0., 3.))
  | #flanger =>
    s("Fl_Rate", within(r, w, (0.2, 0.45), (0.05, 0.85)))
    s("Fl_Depth", between(r, 0.3, 0.8))
    s("Fl_Delay", within(r, w, (0.3, 0.6), (0.1, 0.9)))
    s("Fl_Feedback", within(r, w, (0.15, 0.4), (-0.6, 0.6)))
    s("Fl_Mix", within(r, w, (0.25, 0.45), (0.2, 0.6)))
  | #phaser =>
    s("Ph_Rate", within(r, w, (0.2, 0.45), (0.05, 0.85)))
    s("Ph_Depth", between(r, 0.4, 0.85))
    s("Ph_Freq", between(r, 0.35, 0.65))
    s("Ph_Feedback", within(r, w, (0.1, 0.5), (-0.85, 0.85)))
    s("Ph_Stages", tiered(r, w, [(1., 0., 1.), (2., 0., 1.), (3., 0., 0.7), (4., 0.4, 0.5), (5., 0.6, 0.4)]))
    s("Ph_Mix", within(r, w, (0.3, 0.5), (0.2, 0.8)))
  | #filter =>
    // a lowpass leaning towards a bandpass (morphed no further: a highpass would leave little of
    // most notes), or when wild a formant or a comb
    let types = [("SVF LP > BP > HP", 0., 1.), ("L/B/H 24 (morph)", 0., 1.), ("ladder", 0., 1.), ("formant", 0.5, 0.6), ("comb", 0.7, 0.4)]
    s("Ff_Type", Int.toFloat(FilterTypes.index(tiered(r, w, types))))
    s("Ff_Cutoff", within(r, w, (0.6, 0.85), (0.5, 0.95)))
    s("Ff_Resonance", within(r, w, (0.1, 0.4), (0., 0.75)))
    s("Ff_Morph", within(r, w, (0., 0.2), (0., 0.35)))
    s("Ff_Drive", within(r, w, (0., 0.2), (0., 0.6)))
    s("Ff_Mix", between(r, 0.5, 1.))
  | #bode if lane =>
    // in each voice: partials moved by a small part of the note (no Hz, and a voice has no
    // echoes): a shine, or wild, a clang
    let ratio = logWithin(r, w, (0.01, 0.05), (0.005, 0.5))
    s("Bd_Shift", 0.)
    s("Bd_Ratio", Math.cbrt(ratio / 2.))
    s("Bd_Mode", tiered(r, w, [(2., 0., 2.), (0., 0., 1.), (1., 0.3, 0.6), (3., 0.7, 0.4)]))
    s("Bd_Mix", within(r, w, (0.2, 0.4), (0.15, 0.55)))
  | #bode =>
    s("Bd_Shift", sign(r) * within(r, w, (0.08, 0.2), (0.03, 0.7)))
    s("Bd_Mode", tiered(r, w, [(0., 0., 1.), (1., 0., 1.), (2., 0., 1.), (3., 0.7, 0.5)]))
    s("Bd_Feedback", within(r, w, (0., 0.3), (0., 0.8)))
    s("Bd_Delay", between(r, 0.3, 0.8))
    s("Bd_Mix", within(r, w, (0.2, 0.4), (0.15, 0.7)))
  | #convolve =>
    // room, hall, plate, spring; then cathedral, metal tank, swell, noise bloom, telephone
    s("Cv_Impulse", tiered(r, w, [(0., 0., 1.5), (1., 0., 1.5), (3., 0., 1.), (4., 0.2, 0.8), (2., 0.4, 0.6), (7., 0.6, 0.5), (9., 0.6, 0.5), (10., 0.7, 0.4), (8., 0.8, 0.3)]))
    s("Cv_Mix", within(r, w, (0.1, 0.3), (0.08, 0.5)))
    s("Cv_LowCut", between(r, 0.1, 0.35))
  | #air =>
    s("Ai_Air", within(r, w, (0.52, 0.6), (0.45, 0.68)))
    s("Ai_Body", between(r, 0.45, 0.55))
  | #utility =>
    s("Ut_Width", within(r, w, (1.1, 1.35), (0.8, 1.6)))
    s("Ut_BassMono", PorridgeParams.bassMonoValue(between(r, 80., 160.)))
  | #distortion => distortion(r, w, m, first => FxRack.id(e, first))
  // (the voice lane's own: each follows the note)
  | #resonator =>
    // harmonic, odd, fifths, bar, bell, membrane: a string's first
    s("Rs_Model", tiered(r, w, [(0., 0., 2.), (3., 0., 1.), (1., 0.3, 0.6), (4., 0.3, 0.8), (2., 0.5, 0.5), (5., 0.6, 0.5)]))
    s("Rs_Pitch", w > 0.7 && chance(r, 0.3) ? pick(r, [-12., 7., 12.]) : 0.)
    s("Rs_Decay", PorridgeParams.expPos(10., 10000., logWithin(r, w, (300., 1500.), (100., 3000.))))
    s("Rs_Bright", between(r, 0.3, 0.7))
    s("Rs_Mix", within(r, w, (0.25, 0.5), (0.2, 0.6)))
  | #octaver =>
    s("Oc_Sub", within(r, w, (0.3, 0.6), (0.1, 0.9)))
    s("Oc_Up", within(r, w, (0., 0.2), (0., 0.6)))
    s("Oc_Dry", 1.)
  // (random patches add no EQ)
  | #eq => ()
  }
}

// What the rack can be given: (kind, threshold, weight, is a space). Rooms and reverbs are
// spaces, of which a patch gets one (two when wild).
let rackChoices = (k: kind) => [
  (#chorus, 0., k == #pad ? 2. : k == #keys ? 1.5 : 1., false),
  (#delay, 0., k == #pluck ? 2. : k == #lead ? 1.5 : 1., false),
  (#space, 0., 1.2, true),
  (#reverb, 0., 0.6, true),
  (#ambience, 0., 0.6, true),
  (#compressor, 0.2, 0.4, false),
  (#air, 0.25, 0.3, false),
  (#phaser, 0.3, 0.6, false),
  (#utility, 0.3, 0.3, false),
  (#convolve, 0.3, 0.4, true),
  (#flanger, 0.35, 0.5, false),
  (#filter, 0.4, 0.4, false),
  (#distortion, 0.55, 0.4, false),
  (#bode, 0.6, 0.4, false),
]

let isSpace = (kind: FxRack.kind) =>
  switch kind {
  | #space | #reverb | #ambience | #convolve => true
  | _ => false
  }

// where a kind of effect goes in the rack: drive and tone first, echoes and spaces last
let rank = (kind: FxRack.kind) =>
  switch kind {
  | #distortion => 0
  | #filter => 1
  | #compressor => 2
  | #phaser | #flanger | #chorus | #bode => 3
  | #utility => 4
  | #eq | #air => 5
  | #delay => 6
  | #convolve => 7
  | #space | #reverb | #ambience => 8
  | #resonator | #octaver => 1
  }

let rackOf = m => FxRack.read(get(m, ...))
let laneOf = m => FxRack.readLane(get(m, ...))

// The rack with one more effect of this kind (if it has room), in its place, set up.
let addEffect = (r, w, m, kind: FxRack.kind, ~shuffled=false) =>
  switch FxRack.free(rackOf(m), ~lane=laneOf(m), kind) {
  | Some(e) =>
    let rack = rackOf(m)
    let at = shuffled
      ? Float.toInt(r() * Int.toFloat(Array.length(rack) + 1))
      : rack->Array.findIndex(x => rank(x.kind) > rank(kind))
    let at = at < 0 ? Array.length(rack) : at
    let next = Array.concat(Array.concat(rack->Array.slice(~start=0, ~end=at), [e]), rack->Array.slice(~start=at))
    FxRack.values(get(m, ...), next)->Array.forEach(((id, v)) => put(m, id, v))
    let e = FxRack.placed(next)->Array.getUnsafe(at)
    put(m, FxRack.switchId(e), FxRack.onValue(e))
    effectSettings(r, w, m, e)
    true
  | None => false
  }

// the next kind of effect for the rack as it is, if any may go in
let nextEffect = (r, w, k, m) => {
  let rack = rackOf(m)
  let spaces = rack->Array.filter(e => isSpace(e.kind))->Array.length
  let options =
    rackChoices(k)->Array.filter(((kind, from, weight, space)) =>
      w >= from && weight > 0. && !(rack->Array.some(e => e.kind == kind)) && (!space || spaces < (w > 0.75 ? 2 : 1))
    )
  options == [] ? None : Some(weighted(r, options->Array.map(((kind, _, weight, _)) => (kind, weight))))
}

// What the voice lane can be given: (kind, threshold, weight). Each note runs its own copy, so
// its key, envelopes and own random values move it for that note alone.
let laneChoices = (k: kind) => [
  (#phaser, 0., 1.),
  (#filter, 0., 0.8),
  (#flanger, 0.2, 0.7),
  (#octaver, 0.3, k == #bass ? 1.2 : k == #lead ? 0.6 : 0.3),
  (#resonator, 0.3, k == #pluck || k == #bell || k == #keys ? 1.2 : 0.5),
  (#bode, 0.35, 0.6),
  (#distortion, 0.5, 0.5),
]

let laneIds = Array.concat(
  Array.fromInitializer(~length=PorridgeParams.laneSlots, i => PorridgeParams.laneId(i + 1)),
  ["VL_FilterAt", "VL_AmpAt"],
)

// An effect in the voice lane, set up: as in the rack, and what makes each note's its own (the
// phaser's and flanger's sweeps starting at a random point and following the key, the flanger
// now and then tuned to the note, so that it rings there; the filter following the key). A
// lane with a resonator goes before the amp envelope, which damps it as a note ends.
let addToLane = (r, w, m, kind: FxRack.kind) =>
  FxRack.free(rackOf(m), ~lane=laneOf(m), ~forLane=true, kind)->Option.forEach(e => {
    let lane = Array.concat(laneOf(m), [e])
    let ampAt = lane->Array.some(x => x.kind == #resonator) ? Array.length(lane) : 0
    FxRack.laneValues(get(m, ...), lane, {filterAt: 0, ampAt})->Array.forEach(((id, v)) => put(m, id, v))
    let e = FxRack.placed(lane, ~lane=true)->Array.getUnsafe(Array.length(lane) - 1)
    put(m, FxRack.switchId(e), FxRack.onValue(e))
    effectSettings(r, w, m, e, ~lane=true)
    let s = (first, v) => put(m, FxRack.id(e, first), v)
    switch kind {
    | #phaser =>
      // (its feedback held back: in every voice, a ringing phaser is louder than the estimate
      // can follow)
      s("Ph_Feedback", Math.max(-0.6, Math.min(0.6, get(m, FxRack.id(e, "Ph_Feedback")))))
      s("Ph_PhaseRand", 1.)
      s("Ph_RateTrack", within(r, w, (0.2, 0.5), (0., 1.)))
      s("Ph_Track", between(r, 0.3, 1.))
    | #flanger =>
      s("Fl_PhaseRand", 1.)
      s("Fl_RateTrack", within(r, w, (0.2, 0.5), (0., 1.)))
      if chance(r, 0.3 + 0.3 * w) {
        // (a delay of middle C's period, followed by each note's)
        s("Fl_Track", 1.)
        s("Fl_Delay", PorridgeParams.expPos(0.1, 20., 1000. / 261.63))
        s("Fl_Depth", within(r, w, (0.03, 0.08), (0.02, 0.2)))
        s("Fl_Feedback", within(r, w, (0.4, 0.6), (0.3, 0.7)) * (chance(r, 0.8) ? 1. : -1.))
      }
    | #filter => s("Ff_Track", between(r, 0.5, 1.))
    | _ => ()
    }
  })

// Now and then (the likelier the wilder) an effect in every voice; wild, two of different kinds.
let voiceFx = (r, w, k, m) => {
  laneOf(m)->Array.forEach(e => put(m, FxRack.switchId(e), 0.))
  reset(m, laneIds)
  if w >= 0.15 && chance(r, 0.1 + 0.45 * (w - 0.15) / 0.85) {
    let count = w > 0.75 && chance(r, 0.3) ? 2 : 1
    for _ in 1 to count {
      let options = laneChoices(k)->Array.filter(((kind, from, _)) =>
        w >= from &&
        !(laneOf(m)->Array.some(e => e.kind == kind)) &&
        FxRack.free(rackOf(m), ~lane=laneOf(m), ~forLane=true, kind) != None
      )
      if options != [] {
        addToLane(r, w, m, weighted(r, options->Array.map(((kind, _, weight)) => (kind, weight))))
      }
    }
  }
}

let makeFx = (r, w, k: kind, m) => {
  drive(r, w, k, m)
  // an empty rack, then up to five effects (pads and bells always get a space)
  FxRack.values(get(m, ...), [])->Array.forEach(((id, v)) => put(m, id, v))
  let count = w < 0.05 ? 0 : Math.Int.min(5, Float.toInt(Math.round(w * (1. + 3. * r()) + 0.3)))
  let count = (k == #pad || k == #bell) && w >= 0.05 ? Math.Int.max(1, count) : count
  let shuffled = w > 0.7 && chance(r, 0.3)
  if (k == #pad || k == #bell) && count > 0 {
    addEffect(r, w, m, weighted(r, [(#space, 2.), (#reverb, 1.), (#convolve, w)]), ~shuffled)->ignore
  }
  let tries = ref(0)
  while Array.length(rackOf(m)) < count && tries.contents < 8 {
    tries := tries.contents + 1
    nextEffect(r, w, k, m)->Option.forEach(kind => addEffect(r, w, m, kind, ~shuffled)->ignore)
  }
  voiceFx(r, w, k, m)
}

//==============================================================================
// Modulation

let lfoIds = n =>
  [
    "Unit",
    "Shape",
    "Speed",
    "Quantize",
    "Sync",
    "Fade",
    "Delay",
    "Slew",
    "Steps",
    "OneShot",
    "Pitch",
    "Cutoff_1",
    "Cutoff_2",
    "Resonance",
    "Pan",
  ]->Array.map(p => `LFO_${Int.toString(n)}_${p}`)
let modEnv2Ids = ["M2_Attack", "M2_Hold", "M2_Decay1", "M2_Breakpoint", "M2_Decay2", "M2_Sustain", "M2_Release", "M2_VeloSens"]
let modIds = Lazy.make(() =>
  [lfoIds(1), lfoIds(2), ["LFO_1_2", "LFO_2_1"], modEnv2Ids, ModMatrix.slotNumbers->Array.flatMap(ModMatrix.slotIds)]->Array.flat
)

let sourceValue = key => Int.toFloat(ModMatrix.sourceIndex(key))
let usedSlots = m => ModMatrix.slotNumbers->Array.filter(k => get(m, ModMatrix.sourceId(k)) != 0.)
let freeSlot = m => ModMatrix.slotNumbers->Array.find(k => get(m, ModMatrix.sourceId(k)) == 0.)
let sourceUsed = (m, key) =>
  usedSlots(m)->Array.some(k =>
    get(m, ModMatrix.sourceId(k)) == sourceValue(key) || get(m, ModMatrix.viaId(k)) == sourceValue(key)
  )

// A routing in the first free slot of the matrix, unless the same one is there already.
let connect = (m, source, target, amount, ~via=?) => {
  let t = Int.toFloat(SlotParams.targetIndex(target))
  let v = via->Option.mapOr(0., sourceValue)
  let same = usedSlots(m)->Array.some(k =>
    get(m, ModMatrix.sourceId(k)) == sourceValue(source) &&
    get(m, ModMatrix.targetId(k)) == t &&
    get(m, ModMatrix.viaId(k)) == v
  )
  switch freeSlot(m) {
  | Some(k) if t > 0. && !same =>
    put(m, ModMatrix.sourceId(k), sourceValue(source))
    put(m, ModMatrix.targetId(k), t)
    put(m, ModMatrix.amountId(k), amount)
    put(m, ModMatrix.viaId(k), v)
    true
  | _ => false
  }
}

// An LFO's rate: Hz, or a count of a tempo unit (LFO_n_Unit: 5 sixteenths, 7 eighth triplets,
// 8 eighths, 11 quarters ...).
type rate = Hz(float) | Beats(float, float)

let lfoFree = (m, n) =>
  !sourceUsed(m, `lfo${Int.toString(n)}`) &&
  ["Pitch", "Cutoff_1", "Cutoff_2", "Resonance", "Pan"]->Array.every(p =>
    get(m, `LFO_${Int.toString(n)}_${p}`) == 0.
  )

// A free LFO (the preferred one first) set up this way, and its source's key. Shapes: 0 sine,
// 1 saw, 2 square, 3 triangle, 4 smooth random, 5 stepping random; modes: 0 per note,
// 1 global and reset by each note, 2 global and free.
let takeLfo = (m, ~prefer=1, ~rate, ~shape, ~mode) =>
  [prefer, 3 - prefer]
  ->Array.find(n => lfoFree(m, n))
  ->Option.map(n => {
    reset(m, lfoIds(n))
    let p = `LFO_${Int.toString(n)}_`
    switch rate {
    | Hz(hz) if hz < 0.5 =>
      put(m, p ++ "Unit", 2.)
      put(m, p ++ "Speed", 1. / hz)
    | Hz(hz) =>
      put(m, p ++ "Unit", 1.)
      put(m, p ++ "Speed", 100. / hz)
    | Beats(unit, count) =>
      put(m, p ++ "Unit", unit)
      put(m, p ++ "Speed", count)
      put(m, p ++ "Quantize", 1.)
    }
    put(m, p ++ "Shape", shape)
    put(m, p ++ "Sync", mode)
    (n, `lfo${Int.toString(n)}`)
  })

// Mod env 2, falling from its peak (the first routing to use it sets it up; the others share it).
let takeModEnv = (m, ~attack, ~decay) => {
  if !sourceUsed(m, "modEnv2") {
    reset(m, modEnv2Ids)
    put(m, "M2_Attack", attack)
    put(m, "M2_Decay1", 10.)
    put(m, "M2_Breakpoint", 1.)
    put(m, "M2_Decay2", decay)
    put(m, "M2_Sustain", 0.)
    put(m, "M2_Release", Math.max(50., decay * 0.5))
    put(m, "M2_VeloSens", 0.3)
  }
  "modEnv2"
}

let filtered = m => get(m, "Filter") != 0.

// the parameters of the rack's effects that a routing can move (mixes and tones, not levels:
// a delay's wet knob goes to +30 dB)
let fxTargets = m =>
  rackOf(m)
  ->Array.flatMap(e =>
    ["Fl_Mix", "Ph_Freq", "Ff_Cutoff", "Ff_Morph", "Bd_Shift", "Rv_Mix", "C_Mix", "Am_Mix", "Cv_Mix"]->Array.map(f =>
      FxRack.id(e, f)
    )
  )
  ->Array.filter(id => rackOf(m)->Array.some(e => FxRack.params(e)->Array.includes(id)) && SlotParams.targetOfParam(id) > 0)

// the parameters of the voice lane's effects that a routing can move, each note its own (their
// tones and depths, not feedback, which can ring on, nor a distortion's gains)
let laneTargets = m =>
  laneOf(m)
  ->Array.flatMap(e =>
    ["Ph_Freq", "Ph_Depth", "Fl_Mix", "Fl_Depth", "Ff_Cutoff", "Ff_Morph", "Bd_Ratio", "Bd_Mix", "Rs_Bright", "Rs_Decay", "Oc_Sub", "Oc_Up"]->Array.map(f =>
      FxRack.id(e, f)
    )
  )
  ->Array.filter(id => laneOf(m)->Array.some(e => FxRack.params(e)->Array.includes(id)) && SlotParams.targetOfParam(id) > 0)

// A kind of routing: the wildness it needs, how likely it is for each kind of patch, whether the
// patch can take it, and what it adds (false if it couldn't).
type route = {
  key: string,
  from: float,
  weight: kind => float,
  fits: Bank.values => bool,
  add: (rng, float, Bank.values) => bool,
}

let always = _ => true
let evenly = _ => 1.

let routes: array<route> = [
  // a vibrato that fades in, or comes in with the mod wheel
  {
    key: "vibrato",
    from: 0.,
    weight: k => k == #lead ? 2. : k == #pad || k == #brass ? 1.5 : 0.6,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=1, ~rate=Hz(within(r, w, (4.5, 6.5), (3., 9.))), ~shape=0., ~mode=0.) {
      | Some((n, lfo)) =>
        put(m, `LFO_${Int.toString(n)}_Fade`, logBetween(r, 200., 1200.))
        chance(r, 0.4)
          ? connect(m, lfo, "finePitch", within(r, w, (0.2, 0.4), (0.2, 1.)), ~via="modWheel")
          : connect(m, lfo, "finePitch", within(r, w, (0.06, 0.18), (0.06, 0.6)))
      | None => false
      },
  },
  // harder notes brighter
  {
    key: "velocity",
    from: 0.,
    weight: evenly,
    fits: filtered,
    add: (r, w, m) => connect(m, "velocity", "Cutoff", within(r, w, (0.05, 0.15), (0.05, 0.35))),
  },
  // each note a little out of tune, or a little brighter or darker, than the last
  {
    key: "note drift",
    from: 0.,
    weight: evenly,
    fits: always,
    add: (r, w, m) => connect(m, "random", "finePitch", within(r, w, (0.02, 0.06), (0.02, 0.4))),
  },
  {
    key: "note tone",
    from: 0.,
    weight: _ => 0.8,
    fits: filtered,
    add: (r, w, m) => connect(m, "random", "Cutoff", within(r, w, (0.02, 0.07), (0.02, 0.25))),
  },
  // a slow sweep of the cutoff, and of the stereo position with it
  {
    key: "sweep",
    from: 0.,
    weight: k => k == #pad ? 2. : 1.,
    fits: filtered,
    add: (r, w, m) =>
      switch takeLfo(
        m,
        ~prefer=2,
        ~rate=Hz(logWithin(r, w, (0.05, 0.4), (0.03, 1.5))),
        ~shape=pick(r, [0., 3., 4.]),
        ~mode=2.,
      ) {
      | Some((_, lfo)) =>
        if chance(r, 0.5) {
          connect(m, lfo, "pan", within(r, w, (0.1, 0.35), (0.1, 0.8)))->ignore
        }
        connect(m, lfo, "Cutoff", within(r, w, (0.03, 0.1), (0.05, 0.4)))
      | None => false
      },
  },
  {
    key: "aftertouch",
    from: 0.,
    weight: _ => 0.5,
    fits: filtered,
    add: (r, _, m) => connect(m, "aftertouch", "Cutoff", between(r, 0.1, 0.25)),
  },
  // the voice lane's effect moved by something of each note's own: a random value, its velocity,
  // its key, an envelope
  {
    key: "voice fx",
    from: 0.,
    weight: _ => 1.5,
    fits: m => laneTargets(m) != [],
    add: (r, w, m) => {
      let target = pick(r, laneTargets(m))
      let amount = within(r, w, (0.05, 0.15), (0.05, 0.35))
      switch weighted(r, [("random", 2.), ("velocity", 1.5), ("modEnv2", 1.), ("key", 0.5)]) {
      | "modEnv2" =>
        let env = takeModEnv(m, ~attack=logBetween(r, 0.2, 300.), ~decay=logWithin(r, w, (300., 2000.), (60., 6000.)))
        connect(m, env, target, amount * sign(r))
      | source => connect(m, source, target, amount * sign(r))
      }
    },
  },
  // pulse width modulation
  {
    key: "pwm",
    from: 0.,
    weight: evenly,
    fits: m => hasWidth(get(m, "O1_Waveform")),
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Hz(logWithin(r, w, (0.3, 2.), (0.1, 8.))), ~shape=3., ~mode=0.) {
      | Some((_, lfo)) => connect(m, lfo, "O1_PWM_W", within(r, w, (0.05, 0.15), (0.05, 0.3)))
      | None => false
      },
  },
  // the cutoff in time with the music
  {
    key: "wobble",
    from: 0.3,
    weight: k => k == #bass ? 1.5 : 0.7,
    fits: filtered,
    add: (r, w, m) => {
      let (unit, count) = pick(r, [(8., 1.), (8., 2.), (11., 1.), (7., 1.), (5., 2.)])
      switch takeLfo(m, ~prefer=2, ~rate=Beats(unit, count), ~shape=pick(r, [0., 3., 2.]), ~mode=1.) {
      | Some((_, lfo)) => connect(m, lfo, "Cutoff", within(r, w, (0.1, 0.25), (0.1, 0.5)))
      | None => false
      }
    },
  },
  {
    key: "tremolo",
    from: 0.3,
    weight: k => k == #keys ? 1. : 0.5,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~rate=Hz(between(r, 3., 8.)), ~shape=pick(r, [0., 3.]), ~mode=0.) {
      | Some((_, lfo)) => connect(m, lfo, "volume", within(r, w, (0.15, 0.3), (0.15, 0.6)))
      | None => false
      },
  },
  {
    key: "auto-pan",
    from: 0.3,
    weight: _ => 0.6,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~rate=Hz(logBetween(r, 0.5, 5.)), ~shape=pick(r, [0., 3.]), ~mode=0.) {
      | Some((_, lfo)) => connect(m, lfo, "pan", within(r, w, (0.3, 0.6), (0.3, 1.)))
      | None => false
      },
  },
  // a quick blip of pitch at the start of each note
  {
    key: "blip",
    from: 0.3,
    weight: k => k == #bass ? 1.2 : k == #pluck ? 1. : 0.5,
    fits: always,
    add: (r, w, m) => {
      let env = takeModEnv(m, ~attack=0.2, ~decay=logBetween(r, 15., 80.))
      connect(m, env, "pitch", within(r, w, (0.1, 0.3), (0.1, 1.)) * (chance(r, 0.7) ? 1. : -1.))
    },
  },
  // an envelope on the tone: the modulator's depth, osc 2's level or detune, the PM feedback,
  // the unison, the resonance (each by an amount that suits it: a level's knob moves fast)
  {
    key: "timbre env",
    from: 0.3,
    weight: evenly,
    fits: always,
    add: (r, w, m) => {
      let mode = mixMode(m)
      let targets = [
        modulating(mode) ? Some((depthOf(mode), (0.1, 0.3), (0.1, 0.5))) : None,
        secondSounds(m) && !modulating(mode) ? Some(("O2_Amp", (0.05, 0.1), (0.05, 0.2))) : None,
        secondSounds(m) && !modulating(mode) ? Some(("Detune", (0.01, 0.04), (0.01, 0.15))) : None,
        mode == pm || mode == pmFeedback ? Some(("PM_Feedback", (0.1, 0.3), (0.1, 0.6))) : None,
        get(m, "U_Voices") > 1. ? Some(("U_Detune", (0.03, 0.1), (0.03, 0.3))) : None,
        filtered(m) ? Some(("Resonance", (0.1, 0.2), (0.1, 0.4))) : None,
      ]->Array.filterMap(t => t)
      if targets == [] {
        false
      } else {
        let env = takeModEnv(m, ~attack=logBetween(r, 0.2, 30.), ~decay=logWithin(r, w, (150., 1500.), (30., 6000.)))
        let (target, tame, whole) = pick(r, targets)
        connect(m, env, target, within(r, w, tame, whole) * sign(r))
      }
    },
  },
  {
    key: "key pan",
    from: 0.3,
    weight: _ => 0.4,
    fits: always,
    add: (r, _, m) => connect(m, "key", "pan", between(r, 0.3, 0.7)),
  },
  // osc 2 drifting against osc 1
  {
    key: "beating",
    from: 0.3,
    weight: _ => 0.6,
    fits: m => secondSounds(m) && !modulating(mixMode(m)),
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Hz(logBetween(r, 0.1, 1.)), ~shape=pick(r, [0., 4.]), ~mode=0.) {
      | Some((_, lfo)) => connect(m, lfo, "Detune", within(r, w, (0.01, 0.04), (0.01, 0.15)))
      | None => false
      },
  },
  // an effect in the rack moving slowly
  {
    key: "fx motion",
    from: 0.3,
    weight: evenly,
    fits: m => fxTargets(m) != [],
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Hz(logBetween(r, 0.05, 1.)), ~shape=pick(r, [0., 3., 4.]), ~mode=2.) {
      | Some((_, lfo)) => connect(m, lfo, pick(r, fxTargets(m)), within(r, w, (0.1, 0.25), (0.1, 0.6)))
      | None => false
      },
  },
  // an LFO at audio rate on the cutoff or the level: a growl
  {
    key: "growl",
    from: 0.6,
    weight: k => k == #bass ? 1.2 : 0.6,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Hz(logBetween(r, 15., 60.)), ~shape=pick(r, [0., 2.]), ~mode=0.) {
      | Some((_, lfo)) =>
        filtered(m) && chance(r, 0.6)
          ? connect(m, lfo, "Cutoff", within(r, w, (0.1, 0.2), (0.1, 0.35)))
          : connect(m, lfo, "volume", within(r, w, (0.3, 0.45), (0.3, 0.6)))
      | None => false
      },
  },
  // sample & hold: a new value every sixteenth
  {
    key: "sample & hold",
    from: 0.6,
    weight: evenly,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Beats(5., 1.), ~shape=5., ~mode=1.) {
      | Some((_, lfo)) =>
        filtered(m) && chance(r, 0.7)
          ? connect(m, lfo, "Cutoff", within(r, w, (0.15, 0.3), (0.15, 0.5)))
          : connect(m, lfo, "finePitch", within(r, w, (0.3, 0.6), (0.3, 1.)))
      | None => false
      },
  },
  {
    key: "grit",
    from: 0.6,
    weight: _ => 0.6,
    fits: always,
    add: (r, w, m) =>
      filtered(m) && chance(r, 0.5)
        ? connect(m, "noise", "Cutoff", within(r, w, (0.1, 0.2), (0.1, 0.4)))
        : connect(m, "noise", "finePitch", within(r, w, (0.1, 0.25), (0.1, 0.5))),
  },
  // a long fall (or rise) in pitch
  {
    key: "laser",
    from: 0.65,
    weight: _ => 0.6,
    fits: always,
    add: (r, w, m) => {
      let env = takeModEnv(m, ~attack=0.2, ~decay=logBetween(r, 100., 800.))
      connect(m, env, "pitch", within(r, w, (0.3, 0.5), (0.3, 1.)) * (chance(r, 0.8) ? 1. : -1.))
    },
  },
  {
    key: "siren",
    from: 0.7,
    weight: _ => 0.5,
    fits: always,
    add: (r, w, m) =>
      switch takeLfo(m, ~rate=Hz(logBetween(r, 0.3, 4.)), ~shape=pick(r, [0., 3.]), ~mode=0.) {
      | Some((_, lfo)) => connect(m, lfo, "pitch", within(r, w, (0.03, 0.1), (0.03, 0.4)))
      | None => false
      },
  },
  // the modulator's depth swaying
  {
    key: "fm motion",
    from: 0.6,
    weight: evenly,
    fits: m => modulating(mixMode(m)) || mixMode(m) == pmFeedback,
    add: (r, w, m) =>
      switch takeLfo(m, ~prefer=2, ~rate=Hz(logBetween(r, 0.1, 6.)), ~shape=pick(r, [0., 3., 4.]), ~mode=0.) {
      | Some((_, lfo)) =>
        let mode = mixMode(m)
        connect(
          m,
          lfo,
          mode == pm || mode == pmFeedback ? "PM_Feedback" : depthOf(mode),
          within(r, w, (0.15, 0.3), (0.15, 0.45)),
        )
      | None => false
      },
  },
  // every note at its own interval
  {
    key: "chaos",
    from: 0.8,
    weight: _ => 0.4,
    fits: secondSounds,
    add: (r, w, m) => connect(m, "random", "Transpose", within(r, w, (0.05, 0.1), (0.05, 0.2))),
  },
]

// One more routing of a kind the patch can take, if there is one (`taken`: the kinds it has).
let addRoute = (r, w, k, m, ~taken: array<string>=[]) => {
  let left = ref(
    routes->Array.filter(route =>
      w >= route.from && route.weight(k) > 0. && !(taken->Array.includes(route.key)) && route.fits(m)
    ),
  )
  let added = ref(None)
  while added.contents == None && Array.length(left.contents) > 0 {
    let route = weighted(r, left.contents->Array.map(x => (x, x.weight(k))))
    left := left.contents->Array.filter(x => x.key != route.key)
    if route.add(r, w, m) {
      added := Some(route.key)
    }
  }
  added.contents
}

// The XY pad: Oatmeal's four routes on each axis, and its random walk.
let xyAxes = ["H", "V"]
let xyTargetId = (axis, n) => `XY_${axis}_Target_${Int.toString(n)}`
let xyDepthId = (axis, n) => `XY_${axis}_Depth_${Int.toString(n)}`
let xyIds = Array.concat(
  xyAxes->Array.flatMap(axis => [1, 2, 3, 4]->Array.flatMap(n => [xyTargetId(axis, n), xyDepthId(axis, n)])),
  ["XY_X", "XY_Y", "XY_Var_Radius", "XY_Var_Rate"],
)
let xyRouted = m => xyAxes->Array.some(axis => [1, 2, 3, 4]->Array.some(n => get(m, xyTargetId(axis, n)) != 0.))

// What the pad moves, as Oatmeal's programs route it most (the cutoff, the resonance, the pan,
// then the rest): (target, weight, whether the patch has it, the tame depths and all of them).
// Depths are -1..1 of the target's range (the cutoff's is 4 octaves either way).
let xyChoices = m => [
  ("cutoff 1", 4.8, filtered(m), (0.25, 0.5), (0.1, 1.)),
  ("resonance", 3.1, filtered(m), (0.25, 0.5), (0.1, 0.9)),
  ("pan", 2., true, (0.2, 0.4), (0.1, 0.8)),
  ("filter env mod", 1.2, filtered(m) && get(m, "F_EnvMod") != 0., (0.1, 0.25), (0.05, 0.6)),
  ("distortion", 1.3, get(m, "Sat_Type") != 0., (0.2, 0.4), (0.1, 0.8)),
  ("LFO 1 speed", 1.3, sourceUsed(m, "lfo1"), (0.3, 0.6), (0.2, 1.)),
  ("LFO 2 speed", 0.6, sourceUsed(m, "lfo2"), (0.3, 0.6), (0.2, 1.)),
  ("amp envelope speed", 0.6, true, (0.2, 0.5), (0.2, 1.)),
  ("noise amp", 0.2, get(m, "N_Amp") > 0., (0.1, 0.3), (0.1, 0.6)),
]

// Now and then the XY pad routed (half of Oatmeal's programs route it), for the Play page's pad
// to play the patch with: a route or two, more when wild, on both axes mostly; and sometimes its
// random walk, which moves the pad on its own.
let xyPad = (r, w, m) => {
  reset(m, xyIds)
  if w >= 0.03 && chance(r, 0.35 + 0.35 * w) {
    let left = ref(xyChoices(m)->Array.filter(((_, _, has, _, _)) => has))
    let count = 1 + Float.toInt(r() * (1.5 + 2.5 * w))
    let next = Dict.fromArray([("H", 1), ("V", 1)])
    for i in 0 to count - 1 {
      if left.contents != [] {
        let (target, _, _, tame, whole) = weighted(r, left.contents->Array.map(c => {
          let (_, weight, _, _, _) = c
          (c, weight)
        }))
        left := left.contents->Array.filter(((t, _, _, _, _)) => t != target)
        let axis = mod(i, 2) == 0 ? (chance(r, 0.25) ? "V" : "H") : chance(r, 0.8) ? "V" : "H"
        let n = next->Dict.get(axis)->Option.getOr(1)
        next->Dict.set(axis, n + 1)
        // (the resonance no further than 0.9 with the pad in a corner: a filter ringing on
        // past that can be far too loud)
        let depth = within(r, w, tame, whole)
        let depth = target == "resonance" ? Math.min(depth, Math.max(0.05, 0.9 - get(m, "Resonance"))) : depth
        // (by Oatmeal's own name for it, which stays put while the menu words it its own way)
        put(m, xyTargetId(axis, n), OatmealParams.xyTargets->Array.indexOf(target)->Int.toFloat)
        put(m, xyDepthId(axis, n), depth * (chance(r, 0.35) ? -1. : 1.))
      }
    }
    if chance(r, 0.25 + 0.4 * w) {
      put(m, "XY_Var_Radius", within(r, w, (0.08, 0.25), (0.03, 0.8)))
      put(m, "XY_Var_Rate", logWithin(r, w, (0.3, 2.5), (0.1, 8.)))
    }
  }
}

let makeMod = (r, w, k, m) => {
  reset(m, Lazy.get(modIds))
  let count = w < 0.03 ? 0 : Math.Int.max(1, Float.toInt(Math.round(w * (1.5 + 4. * r()))))
  let taken = []
  for _ in 1 to count {
    addRoute(r, w, k, m, ~taken)->Option.forEach(key => taken->Array.push(key))
  }
  xyPad(r, w, m)
}

//==============================================================================
// Level

// How loud a patch plays is estimated from what LevelTables has measured of the synth: the
// oscillators' levels (by wave and mix mode) and the noise's, then a note simulated every 2 ms,
// its amp envelope on what the filter lets through as its envelope moves the cutoff (for a saw's
// spectrum and for a sine's) and its distortions, and the loudest 300 ms of that. What is
// left (the unison, the rack's effects, the modes' quirks) is weighed by loudnessWeights, fitted
// to renders of random patches (tools/random-levels.mjs).

// The oscillators' and the noise's power at the output (with the output gain at 1), as a saw's
// spectrum (what's bright: saws, pulses, a drawn wave's harmonics, noise, a synced osc, a deep
// modulator) and as a sine's.
let sources = (m, ~tables: OatmealFormat.tables) => {
  let mode = mixMode(m)
  // an oscillator's power, and how much of it is pure (a sine's, or a drawn wave's fundamental)
  let power = (amp, wave, width, table) => {
    let w = get(m, wave)
    let db =
      LevelTables.waves[Float.toInt(w)]->Option.getOr(-12.) +
        (isPulse(w) ? 10. * Math.log10(Math.max(0.01, 4. * get(m, width) * (1. - get(m, width)))) : 0.)
    let p = get(m, amp) * get(m, amp) * Math.pow(10., ~exp=db / 10.)
    if isDrawn(w) {
      let (fundamental, rest) = drawnPower(table, ~width=?(w == drawnPulse ? Some(get(m, width)) : None))
      (p * (fundamental + rest), fundamental / Math.max(1e-9, fundamental + rest))
    } else {
      (p, w == 0. || w == 3. || w == triangle ? 1. : 0.)
    }
  }
  let bright = ref(0.)
  let pure = ref(0.)
  let add = ((p, sineShare), ~bright as b=false) => {
    let share = b ? 0. : sineShare
    pure := pure.contents + p * share
    bright := bright.contents + p * (1. - share)
  }
  let (p1, s1) = power("O1_Amp", "O1_Waveform", "O1_PWM_W", tables.wave1)
  let (p2, s2) = power("O2_Amp", "O2_Waveform", "O2_PWM_W", tables.wave2)
  let deep = get(m, mode == fm ? "O1_Amp" : "O2_Amp") > 0.3
  let heard = get(m, "O2_PairMix") * get(m, "O2_PairMix")
  if mode == fm {
    add((p2, s2), ~bright=deep)
  } else if mode == pm || mode == ring || mode == am {
    add((mode == pm ? p1 : p1 * 0.5, s1), ~bright=deep)
    add((p2 * heard, s2))
  } else {
    add((p1, s1), ~bright=mode == pmFeedback && get(m, "PM_Feedback") > 0.3)
    add((p2, s2), ~bright=mode == sync)
  }
  let n = get(m, "N_Amp")
  bright :=
    bright.contents +
    n * n * Math.pow(10., ~exp=(interpolate(LevelTables.noiseResonances, LevelTables.noise, get(m, "N_Resonance")) + noiseTypeDb(m)) / 10.)
  (bright.contents, pure.contents)
}

// An envelope's level (0..1) t ms into a held note, as dsp/Modulation.cmajor shapes it: the
// attack rising (2 - L) L, the hold, then decays falling in dB from the peak to the breakpoint
// and from there to the sustain (or 120 dB down), each stage's progress warped by its curve.
type envelope = {attack: float, hold: float, decay1: float, bp: float, decay2: float, sus: float, k1: float, k2: float}

let envelopeOf = (m, prefix, ~curves) => {
  let curve = id => curves == "" ? 1. : Math.pow(8., ~exp=get(m, id))
  let bp = get(m, prefix ++ "Breakpoint")
  let sus = get(m, prefix ++ "Sustain")
  {
    attack: Math.max(0.2, get(m, prefix ++ "Attack")),
    hold: get(m, prefix ++ "Hold"),
    decay1: Math.max(1., get(m, prefix ++ "Decay1")),
    bp: bp > 0.998 ? 1. : Math.max(bp, 1e-4),
    decay2: Math.max(1., get(m, prefix ++ "Decay2")),
    sus: sus > 0.998 ? 1. : sus,
    k1: curve(`Curve_${curves}_Decay1`),
    k2: curve(`Curve_${curves}_Decay`),
  }
}

let envelopeAt = (e, t) => {
  let warp = (p: float, k: float) => k * p / (1. + (k - 1.) * p)
  if t < e.attack {
    let l = t / e.attack
    (2. - l) * l
  } else if t < e.attack + e.hold {
    1.
  } else {
    let t = t - e.attack - e.hold
    let first = e.bp < 1. ? e.decay1 : 0.
    if t < first {
      ampOfDb(dbOfAmp(e.bp) * warp(t / first, e.k1))
    } else {
      let p = Math.min(1., (t - first) / e.decay2)
      let fall = dbOfAmp(Math.max(e.sus / e.bp, 1e-6))
      ampOfDb(dbOfAmp(e.bp) + fall * warp(p, e.k2))
    }
  }
}

// velocity 100's scaling, by a velocity sensitivity (as dsp/Modulation.cmajor's velScale)
let velocityScale = sens => sens > 0.001 ? Math.pow(100. / 127., ~exp=2. * sens) : 1.

// What the rack's and the voice lane's filters do to the level (dB), for a saw's spectrum or a
// sine's: each at its cutoff (following the note as far as it tracks it) against the note, with
// its resonance, mixed with the dry sound.
let rackFilters = (m, rows, ~note) =>
  Array.concat(laneOf(m), rackOf(m))
  ->Array.filter(e => e.kind == #filter)
  ->Array.reduce(0., (db, e) => {
    let id = first => FxRack.id(e, first)
    let t = Float.toInt(get(m, id("Ff_Type")))
    let tracked = Math.pow(noteHz(note) / 261.63, ~exp=get(m, id("Ff_Track")))
    let hz = PorridgeParams.expValue(20., 20000., get(m, id("Ff_Cutoff"))) * tracked
    let octaves = Math.log2(hz / noteHz(note))
    let level = filterLevel(rows, t, octaves) + resonanceLevel(t, get(m, id("Ff_Resonance")), octaves)
    let mix = get(m, id("Ff_Mix"))
    db + 20. * Math.log10(Math.max(1e-3, 1. - mix + mix * ampOfDb(level)))
  })

// An LFO's rate, Hz (at 120 beats a minute for one in time with the music).
let lfoHz = (m, n) => {
  let p = `LFO_${Int.toString(n)}_`
  let speed = Math.max(0.25, get(m, p ++ "Speed"))
  switch get(m, p ++ "Unit") {
  | 0. => 1000. / speed
  | 1. => 100. / speed
  | 2. => 1. / speed
  | unit => 2. / (speed * Math.pow(2., ~exp=(unit - 11.) / 3.))
  }
}

// What routings on the volume add (dB): the loudest 300 ms catch a slow LFO near its peak, and
// a mod envelope at its start; a fast LFO or a random value adds its power on average.
let volumeLevel = m => {
  let volume = Int.toFloat(ModMatrix.targetIndex("volume"))
  usedSlots(m)
  ->Array.filter(k => get(m, ModMatrix.targetId(k)) == volume && get(m, ModMatrix.viaId(k)) == 0.)
  ->Array.reduce(0., (db, k) => {
    let a = Math.min(1., Math.abs(get(m, ModMatrix.amountId(k))))
    let source = ModMatrix.sources[Float.toInt(get(m, ModMatrix.sourceId(k)))]->Option.mapOr("", s => s.key)
    let slow = switch source {
    | "lfo1" => lfoHz(m, 1) < 2.
    | "lfo2" => lfoHz(m, 2) < 2.
    | "modEnv1" | "modEnv2" | "ampEnv" | "filterEnv" => true
    | _ => false
    }
    db + (slow ? 20. * Math.log10(1. + 0.8 * a) : 10. * Math.log10(1. + a * a / 2.))
  })
}

// How far routings take the cutoff up while the loudest 300 ms play, as a knob position: an LFO
// near its peak, a random value on average, velocity 100, the key, an envelope near its start
// (a routing through the mod wheel or aftertouch, which the note doesn't move, adds nothing).
let cutoffShift = (m, ~note) => {
  let cutoff = Int.toFloat(ModMatrix.targetIndex("Cutoff"))
  usedSlots(m)
  ->Array.filter(k => get(m, ModMatrix.targetId(k)) == cutoff && get(m, ModMatrix.viaId(k)) == 0.)
  ->Array.reduce(0., (s, k) => {
    let a = get(m, ModMatrix.amountId(k))
    switch ModMatrix.sources[Float.toInt(get(m, ModMatrix.sourceId(k)))]->Option.mapOr("", s => s.key) {
    | "lfo1" | "lfo2" => s + 0.7 * Math.abs(a)
    | "random" | "noise" => s + 0.3 * Math.abs(a)
    | "velocity" => s + a * 100. / 127.
    | "key" => s + a * (Int.toFloat(note) - 60.) / 60.
    | "modEnv1" | "modEnv2" | "ampEnv" | "filterEnv" => s + 0.5 * Math.max(0., a)
    | _ => s
    }
  })
}

// The simulated note (dB over its loudest 300 ms, with the output gain at 1), and its loudest
// moment (dB, about where the peak is); only its first `within` ms, if given.
//
// A voice's own distortion comes after the amp envelope and the velocity (dsp/Synth.cmajor's
// gainAndDistort), so it takes each moment's level through its curve (LevelTables.drive): a
// driven note's decay is squashed back up towards the clip, and only fades below 1/16 of the
// envelope. The global distortion and the rack's come after that, on the whole sound.
let simulated = (m, ~note, ~within=2000., ~tables=?) => {
  let (bright, pure) = sources(m, ~tables=tables->Option.getOr(Lazy.get(initTables)))
  let rackSaw = rackFilters(m, LevelTables.saw, ~note)
  let rackSine = rackFilters(m, LevelTables.sine, ~note)
  let t = Float.toInt(get(m, "Filter"))
  let filtered = t != 0
  let amp = envelopeOf(m, "", ~curves="Amp")
  let filterEnv = envelopeOf(m, "F_", ~curves="Filter")
  let knob = Math.max(0., Math.min(1., get(m, "Cutoff") + cutoffShift(m, ~note)))
  let base = filtered ? Math.log2(Math.max(1., cutoffAt(m, ~note, ~knob)) / noteHz(note)) : 0.
  let envOctaves = 8. * get(m, "F_EnvMod") * velocityScale(get(m, "F_VeloSens"))
  // the second filter: after the first, or beside it, up to F_Split's two octaves above
  let double = filtered ? Float.toInt(get(m, "F_Double")) : 0
  let t2 = get(m, "Filter2") == 0. ? t : Float.toInt(get(m, "Filter2"))
  let split = 2. * get(m, "F_Split")
  let mix = get(m, "F_Mix")
  let res = get(m, "Resonance")
  let drive = get(m, "F_Drive")
  let through = (rows, octaves) =>
    if !filtered {
      0.
    } else {
      let one = filterLevel(rows, t, octaves) + resonanceLevel(t, res, octaves) + filterDriveLevel(t, drive)
      let two = () => {
        let o = octaves + split
        filterLevel(rows, t2, o) + resonanceLevel(t2, res, o) + filterDriveLevel(t2, drive)
      }
      switch double {
      | 1 => 10. * Math.log10((1. - mix) * Math.pow(10., ~exp=one / 10.) + mix * Math.pow(10., ~exp=two() / 10.))
      | 2 => one + two()
      | _ => one
      }
    }
  let db = p => 10. * Math.log10(Math.max(p, 1e-12))
  let power10 = x => Math.pow(10., ~exp=x / 10.)
  let velocity = 20. * Math.log10(velocityScale(get(m, "VeloSens")))
  // the distortions: the voice's (by Sat_Mode: 0 global, 1 after the filter, 2 before it,
  // 3 both), then the voice lane's and the rack's, each as (type, pregain, postgain)
  let driveType = Float.toInt(get(m, "Sat_Type"))
  let driveMode = Float.toInt(get(m, "Sat_Mode"))
  let voiceDrive = driveType != 0 && driveMode != 0
  let globalDrive = driveType != 0 && (driveMode == 0 || driveMode == 3)
  let (pregain, postgain) = (get(m, "Sat_Pregain"), get(m, "Sat_Postgain"))
  let rackDrives =
    Array.concat(laneOf(m), rackOf(m))
    ->Array.filter(e => e.kind == #distortion)
    ->Array.map(e => {
      let id = first => FxRack.id(e, first)
      (Float.toInt(get(m, id("Sat_Type"))), get(m, id("Sat_Pregain")), get(m, id("Sat_Postgain")))
    })
  let step = 2.
  let window = Float.toInt(300. / step)
  let steps = Math.Int.max(window, Math.Int.min(1000, Float.toInt(within / step)))
  let power = Array.fromInitializer(~length=steps, i => {
    let ms = Int.toFloat(i) * step
    let a = envelopeAt(amp, ms)
    let octaves = base + envOctaves * (filtered ? envelopeAt(filterEnv, ms) : 0.)
    let (saw, sine) = (through(LevelTables.saw, octaves), through(LevelTables.sine, octaves))
    let voice = bright * power10(saw) + pure * power10(sine)
    let level = if voiceDrive {
      // (what it puts out is bright, whatever goes in: the rack's filters take it as a saw)
      let raw = bright + pure
      let input = db(driveMode == 2 ? raw : voice) + db(a * a) + velocity
      let out = driveCurve(driveType, input + pregain) + postgain + (driveMode == 2 ? db(voice) - db(raw) : 0.) + rackSaw
      a < 0.0625 ? out + 20. * Math.log10(Math.max(16. * a, 1e-6)) : out
    } else {
      db(a * a * (bright * power10(saw + rackSaw) + pure * power10(sine + rackSine))) + velocity
    }
    let level = globalDrive ? driveCurve(driveType, level + pregain) + postgain : level
    power10(rackDrives->Array.reduce(level, (l, (t, pre, post)) => driveCurve(t, l + pre) + post))
  })
  let sum = ref(power->Array.slice(~start=0, ~end=window)->Array.reduce(0., (s, p) => s + p))
  let loudest = ref(sum.contents)
  for i in window to steps - 1 {
    sum := sum.contents + power->Array.getUnsafe(i) - power->Array.getUnsafe(i - window)
    loudest := Math.max(loudest.contents, sum.contents)
  }
  let gains = volumeLevel(m)
  (db(loudest.contents / Int.toFloat(window)) + gains, db(power->Array.reduce(0., Math.max)) + gains)
}

let simulatedLevel = (m, ~note, ~within=?, ~tables=?) => {
  let (level, _) = simulated(m, ~note, ~within?, ~tables?)
  level
}

// What the simulation leaves out, as `loudness` weighs it: the unison, osc 2's interval against
// osc 1 (at one, they add more than their powers), the modes, the rack's compressor, its spaces
// and echoes, the sweeping effects (chorus, flanger and phaser, in the rack or the voices: each
// about the same whatever its settings, and less each the more there are; louder as a phaser's
// or an untuned flanger's feedback makes it ring), the frequency shifter, the distortion models'
// own drive, the second filter, and the voice lane's flangers tuned to the note (which ring
// there, the more the more feedback), resonator, octaver, frequency shifter, filter and distortion.
let loudnessFeatures = m => {
  let mode = mixMode(m)
  let rack = rackOf(m)
  let lane = laneOf(m)
  let has = kind => rack->Array.some(e => e.kind == kind) ? 1. : 0.
  let inLane = (kind, first) => lane->Array.find(e => e.kind == kind)->Option.mapOr(0., e => get(m, FxRack.id(e, first)))
  let sweeping = Array.concat(rack, lane)->Array.filter(e => e.kind == #chorus || e.kind == #flanger || e.kind == #phaser)
  let feedback = (e: FxRack.effect, first) => Math.max(0., Math.abs(get(m, FxRack.id(e, first))) - 0.4)
  let resonant = sweeping->Array.reduce(0., (sum, e) =>
    switch e.kind {
    | #phaser => sum + feedback(e, "Ph_Feedback")
    | #flanger if get(m, FxRack.id(e, "Fl_Track")) == 0. => sum + feedback(e, "Fl_Feedback")
    | _ => sum
    }
  )
  let ringing =
    lane
    ->Array.filter(e => e.kind == #flanger && get(m, FxRack.id(e, "Fl_Track")) > 0.)
    ->Array.reduce(0., (sum, e) => sum + Math.max(0., get(m, FxRack.id(e, "Fl_Feedback"))))
  [
    10. * Math.log10(Math.max(1., get(m, "U_Voices"))),
    secondSounds(m) && !modulating(mode) && Math.abs(get(m, "Transpose")) < 0.01 ? 1. : 0.,
    mode == sync ? 1. : 0.,
    mode == fm ? 1. : 0.,
    mode == pm || mode == pmFeedback ? get(m, "PM_Feedback") : 0.,
    has(#compressor),
    has(#space) + has(#reverb) + has(#ambience) + has(#convolve),
    has(#delay),
    Math.log2(1. + Int.toFloat(Array.length(sweeping))),
    resonant,
    has(#bode),
    get(m, "Sat_Type") >= Int.toFloat(DistTypes.firstModel) ? get(m, "Sat_Drive") - 0.5 : 0.,
    filtered(m) ? Int.toFloat(Float.toInt(get(m, "F_Double"))) : 0.,
    ringing,
    inLane(#resonator, "Rs_Mix"),
    inLane(#octaver, "Oc_Sub") + inLane(#octaver, "Oc_Up"),
    inLane(#bode, "Bd_Mix"),
    inLane(#filter, "Ff_On"),
    lane->Array.some(e => e.kind == #distortion) ? 1. : 0.,
  ]
}

let loudnessWeights = [0.1, 0.341, -0.7, -0.134, -0.757, -4.822, -0.039, 0.04, -2.793, 6.748, -2.282, 3.717, -1.599, 2.388, -11.806, -0.147, -7.798, -2.987, -2.125]
let loudnessBias = 1.904

// About how loud a patch's note plays: dB over its loudest 300 ms, K-weighted (as a loudness
// meter hears it), with the output gain at 1. (Without its tables, as if its drawn waves were
// Init's sines.)
let loudness = (m, ~note, ~tables=?) =>
  loudnessFeatures(m)->Array.reduceWithIndex(simulatedLevel(m, ~note, ~tables?) + loudnessBias, (s, x, i) =>
    s + x * loudnessWeights->Array.getUnsafe(i)
  )

// The loudest moment of a patch's note (dB, with the output gain at 1), with the estimate's
// correction: its peak is mostly within a few dB above it (tools/random-levels.mjs).
let loudestMoment = (m, ~note, ~tables=?) => {
  let (level, loudest) = simulated(m, ~note, ~tables?)
  loudest + loudness(m, ~note, ~tables?) - level
}

// the level a single note is set to, as the Vanilla bank's chords are (-18 dB for four notes),
// and the most its loudest moment may reach
let targetDb = -24.
let ceilingDb = -9.

// The output gain that puts a patch's note at targetDb, unless that would take its loudest
// moment over the ceiling (a short pluck, whose 300 ms are mostly its tail).
let gainFor = (t, ~note) =>
  Math.min(
    2.,
    ampOfDb(Math.min(targetDb - loudness(t.values, ~note, ~tables=t.tables), ceilingDb - loudestMoment(t.values, ~note, ~tables=t.tables))),
  )

//==============================================================================
// Making patches

// A random patch: Init with each area made at its wildness, except the locked ones (`keep`:
// the patch they come from, and which), which keep what that patch has (the oscillators their
// drawn waves too). `note` is where it will be auditioned.
let generate = (~wild: wildness, ~kind: kind, ~random as r: rng, ~keep: option<(patch, array<area>)>=?) => {
  let m = copy(Lazy.get(initValues))
  let locked = a => keep->Option.mapOr(false, ((_, areas)) => areas->Array.includes(a))
  let t = {values: m, tables: Lazy.get(initTables)}
  keep->Option.forEach(((from, _)) => {
    from.values->Map.forEachWithKey((v, id) =>
      switch owner(id) {
      | Some(a) if locked(a) => m->Map.set(id, v)
      | _ => ()
      }
    )
    if locked(#osc) {
      t.tables = from.tables
    }
  })
  if !locked(#osc) {
    makeOsc(r, wild.osc, kind, t)
  }
  if !locked(#filter) {
    makeFilter(r, wild.filter, kind, m)
  }
  if !locked(#env) {
    makeEnv(r, wild.env, kind, m)
  }
  // (the routings may move the rack's effects)
  if !locked(#fx) {
    makeFx(r, wild.fx, kind, m)
  }
  if !locked(#mod) {
    makeMod(r, wild.mod, kind, m)
  }
  // (a new rack takes the connections to its slots' knobs with what it moves: locked ones stay)
  keep->Option.forEach(((from, _)) =>
    from.values->Map.forEachWithKey((v, id) =>
      switch owner(id) {
      | Some(a) if locked(a) => m->Map.set(id, v)
      | _ => ()
      }
    )
  )
  m->Map.set("Gain", gainFor(t, ~note=profile(kind).note))
  t
}

//==============================================================================
// Varying

// How a setting moves: along a line, on a log scale (times, rates), in dB (levels, which stay
// off at 0), by its knob, or by a factor (modulation amounts, which keep their sign).
type law = Lin(float, float) | Log(float, float) | Db(float, float) | Knob | Factor

type nudge = {id: string, law: law, scale: float, active: Bank.values => bool}

let nudge = (~scale=1., ~active=always, id, law) => {id, law, scale, active}
let nonzero = id => m => get(m, id) != 0.
let pulsed = id => m => hasWidth(get(m, id))
let decay1On = id => m => get(m, id) < 1.

// The settings each area moves.
let nudges = (a: area) =>
  switch a {
  | #osc => [
      nudge("O1_Amp", Db(-40., 12.), ~scale=0.5, ~active=nonzero("O1_Amp")),
      nudge("O2_Amp", Db(-40., 12.), ~scale=0.6, ~active=nonzero("O2_Amp")),
      nudge("O1_PWM_W", Lin(0.04, 0.5), ~active=pulsed("O1_Waveform")),
      nudge("O2_PWM_W", Lin(0.04, 0.5), ~active=pulsed("O2_Waveform")),
      nudge("O1_PWM_R", Log(0.05, 8.), ~active=nonzero("O1_PWM_R")),
      nudge("O1_PWM_D", Lin(-0.5, 0.5), ~active=nonzero("O1_PWM_R")),
      nudge("Detune", Lin(-12., 12.), ~scale=0.4, ~active=secondSounds),
      nudge("N_Amp", Db(-40., 0.), ~active=nonzero("N_Amp")),
      nudge("N_Resonance", Lin(0., 0.95), ~active=nonzero("N_Amp")),
      nudge("N_Density", Lin(0., 0.9), ~active=m => get(m, "N_Amp") > 0. && get(m, "N_Type") == Int.toFloat(PorridgeParams.noiseCrackle)),
      nudge("U_Detune", Log(2., 100.), ~active=m => get(m, "U_Voices") > 1.),
      nudge("U_Spread", Lin(0., 1.), ~active=m => get(m, "U_Voices") > 1.),
      nudge("PM_Feedback", Lin(0., 0.95), ~active=m => mixMode(m) == pm || mixMode(m) == pmFeedback),
      nudge("O2_PairMix", Lin(0., 1.), ~active=nonzero("O2_PairMix")),
      nudge("O1_Noise", Lin(0., 0.8), ~active=nonzero("O1_Noise")),
      nudge("O2_Noise", Lin(0., 0.8), ~active=nonzero("O2_Noise")),
      nudge("Drift_Pitch", Lin(0., 20.), ~active=nonzero("Drift_Pitch")),
      nudge("M1_Depth_1", Factor, ~active=nonzero("M1_Target_1")),
      nudge("M1_Decay2", Log(10., 8000.), ~active=nonzero("M1_Target_1")),
    ]
  | #filter => [
      nudge("Cutoff", Knob, ~active=filtered),
      nudge("Resonance", Lin(0., 0.9), ~scale=0.6, ~active=filtered),
      nudge("F_EnvMod", Lin(-0.5, 0.75), ~scale=0.6, ~active=filtered),
      nudge("F_Attack", Log(0.2, 4000.), ~active=filtered),
      nudge("F_Decay2", Log(20., 12000.), ~active=filtered),
      nudge("F_Sustain", Lin(0., 1.), ~active=filtered),
      nudge("F_Track", Lin(-0.5, 1.5), ~scale=0.4, ~active=filtered),
      nudge("F_Split", Lin(0., 1.), ~active=nonzero("F_Double")),
      nudge("F_Mix", Lin(0., 1.), ~active=nonzero("F_Double")),
      nudge("F_Morph", Lin(0., 1.), ~active=filtered),
      nudge("F_Drive", Lin(0., 1.), ~active=nonzero("F_Drive")),
    ]
  | #env => [
      nudge("Attack", Log(0.2, 8000.)),
      nudge("Decay1", Log(10., 4000.), ~active=decay1On("Breakpoint")),
      nudge("Breakpoint", Lin(0.05, 0.95), ~active=decay1On("Breakpoint")),
      nudge("Decay2", Log(30., 20000.)),
      nudge("Sustain", Lin(0., 1.)),
      nudge("Release", Log(10., 12000.)),
      nudge("PEnv_Decay", Log(10., 4000.), ~active=nonzero("PEnv_On")),
      nudge("Glide", Log(2., 500.), ~active=nonzero("Glide")),
    ]
  | #mod => [
      nudge("LFO_1_Speed", Log(0.25, 256.), ~scale=0.6, ~active=m => !lfoFree(m, 1)),
      nudge("LFO_2_Speed", Log(0.25, 256.), ~scale=0.6, ~active=m => !lfoFree(m, 2)),
      nudge("LFO_1_Pitch", Factor, ~active=nonzero("LFO_1_Pitch")),
      nudge("LFO_1_Cutoff_1", Factor, ~active=nonzero("LFO_1_Cutoff_1")),
      nudge("LFO_2_Cutoff_1", Factor, ~active=nonzero("LFO_2_Cutoff_1")),
      nudge("M2_Attack", Log(0.2, 4000.), ~active=m => sourceUsed(m, "modEnv2")),
      nudge("M2_Decay2", Log(10., 12000.), ~active=m => sourceUsed(m, "modEnv2")),
      ...ModMatrix.slotNumbers->Array.map(k =>
        nudge(ModMatrix.amountId(k), Factor, ~active=nonzero(ModMatrix.sourceId(k)))
      ),
      ...xyAxes->Array.flatMap(axis =>
        [1, 2, 3, 4]->Array.map(n => nudge(xyDepthId(axis, n), Factor, ~active=nonzero(xyTargetId(axis, n))))
      ),
      nudge("XY_Var_Radius", Lin(0.02, 1.), ~active=nonzero("XY_Var_Radius")),
      nudge("XY_Var_Rate", Log(0.05, 16.), ~active=nonzero("XY_Var_Radius")),
    ]
  | #fx => [
      nudge("Sat_Pregain", Lin(-12., 36.), ~scale=0.5, ~active=nonzero("Sat_Type")),
    ]
  }

// The rack's and the voice lane's effects' settings that move: their continuous ones, but not
// their levels in and out (which the output gain answers for) nor what restarts an effect.
let fixedFx = ["Gain", "Pregain", "Postgain", "Limit", "Wet", "InGain", "OutGain", "Predelay", "Length", "Dry", "Phase", "Spread", "Width", "Pan", "Freq", "Inv", "Swap", "Thresh", "Ratio", "Split"]
// (nor the phaser's and flanger's tracking and random starts, which stay as they were made)
// (nor in the voices what only the whole sound has: the frequency shifter's echoes)
let rackNudges = m =>
  Array.concat(rackOf(m)->Array.map(e => (e, false)), laneOf(m)->Array.map(e => (e, true)))->Array.flatMap(((e, inLane)) =>
    FxRack.spec(e.kind).params->Array.filterMap(((first, _)) => {
      let id = FxRack.id(e, first)
      let d = def(id)
      let fixed =
        fixedFx->Array.some(word => String.includes(id, word)) ||
        PorridgeParams.isLaterKindParam(first) ||
        (inLane && PorridgeParams.rackOnlyParams->Array.includes(first))
      d.names == None && !d.isInt && !fixed ? Some(nudge(id, Knob, ~scale=0.6)) : None
    })
  )

let moveBy = (r, m, n: nudge, amount) => {
  let v = get(m, n.id)
  let step = gaussian(r) * amount * 0.25 * n.scale
  let clamp01 = x => Math.max(0., Math.min(1., x))
  let next = switch n.law {
  | Lin(lo, hi) => lo + (hi - lo) * clamp01((v - lo) / (hi - lo) + step)
  | Log(lo, hi) =>
    let span = Math.log(hi / lo)
    lo * Math.exp(span * clamp01(Math.log(Math.max(v, lo) / lo) / span + step))
  | Db(lo, hi) => ampOfDb(lo + (hi - lo) * clamp01((dbOfAmp(v) - lo) / (hi - lo) + step))
  | Knob =>
    let d = def(n.id)
    d.fromNorm(clamp01(d.toNorm(v) + step))
  | Factor => v * Math.pow(2., ~exp=4. * step)
  }
  put(m, n.id, next)
}

// feedback that would ring on is held back (in the voices, sooner: see addToLane)
let tamedFeedback = m => {
  let tame = (e, first, most) => {
    let id = FxRack.id(e, first)
    if FxRack.params(e)->Array.includes(id) {
      put(m, id, Math.max(-.most, Math.min(most, get(m, id))))
    }
  }
  rackOf(m)->Array.forEach(e =>
    ["C_Feedback", "D_FeedbackL", "D_FeedbackR", "Fl_Feedback", "Ph_Feedback", "Bd_Feedback"]->Array.forEach(first =>
      tame(e, first, 0.92)
    )
  )
  laneOf(m)->Array.forEach(e => {
    tame(e, "Ph_Feedback", 0.6)
    tame(e, "Fl_Feedback", 0.7)
  })
}

// A part of an area made again, added or taken away.
let restructure = (r, w, k: kind, t, a: area) => {
  let m = t.values
  let p = profile(k)
  switch a {
  | #osc =>
    switch weighted(r, [(0, 1.), (1, 0.5), (2, 0.5), (3, 0.4)]) {
    | 0 => oscPair(r, w, k, p, t)
    | 1 => oscWave(r, w, k, p, t)
    | 2 => oscUnison(r, w, p, m)
    | _ => oscNoise(r, w, k, m)
    }
  | #filter => chance(r, 0.6) ? filterType(r, w, k, m) : filterEnv(r, w, k, m)
  | #env => chance(r, 0.7) ? pitchEnv(r, w, k, m) : mono(r, w, k, m)
  | #mod =>
    switch usedSlots(m) {
    | _ if chance(r, 0.2) => xyPad(r, w, m)
    | [] => addRoute(r, w, k, m)->ignore
    | used =>
      if chance(r, 0.4) {
        reset(m, ModMatrix.slotIds(pick(r, used)))
      } else {
        addRoute(r, w, k, m)->ignore
      }
    }
  | #fx =>
    let rack = rackOf(m)
    if chance(r, 0.2) {
      voiceFx(r, w, k, m)
    } else if rack != [] && chance(r, 0.4) {
      let gone = pick(r, rack)
      FxRack.values(get(m, ...), rack->Array.filter(e => e != gone))->Array.forEach(((id, v)) => put(m, id, v))
      put(m, FxRack.switchId(gone), 0.)
    } else if chance(r, 0.25) {
      drive(r, w, k, m)
    } else {
      nextEffect(r, w, k, m)->Option.forEach(kind => addEffect(r, w, m, kind)->ignore)
    }
  }
}

// Choices picked again now and then: the waves, the filter type within its family's wildness,
// the LFOs' shapes, the distortion's type, the spaces' models.
let repick = (r, w, k: kind, t, a: area, amount) => {
  let m = t.values
  let often = () => chance(r, amount * 0.3)
  switch a {
  | #osc =>
    if often() {
      oscWave(r, w, k, profile(k), t)
    }
    if secondSounds(m) && !modulating(mixMode(m)) && often() {
      put(m, "O2_Waveform", weighted(r, profile(k).waves))
    }
  | #filter =>
    if filtered(m) && often() {
      let (name, _) = tiered(r, w, filterChoices(k)->Array.map(((name, family, from, weight)) => ((name, family), from, weight)))
      let t = FilterTypes.index(name)
      // (at the same frequency)
      let hz = FilterTypes.cutoffHz(~filterType=Float.toInt(get(m, "Filter")), get(m, "Cutoff"))
      put(m, "Filter", Int.toFloat(t))
      put(m, "Cutoff", FilterTypes.cutoffOfHz(~filterType=t, hz))
    }
  | #env => ()
  | #mod =>
    [1, 2]->Array.forEach(n =>
      if !lfoFree(m, n) && often() {
        put(m, `LFO_${Int.toString(n)}_Shape`, tiered(r, w, [(0., 0., 2.), (3., 0., 1.5), (4., 0., 1.), (1., 0.4, 0.6), (2., 0.4, 0.6), (5., 0.6, 0.6)]))
      }
    )
  | #fx =>
    if get(m, "Sat_Type") != 0. && often() {
      put(m, "Sat_Type", tiered(r, w, driveTypes))
    }
    rackOf(m)->Array.forEach(e =>
      switch e.kind {
      | #space if often() => put(m, FxRack.id(e, "Rv_Model"), tiered(r, w, [(0., 0., 2.), (1., 0., 1.5), (4., 0., 1.), (2., 0.5, 0.7), (3., 0.5, 0.7)]))
      | #ambience if often() => put(m, FxRack.id(e, "Am_Model"), pick(r, [0., 1., 2.]))
      | _ => ()
      }
    )
  }
}

// A variation of any patch: its unlocked areas moved by `amount` (0..1: 0.15 is a little, 0.7 a
// lot), each now and then made again in part, more often the wilder it may go. The output gain
// moves by what the estimate says the change in level is.
let vary = (from: patch, ~amount, ~wild: wildness, ~locks: array<area>, ~kind: kind, ~random as r: rng) => {
  let t = copyPatch(from)
  let m = t.values
  let src = from.values
  let free = areas->Array.filter(a => !(locks->Array.includes(a)))
  free->Array.forEach(a => {
    let w = wildOf(wild, a)
    let moves = a == #fx ? Array.concat(nudges(a), rackNudges(m)) : nudges(a)
    moves->Array.forEach(n =>
      if n.active(m) {
        moveBy(r, m, n, amount)
      }
    )
    repick(r, w, kind, t, a, amount)
    if chance(r, amount * (0.25 + 0.6 * w)) {
      restructure(r, w, kind, t, a)
    }
  })
  tamedFeedback(m)
  // (the rack's changes leave the locked areas' values as they were: its connections too)
  src->Map.forEachWithKey((v, id) =>
    switch owner(id) {
    | Some(a) if locks->Array.includes(a) => m->Map.set(id, v)
    | _ => ()
    }
  )
  // a distortion's pregain or type moved: its postgain follows, as far as the curves differ
  let (t0, t1) = (Float.toInt(get(src, "Sat_Type")), Float.toInt(get(m, "Sat_Type")))
  let (p0, p1) = (get(src, "Sat_Pregain"), get(m, "Sat_Pregain"))
  if t0 != 0 && t1 != 0 && (t0 != t1 || p0 != p1) {
    put(m, "Sat_Postgain", get(src, "Sat_Postgain") + neutralPostgain(t1, p1) - neutralPostgain(t0, p0))
  }
  let note = profile(kind).note
  let before = get(src, "Gain")
  m->Map.set(
    "Gain",
    Math.min(2., before * ampOfDb(loudness(src, ~note, ~tables=from.tables) - loudness(m, ~note, ~tables=t.tables))),
  )
  t
}

//==============================================================================
// Names and descriptions

let waveName = v =>
  switch v {
  | 0. => "sine"
  | 1. | 6. => "saw"
  | 2. | 7. => "pulse"
  | 3. | 8. => "triangle"
  | 4. => "drawn wave"
  | _ => "drawn pulse"
  }

let fixed1 = x => Float.toString(Math.round(x * 10.) / 10.)
let percentOf = x => Float.toString(Math.round(x * 100.)) ++ "%"
let msText = ms => ms >= 1000. ? fixed1(ms / 1000.) ++ " s" : Float.toString(Math.round(ms)) ++ " ms"

let oscText = m => {
  let mode = mixMode(m)
  let w1 = waveName(get(m, "O1_Waveform"))
  let w2 = waveName(get(m, "O2_Waveform"))
  let semis = 12. * get(m, "Transpose")
  let interval = Math.abs(semis) < 0.05 ? "" : (semis > 0. ? " +" : " ") ++ fixed1(semis)
  let ratio = " ×" ++ Float.toString(Math.round(Math.pow(2., ~exp=semis / 12.) * 100.) / 100.)
  let pair = if mode == sync {
    `${w1} sync ${w2}${interval}`
  } else if mode == fm {
    `${w2} FM by ${w1}${ratio}`
  } else if mode == pm {
    `${w1} PM by ${w2}${ratio}`
  } else if mode == ring {
    `${w1} ring ${w2}${ratio}`
  } else if mode == am {
    `${w1} AM by ${w2}${ratio}`
  } else if get(m, "O2_Amp") > 0. {
    `${w1} + ${w2}${interval}` ++ (mode == pmFeedback ? " PM feedback" : "")
  } else {
    w1 ++ (mode == pmFeedback ? " PM feedback" : "")
  }
  let voices = get(m, "U_Voices")
  [
    Some(pair),
    get(m, "M1_Target_1") != 0. ? Some("swept") : None,
    voices > 1. ? Some(`×${Float.toString(voices)}`) : None,
    get(m, "N_Amp") > 0. ? Some("+ " ++ noiseText(m)) : None,
    get(m, "O1_Noise") > 0. || get(m, "O2_Noise") > 0. ? Some("rough") : None,
  ]->Array.filterMap(x => x)->Array.join(" ")
}

let filterText = (m, ~note) =>
  if !filtered(m) {
    "no filter"
  } else {
    let t = Float.toInt(get(m, "Filter"))
    let name = FilterTypes.all->Array.getUnsafe(t)
    let octaves = 8. * get(m, "F_EnvMod")
    [
      Some(name),
      Some("at " ++ fixed1(cutoffAt(m, ~note) / noteHz(note)) ++ "×"),
      get(m, "Resonance") >= 0.3 ? Some("res " ++ percentOf(get(m, "Resonance"))) : None,
      Math.abs(octaves) >= 0.5 ? Some(`env ${octaves > 0. ? "+" : ""}${fixed1(octaves)} oct`) : None,
      get(m, "F_Double") != 0. ? Some(get(m, "F_Double") == 1. ? "parallel" : "serial") : None,
      get(m, "F_Drive") > 0. ? Some("driven") : None,
    ]->Array.filterMap(x => x)->Array.join(", ")
  }

let envText = m => {
  let attack = get(m, "Attack")
  let decay = get(m, "Decay2")
  let sustain = get(m, "Sustain")
  let shape = if attack > 150. {
    `${msText(attack)} swell`
  } else if sustain < 0.05 {
    decay < 900. ? `${msText(decay)} pluck` : `${msText(decay)} decay`
  } else {
    `held at ${percentOf(sustain)}`
  }
  let st = get(m, "PEnv_Start")
  [
    Some(shape),
    get(m, "PEnv_On") != 0. ? Some(`pitch ${st > 0. ? "drop" : "rise"} ${fixed1(Math.abs(st))} st`) : None,
    get(m, "PolyMode") != 1. ? Some(get(m, "Glide") > 0. ? "mono, glide" : "mono") : None,
  ]->Array.filterMap(x => x)->Array.join(", ")
}

let targetLabel = i => ModMatrix.targets[i]->Option.mapOr("", t => t.label)
let sourceLabel = i => ModMatrix.sources[i]->Option.mapOr("", s => s.label)

// the XY pad's routes: "XY > cutoff 1, resonance (wandering)"
let xyText = m => {
  let targets = xyAxes->Array.flatMap(axis =>
    [1, 2, 3, 4]->Array.filterMap(n => {
      let t = Float.toInt(get(m, xyTargetId(axis, n)))
      t == 0 ? None : def(xyTargetId(axis, n)).names->Option.flatMap(names => names[t])
    })
  )
  targets == [] ? [] : [`XY > ${targets->Array.join(", ")}` ++ (get(m, "XY_Var_Radius") > 0. ? " (wandering)" : "")]
}

let modText = m =>
  switch Array.concat(
    usedSlots(m)->Array.map(k => {
      let slot = ModMatrix.readSlot(get(m, ...), k)
      `${sourceLabel(slot.source)} > ${SlotParams.targetLabel(get(m, ...), slot.target)}` ++ (slot.via == 0 ? "" : ` (${sourceLabel(slot.via)})`)
    }),
    xyText(m),
  ) {
  | [] => "none"
  | routes => routes->Array.join(", ")
  }

let fxText = m => {
  let rack = rackOf(m)
  let lane = laneOf(m)
  let drive = get(m, "Sat_Type") == 0. ? [] : [DistTypes.all[Float.toInt(get(m, "Sat_Type"))]->Option.mapOr("drive", t => t.name)]
  let voices = lane == [] ? [] : [`${lane->Array.map(e => FxRack.label(lane, e))->Array.join(" and ")} in each voice`]
  switch [drive, voices, rack->Array.map(e => FxRack.label(rack, e))]->Array.flat {
  | [] => "dry"
  | parts => parts->Array.join(", ")
  }
}

// What a patch is made of, area by area.
let describe = (m, ~note) => [
  (#osc, oscText(m)),
  (#filter, filterText(m, ~note)),
  (#env, envText(m)),
  (#mod, modText(m)),
  (#fx, fxText(m)),
]

let nouns = (k: kind) =>
  switch k {
  | #bass => ["Bass", "Bass", "Low End"]
  | #lead => ["Lead", "Lead", "Line"]
  | #pad => ["Pad", "Pad", "Haze", "Wash"]
  | #keys => ["Keys", "Keys", "Piano"]
  | #pluck => ["Pluck", "Pluck", "Pick"]
  | #bell => ["Bell", "Chime", "Mallet"]
  | #brass => ["Brass", "Horn"]
  }

// A name from what stands out in a patch, with its kind's noun: "Glassy Bell", "Gritty Bass".
let nameOf = (m, ~kind, ~random as r: rng) => {
  let mode = mixMode(m)
  let note = profile(kind).note
  let octaves = filtered(m) ? Math.log2(cutoffAt(m, ~note) / noteHz(note)) : 4.
  let family = filtered(m) ? Some(familyOf(Float.toInt(get(m, "Filter")))) : None
  // (the rack's effects and the voices')
  let rack = Array.concat(rackOf(m), laneOf(m))
  let has = kind => rack->Array.some(e => e.kind == kind)
  let routed = target => usedSlots(m)->Array.some(k => get(m, ModMatrix.targetId(k)) == Int.toFloat(SlotParams.targetIndex(target)))
  let words = [
    (["Glassy", "Crystal"], (mode == pm || mode == fm) && get(m, "O1_Waveform") == sine),
    (["Metallic", "Clangy"], mode == ring || mode == am),
    (["Sync", "Tearing"], mode == sync),
    (["Gritty", "Dirty", "Crunchy"], get(m, "Sat_Type") != 0. || has(#distortion)),
    (["Rough", "Dusty"], get(m, "O1_Noise") > 0. || get(m, "N_Amp") > 0.),
    (["Wide", "Lush", "Thick"], get(m, "U_Voices") >= 3. || has(#chorus)),
    (["Dark", "Warm", "Muted"], family == Some(Low) && octaves < 1.5),
    (["Bright", "Crisp"], octaves > 3.5),
    (["Hollow", "Reedy"], hasWidth(get(m, "O1_Waveform")) || family == Some(Band)),
    (["Drawn", "Sketched"], isDrawn(get(m, "O1_Waveform"))),
    (["Ringing", "Resonant"], has(#resonator)),
    (["Restless", "Wandering"], xyRouted(m) && get(m, "XY_Var_Radius") > 0.),
    (["Vocal", "Talking"], family == Some(Formant)),
    (["Acid", "Squelchy"], family == Some(Low) && get(m, "Resonance") > 0.55 && get(m, "F_EnvMod") > 0.1),
    (["Wobbly", "Wobble"], routed("Cutoff") && !lfoFree(m, 2)),
    (["Shimmering", "Swirling"], has(#phaser) || has(#flanger)),
    (["Spacey", "Distant", "Vast"], has(#space) || has(#reverb) || has(#convolve)),
    (["Echoing", "Dub"], has(#delay)),
    (["Soft", "Gentle"], get(m, "O1_Waveform") == triangle || get(m, "O1_Waveform") == sine),
    (["Drifting", "Vintage"], get(m, "Drift_Pitch") > 4.),
    (["Zappy", "Laser"], get(m, "PEnv_On") != 0. || routed("pitch")),
    (["Swelling", "Blooming"], get(m, "Attack") > 300. && kind != #pad),
    (["Combed", "Tubular"], family == Some(Comb)),
  ]->Array.filterMap(((ws, on)) => on ? Some(ws) : None)
  let adjective = words == [] ? pick(r, ["Plain", "Simple", "Oaty", "Classic"]) : pick(r, pick(r, words))
  `${adjective} ${pick(r, nouns(kind))}`
}
