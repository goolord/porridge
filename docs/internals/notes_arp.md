# Oatmeal 38-1: note handling, voice allocation, glide, arpeggiator

Scope: MIDI note input, the note/arpeggiator object (`N = this+0x1e5c10`), the voice manager's
allocation logic (`VM = this+0x1e6858`), what a voice (re)start does (fresh voice vs. reused voice,
legato), glide, sustain pedal, and the arpeggiator.
Oscillator, envelope, filter and modulation DSP are only referenced here; see those specs.

**Verification status (details in §11):**
* The Python models `work_arp/arpmodel.py` (note object + arpeggiator) and `work_arp/vmmodel.py` (voice
  allocation) were run next to the real DLL and compared after every 64-sample block.
  * Arpeggiator: 60 random cases (all 5 arp modes, all 16 commands, random patterns/lengths/units/steps/
    arp notes/shifts, voice modes 0/1/2, random note on/off including duplicates and deltaFrames 0..100).
    5467 arp steps and 8063 voice note-ons. **0 mismatches.** Compared: every note-object state variable
    (phase double included), the held-note list, the per-note subsequence counters, and the set of held
    voices with their keys and frequencies (to 0.01 Hz).
  * Voice allocation, arp off: 60 random cases (modes 0/1/2, max polyphony 1..6, several release times,
    sustain 50 % and 0 %). 1828 steals, 260 same-key re-strikes. **0 mismatches** in the complete
    voice-list order and release counters.
* Glide: time scaling for all 7 glide modes and 4 intervals matches the formula exactly
  (N measured = N predicted ±1 sample). The pitch trajectory is linear in Hz.
* Note timing quantisation, sustain pedal, the re-strike quirk and other quirks were checked by audio or
  memory measurements (§11).

---------------------------------------------------------------------------------------------------------

## 1. Parameters (normalized v → internal; chunk offset)

| p | name | chunk off | internal value (setParameter 0x10048260) |
|---|------|-----------|------------------------------------------|
| 103 | Voice mode | 8760 int | `int(2v+0.5)`: **0 = Mono, 1 = Poly, 2 = Legato** (skin switch frames "M","P","L"; Init 0.5 → Poly) |
| 104 | Max polyphony | 8764 int | `int(31v+0.5)+1` (1..32) |
| 105 | Glide | 8768 float ms | `500·v²` |
| 106 | Glide mode | 8772 int | `int(6v+0.5)`: 0 Param, 1 P·o, 2 P/o, 3 P·(o+1/o), 4 P·(1+o), 5 P·(1+1/o), 6 P·(1+o+1/o) |
| 129 | Arp mode | 8844 int | `int(5v+0.5)`: 0 off, 1 pattern, 2 pattern (global subseq), 3 chord pattern, 4 chord, 5 transposed chords |
| 130 | Arp unit | 8848 int | `int(17v+0.5)`, table in §8.2 |
| 131 | Arp quantize | 8852 int | `int(v+0.5)` |
| 132 | Arp step | 8856 float | `v > 0.25 ? 1 + (v-0.25)·41.3333321f : 1/(1 + 7·(1-4v))` (0.125 … 1 … 32) |
| 133..148 | Arp step 1..16 | 8860+4i int | `int(15v+0.5)`: command 0..15, §8.5 |
| 149 | Arp pattern length | 8924 int | `int(15v+0.5)` = (length-1), 0..15 |
| 150..156 | Arp note 1..7 on | 8928+4i int | `int(v+0.5)` |
| 157..163 | Arp note 1..7 shift | 8956+4i float | `(2v-1)·36` semitones |
| 286 | Sustain pedal | 9592 int | `int(v+0.5)`: 0 ignore, 1 use |
| — | velocity curve | 9596 float[64] | used for note-on velocity |
| — | aftertouch curve | 9852 float[64] | used for poly AT, channel pressure and note-on velocity → AT |
| 178 / 179 | Tune main / Octave | 9060 / 9064 float | Hz / frequency ratio per "octave" (2.0); **9068 = ln(Octave)** (derived) |
| 114 | Random freq | 8804 float cents | per-note random detune, §4.4 |
| 65 | (amp) Sustain | 8284 float | only used for the "return to held note" condition, §5.6 |
| 270..285 | MIDI channel 1..16 | 9528+4·ch int | channel filter |

Other fields read by the code covered here: LFO1/LFO2 mode (8552/8588: 0 per note, 1 global reset on
note, 2 global free), Osc/PWM/LFO retrigger (8816/8828/8840), P env on (8984), Transpose ratio (8516),
Detune Hz (8520), N transpose st (8536).
In the code most of these are addressed through a program pointer `P = chunk+16`, so `P[0x227c]` is
chunk 8844 and so on.

---------------------------------------------------------------------------------------------------------

## 2. MIDI input (processEvents 0x10050480)

Events are dropped entirely while the "busy/loading" byte `this+0xb0` is set. Only `type==1` (MIDI) events
are handled. `ch = status & 15`; the event is ignored if `P.midiChannelOn[ch] == 0`.

```
0x90 with d2>0 (note on):   vel = d2&127; key = d1&127
    x = vel * 0.00787401572f * 64f   (x87)
    pressure = ATcurveLerp(x)               // this+0x229368 (channel pressure) AND
    perKeyAT[key] = same value              // this+0x1e6958 (= VM+0x100) float[128]
    N.noteEvent(key, 0.0f, vel, deltaFrames)            // 0x1000df20
0x80 (any velocity), or 0x90 with d2==0:  N.noteEvent(key, 0.0f, 0, deltaFrames)
0xB0: CC 123,124,125,126,127 -> N.allNotesOff()  (0x1000dd10: HARD kill of all voices, §3.4)
      CC 64: if P.sustainPedal: sustainDown = (value >= 63) ? 1 : 0   // byte this+0x1e5bf8; NOTE threshold 63
             else sustainDown = 0 ; the value is also stored as a normal CC
      (CC 0 is never stored; CC120/121 have no special meaning)
0xA0 poly AT, 0xD0 channel pressure, 0xE0 bend: see the modulation spec (curve lerp identical to below)
```
`ATcurveLerp`/`VelCurveLerp(x)`: `i = trunc(x); f = x - i; i0 = min(i,63); i1 = min(i+1,63);
return (1-f)·curve[i0] + f·curve[i1]`.
At the start of every process call: if `P.sustainPedal == 0`, then `sustainDown = 0`.

---------------------------------------------------------------------------------------------------------

## 3. Block structure and timing

### 3.1 Process loop
Each process call is split into sub-blocks of 64 samples plus a final remainder `r = nframes % 64`.
For each sub-block of length n:
```
voices.render(n)          // 0x1000c2e0: all voices in list order (newest first)
N.tick(n)                 // 0x1000e430: queued events, then arpeggiator
```
So anything triggered inside `tick` is first heard at the start of the next sub-block.

### 3.2 Note event timestamps (0x1000df20)
* `deltaFrames <= 0`: handled immediately in processEvents, before the first sub-block. The note sounds
  from sample 0 of the call.
* `deltaFrames > 0`: put into a 32-entry queue `N+0xa48` (entries `{int key; float off; int vel; int delta}`,
  `key<0` = free). In every `tick(n)`, each pending entry does `delta -= n`. Then entries with
  `delta <= 0` are handled one by one, rescanning from slot 0 each time (so the order is slot order).
  Result: an event at delta d (1 ≤ d ≤ …) takes effect at sample `64·ceil(d/64)` of the call. This was
  measured: d=1..64 → 64, 65..128 → 128, d=200 → 256. With a non-multiple-of-64 host block, a delta
  inside the remainder takes effect at the start of the next call. Deltas larger than the call carry
  over into later calls.
* Queue insert (0x1000dbf0): the first slot with `key <= 0` is used (bug: a queued key-0 event counts as a
  free slot). If no slot is free, the entry with the smallest `delta` is overwritten.

### 3.3 Note object state (N = this+0x1e5c10)
```
+0x000 int   prevCmd        (command of the last arp step; "cmd")
+0x004 byte  firstNote      (set when the held count becomes 1 on a note-on)
+0x005 byte  noAdvance      (never set anywhere: dead)
+0x008 int   dir, +0x00c int prevDir
+0x010 double phase         (arp sample counter)
+0x018 int   stepIdx
+0x01c int   curKey         (last key played by the arp, may carry subseq bits <<8; -1 = none)
+0x020 int   pos, +0x024 int prevPos   (indices into held list; -1 = none)
+0x028 float off[128]       (per held note pitch offset: always 0 from MIDI)
+0x228 int   vel[128]       (MIDI velocity 1..127)
+0x428 int   key[128]       (held keys, sorted ascending)
+0x628 int   gSub, +0x62c int gSubPrev    (global subsequence / transposition counter)
+0x630 int   sub[128]       (per-note subsequence counters, index-bound!)
+0x830 int   subFlag
+0x834 uint  stamp[128]     (note-on order stamps), +0xa34 uint stampCounter
+0xa38 int   count          (held notes)
+0xa3c P*, +0xa40 G* (= this+0x1e5bf8: {byte sustainDown; int SR @+4; double samplesPerBeat @+8}), +0xa44 VM*
+0xa48 queue[32]
```

### 3.4 All notes off (0x1000dd10)
This runs on CC 123..127, at construction and in suspend (vtable slot 21, 0x10047b80, which also
resets bend/pressure/XY/CCs and the effects). A program change does NOT run it.
```
gSub=gSubPrev=0; prevCmd=0; firstNote=noAdvance=0; VM.stopAll();
queue[*].key = -1; count=0; stampCounter=0; subFlag=0; phase=0; stepIdx=0;
dir=prevDir=1; curKey=pos=prevPos=-1
```
`VM.stopAll` (0x1000c1e0) deletes every voice immediately (a hard cut with no release) and resets the
two global phantom mod envelopes. It sets `keyReleased[0..255]=1` and `perKeyAT[0..127]=0`.

---------------------------------------------------------------------------------------------------------

## 4. Note object: held list and note dispatch

### 4.1 noteEvent / handle (0x1000df20; the queue path in 0x1000e430 is identical)
```
noteEvent(key, off, vel, delta): if (delta > 0) { enqueue(...); return; }  handle(key, off, vel)

handle(key, off, vel):
  heldListUpdate(key, off, vel)                        // 0x1000e0f0, 4.2
  if (vel > 0 && count == 1) { firstNote = 1; gSub = 0; gSubPrev = 0; }   // also on a duplicate note-on!
  mode = P.arpMode
  if (mode == 0) { voiceNote(key, vel, off); return; }                   // no arp
  if (vel == 0) { if (mode >= 4) voiceNote(key, 0, 0); return; }        // pattern modes: note-off does NOT stop sound
  if (mode < 4 || prevCmd == 0) return;               // pattern modes: nothing until the next step
  if (mode == 4) {                                    // chord, current step is "on": play at once
     voiceNote(key, vel, off);
     for j=1..7: if (P.arpNoteOn[j]) voiceNote(key + 256*j, vel, off + P.arpShift[j]);
  } else {                                            // mode 5
     gSub = advance(gSub)                             // 8.6
     if (gSub <= 0) voiceNote(key, vel, 0.0);
     else           voiceNote(key + (gSub<<8), vel, off + P.arpShift[gSub]);   // quirk: uses the NEXT transposition
  }
```
`voiceNote` = 0x1000dd90 (4.4). Keys ≥ 256 identify arp transpositions: `key & 0xff` is the MIDI note and
`key >> 8` is the arp-note index. Note-offs always act on `key & 0xff`, so every transposition of that
note is released too. dd90 has a 4th "flag" argument that the voice manager ignores; it is omitted here.

### 4.2 Held list insert (0x1000e0f0, vel>0)
```
if (key < 0 || count >= 128) return
i = 0; while (i < count) { if (keyL[i] == key) return;  /* duplicate: nothing, velocity NOT updated */
                           if (keyL[i] > key) break; i++ }
shift keyL, vel, stamp  [i..count-1] up by one        // NOTE: off[] and sub[] are NOT shifted (bug)
if (pos >= i) pos++;  if (prevPos >= i) prevPos++
keyL[i]=key; off[i]=off; vel[i]=vel; sub[i]=0; stamp[i]=stampCounter++; count++
```
(An index ≥ 128 shows a MessageBox, which cannot happen.) So the list is sorted ascending by MIDI key.
When a note is inserted, the arp position keeps pointing at the same note.

### 4.3 Held list remove (0x1000e210, vel==0)
```
if (count > 0) {
  find i with keyL[i]==key
  if found: if (pos > i || (pos == i && i == count-1)) pos--;   (same rule for prevPos)
            count--; shift keyL, vel, stamp [i+1..] down      // off[], sub[] NOT shifted
  if (P.arpMode == 0) returnToHeld(key)                       // 5.6 (runs even if the key was not found)
}
if (count <= 0) { count = 0; gSub = 0; gSubPrev = 0; }
```
Because `sub[]` is never shifted, the per-note subsequence counters belong to list indices, not to notes.
A new note resets only its own index. This is a quirk and should be kept.

### 4.4 voiceNote = 0x1000dd90(key, vel, off)
```
if (vel == 0) {                                       // note off
   k = key & 0xff; VM.keyReleased[k] = 1
   for every voice v in VM list: if ((v.key & 0xff) == k) v.release()      // 5.4, even if already releasing
   if (no voice in the list has relCount < 0) { globalModEnv1.release(); globalModEnv2.release(); }
   return
}
x = vel * 0.00787401572f * 64f;  velc = VelCurveLerp(x)          // curve at chunk 9596
det = (rand()*(1/16384.f) - 1) * P.randomFreqCents * 0.01f       // rand() is ALWAYS consumed
semis = float(det + off)                                          // stored as float
freq  = (double) TuneMain * pow(Octave, ((key&0xff) - 69 + semis) / 12.0)   // x87 → double
VM.noteOn(freq, key, velc)                                        // 0x1000bc20, 5.3
```
Per-note tuning (Tune C..B), global transpose, bend and so on are applied later, per block, by the
VM/voice render. That code indexes the tuning table with `(key&0xff)%12`, so **an arp transposition
uses the tuning of its base note's pitch class** (quirk; only matters with non-flat tuning).

---------------------------------------------------------------------------------------------------------

## 5. Voice manager: allocation

### 5.1 Structures
The VM holds a **doubly linked list of dynamically allocated voices**. The head is the most recently
(re)started voice. In Cmajor, use a fixed pool of 32 voices plus an explicit order array.
```
VM+0x000 byte keyReleased[256]   (1 = key not sounding; indexed by key&0xff)
VM+0x100 float perKeyAT[128]
VM+0x300 P*, VM+0x304 G*, VM+0x308 list sentinel, VM+0x30c head node
VM+0x31c / +0x33c global "phantom" mod envelopes 1/2;  VM+0x35c / +0x374 global LFO 1/2
voice: +0x9 byte active, +0xc int key (full, incl. <<8 bits), +0x10 float glideF0, +0x14 float freq (target),
       +0x18 float glideProg (2.0 = none), +0x1c float glideInc, +0x60 osc1[16] (stride 0xd8), +0xde0 osc2[16],
       +0x1ca0/+0x1ec8/+0x20f0/+0x2318 filter objects (each has an envelope at +0xc),
       +0x2970 amp env (+0x297c = its internal level), +0x2990 mod env 1, +0x29b0 mod env 2,
       +0x29d0/+0x29e8 per-voice LFO 1/2, +0x2a04 int relCount (-1 = held, >=0 = samples since release),
       +0x2a08 float velc, +0x2a28/+0x2a34/+0x2a38 pitch-env state (0x2a38 = stage)
```

### 5.2 Render / free (0x1000c2e0)
```
i = 0
for v in list (head -> tail):
    if (++i > P.maxPoly) { delete v and every voice after it (hard cut); break }
    if (!v.render(n)) remove+delete v      // render: if (v.relCount >= 0) v.relCount += n (first);
                                           // returns false if !v.active or the amp env is idle
```
A voice is **freed when its amp envelope has reached the idle state**. In release (state 8), once the
smoothed output drops below 1e-6 the env becomes idle, and the voice is deleted in the next block's render.
Held voices are also freed if the amp env ever reaches idle; that happens with sustain 0 and
"skip"-style settings (see the envelope spec). Voices beyond Max polyphony (after lowering it) are cut
immediately.

### 5.3 Note on (0x1000bc20(freq, key, velc))
```
same = first voice in list with v.key == key (FULL key) && v.relCount < 0
keyReleased[key&0xff] = 0
if (!(voiceMode == 2 && any voice has relCount < 0)) { globalModEnv1.trigger(); globalModEnv2.trigger(); }
if (P.lfo1Mode < 2) globalLFO1.reset();  if (P.lfo2Mode < 2) globalLFO2.reset();   // every note-on
oldHead = list.head (may be null)

if (same) {                                   // RE-STRIKE of a still-held key
    same.start(ref = oldHead, freq, key, velc + same.ampEnvLevel)   // QUIRK: velocity += current env level
    move same to head; return                 // (other voices are NOT released, even in mono modes)
}
if (voiceMode == 2) {                          // LEGATO
    if (list empty) { v = new voice at head; ref = null }
    else { v = head; keyReleased[v.key&0xff] = 1; ref = v }          // always reuse the head, glide from itself
} else if (listLength >= P.maxPoly) {          // STEAL (Mono and Poly)
    best = 0; v = null
    for u in list (head -> tail): if (u.relCount >= best) { best = u.relCount; v = u }   // longest-released; ties -> older
    if (!v) v = list.tail                      // nobody released: the oldest voice
    move v to head; keyReleased[v.key&0xff] = 1
    if (v.ampEnvLevel <= 1e-4 && v != oldHead) v.reset()     // 0x1005d3a0: becomes a fresh voice (active=0)
    ref = oldHead
} else { v = new voice at head (fresh); ref = oldHead }
v.start(ref, freq, key, velc)                  // 0x10063e20, section 6
if (voiceMode != 1)                            // Mono and Legato: release everything else
    for u in list except head: { keyReleased[u.key&0xff] = 1; u.release(); }
```
Consequences (all verified):
* **Poly**: a new voice for each note. At the limit the stolen voice is the released voice with the
  longest release time so far. If no voice is released, the oldest voice is stolen, even if its key is
  still held.
* **Mono (0)**: a new voice for each note (or steal at Max polyphony) and every other voice is released.
  Releases therefore overlap, and Max polyphony limits how many releasing voices can exist. With
  Max polyphony 1 the single voice is re-keyed.
* **Legato (2)**: the head voice is always re-keyed (also when it is only releasing) and glides from
  itself. Envelopes are retriggered only if they are idle or releasing (section 6.2).
* Unison (params 124..128) is rendered inside a voice (16 oscillator pairs per voice) and **does not
  affect allocation** (checked: identical voice lists with 1/4/16 unison voices).

### 5.4 Voice release (0x100645a0)
`relCount = 0` (**restarts the counter even for a voice that is already releasing**, which affects later
steal decisions). Amp env release(false), filter envs ×4 release(true), mod env 1/2 release(true),
pitch-env stage `0x2a38 = 8`. Details are in the envelope spec. `release(true)` on an env that is
already in release does nothing.

### 5.5 Sustain pedal
**The pedal does not hold notes.** Note-offs are processed normally: voices go to release, count as
released for stealing, and so on. While `sustainDown` (byte G+0) is set, the per-sample release
coefficient of the amp env (0x100050c0) is `relCoef^(speed/128)` instead of `relCoef^speed`. The
mod-env type (0x10005a00: mod envs 1/2, global phantom envs, filter envs) uses `relCoef^(1/128)`. So
releases run **128× slower** while the pedal is down, and resume at normal speed from the current level
when it is lifted. Measured: release 810 ms went from −0.43 ln/2205 samples to −0.0033 ln/2205 (≈130×,
the difference comes from the 0.001 offset/smoothing). CC64 value ≥ 63 counts as down (63 verified).

### 5.6 Return to held note (end of 0x1000e210, **only when Arp mode = 0**)
This runs in the note-off path after the key has been removed from the held list and **before** the
voice note-off of that key.
```
k = key & 0xff
hasActive = any voice v: v.key == k && v.relCount < 0
if (!hasActive && keyReleased[k] != 0) return
if (!(P.ampSustain > 0.001f) && voiceMode == 1) return      // percussive poly: never re-trigger
best = 0xffffffff; bi = -1
for i in 0..count-1:
    if (any voice v: v.key == (keyL[i]&0xff) && v.relCount < 0) continue    // note still has a voice
    if (stamp[i] <= best) { best = stamp[i]; bi = i }                       // OLDEST stamp; ties -> higher index
if (bi >= 0) { stamp[bi] = stampCounter++; voiceNote(keyL[bi], vel[bi], 0.0) }
```
So in Mono/Legato, releasing the sounding note **returns to the oldest still-held note, not the most
recent one**. Example (verified): hold C, E, G, then release G and C sounds. The returned note's stamp
becomes the newest. Legato returns without retriggering envelopes; Mono retriggers them. In Poly with
limited polyphony, notes that lost their voice are revived the same way. Because this runs before the
released key's own voice is freed, the revived note can **steal another held voice** (verified: maxpoly 2,
hold C E G, release G: C comes back and E is killed).

---------------------------------------------------------------------------------------------------------

## 6. Voice start (0x10063e20(ref, freq, key, velc))

### 6.1 Always
`relCount = -1; velc stored (+0x2a08); randomAmp = 10^((rand/16384-1)·P.randomAmp_dB·0.05)` (see the
amp spec). At the end: `v.freq(+0x14) = (float)freq; active = 1; v.key = key`. The new velocity always
takes effect, also for reused voices (verified).

### 6.2 Fresh voice (active==0: newly allocated or reset) vs. reused voice
* Fresh: velocity/pan/random-pan values are computed. All 16 unison osc phases and PWM phases are
  reset (0x100103b0, 0x10010440). Both per-voice LFOs are reset.
* Reused (active==1): the osc phases are reset only if **Osc retrigger** is on, PWM phases only if
  **PWM retrigger** is on, and the per-voice LFOs only if **LFO retrigger** is on.
* Envelope (re)trigger:
  * Voice mode 0/1: always trigger the amp env (arg 0), filter envs at +0x1cac, +0x1ed4, +0x20fc and
    +0x2324, and mod envs 1 and 2. Pitch-env stage `0x2a38 = fresh ? 2 : 1`; fresh also loads
    `0x2a28 = P[chunk 8456]` and `0x2a34 = P[chunk 8992]`.
  * Voice mode 2, fresh: trigger the amp env, filter envs +0x1cac and +0x1ed4, and mod envs 1 and 2.
    **Filter envs +0x20fc and +0x2324 are never triggered in Legato mode** (quirk). Pitch stage 2.
  * Voice mode 2, reused: trigger each of {amp, filter +0x1cac, filter +0x1ed4, mod1, mod2} **only if that
    env's state is 0 (idle), 8 (release) or 9** (0x10005080(2)). Pitch stage: set to 2 only if it was < 2
    or > 7 (released). So legato does not retrigger envelopes while the voice is held and not releasing.

### 6.3 Glide (verified exactly)
```
G = uint(P.glide_ms * SR * 0.001 + 0.5)                 // SR = int sample rate
newInc1 = uint(2^32 * freq / SR + 0.5)                   // osc1 phase increment
glide = (G > 10) && (!v.active || ref == v) && ref != null
if (!glide) {
    osc1.inc = newInc1; osc2.inc = uint((P.transposeRatio*freq + P.detuneHz)*2^32/SR + 0.5);  (immediate)
    noise-transpose value = freq*Octave^(P.Ntranspose/12) (immediate)
    glideProg = 2.0; glideF0 = freq
} else {
    oldInc = ref.osc1.inc (current value, possibly mid-glide); if (oldInc == 0) oldInc = 1
    o = |ln((double)newInc1 / oldInc)| / ln(Octave)        // interval in "octaves"
    oc = max(o, 0.001)
    factor = {1, o, 1/oc, oc+1/oc, 1+o, 1+1/oc, 1+oc+1/oc}[P.glideMode]
    Ng = uint(G * factor + 0.5)
    osc1.inc = oldInc;  osc1.rampTo(newInc1, Ng)
    osc2.inc = ref.osc2.inc; osc2.rampTo(newInc2, Ng)
    noise.value = ref.noise.value; noise.rampTo(freq*Octave^(Ntr/12), Ng)  // float ramp, only if Ng > 64
    if (Ng > 0) { glideInc = 1/Ng; glideF0 = (ref.glideProg < 1) ? ref.F0 + (ref.freq-ref.F0)*ref.glideProg
                                                                   : ref.freq;  glideProg = 0 }
    else        { glideProg = 2.0; glideF0 = freq }
}
```
`rampTo(target, N)` on a uint32 increment (0x10013ad0):
```
if (|target - inc| <= 1000) { inc = target; ramping = 0 }
else { step = round_half_away((target-inc)/N); count = uint(|(target-inc)/step| + 0.5); ramping = 1 }
```
Oscillator render, at the start of each render call (block of n): if `ramping && count <= n`, then
`inc = target; ramping = 0` (**snap**), else `count -= n`. After that, for each sample
`inc += step`, clamped so it never passes the target.
So **glide is linear in frequency (Hz), not in pitch**. It is per-sample, but it jumps to the target at
the start of the 64-block in which ≤ 64 ramp samples would remain. Glides of Ng ≤ 64 samples are
effectively instant. Verified: 440→880 Hz, 100 ms: slope 0.0998 Hz/sample; with 3 ms, the increment
after block 1 was 653 Hz and after block 2 it had snapped to 880.

The float glide `glideF0/glideProg` is advanced per block (`prog += n·glideInc`, clamp 1, then
`F0 = freq` once prog ≥ 1). It gives the block-rate "current note frequency" used by frequency-dependent
modulation (e.g. Frequency pan).

When glide happens:
* Poly: from the list head, i.e. the most recently started voice, even if it is released but not yet
  freed. There is no glide once all voices have been freed. Verified: glide with the previous note held
  or still releasing; none after it was freed.
* Mono: new voice, glides from the previous (head) voice.
* Legato: from itself.
* A **stolen voice that is still audible and is not the head does NOT glide** (verified). A stolen head
  (Max polyphony 1) glides from itself.
* `o` is measured between the current (possibly mid-glide) pitch of the reference voice and the new
  note.

---------------------------------------------------------------------------------------------------------

## 7. Tick (0x1000e430(n))
```
for q in queue: if (q.key >= 0) q.delta -= n
while (some q with q.key >= 0 && q.delta <= 0, first by slot): { take it; q.key = -1; handle(q.key, q.off, q.vel) }
if (P.arpMode == 0) return
L = stepLength()                                    // 8.2, double
if (firstNote) { firstNote = 0; dir = 0; phase = 0.0; stepIdx = 0; doStep(); }
else { phase += n; if (phase >= L) { phase -= (int)(phase/L) * L; doStep(); } }   // at most ONE step per tick
```

## 8. Arpeggiator

### 8.1 Timing
* **Free-running. It is not synced to host position (ppqPos is never read).** The phase is a sample
  counter (double) that runs **whether or not notes are held**. The step index keeps advancing with no
  notes held (nothing is played).
* The phase, step index and direction are reset only when a note-on makes the held count equal 1
  (including a duplicate note-on of the only held key, which restarts the pattern). That reset
  executes step 1 in the same tick: with a note at delta 0, the first arp note sounds from **sample
  64**, not 0 (verified).
* After a reset at the end of block B0, step k executes at the end of block `B0 + ceil(k·L/64)` for
  64-sample blocks with L ≥ 64, and sounds from the next block. If L < 64 there is one step per block
  (the phase is reduced modulo L). Tempo (samplesPerBeat = 60/tempo·SR, re-read every process call,
  initial 21000.0 if the host gives no time info) and step parameters act immediately on L. The phase
  is kept in samples.

### 8.2 Step length
```
s = P.arpStep
if (P.arpQuantize) s = (3*s >= 2) ? (double)(int)(s + 0.5) : 1.0 / (int)(1.0/s + 0.5)
unit (p130): 0 ms: L = s*SR*0.001 | 1 10ms: s*SR*0.01 | 2 sec: s*SR
   beats = {3: 0.1 (4/5 32nds), 4: 1/12 (2/3 32nds), 5: 0.125 (32nds), 6: 0.2 (4/5 16ths), 7: 1/6 (2/3 16ths),
            8: 0.25 (16ths), 9: 0.4 (4/5 8ths), 10: 1/3 (2/3 8ths), 11: 0.5 (8ths), 12: 0.8 (4/5 quarter),
            13: 2/3 (2/3 quarter), 14: 1 (quarter), 15: 1.6 (4/5 half), 16: 4/3 (2/3 half), 17: 2 (half)}
   otherwise L = s * samplesPerBeat * beats[unit]        ("2/3" = triplet, "4/5" = quintuplet)
if (L < 1.0) L = 1.0
```

### 8.3 doStep
```
if (stepIdx > P.patLen) stepIdx = 0;  if (stepIdx > 15 || stepIdx < 0) stepIdx = 0
c = P.pattern[stepIdx]; mode = P.arpMode
if (mode >= 4) chordStep(c)                 // 8.7
else if (c == 0) { if (curKey >= 0) voiceNote(curKey, 0, 0); }        // "off": release; curKey is KEPT
else {
    key = (count > 0) ? command(c) : -1     // 8.5 (moves pos/dir)
    shift = 0.0
    if (mode != 3 && 0 <= pos < 128 && (P.arpNoteOn[1]|P.arpNoteOn[2]|P.arpNoteOn[3]|P.arpNoteOn[4]))
        subsequence(mode, c, &key, &shift)  // 8.6.  BUG: only notes 1-4 enable it (verified)
    if (!(P.voiceMode == 2 && key != -1))           // Legato: previous arp note not released (legato transitions)
        if (curKey != key && curKey >= 0) voiceNote(curKey, 0, 0)
    if ((curKey != key && key >= 0) || prevCmd == 0) {       // same key after an "on" step: sustain, no retrigger
        voiceNote(key, vel[pos], shift + off[pos])            // mode 1/2
        // mode 3 (chord pattern): voiceNote(key, vel[pos], off[pos]);
        //   for j=1..7: if (P.arpNoteOn[j]) voiceNote(key + 256*j, vel[pos], off[pos] + P.arpShift[j])
    }
    curKey = key
}
prevCmd = c; stepIdx++          (noAdvance is never set)
```
(With `key == -1` and `prevCmd == 0` the DLL calls voiceNote(-1, vel[pos]…). Normally pos == -1 in that
situation, and `vel[-1]` aliases `off[127]` = 0, so it is a harmless note-off of key 255. `off[-1]` aliases
`prevPos`, which is harmless for a note-off.)
The velocity of an arp note is the MIDI velocity of the held note it came from. There is no gate
parameter: a note lasts until a step plays a different key or until an "off" step. When the user
releases a key in pattern modes, the sounding arp note continues **until the next step**.

### 8.4 Held-note order
The list is sorted ascending by key. `pos` indexes it. See 4.2/4.3 for how pos follows insertions and
removals.

### 8.5 Pattern commands (`command(c)`, n = count ≥ 1, K = key list) — enum order verified via display
```
1 up:            prevDir=dir; dir=1;  prevPos=pos; pos++; if (pos>=n || pos<0) pos=0
2 up, no wrap:   prevDir=dir; dir=1;  prevPos=pos; pos++; if (pos>=n) pos=n-1; else if (pos<0) pos=0
3 down:          prevDir=dir; dir=-1; prevPos=pos; pos--; if (pos>=n || pos<0) pos=n-1
4 down, no wrap: prevDir=dir; dir=-1; prevPos=pos; pos--; if (pos>=n) pos=n-1; else if (pos<0) pos=0
5 up or down:    prevDir=dir; d=rand()&1 ? +1 : -1; dir=d; prevPos=pos; pos+=d; if (pos>=n) pos=0; else if (pos<0) pos=n-1
6 up/down no wrap: prevDir=dir; d=±1 (as 5); dir=d; prevPos=pos; pos+=d; if (pos>=n) pos=n-1; else if (pos<0) pos=0
7 continue:      return curKey          (pos/dir unchanged)
8 continue dir:  if (dir==0) dir=±1 (rand); prevDir=dir; prevPos=pos; pos+=dir; if (pos>=n) pos=0; else if (pos<0) pos=n-1
9 cont. bounce:  if (dir==0) dir=±1 (rand); prevPos=pos; pos+=dir; prevDir=dir;
                 if (pos>=n) { dir=-1; pos=n-2; if (pos<0) pos=0 } else if (pos<0) { dir=1; pos=(n>1)?1:0 }
10/11/12 return / return up / return down:
                 if (prevPos<0 || prevPos>=n) { prevPos=pos; prevDir=1; dir=1; return curKey }
                 old=pos
                 10: pos=prevPos; prevPos=old; swap(dir, prevDir)
                 11: pos=prevPos+1 (>=n -> 0);  prevPos=old; t=dir; dir=-prevDir; prevDir=t
                 12: pos=prevPos-1 (<0 -> n-1); prevPos=old; t=dir; dir=-prevDir; prevDir=t
13 top:          prevDir=dir; dir=1;  prevPos=pos; pos=n-1
14 bottom:       prevDir=dir; dir=-1; prevPos=pos; pos=0
15 random:       prevDir=dir; prevPos=pos; pos = (int)(rand()*(n-1)*(1/32768.f) + 0.5) clamped to [0,n-1];
                 dir = pos>prevPos ? 1 : pos==prevPos ? 0 : -1
return K[pos]   (commands 1-6, 8-15)
```
Initial state after reset: dir=prevDir=1, pos=prevPos=-1, curKey=-1. The first-note reset sets dir=0,
so a leading "continue direction" picks a random direction. "up" from pos=-1 gives the lowest note.

### 8.6 Subsequences ("arp notes": index 0 = the unshifted note, 1..7 = arp note j with shift j)
```
advance(c): if (c > 0 && !noteOn[c]) { do { if (c > 7) break; c++; } while (!noteOn[c]); }  if (c > 7) c = 0;  return c
            (the next enabled index >= c, or 0 if none; noteOn[8] reads shift-1's bits, which is harmless)
mode 1 (per-note counter sub[pos]):
    if (c == 7) { if (subFlag && ((curKey ^ key) & 0xff) == 0) { if (--sub[pos] < 0) sub[pos] = 7; } subFlag = 0 }
    sub[pos] = advance(sub[pos]); s = sub[pos]
    if (s > 0) { if (key >= 0) key = (key & 0xff) + (s << 8); shift = P.arpShift[s] }
    subFlag = 1; if (++sub[pos] > 7) sub[pos] = 0
mode 2 (global counter):
    if (c == 7) { if (subFlag) gSub = gSubPrev; subFlag = 0 }
    gSub = advance(gSub)
    if (gSub > 0) { if (key >= 0) key = (key & 0xff) + (gSub << 8); shift = P.arpShift[gSub] }
    gSubPrev = gSub; if (++gSub > 7) gSub = 0; subFlag = 1
```
So each held note (mode 1) or the whole arp (mode 2) cycles 0 → enabled notes in index order → 0 …
"continue" repeats the same element: the key is unchanged, so with the previous step "on" the note
simply sustains. A transposed arp note has pitch `(key&0xff) + shift` semitones.

### 8.7 Chord modes (mode 4 chord, mode 5 transposed chords): the command value only matters as 0 / non-0 (and 7 in mode 5)
```
if (c == 0) { for i<count: voiceNote(keyL[i], 0, 0) }                  // release all held keys (+ their transpositions)
else if (mode == 4) {
    if (prevCmd == 0) for i<count: { voiceNote(keyL[i], vel[i], off[i]);
                                     for j=1..7 if noteOn[j]: voiceNote(keyL[i]+256j, vel[i], off[i]+shift[j]) }
    // consecutive non-0 steps: nothing (the chord sustains)
} else {  // mode 5
    if (c == 7) gSub = gSubPrev
    gSub = advance(gSub)
    if (!(gSub == gSubPrev && prevCmd != 0)) {
        for i<count: voiceNote(keyL[i], 0, 0)
        for i<count: gSub == 0 ? voiceNote(keyL[i], vel[i], off[i])
                               : voiceNote(keyL[i] + (gSub<<8), vel[i], off[i] + shift[gSub])
    }
    gSubPrev = gSub; if (++gSub > 7) gSub = 0
}
```
Mode 5 therefore plays the whole held chord transposed by 0, shift a, shift b, … (enabled notes), one
transposition per "on" step. With no arp notes enabled, the chord is played once and held, and it is
retriggered only after an "off" step. In chord modes a MIDI note-off releases that key at once, and a
note-on during an "on" step sounds at once (4.1).

### 8.8 Random source
MSVCRT.dll `rand()`: `holdrand = holdrand*214013 + 2531011; return (holdrand>>16) & 0x7fff`. It is per
thread, seed 1, and **never seeded by the plugin** (srand is not imported). The same sequence is shared
by every random feature: one call per voiceNote-on, random amp/pan in voice start, 32+ calls per voice
reset (unison detune), LFO resets, XY random walk, and so on. So arp randomness cannot be reproduced
bit-exactly in practice. Any 15-bit uniform generator with the formulas above is equivalent.

---------------------------------------------------------------------------------------------------------

## 9. Quirks to keep (summary)
1. Note events are quantised to 64-sample sub-blocks (`64·ceil(delta/64)`). The first arp note is
   delayed by one sub-block.
2. Re-striking a held key (note-on without note-off) keeps the same voice with
   `velocity = curve(vel) + current amp-env level` (can exceed 1). Measured: 0.51 + 0.71 = 1.22,
   output ×6.5.
3. Mono/Legato return to the **oldest** held note. The Poly revival can steal another held note (5.6).
4. Mono mode (0) uses a new voice per note, with overlapping releases up to Max polyphony.
5. The sustain pedal slows releases 128× instead of holding notes. The CC64 threshold is 63.
6. Glide is linear in Hz. The oscillator ramp snaps at block granularity, so glides ≤ 64 samples are
   instant. There is no glide for a stolen, still-audible non-head voice. Poly glides from the most
   recent voice.
7. Legato never triggers the envelopes of filter objects 3/4 (+0x20fc, +0x2324).
8. Arp: notes 5-7 alone do not enable subsequences in pattern modes. `off[]`/`sub[]` are not shifted on
   insert/remove. Mode 5 note-on uses the next transposition. In pattern modes a MIDI note-off does not
   stop the arp note before the next step. The arp free-runs with no notes held.
9. Arp transpositions use the per-pitch-class tuning of their base note.
10. CC 123-127 cut all voices instantly (no release).

## 10. Sample-rate dependence
Event timing and arp timing use a fixed 64-sample grid, so the time resolution is 1.45 ms at 44.1 kHz.
Glide samples `= round(ms·SR/1000)`. Arp ms/10ms/sec units use SR, and beat units use
`60/tempo·SR`. Phase increments are `2^32·f/SR`. The ramp threshold of 1000 increment units is
0.01 Hz at 44.1 kHz.

## 11. Verification details (scripts in `OM/work_arp/`, run with 32-bit Python)
* `common.py`: helpers, including memory readers for the note object, the VM voice list and the program
  struct. `hook_rand()` patches the DLL's IAT entry for `rand` to a Python callback, so the arp random
  commands can be driven with known values.
* `arpmodel.py` + `t7_compare.py`: randomized note-object/arp comparison (§0), per block. Run as
  `t7_compare.py 100 160`: 0 mismatches, 5467 steps. Seeds 0..11 with long steps were also 0 mismatches.
* `vmmodel.py` + `t8_vmcompare.py`: randomized voice-allocation comparison (full list order + release
  counters + return-to-held), 60 seeds, 0 mismatches.
* `t1_timing.py`: event quantisation (host blocks 64/100/256).
* `t2_alloc.py`: Goertzel note presence for the poly/mono/legato scenarios (steal oldest; return to C;
  legato without retrigger).
* `t3/t4/t5/t13/t16`: glide trajectories. For all glide modes the measured duration equals the formula
  (e.g. mode 3, 69→62: 5066.4 measured vs 5066). Also: poly/mono/stolen-voice cases and the
  block-snap behaviour.
* `t9_sustain.py` (pedal), `t10_unison.py`, `t11_arpaudio.py` (arp note onsets at 64/16640/33152 samples with
  the pitches predicted by the model), `t12_reusevel.py`, `t14_note5bug.py`, `t15_restrike.py`.

## 12. Open questions / not covered
* Envelope internals (states 1-9, the smoothing, what state 9 is) and the pitch-env stage machine
  (`0x2a28/0x2a34/0x2a38`, and why fresh voices load chunk 8456 = "F mix" into 0x2a28) belong to the
  envelope/modulation specs. The legato filter-env quirk (§6.2) was read from code but not confirmed
  by audio.
* Global phantom mod envelopes (VM+0x31c/+0x33c): only their trigger/release points are given here.
* The exact rand() call count per event (needed only for bit-exact random reproduction) was not
  catalogued.
* Tempo changes during a run and queue overflow (>32 pending events) were not exercised against the
  DLL. The model follows the code.
