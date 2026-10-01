// Runs whenever the patch is created, with or without the GUI open.
// Parameters are restored by the host, but the user waveforms, LFO shapes and response
// curves live in the patch's stored state and must be pushed into the DSP here.
// On a fresh instance it installs the factory bank and loads its first program, like
// Oatmeal does when it starts.

open PatchConnection

type response
@get_index external member: (resource, string) => unknown = ""
external asResponse: resource => response = "%identity"
@get external ok: response => option<bool> = "ok"
@send external arrayBuffer: response => promise<ArrayBuffer.t> = "arrayBuffer"
@val external isView: Type.Classify.object => bool = "ArrayBuffer.isView"
@val external codePoints: string => array<string> = "Array.from"
external asView: Type.Classify.object => Uint8Array.t = "%identity"
external asBuffer: Type.Classify.object => ArrayBuffer.t = "%identity"
external asBytes: Type.Classify.object => array<int> = "%identity"

let utf8 = text =>
  text
  ->codePoints
  ->Array.flatMap(ch => {
    let c = String.codePointAt(ch, 0)->Option.getOr(0)
    if c < 0x80 {
      [c]
    } else if c < 0x800 {
      [0xc0 ||| c >> 6, 0x80 ||| c &&& 63]
    } else if c < 0x10000 {
      [0xe0 ||| c >> 12, 0x80 ||| c >> 6 &&& 63, 0x80 ||| c &&& 63]
    } else {
      [0xf0 ||| c >> 18, 0x80 ||| c >> 12 &&& 63, 0x80 ||| c >> 6 &&& 63, 0x80 ||| c &&& 63]
    }
  })
  ->Uint8Array.fromArray

// readResource returns different things depending on the runtime: the native worker gives
// an array of (signed) byte values, or a string when the file happens to be valid UTF-8; the
// WebAudio runtime gives a fetch Response.
let toBytes = async (data: resource) =>
  if Type.typeof(data->member("arrayBuffer")) == #function {
    let response = asResponse(data)
    response->ok == Some(false) ? None : Some(Uint8Array.fromBuffer(await response->arrayBuffer))
  } else {
    switch Type.Classify.classify(data) {
    | String(text) => Some(utf8(text))
    | Object(o) if Array.isArray(o) => Some(Uint8Array.fromArrayLikeOrIterable(asBytes(o))) // wraps negative values to 0..255
    | Object(o) if isView(o) =>
      let view = asView(o)
      Some(
        Uint8Array.fromBuffer(
          view->TypedArray.buffer,
          ~byteOffset=view->TypedArray.byteOffset,
          ~length=view->TypedArray.byteLength,
        ),
      )
    | Object(o) => Some(Uint8Array.fromBuffer(asBuffer(o))) // empty unless it's an ArrayBuffer
    | _ => None
    }
  }

let readBytes = async (pc, path) => {
  let rec attempt = async paths =>
    switch paths {
    | list{} => None
    | list{p, ...rest} =>
      let bytes = try await toBytes(await pc->readResource(p)) catch {
      | _ => None
      }
      switch bytes {
      | Some(b) if TypedArray.length(b) > 0 => bytes
      | _ => await attempt(rest)
      }
    }
  await attempt(list{path, "/" ++ path})
}

// A new instance: install the factory bank, as Oatmeal does.
let installFactoryBank = async pc => {
  let factory = switch await readBytes(pc, "presets/oatmealprs.dat") {
  | Some(bytes) =>
    switch OatmealFormat.parseFile(bytes) {
    | Ok({programs}) => programs->Array.map(p => p.bytes)
    | Error(e) =>
      Console.log("Porridge: factory bank not available: " ++ e)
      []
    }
  | None => []
  }
  let all = Array.fromInitializer(~length=OatmealFormat.bankPrograms, i =>
    switch factory[i] {
    | Some(bytes) => Preset.fromOatmeal(bytes)
    | None => Preset.make(i == 0 ? "Init" : `Init ${Int.toString(i)}`)
    }
  )

  let first = all->Array.getUnsafe(0)
  Bank.sendValues(pc, first.values)
  Bank.sendShapes(pc, first.tables)
  pc->sendStoredStateValue("shapes", Bank.encodeShapes(first.tables))
  pc->sendStoredStateValue("program", 0)
  pc->sendStoredStateValue("bank", Preset.encodeBank(all))
}

let default = pc => {
  let seen = Map.make()
  let settled = ref(false)

  pc->addStoredStateValueListener(({key, value}) => {
    switch (key, value) {
    | ("shapes", String(shapes)) =>
      Bank.decodeShapes(shapes)->Option.forEach(Bank.sendShapes(pc, _))
    | _ => ()
    }
    if !settled.contents {
      seen->Map.set(key, value)
    }
  })
  pc->requestStoredStateValue("bank")
  pc->requestStoredStateValue("shapes")

  // Give the host a moment to answer; if there is no bank in the session this is a
  // new instance.
  setTimeout(() => {
    settled := true
    switch seen->Map.get("bank") {
    | Some(JSON.String(bank)) if String.length(bank) > 1000 => ()
    | _ => installFactoryBank(pc)->Promise.ignore
    }
  }, 400)->ignore
}
