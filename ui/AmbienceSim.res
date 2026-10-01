// The ambience's models run on an impulse, for its graphs: dsp/Ambience.cmajor at 48 kHz with
// the size settled (whole-sample delays), without the predelay, width and mix. Clear coat leaves
// out its SubTight (a slow follower that takes the subsonics out).

let sr = 48000.

type settings = {model: int, size: float, time: float, density: float, highTime: float, highFreq: float, lowTime: float, lowFreq: float, highCut: float}

let chainPrimes = [839., 1259., 1907., 421., 641., 907., 727., 1117., 1499., 523., 757., 1069.]
let loopPrimes = [1601., 2357., 3469., 2207., 3253., 4787., 1733., 2551., 3761., 2459., 3631., 5347.]
let chainG = [0.68, 0.58, 0.5]
let (clearCoatGain, verbTinyGain) = (0.33, 0.2)
let loopG = [0.42, 0.33, 0.24]

let clearCoat = [
  [65, 124, 83, 180, 200, 291, 108, 189, 73, 410, 479, 310, 11, 928, 23, 654],
  [114, 205, 498, 195, 205, 318, 143, 254, 64, 721, 512, 324, 11, 782, 26, 394],
  [118, 272, 292, 145, 200, 241, 204, 504, 50, 678, 424, 412, 11, 1124, 47, 766],
  [19, 474, 301, 275, 260, 321, 371, 571, 50, 410, 697, 414, 11, 986, 47, 522],
  [112, 387, 452, 289, 173, 476, 321, 593, 73, 343, 829, 91, 11, 1055, 43, 862],
  [60, 368, 295, 272, 210, 284, 326, 830, 125, 236, 737, 486, 11, 1178, 75, 902],
  [73, 311, 472, 251, 134, 509, 393, 591, 124, 1070, 340, 525, 11, 1367, 75, 816],
  [159, 518, 514, 165, 275, 494, 296, 667, 75, 1101, 116, 414, 11, 1261, 79, 998],
  [41, 741, 274, 59, 306, 332, 291, 767, 42, 881, 959, 422, 11, 1237, 45, 958],
  [251, 437, 783, 189, 130, 272, 244, 761, 128, 1190, 320, 491, 11, 1409, 58, 455],
  [316, 510, 1087, 349, 359, 74, 79, 1269, 34, 693, 749, 511, 11, 1751, 93, 403],
  [254, 651, 845, 316, 373, 267, 182, 857, 215, 1535, 1127, 315, 11, 1649, 97, 829],
  [113, 101, 673, 357, 340, 229, 278, 1008, 265, 1890, 155, 267, 11, 2233, 116, 600],
  [218, 1058, 862, 505, 297, 580, 532, 1387, 120, 576, 1409, 473, 11, 1991, 76, 685],
  [78, 760, 982, 528, 445, 1128, 130, 708, 22, 2144, 354, 1169, 11, 2782, 58, 1515],
  [330, 107, 1110, 371, 620, 143, 1014, 1763, 184, 2068, 1406, 595, 11, 2639, 33, 1594],
  [336, 1660, 386, 623, 693, 1079, 891, 1574, 24, 2641, 1239, 775, 11, 3104, 55, 2366],
]
// the seats and the span of each clear coat room
let clearCoatRooms = [
  (96, 5, 51), (107, 7, 52), (135, 8, 58), (143, 7, 61), (166, 8, 66), (189, 9, 70), (225, 7, 79),
  (252, 11, 80), (255, 8, 83), (323, 10, 93), (427, 9, 110), (470, 15, 110), (606, 11, 131),
  (643, 14, 132), (809, 5, 159), (984, 10, 171), (1541, 24, 203),
]
let verbTiny = [136, 52, 53, 1261, 209, 473, 549, 29, 92, 1137, 1406, 994, 1314, 191, 1263, 103]
let lettersL = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
let lettersR = [3, 7, 11, 15, 2, 6, 10, 14, 1, 5, 9, 13, 0, 4, 8, 12]

let clearCoatRoom = size => Math.Int.min(16, Float.toInt(size * 16.999))

// the room's size factor
let scale = size => 0.01 + 0.99 * size * size

// A delay line of whole samples: read the oldest, then write.
type line = {buf: Float32Array.t, mutable pos: int}
let line = n => {buf: Float32Array.fromLength(Math.Int.max(1, n)), pos: 0}
let push = (l, x) => {
  let z = l.buf->ByteView.getUnsafe(l.pos)
  l.buf->ByteView.setUnsafe(l.pos, x)
  l.pos = l.pos + 1 >= TypedArray.length(l.buf) ? 0 : l.pos + 1
  z
}
let allpass = (l, x, g) => {
  let z = l.buf->ByteView.getUnsafe(l.pos)
  let v = x + g * z
  l.buf->ByteView.setUnsafe(l.pos, v)
  l.pos = l.pos + 1 >= TypedArray.length(l.buf) ? 0 : l.pos + 1
  z - g * v
}

// a one-pole lowpass's gain, and one sample through it (state in s[k])
let onePoleGain = hz => {
  let k = Math.tan(Math.Constants.pi * Math.min(hz, 0.49 * sr) / sr)
  k / (1. + k)
}
let lowpass = (s: array<float>, k, x, g) => {
  let v = (x - s->Array.getUnsafe(k)) * g
  let y = v + s->Array.getUnsafe(k)
  s->Array.setUnsafe(k, y + v)
  y
}

let shelfGain = (t, h) => t <= 0. ? 1. : h > 0. ? (t + h * (1. - t)) / t : 1. + h

let room = (s, n, outL, outR) => {
  let f = scale(s.size)
  let r = sr / 48000.
  let chains = chainPrimes->Array.map(p => line(Float.toInt(p * r * f) + 1))
  let loops = loopPrimes->Array.map(p => line(Float.toInt(p * r * f) + 1))
  let c = 0.7 * s.time
  let (gH, gL) = (shelfGain(s.time, s.highTime), shelfGain(s.time, s.lowTime))
  let (kH, kL) = (onePoleGain(s.highFreq), onePoleGain(s.lowFreq))
  let fb = [0., 0., 0., 0.]
  let (hi, lo) = ([0., 0., 0., 0.], [0., 0., 0., 0.])
  let y = [0., 0., 0., 0.]
  let sv = [0., 0., 0., 0.]
  for i in 0 to n - 1 {
    let x = i == 0 ? 1. : 0.
    for k in 0 to 3 {
      let v = ref(x + fb->Array.getUnsafe(k))
      for j in 0 to 2 {
        v := allpass(chains->Array.getUnsafe(3 * k + j), v.contents, chainG->Array.getUnsafe(j) * s.density)
      }
      y->Array.setUnsafe(k, v.contents)
    }
    outL->ByteView.setUnsafe(i, 0.5 * (y->Array.getUnsafe(0) + y->Array.getUnsafe(1)))
    outR->ByteView.setUnsafe(i, 0.5 * (y->Array.getUnsafe(2) + y->Array.getUnsafe(3)))
    if c > 0. {
      for k in 0 to 3 {
        let v = ref(y->Array.getUnsafe(k))
        for j in 0 to 2 {
          v := allpass(loops->Array.getUnsafe(3 * k + j), v.contents, loopG->Array.getUnsafe(j) * s.density)
        }
        let h = lowpass(hi, k, v.contents, kH)
        let w = h + gH * (v.contents - h)
        let l = lowpass(lo, k, w, kL)
        sv->Array.setUnsafe(k, w + (gL - 1.) * l)
      }
      let sa = Array.getUnsafe(sv, ...)
      fb->Array.setUnsafe(0, c * (sa(0) - sa(2)))
      fb->Array.setUnsafe(1, c * (-.sa(1) - sa(3)))
      fb->Array.setUnsafe(2, c * (sa(1) - sa(3)))
      fb->Array.setUnsafe(3, c * (sa(0) + sa(2)))
    }
  }
}

// Four stages of 4x4 Householder matrices on lines, fed with x plus the feedback fb[from..]
// times regen; the last stage's feedback goes to fb[to..]. Returns the sum / 8.
let householder = (lines: array<line>, x, fb: array<float>, ~from, ~to, regen, ~mulch: option<ref<float>>) => {
  let v = Array.fromInitializer(~length=4, i => x + fb->Array.getUnsafe(from + i) * regen)
  let h = [0., 0., 0., 0.]
  for st in 0 to 3 {
    for i in 0 to 3 {
      h->Array.setUnsafe(i, push(lines->Array.getUnsafe(4 * st + i), v->Array.getUnsafe(i)))
    }
    if st == 3 {
      mulch->Option.forEach(m => {
        let raw = h->Array.getUnsafe(0)
        h->Array.setUnsafe(0, (3. * raw + m.contents) * 0.25)
        m := raw
      })
    }
    let sum = h->Array.reduce(0., (a, b) => a + b)
    for i in 0 to 3 {
      v->Array.setUnsafe(i, 2. * h->Array.getUnsafe(i) - sum)
    }
  }
  for i in 0 to 3 {
    fb->Array.setUnsafe(to + i, v->Array.getUnsafe(i))
  }
  h->Array.reduce(0., (a, b) => a + b) * 0.125
}

let sideLines = (lens: array<int>, letters) => letters->Array.map(l => line(lens->Array.getUnsafe(l)))

let clearCoatRun = (s, n, outL, outR) => {
  let lens = clearCoat->Array.getUnsafe(clearCoatRoom(s.size))
  let (ll, lr) = (sideLines(lens, lettersL), sideLines(lens, lettersR))
  let fb = Array.make(~length=8, 0.)
  let regen = 0.0625 * 0.999 * s.time
  let (mL, mR) = (ref(0.), ref(0.))
  for i in 0 to n - 1 {
    let x = i == 0 ? 1. : 0.
    let l = householder(ll, x, fb, ~from=0, ~to=0, regen, ~mulch=Some(mL))
    let r = householder(lr, x, fb, ~from=4, ~to=4, regen, ~mulch=Some(mR))
    outL->ByteView.setUnsafe(i, FxDsp.clamp(l, -1., 1.) * clearCoatGain)
    outR->ByteView.setUnsafe(i, FxDsp.clamp(r, -1., 1.) * clearCoatGain)
  }
}

// VerbTiny's Bezier undersampling: the step and trim at derez
let bezStep = derez => {
  let fraction = Float.toInt(1. / FxDsp.clamp(derez, 0.0001, 1.))
  let t = Int.toFloat(fraction) / Int.toFloat(fraction + 1)
  let step = 1. / Int.toFloat(fraction)
  (step, 1. - step * t)
}
let bezier = (b: array<float>, ch, trim) => {
  let x = b->Array.getUnsafe(8) * trim
  let (a, bb, c) = (b->Array.getUnsafe(ch), b->Array.getUnsafe(2 + ch), b->Array.getUnsafe(4 + ch))
  let cb = c * (1. - x) + bb * x
  let ba = bb * (1. - x) + a * x
  bb + cb * (1. - x) + ba * x
}

let verbTinyRun = (s, n, outL, outR) => {
  let (ll, lr) = (sideLines(verbTiny, lettersL), sideLines(verbTiny, lettersR))
  let fb = Array.make(~length=8, 0.)
  let overall = sr / 44100.
  let replace = s.time
  let regen = (1. - (1. - replace) * (1. - replace)) * 0.0625
  let attenuate = (1. - replace) * (1. - replace)
  let (derez, trim) = bezStep(1. / ((1. + 3. * s.size) * overall))
  let (derezF, trimF) = bezStep(1. / overall)
  let bez = Array.make(~length=9, 0.)
  let bezF = Array.make(~length=9, 0.)
  bez->Array.setUnsafe(8, 1.)
  bezF->Array.setUnsafe(8, 1.)
  let add = (b: array<float>, k, v: float) => b->Array.setUnsafe(k, b->Array.getUnsafe(k) + v)
  let shift = (b: array<float>, l: float, r: float) => {
    b->Array.setUnsafe(4, b->Array.getUnsafe(2))
    b->Array.setUnsafe(2, b->Array.getUnsafe(0))
    b->Array.setUnsafe(0, l)
    b->Array.setUnsafe(5, b->Array.getUnsafe(3))
    b->Array.setUnsafe(3, b->Array.getUnsafe(1))
    b->Array.setUnsafe(1, r)
    b->Array.setUnsafe(6, 0.)
    b->Array.setUnsafe(7, 0.)
  }
  for i in 0 to n - 1 {
    let x = i == 0 ? 1. : 0.
    add(bez, 8, derez)
    add(bez, 6, x * attenuate * derez)
    add(bez, 7, x * attenuate * derez)
    if bez->Array.getUnsafe(8) > 1. {
      bez->Array.setUnsafe(8, 0.)
      let l = householder(ll, bez->Array.getUnsafe(6), fb, ~from=4, ~to=0, regen, ~mulch=None)
      let r = householder(lr, bez->Array.getUnsafe(7), fb, ~from=0, ~to=4, regen, ~mulch=None)
      shift(bez, l, r)
    }
    let l = bezier(bez, 0, trim) * -0.25
    let r = bezier(bez, 1, trim) * -0.25
    add(bezF, 8, derezF)
    add(bezF, 6, l * derezF)
    add(bezF, 7, r * derezF)
    if bezF->Array.getUnsafe(8) > 1. {
      bezF->Array.setUnsafe(8, 0.)
      shift(bezF, bezF->Array.getUnsafe(6), bezF->Array.getUnsafe(7))
    }
    outL->ByteView.setUnsafe(i, bezier(bezF, 0, trimF) * 0.5 * verbTinyGain)
    outR->ByteView.setUnsafe(i, bezier(bezF, 1, trimF) * 0.5 * verbTinyGain)
  }
}

// The wet for an impulse into both sides, `seconds` long, through the high cut (left, right).
let impulse = (s, ~seconds) => {
  let n = Math.Int.max(16, Float.toInt(sr * seconds))
  let outL = Float32Array.fromLength(n)
  let outR = Float32Array.fromLength(n)
  switch s.model {
  | 1 => clearCoatRun(s, n, outL, outR)
  | 2 => verbTinyRun(s, n, outL, outR)
  | _ => room(s, n, outL, outR)
  }
  let g = onePoleGain(s.highCut)
  let st = [0., 0.]
  for i in 0 to n - 1 {
    outL->ByteView.setUnsafe(i, lowpass(st, 0, outL->ByteView.getUnsafe(i), g))
    outR->ByteView.setUnsafe(i, lowpass(st, 1, outR->ByteView.getUnsafe(i), g))
  }
  (outL, outR)
}

// How long the impulse takes to fall 60 dB below its peak energy (seconds), from its end back.
let decayTime = (x: Float32Array.t, y: Float32Array.t) => {
  let n = TypedArray.length(x)
  let total = ref(0.)
  for i in 0 to n - 1 {
    total := total.contents + FxDsp.sq(x->ByteView.getUnsafe(i)) + FxDsp.sq(y->ByteView.getUnsafe(i))
  }
  let rest = ref(total.contents)
  let at = ref(n)
  let k = ref(0)
  while at.contents == n && k.contents < n {
    let i = k.contents
    rest := rest.contents - FxDsp.sq(x->ByteView.getUnsafe(i)) - FxDsp.sq(y->ByteView.getUnsafe(i))
    if rest.contents <= total.contents * 1e-6 {
      at := i
    }
    k := i + 1
  }
  Int.toFloat(at.contents) / sr
}
