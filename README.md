# Porridge

A Cmajor plugin that is compatible with FUzzpilz's Oatmeal VST presets

```bash
cmaj play Porridge.cmajorpatch
```

## Interface

![Synth page](docs/screenshot.png)

The interface is one 1344 × 732 panel, scaled to fit any window size. It has three pages:

- **Synth**: every sound parameter, laid out in the same order as Oatmeal's default skin.
- **Shapes**: draw the two oscillator waveforms and the two LFO shapes. The editor shows the
  waveform's harmonics.
- **MIDI**: channel filter, sustain pedal, velocity and aftertouch curves, and the six
  assignable controllers (with learn).

## Layout

```
Porridge.cmajorpatch    manifest
dsp/                    Cmajor DSP
  Porridge.cmajor         top-level graph
  ParamStore.cmajor       the 342 parameter endpoints (generated)
  Slots.cmajor            parameter -> program-struct slot constants (generated)
  Synth.cmajor            MIDI, voice manager, arpeggiator, per-voice rendering, effects chain
  Oscillator, Filter, Modulation, Effects, Tables, Voice, Types
ui/                     patch view (plain ES modules, no build step)
  oatmeal/                file formats, parameter table, value texts
worker/worker.js        restores shapes/curves and installs the factory bank
presets/oatmealprs.dat  Oatmeal's factory bank
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots from ui/oatmeal/fields.js
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp)
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.
