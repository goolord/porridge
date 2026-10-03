# Porridge UX plan: less noise, same depth

2026-10-02, at d5ceb58. Based on four audits run against HEAD: a UI inventory (every page, tab and
menu), a DSP/resource bench (MSVC test host, 8-voice chords, interleaved minimums), a usage census
of 1,513 real presets (17 factory, 1,432 from 33 third-party Oatmeal banks, 64 Vanilla), and a
perceptual study (loudness-matched ERB spectra of every filter and distortion type, oversampling,
waveforms, the reverb family). Scripts and raw reports live in the session scratchpad; the numbers
below are quoted from them.

## Summary

Porridge grew about 30 feature groups in two days (`PorridgeParams.groups`), almost all by adding
controls *beside* Oatmeal's rather than folding into them. The sound engine is in good shape (0.66x
Oatmeal's CPU, nearly every addition is gated when off). The interface and the host-facing surface
are not:

- 1,621 host parameters, 736 of them numbered copies of rack effects ("Ambience 3 high freq").
- 19 tabs on the Synth page, none of which says whether its feature is on.
- Four routing systems with four target vocabularies (mod env slots, XY slots, CC slots, the
  matrix) plus fixed depth knobs; a source's panel never shows its matrix routes.
- The voice lane drawn three times, inconsistently; the distortion filed under "whole sound"
  while it runs per voice.
- A 60-entry filter menu, 23 entries of which are effects, grouped by implementation
  ("zero-delay feedback", "normal", "analog"); several entries are measurably identical.
- Every control drawn at one size, whether it is cutoff or noise colour, set or at its default;
  about 35 lines of permanent prose standing in for structure.

The plan has five moves, in order of value per effort:

1. **Show state, hide defaults** (Phase 1, UI only): tab activity marks, "+ add" instead of
   empty slots, one switch per effect, prose into "?" tips, a smaller header, a shorter host list.
2. **One modulation model** (Phase 2): every routing, Oatmeal's included, is a row in one list
   and a chip on its source; select a source to light up everything it moves, on any page.
3. **One home per concern** (Phase 3): Synth makes the sound, Mod moves it, FX processes it,
   Play performs it; a signal-flow strip and a shared modulation layer keep interactions visible.
4. **Choosers by sound, not by implementation** (Phase 4): ~12 filter types with variant and
   character knobs, ~8 distortion characters, 3 space families, one saw.
5. **Cut what costs without paying** (Phase 5): rack copies, 8x oversampling, sample-split MIDI
   controllers, always-on routing scans, eagerly allocated buffers.

No separate "beginner mode": one interface that is quiet by default and deep on demand, plus a
Play page for people who want to perform rather than edit.

## Decisions (2026-10-02, from the review of this plan)

These override anything below that disagrees.

1. **Envelopes and LFOs stay on the Synth page** (the bottom panel). They are simple, and people
   who never touch the matrix still shape sounds with them. What leaves that panel is the clutter:
   the empty target slots become destination chips plus "+". The Mod page *additionally* offers
   them without breaking its patch-bay metaphor: the sources column stays a bay of chips with
   jacks and cables; selecting a chip (its name, not its jack) opens that source's editor, the
   same component as on the Synth page, in a panel over the lower part of the connections area,
   and the cables keep drawing above it.
2. **Controller timing is opt-in through MPE mode.** With MPE on, per-note and channel controllers
   (pressure, bend, slide, CCs) are applied once per block (ramped), without splitting blocks;
   notes stay sample-accurate. Outside MPE everything stays sample-accurate.
3. **No big "primary" knobs where a graph already edits the value** (cutoff/resonance on the
   filter response, envelope stages, EQ bands). The graph is the primary, WYSIWYG control; the
   ordinary slider stays as the compact precise one. Power is opted into ("more", "values", search),
   not shown by default.
4. **Effect copies: 4 to 3** per kind (the distortion: Oatmeal's plus rack copies 2-4). Values
   stay append-only; programs using a 4th copy are mapped onto a free copy on load, or warned
   about. Longer term, research arbitrary stacking without a fixed per-kind cost: Cmajor has no
   dynamic allocation, so this means generic rack slots that host any kind over a shared buffer
   pool (see Phase 5b).
5. **HQ Saw is the default; the aliasing waveforms are Oatmeal compatibility.** New and Init
   programs use the HQ waves; the waveform menu lists Saw / Pulse / Triangle (the HQ ones) first
   and the plain ones under an "Oatmeal (aliasing)" heading; Oatmeal imports keep their plain waves
   and an Oatmeal export still maps HQ to plain.

---

## Status (2026-10-02, after rounds 1 and 2)

Done, on main:
- Phase 1: tab marks (ui/Features.res), empty slots collapsed to "+", one switch per effect, no
  idle effect cards, duplicates removed, prose turned into "?" tips, the header (‹ name ›, A/B,
  Browse, Random, panic, ≡, gear), structural parameters out of the host list, undo/redo.
- Phase 2: one connections list with Oatmeal's built-in routes (those at their Init values folded
  away), source editors in the Mod page's bay, source focus across pages, one vocabulary, a menu on
  every control (ctrl+right-click; right-click still resets).
- Phase 3: four pages (Synth, Mod, FX, Play); the Synth page's voice flow and destination chips; the
  FX strip as the signal path; the Play page (macros, XY, arpeggiator, wheels, MIDI input, patch
  summary); the shapes editor as an overlay.
- Phase 4: filter, distortion and space pickers by family; rare values under "more"; HQ waves by
  default; consistent LFO names.
- Phase 5, in part: cached routing scans (-10 to -12 % per voice, bit-exact), MPE mode (controllers
  once a block: -47 % on a dense MPE stream), MIDI dispatch as a switch (-83 % of the rest), rack
  copies 4 to 3 with load-time migration and stable CLAP ids, a shared buffer pool (82.4 to 51.7 MB
  per instance).
- Phase 6: ctrl+K search and commands, A/B compare, keyboard nudging; the random generator draws user
  waves and routes the XY pad and the voice lane; Vanilla rebuilt around the voice lane.

Metrics now (Init): 24 parameter controls on the Synth page; 18 Synth tabs, marked when in use (with
Decision 1 keeping the envelopes and LFOs there, the marks matter more than the count, so that target
is dropped); 0 permanent prose lines; 13 header controls (9 without the page tabs); 12 entries on the
filter menu's first level; 879 host-visible parameters (the rest are effect copies 2-3's sound
parameters, kept automatable); 51.7 MB per instance (45 MB would mean cutting reachable delay or
convolver capacity).

Not done yet:
- DSP merges of the measured-identical filter and distortion types, Bode with the key shifter, and a
  single convolver instance: the pickers already offer each sound once, so what's left is memory,
  parameters and code size, not UX.
- Oversampling as an HQ switch: waits for the oversampling-gain fix in the DSP bug session.
- Free stacking: see Phase 5b (make CLAP ids independent of endpoint order first).

## 1. Diagnosis (evidence)

### 1.1 Everything has the same weight
`Grid.res` gives every parameter, list, switch and button the same footprint. On the Init Synth
page 44 controls are visible; most sit at their defaults (`target 1: none / depth 0.00 %` four
times per mod envelope, `noise 0.0 %`, `pm feedback 0.0 %`). Primary controls (waveform, cutoff,
resonance, the envelopes) look exactly like tertiary ones (noise colour, detune curve, pwm rate).

### 1.2 State hides behind tabs
Synth: osc 1 / osc 2 / noise / unison / phase / osc envs, filter / response / dual filter /
key EQ / voice fx, mod env 1 / 2 / pitch env / lfo 1 / 2 / 3, voice / tuning. Noise, unison, osc
envs, pitch env, key EQ, voice fx, LFO 3 and a loaded scale can all be active and invisible
(`Panel.res:40` draws a plain label).

### 1.3 Two architectures for the same jobs
Oatmeal's fixed structure and Porridge's flexible one are both on screen:

| Job | Oatmeal's way | Porridge's way |
|---|---|---|
| Modulate cutoff | LFO `cut 1` knob, mod env slot (30 targets), XY slot (33), CC slot (34), filter `touch`/`velocity`/`track` | matrix (483 targets), tray drag |
| Put an effect in the voice | distortion `where`, 23 filter "effect" types | voice lane (9 kinds) |
| Order effects | FX_Order (24 permutations) | rack drag |
| Per-voice vs shared | distortion `where`, LFO mode, touch mode | lane, matrix follow (MM_Follow), scope labels |

About 20 parameters are reachable from all four routing systems under different names ("cutoff 1"
/ "cutoff", "LFO 1 speed" / "LFO 1 rate", "2 pitch" / "osc 2 transpose", "distortion" / "dist
pregain"). Felt Piano routes LFO 1 to cutoff and pan through the matrix while its LFO tab shows
`cut 1 0` and `pan 0`: the tab looks unused. Mod page badges count matrix slots only.

### 1.4 Duplicates and contradictions
- Voice lane: Synth "voice fx" tab, FX strip "per-voice" tabs, FX routing row. The strip files
  Oatmeal's distortion under "whole sound" even when it runs per voice post-filter; the voice fx
  tab omits it.
- Effect on/off in up to four places (tab LED, card, "on" box, lane row); chorus and distortion
  switch off by a list value, others by a toggle.
- Output gain (amp panel, routing box), wheels (voice tab, Arp/XY), distortion type and where
  (routing, distortion tab), filter type/cutoff/reso (filter, response), osc mix / touch>amp /
  pm feedback (osc 1 and osc 2 tabs), preview switch and bank folders (browser, settings).
- Vanilla programs keep Oatmeal's chorus, delay and reverb cards in the rack while off, plus an
  EQ with every band off: four dead cards in Felt Piano.

### 1.5 Options organised by how they are built
- **Filter, 60 types:** ~19 lowpasses across four headings. Measured identical (≤0.1 dB mean
  band distance, also when driven): SVF morph = L/N/H at morph 0 = Sallen-Key; peak 12 = B/P/B
  and N/P/N at morph 0.5; low EQ boost = high EQ cut. Ladder ≈ MG low 24 (0.2 dB), comb ≈ comb +
  (0.2). French / German / clean drive / PZ SVF / SVF are within 0.2-0.7 dB unless driven. With
  cutoff compensation, 2P LP ≈ SVF, ladder ≈ diode ≈ acid, 2P narrow BP ≈ BP 12, 2P notch ≈
  notch 12 (all ≤0.8 dB). Usage: Oatmeal presets use 13 types, 87 % of them in five; 34 of
  Porridge's 44 types appear in no preset.
- **Distortion, 17 types:** at matched drive, hard / soft / custom (default curve, 0.0 dB from
  hard) / tube / saturate / mixer drive cluster within 0.3-1.6 dB; on a sine they all converge to
  the same odd series. Distinct: asymmetric (the only even harmonics), fold, tape, 7-stage /
  multiband, the amps, bitcrush, lo-fi.
- **Oversampling off / 2x / 4x / 8x:** 2x already puts aliasing 40+ dB down; 8x aliases *more*
  than 4x (32-tap filter, 4 taps a phase). The filters are not unity gain: -0.9 / -3.8 / +6.8 dB.
  So the switch is heard as a level and tone change. 8x guitar amp costs 6.3 % of a core per voice.
- **Waveforms:** plain Saw and Pulse alias at -24 to -32 dB on keys 54-64 (one table covers that
  octave); HQ stays below -63 dB everywhere and is otherwise 0.0-0.2 dB from plain. Plain Triangle
  is already clean. "Saw" and "Saw HQ" are one choice that should not be a choice.
- **Space:** Oatmeal reverb, algo reverb (5 models), ambience (3), convolver (11 impulses), filter
  reverb/diffusor. Algo hall / plate / nitrous and convolver plate are within 0.4-1.0 dB and
  0.04-0.09 decay-shape; convolver room / hall / cathedral are one size continuum; cabinets and
  telephone are EQ, not space.
- **Two frequency shifters** (Bode in the rack, the key shifter in the lane), **phasers in five
  places** (Oatmeal filter 4/12/36, filter phaser/+/-, rack, lane), **four EQs**.
- Rarely used Oatmeal values crowd menus: 7 glide modes (two cover 96 %), 18 LFO units (three
  cover ~90 %), arp units (16ths alone 85 %).

### 1.6 Naming drift and Oatmeal-isms
"touch" / "aftertouch" / "pressure"; "track" / "keytrack" / "note track" / "freq >" / "on note";
"noise" for three things; "random" about twelve ways; "voices" for polyphony, unison copies and
chorus voices; "mix" for the osc mode and for wet/dry. Glide `P·(o+1/o)`, LFO rates in "units",
diffusion in "Pi", `cut 1 / cut 2`, `rate 2`, Oat mode among the synthesis controls. LFO 1/2 and
LFO 3 differ in shape list, case, order, rate model and features.

### 1.7 Prose and hidden gestures
About 35 permanent lines (FX routing 4 lines / 95 words, osc envs 6, MPE 6, voice fx 3, Mod footer
2, tuning 2, key EQ 2, LFO 3 2). Meanwhile essential gestures live only in a status line that gets
truncated: macro rename, alt-drag amount, double right-click host menu, the LFO reset/free second
click, ctrl+F, the routing tab's unlabelled distortion places.

### 1.8 The host and the machine
- 1,621 automatable parameters (`ParamStore.cmajor` has no `automatable: false`; the CLAP wrapper
  exposes exactly the automatable ones). 736 are rack copies 2-4, 245 are custom-shaper points,
  256 are matrix fields of which only the 32 amounts make sense to automate.
- 82.4 MB of state per instance, all touched by `initialise`: rack copies 2-4 hold 41.6 MB, delay
  lines sized for 15 s 21 MB, voice-lane buffers 6.4 MB allocated with an empty lane. An
  Oatmeal-equivalent core would be about 22 MB.
- 80 % of the 6.3 MB generated header scales with the parameter count (78 s MSVC builds).
- Always-on per-block work: Oatmeal's routing scans 7-14 % of every voice, Porridge's bookkeeping
  5-8 %. Sample-accurate MIDI splits every block at every controller: +20 % CPU with a dense mod
  wheel, +78 % with MPE.

### 1.9 What matters to real presets (keep it prominent)
Effects 95 %, osc 2 83 %, filter 80 %, **user waveforms 75 %**, resonance 74 %, chorus 64 %, delay
61 %, reverb 58 %, **XY pad 53 %**, filter envelope 52 %. The random generator touches neither user
waveforms nor the XY pad. The Vanilla bank (built Oct 1) uses no voice lane, LFO 3, osc envs, key
EQ or distortion models, so zero usage of those says nothing about their worth; it says nobody
is shown them.

---

## 2. Principles

1. **One home per concern, one visual language across homes.** Synth makes sound, Mod moves it,
   FX processes it, Play performs it. Modulation and per-voice-ness look the same everywhere.
2. **In use beats available.** A control at its default and unmodulated is noise unless it is a
   primary control of its block. Unused features collapse to a "+".
3. **Two tiers per block.** Shown (graphs as the primary controls, ordinary sliders beside them)
   and more (behind the block's "more", or reached by search). See Decision 3.
4. **Structure, not prose.** No paragraph on screen; a "?" where a concept needs words.
5. **Name by sound.** Lowpass > character, not ZDF > ladder. One word per concept, everywhere:
   label, matrix target, status line, host name.
6. **Lose nothing.** Every parameter stays reachable in two clicks or by search; Oatmeal import,
   export and Oat mode stay lossless; preset values stay append-only, removed DSP options map to
   their nearest survivor on load.
7. **No beginner mode.** Quiet-by-default editing plus a Play page serves both; two UIs would
   double the work and strand people in one of them.

---

## 3. Target design

### 3.1 Pages and header

```
porridge  [Synth][Mod][FX][Play]      [‹] 01 bassmeh ▾ [›]  [Browse] [⚂] [≡] [⚙]
```

- Six pages become four. **Shapes** becomes an overlay editor opened from "draw" (and from a
  waveform menu's "edit shape…"). **MIDI** splits: performance response (velocity and aftertouch
  curves, MPE) moves to Play; channel filter, sustain switch and CC learn move to a MIDI section in
  Settings (channel filter and curves are used by 0-0.3 % of presets).
- Header: the program name opens the browser (the 64-program menu becomes the browser's "This
  bank" view), ⚂ opens the Random drawer, ≡ holds Load, Save program, Save bank, Export for
  Oatmeal, Program info, Init, New bank, Panic (Panic also on Esc-Esc or a small icon if live use
  wants it). Rename stays a double-click, now with a pencil on hover.

### 3.2 Synth page: the voice, as a signal path

```
┌ flow ─────────────────────────────────────────────────────────────────────────┐
│ [osc 1 saw][osc 2 user ▸+7][noise] → [filter ladder 2.1k] → [▹dist] → [amp] → ⇒ FX │  per-voice tint
└───────────────────────────────────────────────────────────────────────────────┘
┌ oscillators ───────────┐┌ filter ─────────────────┐┌ amp ──────────────────┐
│ osc 1  ∿ saw ▾   lvl   ││ type ladder ▾ (character)││  [ amp envelope ]     │
│ osc 2  ✎ user ▾ +7 st  ││ cutoff  reso  env  key   ││                       │
│ mix: hard sync ▾       ││ [ filter envelope ]      ││ level  velocity       │
│ + noise  + unison      ││ + 2nd filter  + key EQ   ││ voice: poly 8 · glide │
└────────────────────────┘└──────────────────────────┘└───────────────────────┘
┌ per-voice effects (the lane) ──────────────────────┐┌ voice ────────────────┐
│ [dist: tube ·drive·mix] [phaser ·rate·mix] [+]     ││ poly/mono, glide, bend│
│                                                    ││ transpose, tuning ▸   │
└────────────────────────────────────────────────────┘└───────────────────────┘
```

- The flow strip is the voice's real order (`VL_FilterAt`, `VL_AmpAt`, Sat_Mode included): click
  a node to scroll to its block, drag a lane node to move it. It replaces the FX routing tab's
  per-voice row and the voice fx tab. Oatmeal's distortion is a node like any lane effect; its
  `where` is its position (pre-filter, post-filter, whole sound, or both).
- Oscillators as rows, not tabs: each shows its wave thumbnail, level and pitch; the mix mode sits
  between them. Noise, unison, phase/retrigger and osc envs are "+" rows that expand when used.
  Drift moves to unison's "more" except drift cutoff, which goes to the filter.
- Mod envelopes, pitch envelope and LFOs stay in the bottom panel (Decision 1), with their target
  slots replaced by destination chips and "+"; the voice lane gets its own row in that panel or
  shares it, decided when laying the page out.
- Promote the per-voice lane to the main page: it is the identity, and Vanilla never shows it.

### 3.3 Mod page: sources and everything they move

- Left: sources as cards with a live mini-graph (LFOs, envelopes, macros, XY, wheels, MIDI
  controllers, per-note sources). The common twelve first; the note sources (chord place, gap,
  legato, alternate, cycle, interval, glide, pitch, held notes, voice level, noise, random) fold
  under "note sources". Selecting a card shows its editor (shape, rate, envelope) and its
  destinations.
- Right: **one connections list** with every route: matrix slots *and* Oatmeal's built-ins (mod
  env slots, LFO 1/2 depths, XY slots, CC slots, filter env / key / velocity / touch, touch > pitch
  and amp, freq > env and pan). Built-in rows carry a small "Oatmeal" badge and edit their own
  parameters; their targets are limited to Oatmeal's list, which the picker shows. Rows show
  `via` and options only when set (they are unused in every preset), with a "⋯" to add them.
- The four target vocabularies collapse to one: the knob's own label (Modulators already resolves
  Oatmeal targets to parameters; extend it to pitch, pan, volume, LFO pitch/pan and the envelope
  speeds, which are never marked today).
- Quick edit anywhere: clicking a source chip in the tray or a modulator mark on a knob opens a
  small popover with the source's main controls and its routes, so separation never forces a page
  switch.

### 3.4 FX page: the whole sound

- Strip: `per-voice: [lane…] ⇒ whole sound: [dist] › [chorus] › [delay] › [+] → out [gain]`. The
  routing tab and its 95-word note go; the strip is the routing. Output gain lives in one place.
- One switch per effect (the tab LED), and an off effect recedes. Chorus "mode: off" and
  distortion "type: off" become the LED; their lists start at the first real mode.
- The add menu offers kinds, never copies ("Chorus", not "Chorus 2"), grouped by job: drive, tone,
  movement, pitch, echo, space, dynamics, utility.
- Effect editors stay (they are the best-designed part of the app) but lead with their primary
  row, with graphs that earn their space; the algo reverb's decorative "space" picture shrinks.

### 3.5 Play page: performing, and the beginner's front door

Macros (big, named per program, showing what they move), the XY pad with its routes (53 % of
Oatmeal presets use it), wheels (once), the arpeggiator, MPE, velocity and aftertouch curves, and
the patch summary (`PatchGen.describe`: osc / filter / env / mod / fx, each line a link to its
editor) with "vary" from the Random drawer. A program can name Play as its landing page.

### 3.6 The modulation layer (what keeps separation from hiding interactions)

- **Source focus:** select a source (card, tray chip, modulator mark) and every target it moves
  lights in its colour on every page; page tabs show counts ("FX ·2"); the flow strip marks the
  blocks it touches. Esc clears.
- **Target view:** hovering a control lists its modulators in their colours, all four systems
  included, with the named macro ("tone", not "macro 2"). Bands stop covering the readout.
- **Live motion:** per-voice marks (VoiceView) and swept bands on every modulated control,
  including graphs' points (exists; extend coverage).
- **Per-voice tint:** one colour/texture for "each voice has its own" on the flow strip's voice
  part, lane cards, per-voice sources and targets; one word for it everywhere: *per-voice*, and
  *whole sound* for the rest.
- **Tab marks:** a dot on any tab whose feature is on, in the colour of a source if modulated.

### 3.7 Choosers by sound

- **Filter:** families first, character second, variants as knobs. Lowpass (1-pole, 12 dB SVF,
  24 dB ladder, driven), Highpass, Bandpass, Notch, Peak, Shelf/tilt, Morph, Comb/flanger, Phaser,
  Formant, and an "effects" corner (ring mod, S&H, reverb/diffusor). Slope, polarity, stages and
  vowel set become a variant control beside the type (MG 6/12/18/24, 1P/2P/4P, comb +/-, phaser
  4/12/36, formant I/II/III, BP/notch 12/24 are all one type each). Characters (clean, analog,
  diode, acid, dirty, French, German) become a character list on the ladder and SVF. This is
  UI-only first: the picker maps (type, variant, character) onto today's values, so presets and
  Oatmeal export are untouched. Oatmeal's 16 keep a "classic" badge and stay in Oat mode.
- **Distortion:** soft clip with a knee (absorbs hard, custom-default, tube, saturate, mixer),
  asymmetric, fold, tape, dense/multiband, amps, bitcrush, lo-fi; custom stays as the shape editor.
  Oversampling becomes an "HQ" switch (a gain-corrected 4x), no 8x.
- **Space:** Reverb (one entry; models hall/plate/dark/long, Oatmeal's classic), Ambience (room,
  clear coat, tiny), Convolve (spring, metal tank, cathedral, swell/bloom, file). Cabinets and
  telephone move to drive/tone as a "cabinet" option.
- **Waveforms:** Sine, Saw, Pulse, Triangle, User, User PWM; HQ tables always outside Oat mode.
- **Rare Oatmeal values** (glide modes, quintuplet units, unsynced delay units) sit under "more"
  in their lists, plain names first ("glide: constant time / by interval").
- **LFOs:** one layout for LFO 1, 2 and 3: shape (same names and order; user shape where it
  exists), per-voice / shared (and the reset/free choice as a visible third state), rate with a
  sync switch and a division list (triplet/quintuplet as modifiers), delay, fade, phase.

### 3.8 Power users

- **Search / command palette** (ctrl+K or "/"): any parameter by name or host name, jump and
  highlight; commands ("add chorus", "connect LFO 1 to cutoff", "init filter").
- **Undo / redo** for every edit, grouped by gesture (there is none today outside Shapes and MIDI
  curves), and **A/B compare** of the program.
- **"Show all"** per block reveals the "more" tier in place; a global setting can keep it open.
- **Context menu on every control:** modulate with ▸, show modulators, MIDI learn, reset, copy /
  paste value, host menu (replacing the hidden double right-click).
- Keyboard: arrows nudge the hovered control, shift fine, ctrl+arrows coarse; Enter types a value.

### 3.9 Beginners

- Play page as described; Random drawer with kinds and wildness (it already writes the best
  plain-language patch descriptions in the app).
- Quiet editing pages: on Init, the Synth page should show about 20 controls, not 44.
- Every "?" explains one concept in two sentences; hints that matter are never truncated (the
  status line gets a second line or a tooltip).
- Vanilla rebuilt to show the identity: per-voice lane presets, LFO 3, osc envs, key EQ, XY and
  user waveforms, and no dead effect cards.

---

## 4. Keep, hide, merge, cut

| Item | Verdict | Evidence | Saving / risk |
|---|---|---|---|
| Rack copies (4 of each kind, 5 distortions) | **Cut to 2** (lane and rack each get the copies they need), or restructure as generic slots later | 736 params (45 %), 41.6 MB, ~2.3 MB of header | ~400 params, ~28 MB/instance, faster builds. Check presets for a 3rd copy first; map or refuse on load |
| Custom-shaper points (245) | **Stored state**, not host parameters | 49 per distortion x 5 | 245 params; no audio change |
| Matrix fields other than amount (224) | **`automatable: false`** | nobody automates a target choice | 224 params; verify state save keeps them |
| Other structural lists (rack and lane slots, ME/XY/CC targets, FX_Order, Oat mode, channel switches, tuning) | **`automatable: false`** | | a few hundred more; host list ~500 |
| Oversampling 2x/4x/8x | **Merge** to HQ on/off (gain-corrected 4x); drop 8x | 8x aliases more than 4x; filters at -3.8 / +6.8 dB; 8x guitar amp 6.3 %/voice | check Oat-mode exactness before correcting gain |
| HQ waveforms | **Merge** into Saw/Pulse/Triangle | plain aliases -24..-32 dB at keys 54-64; HQ otherwise identical | plain stays for Oat mode |
| Identical filter types (SVF = L/N/H m0 = Sallen-Key; peak 12 = B/P/B m.5 = N/P/N m.5; low/high EQ mirrors) | **Merge** (alias values on load) | 0.0-0.1 dB, also driven | Porridge-only, unused outside Vanilla |
| Near-identical filter types (ladder/MG 24, comb/comb +, French/German/clean drive/PZ SVF, 2P narrow BP / BP 12, notch 12/24) | **Hide** behind variant/character controls; merge DSP later if the character knob covers them | 0.2-0.8 dB | none |
| Filter "effect" types (comb, flanger, phaser, formant, EQ, ring, S&H, diffusor, reverb: 23) | **Move** to an effects corner of the picker; the lane is their home | 34 of 44 Porridge types unused | keep values |
| Oatmeal filter phaser 4/12/36 | **Keep, hide** (classic) | 4 and 36 never used, 12 once; 36 costs 0.36 %/voice | compat |
| Distortion 17 types | **Merge** to ~8 characters + knee | hard/soft/custom/tube/saturate/mixer within 0.3-1.6 dB | Porridge-only types are unused in presets |
| Reverb family (5 kinds, 204 params, 36 MB) | **Merge** to Reverb / Ambience / Convolve; drop convolver room/hall/plate impulses | hall/plate/nitrous/conv plate 0.4-1.0 dB apart | -52 params, ~5 MB; one convolver instance saves 6.45 MB |
| Bode and key shifter | **Merge** to one frequency shifter with "follow note" | two Hilbert shifters | params, code |
| Sample-accurate MIDI for controllers | **Change**: split blocks on notes and arp steps only; ramp controllers per block | +20 % (dense CC), +78 % (MPE) | keep sample-accurate notes |
| Always-on routing scans (Oatmeal 7-14 %, Porridge 5-8 % of a voice) | **Cache** "any routes live" when parameters change | measured with stubs | 12-18 % of all voice CPU, no feature loss |
| Delay lines sized for 15 s, lane buffers with an empty lane | **Allocate on use** / size to the real maximum | 21 MB + 6.4 MB | ~20 MB/instance |
| MIDI CC slots (6 x 4 targets) | **Keep for compat**, show as built-in connections; page goes | 7 % of presets, 3 of 20 authors, always CC 1 | |
| MIDI channel filter, curves | **Settings / Play "more"** | 0-0.3 % | |
| Matrix hold / slew / curve / steps | **Keep, hide until asked** (the "⋯") | unused in every preset; 32 with all options +0.15 %/voice | |
| User waveforms, XY pad | **Promote** (Synth rows show the drawn wave; Play hosts XY); teach the random generator both | 75 % and 53 % of Oatmeal presets | |
| Voice lane, LFO 3, osc envs, key EQ, distortion models | **Keep, show** in Vanilla and the generator before judging | never used because never shown | |

---

## 5. Roadmap

Each phase ships on its own branch/worktree (other sessions share this checkout), keeps
`tools/test` green (golden.mjs bit-exact in Oat mode, presets.mjs round trips, random.mjs), and
ends with before/after screenshots of every page from the ui-preview harness.

**Phase 1: declutter in place (UI only, ~2 sessions)**
1. Tab activity marks (`Panel.res`): a predicate per tab from a new `Features.res` registry
   (isActive, its parameters, its tab), which the summary, the export losses and the generator
   can share.
2. Empty slots collapse: mod env, XY and CC target rows show used rows + "+ add target"; matrix
   rows hide unset via/options.
3. One effect switch; no dead cards (list-value "off" becomes the LED).
4. Remove duplicates: wheels (keep Play/Arp), output gain (keep amp), distortion type/where (keep
   its editor), osc 2's copies of shared controls, settings' copies of browser options.
5. Prose to "?" tips; status hints never truncated.
6. Header to `‹ name › Browse ⚂ ≡ ⚙`.
7. `automatable: false` in `tools/gen.mjs` for structural parameters; check CLAP state
   save/load and the view's model still see them. Target: host list ≤ 600.
8. Global undo/redo over `ParamModel` gestures and program loads.
9. Vanilla: drop dead cards; add six programs that use the lane, LFO 3, osc envs, key EQ, XY.

Acceptance: Init Synth page ≤ 25 visible controls; every active feature visible without
clicking a tab; no on-screen paragraph; host list ≤ 600.

**Phase 2: one modulation model (~3 sessions)**
1. Unified connections list with built-in rows (`PageMod.res`, `Modulators.res`, `ModEdit.res`).
2. Source focus across pages; tab counts; tray chips with live motion.
3. Source panels show their destinations as chips (all systems) instead of target slots.
4. One vocabulary: matrix targets, Oatmeal lists, status texts and host names read from the
   knob's label (`ModMatrix.targets`, `OatmealParams` target lists, `Modulators`).
5. Control context menu: modulate with ▸, show modulators, MIDI learn, reset, host menu.

Acceptance: "what moves X" and "what does Y move" each answered in zero clicks; every built-in
route listed; tests unchanged.

**Phase 3: pages by concern (~4 sessions; layout first)**
0. Layout primitive: a `Section` that places visible controls in grid order, collapses a "more"
   tier and offers a larger primary control, keeping Grid's no-overlap rule.
1. Synth page per 3.2 with the flow strip; lane on the main page.
2. Mod page per 3.3 with source editors and popovers.
3. FX page per 3.4; routing tab removed.
4. Play page per 3.5; Shapes as overlay; MIDI setup to Settings.

Acceptance: four pages; each parameter reachable in ≤ 2 clicks or by search; screenshot review.

**Phase 4: choosers (~2 sessions, UI only)**
Filter family/variant/character picker, distortion characters, space families, waveforms
without HQ duplicates, consistent LFOs, rare values under "more", effect add menu by job.

Acceptance: filter menu's first level ≤ 12 entries; every old value still loads and shows.

**Phase 5: cuts (DSP, ~3 sessions, measured)**
Cache routing scans; controller ramps instead of block splits; lazy buffers; oversampling HQ
switch; rack copies to 2; shaper points to state; merge identical filter/distortion types and
the reverb family with load-time aliases. Each change: CPU before/after (MSVC, PolyMode=1,
interleaved minimums), golden.mjs bit-exact in Oat mode, a migration test for every removed
value.

Acceptance: per-voice CPU -10 % or better on bassmeh/organblargh; state ≤ 45 MB/instance;
parameters ≤ ~900 (≤ ~500 automatable); builds faster.

**Phase 6: depth for power users**
Command palette, A/B compare, keyboard nudging, "show all" setting, random generator taught
user waveforms and the XY pad.

---

## 6. Metrics to track

| Metric | Now | Target |
|---|---|---|
| Visible controls, Init Synth page | 44 | ≤ 25 |
| Tabs on the Synth page | 19 | ≤ 6 |
| Places that route modulation | 6 (+ tray) | 1 list (+ drag from anywhere) |
| Permanent prose lines | ~35 | 0 |
| Header controls | 17 | 9 |
| Filter menu first level | 60 | ≤ 12 |
| Host-visible parameters | 1,621 | ≤ 600 |
| Memory per instance | 82.4 MB | ≤ 45 MB |
| Per-voice CPU (bassmeh, 8 voices) | 2.86 % | ≤ 2.5 % |
| Clicks to "what moves cutoff" | 1-4 pages | 0 (hover) |

## 7. Decisions for you

1. **Envelopes and LFOs on Mod, or a source strip at the bottom of Synth** (Serum/Vital style)?
   Recommended: Mod, with popovers from any chip, because you asked for separation and the
   modulation layer keeps the connections visible.
2. **Rack copies: 4 to 2?** Recommended yes, after a usage check of copies 3-4.
3. **Merge identical/near-identical Porridge filter and distortion types in the DSP** (with load
   aliases), or only hide them in the UI? Recommended: hide in Phase 4, merge the 0.0-dB ones in
   Phase 5.
4. **Oversampling:** HQ on/off instead of 2x/4x/8x, with corrected gain outside Oat mode?
5. **Sample-accurate controllers:** give them up for per-block ramps (big MPE win)?
6. **Landing page:** Synth for everyone, or Play for programs that have macros?

## Side findings (bugs, separate from this plan)

- Ambience "verb tiny" falls with Am_Time (-7 dB at 0, -41 dB at 0.95) and is silent at 1.
- Oversampling filters' gain: -0.9 / -3.8 / +6.8 dB at 2x / 4x / 8x (check Oat mode first).
- Plain Saw/Pulse alias at -24..-32 dB on keys 54-64 (one table for that octave).
- PZ SVF at morph 1 expands (+12 dB in, about +16 dB out).
- Lane EQ measured ≈0 CPU in the bench; it may not have been switched on; recheck.

---

## Phase 5b: stacking

2026-10-02, after the rack's pool landed (Phase 5's memory work). The question: can effects stack
freely (five reverbs, eight delays) without each kind paying a fixed cost per copy, given that
Cmajor allocates nothing at run time? Sizes are `sizeof` of the generated state (MB = 10^6
bytes); CPU is the MSVC test host, 8-note saw chord, PolyMode=1, interleaved minimums of 7, % of
a core at 44.1 kHz.

### Where things stand

The rack has 8 slots. Behind them are fixed instances: Oatmeal's chorus, delay, reverb and EQ,
two more copies of those four, and three of each Porridge kind (two convolvers). Each copy has
its own parameter endpoints (577 declared, 430 automatable) and matrix targets (221 live).

Memory now has no per-copy cost for the big buffers. The effects with long lines keep them in one
pool (`Common.cmajor`'s FxPool: 8,192 blocks of 1,024 floats, 33.5 MB) and borrow their blocks
while they are in the rack (Synth's `claimPool`). Eight slots can hold at most eight instances,
so the pool only has to fit the eight largest together:

| Instance | Footprint (blocks) | MB |
|---|---|---|
| Oatmeal's delay (30 s a side at any rate, as Oatmeal) | 2,584 | 10.58 |
| convolver (tail spectra and predelay), x2 | 1,102 | 4.51 |
| rack delay copy (10 s a side), x2 | 862 | 3.53 |
| algo reverb, x3 | 512 | 2.10 |
| Oatmeal's reverb and its copies, x3 | 502 | 2.06 |
| Bode, x3 | 376 | 1.54 |
| ambience, x3 | 320 | 1.31 |
| flanger, x3 | 128 | 0.52 |
| **all 20** | **12,026** | **49.3** |
| **the worst eight** (delay, 2 convolvers, 2 delays, 3 algo reverbs) | **8,048** | **33.0** |

Per instance: 70.6 MB before this work, 51.7 MB now (the pool 33.5, wave tables 6.2, voice
lane 4.3, convolvers' own parts 3.9, voices and their filters 2.2, the rest 1.6). The ≤ 45 MB
target is not reachable without giving something up: the worst eight alone are 33 MB, and they
are all reachable (Oatmeal's delay really is 30 s at 44.1 kHz with length 100 x seconds; the
reverbs' lines are sized for 192 kHz, Cmajor's highest rate). A 24 MiB pool would make 43 MB, at
the price of a rack holding more than 24 MiB of long lines at once (for example Oatmeal's delay,
both convolvers and a delay copy) not getting all of them.

What stays per copy: its small state (bytes: delay 68, flanger 40, Bode 656, ambience 2,160,
algo reverb 5,848, Oatmeal reverb 8,516, distortion 7,664, rack filter 17,996, chorus 262,576 for
its 0.74 s line, convolver 1,936,912 of which 1.57 MB is the loaded file and its resampled
copy), and its parameters.

CPU of the pool (base = before, pool = now):

| Case | base | pool |
|---|---|---|
| no effects | 1.516 | 1.488 |
| Oatmeal delay | 1.606 | 1.589 |
| delay copy | 1.607 | 1.588 |
| Oatmeal reverb | 1.790 | 1.738 |
| algo reverb, hall | 2.998 | 2.816 |
| algo reverb, plate | 2.270 | 2.299 |
| convolver, hall | 2.728 | 2.687 |
| Bode with feedback | 1.769 | 1.770 |
| ambience, room | 2.590 | 2.075 |
| ambience, verb tiny | 1.771 | 1.672 |
| flanger | 1.624 | 1.646 |
| six pooled effects at once | 6.129 | 5.297 |
| Oatmeal program (Oat mode), f001 / f005 | 1.554 / 8.542 | 1.498 / 8.511 |

A pool access costs about four more instructions than a member array's (block, then float);
that alone made the algo reverb 20 % slower. Its line tables (40 entries, indexed modulo 40,
which compiles to a multiply) were cheaper to fix than the pool: at 64 entries a line number is a
mask, and the algo reverb and ambience now run faster than before. The convolver's spectra are
whole blocks, so its multiply-accumulates still vectorize.

### Designs for free stacking

**A. Fixed copies over the pool (built).** As now. More copies of a kind cost their parameters
(a delay copy 15, a compressor 28, an EQ 21) and small state, and pool memory only if they change
the worst eight: a third delay copy does (8,398 blocks, over 8,192), a fourth reverb or Bode does
not. A pool whose block count isn't a power of two pays a multiply on every access (the cost the
line tables had), so the next size up is 16,384 blocks (67 MB). Stacking stays capped per kind,
and the host list, the matrix's targets and the generated header (80 % of it scales with the
parameters; 78 s MSVC builds) grow with every copy.

**B. Generic slots.** Each of the 8 slots hosts any kind, with a block of M generic parameters
(M ≈ 28, the compressor's, once the custom shaper's 49 points are stored state). Cmajor has no
unions, so a slot holds every kind's small state: about 0.4 MB a slot (0.36 of it the
convolver's spectra and buffers) once the chorus's line moves into the pool, 3.3 MB for 8 slots.
The convolver's file and resampled copy (1.57 MB) can't be per slot (12.6 MB): cap convolvers at
2, or keep the file in the view and send it when a slot becomes a convolver. Pool: Oatmeal's four
stay fixed instances (Oatmeal compatibility); generic slots hold rack-sized kinds, so the worst
case is Oatmeal's delay, 2 convolvers and 5 rack delays, 9,098 blocks, which needs the next
power of two (67 MB); with rack delays capped at 2 it is today's 8,048. Total about 53 MB with
the delays capped.
Parameters: 8 x 28 = 224 slot parameters replace 430 automatable copy parameters.
CPU per sample is unchanged; per block, a switch on the slot's kind and its parameter block moved
into the kind's slots (what `swapKind` does for copies today: about 2 M floats a slot, under
0.01 % of a core).

**C. Per-kind instance pools that slots borrow.** Each kind has N instances (small state only);
a slot holds a kind and the generic parameter block, and borrows a free instance of its kind
while it holds it. Memory is Σ N x small state plus the pool: with 2 convolvers and 8 of
everything else (about 45 kB a set) it is 51 MB, the same pool limits as B. Over B it keeps an
effect's state when slots
are reordered (the instance stays, only the slot's index moves), where B would have to copy state
between slots or reset it.

**Parameters, automation and presets (B and C alike).**
- CLAP parameter IDs are endpoint handles, so endpoints can't be removed or reordered without
  breaking hosts' saved automation. The copies' 577 endpoints have to stay declared (non-
  automatable, as aliases the loader reads) and the slot parameters go at the end, so the header
  only shrinks once IDs stop being handles. Worth doing first: tools/clap-patch.mjs can give the
  wrapper a table from gen.mjs (today's handles kept as the IDs of today's parameters, new IDs for
  new ones), after which retired endpoints can go.
- A slot parameter's meaning follows the slot's kind. Hosts keep automation on "slot 3, knob 2"
  and it moves whatever kind is there. Names can follow the kind through CLAP's params rescan
  (`CLAP_PARAM_RESCAN_INFO | CLAP_PARAM_RESCAN_TEXT`), which Cmajor's wrapper doesn't do: a
  clap-patch.mjs addition, and hosts differ in how they show renamed parameters.
- Presets: a slot stores its kind and its knobs by name; programs that use copies map each
  (kind, copy) in the rack to its slot on load (values stay append-only; a load-time migration in
  `Preset.res` with a test, as for the 4th copies).
- The matrix: 221 live per-copy targets become 8 x M per-slot targets, appended; old target
  indices map to the slot their copy sits in when loaded (a copy outside the rack doesn't sound,
  so its routes have nothing to map to).
- Oatmeal export: unchanged. Oatmeal's chorus, delay, reverb and EQ stay fixed instances with
  their own parameters; generic slots are Porridge's, lost on export as copies are now (the
  export's loss list names them).

### Making stacking actually free: footprints that follow the knobs

Every design above sizes the pool for the worst reachable rack. The cost people would notice is
the fixed 33 MB, not the per-copy one, and almost no rack is near that worst case: Oatmeal itself
allocates its delay at the length the knobs ask for. The pool already allocates at run time, so
it can do the same: a delay claims lenL + lenR (it clears its line on every length change
anyway), a reverb its lines at the current rate (cleared on a size change), and an effect whose
claim doesn't fit runs dry with an "out of memory" mark on its card. With footprints like that
the 32 MiB pool holds eight rack delays at their longest, or reverbs of any kind in every slot
(at 48 kHz an algo reverb's lines take a quarter of their 192 kHz size); only a rack with
Oatmeal's delay near 30 s, both convolvers and several long delays could reach the limit, and the
limit could be a setting.

### Recommendation

1. Keep A (done): the copies' memory is gone, the CPU is level or better.
2. Make CLAP IDs independent of endpoint order (clap-patch.mjs table), and move the custom
   shaper's points to stored state; both are needed by any slot design and help the host list on
   their own.
3. Then C with B's parameters: 8 generic slots of 28 knobs, per-kind instances (2 convolvers,
   8 of everything else, the chorus's line in the pool), footprints that follow the knobs, and a
   memory mark on the cards. Estimate: about 51 MB per instance with no per-kind stacking limit
   except the convolver's, 224 slot parameters instead of 430, the same per-sample CPU, and the
   copies' endpoints kept as aliases until step 2 lets them go.
