# PianoML-13EDO

A SuperCollider instrument that generates original piano phrases in 13-EDO from a model trained on the Chopin MIDI corpus. A FluCoMa neural net (`FluidMLPRegressor`) learns which interval and rhythm tend to follow the previous notes; a smoothed variable-order Markov model trained on the same data is the fallback when FluCoMa is missing or the net is still loading. Generated notes are steered towards an editable chord progression. Playback uses the Salamander Grand Piano V3 WAV samples, with sampled key-release and pedal noises.

## Requirements

Download and install these before running the project:

1. **SuperCollider 3.13 or later** from <https://supercollider.github.io/downloads>.
2. **FluCoMa for SuperCollider** from <https://learn.flucoma.org/installation/sc>. Follow its installation guide, then recompile the class library (Language > Recompile Class Library) and restart SuperCollider. FluCoMa runs the neural net; without it, only the Markov model is used.
3. **Salamander Grand Piano V3, 44.1 kHz 16-bit** (about 394 MB, licensed [CC BY 3.0](http://creativecommons.org/licenses/by/3.0/)) from FreePats: <https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html>. Download `SalamanderGrandPianoV3+20161209_44khz16bit.tar.xz` and extract it into this `SuperCollider` folder, so that the WAV files end up at:

   ```text
   SuperCollider/SalamanderGrandPianoV3_44.1khz16bit/44.1khz16bit/C4v8.wav
   ```

   Rename the extracted folder to `SalamanderGrandPianoV3_44.1khz16bit` if its name differs. The samples are not included in this repository, and the project will report "Salamander sample not found" until they are in place. The SuperCollider sampler loads the WAV files directly; no SFZ plugin is needed.
4. **The `wslib` Quark**, which provides `SimpleMIDIFile` for reading and writing MIDI. In SuperCollider, run the line below, then recompile the class library:

   ```supercollider
   Quarks.install("wslib");
   ```

## Start

Open and evaluate `PianoML-13EDO.scd`. Saved models in `models/` load automatically; the neural net becomes available once the audio server has booted.

- **Train on corpus** trains both models on a seeded random sample of the `.mid` files under `MIDI/Chopin` (settings at the top of `parts/learning.scd`: `trainFiles`, `maxPoints`, `trainRounds`) and saves them to `models/`.
- **Browse MIDI** / **Load path** (optional) loads a MIDI file whose opening phrase primes the model and whose velocities are reused.
- **Generate**, **Play**, and **Stop** create and perform a phrase. The tempo can be changed while playing.
- **Duration** (minutes and seconds) sets the length of the piece at the current tempo, rounded up to whole bars; the melody ends on a held tonic note over a final tonic chord.
- **Meter** chooses 4/4 or 3/4.
- **Left hand** chooses the accompaniment: Broken chord, Arpeggio, Alberti, Waltz, Block chords, Octave bass, **Learned (corpus)** (a Markov model of the corpus left hand: bass leaps, rhythm and chord size, snapped onto the current chord), or **Mixed** (a new form every 4 bars).
- **Corpus influence** sets how strongly the model outweighs the harmony; **Temperature** makes choices safer (lower) or more surprising (higher).

Select a harmony preset or enter a progression in the text field and choose **Apply harmony** before generating again. Each chord is a semicolon-separated group of pitch classes from `0` to `12`; chord tones use commas. For example:

```text
0,3,7; 5,8,12; 2,5,9; 7,10,1
```

Pitch class `0` is anchored to A4 (440 Hz). Playback uses only the Salamander C samples (C1 to C8), each resampled by an exact frequency ratio to the 13-EDO pitch, so no 12-EDO pitch leaks into the tuning. **Auto sustain pedal** holds notes through each bar's pedal-up point and plays the Salamander pedal-down/up samples. Exported `.mid` files include CC64 sustain events but quantize 13-EDO pitches to the nearest 12-tone MIDI note. **Export audio** renders the piece, exactly as played (13-EDO Salamander samples, release and pedal noises, limiter), to a 48 kHz 24-bit stereo WAV file. Rendering runs offline in a separate scsynth process, much faster than real time, and does not use the running server.

## Files

- `PianoML-13EDO.scd` loads the modules and opens the interface.
- `parts/edo.scd` handles 13-EDO pitch conversion and harmony input.
- `parts/salamander.scd` maps notes to the C samples, loads the WAV files, and defines the sampler and limiter SynthDefs.
- `parts/learning.scd` extracts melodies from the corpus and trains, saves, and loads the neural net and Markov models.
- `parts/lefthand.scd` provides the left-hand forms and trains the learned left-hand model.
- `parts/corpus.scd` reads the loaded MIDI file used to prime the model.
- `parts/flucoma.scd` builds normalized phrase-feature data for the loaded MIDI file with FluCoMa.
- `parts/composer.scd` generates the melody from the model and the accompaniment from the harmony.
- `parts/piano.scd` defines sampled piano playback, sustain-pedal scheduling, MIDI export, and audio export.
- `parts/interface.scd` provides the controls.
- `models/` holds the trained models.
