"""Banc de test CrisperWhisper 2.0 — jalon J0/J1.

Répond à trois questions, dans cet ordre d'importance :

  1. Le franglais dev survit-il ? (`useEffect` doit rester `useEffect`)
  2. Les hotwords <htx>...<ehtx> corrigent-ils ce que le mode seul rate ?
  3. Quelle latence sur M4 Pro, pour des phrases de 3-15 s ?

Usage :
    uv run python bench.py                      # turbo, fr, tous les samples
    uv run python bench.py --model large
    uv run python bench.py --no-hotwords
"""

from __future__ import annotations

import argparse
import gc
import re
import resource
import time
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

import soundfile as sf

from make_samples import DEV_HOTWORDS

SAMPLES_DIR = Path(__file__).parent / "samples"

# Les termes qui doivent survivre intacts. Casse comprise : « useEffect »
# transcrit « use effect » ou « Use Effect » est un échec.
TECH_TERMS = [
    "useEffect", "component", "TypeScript", "endpoint", "middleware",
    "rebase", "commit", "hook", "props", "main", "feature", "state",
]


def peak_rss_gb() -> float:
    # macOS renvoie ru_maxrss en octets (Linux en Kio).
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    return " ".join(text.split())


def term_hits(text: str) -> tuple[list[str], list[str]]:
    """Sépare les termes techniques trouvés à la casse exacte de ceux ratés.

    Un terme n'est « raté » que s'il apparaît sous une forme dégradée
    (casse changée, mot scindé) — pas s'il est simplement absent d'une
    phrase qui ne le contenait pas.
    """
    found, mangled = [], []
    for term in TECH_TERMS:
        if re.search(rf"\b{re.escape(term)}\b", text):
            found.append(term)
        else:
            # Détection de la forme dégradée : mêmes lettres, casse ou
            # espacement différents (useEffect -> « use effect », « useeffect »).
            loose = r"\s*".join(re.escape(c) for c in term.lower())
            if re.search(loose, text.lower()):
                mangled.append(term)
    return found, mangled


@dataclass
class Row:
    sample: str
    mode: str
    hotwords: bool
    text: str
    infer_s: float
    audio_s: float
    mangled: list[str] = field(default_factory=list)

    @property
    def rtf(self) -> float:
        return self.infer_s / self.audio_s if self.audio_s else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="turbo",
                    choices=["turbo", "large", "medium", "small"])
    ap.add_argument("--language", default="fr")
    ap.add_argument("--no-hotwords", action="store_true")
    args = ap.parse_args()

    from crisperwhisper import CrisperWhisperModel

    repo = f"nyralabs/CrisperWhisper2.0_{args.model}"
    print(f"\n{'=' * 78}\nModèle : {repo}\n{'=' * 78}")

    t0 = time.perf_counter()
    model = CrisperWhisperModel(repo, backend="transformers", device="mps",
                                compute_type="float16")
    load_s = time.perf_counter() - t0
    print(f"Chargement : {load_s:.2f} s   |   RSS après load : {peak_rss_gb():.2f} Go\n")

    refs = {}
    ref_file = SAMPLES_DIR / "references.tsv"
    if ref_file.exists():
        for line in ref_file.read_text(encoding="utf-8").splitlines():
            name, lang, text = line.split("\t")
            refs[name] = (lang, text)

    wavs = sorted(SAMPLES_DIR.glob("*.wav"))
    if not wavs:
        print(f"Aucun .wav dans {SAMPLES_DIR}. Lance d'abord make_samples.py.")
        return 1

    hotword_sets = [None] if args.no_hotwords else [None, DEV_HOTWORDS]
    rows: list[Row] = []

    for wav in wavs:
        info = sf.info(str(wav))
        audio_s = info.frames / info.samplerate
        lang = refs.get(wav.stem, (args.language, ""))[0]
        expected = refs.get(wav.stem, ("", ""))[1]

        print(f"\n── {wav.stem}  ({audio_s:.1f} s, langue={lang})")
        if expected:
            print(f"   attendu : {expected}")

        for hw in hotword_sets:
            for mode in ("verbatim", "intended"):
                # hallucination_mitigation / early_eot_recovery importent
                # ctranslate2 en dur, indisponible ici : bug de packaging côté
                # Nyra, l'extra [transformers] ne devrait pas en dépendre.
                opts = dict(language=lang, mode=mode,
                            hallucination_mitigation=False,
                            early_eot_recovery=False)

                # Première passe non chronométrée : évite de mesurer la
                # compilation des kernels Metal au lieu de l'inférence.
                if not rows:
                    model.transcribe(str(wav), **opts)

                t0 = time.perf_counter()
                res = model.transcribe(str(wav), hotwords=hw, **opts)
                dt = time.perf_counter() - t0

                text = normalize(res.text)
                _, mangled = term_hits(text)
                rows.append(Row(wav.stem, mode, hw is not None, text,
                                dt, audio_s, mangled))

                tag = f"{mode:8s} {'+hw' if hw else '   '}"
                flag = f"  ⚠ {','.join(mangled)}" if mangled else ""
                print(f"   {tag} {dt:5.2f}s  rtf={dt / audio_s:4.2f}  {text}{flag}")

        gc.collect()

    # ---- synthèse ----
    print(f"\n{'=' * 78}\nSYNTHÈSE\n{'=' * 78}")
    for hw in ([False] if args.no_hotwords else [False, True]):
        for mode in ("verbatim", "intended"):
            sel = [r for r in rows if r.hotwords == hw and r.mode == mode]
            if not sel:
                continue
            bad = sum(len(r.mangled) for r in sel)
            mean_rtf = sum(r.rtf for r in sel) / len(sel)
            mean_lat = sum(r.infer_s for r in sel) / len(sel)
            label = f"{mode}{' + hotwords' if hw else ''}"
            print(f"  {label:24s} latence moy {mean_lat:5.2f}s  rtf {mean_rtf:4.2f}"
                  f"  termes dégradés : {bad}")

    print(f"\n  Peak RSS : {peak_rss_gb():.2f} Go   |   chargement : {load_s:.2f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
