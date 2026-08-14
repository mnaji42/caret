"""Test de faisabilité : l'encodeur CrisperWhisper sur le Neural Engine.

Question posée, et rien d'autre : l'ANE encode-t-il plus vite que le GPU, à
quel coût processeur, et la fenêtre variable de 15 s survit-elle au passage ?

L'encodeur seul suffit à décider : le profilage le donne à ~285 ms sur 426 ms
de latence totale. S'il n'accélère pas là, il n'accélérera nulle part.

    uv run python coreml_probe.py convert          # génère les .mlpackage
    uv run python coreml_probe.py bench            # compare MPS et ANE
"""

from __future__ import annotations

import argparse
import gc
import json
import statistics
import time
from pathlib import Path

import numpy as np
import torch

MODEL_ID = "nyralabs/CrisperWhisper2.0_turbo"
OUT_DIR = Path(__file__).parent / "coreml"
MELS = 128
# Les deux formes qui comptent : la fenêtre de production et la fenêtre pleine.
WINDOWS = {15: 1500, 30: 3000}
REPEATS = 12


class EncoderWrapper(torch.nn.Module):
    """Encodeur isolé, avec ses positions tronquées à la fenêtre visée.

    Core ML fige les formes : chaque fenêtre demande son propre modèle. On
    coupe donc l'embedding positionnel à la longueur voulue, exactement comme
    le fait le moteur PyTorch à l'exécution — les positions conservées gardent
    leur indice d'origine.
    """

    def __init__(self, encoder, frames: int):
        super().__init__()
        self.encoder = encoder
        positions = frames // 2
        if positions < encoder.embed_positions.num_embeddings:
            encoder.config.max_source_positions = positions
            encoder.embed_positions.num_embeddings = positions
            encoder.embed_positions.weight = torch.nn.Parameter(
                encoder.embed_positions.weight[:positions].clone(),
                requires_grad=False)

    def forward(self, mel):
        return self.encoder(mel).last_hidden_state


def load_encoder(frames: int):
    from transformers import WhisperForConditionalGeneration

    model = WhisperForConditionalGeneration.from_pretrained(
        MODEL_ID, dtype=torch.float32).eval()
    return EncoderWrapper(model.model.encoder, frames).eval()


def convert() -> None:
    import coremltools as ct

    OUT_DIR.mkdir(exist_ok=True)
    for seconds, frames in WINDOWS.items():
        target = OUT_DIR / f"encoder_{seconds}s.mlpackage"
        if target.exists():
            print(f"  {target.name} déjà présent")
            continue

        print(f"\n▸ fenêtre {seconds}s ({frames} trames)")
        wrapper = load_encoder(frames)
        example = torch.zeros(1, MELS, frames)

        t0 = time.perf_counter()
        traced = torch.jit.trace(wrapper, example, strict=False)
        print(f"  tracé en {time.perf_counter() - t0:.0f}s")

        t0 = time.perf_counter()
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="mel", shape=example.shape,
                                  dtype=np.float16)],
            outputs=[ct.TensorType(name="hidden", dtype=np.float16)],
            # float16 partout : l'ANE ne calcule pas autrement, et imposer du
            # float32 le renverrait sur le GPU sans le dire.
            compute_precision=ct.precision.FLOAT16,
            compute_units=ct.ComputeUnit.ALL,
            minimum_deployment_target=ct.target.iOS18,
        )
        mlmodel.save(str(target))
        print(f"  converti en {time.perf_counter() - t0:.0f}s → {target.name}")

        del wrapper, traced, mlmodel
        gc.collect()


def bench() -> None:
    import coremltools as ct

    report: dict[str, dict] = {}

    for seconds, frames in WINDOWS.items():
        mel_np = np.random.default_rng(0).standard_normal(
            (1, MELS, frames)).astype(np.float16) * 0.5
        print(f"\n{'=' * 70}\nFenêtre {seconds}s\n{'=' * 70}")
        entry: dict = {}

        # --- référence PyTorch / MPS ---
        wrapper = load_encoder(frames).to("mps").half()
        mel_mps = torch.from_numpy(mel_np.astype(np.float32)).to("mps").half()
        with torch.no_grad():
            for _ in range(3):
                reference = wrapper(mel_mps)
            torch.mps.synchronize()

            times = []
            for _ in range(REPEATS):
                t0 = time.perf_counter()
                out = wrapper(mel_mps)
                torch.mps.synchronize()
                times.append((time.perf_counter() - t0) * 1000)
        reference = reference.float().cpu().numpy()
        entry["mps_ms"] = round(statistics.median(times), 1)
        print(f"  PyTorch/MPS      {entry['mps_ms']:7.1f} ms")
        del wrapper, mel_mps
        gc.collect()

        # --- Core ML, sur chaque unité de calcul ---
        path = OUT_DIR / f"encoder_{seconds}s.mlpackage"
        if not path.exists():
            print(f"  {path.name} absent — lancer `convert` d'abord")
            continue

        for label, units in [("ANE (+CPU)", ct.ComputeUnit.CPU_AND_NE),
                             ("GPU (+CPU)", ct.ComputeUnit.CPU_AND_GPU),
                             ("auto", ct.ComputeUnit.ALL)]:
            try:
                model = ct.models.MLModel(str(path), compute_units=units)
            except Exception as exc:
                print(f"  {label:16s} indisponible : {exc}")
                continue

            for _ in range(3):
                result = model.predict({"mel": mel_np})
            times = []
            for _ in range(REPEATS):
                t0 = time.perf_counter()
                result = model.predict({"mel": mel_np})
                times.append((time.perf_counter() - t0) * 1000)

            produced = np.asarray(next(iter(result.values())), dtype=np.float32)
            # Écart relatif à la référence : une accélération qui change la
            # sortie n'est pas une accélération.
            delta = float(np.abs(produced - reference).max())
            scale = float(np.abs(reference).max()) or 1.0
            median = round(statistics.median(times), 1)
            entry[label] = median
            entry[f"{label}_delta"] = round(delta / scale, 5)
            print(f"  Core ML {label:12s} {median:7.1f} ms"
                  f"   écart max {delta / scale:.2%}")
            del model
            gc.collect()

        report[f"{seconds}s"] = entry

    out = OUT_DIR / "probe.json"
    out.write_text(json.dumps(report, indent=2))
    print(f"\n  écrit dans {out}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["convert", "bench"])
    args = ap.parse_args()
    convert() if args.action == "convert" else bench()
