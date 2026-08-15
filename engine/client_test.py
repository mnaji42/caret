"""Client de vérification du service — envoie un wav, affiche la réponse.

    uv run python client_test.py ../poc/samples/01-fr-dev.wav
    uv run python client_test.py --mode verbatim ../poc/samples/06-hesitations.wav
"""

from __future__ import annotations

import argparse
import socket
import sys
import time
from pathlib import Path

import soundfile as sf

from sofler_engine import protocol


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wav", nargs="*", type=Path)
    ap.add_argument("--mode", default="intended", choices=["intended", "verbatim"])
    ap.add_argument("--language", default="fr")
    ap.add_argument("--no-lexicon", action="store_true")
    ap.add_argument("--socket", type=Path, default=protocol.DEFAULT_SOCKET)
    args = ap.parse_args()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(str(args.socket))
    except (FileNotFoundError, ConnectionRefusedError):
        print(f"service injoignable sur {args.socket}\n"
              f"démarrer : uv run python -m sofler_engine.server", file=sys.stderr)
        return 1

    with sock:
        protocol.write_message(sock, {"op": "ping"})
        info, _ = protocol.read_message(sock)
        print(f"service : {info['model']} sur {info['device']}\n")

        for wav in args.wav:
            audio, sr = sf.read(str(wav), dtype="float32")
            if sr != protocol.SAMPLE_RATE:
                print(f"{wav.name} : {sr} Hz, attendu 16000 — ignoré")
                continue

            header = {
                "op": "transcribe",
                "mode": args.mode,
                "language": args.language,
            }
            if args.no_lexicon:
                header["hotwords"] = []

            t0 = time.perf_counter()
            protocol.write_message(sock, header, protocol.float32_to_pcm16(audio))
            reply, _ = protocol.read_message(sock)
            rtt = (time.perf_counter() - t0) * 1000

            t = reply.get("timings", {})
            print(f"── {wav.name}  ({len(audio) / sr:.1f}s)")
            print(f"   aller-retour {rtt:6.0f} ms   "
                  f"[mel {t.get('mel_ms', 0):.0f} | encodeur {t.get('encoder_ms', 0):.0f} "
                  f"| décodeur {t.get('decoder_ms', 0):.0f}]  fenêtre {reply.get('window_s')}s")
            print(f"   {reply.get('text', '')}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
