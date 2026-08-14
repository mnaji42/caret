"""Détection de parole.

Ces seuils ont été calibrés contre des mesures, et une régression ici est
invisible à l'usage : l'utilisateur perd des dictées sans message d'erreur.
C'est exactement ce qui est arrivé une fois — un échantillon parfaitement
audible rejeté parce que le seuil frôlait les valeurs réelles.
"""

import numpy as np
import pytest

from caret_engine.crisper import CrisperWhisperEngine as Engine
from caret_engine.crisper import SPEECH_MODULATION_DB

SAMPLE_RATE = 16_000


def test_rejects_absolute_silence(silence):
    assert not Engine.has_speech(silence)


def test_rejects_white_noise(white_noise):
    """Un bruit fort ne doit pas passer : c'est le volume qui trompe."""
    assert not Engine.has_speech(white_noise)


def test_rejects_constant_hum():
    hum = (0.02 * np.sin(2 * np.pi * 50 * np.arange(SAMPLE_RATE * 3) / SAMPLE_RATE))
    assert not Engine.has_speech(hum.astype(np.float32))


def test_rejects_slowly_drifting_noise(rng):
    """Cas limite : un bruit modulé lentement imite mal la parole.

    C'est le pire des bruits mesurés (1,97 dB de dispersion), donc celui qui
    approche le plus le seuil.
    """
    base = rng.standard_normal(SAMPLE_RATE * 3) * 0.03
    drift = 1 + 0.3 * np.sin(np.linspace(0, 6, SAMPLE_RATE * 3))
    assert not Engine.has_speech((base * drift).astype(np.float32))


def test_rejects_isolated_click(silence):
    clicked = silence.copy()
    clicked[24000:24200] = 0.5
    assert not Engine.has_speech(clicked)


def test_accepts_speech_like_modulation(synthetic_speech):
    assert Engine.has_speech(synthetic_speech)


def test_accepts_quiet_speech(synthetic_speech):
    """Une voix faible reste de la parole : le critère porte sur la structure,
    pas sur le volume."""
    assert Engine.has_speech(synthetic_speech * 0.1)


def test_rejects_too_short_input():
    assert not Engine.has_speech(np.zeros(100, dtype=np.float32))


def test_threshold_sits_between_measured_populations():
    """Le seuil doit rester dans l'écart mesuré, à distance des deux bords.

    Bruits mesurés : jusqu'à ~2 dB. Parole réelle : à partir de ~8,4 dB.
    Le resserrer d'un côté ou de l'autre reproduirait la panne d'origine.
    """
    assert 2.5 < SPEECH_MODULATION_DB < 8.0
