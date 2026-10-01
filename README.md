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
1080p screen at 150 % scaling. Resizing the plugin window keeps the panel's proportions, and
**⚙** (settings) sets the size new windows open at (75-300 %); it is saved for every instance,
in `%APPDATA%\Porridge`, `~/Library/Application Support/Porridge` or `~/.config/porridge`.

Drag or scroll a value, double-click to type one, right-click to reset it. Click a list to
pick from it; right-click steps through it (shift-right-click steps back).

Double-right-click a control to open the host's menu for its parameter, in hosts that offer one
to CLAP plugins: in FL Studio it has **Create automation clip**, **Link to controller** and the
rest of FL's knob menu. The second click puts back the value the first one reset or stepped.

MIDI is sample-accurate: every message, and every arpeggiator step, starts on its own sample,
where Oatmeal starts it at the next 64-sample block (up to about 1.5 ms late at 44.1 kHz). This
costs a constant latency of one block (64 samples), which the plugin reports to the host. **Oat
mode** (Synth page, voice tab) goes back to Oatmeal's timing, for the cases where its
idiosyncrasies are wanted.

The header switches between six pages:

- **Synth**: oscillators (with noise, unison and phase on tabs), the filter, the amp
  envelope, the modulation sources (mod envelopes, pitch envelope and LFOs, on tabs), and
  voice and tuning settings. The tuning tab loads Scala scales (`.scl`) and keyboard
  mappings (`.kbm`) for microtuning; they are saved with the program. Drag the small point in
  the middle of an envelope's attack, decay or release up or down to bend that stage.
- **Mod**: the modulation matrix. The sources (LFOs, envelopes, velocity, key, aftertouch, mod
  wheel, bend, XY, a random value per note, the four macro knobs, the assignable controllers)
  are grouped on the left; the connections are listed on the right. Grab or click a source (or
  **+ add connection**) and a target picker opens: pitch, volume, pan, and the oscillator,
  filter, LFO and effect knobs. Up to 16 connections, each with an amount and an optional
  "via" source that scales it. Parameter targets move in knob space, and the knobs on the
  other pages show the range their connections sweep.
- **FX**: distortion, chorus, delay, reverb and the EQ. Drag the effects in the chain in the
  EQ's title row to reorder them (right-click: Oatmeal's order).
- **Arp / XY**: the arpeggiator pattern and the XY pad with its targets.
- **Shapes**: draw the two oscillator waveforms and the two LFO shapes. Under a waveform, click
  or drag the level and phase of its first 64 harmonics (right-click clears one). Drop a sample
  onto the window (or use "sample…") to build a waveform from its harmonics: a single cycle is
  taken whole, a wavetable gives one frame (Serum's frame size is read from the file), and a
  recording is measured at its pitch over a few periods. Drag along the sample's overview,
  above the drawing, to measure another part of it or pick another frame. An LFO shape takes
  the sample's volume envelope instead. WAV and AIFF always work; FLAC, MP3 and OGG need the
  host's web view to decode them.
- **MIDI**: channel filter, sustain pedal, velocity and aftertouch curves, MPE, and the six
  assignable controllers (with learn). With MPE on (lower zone, master channel 1), every note
  on channels 2-16 follows its own channel's pitch bend (range up to ±96 semitones), pressure
  (it drives the touch settings) and slide (CC 74, a modulation source).

Beyond Oatmeal (all off by default, so Oatmeal programs sound as they did):

- **HQ waveforms**: Saw HQ, Pulse HQ and Triangle HQ are Oatmeal's saw and triangle without
  the aliasing (Oatmeal's own tables alias at low notes on purpose, and keep only the
  fundamental above a quarter of the sample rate).
- **Osc mix modes**: clean phase modulation (osc 2 → osc 1, with osc 1 self-feedback, or
  self-feedback alone), ring modulation and AM. In PM 2 > 1, ring and AM, osc 2 is silent and
  its level sets the depth.
- **Zero-delay-feedback filters** (types 16-21, after Zavalishin's *The Art of VA Filter
  Design*): a state-variable filter that morphs lowpass › bandpass › highpass, a ladder with
  tanh saturation, a diode ladder, Sallen-Key, comb and formant (vowel) filters. They stay
  stable under fast modulation, and their cutoff knob reaches 20 kHz rather than 11 kHz.
- **Envelope curves** for every stage of the amp, filter and mod envelopes.
- **LFO** delay and fade-in, slew, sample & hold steps and one-shot.
- **Unison** detune curve (supersaw-style), random phase per copy and stereo width.
- **Analog drift**: slow random pitch (per unison copy) and cutoff (per voice) offsets.
- **Effects order**, as above.

Programs and banks are saved as `.porridge` files (JSON, see
[docs/preset-format.md](docs/preset-format.md)), with a name, author, category, tags and
description (**Info**). Oatmeal programs and banks load as they are, and **Save ▸ Export for
Oatmeal** writes them back out for Oatmeal.

**Browse** (ctrl+F) searches the programs in the bank, the banks that come with Porridge
(Vanilla, Porridge's own, and Oatmeal's factory bank) and any files you open or drop on it,
by name, category, tags, author and description. Words must all match; `tag:`, `cat:`,
`author:` and `name:` search one field (`tag:"per-voice pan"`), and the lists on the left
narrow the search by source, category, tag and author. Clicking a preset plays it; **Load**
puts it into the current program (or goes to it, for one of the bank's), and **Cancel** puts
back what was playing.

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
  PresetBrowser.res       the preset browser; Library.res searches and filters for it
  oatmeal/                file formats, parameter table, value texts
  bindings/               Cmajor PatchConnection and browser API bindings
worker/PatchWorker.res  restores shapes/curves and installs the factory bank
bundle/                 view.js and worker.js, built by `npm run build`
presets/oatmealprs.dat  Oatmeal's factory bank
presets/vanilla.porridge  Porridge's own bank (built by tools/vanilla-bank.mjs)
docs/internals/         reverse-engineering notes on the original
tools/
  gen.mjs                 regenerates ParamStore/Slots/ModTables from the parameter tables
  bundle.mjs              bundles the compiled view and worker into bundle/
  clap-patch.mjs          patches the generated CLAP wrapper: aspect-locked resizing, the
                          interface size setting, the host's parameter menu, and the
                          64-sample latency
  test/                   native C++ test host built from the patch (cmaj generate --target=cpp),
                          golden.mjs (bit-exact factory renders, in Oat mode), presets.mjs
                          (format round trips), library.mjs (the preset browser's search)
  vanilla-bank.mjs        builds presets/vanilla.porridge
  re/                     comparisons against Oatmeal.dll (32-bit Python) and data checks
  ui-preview/             runs the view in a browser with a mock PatchConnection
```

## Credits

Oatmeal and its factory bank (`presets/oatmealprs.dat`) authored by Fuzzpilz. 
Porridge is not affiliated with Fuzzpilz.
