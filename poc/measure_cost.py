"""Ce que coûte vraiment chaque moteur, disque et mémoire.

Le RSS seul ment sur Apple Silicon : la mémoire unifiée fait que les poids
poussés sur Metal n'apparaissent pas forcément dans le RSS du processus. Le
service CrisperWhisper affiche 0,11 Go avec 1,5 Go de poids chargés — ce n'est
pas une bonne nouvelle, c'est un instrument qui regarde ailleurs. On relève
donc les trois : RSS, mémoire allouée par le pilote Metal, et empreinte
physique vue par le système.

Usage :
    engine/.venv/bin/python poc/measure_cost.py crisper
    poc/.venv/bin/python poc/measure_cost.py voxtral
"""

from __future__ import annotations

import json
import os
import resource
import subprocess
import sys
import time
from pathlib import Path

CORPUS = Path.home() / "Library/Application Support/Caspr/corpus"


def footprint_mb() -> float:
    """Empreinte physique vue par macOS, en Mo — ce que dit le Moniteur."""
    try:
        out = subprocess.run(["/usr/bin/footprint", "-p", str(os.getpid())],
                             capture_output=True, text=True, timeout=30).stdout
        for line in out.splitlines():
            if "phys_footprint" in line.lower() or "Physical footprint" in line:
                for tok in line.replace("=", " ").split():
                    tok = tok.rstrip("MB").rstrip("K")
                    try:
                        return float(tok)
                    except ValueError:
                        continue
    except Exception:                                   # noqa: BLE001
        pass
    return 0.0


def report(tag: str, torch) -> dict:
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9
    mps_alloc = mps_drv = 0.0
    try:
        mps_alloc = torch.mps.current_allocated_memory() / 1e9
        mps_drv = torch.mps.driver_allocated_memory() / 1e9
    except Exception:                                   # noqa: BLE001
        pass
    d = {"étape": tag, "rssPicGo": round(rss, 2),
         "mpsAlloueGo": round(mps_alloc, 2), "mpsPiloteGo": round(mps_drv, 2)}
    print(f"  {tag:22s} RSS pic {rss:5.2f} Go | Metal alloué {mps_alloc:5.2f} Go "
          f"| Metal pilote {mps_drv:5.2f} Go")
    return d


def sample_audio(seconds: float = 20.0):
    import soundfile as sf
    rows = [json.loads(l) for l in (CORPUS / "sessions.jsonl").read_text().splitlines() if l.strip()]
    for r in rows:
        n = r.get("audioFile")
        if n and (CORPUS / "audio" / n).exists() and 15 < r["durationSeconds"] < 30:
            a, _ = sf.read(CORPUS / "audio" / n, dtype="float32")
            return (a.mean(axis=1) if a.ndim > 1 else a), str(CORPUS / "audio" / n)
    raise SystemExit("aucun échantillon de 15–30 s dans le corpus")


def main() -> None:
    which = sys.argv[1] if len(sys.argv) > 1 else "crisper"
    import torch
    steps = [report("avant chargement", torch)]
    audio, path = sample_audio()

    if which == "crisper":
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "engine"))
        from caspr_engine.crisper import CrisperWhisperEngine
        t = time.time()
        eng = CrisperWhisperEngine(model_id="nyralabs/CrisperWhisper2.0_turbo")
        eng.load()
        load_s = time.time() - t
        steps.append(report("modèle chargé", torch))
        t = time.time()
        out = eng.transcribe(audio, mode="intended", language="fr")
        infer_s = time.time() - t
        steps.append(report("après transcription", torch))
        text = out.text
    else:
        from transformers import AutoProcessor, VoxtralForConditionalGeneration
        repo = "mistralai/Voxtral-Mini-3B-2507"
        t = time.time()
        proc = AutoProcessor.from_pretrained(repo)
        model = VoxtralForConditionalGeneration.from_pretrained(
            repo, dtype=torch.bfloat16, device_map="mps")
        load_s = time.time() - t
        steps.append(report("modèle chargé", torch))
        t = time.time()
        inputs = proc.apply_transcription_request(language="fr", audio=path, model_id=repo)
        inputs = inputs.to("mps", dtype=torch.bfloat16)
        with torch.no_grad():
            o = model.generate(**inputs, max_new_tokens=2048, do_sample=False)
        text = proc.batch_decode(o[:, inputs.input_ids.shape[1]:],
                                 skip_special_tokens=True)[0]
        infer_s = time.time() - t
        steps.append(report("après transcription", torch))

    print(f"\n  chargement {load_s:.1f} s | inférence {infer_s:.1f} s")
    print(f"  empreinte système : {footprint_mb():.0f} Mo")
    print(f"  texte : {text[:70]!r}")
    Path(__file__).parent.joinpath(f"cost-{which}.json").write_text(
        json.dumps({"moteur": which, "chargementS": round(load_s, 1),
                    "inferenceS": round(infer_s, 1), "étapes": steps},
                   ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
