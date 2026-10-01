// Oatmeal's parameters as Porridge's endpoints: endpoint id, DLL parameter name, byte offset
// in the version-38 program chunk, storage type. Read off the parameter table measured from
// Oatmeal.dll (OatmealParams); ids are the DLL's skin action names.

type kind =
  | @as("f32") F32
  | @as("i32") I32
  // low / high 16 bits of the int at 8428
  | @as("filter1") Filter1
  | @as("filter2") Filter2
  // uint32 phase (fraction * 2^32)
  | @as("pw") Pw

type t = {index: int, id: string, name: string, offset: int, kind: kind}

let isInt = f =>
  switch f.kind {
  | I32 | Filter1 | Filter2 => true
  | F32 | Pw => false
  }

let kindOf = (storage: OatmealParams.storage) =>
  switch storage {
  | F32 => F32
  | I32 => I32
  | Lo16 => Filter1
  | Hi16 => Filter2
  | U32 => Pw
  }

// The DLL leaves the unison parameters unnamed, and names the XY pad's actions just X and Y.
let idOf = action =>
  switch action {
  | "X" => "XY_X"
  | "Y" => "XY_Y"
  | action => action
  }

let nameOf = (p: OatmealParams.t) =>
  switch p.action {
  | "U_Voices" => "U voices"
  | "U_Detune" => "U detune"
  | "U_Spread" => "U spread"
  | "U_PitchJitter" => "U pitch jitter"
  | "U_PanJitter" => "U pan jitter"
  | _ => p.name
  }

let all = OatmealParams.params->Array.map(p => {
  index: p.index,
  id: idOf(p.action),
  name: nameOf(p),
  offset: p.offset,
  kind: kindOf(p.storage),
})
