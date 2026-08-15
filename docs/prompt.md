# Sofler — Next step after initial CrisperWhisper tests

We need to continue the POC based on your latest findings and the real voice samples I have now added.

Do NOT start building the full UI or the production application yet.

The immediate objective is to finish the validation phase with my real voice and determine whether CrisperWhisper is good enough to justify the next stage of the project.

---

## 1. Important context from your previous tests

Your initial tests already established several important points:

- CrisperWhisper Turbo loads and runs locally on my Mac.
- The current Python/MPS implementation has around 3.3–3.6 GB RSS for Turbo in float16.
- Cold model loading is around 10–17 seconds, which is acceptable for a persistent warm model but not for loading per transcription.
- Current inference latency is around 1.7–2.0 seconds for short audio.
- The latency appears largely independent of the actual audio duration, suggesting that the current implementation is processing a fixed-size Whisper input.
- Verbatim vs Intended works in French.
- Vocabulary/hotword experiments showed that technical terms such as `useEffect` can be strongly improved.
- However, vocabulary biasing can also introduce regressions in normal French text.
- Some terms such as `feature`, `TypeScript`, and numbers still need investigation.
- The previous automatic metric was flawed because generic words such as `main`, `state`, and `feature` produced false positives.

These findings should be treated as preliminary observations, not final conclusions.

---

# 2. I have now added my real voice samples

I added the following directory to the project:

```text
poc/samples/
````

It contains my real voice recordings.

I also added:

```text
poc/samples/references.md
```

## IMPORTANT about references.md

The text in `references.md` is primarily a reference for the intended content of each recording.

The recordings are deliberately NOT 100% identical to the text written in `references.md`.

This is intentional.

When recording, I naturally:

* changed some wording;
* added words;
* removed words;
* hesitated;
* repeated words;
* reformulated sentences;
* sometimes added small spontaneous phrases.

This is exactly what I want to test.

Therefore:

**Do NOT treat `references.md` as an exact ground-truth transcript.**

It should be treated as an approximate semantic/textual reference for what I was trying to say.

For evaluation:

* distinguish genuine transcription errors from legitimate differences caused by my spontaneous speech;
* do not penalize the model simply because it produced a slightly different wording when the meaning is correct;
* for Verbatim, compare against the actual audio as the ultimate source of truth;
* for Intended, evaluate semantic correctness and quality rather than exact string matching.

---

# 3. Use my actual voice as the primary benchmark now

This is now more important than the previous synthetic/TTS tests.

My real voice samples are specifically designed to test:

* French;
* French/English code-switching;
* developer vocabulary;
* React;
* TypeScript;
* Next.js;
* `useEffect`;
* `useState`;
* `component`;
* `dependencies`;
* `hook`;
* `refactor`;
* `merge`;
* `pull request`;
* `commit`;
* technical numbers such as `500`;
* natural hesitation;
* repetitions;
* spontaneous reformulation;
* English speech.

Do not replace these samples with synthetic speech.

You may continue using synthetic samples for controlled experiments, but my real recordings must be the primary validation set.

---

# 4. Re-run J0 with my samples

Start with:

**CrisperWhisper 2.0 Turbo**

Do not benchmark every model yet.

First establish whether Turbo is good enough.

For each sample, test at least:

1. Verbatim
2. Intended

Record:

* raw transcription;
* inference time;
* total latency;
* model loading time;
* memory usage;
* any obvious hallucination;
* technical vocabulary errors;
* language/code-switching errors.

Do not rely only on an automatic WER/CER metric.

Show the actual transcription outputs.

---

# 5. Specifically evaluate developer code-switching

This is one of the most important goals of the project.

Pay particular attention to terms such as:

```text
useEffect
useState
TypeScript
React
component
dependencies
hook
refactor
merge
commit
pull request
endpoint
middleware
feature
500
npm
Next.js
```

We want to know whether the model preserves these terms when spoken naturally inside French sentences.

Example:

```text
"Je vais modifier le component React parce que le useEffect n'a pas les bonnes dependencies."
```

The desired behavior is NOT necessarily an exact sentence match.

The important thing is that technical terms remain technically correct.

For example:

```text
useEffect
```

should not become:

```text
russe-fake
```

and:

```text
component
```

should not be unnecessarily translated or corrupted.

---

# 6. Investigate vocabulary conditioning carefully

Your previous experiment showed a very promising result:

```text
useEffect
→ incorrect without vocabulary conditioning
→ correct with vocabulary conditioning
```

This is potentially one of the most important technical findings of the project.

However, it also showed regressions in ordinary French when a vocabulary list was active.

Therefore:

**Do not simply enable a large vocabulary list globally.**

Investigate:

* how vocabulary conditioning is actually implemented;
* whether it can be made context-aware;
* whether it can be limited to a small relevant lexicon;
* whether it can be activated only in developer contexts;
* whether prompt conditioning can achieve the same effect;
* whether the behavior is stable on the real recordings.

Do NOT assume that the official `hotwords` API is safe for the standard models.

The objective is to understand the underlying mechanism, not blindly reproduce the Pro API.

---

# 7. Context-aware vocabulary is an important research direction

The eventual product may be able to distinguish contexts such as:

```text
VS Code / Cursor / Xcode
→ developer vocabulary enabled

Terminal
→ developer vocabulary enabled

Browser / ChatGPT
→ potentially developer vocabulary enabled

Mail / Messages / Notes
→ normal vocabulary
```

However:

**DO NOT implement application-context detection yet.**

First prove that vocabulary conditioning itself is useful and controllable.

---

# 8. Test Verbatim / Intended properly

The previous tests already suggest that this works in French.

Now validate it on my real hesitation sample.

For example, if I say something like:

```text
"Alors euh... je pense que... enfin non attends..."
```

Verbatim should preserve the relevant hesitation/repetition.

Intended should clean it up.

The goal is to verify that the distinction remains useful with real spontaneous speech.

---

# 9. Investigate the 1–10 fidelity levels

If the underlying CrisperWhisper tokens support the different fidelity levels you identified, test them using my real hesitation sample.

Do NOT assume that all ten levels are meaningfully different.

Produce something like:

```text
Level 1:
...

Level 2:
...

Level 3:
...

...

Level 10:
...
```

Then determine:

* whether there is actually a useful progression;
* whether the progression is monotonic;
* whether some levels are effectively identical;
* whether higher "cleanliness" causes semantic loss;
* whether the behavior works in French;
* whether it remains useful with developer vocabulary.

If the 10-level slider is not reliable, say so.

Do not force this feature into the product merely because the tokens exist.

---

# 10. Fix the evaluation methodology

The previous automatic metric produced false positives because common words such as:

```text
main
state
feature
```

can naturally appear as parts of other French words.

Do not use simplistic substring matching.

If creating an automatic evaluation:

* use token-aware matching;
* normalize punctuation;
* distinguish technical vocabulary from common French words;
* avoid false positives caused by substrings;
* preserve case-insensitive comparisons where appropriate;
* separately evaluate numbers.

For technical terms, use explicit token boundaries and/or normalized token matching.

The raw transcription remains the authoritative output for qualitative evaluation.

---

# 11. Investigate the numbers problem

Your previous test showed:

```text
500
```

was frequently corrupted.

This is important because developers routinely dictate:

```text
500
404
200
3.12
16
26
npm
v3
```

Test numbers separately.

Determine whether the problem comes from:

* the model;
* French pronunciation;
* audio preprocessing;
* tokenizer;
* decoding;
* Whisper's general behavior;
* vocabulary conditioning;
* the synthetic voice.

Do not attempt a complicated solution yet.

Just characterize the problem.

---

# 12. Investigate the ignored encoder_blank_head weights

You noticed that Transformers ignored:

```text
encoder_blank_head.weight
encoder_blank_head.bias
```

This is interesting because the use case is:

```text
User presses the dictation hotkey
↓
User says nothing
↓
We should NOT produce hallucinated text
```

Investigate what this head actually does in the CrisperWhisper architecture.

Determine whether it is related to:

* blank/silence detection;
* hallucination prevention;
* audio activity detection;
* endpoint detection.

Do not implement it yet unless the investigation is conclusive.

The desired eventual behavior is:

```text
No meaningful speech
→ no transcription
→ no text insertion
```

---

# 13. Latency investigation

The current MPS implementation is around:

```text
~1.7–2.0s
```

for short samples.

This is too slow for the final user experience.

However, do NOT optimize blindly yet.

First measure the current pipeline precisely:

```text
microphone/audio preparation
↓
mel preprocessing
↓
encoder
↓
decoder
↓
post-processing
↓
text injection
```

Determine which component dominates the latency.

The current observation that latency is almost independent of audio duration suggests fixed-size encoder processing.

Validate this with a controlled benchmark.

---

# 14. Dynamic encoder length

Investigate whether the Whisper/CrisperWhisper encoder can safely process a shorter audio window for short dictation instead of always processing a full 30-second window.

Potential objective:

```text
5 second audio
→ process approximately 5–8 seconds
```

instead of:

```text
5 second audio
→ process 30 seconds
```

BUT:

Do not break:

* timestamps;
* longform behavior;
* conditional continuation;
* hallucination repair;
* Verbatim/Intended behavior.

This is a research/optimization task.

Do not implement it in the production app until its correctness is demonstrated.

---

# 15. Runtime / backend strategy

Do not commit yet to:

* whisper.cpp;
* Core ML;
* Core AI;
* MLX;
* CTranslate2;
* PyTorch/MPS.

Benchmark and choose based on actual results.

The intended long-term architecture is:

```text
SpeechEngine
    │
    ├── CrisperWhisper
    │
    ├── Free / commercially compatible engine
    │
    └── Apple Speech fallback
```

The application should not be coupled to a single inference runtime.

---

# 16. Apple Silicon remains a core project objective

My machine is:

```text
MacBook Pro
Apple M4 Pro
48 GB RAM
macOS 26.6
```

The project is intentionally:

**Apple Silicon only.**

The goal is not merely to compile for ARM64.

We want to investigate how to make the inference pipeline properly exploit:

* Apple GPU;
* Neural Engine;
* Core ML;
* Metal;
* Accelerate;
* unified memory;
* Apple Silicon-specific optimizations.

Core ML / ANE should therefore remain an important J3 investigation.

But do not delay the first usable prototype for weeks just to achieve a perfect Core ML implementation.

---

# 17. Current development environment

I have now installed `uv`.

Homebrew reported:

```text
uv 0.12.4 is already installed and up-to-date.
```

Inside the project I ran:

```bash
uv python pin 3.12
```

and the project now contains:

```text
.python-version
```

with:

```text
3.12
```

So use the project's `uv` environment rather than relying on the system Python.

Do NOT modify or replace the system Python 3.9.6.

If necessary, create the project environment with `uv` and install the required dependencies there.

---

# 18. Xcode

I have installed Xcode from the Mac App Store.

My machine previously had only the Command Line Tools active.

After Xcode installation:

**verify the environment yourself.**

Check:

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-path
```

If the active developer directory still points to:

```text
/Library/Developer/CommandLineTools
```

configure it to the installed Xcode.

Do not assume the exact Xcode path/version without checking.

If anything is missing or incompatible, tell me exactly what needs to be fixed.

---

# 19. Do not over-engineer yet

At this stage, do NOT build:

* menu bar UI;
* settings;
* history;
* global hotkeys;
* text injection;
* Core ML production pipeline;
* signing;
* notarization.

Those come after the model validation.

The immediate goal is:

```text
REAL VOICE
↓
CrisperWhisper Turbo
↓
GOOD TRANSCRIPTION?
```

---

# 20. Revised roadmap

## J0 — Real voice validation

* Verify environment.
* Use my real samples.
* Turbo.
* French.
* French/English code-switching.
* Verbatim.
* Intended.
* latency.
* memory.
* raw outputs.

## J1 — Developer vocabulary

* vocabulary conditioning;
* prompt conditioning;
* technical lexicon;
* real voice validation;
* 1–10 fidelity experiment;
* numbers;
* regressions.

## J2 — First usable native prototype

Only if J0/J1 are successful:

```text
Swift
↓
Microphone
↓
SpeechEngine
↓
CrisperWhisper/runtime
↓
Text
↓
macOS caret
```

Minimal functionality:

* global hotkey;
* start/stop;
* transcription;
* text insertion.

## J3 — Apple Silicon optimization

Investigate:

* Core ML;
* ANE;
* Metal;
* dynamic encoder length;
* memory;
* latency;
* warm model lifecycle.

## J4 — Product layer

Only after the engine is proven:

* menu bar;
* fidelity slider;
* language;
* developer lexicon;
* transcription history;
* settings;
* Apple Speech fallback;
* signing;
* notarization;
* DMG.

---

# 21. Product direction

The project should remain:

**Sofler**

> Local dictation that speaks developer.

The core product hypothesis is:

> A private, local, extremely fast dictation tool for macOS that handles French/English developer speech particularly well.

The differentiator is NOT simply:

> "AI dictation on Apple Silicon."

The differentiator should be:

> "Dictation that understands how developers actually speak."

In particular:

```text
French
+
English
+
technical vocabulary
+
code-switching
+
natural hesitation
+
local inference
```

---

# 22. Important: challenge the hypothesis

Do not try to make the project succeed.

Try to determine whether it actually works.

If the real voice samples show that:

* Turbo is not good enough;
* code-switching is too unreliable;
* numbers are unacceptable;
* vocabulary conditioning causes too many regressions;
* latency cannot realistically reach the target;
* or the model cannot be ported correctly;

say so.

A failed hypothesis discovered early is a successful POC.

The goal of this phase is to obtain evidence, not to justify the architecture we initially imagined.

---

## Immediate action

1. Verify the current environment.
2. Confirm the `uv` / Python 3.12 project environment.
3. Find and load all samples in `poc/samples/`.
4. Read `references.md` as approximate semantic references, NOT exact transcripts.
5. Run the real-voice Turbo benchmark.
6. Report raw outputs and measurements.
7. Only then decide whether J1 vocabulary experiments should continue.

Do not start the Swift UI yet.