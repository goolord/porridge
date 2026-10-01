// Complex numbers, for the frequency responses the effect and filter graphs draw.

type t = {re: float, im: float}

let make = (re, im) => {re, im}
let one = {re: 1., im: 0.}
let add = (a, b) => {re: a.re + b.re, im: a.im + b.im}
let mul = (a, b) => {re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re}
let scale = (a, k: float) => {re: a.re * k, im: a.im * k}
let div = (a, b) => {
  let d = b.re * b.re + b.im * b.im
  {re: (a.re * b.re + a.im * b.im) / d, im: (a.im * b.re - a.re * b.im) / d}
}
let abs = a => Math.sqrt(a.re * a.re + a.im * a.im)
// e^(j phase)
let expj = (phase: float) => {re: Math.cos(phase), im: Math.sin(phase)}

let pow = (c, n) => {
  let r = ref(one)
  for _ in 1 to n {
    r := mul(r.contents, c)
  }
  r.contents
}
