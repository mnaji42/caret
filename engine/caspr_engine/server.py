"""Service de transcription persistant.

Le modèle est chargé une fois au démarrage et reste chaud : chaque dictée ne
paie que l'inférence. C'est la moitié du gain de latence — l'autre venant de
la fenêtre d'encodage adaptative.

    uv run python -m caspr_engine.server
    uv run python -m caspr_engine.server --model nyralabs/CrisperWhisper2.0_large

Requêtes acceptées (champ ``op``) :

    transcribe   header {mode, language, hotwords?, keep_disfluencies?}
                 + PCM int16 mono 16 kHz
                 -> {text, timings, window_s, truncated}
    ping         -> {ready, model, device}
    shutdown     -> {ok}

    stream_start header {delay_ms?}                  -> {ok}
    stream_chunk + PCM int16                         -> {delta, text}
    stream_end   header {mode?, language?}           -> {text, tail_ms}

Le moteur se choisit au démarrage :

    uv run python -m caspr_engine.server --engine voxtral

L'application ne voit pas la différence — le protocole n'a jamais nommé de
modèle, et c'est ce qui rend l'échange possible sans toucher une ligne de Swift.
"""

from __future__ import annotations

import argparse
import contextlib
import logging
import os
import signal
import socket
import sys
import time
from pathlib import Path

from caspr_engine import protocol
from caspr_engine.crisper import SAMPLE_RATE, CrisperWhisperEngine

log = logging.getLogger("caspr.server")


class EngineServer:
    def __init__(self, engine: CrisperWhisperEngine, socket_path: Path) -> None:
        self.engine = engine
        self.socket_path = socket_path
        self._sock: socket.socket | None = None
        self._running = False

    def _bind(self) -> socket.socket:
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        # Un socket résiduel d'un process tué empêche le bind.
        with contextlib.suppress(FileNotFoundError):
            self.socket_path.unlink()
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(self.socket_path))
        # L'app est le seul client légitime : personne d'autre ne doit pouvoir
        # soumettre de l'audio ni lire les transcriptions.
        os.chmod(self.socket_path, 0o600)
        sock.listen(4)
        return sock

    def serve_forever(self) -> None:
        self._sock = self._bind()
        self._running = True
        log.info("à l'écoute sur %s", self.socket_path)

        while self._running:
            try:
                conn, _ = self._sock.accept()
            except OSError:
                break
            with conn:
                try:
                    self._handle(conn)
                except (ConnectionError, OSError) as exc:
                    log.warning("connexion interrompue : %s", exc)
                except Exception:
                    log.exception("erreur pendant le traitement")
                    with contextlib.suppress(OSError):
                        protocol.write_message(conn, {"error": "internal"})

    def _handle(self, conn: socket.socket) -> None:
        stream = None
        while True:
            try:
                header, payload = protocol.read_message(conn)
            except ConnectionError:
                return

            op = header.get("op", "transcribe")

            if op == "ping":
                protocol.write_message(conn, {
                    "ready": self.engine.loaded,
                    "model": self.engine.model_id,
                    "device": self.engine.device,
                })
                continue

            if op == "shutdown":
                protocol.write_message(conn, {"ok": True})
                self._running = False
                if self._sock:
                    self._sock.close()
                return

            # --- dictée au fil de la parole ---------------------------------
            #
            # Trois opérations plutôt qu'une, parce que la connexion vit le
            # temps d'une dictée : `stream_start` ouvre la session,
            # `stream_chunk` l'alimente et rend ce qui est apparu depuis le
            # morceau précédent, `stream_end` ferme et rend le texte complet.
            # L'état vit sur la connexion, pas sur le serveur : deux dictées
            # simultanées n'ont aucune raison de se marcher dessus, et un
            # client qui meurt en cours de route n'en laisse pas la trace.
            if op == "stream_start":
                if not hasattr(self.engine, "open_stream"):
                    protocol.write_message(conn, {
                        "error": f"{self.engine.model_id} ne sait pas travailler au fil"})
                    continue
                stream = self.engine.open_stream(delay_ms=header.get("delay_ms"))
                log.info("flux ouvert")
                protocol.write_message(conn, {"ok": True})
                continue

            if op == "stream_chunk":
                if stream is None:
                    protocol.write_message(conn, {"error": "aucun flux ouvert"})
                    continue
                delta = stream.feed(protocol.pcm16_to_float32(payload))
                protocol.write_message(conn, {"delta": delta, "text": stream.text})
                continue

            if op == "stream_end":
                if stream is None:
                    protocol.write_message(conn, {"error": "aucun flux ouvert"})
                    continue
                t0 = time.perf_counter()
                final = stream.close()
                wall = (time.perf_counter() - t0) * 1000
                log.info("flux fermé | %.0f ms de rattrapage | %d mots | %s",
                         wall, len(final.split()), final[:60])
                protocol.write_message(conn, {
                    "text": final, "mode": header.get("mode", "intended"),
                    "language": header.get("language", "fr"),
                    "tail_ms": round(wall, 1),
                })
                stream = None
                continue

            if op != "transcribe":
                protocol.write_message(conn, {"error": f"op inconnue : {op}"})
                continue

            audio = protocol.pcm16_to_float32(payload)
            if audio.size == 0:
                # Tracé, désormais. Ce chemin répondait « texte vide » sans
                # rien écrire nulle part : vu de l'application, une charge
                # audio perdue en route était indiscernable d'un modèle qui
                # n'a rien reconnu, et le journal ne permettait pas de
                # trancher entre les deux.
                log.warning("charge audio vide reçue (%d octets d'entête) — "
                            "rien à transcrire", len(payload))
                protocol.write_message(conn, {"text": "", "empty": True})
                continue

            t0 = time.perf_counter()
            result = self.engine.transcribe(
                audio,
                mode=header.get("mode", "intended"),
                language=header.get("language", "fr"),
                hotwords=header.get("hotwords"),
                keep_disfluencies=bool(header.get("keep_disfluencies", False)),
            )
            wall_ms = (time.perf_counter() - t0) * 1000

            # La durée reçue figure dans la ligne : sans elle, une sortie vide
            # laisse ouvert « le moteur n'a rien reconnu » contre « il n'a rien
            # reçu », et il faut une seconde machine pour en décider.
            log.info("%.1fs reçues | %.0f ms | fenêtre %.0fs | %d tokens | %s",
                     len(audio) / SAMPLE_RATE, wall_ms, result.window_s,
                     result.tokens, result.text[:60])

            protocol.write_message(conn, {
                "text": result.text,
                "mode": result.mode,
                "language": result.language,
                "window_s": result.window_s,
                "truncated": result.truncated,
                "tokens": result.tokens,
                "timings": {
                    "mel_ms": round(result.timings.mel_ms, 1),
                    "encoder_ms": round(result.timings.encoder_ms, 1),
                    "decoder_ms": round(result.timings.decoder_ms, 1),
                    "wall_ms": round(wall_ms, 1),
                },
            })

    def close(self) -> None:
        self._running = False
        if self._sock:
            with contextlib.suppress(OSError):
                self._sock.close()
        with contextlib.suppress(FileNotFoundError):
            self.socket_path.unlink()


def main() -> int:
    ap = argparse.ArgumentParser(description="Service de transcription Caspr")
    # Le moteur se choisit ici, pas dans le protocole : il se charge une fois
    # au démarrage et reste chaud, donc en changer suppose de redémarrer le
    # service de toute façon. L'application ne voit pas la différence — le
    # protocole n'a jamais nommé de modèle.
    ap.add_argument("--engine", default="crisper", choices=("crisper", "voxtral"),
                    help="moteur d'inférence (défaut : crisper)")
    ap.add_argument("--model", default=None,
                    help="identifiant du modèle ; défaut selon --engine")
    # « auto » mesure Metal au lieu de le supposer : sur une machine virtuelle
    # macOS il n'y en a pas, et « mps » écrit en dur y tuait le service au
    # chargement du modèle. Cf. caspr_engine.crisper.resolve_device.
    ap.add_argument("--device", default="auto")
    # Un socket distinct permet de faire tourner deux moteurs côte à côte. Ce
    # n'est pas une commodité de développement : l'application régénère
    # elle-même l'agent de lancement du moteur principal — cf.
    # `EngineInstall.writeAgent` — donc tout argument ajouté à la main y est
    # effacé à la première réconciliation. Un second service, sur son propre
    # socket et son propre agent, est le seul endroit où un moteur
    # expérimental survit.
    ap.add_argument("--socket", type=Path, default=protocol.DEFAULT_SOCKET)
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s  %(message)s",
        datefmt="%H:%M:%S",
    )

    if args.engine == "voxtral":
        from caspr_engine.voxtral import DEFAULT_MODEL, VoxtralEngine
        engine = VoxtralEngine(model_id=args.model or DEFAULT_MODEL,
                               device=args.device)
    else:
        engine = CrisperWhisperEngine(
            model_id=args.model or "nyralabs/CrisperWhisper2.0_turbo",
            device=args.device)
    # Le device dans la ligne qui précède le chargement : c'est le chargement
    # qui échoue quand il est mauvais, et le journal doit dire sur quoi il
    # portait avant de montrer la trace.
    log.info("chargement de %s sur %s …", engine.model_id, engine.device)
    engine.load()

    server = EngineServer(engine, args.socket)
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: server.close())

    try:
        server.serve_forever()
    finally:
        server.close()
        log.info("arrêté")
    return 0


if __name__ == "__main__":
    sys.exit(main())
