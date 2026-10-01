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
1080p screen at 150 % scaling. The header switches between five pages:

- **Synth**: oscillators (with noise, unison and phase on tabs), the filter, the amp
  envelope, the modulation sources (mod envelopes, pitch envelope and LFOs, on tabs), and
  voice and tuning settings.
- **FX**: distortion, chorus, delay, reverb and the EQ.
- **Arp / XY**: the arpeggiator pattern and the XY pad with its targets.
- **Shapes**: draw the two oscillator waveforms and the two LFO shapes. The editor shows the
  waveform's harmonics.
- **MIDI**: channel filter, sustain pedal, velocity and aftertouch curves, and the six
  assignable controllers (with learn).

Programs and banks are saved as `.porridge` files (JSON, see
[docs/preset-format.md](docs/preset-format.md)), with a name, author, category, tags and
description (**Info**). Oatmeal programs and banks load as they are, and **Save ▸ Export for
Oatmeal** writes them back out for Oatmeal.

## Layout

```
Porridge.cmajorpatch    manifest
dsp/                    Cmajor DSP
  Porridge.cmajor         top-level graph
  ParamStore.cmajor       the 342 parameter endpoints (generated)
  Slots.cmajor            parameter -> program-struct slot constants (generated)
  Synth.cmajor            MIDI, voice manager, arpeggiator, per-voice rendering, effects chain
  Oscillator, Filter, Modulation, Effects, Tables, Voice, Types
ui/                     patch view (ReScript)
  Index.res               entry point; View.res builds the pages
  oatmeal/                file formats, parameter table, value texts
  bindings/               Cmajor PatchConnection and browser API bindings
worker/PatchWorker.res  restores shapes/curves and installs the factory bank
bundle/                 view.js and worker.js, built by `npm run build`
presets/oatmealprs.dat  Oatmeal's factory bank
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots from ui/oatmeal/Fields.res
  bundle.mjs              bundles the compiled view and worker into bundle/
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp),
                          golden.mjs (bit-exact factory renders), presets.mjs (format round trips)
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.
