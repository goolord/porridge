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
...", "kbm": "" }
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
`ModN_Amount`, `ModN_Via` for N = 1..16), then `MPE_On` and `MPE_BendRange`. They are appended to, never reordered, and each one's
default leaves the sound exactly as Oatmeal's. **Export for Oatmeal** leaves them out and says
so.

## Compatibility rules

- A parameter or table that is missing has its Init value. Every new feature is added with a
  default that leaves the sound unchanged, so older files keep sounding the same.
- Readers ignore parameters and fields they don't know.
- A file with a newer `version` is still read, with a warning.

The plugin keeps its bank in the host session as a bank document, under the stored-state key
`bank`. Sessions saved by earlier builds stored base64 Oatmeal chunks there; they are converted
when loaded.
