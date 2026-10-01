// The CLAP plugin's bank library (tools/clap/PorridgeLibrary.h): the banks in the folders the
// user adds in the preset browser, which the plugin scans and copies, and the files opened in
// the browser, which it keeps. So the browser lists them without walking the folders each time,
// and still has them when the plugin window is opened again. The folders are a user setting
// ("bankFolders"). Elsewhere (cmaj play) nothing answers, and files opened in the browser last as
// long as the view.
//
// Banks are read from the plugin in parts, and parsed once per bank and version.

type origin = Folder | Opened

type bank = {
  id: string,
  name: string,
  origin: origin,
  // where a folder's bank was found, and the folder
  path: string,
  folder: string,
  modified: float,
}

type t = {
  channel: HostChannel.t,
  settings: Settings.t,
  // whether the plugin has answered
  mutable available: bool,
  mutable banks: array<bank>,
  mutable scanning: bool,
  // whether this view has scanned the folders yet
  mutable scanned: bool,
  listeners: array<unit => unit>,
  // reads in progress, by id: the parts so far, and what gets the file
  reads: Map.t<string, (array<Uint8Array.t>, option<Uint8Array.t> => unit)>,
}

let settingKey = "bankFolders"

// banks parsed already, by id and version: they're read again only when they change
let parsed: Map.t<string, result<array<Preset.t>, string>> = Map.make()
let versionKey = bank => bank.origin == Opened ? bank.id : `${bank.id}@${Float.toString(bank.modified)}`

let str = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.String(s)) => s
  | _ => ""
  }

let num = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.Number(x)) => x
  | _ => 0.
  }

let bankOf = (json: JSON.t) =>
  switch json {
  | Object(d) if str(d, "id") != "" =>
    Some({
      id: str(d, "id"),
      name: str(d, "name"),
      origin: str(d, "origin") == "opened" ? Opened : Folder,
      path: str(d, "path"),
      folder: str(d, "folder"),
      modified: num(d, "modified"),
    })
  | _ => None
  }

let changed = t => t.listeners->Array.forEach(fn => fn())

let onRead = (t, d: dict<JSON.t>) => {
  let id = str(d, "id")
  t.reads
  ->Map.get(id)
  ->Option.forEach(((parts, finish)) =>
    switch d->Dict.get("data") {
    | Some(String(data)) =>
      parts->Array.push(Bank.fromBase64(data))
      let part = Float.toInt(num(d, "part"))
      let count = Float.toInt(num(d, "parts"))
      if part + 1 < count {
        t.channel->HostChannel.request(
          "read=" ++ JSON.stringify(Object(Dict.fromArray([("id", JSON.String(id)), ("part", Number(Int.toFloat(part + 1)))]))),
        )
      } else {
        t.reads->Map.delete(id)->ignore
        let all = Uint8Array.fromLength(parts->Array.reduce(0, (n, p) => n + TypedArray.length(p)))
        parts->Array.reduce(0, (at, p) => {
          all->ByteView.blit(p, at)
          at + TypedArray.length(p)
        })->ignore
        finish(Some(all))
      }
    | _ =>
      t.reads->Map.delete(id)->ignore
      finish(None)
    }
  )
}

let onReply = (t, reply: dict<JSON.t>) =>
  switch (reply->Dict.get("read"), reply->Dict.get("banks")) {
  | (Some(Object(d)), _) => onRead(t, d)
  | (_, Some(Array(banks))) =>
    t.available = true
    t.scanning = false
    t.banks = banks->Array.filterMap(bankOf)
    changed(t)
  | _ =>
    t.scanning = false
    changed(t)
  }

let make = (pc, settings) => {
  let t = {
    channel: HostChannel.make(pc, "library"),
    settings,
    available: false,
    banks: [],
    scanning: false,
    scanned: false,
    listeners: [],
    reads: Map.make(),
  }
  t.channel->HostChannel.listen(onReply(t, _))
  t
}

let dispose = t => t.channel->HostChannel.dispose

let listen = (t, fn) => t.listeners->Array.push(fn)

let folders = t =>
  switch t.settings->Settings.savedValue(settingKey) {
  | Some(Array(items)) =>
    items->Array.filterMap(x =>
      switch x {
      | String(s) => Some(s)
      | _ => None
      }
    )
  | _ => []
  }

let scan = t => {
  t.scanned = true
  t.scanning = true
  changed(t)
  t.channel->HostChannel.request("scan=" ++ JSON.stringify(Array(folders(t)->Array.map(s => JSON.String(s)))))
}

// The banks: scanned the first time the view asks, then as the plugin last listed them.
let refresh = t => t.scanned ? t.channel->HostChannel.request("list") : scan(t)

let setFolders = (t, list) => {
  t.settings->Settings.save(settingKey, Array(list->Array.map(s => JSON.String(s))))
  scan(t)
}

// A folder as typed or pasted: without quotes around it or a slash at the end.
let cleanFolder = s => {
  let s = s->String.trim->String.replaceRegExp(/^["']|["']$/g, "")->String.trim
  String.length(s) > 3 ? s->String.replaceRegExp(/[\\/]+$/, "") : s
}

let addFolder = (t, folder) => {
  let folder = cleanFolder(folder)
  let list = folders(t)
  if folder != "" && !(list->Array.includes(folder)) {
    setFolders(t, [...list, folder])
  }
}

let removeFolder = (t, folder) => setFolders(t, folders(t)->Array.filter(f => f != folder))

// A bank's file, read from the plugin.
let read = (t, id) =>
  Promise.make((resolve, _) => {
    t.reads->Map.set(id, ([], resolve))
    t.channel->HostChannel.request(
      "read=" ++ JSON.stringify(Object(Dict.fromArray([("id", JSON.String(id)), ("part", Number(0.))]))),
    )
  })

// The presets of a bank, parsed once per version.
let presets = async (t, bank) =>
  switch parsed->Map.get(versionKey(bank)) {
  | Some(result) => result
  | None =>
    let result = switch await read(t, bank.id) {
    | Some(bytes) => Preset.parseFile(bytes)->Result.map(p => p.presets)
    | None => Error("the plugin couldn't read its copy")
    }
    parsed->Map.set(versionKey(bank), result)
    result
  }

// An opened file's id: its contents' hash (two 32-bit FNV-1a), so opening it again finds it.
let hashBytes: (Uint8Array.t, int) => string = %raw(`(bytes, seed) => {
  let h = seed >>> 0
  for (let i = 0; i < bytes.length; ++i) h = Math.imul (h ^ bytes[i], 16777619) >>> 0
  return h.toString (16).padStart (8, "0")
}`)

let idOf = bytes => "o" ++ hashBytes(bytes, 0x811c9dc5) ++ hashBytes(bytes, 0x050c5d1f)

let partSize = 384 * 1024

// Keeps a file opened in the browser, already parsed into presets; returns its id.
let keep = (t, ~name, ~ext, bytes: Uint8Array.t, presets) => {
  let id = idOf(bytes)
  parsed->Map.set(id, Ok(presets))
  let length = TypedArray.length(bytes)
  let parts = Math.Int.max(1, (length + partSize - 1) / partSize)
  for part in 0 to parts - 1 {
    let slice = bytes->TypedArray.subarray(~start=part * partSize, ~end=Math.Int.min(length, (part + 1) * partSize))
    t.channel->HostChannel.request(
      "put=" ++
      JSON.stringify(
        Object(
          Dict.fromArray([
            ("id", JSON.String(id)),
            ("name", JSON.String(name)),
            ("ext", JSON.String(ext)),
            ("part", Number(Int.toFloat(part))),
            ("parts", Number(Int.toFloat(parts))),
            ("data", JSON.String(Bank.toBase64(slice))),
          ]),
        ),
      ),
    )
  }
  id
}

let remove = (t, id) => t.channel->HostChannel.request("remove=" ++ id)
