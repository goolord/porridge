# Porridge

A Cmajor re-implementation of **Oatmeal** (Fuzzpilz, release 38-1, 2008), the freeware VST
synth. It was reverse-engineered from `Oatmeal.dll`. It has the same 342 parameters, loads
Oatmeal programs and banks, and reproduces the original's sound.

```bash
cmaj play Porridge.cmajorpatch
```

To build a plugin, use `cmaj generate --target=clap` (or `--target=juce`). The patch also
exports to WebAssembly with `--target=webaudio-html`.

## Presets

Porridge reads every file format Oatmeal wrote or accepted:

| file | what |
|---|---|
| `.omp` | Oatmeal program (`Oatmeal.prgm`) |
| `.omb`, `oatmealprs.dat` | Oatmeal bank: 64 programs |
| `.fxp`, `.fxb` | VST program/bank, either the opaque chunk or a plain parameter list |

Programs from Oatmeal versions 31 to 38 are converted to 38 the same way the DLL does it.
Truncated banks keep their complete programs. Use **Load**, or drop a file onto the window.
**Save program** and **Save bank** write `.omp` and `.omb` files that Oatmeal itself can load.

When a new instance starts, it loads the factory bank, as Oatmeal does. The whole bank is
saved with the host session: 64 programs, including user waveforms, LFO shapes and
velocity/aftertouch curves.

## Parameters

Each of Oatmeal's 342 parameters is a Cmajor parameter named after its action in the
original skin (`Cutoff`, `F_Decay1`, `LFO_1_Speed`, ...). Values are in Oatmeal's own
units (Hz, ms, dB, semitones), so they match what a preset stores. The UI uses Oatmeal's
knob tapers. Host automation lanes, however, are linear between each parameter's min and
max. Automation recorded against the original plugin does not carry over.

## Interface

![Synth page](docs/screenshot.png)

The interface is one 1344 × 732 panel, scaled to fit any window size. It has three pages:

- **Synth**: every sound parameter, laid out in the same order as Oatmeal's default skin.
- **Shapes**: draw the two oscillator waveforms and the two LFO shapes. The editor shows the
  waveform's harmonics.
- **MIDI**: channel filter, sustain pedal, velocity and aftertouch curves, and the six
  assignable controllers (with learn).

Controls:

- Drag or scroll to change a value (shift for fine steps).
- Double-click to type a value, right-click to reset it.
- Hover over a control to see Oatmeal's full value text in the status bar.

## How close it is

The DSP runs in Oatmeal's 64-sample control blocks, in the same order, with the same
float32 rounding points. `tools/re` compares renders from the real DLL with Porridge's
renders:

- **Deterministic features** match sample for sample, within about 5e-5 relative error.
  This covers all oscillator modes (sync, FM, PWM, unison), the 16 filter types and
  doubling, envelopes, LFOs, the pitch envelope, distortion, glide, the arpeggiator, chorus,
  delay, reverb and EQ.
- **Factory programs**, with their random sources made deterministic, match the same way.
- **Random features** use the same algorithms but can't be sample-identical, since their
  state depends on history. This covers noise, random LFO shapes, the irregular chorus,
  the XY random walk, and random pan/amp/pitch and phases. The phase of a free-running
  global LFO depends on how long the plugin has been running, in both versions.
- **Parameters:** all 342 map from normalized to internal values exactly as the DLL does
  (checked on 14,022 samples). The value texts match, with one exception: Oatmeal shows
  filter-2 envelope speeds above 1× as `/(10 − ratio)`, and Porridge shows `*ratio`.
- **Preset files:** all 160 program and bank files in a large community collection load,
  4,722 programs in total.

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

## Development

Run `node tools/gen.mjs` after changing the parameter table. The UI can be worked on without
Cmajor: serve the repo root (`python -m http.server`) and open `tools/ui-preview/index.html`.
Add `?page=shapes` or `?page=midi` to open another page.

Checks that don't need the DLL:

```bash
node tools/re/check-params.mjs
```

```bash
node tools/re/check-presets.mjs "path/to/oatmeal banks"
```

The comparisons against the original need a 32-bit Python 3 on Windows, the native test host,
and `Oatmeal.dll` (taken from `$OATMEAL_DLL`, default `F:\VST32\Oatmeal.dll`):

```bash
sh tools/test/build.sh
```

```bash
python tools/re/cmp_synth.py
```

`cmp_fx.py` covers the effects and `cmp_factory.py` the factory programs.

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) are by Fuzzpilz. The bank is
included so that new instances start the same way as the original. Porridge is not affiliated
with Fuzzpilz.
