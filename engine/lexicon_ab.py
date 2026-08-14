"""Le lexique s'est-il retourné contre nous ?

Il est passé de 18 à 36 termes au fil des ratés constatés. Or on a mesuré que
plus la liste est longue, plus le modèle risque d'y piocher un mot sur un
passage ambigu. Cette expérience compare les configurations sur les mêmes
enregistrements réels.
"""
from pathlib import Path
import soundfile as sf
from caret_engine.crisper import CrisperWhisperEngine

ORIGINAL = [
    "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
    "hook", "refactor", "merge", "commit", "endpoint", "dependencies",
    "pull request", "branch", "async", "await", "props", "state",
]
CURRENT = None      # None = liste intégrée du moteur (36 termes)
MINIMAL = ["useEffect", "useState", "component", "React", "dependencies"]

CONFIGS = [("aucun", []), ("minimal (5)", MINIMAL),
           ("origine (18)", ORIGINAL), ("actuel (36)", CURRENT)]

engine = CrisperWhisperEngine()
engine.load()

samples = sorted(Path("../poc/samples").glob("*.wav"))
results = {}
for label, lexicon in CONFIGS:
    texts = []
    for wav in samples:
        audio, _ = sf.read(str(wav), dtype="float32")
        lang = "en" if wav.stem.endswith("english") else "fr"
        texts.append(engine.transcribe(audio, language=lang, hotwords=lexicon).text)
    results[label] = texts

base = results["actuel (36)"]
for label, texts in results.items():
    diffs = sum(1 for a, b in zip(texts, base) if a != b)
    print(f"  {label:14s} {diffs}/{len(samples)} transcriptions diffèrent de l'actuel")

print("\n" + "=" * 78)
for i, wav in enumerate(samples):
    variants = {label: texts[i] for label, texts in results.items()}
    if len(set(variants.values())) == 1:
        continue
    print(f"\n── {wav.stem}")
    for label, text in variants.items():
        print(f"   [{label:12s}] {text[:120]}")
