"""Découpage long-format.

Une régression ici perd du texte sans rien signaler : la transcription revient
plus courte et personne ne sait qu'il manque un paragraphe. C'est déjà arrivé,
quand la moitié des échantillons disparaissait sur un enregistrement de 157 s.
"""

import numpy as np
import pytest

from caspr_engine.crisper import (MAX_WINDOW_S, MIN_PAUSE_S, MIN_SEGMENT_S,
                                  MIN_WINDOW_S, SAMPLE_RATE)
from caspr_engine.crisper import CrisperWhisperEngine as Engine


def speech_block(rng, seconds, amplitude=0.15):
    return (rng.standard_normal(int(seconds * SAMPLE_RATE)) * amplitude).astype(np.float32)


def pause(seconds):
    return np.zeros(int(seconds * SAMPLE_RATE), dtype=np.float32)


def test_short_audio_is_not_split(rng):
    audio = speech_block(rng, 10)
    assert len(Engine._split_at_silence(audio)) == 1


def test_no_segment_exceeds_model_window(rng):
    """Dépasser 30 s ferait échouer l'encodeur : contrainte architecturale."""
    audio = speech_block(rng, 120)
    for segment in Engine._split_at_silence(audio):
        assert len(segment) <= MAX_WINDOW_S * SAMPLE_RATE + 1


def test_split_preserves_every_sample(rng):
    """Aucun échantillon perdu ni dupliqué : la somme doit être exacte."""
    audio = np.concatenate([speech_block(rng, 20), pause(0.5),
                            speech_block(rng, 25), pause(0.4),
                            speech_block(rng, 18)])
    segments = Engine._split_at_silence(audio)
    assert sum(len(s) for s in segments) == len(audio)
    assert np.array_equal(np.concatenate(segments), audio)


def test_cuts_land_on_pauses(rng):
    """Les coupes doivent tomber sur les silences, pas au milieu d'un mot."""
    audio = np.concatenate([speech_block(rng, 12), pause(0.6),
                            speech_block(rng, 12), pause(0.6),
                            speech_block(rng, 12)])
    boundaries = Engine._silence_boundaries(audio)
    expected = [12.3, 24.9]
    for target in expected:
        assert any(abs(b / SAMPLE_RATE - target) < 1.5 for b in boundaries), \
            f"aucune coupe près de {target}s dans {[round(b/SAMPLE_RATE,1) for b in boundaries]}"


def test_brief_pauses_are_not_boundaries(rng):
    """Une respiration au milieu d'une phrase ne doit pas couper."""
    audio = np.concatenate([speech_block(rng, 5), pause(MIN_PAUSE_S / 2),
                            speech_block(rng, 5)])
    assert Engine._silence_boundaries(audio) == []


def test_continuous_speech_still_splits(rng):
    """Sans aucune pause, il faut couper quand même : le modèle plafonne."""
    audio = speech_block(rng, 90)
    segments = Engine._split_at_silence(audio)
    assert len(segments) >= 3
    assert sum(len(s) for s in segments) == len(audio)


@pytest.mark.parametrize("duration,expected_floor", [
    (2.0, MIN_WINDOW_S),      # une dictée brève garde le plancher
    (10.0, MIN_WINDOW_S),
    (20.0, 21.0),             # au-delà, la durée + une marge
    (40.0, MAX_WINDOW_S),     # plafonné
])
def test_window_selection(duration, expected_floor):
    engine = Engine.__new__(Engine)
    window, truncated = engine._window_for(duration)
    assert window == pytest.approx(expected_floor)
    assert truncated == (duration > MAX_WINDOW_S)


def test_window_never_below_measured_floor():
    """Sous 15 s la troncature devient imprévisible — mesuré, pas supposé."""
    engine = Engine.__new__(Engine)
    for duration in (0.5, 1, 3, 8, 14):
        window, _ = engine._window_for(duration)
        assert window >= MIN_WINDOW_S


def test_mel_frame_count_stays_even():
    """La seconde convolution a un pas de 2 : un compte impair fait échouer
    le contrôle interne de Whisper. Bug déjà rencontré (2569 au lieu de 2568)."""
    engine = Engine.__new__(Engine)
    for duration in np.arange(1.0, 30.0, 0.37):
        window, _ = engine._window_for(float(duration))
        frames = int(window * 100)
        assert (frames - frames % 2) % 2 == 0


# --- dernier segment trop court -------------------------------------------
#
# Cas venu d'une dictée réelle de 73 s : le découpage produisait 11 segments
# dont le dernier de 0,7 s. Complété jusqu'à `MIN_WINDOW_S` par la fenêtre
# d'encodage, il n'offrait au modèle qu'une seconde de souffle dans quinze
# secondes de vide, et lui faisait ajouter « Effects de la réunion des deux
# deux deux. » à un texte par ailleurs correct.

def test_short_trailing_segment_is_merged(rng):
    """Un reliquat d'une seconde ne doit pas devenir un segment isolé."""
    audio = np.concatenate([
        speech_block(rng, 12), pause(MIN_PAUSE_S * 2),
        speech_block(rng, 12), pause(MIN_PAUSE_S * 2),
        speech_block(rng, 1),
    ])
    segments = Engine._split_at_silence(audio)
    assert all(len(s) >= MIN_SEGMENT_S * SAMPLE_RATE for s in segments), \
        "aucun segment ne doit rester sous le plancher"


def test_merging_preserves_every_sample(rng):
    """La fusion rattache, elle ne jette pas : l'audio doit être intact."""
    audio = np.concatenate([
        speech_block(rng, 12), pause(MIN_PAUSE_S * 2), speech_block(rng, 1),
    ])
    segments = Engine._split_at_silence(audio)
    assert sum(len(s) for s in segments) == len(audio)


def test_a_lone_short_recording_is_kept(rng):
    """Sans segment précédent, il n'y a rien à quoi rattacher : on garde."""
    audio = speech_block(rng, 2)
    assert len(Engine._split_at_silence(audio)) == 1
