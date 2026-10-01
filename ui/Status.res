// The status bar message: hover texts, or a hint about the current page when idle.

open! Web

type t = {msg: element, mutable idle: string}

let make = msg => {msg, idle: ""}

let show = (t, text) => {
  t.msg->setTextContent(text)
  t.msg->removeClass("idle")
}

let clear = t => {
  t.msg->setTextContent(t.idle)
  t.msg->addClass("idle")
}

let setIdle = (t, text) => {
  t.idle = text
  clear(t)
}
