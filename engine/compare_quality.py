"""Compare décodage glouton / faisceau et turbo / large sur voix réelle.

Le but n'est pas de compter des mots mais de voir *quelles* erreurs chaque
configuration commet, sur les mêmes enregistrements.
"""
import sys, time
from pathlib import Path
import numpy as np, soundfile as sf
from caret_engine.crisper import CrisperWhisperEngine

SAMPLES = sorted((Path(__file__).parent.parent / "poc/samples").glob("*.wav"))

def run(model: str, beam: int):
    e = CrisperWhisperEngine(model_id=f"nyralabs/CrisperWhisper2.0_{model}", beam_size=beam)
    e.load()
    print(f"\n{'='*78}\n{model} · {'faisceau ' + str(beam) if beam > 1 else 'glouton'}\n{'='*78}")
    total = 0.0
    for wav in SAMPLES:
        audio, sr = sf.read(str(wav), dtype="float32")
        t0 = time.perf_counter()
        r = e.transcribe(audio, language="en" if "english" in wav.stem else "fr")
        dt = time.perf_counter() - t0
        total += dt
        print(f"  [{dt:5.2f}s] {wav.stem}")
        print(f"     {r.text[:150]}")
    print(f"\n  total {total:.1f}s")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else "turbo",
        int(sys.argv[2]) if len(sys.argv) > 2 else 5)
