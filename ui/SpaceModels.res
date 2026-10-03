// The space effects' models as one choice: reverb (the algo reverb's five models and Oatmeal's
// reverb), ambience (its three) and convolution (the convolver's characterful impulses, and a
// file). The add menus offer "reverb" once (FxRack.menuGroups); its tab's model list, the same
// on all four kinds, offers them all. A model of another kind swaps the effect for one of that
// kind in its place in the rack, carrying over what means the same on both (mix, predelay,
// decay), as one step of undo.
//
// The convolver's room, hall and plate impulses still load, and show while they are set, but
// aren't offered: the perceptual study found them one size continuum with the algo hall and
// plate. Its cabinets and telephone are a tone, not a space: the add menus' "cabinet", and only
// the convolver's list offers them.

type model = {
  label: string,
  kind: FxRack.kind,
  // the kind's parameter (the first's) and value for this model, if it has several
  param: option<(string, float)>,
  about: string,
  heading?: string,
  // Oatmeal's own
  classic?: bool,
  // offered only in the convolver's list (the cabinets)
  convolverOnly?: bool,
  // not offered, shown while set
  hidden?: bool,
}

let algoAbout = model =>
  switch model {
  | 1 => "plate: dense and bright from the first moment"
  | 2 => "nitrous: bright, dense and airy, a little metallic when small"
  | 3 => "basin: dark and huge, blooming in slowly"
  | 4 => "vintage: an 1980s digital reverb, grainy and band-limited"
  | _ => "hall: a large, smooth room"
  }

let impulseAbout = impulse =>
  switch impulse {
  | 0 => "a small room"
  | 1 => "a concert hall"
  | 2 => "a cathedral, with long echoes"
  | 3 => "a plate: bright and dense"
  | 4 => "a spring: boings and drips"
  | 5 => "a 1×12 guitar cabinet"
  | 6 => "a 4×12 guitar cabinet, darker"
  | 7 => "a metal tank's ringing modes"
  | 8 => "a telephone line"
  | 9 => "a swell, rising like a reversed reverb"
  | 10 => "a slowly blooming noise cloud"
  | _ => "an impulse response from a file of your own"
  }

let ambienceAbout = model =>
  switch model {
  | 1 => "clear coat (Airwindows): a small room's early reflections"
  | 2 => "verb tiny (Airwindows): a small reverb fed across the sides"
  | _ => "room: a few milliseconds of diffusion, different on each side"
  }

let algo = (label, ~heading=?) => {
  let v = PorridgeParams.reverbModels->Array.indexOf(label)
  {label, kind: #space, param: Some(("Rv_Model", Int.toFloat(v))), about: "algo reverb, " ++ algoAbout(v), ?heading}
}
let ambience = (label, name, ~heading=?) => {
  let v = PorridgeParams.ambienceModels->Array.indexOf(name)
  {label, kind: #ambience, param: Some(("Am_Model", Int.toFloat(v))), about: "ambience, " ++ ambienceAbout(v), ?heading}
}
let impulse = (label, name, ~heading=?, ~convolverOnly=?, ~hidden=?) => {
  let v = PorridgeParams.impulseNames->Array.indexOf(name)
  {
    label,
    kind: #convolve,
    param: Some(("Cv_Impulse", Int.toFloat(v))),
    about: "convolution, " ++ impulseAbout(v),
    ?heading,
    ?convolverOnly,
    ?hidden,
  }
}

let models = [
  algo("hall", ~heading="reverb"),
  algo("plate"),
  algo("nitrous"),
  algo("basin"),
  algo("vintage"),
  {label: "Oatmeal", kind: #reverb, param: None, about: "Oatmeal's reverb", classic: true},
  ambience("room", "room", ~heading="ambience"),
  ambience("clear coat", "clear coat"),
  ambience("tiny", "verb tiny"),
  impulse("spring", "spring", ~heading="convolution"),
  impulse("metal tank", "metal tank"),
  impulse("cathedral", "cathedral"),
  impulse("swell", "swell"),
  impulse("noise bloom", "noise bloom"),
  impulse("file", "file"),
  impulse("room (impulse)", "room", ~hidden=true),
  impulse("hall (impulse)", "hall", ~hidden=true),
  impulse("plate (impulse)", "plate", ~hidden=true),
  impulse("cabinet 1×12", "cabinet 1×12", ~heading="cabinet", ~convolverOnly=true),
  impulse("cabinet 4×12", "cabinet 4×12", ~convolverOnly=true),
  impulse("telephone", "telephone", ~convolverOnly=true),
]

let isCabinet = m => m.convolverOnly == Some(true)

// The model an effect of these kinds is at (-1 if none: an impulse that is neither).
let current = (get: string => float, e: FxRack.effect) =>
  models->Array.findIndex(m =>
    m.kind == e.kind &&
      switch m.param {
      | Some((first, v)) => get(FxRack.id(e, first)) == v
      | None => true
      }
  )

// Its menu: the models its list offers (the cabinets only on a convolver's), with the one it is
// at even if hidden.
let offered = (e: FxRack.effect, now) =>
  models
  ->Array.mapWithIndex((m, i) => (m, i))
  ->Array.filter(((m, i)) =>
    i == now || m.hidden != Some(true) && (!isCabinet(m) || e.kind == #convolve)
  )

let items = (e, now) =>
  offered(e, now)->Array.map(((m, i)) => {
    Menu.label: m.label,
    value: i,
    heading: ?m.heading,
    badge: ?(m.classic == Some(true) ? Some("classic") : None),
    hint: m.about,
  })

//==============================================================================
// choosing one

// What carries over between the kinds: the mix (0..1, dry and wet on an equal-power curve),
// the predelay (ms) and the decay (seconds), where a kind has them. A cabinet has none of a
// space's: it neither gives nor takes them.
type carried = {mix: option<float>, predelay: option<float>, decay: option<float>}

let halfPi = Math.Constants.pi /. 2.
// the algo reverb's decay knob, in seconds (PorridgeParams.spaceSpecs)
let decaySeconds = v => PorridgeParams.expValue(0.1, 30., v)
let decayKnob = seconds => PorridgeParams.expPos(0.1, 30., Math.max(0.1, seconds))

let carriedFrom = (get: string => float, e: FxRack.effect): carried => {
  let p = first => get(FxRack.id(e, first))
  switch e.kind {
  // (Oatmeal's dry and wet are gains of their own)
  | #reverb => {mix: Some(Math.atan2(~y=p("R_Wet"), ~x=p("R_Dry")) /. halfPi), predelay: Some(p("R_Predelay")), decay: Some(p("R_Length"))}
  | #space => {mix: Some(p("Rv_Mix")), predelay: Some(p("Rv_Predelay")), decay: Some(decaySeconds(p("Rv_Decay")))}
  | #ambience => {mix: Some(p("Am_Mix")), predelay: Some(p("Am_Predelay")), decay: None}
  | _ => {mix: Some(p("Cv_Mix")), predelay: Some(p("Cv_Predelay")), decay: None}
  }
}

// The parameter values that give an effect what carries over (each within its range).
let carriedTo = (e: FxRack.effect, c: carried): array<(string, float)> => {
  let some = (first, x) => x->Option.mapOr([], x => [(FxRack.id(e, first), x)])
  switch e.kind {
  | #reverb =>
    let mix = c.mix->Option.mapOr([], mix => [
      (FxRack.id(e, "R_Dry"), Math.cos(mix *. halfPi)),
      (FxRack.id(e, "R_Wet"), Math.sin(mix *. halfPi)),
    ])
    [...mix, ...some("R_Predelay", c.predelay), ...some("R_Length", c.decay)]
  | #space => [...some("Rv_Mix", c.mix), ...some("Rv_Predelay", c.predelay), ...some("Rv_Decay", c.decay->Option.map(decayKnob))]
  | #ambience => [...some("Am_Mix", c.mix), ...some("Am_Predelay", c.predelay)]
  | _ => [...some("Cv_Mix", c.mix), ...some("Cv_Predelay", c.predelay)]
  }
}

// Sets effect e to model i: the model's value, or e swapped for a free effect of the model's
// kind in e's place, switched on, with what carries over; then its tab opens. A gesture: one step
// of undo. (Only a convolver's list offers the cabinets: a cabinet is all wet, and a space from
// one starts at the usual mix.)
let choose = (ctx: Ctx.t, e: FxRack.effect, i) =>
  models[i]->Option.forEach(m => {
    let model = ctx.model
    let get = id => model->ParamModel.get(id)
    let set = (id, x) => {
      let x = ParamModel.def(model, id).clamp(x)
      if get(id) != x {
        model->ParamModel.gestureSet(id, x)
      }
    }
    let setModel = to => m.param->Option.forEach(((first, v)) => set(FxRack.id(to, first), v))
    let wasCabinet = models[current(get, e)]->Option.mapOr(false, isCabinet)
    if m.kind == e.kind {
      setModel(e)
      if isCabinet(m) != wasCabinet {
        let mix = FxRack.id(e, "Cv_Mix")
        set(mix, isCabinet(m) ? 1. : ParamModel.def(model, mix).init)
      }
    } else {
      let rack = FxRack.read(get)
      let others = rack->Array.filter(x => x != e)
      switch FxRack.free(others, ~lane=VoiceLane.lane(model), m.kind) {
      | Some(to) =>
        let carried = wasCabinet ? {mix: None, predelay: None, decay: None} : carriedFrom(get, e)
        VoiceLane.setAll(model, FxRack.values(rack->Array.map(x => x == e ? to : x)))
        VoiceLane.switchOn(model, to)
        setModel(to)
        carriedTo(to, carried)->Array.forEach(((id, x)) => set(id, x))
        model->ParamModel.nameStep(`${m.label} ${FxRack.kindName(m.kind)}`)
        ctx.openEffect(to)
      | None => ctx.toast(`Every ${FxRack.kindName(m.kind)} the rack has is in use`)
      }
    }
  })

//==============================================================================
// the list

// The model list of a space effect's tab, in a grid cell's box.
let picker = (ctx: Ctx.t, parent, e: FxRack.effect, ~x, ~y, ~w) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let now = () => current(get, e)
  let shown = () => models[now()]
  let refresh = Controls.picker(
    ctx,
    parent,
    ~x,
    ~y,
    ~w,
    ~label="model",
    ~text=() => shown()->Option.mapOr("", m => m.label),
    ~items=() => items(e, now()),
    ~current=now,
    ~set=i => choose(ctx, e, i),
    // (a right click stays with the effect's own kind)
    ~stepping=() => offered(e, now())->Array.filterMap(((m, i)) => m.kind == e.kind ? Some(i) : None),
    ~status=() =>
      shown()->Option.mapOr("", m => m.about) ++
      ". Click for the other reverbs, rooms and impulses: one of another kind takes this one's place, with its mix and predelay.",
  )
  // (the kind's model parameter, if it has one)
  models
  ->Array.find(m => m.kind == e.kind)
  ->Option.flatMap(m => m.param)
  ->Option.forEach(((first, _)) => model->ParamModel.listen(FxRack.id(e, first), refresh))
  refresh()
}
