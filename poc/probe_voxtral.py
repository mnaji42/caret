"""Ce qu'on peut demander à Voxtral, et ce qu'il en fait vraiment.

Voxtral n'est pas un ASR : c'est un modèle de langage qui entend. La voie
`apply_transcription_request` — celle du banc — n'en expose qu'une fraction,
la transcription pure. `apply_chat_template` permet de lui parler.

Ce script n'illustre pas cette capacité, il la met à l'épreuve sur les dictées
réelles où elle changerait quelque chose : la traduction involontaire, le
vocabulaire technique, la mise en forme. Une capacité annoncée par le vendeur
n'est pas une capacité mesurée.

Usage :
    poc/.venv/bin/python poc/probe_voxtral.py
    poc/.venv/bin/python poc/probe_voxtral.py --only langue
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

CORPUS = Path.home() / "Library/Application Support/Caspr/corpus"
REPO = "mistralai/Voxtral-Mini-3B-2507"
OUT = Path(__file__).parent / "probe-run.json"

# Les dictées choisies pour ce qu'elles mettent à l'épreuve, pas au hasard.
CASES = {
    # Français prononcé, « en » demandé : Voxtral l'a traduit au banc.
    "2026-08-15T18-58-20": "français dit, anglais demandé — a été traduit au banc",
    # Long passage technique, franglais dense.
    "2026-08-15T13-32-23": "franglais technique, 147 s",
    # Court, là où CrisperWhisper laisse fuir son lexique (« Effects les deux-mêmes »).
    "2026-08-16T01-08-30": "court, 4,3 s",
}

PROMPTS = {
    "brut": None,   # apply_transcription_request, la référence du banc
    "fidele": ("Transcribe the audio exactly as spoken, in the language actually "
               "spoken. Never translate. Output only the transcription."),
    "lexique": ("Transcribe the audio exactly as spoken, in the language actually "
                "spoken. Never translate. These technical terms may appear and "
                "must be spelled exactly like this when they do: useEffect, "
                "useState, component, React, Next.js, TypeScript, hook, refactor, "
                "merge, commit, endpoint, dependencies, branch, pull request, "
                "Caspr, CrisperWhisper, Voxtral, macOS, Swift. Do not insert any "
                "of these words if they were not spoken. Output only the "
                "transcription."),
    "redige": ("Transcribe the audio, then rewrite it as clean written French: "
               "remove hesitations and false starts, punctuate properly, keep "
               "every idea and every technical term exactly as spoken. Do not "
               "translate, do not summarise, do not add anything. Output only "
               "the final text."),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    import torch
    from transformers import AutoProcessor, VoxtralForConditionalGeneration

    rows = {json.loads(l)["id"]: json.loads(l)
            for l in (CORPUS / "sessions.jsonl").read_text().splitlines() if l.strip()}

    processor = AutoProcessor.from_pretrained(REPO)
    model = VoxtralForConditionalGeneration.from_pretrained(
        REPO, dtype=torch.bfloat16, device_map="mps")

    results = []
    for cid, why in CASES.items():
        row = rows.get(cid)
        if not row or not row.get("audioFile"):
            print(f"!! {cid} absent du corpus"); continue
        path = str(CORPUS / "audio" / row["audioFile"])
        lang = row.get("language", "fr")
        print(f"\n══ {cid}  {row['durationSeconds']:.1f}s  langue demandée « {lang} »"
              f"\n   {why}")

        for name, instruction in PROMPTS.items():
            if args.only and args.only != name:
                continue
            t = time.time()
            if instruction is None:
                inputs = processor.apply_transcription_request(
                    language=lang, audio=path, model_id=REPO)
            else:
                inputs = processor.apply_chat_template([{
                    "role": "user",
                    "content": [{"type": "audio", "path": path},
                                {"type": "text", "text": instruction}],
                }])
            inputs = inputs.to("mps", dtype=torch.bfloat16)
            with torch.no_grad():
                out = model.generate(**inputs, max_new_tokens=2048, do_sample=False)
            text = processor.batch_decode(
                out[:, inputs.input_ids.shape[1]:], skip_special_tokens=True)[0].strip()
            dt = time.time() - t
            results.append({"id": cid, "prompt": name, "text": text,
                            "latencyMs": round(dt * 1000, 1)})
            print(f"\n   ── {name}  ({dt:.1f}s)\n   {text[:400]}")

    OUT.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print(f"\n→ {OUT}")


if __name__ == "__main__":
    main()
