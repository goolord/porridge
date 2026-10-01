# Porridge

A Cmajor plugin that is compatible with FUzzpilz's Oatmeal VST presets

```bash
npm install
npm run build
cmaj play Porridge.cmajorpatch
```

## Interface

![Synth page](docs/screenshot.png)

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
  FxExtra.cmajor          Porridge's flanger, phaser, compressor, bode, rack filter and utility
  Space.cmajor            the algo reverb (hall, plate, nitrous, basin, vintage)
  Convolve.cmajor         the convolver: zero-latency partitioned convolution, built-in impulses
ui/                     patch view (ReScript)
  Index.res               entry point; View.res builds the pages
  Preset.res              Porridge's preset format; PorridgeParams.res and ModMatrix.res
                          list the parameters and modulation sources/targets Oatmeal doesn't have
  PresetBrowser.res       the preset browser; Library.res searches and filters for it
  FilterTypes.res         the filter types; FilterGraph.res their response pictures, with a
                          point to drag for cutoff and resonance
  FxPanels.res            the tabs of Porridge's own effects (CompEditor.res: the compressor's);
                          Impulse.res the convolvers' impulse files
  oatmeal/                file formats, parameter table, value texts
  bindings/               Cmajor PatchConnection and browser API bindings
worker/PatchWorker.res  restores shapes/curves and installs the factory bank
bundle/                 view.js, worker.js and the factory bank as a new instance stores it
                        (factory-bank.json), built by `npm run build`
presets/oatmealprs.dat  Oatmeal's factory bank
presets/vanilla.porridge  Porridge's own bank (built by tools/vanilla-bank.mjs)
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots/ModTables from the parameter tables
  bundle.mjs              bundles the compiled view and worker into bundle/
  clap-patch.mjs          patches the generated CLAP wrapper: aspect-locked resizing, the
                          interface size setting, the host's parameter menu, the
                          64-sample latency, and a faster start (a QuickJS worker, one
                          rebuild per activation)
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp),
                          golden.mjs (bit-exact factory renders, in Oat mode), presets.mjs
                          (format round trips), library.mjs (the preset browser's search),
                          smoke.mjs (Porridge's own effects and filter types sound, stay
                          bounded and fall silent)
  vanilla-bank.mjs        builds presets/vanilla.porridge
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.
