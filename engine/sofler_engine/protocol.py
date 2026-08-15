"""Protocole de la frontière app ↔ moteur.

C'est *la* couture du projet : tant qu'un moteur parle ce protocole, l'app
Swift n'a pas à savoir s'il tourne sous PyTorch, Core ML ou whisper.cpp.
Remplacer le moteur ne doit toucher aucune ligne côté app.

Trame, dans les deux sens :

    [4 octets  uint32 big-endian : longueur du JSON]
    [JSON utf-8]
    [charge utile binaire éventuelle, longueur annoncée dans le JSON]

L'audio circule en PCM int16 mono 16 kHz plutôt qu'en base64 : 15 s pèsent
480 Ko contre 1,3 Mo encodés, et la conversion coûte un memcpy.
"""

from __future__ import annotations

import json
import socket
import struct
from pathlib import Path
from typing import Any

import numpy as np

HEADER_STRUCT = struct.Struct(">I")
SAMPLE_RATE = 16_000

DEFAULT_SOCKET = Path.home() / "Library" / "Caches" / "sofler" / "engine.sock"


def pcm16_to_float32(raw: bytes) -> np.ndarray:
    """PCM int16 little-endian -> float32 dans [-1, 1]."""
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def float32_to_pcm16(samples: np.ndarray) -> bytes:
    clipped = np.clip(samples, -1.0, 1.0)
    return (clipped * 32767.0).astype("<i2").tobytes()


def _recv_exactly(sock: socket.socket, n: int) -> bytes:
    chunks: list[bytes] = []
    remaining = n
    while remaining:
        chunk = sock.recv(min(remaining, 1 << 20))
        if not chunk:
            raise ConnectionError(f"connexion fermée, {remaining} octets manquants")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def read_message(sock: socket.socket) -> tuple[dict[str, Any], bytes]:
    """Lit une trame. Retourne (header, charge utile)."""
    (length,) = HEADER_STRUCT.unpack(_recv_exactly(sock, HEADER_STRUCT.size))
    header = json.loads(_recv_exactly(sock, length))
    payload_len = int(header.get("payload_bytes", 0))
    payload = _recv_exactly(sock, payload_len) if payload_len else b""
    return header, payload


def write_message(sock: socket.socket, header: dict[str, Any],
                  payload: bytes = b"") -> None:
    header = {**header, "payload_bytes": len(payload)}
    blob = json.dumps(header, ensure_ascii=False).encode("utf-8")
    sock.sendall(HEADER_STRUCT.pack(len(blob)) + blob + payload)
