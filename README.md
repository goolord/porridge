# Porridge

A Cmajor plugin that is compatible with FUzzpilz's Oatmeal VST presets

```bash
npm install
npm run build
cmaj play Porridge.cmajorpatch
```

## Interface

![Synth page](docs/screenshot.png)

The interface is one 1100 × 580 panel, scaled to fit any window size, so that it fits on a
1080p screen at 150 % scaling. The header switches between six pages:

- **Synth**: oscillators (with noise, unison and phase on tabs), the filter, the amp
  envelope, the modulation sources (mod envelopes, pitch envelope and LFOs, on tabs), and
  voice and tuning settings. The tuning tab loads Scala scales (`.scl`) and keyboard
  mappings (`.kbm`) for microtuning; they are saved with the program.
- **Mod**: the modulation matrix as a patch bay. Drag a cable from a source (LFOs, envelopes,
  velocity, key, aftertouch, mod wheel, bend, XY, a random value per note, the four macro
  knobs, the assignable controllers) to a target (pitch, volume, pan, and the oscillator,
  filter, LFO and effect knobs). Up to 16 connections, each with an amount and an optional
  "via" source that scales it. Parameter targets move in knob space, and the knobs on the
  other pages show the range their connections sweep.
- **FX**: distortion, chorus, delay, reverb and the EQ.
- **Arp / XY**: the arpeggiator pattern and the XY pad with its targets.
- **Shapes**: draw the two oscillator waveforms and the two LFO shapes. The editor shows the
  waveform's harmonics.
- **MIDI**: channel filter, sustain pedal, velocity and aftertouch curves, MPE, and the six
  assignable controllers (with learn). With MPE on (lower zone, master channel 1), every note
  on channels 2-16 follows its own channel's pitch bend (range up to ±96 semitones), pressure
  (it drives the touch settings) and slide (CC 74, a modulation source).

Programs and banks are saved as `.porridge` files (JSON, see
[docs/preset-format.md](docs/preset-format.md)), with a name, author, category, tags and
description (**Info**). Oatmeal programs and banks load as they are, and **Save ▸ Export for
Oatmeal** writes them back out for Oatmeal.

## Layout

```
Porridge.cmajorpatch    manifest
dsp/                    Cmajor DSP
  Porridge.cmajor         top-level graph
  ParamStore.cmajor       the parameter endpoints: Oatmeal's 342, then Porridge's own (generated)
  Slots.cmajor            parameter -> program-struct slot constants (generated)
  ModTables.cmajor        modulation sources, targets and knob laws (generated)
  Synth.cmajor            MIDI, voice manager, arpeggiator, per-voice rendering, effects chain
  Oscillator, Filter, Modulation, Effects, Tables, Voice, Types
ui/                     patch view (ReScript)
  Index.res               entry point; View.res builds the pages
  Preset.res              Porridge's preset format; PorridgeParams.res and ModMatrix.res
                          list the parameters and modulation sources/targets Oatmeal doesn't have
  oatmeal/                file formats, parameter table, value texts
  bindings/               Cmajor PatchConnection and browser API bindings
worker/PatchWorker.res  restores shapes/curves and installs the factory bank
bundle/                 view.js and worker.js, built by `npm run build`
presets/oatmealprs.dat  Oatmeal's factory bank
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots/ModTables from the parameter tables
  bundle.mjs              bundles the compiled view and worker into bundle/
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp),
                          golden.mjs (bit-exact factory renders), presets.mjs (format round trips)
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.
