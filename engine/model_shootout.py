"""Comparaison des moteurs de transcription locaux sur voix réelle.

La question n'est pas « lequel a le meilleur score publié » mais « lequel sert
le mieux cet usage » : du français parlé mêlé de vocabulaire technique anglais,
sur un Mac, sans réseau.

Trois candidats, chacun avec son meilleur réglage :

* **CrisperWhisper 2.0 turbo** — l'actuel. Conditionnement par vocabulaire via
  ses tokens propres, et modes verbatim/intended.
* **Whisper large-v3-turbo** — le standard d'OpenAI, optimisé sur le taux
  d'erreur de mots et non sur la détection de disfluences. Il possède son
  propre mécanisme de biais, ``<|startofprev|>``.
* **Parakeet TDT 0.6b v3** — le transducteur de NVIDIA, celui qu'utilise
  FluidVoice. Réputé très rapide sur Apple Silicon. Pas de mécanisme de biais
  exposé, donc testé tel quel.

    uv run python model_shootout.py
"""

from __future__ import annotations

import gc
import resource
import time
from pathlib import Path

import numpy as np
import soundfile as sf

SAMPLES = Path(__file__).parent.parent / "poc" / "samples"

LEXICON = [
    "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
    "hook", "props", "state", "refactor", "merge", "commit", "branch",
    "pull request", "endpoint", "dependencies", "async", "await", "chunk",
]

# Ce que chaque transcription doit préserver. C'est le seul critère qui
# compte ici : un modèle qui écrit un français impeccable mais rend
# « use effect » ne sert pas cet usage.
EXPECTED = {
    "01-fr-dev": ["component", "React", "useEffect", "dependencies"],
    "02-franglais-500": ["merge", "feature", "endpoint", "200", "500"],
    "03-refactor": ["refactor", "hook", "component", "duplicated"],
    "04-nextjs": ["Next.js", "component", "useState", "useEffect"],
    "05-natural-long": ["service", "refactor", "component"],
    "06-hesitations": ["useEffect", "dependencies"],
    "07-english": ["refactor", "component", "branch", "dependencies"],
    "08-franglais-natural": ["pull request", "comments", "component"],
}


def rss_gb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def samples():
    for wav in sorted(SAMPLES.glob("*.wav")):
        if wav.stem not in EXPECTED:
            continue
        audio, _ = sf.read(str(wav), dtype="float32")
        yield wav, audio, ("en" if wav.stem.endswith("english") else "fr")


# --------------------------------------------------------------------------
# Moteurs
# --------------------------------------------------------------------------

def run_crisper():
    from caspr_engine.crisper import CrisperWhisperEngine
    engine = CrisperWhisperEngine()
    engine.load()
    out = {}
    for wav, audio, language in samples():
        t0 = time.perf_counter()
        text = engine.transcribe(audio, language=language).text
        out[wav.stem] = (text, (time.perf_counter() - t0) * 1000)
    return out, rss_gb()


def run_whisper_standard():
    """Whisper d'OpenAI, avec biais de vocabulaire via prompt_ids.

    C'est le mécanisme natif de Whisper : les termes sont placés après
    ``<|startofprev|>``, ce qui incline le décodeur sans forcer.
    """
    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    repo = "openai/whisper-large-v3-turbo"
    model = (WhisperForConditionalGeneration
             .from_pretrained(repo, dtype=torch.float16).to("mps").eval())
    processor = WhisperProcessor.from_pretrained(repo)
    prompt = processor.get_prompt_ids(", ".join(LEXICON), return_tensors="pt").to("mps")

    out = {}
    for wav, audio, language in samples():
        feats = processor.feature_extractor(audio, sampling_rate=16_000,
                                            return_tensors="pt")
        inputs = feats.input_features.to("mps", torch.float16)
        t0 = time.perf_counter()
        with torch.no_grad():
            ids = model.generate(inputs, language=language, task="transcribe",
                                 prompt_ids=prompt, max_new_tokens=200)
        torch.mps.synchronize()
        elapsed = (time.perf_counter() - t0) * 1000
        text = processor.batch_decode(ids, skip_special_tokens=True)[0]
        # Le prompt est réémis en tête de la sortie : on le retire.
        for marker in (", ".join(LEXICON), LEXICON[-1]):
            if marker in text:
                text = text.split(marker, 1)[-1]
        out[wav.stem] = (text.strip(), elapsed)
    del model
    gc.collect()
    return out, rss_gb()


def run_parakeet():
    """Parakeet TDT — transducteur NVIDIA, via MLX.

    Aucun mécanisme de biais exposé : c'est justement ce qu'on veut vérifier,
    puisque le vocabulaire technique est le cœur du besoin.
    """
    from parakeet_mlx import from_pretrained

    model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v3")
    out = {}
    for wav, audio, _ in samples():
        t0 = time.perf_counter()
        result = model.transcribe(str(wav))
        elapsed = (time.perf_counter() - t0) * 1000
        text = getattr(result, "text", str(result))
        out[wav.stem] = (text.strip(), elapsed)
    del model
    gc.collect()
    return out, rss_gb()


# --------------------------------------------------------------------------

def score(text: str, terms: list[str]) -> tuple[int, list[str]]:
    kept = [t for t in terms if t.lower() in text.lower()]
    return len(kept), [t for t in terms if t not in kept]


def main() -> None:
    engines = [
        ("CrisperWhisper turbo + lexique", run_crisper),
        ("Whisper large-v3-turbo + prompt", run_whisper_standard),
        ("Parakeet TDT 0.6b v3", run_parakeet),
    ]

    results = {}
    for name, runner in engines:
        print(f"\n▸ {name}")
        try:
            outputs, memory = runner()
            results[name] = (outputs, memory)
            total = sum(score(t, EXPECTED[k])[0] for k, (t, _) in outputs.items())
            possible = sum(len(v) for v in EXPECTED.values())
            latency = np.median([ms for _, ms in outputs.values()])
            print(f"  {total}/{possible} termes · {latency:.0f} ms médian · {memory:.1f} Go")
        except Exception as exc:
            print(f"  indisponible : {exc}")

    print(f"\n{'=' * 78}\nDÉTAIL PAR ÉCHANTILLON\n{'=' * 78}")
    for name, terms in EXPECTED.items():
        print(f"\n── {name}   [{', '.join(terms)}]")
        for engine, (outputs, _) in results.items():
            if name not in outputs:
                continue
            text, ms = outputs[name]
            kept, missing = score(text, terms)
            flag = "✓" if not missing else "✗ " + ",".join(missing)
            print(f"   {engine[:30]:32s} {kept}/{len(terms)} {flag}")
            print(f"      {text[:120]}")

    print(f"\n{'=' * 78}\nSYNTHÈSE\n{'=' * 78}")
    possible = sum(len(v) for v in EXPECTED.values())
    for name, (outputs, memory) in results.items():
        total = sum(score(t, EXPECTED[k])[0] for k, (t, _) in outputs.items())
        latency = np.median([ms for _, ms in outputs.values()])
        print(f"  {name:34s} {total:>3}/{possible}  "
              f"{latency:>6.0f} ms  {memory:>5.1f} Go")


if __name__ == "__main__":
    main()
