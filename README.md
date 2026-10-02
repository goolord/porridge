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
  Ambience.cmajor         the ambience: very small spaces (room, and Airwindows' ClearCoat
                          and VerbTiny), for a little stereo and tone
  Airwindows.cmajor       ports of Airwindows plugins: the distortion's model types (Tube,
                          Tape, Density, Mackity, Edge, MultiBandDistortion, Fracture2,
                          BassAmp, GrindAmp, Beam, BitGlitter) and the air rack effect (Air4)
  Convolve.cmajor         the convolver: zero-latency partitioned convolution, built-in impulses
ui/                     patch view (ReScript)
  Index.res               entry point; View.res builds the pages
  Preset.res              Porridge's preset format; PorridgeParams.res and ModMatrix.res
                          list the parameters and modulation sources/targets Oatmeal doesn't have
  PresetBrowser.res       the preset browser; Library.res searches and filters for it, and
                          BankLibrary.res asks the plugin for the banks it keeps
  match/                  the sound matcher: MatchDrawer.res (the drawer and its cards),
                          SoundTarget.res (a sample made ready: pitch, envelope, fitted wave),
                          Genome.res (what is searched, as parameter values), EnvelopeFit.res
                          (the amp envelope that follows the sample), Spectrum.res and
                          MatchLoss.res (how close a render is), Cmaes.res (the optimizer),
                          MatchModel.res and match-model.bin (the predictor), MatchSearch.res
                          and MatchRun.res (the outline and the four searches), MatchPool.res,
                          MatchWorker.res and MatchEngine.res (the workers and their synth)
  NewBankDialog.res       starts a new bank of Init programs, for someone writing one
  FilterTypes.res         the filter types; FilterGraph.res their response pictures, with a
                          point to drag for cutoff and resonance
  FxPanels.res            the tabs of Porridge's own effects (CompEditor.res: the compressor's);
                          Impulse.res the convolvers' impulse files; AmbienceSim.res runs the
                          ambience's models on an impulse for its graphs
  DistTypes.res           the distortion's types: names, menu groups, what each model's knobs
                          are; DistEditor.res its tab; AirwindowsSim.res runs the Airwindows
                          models on a sine (and the air on sines) for their graphs
  oatmeal/                file formats, parameter table, value texts
  bindings/               Cmajor PatchConnection and browser API bindings
worker/PatchWorker.res  restores shapes/curves and installs the factory bank
bundle/                 view.js, worker.js and the factory bank as a new instance stores it
                        (factory-bank.json), built by `npm run build`; match-worker.js, and
                        match-engine.js and .wasm (the synth for the matcher, from
                        tools/match-engine.mjs), match-model.bin (its predictor)
presets/oatmealprs.dat  Oatmeal's factory bank
presets/vanilla.porridge  Porridge's own bank (built by tools/vanilla-bank.mjs)
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots/ModTables from the parameter tables, and
                          the test host's field table and manifest
  bundle.mjs              bundles the compiled view and worker into bundle/
  match-engine.mjs        builds the sound matcher's engine: the DSP with one of each rack
                          effect, compiled to WebAssembly (cmaj generate --target=javascript)
  match-train.mjs         trains the sound matcher's predictor on random patches it renders
  clap/                   the C++ clap-patch.mjs adds: PorridgeBridge.h (settings, the host's
                          menu, the view's requests), PorridgeLibrary.h (the bank library:
                          bank folders scanned and copied, files opened in the browser kept)
  clap-patch.mjs          patches the generated CLAP wrapper: aspect-locked resizing, the
                          interface size setting, the host's parameter menu, the
                          64-sample latency, and a faster start (a QuickJS worker, one
                          rebuild per activation)
  clap/PorridgeBridge.h   the settings file, zoom and host menu code clap-patch.mjs adds
  sync-dir.mjs            copies the regenerated CLAP project over the old one, touching only
                          what changed
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp),
                          golden.mjs (bit-exact factory renders, in Oat mode), presets.mjs
                          (format round trips), library.mjs (the preset browser's search),
                          smoke.mjs (Porridge's own effects and filter types sound, stay
                          bounded and fall silent, the ambience's models and the distortion's
                          types too, and the distortion's mix lines up with oversampling; the
                          oscillator envelopes and the noise source), banklibrary.cpp (the plugin's bank library on real files), oneshot.mjs (one-shot LFOs hold their
                          end), levels.mjs (the Vanilla bank's gains, levels and motion),
                          match.mjs (the sound matcher on programs from the banks and on
                          random patches whose genes are known), match-speed.mjs (how fast it
                          scores candidates, and how long a whole match takes);
                          lib.mjs has what they share
  vanilla-bank.mjs        builds presets/vanilla.porridge
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.

The ambience's clear coat and verb tiny models are ports of Airwindows ClearCoat and VerbTiny
by Chris Johnson ([airwindows/airwindows](https://github.com/airwindows/airwindows), MIT licence),
as are the distortion's model types (Tube, Tape, Density, Mackity, Edge, MultiBandDistortion,
Fracture2, BassAmp, GrindAmp, Beam and BitGlitter, under plainer names) and the air effect (Air4).
Porridge is not affiliated with airwindows.
