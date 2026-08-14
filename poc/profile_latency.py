"""Décomposition de la latence + encodeur tronqué — jalon J1.

Deux questions :

  1. Où passe le temps ? (mel / encodeur / décodeur)
  2. Tronquer la fenêtre de 30 s à N s réduit-il la latence sans casser la
     transcription ?

MPS est asynchrone : sans torch.mps.synchronize() avant chaque relevé, on
mesure la mise en file d'attente et pas le calcul. Toutes les mesures ici
sont encadrées par une synchro explicite.
"""

from __future__ import annotations

import argparse
import time

import numpy as np
import soundfile as sf
import torch
from pathlib import Path
from transformers import WhisperForConditionalGeneration, WhisperProcessor

REPO = "nyralabs/CrisperWhisper2.0_turbo"
SAMPLES = Path(__file__).parent / ("samples_tts" if __import__("os").environ.get("TTS") else "samples")
DEVICE = "mps"
DTYPE = torch.float16

# 100 frames mel par seconde d'audio ; l'encodeur divise par 2 (conv stride 2).
MEL_FRAMES_PER_S = 100
ENC_FRAMES_PER_S = 50
WARMUP = 3

DEV_LEXICON = ["useEffect", "useState", "component", "React", "Next.js",
               "TypeScript", "hook", "refactor", "merge", "commit",
               "endpoint", "dependencies", "pull request", "branch"]


def sync() -> None:
    torch.mps.synchronize()


def build_prompt(processor, mode: str = "intended", lang: str = "fr",
                 hotwords: list[str] | None = None) -> list[int]:
    """Reproduit crisperwhisper.prompt.PromptBuilder._build()."""
    tok = processor.tokenizer
    text = "".join(f"[{mode}_{i}]" for i in range(1, 6))
    if hotwords:
        text += f" <htx> {' '.join(hotwords)} <ehtx>"
    ids = tok.encode(text, add_special_tokens=False)
    prefix = [
        tok.convert_tokens_to_ids("<|startoftranscript|>"),
        tok.convert_tokens_to_ids(f"<|{lang}|>"),
        tok.convert_tokens_to_ids("<|transcribe|>"),
        tok.convert_tokens_to_ids("<|notimestamps|>"),
    ]
    return ids + prefix


def encode(model, mel):
    """Encode un mel de longueur arbitraire.

    Deux verrous à lever pour descendre sous 30 s :
      - WhisperEncoder.forward vérifie que le mel fait exactement
        max_source_positions * 4 frames et lève sinon ;
      - il additionne la totalité de embed_positions.weight (1500 positions).

    On abaisse donc les deux de concert, le temps de l'appel. Les positions
    retirées sont les dernières : celles qu'on garde conservent leur indice
    d'origine, donc la sémantique temporelle est intacte.
    """
    enc = model.model.encoder
    n_pos = mel.shape[-1] // 2
    saved_max = enc.config.max_source_positions
    saved_w = enc.embed_positions.weight
    saved_n = enc.embed_positions.num_embeddings
    if n_pos < saved_n:
        # Trois verrous, pas deux : le forward indexe l'embedding via
        # arange(num_embeddings), qui ignore et max_source_positions et la
        # forme réelle du poids.
        enc.config.max_source_positions = n_pos
        enc.embed_positions.num_embeddings = n_pos
        enc.embed_positions.weight = torch.nn.Parameter(
            saved_w[:n_pos].clone(), requires_grad=False)
    try:
        with torch.no_grad():
            return enc(mel)
    finally:
        enc.config.max_source_positions = saved_max
        enc.embed_positions.num_embeddings = saved_n
        enc.embed_positions.weight = saved_w


@torch.no_grad()
def greedy_decode(model, enc_out, prompt_ids: list[int], eos: int,
                  max_new: int = 200) -> list[int]:
    """Décodage greedy explicite avec cache KV.

    On n'utilise pas model.generate() : sur Whisper il réécrit le prompt du
    décodeur (tokens de langue forcés, gestion longform) et écrase les tags
    CrisperWhisper — c'est ce qui produisait des sorties vides. Cette boucle
    est aussi le prototype de ce qu'il faudra écrire côté natif.
    """
    ids = torch.tensor([prompt_ids], device=DEVICE)
    out: list[int] = []
    past = None
    cur = ids
    for _ in range(max_new):
        res = model(encoder_outputs=enc_out, decoder_input_ids=cur,
                    past_key_values=past, use_cache=True)
        past = res.past_key_values
        nxt = int(res.logits[0, -1].argmax())
        if nxt == eos:
            break
        out.append(nxt)
        cur = torch.tensor([[nxt]], device=DEVICE)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows", type=float, nargs="+",
                    default=[30.0, 20.0, 15.0, 10.0])
    ap.add_argument("--repeats", type=int, default=3)
    args = ap.parse_args()

    print(f"\nChargement {REPO} …")
    t0 = time.perf_counter()
    model = WhisperForConditionalGeneration.from_pretrained(
        REPO, dtype=DTYPE).to(DEVICE).eval()
    processor = WhisperProcessor.from_pretrained(REPO)
    print(f"  {time.perf_counter() - t0:.1f}s\n")

    prompt = build_prompt(processor, "intended", "fr", DEV_LEXICON)
    eos = processor.tokenizer.convert_tokens_to_ids("<|endoftext|>")
    wavs = sorted(SAMPLES.glob("*.wav"))[:4]

    # ---------------------------------------------------------------
    # 1. Décomposition sur fenêtre pleine (30 s)
    # ---------------------------------------------------------------
    print("=" * 78)
    print("1. DÉCOMPOSITION DE LA LATENCE (fenêtre 30 s)")
    print("=" * 78)
    print(f"{'échantillon':<24}{'durée':>7}{'mel':>9}{'encodeur':>10}"
          f"{'décodeur':>10}{'total':>9}{'tokens':>8}")

    for wav in wavs:
        audio, sr = sf.read(str(wav), dtype="float32")
        dur = len(audio) / sr

        t_mel = t_enc = t_dec = 0.0
        n_tok = 0
        for r in range(args.repeats + WARMUP):
            t0 = time.perf_counter()
            feats = processor.feature_extractor(
                audio, sampling_rate=sr, return_tensors="pt")
            inp = feats.input_features.to(DEVICE, DTYPE)
            sync()
            d_mel = time.perf_counter() - t0

            t0 = time.perf_counter()
            enc_out = encode(model, inp)
            sync()
            d_enc = time.perf_counter() - t0

            t0 = time.perf_counter()
            toks = greedy_decode(model, enc_out, prompt, eos)
            sync()
            d_dec = time.perf_counter() - t0

            if r < WARMUP:  # rodage : kernels Metal non compilés
                continue
            t_mel += d_mel
            t_enc += d_enc
            t_dec += d_dec
            n_tok = len(toks)

        n = args.repeats
        total = (t_mel + t_enc + t_dec) / n
        print(f"{wav.stem:<24}{dur:>6.1f}s{t_mel / n:>8.3f}s{t_enc / n:>9.3f}s"
              f"{t_dec / n:>9.3f}s{total:>8.2f}s{n_tok:>8}")

    # ---------------------------------------------------------------
    # 2. Encodeur tronqué
    # ---------------------------------------------------------------
    print()
    print("=" * 78)
    print("2. ENCODEUR TRONQUÉ — latence et fidélité du texte")
    print("=" * 78)

    for wav in wavs:
        audio, sr = sf.read(str(wav), dtype="float32")
        dur = len(audio) / sr
        print(f"\n── {wav.stem}  ({dur:.1f}s)")

        feats = processor.feature_extractor(
            audio, sampling_rate=sr, return_tensors="pt")
        full_mel = feats.input_features.to(DEVICE, DTYPE)

        for win in args.windows:
            if win < dur:
                print(f"   {win:>4.0f}s  — fenêtre plus courte que l'audio, ignoré")
                continue
            n_frames = int(win * MEL_FRAMES_PER_S)
            mel = full_mel[:, :, :n_frames]

            best = float("inf")
            text = ""
            for r in range(args.repeats + WARMUP):
                t0 = time.perf_counter()
                enc_out = encode(model, mel)
                toks = greedy_decode(model, enc_out, prompt, eos)
                sync()
                dt = time.perf_counter() - t0
                if r < WARMUP:
                    continue
                best = min(best, dt)
                text = processor.tokenizer.decode(toks, skip_special_tokens=True)

            print(f"   {win:>4.0f}s  {best:>5.2f}s   {text.strip()[:130]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
