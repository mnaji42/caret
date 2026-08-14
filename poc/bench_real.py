"""Banc de test sur voix réelle — jalon J0.

references.md donne l'intention, pas la vérité terrain : les enregistrements
s'en écartent volontairement (reformulations, hésitations). On n'évalue donc
PAS par comparaison de chaînes. On vérifie une chose précise et vérifiable :
les termes techniques attendus survivent-ils, et sous quelle forme ?

Usage :
    uv run python bench_real.py
    uv run python bench_real.py --modes verbatim
    uv run python bench_real.py --model large
"""

from __future__ import annotations

import argparse
import re
import resource
import time
import unicodedata
from pathlib import Path

import soundfile as sf

SAMPLES = Path(__file__).parent / "samples"

# Termes techniques attendus par échantillon, tirés de references.md.
# Le nombre entre parenthèses n'est pas une note : c'est ce qu'on va chercher
# littéralement dans la sortie.
EXPECTED: dict[str, list[str]] = {
    "01-fr-dev": ["component", "React", "useEffect", "dependencies"],
    "02-franglais-500": ["merge", "feature", "endpoint", "200", "500"],
    "03-refactor": ["refactor", "hook", "component", "duplicated"],
    "04-nextjs": ["Next.js", "component", "useState", "useEffect", "server", "client"],
    "05-natural-long": ["service", "refactor", "component"],
    "06-hesitations": ["useEffect", "dependencies"],
    "07-english": ["refactor", "component", "branch", "dependencies", "implementation"],
    "08-franglais-natural": ["pull request", "comments", "component", "merge",
                             "implementation"],
}

# Lexique volontairement court : les tests TTS ont montré qu'une liste large
# dégrade le français ordinaire.
DEV_LEXICON = [
    "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
    "hook", "refactor", "merge", "commit", "endpoint", "dependencies",
    "pull request", "branch",
]

NUMERIC = re.compile(r"^\d+$")


def peak_rss_gb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def norm(text: str) -> str:
    return " ".join(unicodedata.normalize("NFC", text).split())


def find_term(term: str, text: str) -> str:
    """Classe un terme attendu : exact / casse / absent.

    Utilise des frontières de mots explicites — c'est ce qui manquait à la
    métrique précédente, où « main » matchait « demain ».
    """
    pattern = r"\b" + r"\s+".join(re.escape(w) for w in term.split()) + r"\b"
    if re.search(pattern, text):
        return "exact"
    if re.search(pattern, text, re.IGNORECASE):
        return "casse"
    return "absent"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="turbo")
    ap.add_argument("--modes", nargs="+", default=["verbatim", "intended"])
    args = ap.parse_args()

    from crisperwhisper import CrisperWhisperModel

    repo = f"nyralabs/CrisperWhisper2.0_{args.model}"
    print(f"\n{'=' * 84}\n{repo}  —  voix réelle\n{'=' * 84}")

    t0 = time.perf_counter()
    model = CrisperWhisperModel(repo, backend="transformers", device="mps",
                                compute_type="float16")
    load_s = time.perf_counter() - t0
    print(f"chargement {load_s:.1f}s | RSS {peak_rss_gb():.2f} Go\n")

    wavs = sorted(p for p in SAMPLES.glob("*.wav"))
    stats: dict[tuple[str, bool], dict] = {}
    warmed = False

    for wav in wavs:
        info = sf.info(str(wav))
        dur = info.frames / info.samplerate
        expected = EXPECTED.get(wav.stem, [])

        print(f"\n{'─' * 84}\n{wav.stem}   ({dur:.1f}s)")
        print(f"  attendu : {', '.join(expected)}")

        for use_hw in (False, True):
            for mode in args.modes:
                opts = dict(language="fr" if not wav.stem.endswith("english") else "en",
                            mode=mode,
                            hallucination_mitigation=False,
                            early_eot_recovery=False)
                if not warmed:
                    model.transcribe(str(wav), **opts)
                    warmed = True

                t0 = time.perf_counter()
                res = model.transcribe(str(wav),
                                       hotwords=DEV_LEXICON if use_hw else None,
                                       **opts)
                dt = time.perf_counter() - t0
                text = norm(res.text)

                verdicts = {t: find_term(t, text) for t in expected}
                ok = sum(1 for v in verdicts.values() if v == "exact")
                bad = [t for t, v in verdicts.items() if v == "absent"]
                case = [t for t, v in verdicts.items() if v == "casse"]

                key = (mode, use_hw)
                s = stats.setdefault(key, {"ok": 0, "tot": 0, "lat": [], "dur": []})
                s["ok"] += ok
                s["tot"] += len(expected)
                s["lat"].append(dt)
                s["dur"].append(dur)

                label = f"{mode:8s}{'+lex' if use_hw else '    '}"
                print(f"\n  [{label}] {dt:5.2f}s  rtf={dt / dur:4.2f}  "
                      f"termes {ok}/{len(expected)}")
                print(f"     {text}")
                if case:
                    print(f"     ~ casse : {', '.join(case)}")
                if bad:
                    print(f"     ✗ perdus : {', '.join(bad)}")

    print(f"\n{'=' * 84}\nSYNTHÈSE\n{'=' * 84}")
    for (mode, hw), s in sorted(stats.items()):
        lat = sum(s["lat"]) / len(s["lat"])
        rtf = sum(l / d for l, d in zip(s["lat"], s["dur"])) / len(s["lat"])
        label = f"{mode}{' + lexique' if hw else ''}"
        print(f"  {label:22s} termes {s['ok']:3d}/{s['tot']:<3d}  "
              f"latence moy {lat:5.2f}s  rtf {rtf:4.2f}")
    print(f"\n  Peak RSS {peak_rss_gb():.2f} Go | chargement {load_s:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
