# Caret

> **Local dictation that speaks developer.**
> Press a key. Talk. Press it again. Your words land at the caret — `useEffect` spelled `useEffect`.

Caret is a macOS dictation tool for Apple Silicon that handles how developers
actually speak: French and English in the same sentence, technical vocabulary,
hesitations. Everything runs on-device. No account, no cloud, no telemetry.

**Status: engine validated, native app in progress.** See [Roadmap](#roadmap).

---

## Why another dictation app?

macOS already has several good open-source local dictation tools. They share one
blind spot: they assume you speak *one* language at a time.

A French developer doesn't:

> « Tu as oublié les **dependencies** dans le **useEffect**. »

Every general-purpose speech model forces a single language token per segment.
In French mode, English technical terms get phonetically absorbed:

| Spoken | Whisper-family, French mode |
|---|---|
| `useEffect` | *« use effect »*, *« russe-fake »* |
| `dependencies` | *« dépendances »* |
| `React` | *« react »* (lowercase) |

Caret fixes this with **vocabulary conditioning** — a trained mechanism in
CrisperWhisper 2.0 that biases decoding toward a supplied lexicon.

Measured on real French/English developer speech:

| | Technical terms preserved |
|---|---|
| Without lexicon | 29/34 (85%) |
| **With lexicon** | **32/34 (94%)** |

No regression on plain French sentences.

---

## Measured results

All numbers from a MacBook Pro M4 Pro, 48 GB, macOS 26.6, on real voice
recordings — not synthetic speech. Reproduce them with the scripts in
[`poc/`](poc/).

### Latency

Round-trip through the engine service, model kept warm:

| Audio | Engine | mel | encoder | decoder |
|---|---|---|---|---|
| 13,2 s | **425 ms** | 6 ms | 296 ms | 120 ms |
| 12,2 s | **536 ms** | 5 ms | 376 ms | 154 ms |
| 29,2 s | 1 123 ms | 3 ms | 746 ms | 372 ms |

That is **4–5× faster than CrisperWhisper's own Python pipeline** on identical
audio, with byte-identical transcriptions. Two findings account for the gap:

**1. The reference pipeline costs more than the model.** Raw compute measured
at ~0,80 s where the package took ~2,30 s — roughly **1,5 s of pipeline
overhead** per transcription. Caret calls mel → encoder → greedy decode
directly.

**2. Whisper always encodes 30 seconds.** Encoder cost is independent of what
you actually said — it processes a fixed 30 s mel window, mostly silence for a
short dictation. Shrinking the window to 15 s cuts encoder time ~45% with
**strictly identical output**:

| Sample | 30 s window | 15 s window | Text |
|---|---|---|---|
| 13,2 s | 0,76 s | **0,41 s** | identical |
| 12,2 s | 0,84 s | **0,44 s** | identical |
| 16,3 s | 0,82 s | **0,48 s** (20 s) | identical |

Below 15 s the model leaves its training distribution and output becomes
unpredictable — one clip stayed intact down to 4 s while another degraded at
10 s (*« Tu as oublié »* → *« State a oublié »*). **15 s is the safe floor**,
and Caret does not go under it.

### Verbatim vs Intended

CrisperWhisper exposes two transcription styles. Both work in French:

```
verbatim : « Donc je je pense que enfin, le composant devrait être refactoré. »
intended : « Donc je pense que, enfin, le composant devrait être refactoré. »
```

Numbers settle the default. Verbatim transcribes what you *said*, intended what
you *meant*:

```
verbatim : « renvoie bien un deux cents au lieu du cinq cents »
intended : « renvoie bien un 200 au lieu du 500 »
```

Nobody wants *« erreur cinq cents »* in a bug report. **Intended is the
default**; verbatim is available for interview or note-taking use.

---

## Architecture

The speech engine sits behind a socket protocol, so it can be swapped without
touching the app:

```
┌──────────────────────────┐
│  Caret.app  (Swift)      │
│  hotkey → capture →      │
│  inject at caret         │
└───────────┬──────────────┘
            │  unix socket, length-prefixed frames
            │  PCM int16 mono 16 kHz
┌───────────▼──────────────┐
│  SpeechEngine            │
│  ├─ CrisperWhisper       │  ← today (PyTorch/MPS)
│  ├─ Core ML / ANE        │  ← planned
│  └─ Apple SpeechAnalyzer │  ← fallback, no download
└──────────────────────────┘
```

```
caret/
├── engine/          Python transcription service (current backend)
│   └── caret_engine/
│       ├── crisper.py    inference: mel → encoder → greedy decode
│       ├── prompt.py     CrisperWhisper decoder prompt construction
│       ├── protocol.py   the app ↔ engine contract
│       └── server.py     persistent unix-socket service
├── app/             Swift menu-bar app
└── poc/             benchmarks and experiments behind the numbers above
```

### How the prompt actually works

CrisperWhisper conditions behaviour with tokens placed **before**
`<|startoftranscript|>`, not through Whisper's `<|startofprev|>`:

```
[intended_1..5]  <htx> useEffect component React <ehtx>  <|sot|> <|fr|> <|transcribe|> <|notimestamps|>
```

Two things worth knowing, both verified against the released weights:

- The five mode tags are emitted **as one block** — a soft prompt carrying a
  single signal. There are two modes, not ten fidelity levels.
- The hotword markers `<htx>` / `<ehtx>` (ids 51895/51896) **exist in the
  open-weight models**. Vocabulary conditioning works without Nyra's Pro tier.

---

## Requirements

- Apple Silicon Mac (M1 or later) — Intel is not supported
- macOS 26+
- ~1,6 GB disk for the `turbo` model, downloaded on first run

## Getting started

### 1. Start the engine

```bash
cd engine
uv venv --python 3.12 && uv pip install -e .
uv run python -m caret_engine.server
```

The model loads once (~8 s) and stays warm. Leave this running. Verify it
answers:

```bash
uv run python client_test.py ../poc/samples/01-fr-dev.wav
```

### 2. Build and launch the app

```bash
cd app
./build_app.sh && open Caret.app
```

Caret appears in the menu bar — no Dock icon, no window.

### 3. Grant two permissions

| Permission | Why | When |
|---|---|---|
| **Microphone** | capture your voice | prompted on first dictation |
| **Accessibility** | insert text into other apps | System Settings › Privacy & Security › Accessibility |

Accessibility must be granted manually, then relaunch Caret.

### 4. Dictate

| Shortcut | Action |
|---|---|
| **⌃⌥D** | start / stop dictation |
| **Escape** | cancel while recording (no text inserted) |

Press `⌃⌥D`, talk, press again. Text lands at the cursor of whatever app is
focused.

**Why `⌃⌥D`?** macOS 15+ rejects global hotkeys whose only modifiers are
Option and/or Shift — an anti-keylogger measure — so `⌥Space` cannot work. And
on a French AZERTY keyboard Option types `@ # { } [ ] | \ ~`, which rules out
Right Option as a push-to-talk key for developers. `⌃⌥D` is free, mnemonic, and
needs no Input Monitoring permission since it goes through Carbon's
`RegisterEventHotKey` rather than a `CGEventTap`.

---

## Roadmap

- [x] **J0** — validate CrisperWhisper on real French/English developer speech
- [x] **J1** — latency breakdown, adaptive encoder window
- [x] **J2** — persistent engine service (4–5× faster than reference pipeline)
- [x] **J3** — Swift app: global hotkey, capture, inject at caret
- [ ] **J4** — VAD (no inference on silence) and anti-hallucination guards
- [ ] **J5** — Core ML / Neural Engine backend
- [ ] **J6** — menu bar, settings, history, signing, notarization

### Known gaps

- **No VAD.** Pressing the hotkey and saying nothing runs inference on silence.
  CrisperWhisper ships an `encoder_blank_head` in its weights, but no backend
  references it — it is a training leftover. A separate VAD is needed.
- **No anti-hallucination guard.** CrisperWhisper's loop-repair lives in
  `hallucination.py`, which imports `ctranslate2` — and CTranslate2 has no
  Apple Silicon wheel (Linux x86_64 only). These protections are inactive on
  macOS and must be reimplemented.
- **30 s ceiling.** Whisper's architectural limit. Longer dictations are
  truncated; long-form chunking is not implemented.
- **Speculative decoding is not possible** on macOS. It requires CTranslate2,
  and the documented `large` + `turbo` pairing is structurally mismatched
  anyway: 80 vs 128 mel bins, 51896 vs 51897 vocab. `small` → `large` share
  both and would be the viable pair.

---

## Licensing — read this before using the models

Caret's own code and CrisperWhisper's inference code are MIT. **The model
weights are not.**

| Component | License |
|---|---|
| Caret source code | MIT |
| CrisperWhisper inference code | MIT |
| **CrisperWhisper 2.0 weights** | **Nyra Health Non-Commercial Research** |

The weights are free for research and non-commercial use. Commercial use
requires a licence from [Nyra Health](https://nyra-labs.com/crisperwhisper).
Under a strict reading, dictating work email may itself count as commercial
use.

Consequently Caret **does not bundle or silently download the weights**. The
licence is shown before any download, and the choice is yours. A
commercially-unencumbered engine is on the roadmap so the app is usable
regardless.

This is a summary, not legal advice. Read
[the licence](https://huggingface.co/nyralabs/CrisperWhisper2.0_turbo/blob/main/LICENSE.md).

---

## Acknowledgements

- [CrisperWhisper](https://github.com/nyrahealth/CrisperWhisper) by Nyra Health
- [Whisper](https://github.com/openai/whisper) by OpenAI
