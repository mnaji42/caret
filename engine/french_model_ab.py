"""Un Whisper spécialisé français ferait-il mieux sur du franglais technique ?

Le français est une langue secondaire pour CrisperWhisper : ses jeux annotés
par des humains sont l'anglais et l'allemand, les huit autres langues de son
benchmark sont évaluées sur des données synthétiques. D'où l'idée de lui
substituer un modèle entraîné sur du français.

Ce que ce modèle ne peut pas faire, en revanche : il n'a aucun des tokens
CrisperWhisper, donc ni verbatim/intended ni conditionnement par lexique. La
question n'est donc pas « est-il meilleur en français » — il l'est
probablement — mais « son gain en français compense-t-il la perte du lexique
sur du franglais technique », qui est l'usage réel.
"""

from __future__ import annotations

import time
from pathlib import Path

import soundfile as sf
import torch

SAMPLES = Path(__file__).parent.parent / "poc" / "samples"
FRENCH_MODEL = "bofenghuang/whisper-large-v3-distil-fr-v0.2"

# Ce que la transcription doit préserver, par échantillon.
EXPECTED = {
    "01-fr-dev": ["component", "React", "useEffect", "dependencies"],
    "02-franglais-500": ["merge", "feature", "endpoint", "200", "500"],
    "03-refactor": ["refactor", "hook", "component", "duplicated"],
    "04-nextjs": ["Next.js", "component", "useState", "useEffect"],
    "05-natural-long": ["service", "refactor", "component"],
    "06-hesitations": ["useEffect", "dependencies"],
    "08-franglais-natural": ["pull request", "comments", "component"],
}


def run_french() -> dict[str, tuple[str, float]]:
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    model = (WhisperForConditionalGeneration
             .from_pretrained(FRENCH_MODEL, dtype=torch.float16)
             .to("mps").eval())
    processor = WhisperProcessor.from_pretrained(FRENCH_MODEL)

    out: dict[str, tuple[str, float]] = {}
    for wav in sorted(SAMPLES.glob("*.wav")):
        if wav.stem not in EXPECTED:
            continue
        audio, sr = sf.read(str(wav), dtype="float32")
        feats = processor.feature_extractor(audio, sampling_rate=sr,
                                            return_tensors="pt")
        inputs = feats.input_features.to("mps", torch.float16)

        t0 = time.perf_counter()
        with torch.no_grad():
            # Modèle standard : pas de tokens custom, generate() convient.
            ids = model.generate(inputs, language="fr", task="transcribe",
                                 max_new_tokens=200)
        torch.mps.synchronize()
        elapsed = (time.perf_counter() - t0) * 1000
        text = processor.batch_decode(ids, skip_special_tokens=True)[0].strip()
        out[wav.stem] = (text, elapsed)
    return out


def run_sofler() -> dict[str, tuple[str, float]]:
    from sofler_engine.crisper import CrisperWhisperEngine

    engine = CrisperWhisperEngine()
    engine.load()
    out: dict[str, tuple[str, float]] = {}
    for wav in sorted(SAMPLES.glob("*.wav")):
        if wav.stem not in EXPECTED:
            continue
        audio, _ = sf.read(str(wav), dtype="float32")
        t0 = time.perf_counter()
        result = engine.transcribe(audio, language="fr")
        out[wav.stem] = (result.text, (time.perf_counter() - t0) * 1000)
    return out


def score(text: str, terms: list[str]) -> tuple[int, list[str]]:
    kept = [t for t in terms if t.lower() in text.lower()]
    return len(kept), [t for t in terms if t not in kept]


def main() -> None:
    print("CrisperWhisper + lexique …")
    sofler = run_sofler()
    print(f"Whisper français ({FRENCH_MODEL.split('/')[-1]}) …")
    french = run_french()

    totals = {"sofler": 0, "french": 0, "max": 0}
    for name in sorted(sofler):
        terms = EXPECTED[name]
        c_text, c_ms = sofler[name]
        f_text, f_ms = french[name]
        c_score, c_missing = score(c_text, terms)
        f_score, f_missing = score(f_text, terms)
        totals["sofler"] += c_score
        totals["french"] += f_score
        totals["max"] += len(terms)

        print(f"\n── {name}")
        print(f"   Sofler   {c_score}/{len(terms)}  {c_ms:5.0f} ms  {c_text[:105]}")
        if c_missing:
            print(f"            perdus : {', '.join(c_missing)}")
        print(f"   Français {f_score}/{len(terms)}  {f_ms:5.0f} ms  {f_text[:105]}")
        if f_missing:
            print(f"            perdus : {', '.join(f_missing)}")

    print(f"\n{'=' * 74}")
    print(f"  Sofler (CrisperWhisper + lexique) : {totals['sofler']}/{totals['max']}")
    print(f"  Whisper français                 : {totals['french']}/{totals['max']}")


if __name__ == "__main__":
    main()
