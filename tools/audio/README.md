# tools/audio

Generator + QA for everything in `assets/audio/` (station announcements, ambience beds, SFX).
Nothing here is loaded by Godot (`.gdignore` at `tools/`).

```
build/venv/bin/python tools/audio/make_audio.py                  # everything (speech ~20 min on 10 cores, rest ~2 min)
build/venv/bin/python tools/audio/make_audio.py --only speech    # Piper TTS clips only
build/venv/bin/python tools/audio/make_audio.py --only ambience  # looping beds
build/venv/bin/python tools/audio/make_audio.py --only sfx       # one-shots, trains, busker, UI
build/venv/bin/python tools/audio/make_audio.py --names footstep_tile door_chime    # substring filter
build/venv/bin/python tools/audio/make_audio.py --force          # ignore the speech cache
build/venv/bin/python tools/audio/qa_audio.py                    # verify assets/audio (exit 1 on failure)
```

Needs `numpy scipy pillow piper-tts` (the `build/venv`) and `ffmpeg` with libvorbis.
Piper voices are downloaded on demand from Hugging Face (`rhasspy/piper-voices`) into `build/audio/voices/`.

| file | purpose |
|------|---------|
| `make_audio.py` | orchestration, multiprocessing, manifest merge (`assets/audio/manifest.json`) |
| `speech.py` | Piper front end (own phonemiser wrapper so `[[IPA]]` overrides work), name cleaning, PA colouration, list of every speech clip |
| `pronunciations.json` | word/phrase respellings + IPA applied to station names before TTS |
| `ambience.py` | looping beds (tunnel, platform, concourse, corridor, escalator, train interior, crowds) |
| `train.py` | arrive / depart / pass-through one-shots from a kinematic model (distance, speed, Doppler, tunnel mouth) |
| `sfx.py` | doors, gates, footsteps, ticket machines, UI, busker; **registry** of all non-speech assets and their metadata |
| `synth_common.py`, `dsp.py` | building blocks: periodic noise, reverb, BS.1770 loudness, limiter, ogg encoding |
| `qa_audio.py` | QA (existence, duration, clipping, loudness, loop seams, coverage, totals) |

## Design notes

* **Loops are seamless by construction**: noise is generated in the frequency domain over exactly the loop
  length, filters/reverbs are circular, events wrap around the end, hums use an integer number of cycles.
  There is no crossfade to hear. `dsp.crossfade_loop` exists for non-periodic material.
* **Speech**: voices `en_GB-cori-high` (female: station / platform PA and on-train station announcements) and
  `en_GB-alan-medium` (male: driver). Each phrase is phonemised by espeak-ng inside Piper; `pronunciations.json`
  overrides words espeak gets wrong (Holborn, Southwark, Marylebone, Cockfosters, Edgware, Bakerloo, ...) by
  injecting IPA directly. Styles: `train_pa` (band-limited, gentle compression), `driver` (narrow, mid-heavy,
  slightly gritty), `platform_pa` (300 Hz-6 kHz horn speaker + short tiled-hall reverb). Every clip is trimmed and
  normalised to -16 LUFS (BS.1770 gated), peak-limited at -1.5 dBFS, encoded Vorbis 56 kbps mono.
* **Speech is not bit-reproducible** (Piper injects random noise inside the model); clips are cached by
  (text, voice, style) signature in `build/audio/speech_cache.json`, so re-running only renders what changed.
  Procedural assets are seeded by asset name and deterministic.
* Adding a sound: write a generator returning a float array in `sfx.py` (or `ambience.py` for loops) and add it to the
  registry with category / normalisation / suggested volume.

## Optional pronunciation check

`pip install faster-whisper` in a scratch venv and transcribe the station-name clips: mismatches point at
words that need an entry in `pronunciations.json` (whisper mishears some genuine local pronunciations,
e.g. Theydon Bois, so treat it as a hint only).
