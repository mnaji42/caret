"""Référence de performance du moteur — sert de point de comparaison.

Mesure ce qui compte pour une dictée, dans cet ordre :

  * **latence perçue** : du signal audio au texte, médiane sur plusieurs passes
  * **temps processeur** : proxy fiable de la consommation d'énergie, donc de
    l'autonomie. Un backend deux fois plus rapide qui brûle deux fois plus de
    CPU n'a rien gagné sur batterie.
  * **mémoire résidente** : ce que l'application occupe en permanence
  * **fidélité du texte** : une accélération qui dégrade la transcription
    n'est pas une accélération

    uv run python benchmark.py                       # backend courant
    uv run python benchmark.py --label coreml -o coreml.json
    uv run python benchmark.py --compare mps.json coreml.json
"""

from __future__ import annotations

import argparse
import json
import platform
import resource
import statistics
import time
from pathlib import Path

import numpy as np
import soundfile as sf

SAMPLES = Path(__file__).parent.parent / "poc" / "samples"

# Termes attendus par échantillon : c'est leur survie qui dit si un backend
# transcrit aussi bien, pas un score global qui noierait l'information.
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

REPEATS = 5


def cpu_seconds() -> float:
    usage = resource.getrusage(resource.RUSAGE_SELF)
    return usage.ru_utime + usage.ru_stime


def rss_gb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def measure(label: str) -> dict:
    from caspr_engine.crisper import CrisperWhisperEngine

    engine = CrisperWhisperEngine()
    load_s = engine.load()

    results = []
    for wav in sorted(SAMPLES.glob("*.wav")):
        audio, sr = sf.read(str(wav), dtype="float32")
        language = "en" if wav.stem.endswith("english") else "fr"

        latencies, cpu_costs = [], []
        text = ""
        for _ in range(REPEATS):
            cpu0, t0 = cpu_seconds(), time.perf_counter()
            out = engine.transcribe(audio, language=language)
            latencies.append(time.perf_counter() - t0)
            cpu_costs.append(cpu_seconds() - cpu0)
            text = out.text

        expected = EXPECTED.get(wav.stem, [])
        kept = [t for t in expected if t.lower() in text.lower()]

        results.append({
            "sample": wav.stem,
            "audio_s": round(len(audio) / sr, 1),
            "latency_ms": round(statistics.median(latencies) * 1000, 1),
            "cpu_ms": round(statistics.median(cpu_costs) * 1000, 1),
            "terms_kept": len(kept),
            "terms_total": len(expected),
            "text": text,
        })
        print(f"  {wav.stem:24s} {results[-1]['latency_ms']:7.0f} ms"
              f"  cpu {results[-1]['cpu_ms']:7.0f} ms"
              f"  termes {len(kept)}/{len(expected)}")

    return {
        "label": label,
        "machine": platform.machine(),
        "model": engine.model_id,
        "device": engine.device,
        "load_s": round(load_s, 1),
        "rss_gb": round(rss_gb(), 2),
        "median_latency_ms": round(statistics.median(r["latency_ms"] for r in results), 1),
        "total_cpu_ms": round(sum(r["cpu_ms"] for r in results), 1),
        "terms_kept": sum(r["terms_kept"] for r in results),
        "terms_total": sum(r["terms_total"] for r in results),
        "samples": results,
    }


def compare(before: Path, after: Path) -> None:
    a = json.loads(before.read_text())
    b = json.loads(after.read_text())

    def line(name: str, x, y, unit: str = "", lower_is_better: bool = True) -> str:
        if isinstance(x, (int, float)) and x:
            ratio = y / x
            verdict = ("×%.2f" % ratio)
            better = (ratio < 1) == lower_is_better
            mark = "✓" if better and abs(ratio - 1) > 0.02 else (
                "=" if abs(ratio - 1) <= 0.02 else "✗")
        else:
            verdict, mark = "", " "
        return f"  {name:22s} {x:>10}{unit} → {y:>10}{unit}  {verdict:>7} {mark}"

    print(f"\n{'=' * 74}")
    print(f"  {a['label']}  →  {b['label']}")
    print(f"{'=' * 74}")
    print(line("latence médiane", a["median_latency_ms"], b["median_latency_ms"], " ms"))
    print(line("temps processeur", a["total_cpu_ms"], b["total_cpu_ms"], " ms"))
    print(line("mémoire", a["rss_gb"], b["rss_gb"], " Go"))
    print(line("chargement", a["load_s"], b["load_s"], " s"))
    print(line("termes conservés", a["terms_kept"], b["terms_kept"], "", False))

    # Une transcription différente n'est pas forcément pire, mais elle doit
    # être signalée : c'est ce que masquerait un score agrégé.
    changed = [(x["sample"], x["text"], y["text"])
               for x, y in zip(a["samples"], b["samples"]) if x["text"] != y["text"]]
    if changed:
        print(f"\n  {len(changed)} transcription(s) modifiée(s) :")
        for name, old, new in changed:
            print(f"\n    {name}")
            print(f"      avant : {old[:110]}")
            print(f"      après : {new[:110]}")
    else:
        print("\n  Transcriptions identiques sur tous les échantillons.")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="pytorch-mps")
    ap.add_argument("-o", "--output", type=Path)
    ap.add_argument("--compare", nargs=2, type=Path, metavar=("AVANT", "APRÈS"))
    args = ap.parse_args()

    if args.compare:
        compare(*args.compare)
        return 0

    print(f"\nRéférence « {args.label} »\n{'-' * 74}")
    report = measure(args.label)
    print(f"\n  latence médiane   {report['median_latency_ms']:.0f} ms")
    print(f"  temps processeur  {report['total_cpu_ms']:.0f} ms au total")
    print(f"  mémoire           {report['rss_gb']:.2f} Go")
    print(f"  chargement        {report['load_s']:.1f} s")
    print(f"  termes conservés  {report['terms_kept']}/{report['terms_total']}")

    if args.output:
        args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False))
        print(f"\n  écrit dans {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
