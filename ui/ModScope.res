// Where a modulation target is: in each voice, where each note moves it its own way, or on the
// whole sound, which has one value. A per-note source (ModMatrix.sourceScope) on a whole-sound
// target gives it the newest note's value, or every note's by its level (MM_Follow).

// The rack effect whose parameter a target moves, if any (not the voice's distortion: the
// rack's distortions start at 2).
let effectOf = {
  let byParam = Map.fromArray(FxRack.all->Array.flatMap(e => FxRack.params(e)->Array.map(id => (id, e))))
  t =>
    switch ModMatrix.targets[t] {
    | Some({law: Knob(id)}) => byParam->Map.get(id)
    | _ => None
    }
}
let copyOf = t => effectOf(t)->Option.mapOr(0, (e: FxRack.effect) => e.copy)

// the target groups inside the voice
let voiceGroups = ["voice", "osc", "filter", "lfo"]

let targetScope = (get: string => float, t): ModMatrix.scope =>
  switch ModMatrix.targets[t] {
  | Some(target) if voiceGroups->Array.includes(target.group) => EachNote
  // an effect in the voice lane: each voice runs its own
  | Some(_) if effectOf(t)->Option.mapOr(false, e => FxRack.holds(FxRack.readLane(get), e)) => EachNote
  // Oatmeal's distortion: in the voices unless it's on the whole sound alone
  | Some({group: "distortion"}) if effectOf(t) == None =>
    get("Sat_Mode") == ParamDefs.choiceValue("Sat_Mode", "global") ? Shared : EachNote
  | _ => Shared
  }

let sourceScopeOf = (get, s) =>
  switch ModMatrix.sources[s] {
  | Some(source) => ModMatrix.sourceScope(get, source.key)
  | None => ModMatrix.Shared
  }

// Whether a connection gives a whole-sound target the values of notes (its source or via source
// has one per note).
let followsNotes = (get, slot: ModMatrix.slot) =>
  targetScope(get, slot.target) == Shared &&
    (sourceScopeOf(get, slot.source) == EachNote || slot.via > 0 && sourceScopeOf(get, slot.via) == EachNote)

// What MM_Follow says, short, for a connection's cable.
let followText = get => get("MM_Follow") == 0. ? "newest note" : "all notes"

let scopeHelp = (scope: ModMatrix.scope) =>
  switch scope {
  | EachNote => "per-voice: each voice has its own value"
  | Shared => "one value every note shares"
  }
