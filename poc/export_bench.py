"""Rassemble les bancs en un seul fichier, lisible par quelqu'un d'autre.

Existe parce que le corpus de l'application et les bancs ont été confondus, et
que la confusion était prévisible : `sessions.jsonl` porte ce que l'application
a **inséré** au fil des mois — moteurs d'alors, versions d'alors, aucune
transcription Voxtral en lot — tandis que les `run-*.json` portent le corpus
**rejoué** par chaque moteur, à code figé et mémoire libre.

Donner le premier en croyant donner les seconds mène exactement où c'est allé :
un interlocuteur qui conclut que Mistral n'a que cinq mesures.

    engine/.venv/bin/python poc/export_bench.py
    → poc/benchmark-complet.json
"""
import json
from pathlib import Path

POC = Path(__file__).parent
CORPUS = Path.home() / "Library/Application Support/Caspr/corpus"

#: Les quatre passages retenus, et pourquoi ceux-là. Les fichiers
#: `voxtral-run.json` et `crisper-run.json` sont volontairement exclus : ils
#: viennent de la série tournée sous 9 Go de swap, qui coûtait 18 % de latence.
BANCS = {
    "crisperwhisper_lexique_defaut": ("run-crisper.json",
        "CrisperWhisper 2.0 turbo, PyTorch/MPS, DEFAULT_LEXICON actif "
        "(19 termes) — c'est ce que fait l'application aujourd'hui"),
    "crisperwhisper_sans_lexique": ("run-crisper-nolex.json",
        "Le même, hotwords=[] — lexique désactivé"),
    "voxtral_3b_mlx": ("run-voxtral3b.json",
        "Voxtral-Mini-3B-2507 bf16 sous MLX, language=fr, max_tokens=4096, "
        "transcription en lot"),
    "voxtral_realtime_flux": ("run-realtime.json",
        "Voxtral-Mini-4B-Realtime-2602 4-bit sous MLX, vrai streaming, "
        "morceaux d'une seconde, delay 480 ms"),
}


def main() -> None:
    runs = {}
    for cle, (nom, desc) in BANCS.items():
        f = POC / nom
        if not f.exists():
            continue
        d = json.loads(f.read_text())
        runs[cle] = {"description": desc, "modele": d.get("model"),
                     "lexique": d.get("lexicon", "DEFAULT_LEXICON"),
                     "resultats": {r["id"]: r for r in d["results"] if r.get("text")}}

    meta = {}
    for l in (CORPUS / "sessions.jsonl").read_text().splitlines():
        if l.strip():
            r = json.loads(l)
            meta[r["id"]] = r

    tous = sorted(set().union(*(set(v["resultats"]) for v in runs.values())))
    communs = sorted(set.intersection(*(set(v["resultats"]) for v in runs.values())))

    dictees = []
    for i in tous:
        m = meta.get(i, {})
        e = {"id": i,
             "dureeSecondes": round(m.get("durationSeconds", 0), 1),
             "langueDeclaree": m.get("language"),
             "transcritParTous": i in communs,
             "moteurs": {}}
        for cle, v in runs.items():
            r = v["resultats"].get(i)
            if r:
                e["moteurs"][cle] = {"texte": r["text"],
                                     "latenceMs": r.get("latencyMs"),
                                     "mots": len(r["text"].split())}
        dictees.append(e)

    sortie = {
        "aPropos": {
            "quoi": "Le même corpus de dictées réelles, rejoué par quatre "
                    "configurations de moteur. Un seul modèle chargé à la fois, "
                    "mémoire libre.",
            "ceQueCeNestPas": "Ce n'est pas `sessions.jsonl`, le corpus de "
                              "l'application : celui-là porte ce qui a été inséré "
                              "au fil des mois, par des moteurs d'alors, et ne "
                              "contient aucune transcription Voxtral en lot.",
            "pasDeVeriteTerrain": "Ces dictées n'ont jamais été retranscrites à "
                                  "la main. Il n'y a donc pas de référence, et un "
                                  "WER n'est pas calculable — comparer les "
                                  "moteurs entre eux est tout ce qui est possible.",
            "machine": "Apple M4 Pro, 48 Go, macOS 26.6",
            "dicteesTotal": len(tous),
            "dicteesTranscritesParTous": len(communs),
        },
        "moteurs": {k: {"description": v["description"], "modele": v["modele"],
                        "lexique": v["lexique"], "dictees": len(v["resultats"])}
                    for k, v in runs.items()},
        "dictees": dictees,
    }
    f = POC / "benchmark-complet.json"
    f.write_text(json.dumps(sortie, ensure_ascii=False, indent=1))
    print(f"{len(tous)} dictées ({len(communs)} communes) → {f}")
    print(f"  {f.stat().st_size/1e6:.1f} Mo")
    for k, v in sortie["moteurs"].items():
        print(f"  {k:32s} {v['dictees']:3d} dictées")


if __name__ == "__main__":
    main()
