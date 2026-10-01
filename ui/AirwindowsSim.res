// The Airwindows models of dsp/Airwindows.cmajor (the distortion's model types and the air), for
// the graphs: the same code, sample by sample, run on a short signal in the view. Each model is
// made with its controls and returns a function from one input sample to one output sample,
// which keeps the model's state between calls.

let pi = Math.Constants.pi
let clip1 = x => Math.max(-1., Math.min(1., x))
let halfPi = 1.57079633

let sineClip = x => {
  let s = Math.sin(Math.min(Math.abs(x), halfPi))
  x > 0. ? s : -.s
}

let spiral = x => {
  let a = Math.abs(x)
  Math.sin(x * a) / (a == 0. ? 1. : a)
}

type bq = {a0: float, a1: float, a2: float, b1: float, b2: float}

let lowpassBq = (freq, reso) => {
  let k = Math.tan(pi * freq)
  let norm = 1. / (1. + k / reso + k * k)
  let a0 = k * k * norm
  {a0, a1: 2. * a0, a2: a0, b1: 2. * (k * k - 1.) * norm, b2: (1. - k / reso + k * k) * norm}
}

let bandpassBq = (freq, reso) => {
  let k = Math.tan(pi * freq)
  let norm = 1. / (1. + k / reso + k * k)
  let a0 = k / reso * norm
  {a0, a1: 0., a2: -.a0, b1: 2. * (k * k - 1.) * norm, b2: (1. - k / reso + k * k) * norm}
}

// a transposed biquad (Airwindows' "fixed" ones)
let biquad = (b: bq) => {
  let (s1, s2) = (ref(0.), ref(0.))
  x => {
    let y = x * b.a0 + s1.contents
    s1 := x * b.a1 - y * b.b1 + s2.contents
    s2 := x * b.a2 - y * b.b2
    y
  }
}

// a direct form I biquad (Mackity's)
let biquadDf1 = (b: bq) => {
  let (x1, x2, y1, y2) = (ref(0.), ref(0.), ref(0.), ref(0.))
  x => {
    let y = b.a0 * x + b.a1 * x1.contents + b.a2 * x2.contents - b.b1 * y1.contents - b.b2 * y2.contents
    x2 := x1.contents
    x1 := x
    y2 := y1.contents
    y1 := y
    y
  }
}

// a one-pole lowpass's state, run as Airwindows does: s = s (1 - a) + x a
let onePole = (s: ref<float>, a, x) => {
  s := s.contents * (1. - a) + x * a
  s.contents
}

// Airwindows' xorshift noise, as a uint32
let xorshift = (fpd: ref<float>) => {
  let s = Float.toInt(fpd.contents == 0. ? 2654435769. : fpd.contents)
  let s = s->Int.bitwiseXor(s->Int.shiftLeft(13))
  let s = s->Int.bitwiseXor(s->Int.shiftRightUnsigned(17))
  let s = s->Int.bitwiseXor(s->Int.shiftLeft(5))
  // (as unsigned)
  fpd := (s < 0 ? Int.toFloat(s) + 4294967296. : Int.toFloat(s))
}

let uint32Max = 4294967295.

//==============================================================================
// the distortion's models (DistTypes): drive, tone and character 0..1, at rate sr

let tube = (~drive: float, ~sr: float) => {
  let scale = sr / 44100.
  let gain = 1. + drive * 0.2246161992650486
  let power = Float.toInt(5. * (1. - drive) + 1.)
  let gainScaling = 1. / Int.toFloat(power + 1)
  let outScaling = 1. + 1. / Int.toFloat(power)
  let (a, c) = (ref(0.), ref(0.))
  input => {
    let x = ref(input)
    if scale > 1.9 {
      let stored = x.contents
      x := (x.contents + a.contents) * 0.5
      a := stored
    }
    let v = clip1(x.contents * gain)
    let factor = ref(v)
    for _ in 1 to power {
      factor := factor.contents * v
    }
    if mod(power, 2) == 1 && v != 0. {
      factor := factor.contents / v * Math.abs(v)
    }
    let y = ref((v - factor.contents * gainScaling) * outScaling)
    if scale > 1.9 {
      let stored = y.contents
      y := (y.contents + c.contents) * 0.5
      c := stored
    }
    y.contents
  }
}

let tape = (~drive: float, ~tone: float, ~sr: float) => {
  let scale = sr / 44100.
  let gain = Math.pow(10., ~exp=(drive - 0.5) * 24. / 20.)
  let bumpGain = tone * 0.1
  let bumpFreq = 0.12 / scale
  let softness = 0.618033988749894848204586
  let roll = (1. - softness) / scale
  let bump = bandpassBq(0.0072 / scale, 0.0009)
  let sig = bandpassBq(0.032 / scale, 0.0007)
  let (bqA, bqB, bqC, bqD) = (biquad(bump), biquad(bump), biquad(sig), biquad(sig))
  let (rollA, rollB, bumpA, bumpB, last) = (ref(0.), ref(0.), ref(0.), ref(0.), ref(0.))
  let flip = ref(false)
  input => {
    let dry = input
    let (x, highs) = if flip.contents {
      let highs = input - onePole(rollA, roll, input)
      bumpA := bumpA.contents + input * 0.05
      bumpA := bumpA.contents - bumpA.contents * bumpA.contents * bumpA.contents * bumpFreq
      bumpA := Math.asin(clip1(bqA(Math.sin(bumpA.contents))))
      (Math.asin(clip1(bqC(Math.sin(input)))), highs)
    } else {
      let highs = input - onePole(rollB, roll, input)
      bumpB := bumpB.contents + input * 0.05
      bumpB := bumpB.contents - bumpB.contents * bumpB.contents * bumpB.contents * bumpFreq
      bumpB := Math.asin(clip1(bqB(Math.sin(bumpB.contents))))
      (Math.asin(clip1(bqD(Math.sin(input)))), highs)
    }
    flip := !flip.contents
    let ground = dry - x
    let x = gain != 1. ? x * gain : x
    let soften = 1. - Math.cos(Math.min(Math.abs(highs) * halfPi, halfPi))
    let x = highs > 0. ? x - soften : highs < 0. ? x + soften : x
    let x = spiral(Math.max(-1.2533141373155, Math.min(1.2533141373155, x)))
    let suppress = (1. - Math.abs(x)) * 0.00013
    [bumpA, bumpB]->Array.forEach(b =>
      if b.contents > suppress {
        b := b.contents - suppress
      } else if b.contents < -.suppress {
        b := b.contents + suppress
      }
    )
    let x = ref(x + ground + (bumpA.contents + bumpB.contents) * bumpGain)
    if last.contents >= 0.99 {
      last := (x.contents < 0.99 ? 0.99 * softness + x.contents * (1. - softness) : 0.99)
    }
    if last.contents <= -0.99 {
      last := (x.contents > -0.99 ? -0.99 * softness + x.contents * (1. - softness) : -0.99)
    }
    if x.contents > 0.99 {
      x := (last.contents < 0.99 ? 0.99 * softness + last.contents * (1. - softness) : 0.99)
    }
    if x.contents < -0.99 {
      x := (last.contents > -0.99 ? -0.99 * softness + last.contents * (1. - softness) : -0.99)
    }
    last := x.contents
    Math.max(-0.99, Math.min(0.99, x.contents))
  }
}

let saturate = (~drive: float, ~character: float, ~sr: float) => {
  let scale = sr / 44100.
  let d = drive * 5. - 1.
  let density = d * Math.abs(d)
  let blend = ref(Math.abs(d))
  while blend.contents > 1. {
    blend := blend.contents - 1.
  }
  let blend = blend.contents
  let iir = Math.pow(character, ~exp=3.) / scale
  let (a, b, flip) = (ref(0.), ref(0.), ref(false))
  input => {
    let x = ref(input - onePole(flip.contents ? a : b, iir, input))
    flip := !flip.contents
    let count = ref(density)
    while count.contents > 1. {
      x := sineClip(x.contents * halfPi)
      count := count.contents - 1.
    }
    let r = Math.min(Math.abs(x.contents) * halfPi, halfPi)
    let shaped = density > 0. ? Math.sin(r) : 1. - Math.cos(r)
    x.contents > 0. ? x.contents * (1. - blend) + shaped * blend : x.contents * (1. - blend) - shaped * blend
  }
}

let mixerDrive = (~drive: float, ~sr: float) => {
  let scale = sr / 44100.
  let trim = Math.pow(10., ~exp=(drive * 48. - 24.) / 20.)
  let (iirA, iirB) = (0.001860867 / scale, 0.000287496 / scale)
  let (bqA, bqB) = (biquadDf1(lowpassBq(19160. / sr, 0.431684981684982)), biquadDf1(lowpassBq(19160. / sr, 1.1582298)))
  let (sa, sb) = (ref(0.), ref(0.))
  input => {
    let x = input - onePole(sa, iirA, input)
    let x = clip1(bqA(trim != 1. ? x * trim : x))
    let x = bqB(x - Math.pow(x, ~exp=5.) * 0.1768)
    x - onePole(sb, iirB, x)
  }
}

let edgeResos = [4.46570214, 1.51387132, 0.93979296, 0.70710678, 0.59051105, 0.52972649, 0.50316379]

let sevenStage = (~drive: float, ~tone: float, ~character: float, ~sr: float) => {
  let scale = sr / 44100.
  let trim = drive * drive * 4. + 0.5
  let cutoff = Math.max(0.001, Math.min(0.49, tone * 25000. / sr))
  let iir = Math.max(Math.pow(character, ~exp=3.) * 0.5, 0.00000001) / scale
  let stages = edgeResos->Array.map(reso => biquad(lowpassBq(cutoff, reso)))
  let s = ref(0.)
  input => {
    let x = ref(input - onePole(s, iir, input))
    for k in 0 to 5 {
      x := clip1((stages->Array.getUnsafe(k))(x.contents) * trim)
    }
    (stages->Array.getUnsafe(6))(x.contents)
  }
}

let bandClip = (x, thresh, hard) =>
  if Math.abs(x) <= thresh {
    x
  } else {
    let r = Math.sin(Math.min((Math.abs(x) - thresh) * hard, 1.5707963267949)) / hard
    x > 0. ? r + thresh : -.(r + thresh)
  }

let multiband = (~drive: float, ~tone: float, ~character: float, ~sr: float) => {
  let scale = sr / 44100.
  let tweak = 0.0414213562373095048801688
  let decay = 0.915965594177219015
  let iir = Math.pow(tone, ~exp=3.) / scale
  let gain = Math.pow(10., ~exp=drive * 24. / 20.)
  let thresh = character
  let hard = character < 1. ? 1. / (1. - character) : 1e21
  let trim = 1. + 1. + 0.597
  let (outH, outL, outD) = (trim, trim, 0.597 * trim)
  let out = Math.pow(10., ~exp=(0.75 - 1.) * 48. / 20.)
  let (l1, l2, l3, a, b, ia, ib) = (ref(0.), ref(0.), ref(0.), ref(0.), ref(0.), ref(0.), ref(0.))
  let flip = ref(false)
  let bands = (x: float, lows: float) => bandClip((x - lows) * gain, thresh, hard) * outH + bandClip(lows * gain, thresh, hard) * outL
  let antialias = d => {
    if flip.contents {
      a := a.contents * decay + d
      b := b.contents * decay - d
      a.contents * decay
    } else {
      b := b.contents * decay + d
      a := a.contents * decay - d
      b.contents * decay
    }
  }
  input => {
    let dry = input
    let halfDry = (input + l1.contents + (-.l2.contents + l3.contents) * tweak) / 2.
    l3 := l2.contents
    l2 := l1.contents
    l1 := input
    let halfway = bands(halfDry, onePole(ia, iir, halfDry))
    let raw = bands(input, onePole(ib, iir, input))
    let halfDiff = antialias(halfway - halfDry)
    let diff = antialias(raw - dry)
    flip := !flip.contents
    (dry * outD + diff + halfDiff) * out
  }
}

let wavefold = (~drive: float, ~tone: float, ~character: float) => {
  let density = drive * drive * 10.
  let stages = Float.toInt(character * 8.)
  let thresh = tone
  input => {
    let x = ref(input * density)
    for _ in 1 to stages {
      x := x.contents * (Math.abs(x.contents) + 1.)
    }
    let x = x.contents
    if x > 1.5707963267948966 {
      Math.sin(x) * thresh + (1. - thresh)
    } else if x < -1.5707963267948966 {
      Math.sin(x) * thresh - (1. - thresh)
    } else {
      Math.sin(x)
    }
  }
}

let bassAmp = (~drive: float, ~tone: float, ~character: float, ~sr: float) => {
  let scale = sr / 44100.
  let high = Math.pow(drive, ~exp=0.415)
  let dub = Math.pow(tone, ~exp=0.415) * 1.3
  let sub = character / 2.
  let driveOne = Math.pow(high * 3., ~exp=2.)
  let iir = 0.344 / scale
  let bassGain = dub * 0.1
  let bumpFreq = (bassGain + 0.0001) / scale
  let bassOut = dub * 0.2
  let subGain = sub * 0.1
  let subFreq = (subGain + 0.0001) / scale
  let subOut = sub * 0.3
  let hp = 0.0000014 / scale
  let (k1, k2, k3, k4, k5, k6, k7, k8) = (-0.646, 0.311, 0.114, 0.886, 0.122, -0.093, 0.057, -0.023)
  let last = Array.make(~length=6, 0.)
  let driveIir = Array.make(~length=6, ref(0.))->Array.map(_ => ref(0.))
  let head = [ref(0.), ref(0.), ref(0.)]
  let subs = [ref(0.), ref(0.), ref(0.)]
  let hps = Array.make(~length=26, ref(0.))->Array.map(_ => ref(0.))
  let (diff, fpd, wasNegative, subOctave, flip, turn) = (ref(0.), ref(2654435769.), ref(false), ref(false), ref(false), ref(0))
  let driven = (x, lows: ref<float>) => {
    let t = ref(x)
    let correction = ref(0.)
    let k = ref(flip.contents ? 0 : 1)
    while k.contents < 6 {
      let s = driveIir->Array.getUnsafe(k.contents)
      let v = onePole(s, iir, t.contents)
      t := t.contents - v
      correction := correction.contents + v
      k := k.contents + 2
    }
    let y = x - correction.contents
    lows := x - y
    let y = ref(clip1(y))
    let d = ref(driveOne)
    while d.contents > 0.6 {
      d := d.contents - 0.6
      y := y.contents - y.contents * (Math.abs(y.contents) * 0.6) * (Math.abs(y.contents) * 0.6)
      y := y.contents * 1.6
    }
    let y = y.contents - y.contents * (Math.abs(y.contents) * d.contents) * (Math.abs(y.contents) * d.contents)
    y * (1. + d.contents)
  }
  let turnStep = (pool: array<ref<float>>, add, freq, randy) =>
    if turn.contents >= 1 {
      let k = turn.contents - 1
      let h = ref((pool->Array.getUnsafe(k)).contents + add)
      h := h.contents - h.contents * h.contents * h.contents * freq
      let others = (pool->Array.getUnsafe(mod(k + 1, 3))).contents + (pool->Array.getUnsafe(mod(k + 2, 3))).contents
      pool->Array.getUnsafe(k) := (1. - randy) * h.contents + randy * 0.5 * others
    }
  input => {
    let dry = input
    let g = i => last->Array.getUnsafe(i)
    let halfDry = (input + g(0) + g(1) * k1 + g(2) * k2 + g(3) * k6 + g(4) * k7 + g(5) * k8) / 2.
    for i in 5 downto 1 {
      last->Array.setUnsafe(i, g(i - 1))
    }
    last->Array.setUnsafe(0, input)
    let (halfLows, lows) = (ref(0.), ref(0.))
    let halfway = driven(halfDry, halfLows)
    let x = driven(input, lows)
    let halfDry = dry * k3 + halfDry * k4
    let lastDiff = diff.contents * k5
    diff := (x - dry) / 2. + (halfway - halfDry) / 2. - lastDiff
    let x = dry + diff.contents
    let lows = lows.contents + halfLows.contents
    let randy = fpd.contents / uint32Max * 0.0555
    turnStep(head, lows * bassGain, bumpFreq, randy)
    let headSum = head->Array.reduce(0., (s, h) => s + h.contents)
    if headSum > 0. {
      if wasNegative.contents {
        subOctave := !subOctave.contents
      }
      wasNegative := false
    } else {
      wasNegative := true
    }
    let subIn = subOctave.contents ? Math.abs(headSum) : -.Math.abs(headSum)
    turnStep(subs, subIn * subGain, subFreq, randy)
    let subSum = subs->Array.reduce(0., (s, h) => s + h.contents)
    flip := !flip.contents
    turn := (turn.contents >= 3 ? 1 : turn.contents + 1)
    let x = x * high + headSum * bassOut + subSum * subOut
    let t = ref(x)
    let correction = ref(0.)
    hps->Array.forEach(s => {
      let v = onePole(s, hp, t.contents)
      t := t.contents - v
      correction := correction.contents + v
    })
    xorshift(fpd)
    x - correction.contents
  }
}

let grindResos = [4.46570214, 1.51387132, 0.93979296, 0.70710678, 0.52972649, 0.50316379]

// GrindAmp's 4x12 cabinet (dsp/Airwindows.cmajor grindCabA, grindCabB)
let grindCabA = [
  1.29550481610475132, 1.42302569895462616, 1.28728195804197565, 0.88553784290822690, 0.37129054918432319,
  -0.12150959412556320, -0.44900065463203775, -0.54058781908186482, -0.49361966401791391, -0.39819495093078133,
  -0.31379279985435521, -0.30744359242808555, -0.33943170284673974, -0.33838775119286391, -0.30682305697961665,
  -0.23408741339295336, -0.10411746814025019, 0.00133623776084696, 0.02461903992114161, 0.02086715842475373,
  0.02761433637100917, 0.04475285369162533, 0.09447338372862381, 0.13445890343722280, 0.13872868945088121,
  0.14915650097434549, 0.12766643217091783, 0.03675849788393101, -0.06307306864232835, -0.14947389348962944,
  -0.25235266566401526, -0.33496344048679683, -0.36590030482175445, -0.35015197011464372, -0.26808437585665090,
  -0.11624318543291220, 0.05617084165377551, 0.20540028692589385, 0.30455415003043818, 0.33810750937829476,
  0.31936133365277430, 0.27388548321981876, 0.21454597517994098, 0.15001045817707717, 0.07283437284653138,
  -0.03917872184241358, -0.16695932032148642, -0.27055854466909462, -0.33256357307578271, -0.33459770116834442,
  -0.27156687236338090, -0.17197093288412094, -0.06738628195910543, 0.00222429218204290, 0.01346992803494091,
  -0.02038911881377448, -0.08233579178189687, -0.15447855089824883, -0.20518281113362655, -0.22244686050232007,
  -0.21849243134998034, -0.20256105734574054, -0.18604070054295399, -0.17222844322058231, -0.14447856616566443,
  -0.10385520794251019, -0.07124435678265063, -0.05216857461197572, -0.05235381920184123, -0.07569701245553526,
  -0.10320125382718826, -0.12122120969079088, -0.13438969117200902, -0.13534390437529981, -0.11424128854188388,
  -0.08166894518596159, -0.04293976378555305, 0.00933076320644409, 0.06450430362918153, 0.10187400687649277,
  0.11039763294094571, 0.08557960776024547, 0.02730881850805332,
]

let grindCabB = [
  0.19713872057074355, 0.30599505521284787, 0.23168333460446133, 0.14263256172918892, 0.00150040944205920,
  -0.32776273620569107, -0.74101214925298819, -1.07821707459008387, -1.23540109014850508, -1.11247213730917749,
  -0.80330360359638298, -0.42132528876858205, -0.09183418349389982, 0.06453051658561271, 0.09549380253249232,
  0.08083404732361277, -0.00253651281245780, -0.04447267870865820, 0.07530671732655550, 0.22795860236804899,
  0.26108320417844094, 0.19160705011061663, 0.03681550508743799, -0.13713036462146147, -0.22401242373298191,
  -0.26718804981526367, -0.27745664795660430, -0.18338278173550679, -0.06089480869040766, -0.04642103054798480,
  -0.08423062596460507, -0.09808328256677995, -0.10622650888958179, -0.08982043516016047, -0.00735561860229533,
  0.07142484314510467, 0.11785854050350089, 0.20479174663329586, 0.29074864580096849, 0.29182307921316802,
  0.26535537727394987, 0.19735049990538350, 0.06415909270247236, -0.03831118543404573, -0.09281952429543777,
  -0.14306291461398810, -0.19138995946950504, -0.22531296466343192, -0.23305840475692102, -0.24091822618917569,
  -0.24062938573512443, -0.19083085091993421, -0.10268609751019808, 0.01439664435720548, 0.15947137113534526,
  0.26763170752416160, 0.29415931086406055, 0.26489186990840807, 0.16135382257522859, -0.00847180390247432,
  -0.14460595245753741, -0.18932793221831667, -0.17250665610927965, -0.12992472027850357, -0.09089219002147308,
  -0.08600465834570559, -0.09071532210549428, -0.06794061706070262, -0.02818101717909346, 0.00634228544764946,
  0.02751486906644141, 0.05434007312178933, 0.09135218559713874, 0.10437672041458675, 0.08693450726462598,
  0.06949989431475120, 0.05718625137421843, 0.01728285211520138, -0.02492994833691022, -0.03578455940532403,
  -0.03995523517573508, -0.03482514309492527, -0.00514750108411127,
]

let guitarAmp = (~drive: float, ~tone: float, ~sr: float) => {
  let scale = sr / 44100.
  let inLevel = drive * drive
  let trimEq = 1.1 - tone
  let toneEq = trimEq / 1.2
  let trimEq = trimEq / 50. + 0.165
  let eq = (trimEq - toneEq / 6.1) / sr * 22050.
  let bassEq = (trimEq + toneEq / 2.1) / sr * 22050.
  let out = 0.8
  let bassDrive = halfPi * (2.5 - toneEq)
  let cutoff = Math.max(0.001, Math.min(0.49, (18000. + tone * 1000.) / sr))
  let bqs = grindResos->Array.map(reso => biquad(lowpassBq(cutoff, reso)))
  let cycleEnd = Math.Int.max(1, Math.Int.min(4, Float.toInt(Math.floor(scale))))
  let (smooth, second, third) = (Array.make(~length=11, 0.), Array.make(~length=11, 0.), Array.make(~length=11, 0.))
  let iirs = Array.make(~length=9, ref(0.))->Array.map(_ => ref(0.))
  let cab = Array.make(~length=128, 0.)
  let refs = Array.make(~length=9, 0.)
  let (store, cabA, cabB, lastCab, fpd) = (ref(0.), ref(0.), ref(0.), ref(0.), ref(2654435769.))
  let (cabPos, cycle) = (ref(0), ref(0))
  let stage = (k, x, r) => {
    let inverse = (r + 1.) / 2.
    let y = smooth->Array.getUnsafe(k) + second->Array.getUnsafe(k) * inverse + third->Array.getUnsafe(k) * r + x
    third->Array.setUnsafe(k, second->Array.getUnsafe(k))
    second->Array.setUnsafe(k, smooth->Array.getUnsafe(k))
    smooth->Array.setUnsafe(k, x)
    y
  }
  let bq = (k, x) => (bqs->Array.getUnsafe(k))(x)
  let r = i => refs->Array.getUnsafe(i)
  let setR = (i, v) => refs->Array.setUnsafe(i, v)
  input => {
    let x = bq(0, input) * inLevel
    let x = clip1(x - onePole(iirs->Array.getUnsafe(0), eq, x) * 0.92)
    let x = ref(stage(0, x, Math.abs(x)))
    let bass = ref(x.contents)
    let y = bq(1, x.contents) * inLevel
    let y = clip1(y - onePole(iirs->Array.getUnsafe(1), eq, y) * 0.79)
    x := stage(1, y, Math.abs(y))
    for k in 2 to 8 {
      if k == 3 {
        x := bq(2, x.contents)
      } else if k == 4 {
        x := bq(3, x.contents)
      } else if k == 6 {
        x := bq(4, x.contents)
      } else if k == 8 {
        x := bq(5, x.contents)
      }
      let b = onePole(iirs->Array.getUnsafe(k), bassEq, bass.contents) * bassDrive
      let r = Math.sin(Math.min(Math.abs(b), halfPi))
      bass := (b > 0. ? r : -.r)
      x := stage(k, clip1(x.contents), r)
    }
    x := stage(9, x.contents, Math.abs(x.contents))
    x := stage(10, x.contents, Math.abs(x.contents))
    let bass = bass.contents / 2.
    let v = x.contents * toneEq + bass
    let v = (sineClip(v * out) + bass) / (1. + toneEq)
    let randy = fpd.contents / uint32Max * 0.061
    let v = ref((v * (1. - randy) + store.contents * randy) * out)
    store := v.contents
    cycle := cycle.contents + 1
    if cycle.contents >= cycleEnd {
      let temp = (v.contents + cabA.contents) / 3.
      cabA := v.contents
      v := temp
      cabPos := Int.bitwiseAnd(cabPos.contents + 1, 127)
      cab->Array.setUnsafe(cabPos.contents, v.contents)
      for k in 0 to 82 {
        let b = cab->Array.getUnsafe(Int.bitwiseAnd(cabPos.contents - 1 - k, 127))
        v := v.contents + b * (grindCabA->Array.getUnsafe(k) + grindCabB->Array.getUnsafe(k) * Math.abs(b))
      }
      let temp = (v.contents + cabB.contents) / 3.
      cabB := v.contents
      v := temp / 4.
      let randy = fpd.contents / uint32Max * 0.044
      let c = (v.contents * (1. - randy) + lastCab.contents * randy) * out
      lastCab := v.contents
      v := c
      switch cycleEnd {
      | 4 =>
        setR(0, r(4))
        setR(2, (r(0) + v.contents) / 2.)
        setR(1, (r(0) + r(2)) / 2.)
        setR(3, (r(2) + v.contents) / 2.)
        setR(4, v.contents)
      | 3 =>
        setR(0, r(3))
        setR(2, (r(0) + r(0) + v.contents) / 3.)
        setR(1, (r(0) + v.contents + v.contents) / 3.)
        setR(3, v.contents)
      | 2 =>
        setR(0, r(2))
        setR(1, (r(0) + v.contents) / 2.)
        setR(2, v.contents)
      | _ => setR(0, v.contents)
      }
      cycle := 0
    }
    let v = ref(r(cycle.contents))
    if cycleEnd >= 4 {
      setR(8, v.contents)
      v := (v.contents + r(7)) * 0.5
      setR(7, r(8))
    }
    if cycleEnd >= 3 {
      setR(8, v.contents)
      v := (v.contents + r(6)) * 0.5
      setR(6, r(8))
    }
    if cycleEnd >= 2 {
      setR(8, v.contents)
      v := (v.contents + r(5)) * 0.5
      setR(5, r(8))
    }
    xorshift(fpd)
    v.contents
  }
}

let bitcrush = (~drive: float, ~tone: float, ~sr: float) => {
  let scale = sr / 44100.
  let sonority = tone * 1.618033988749894848204586
  let depth = Math.Int.max(3, Math.Int.min(98, Float.toInt(17. * scale)))
  let derez = 1. - Math.pow(4., ~exp=-.drive)
  let s = derez > 0. ? 32768. * Math.pow(1. - derez, ~exp=6.) : 32768.
  let s = Math.max(s, 0.0001)
  let outScale = Math.max(s, 8.)
  let history = Array.make(~length=128, 0.)
  let pos = ref(0)
  input => {
    let x = input * s
    let quantA = Math.floor(x)
    let quantB = Math.floor(x + 1.)
    let past = history->Array.getUnsafe(Int.bitwiseAnd(pos.contents - depth, 127))
    let target = Math.min(Math.abs(x), sonority)
    let testA = Math.abs(Math.abs(past - quantA) - target)
    let testB = Math.abs(Math.abs(past - quantB) - target)
    let y = testA < testB ? quantA : quantB
    pos := Int.bitwiseAnd(pos.contents + 1, 127)
    history->Array.setUnsafe(pos.contents, y)
    y / outScale
  }
}

let glitterStep = (x, rez) => {
  let y = x > 0. ? Math.ceil(x / rez) * rez : x < 0. ? -.Math.ceil(-.x / rez) * rez : x
  let y = y * (1. - rez)
  Math.abs(y) < rez ? 0. : y
}

let lofi = (~drive: float, ~tone: float, ~sr: float) => {
  let scale = sr / 44100.
  let b = drive * drive
  let factor = Math.pow(b + 1., ~exp=7.) + 2.
  let divvy = Int.toFloat(Math.Int.max(1, Float.toInt(factor * scale)))
  let (rateA, rateB) = (1. / divvy, 1.61803398875 / divvy)
  let rez = Math.pow(4., ~exp=1. - 2. * tone)
  let (rezA, rezB) = (0.0016666666666667 * rez, 0.0026666666666667 * rez)
  let (last, heldA, heldB, posA, posB, lastOut) = (ref(0.), ref(0.), ref(0.), ref(0.), ref(0.), ref(0.))
  input => {
    let x = spiral(clip1(input) * 1.2533141373155)
    let halfway = (x + last.contents) / 2.
    last := x
    posA := posA.contents + rateA
    let a = ref(heldA.contents)
    if posA.contents > 1. {
      posA := posA.contents - 1.
      heldA := x * (1. - posA.contents)
      a := a.contents * 0.5 + heldA.contents * 0.5
    }
    posB := posB.contents + rateB
    let bb = ref(heldB.contents)
    if posB.contents > 1. {
      posB := posB.contents - 1.
      heldB := halfway * (1. - posB.contents)
      bb := bb.contents * 0.5 + heldB.contents * 0.5
    }
    let y = (glitterStep(a.contents, rezA) + glitterStep(bb.contents, rezB)) / 2.
    let out = y * 0.5 + lastOut.contents * 0.5
    lastOut := y
    out
  }
}

// The model for a distortion type (DistTypes: 6 on), or the input as it is.
let model = (kind, ~drive: float, ~tone: float, ~character: float, ~sr: float): (float => float) =>
  switch kind {
  | 6 => tube(~drive, ~sr)
  | 7 => tape(~drive, ~tone, ~sr)
  | 8 => saturate(~drive, ~character, ~sr)
  | 9 => mixerDrive(~drive, ~sr)
  | 10 => sevenStage(~drive, ~tone, ~character, ~sr)
  | 11 => multiband(~drive, ~tone, ~character, ~sr)
  | 12 => wavefold(~drive, ~tone, ~character)
  | 13 => bassAmp(~drive, ~tone, ~character, ~sr)
  | 14 => guitarAmp(~drive, ~tone, ~sr)
  | 15 => bitcrush(~drive, ~tone, ~sr)
  | 16 => lofi(~drive, ~tone, ~sr)
  | _ => x => x
  }

// One cycle of a sine of amplitude amp at about hz (a whole number of samples long) through f,
// once it has run long enough to settle: the cycle's inputs and outputs, `steps` of each (f runs
// at rate sr).
let sineCycle = (f: float => float, ~hz: float, ~sr: float, ~amp: float, ~settle: float, ~steps: int) => {
  let n = Math.Int.max(4, Float.toInt(Math.round(sr / hz)))
  let period = Int.toFloat(n)
  let cycles = Math.Int.max(1, Float.toInt(Math.ceil(settle * hz)))
  let total = cycles * n
  let start = total - n
  let inputs = []
  let outputs = []
  for i in 0 to total - 1 {
    let x = amp * Math.sin(2. * pi * Int.toFloat(i) / period)
    let y = f(x)
    if i >= start {
      inputs->Array.push(x)
      outputs->Array.push(y)
    }
  }
  // (thinned to `steps` points)
  let pick = a => Array.fromInitializer(~length=steps + 1, k => a->Array.getUnsafe(mod(k * n / steps, n)))
  (pick(inputs), pick(outputs))
}

//==============================================================================
// the air (Air4)

let air = (~air: float, ~body: float, ~darkFreq: float, ~darken: float, ~sr: float) => {
  let scale = sr / 44100.
  let airGain = air * 2.
  let airGain = airGain > 1. ? Math.pow(airGain, ~exp=3. + Math.sqrt(scale)) : airGain
  let groundGain = body * 2.
  let thresh = darkFreq * darkFreq / scale
  let (a1, a2, a3, a4, gain, groundAvg, last) = (ref(0.), ref(0.), ref(0.), ref(0.), ref(0.), ref(0.), ref(0.))
  dry => {
    let s4 = a4.contents - a3.contents
    let s3 = a3.contents - a2.contents
    let s2 = a2.contents - a1.contents
    let s1 = a1.contents - dry
    let acc3 = s4 - s3
    let acc2 = s3 - s2
    let acc1 = s2 - s1
    let acc22 = acc3 - acc2
    let acc21 = acc2 - acc1
    let out = -.(a1.contents + s3 + acc22 - (acc22 + acc21) * 0.5)
    gain := Math.min(gain.contents * 0.5 + Math.abs(dry - out) * 0.5, 0.3 * Math.sqrt(scale))
    a4 := a3.contents
    a3 := a2.contents
    a2 := a1.contents
    a1 := gain.contents * out + dry
    let ground = dry - (out * 0.5 + dry * (0.457 - 0.017 * scale))
    let avg = (ground + groundAvg.contents) * 0.5
    groundAvg := ground
    let x = (dry - avg) * airGain + avg * groundGain
    let t = ref(clip1(x))
    let sinew = thresh * Math.cos(last.contents * last.contents)
    if t.contents - last.contents > sinew {
      t := last.contents + sinew
    }
    if -.(t.contents - last.contents) > sinew {
      t := last.contents - sinew
    }
    last := clip1(t.contents)
    x * (1. - darken) + last.contents * darken
  }
}

// The gain f gives a sine of amplitude amp at each of hzs (rate sr): the output's part at that
// frequency (over whole cycles, after a few to settle) over the input's.
let response = (make: unit => float => float, ~sr: float, ~amp: float, hzs: array<float>) =>
  hzs->Array.map(hz => {
    let f = make()
    let period = sr / hz
    let cycles = Math.Int.max(2, Float.toInt(Math.ceil(0.02 * hz)))
    let settle = Float.toInt(Math.ceil(period * 2.))
    let n = Float.toInt(Math.round(period * Int.toFloat(cycles)))
    for i in 0 to settle - 1 {
      f(amp * Math.sin(2. * pi * Int.toFloat(i) / period))->ignore
    }
    let (re, im) = (ref(0.), ref(0.))
    for i in settle to settle + n - 1 {
      let phase = 2. * pi * Int.toFloat(i) / period
      let y = f(amp * Math.sin(phase))
      re := re.contents + y * Math.sin(phase)
      im := im.contents + y * Math.cos(phase)
    }
    2. * Math.sqrt(re.contents * re.contents + im.contents * im.contents) / Int.toFloat(n) / amp
  })
