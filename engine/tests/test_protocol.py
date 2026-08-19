"""Protocole app ↔ moteur.

C'est le contrat qui permet de remplacer le backend sans toucher à
l'application. Une incompatibilité silencieuse ici — un cadrage décalé, une
conversion qui perd des bits — se manifesterait par de l'audio corrompu et
une transcription absurde, sans erreur.
"""

import os
import shutil
import socket
import tempfile
import struct
import threading

import numpy as np
import pytest

from caspr_engine import protocol


def test_pcm_roundtrip_preserves_signal():
    original = np.linspace(-1, 1, 4096).astype(np.float32)
    restored = protocol.pcm16_to_float32(protocol.float32_to_pcm16(original))
    # 16 bits : un pas vaut 1/32768, donc l'écart doit rester sous un pas.
    assert np.abs(restored - original).max() < 1e-4


def test_pcm_clips_out_of_range_values():
    loud = np.array([-3.0, 3.0], dtype=np.float32)
    restored = protocol.pcm16_to_float32(protocol.float32_to_pcm16(loud))
    assert restored.min() >= -1.0 and restored.max() <= 1.0


def test_pcm_is_little_endian_int16():
    """L'application Swift écrit du int16 petit-boutiste : tout écart ici
    produirait du bruit blanc côté moteur."""
    encoded = protocol.float32_to_pcm16(np.array([1.0], dtype=np.float32))
    assert len(encoded) == 2
    assert struct.unpack("<h", encoded)[0] == 32767


def test_empty_audio_roundtrip():
    assert protocol.pcm16_to_float32(
        protocol.float32_to_pcm16(np.array([], dtype=np.float32))).size == 0


@pytest.fixture
def short_socket_path():
    """Un socket Unix ne peut dépasser ~104 caractères de chemin sur macOS,
    et les répertoires temporaires de pytest sont bien plus longs."""
    directory = tempfile.mkdtemp(dir="/tmp")
    path = os.path.join(directory, "s")
    yield path
    shutil.rmtree(directory, ignore_errors=True)


def test_message_roundtrip_over_socket(short_socket_path):
    path = short_socket_path
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    server.listen(1)

    received = {}

    def serve():
        conn, _ = server.accept()
        with conn:
            header, payload = protocol.read_message(conn)
            received["header"] = header
            received["payload"] = payload
            protocol.write_message(conn, {"text": "réponse accentuée"})

    thread = threading.Thread(target=serve)
    thread.start()

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(str(path))
    audio = protocol.float32_to_pcm16(np.zeros(1000, dtype=np.float32))
    protocol.write_message(client, {"op": "transcribe", "mode": "intended"}, audio)
    reply, _ = protocol.read_message(client)
    client.close()
    thread.join(timeout=5)
    server.close()

    assert received["header"]["op"] == "transcribe"
    assert received["payload"] == audio
    assert reply["text"] == "réponse accentuée"


def test_large_payload_is_not_truncated(short_socket_path):
    """Dix minutes de dictée pèsent ~19 Mo : la lecture doit boucler jusqu'au
    bout plutôt que se contenter d'un premier recv."""
    path = short_socket_path
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    server.listen(1)
    sizes = {}

    def serve():
        conn, _ = server.accept()
        with conn:
            _, payload = protocol.read_message(conn)
            sizes["received"] = len(payload)
            protocol.write_message(conn, {"ok": True})

    thread = threading.Thread(target=serve)
    thread.start()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(str(path))
    big = protocol.float32_to_pcm16(np.zeros(16_000 * 60 * 3, dtype=np.float32))
    protocol.write_message(client, {"op": "transcribe"}, big)
    protocol.read_message(client)
    client.close()
    thread.join(timeout=30)
    server.close()

    assert sizes["received"] == len(big)


def test_truncated_stream_raises():
    a, b = socket.socketpair()
    a.sendall(struct.pack(">I", 500))     # annonce 500 octets, n'en envoie aucun
    a.close()
    with pytest.raises(ConnectionError):
        protocol.read_message(b)
    b.close()
