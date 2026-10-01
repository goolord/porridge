# Porridge preset format

Porridge saves programs and banks as JSON in files ending in `.porridge`. It still loads
every Oatmeal format (`.omp`, `.omb`, `.fxp`, `.fxb`, `oatmealprs.dat`), and **Save ▸ Export
for Oatmeal** writes `.omp`/`.omb` files that Oatmeal can open. Those files only keep the
settings Oatmeal has.

## Preset

```json
{
 "porridge": "preset",
 "version": 1,
 "name": "Warm pad",
 "author": "",
 "category": "pad",
 "tags": ["slow", "wide"],
 "description": "",
 "params": { "Cutoff": 0.42, "O1_Waveform": 1, "Macro_1": 0.5, "...": 0 },
 "modulations": [
  { "source": "lfo1", "target": "Cutoff", "amount": 0.25, "via": "modWheel" },
  { "source": "macro1", "target": "R_Wet", "amount": 0.5 }
 ],
 "macros": ["space", "", "", ""],
 "tables": { "wave1": "AAAAAD8AAAA..." },
 "tuning": { "scl": "! 19edo.scl
19 equal
 19
 63.157895
...", "kbm": "" },
 "impulses": [ { "name": "hall.wav", "rate": 48000, "left": "AAAAAD8AAAA...", "right": "..." }, null ]
}
```

| field | meaning |
|---|---|
| `porridge` | `"preset"` or `"bank"` |
| `version` | format version. It goes up only for changes an older reader can't skip safely |
| `name`, `author`, `category`, `tags`, `description` | program info (Info button). Names can be up to 64 characters |
| `params` | parameter values by endpoint id (the ids in `dsp/ParamStore.cmajor`). The values are the internal values the patch's endpoints take: Oatmeal's stored value for Oatmeal parameters, except that pulse widths are 0..1 fractions. Lists are stored as the item's index |
| `modulations` | the modulation matrix's connections, in slot order: `source` and `target` keys from `ui/ModMatrix.res` (a parameter target's key is its endpoint id), `amount` (-1..1), and an optional `via` source that scales the amount. The slot parameters (`Mod1_Source` ...) aren't written to `params` |
| `macros` | the four macro knobs' names (their values are the `Macro_1`..`Macro_4` parameters) |
| `tuning` | a microtuning: the text of a Scala scale (`scl`) and keyboard mapping (`kbm`, empty for the default: middle C is degree 0, A above it is 440 Hz). Left out for Oatmeal's 12-note tuning. An empty `scl` with a `kbm` maps 12-tone equal temperament |
| `impulses` | the convolvers' impulse responses from files (`Cv_Impulse` = `file`), one per convolver (`Cv_`, `Cv2_`), `null` where there is none: the file's name, its sample rate (48 kHz or less) and its left and (for a stereo file) right channel as base64 little-endian float32, at most 131072 frames. Left out when no convolver has a file |
| `tables` | user waveforms (`wave1`, `wave2`), LFO shapes (`lfoShape1`, `lfoShape2`) and response curves (`velocityCurve`, `aftertouchCurve`) as base64 little-endian float32 arrays (512 or 64 values). A table is written only when it differs from Init |

Numbers are written with the fewest digits that still read back as the same float32
(`0.7`, not `0.699999988079071`), so a program converted from Oatmeal and back is
unchanged bit for bit (`node tools/test/presets.mjs` checks the factory bank).

## Bank

```json
{ "porridge": "bank", "version": 1, "name": "", "presets": [ { "name": "...", "params": {} } ] }
```

The presets in a bank have the same fields as a preset file, without `porridge` and `version`.

## Porridge parameters

Porridge's own parameters follow Oatmeal's 342 as host parameters (`ui/PorridgeParams.res`):
the macros `Macro_1`..`Macro_4`, then four per modulation slot (`ModN_Source`, `ModN_Target`,
`ModN_Amount`, `ModN_Via` for N = 1..16), then `MPE_On` and `MPE_BendRange`, then:

| parameters | |
|---|---|
| `Oat_Mode` | Oatmeal's MIDI timing (each message at the next 64-sample block) instead of sample-accurate |
| `Drift_Pitch`, `Drift_Cutoff`, `Drift_Rate` | analog drift: cents per unison copy, semitones of cutoff per voice, Hz |
| `FX_Order` | the order of chorus, delay, reverb and EQ: the index of a permutation, in lexicographic order (0 is Oatmeal's) |
| `PM_Feedback` | osc 1's self-feedback in the PM osc mix modes |
| `F_Morph` | the morph of Porridge's filter types (what it does depends on the type, e.g. SVF lowpass › bandpass › highpass, comb polarity, formant vowel; `ui/FilterTypes.res`) |
| `Curve_Amp_Attack` ... `Curve_Mod2_Release` | a curve for the attack, decay 2 (`_Decay`) and release of the amp, filter, mod 1 and mod 2 envelopes, -1..1 |
| `LFO_N_Delay`, `LFO_N_Fade`, `LFO_N_Slew`, `LFO_N_Steps`, `LFO_N_OneShot` | LFO delay and fade-in (ms), slew, sample & hold steps per cycle, one-shot |
| `U_DetuneCurve`, `U_RandomPhase`, `U_Width` | unison detune curve, random phase per copy, stereo width |
| `FX_Rack_1` ... `FX_Rack_8` | the effects rack, in the order it runs: each slot holds `empty`, one of Oatmeal's chorus, delay, reverb or EQ, a copy (`chorus 2`..`4`, `delay 2`..`4`, `reverb 2`..`4`, `EQ 2`..`4`, `distortion 2`..`5`), or one of Porridge's own effects (`Flanger`..`Flanger 4`, `Phaser`.., `Compressor`.., `Algo reverb`.., `Convolve`, `Convolve 2`, `Bode`.., `Filter`.., `Utility`..). Slots holding one of Oatmeal's four take them in `FX_Order`'s order; the default is Oatmeal's chain |
| `EQ_On` | switches Oatmeal's EQ (on by default) |
| `Sat_Points`, `Sat_X1`..`Sat_X16`, `Sat_Y1`..`Sat_Y16`, `Sat_C1`..`Sat_C16` | the distortion's custom shape (type `custom shape`): the number of points less 2, then each point's input and output (-1..1) and the bend of the segment ending at it |
| `C2_Mode` ... `Sat5_C16` | the rack's copies: each of Oatmeal's chorus (`C_`), delay (`D_`), reverb (`R_`), EQ (`EQ_`, with `EQ_On`) and distortion (`Sat_`, without `Sat_Mode`) parameters again, numbered (`D3_Wet` is delay copy 3's wet level) |
| `F_Drive` | input drive into the analog filter types (`MG low` .. `PZ SVF`), 0..1 = 0 .. +24 dB |
| `Fl_`, `Ph_`, `Cp_`, `Rv_`, `Cv_`, `Bd_`, `Ff_`, `Ut_` | Porridge's own rack effects, each with an `_On` switch: flanger, phaser, compressor (OTT-style, 1 or 3 bands), algo reverb (hall, plate, nitrous, basin, vintage), convolve (built-in impulses or a file), bode (frequency shifter and shifted delay), filter (any filter type) and utility (gain, pan, width, phase, bass mono). Frequencies, rates and times hold their knob position 0..1 (the value is lo·(hi/lo)^v; the ranges are in `ui/PorridgeParams.res`) |
| `Curve_Amp_Decay1`, `Curve_Filter_Decay1`, `Curve_Mod1_Decay1`, `Curve_Mod2_Decay1` | each envelope's decay 1 curve, -1..1. A file without them takes its `_Decay` curve, which bent both decays before |
| `Fl2_Rate` ... `Ut4_BassMono` | their copies, numbered like Oatmeal's (convolve has one copy, the others three) |

They are appended to, never reordered, and each one's default leaves the sound exactly as
Oatmeal's, except `Oat_Mode` (off: MIDI is sample-accurate). **Export for Oatmeal** leaves
them out and says so.

Porridge also adds values after the last of some of Oatmeal's lists: the waveforms `Saw HQ`,
`Pulse HQ` and `Triangle HQ` (6..8), the osc mix modes `PM 2 > 1`, `PM 1 feedback`, `ring 1 × 2`
and `AM 2 > 1` (3..6), the filter types 16..59 for both filters (`SVF`, `ladder`, `diode ladder`,
`Sallen-Key`, `comb`, `formant`, then bandpass, peak and notch 12/24 dB, the morphing L/B/H 24,
L/N/H, B/P/B and N/P/N, the analog MG low 6/12/18/24, MG dirty, acid ladder, French LP, German LP,
clean drive and PZ SVF, comb +/−, flanger, flanger +/−, phaser, phaser +/−, formant I/II/III,
low/band/high EQ, ring mod, sample & hold, diffusor and reverb; the list is `ui/FilterTypes.res`),
and the distortion type `custom shape` (5). An Oatmeal
export writes the closest value Oatmeal has (the plain waveform, normal mix, a lowpass or
bandpass, soft clipping) and says so. It also keeps Oatmeal's effects order, leaves the rack's
copies and Porridge's own effects out, and switches off those of Oatmeal's effects that are out
of the rack or off.

## Compatibility rules

- A parameter or table that is missing has its Init value. Every new feature is added with a
  default that leaves the sound unchanged, so older files keep sounding the same.
- Readers ignore parameters and fields they don't know.
- A file with a newer `version` is still read, with a warning.

The plugin keeps its bank in the host session as a bank document, under the stored-state key
`bank`. Sessions saved by earlier builds stored base64 Oatmeal chunks there; they are converted
when loaded.
