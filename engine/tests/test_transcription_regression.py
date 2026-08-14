"""Non-régression de bout en bout, modèle chargé.

Ces tests coûtent une minute et exigent les poids : `pytest -m slow`.
Ils protègent contre ce que les tests unitaires ne voient pas — une
transcription qui se dégrade alors que chaque brique reste correcte, ce qui
est précisément arrivé en gonflant le lexique de 18 à 36 termes.

Ils s'exécutent sur les enregistrements de `poc/samples/`, absents du dépôt
car ce sont des données personnelles ; ils sont ignorés s'ils manquent.
"""

from pathlib import Path

import numpy as np
import pytest

SAMPLES = Path(__file__).parent.parent.parent / "poc" / "samples"
pytestmark = pytest.mark.slow

# Termes qui doivent survivre. Le modèle n'est pas tenu de produire le même
# texte au mot près — l'audio est de la parole spontanée — mais un terme
# technique qui disparaît est une régression.
EXPECTED = {
    "01-fr-dev": ["component", "React", "useEffect", "dependencies"],
    "02-franglais-500": ["merge", "feature", "endpoint", "200", "500"],
    "03-refactor": ["refactor", "hook", "component"],
    "04-nextjs": ["Next.js", "component", "useState", "useEffect"],
    "06-hesitations": ["useEffect", "dependencies"],
    "07-english": ["refactor", "component", "branch"],
}


@pytest.fixture(scope="module")
def engine():
    if not SAMPLES.exists():
        pytest.skip("enregistrements absents (données personnelles)")
    from caret_engine.crisper import CrisperWhisperEngine
    instance = CrisperWhisperEngine()
    instance.load()
    return instance


def load(name):
    import soundfile as sf
    path = SAMPLES / f"{name}.wav"
    if not path.exists():
        pytest.skip(f"{name} absent")
    audio, _ = sf.read(str(path), dtype="float32")
    return audio


@pytest.mark.parametrize("name,terms", EXPECTED.items())
def test_technical_terms_survive(engine, name, terms):
    language = "en" if name.endswith("english") else "fr"
    text = engine.transcribe(load(name), language=language).text
    missing = [t for t in terms if t.lower() not in text.lower()]
    assert not missing, f"perdus : {missing}\ntexte : {text}"


def test_intended_mode_writes_digits(engine):
    """« intended » rend « 200 », « verbatim » rend « deux cents ». C'est ce
    qui impose intended par défaut pour un développeur."""
    text = engine.transcribe(load("02-franglais-500"),
                             language="fr", mode="intended").text
    assert "200" in text and "500" in text


def test_verbatim_keeps_disfluencies(engine):
    """Les deux modes doivent rester distincts : c'est le différenciateur."""
    audio = load("06-hesitations")
    verbatim = engine.transcribe(audio, language="fr", mode="verbatim",
                                 keep_disfluencies=True).text
    intended = engine.transcribe(audio, language="fr", mode="intended").text
    assert verbatim != intended
    assert len(verbatim) > len(intended) * 0.8


def test_silence_produces_no_text(engine):
    """Whisper invente sur du silence : la détection doit l'intercepter."""
    assert engine.transcribe(np.zeros(16_000 * 5, dtype=np.float32)).text == ""


def test_long_audio_is_not_truncated(engine):
    """Au-delà de 30 s, le découpage doit tout couvrir. Une régression ici
    perdait la moitié du texte sans le signaler."""
    import soundfile as sf
    parts = [sf.read(str(p), dtype="float32")[0]
             for p in sorted(SAMPLES.glob("*.wav"))]
    if len(parts) < 4:
        pytest.skip("pas assez d'enregistrements")
    long_audio = np.concatenate(parts)
    result = engine.transcribe(long_audio, language="fr")
    assert not result.truncated
    # Un ordre de grandeur suffit : ~150 s de parole donnent bien plus de
    # 100 mots, et une troncature en produirait une poignée.
    assert len(result.text.split()) > 100, result.text


def test_lexicon_stays_short():
    """Mesuré : au-delà d'une vingtaine de termes, le modèle perd des
    virgules. Ce test empêche la liste de regonfler par ajouts successifs."""
    from caret_engine.crisper import DEFAULT_LEXICON
    assert len(DEFAULT_LEXICON) <= 22, (
        f"{len(DEFAULT_LEXICON)} termes — retirer avant d'ajouter")
