# Oatmeal internals

These are notes on how `Oatmeal.dll` (release 38-1) works. They were written while
reverse-engineering it, and Porridge's DSP and preset code follow them. Addresses refer to
that DLL, and chunk offsets to the 10376-byte program struct (`Oatmeal.prgm`, version 38).

| file | covers |
|---|---|
| [presets_params.md](presets_params.md) | program and bank formats, version 31–37 conversion, the 342 parameters (normalized ↔ internal mapping, display texts), user shapes and curves |
| [voice_osc.md](voice_osc.md) | oscillators and wavetables (plain, hard sync with BLEP, FM), noise, unison, the voice output stage |
| [voice_osc_blep.txt](voice_osc_blep.txt) | the 512-point sync BLEP table |
| [filter_dist.md](filter_dist.md) | the 16 filter types, doubling, and distortion with its oversampling |
| [modulation.md](modulation.md) | envelopes, pitch envelope, LFOs, XY pad, controllers and modulation routing, tuning, velocity, aftertouch |
| [notes_arp.md](notes_arp.md) | note input, voice allocation and stealing, glide, sustain pedal, the arpeggiator |
| [effects.md](effects.md) | the global chain: distortion, chorus, delay, reverb, EQ, output gain |

Sections marked **[V]** were checked sample by sample against the DLL. Where the notes
mention Python models or scripts under `OM/work_*`, those were working files used during
the analysis and are not part of this repository. The checks that are kept live in
`tools/re`.

## Things to know before reading the code

- **Control blocks.** Everything runs in 64-sample control blocks. MIDI arriving during a
  block is handled at the start of the next one. Parameters are read once per block, in the
  same order as in the DLL.
- **Rounding.** The DLL is x87 code. Intermediate values keep extended precision, and values
  are rounded to float32 when stored. Porridge computes in float64 where the DLL keeps a value
  in a register, and rounds to float32 where the DLL stores one. This is why renders match to
  about 1e-5.
- **Random numbers.** Randomness comes from the MSVCRT `rand()` LCG. Porridge uses the same
  generator, but random features are not sample-identical: their state depends on the full
  call history since the plugin was loaded.
- **Program struct.** The synth reads parameters from the program struct at their chunk
  offsets. Porridge's `Synth` keeps a float mirror of that struct: slot = offset / 4.
  `Filter`/`Filter2` share one int (lo16/hi16) and get two virtual slots.
- **Comparisons.** The DLL harness (`tools/re/vsthost.py`) renders 128 samples after loading
  a program, before any notes. The chorus LFO keeps running during that time, so Porridge's
  test host is given the same lead-in with `--preroll 128`.
