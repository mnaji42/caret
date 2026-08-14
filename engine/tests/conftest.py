"""Fixtures partagées.

Les tests sont séparés en deux familles :

* **rapides** — logique pure, aucun modèle chargé, quelques millisecondes.
  Ce sont eux qui figent les seuils calibrés à la main, et ils doivent tourner
  à chaque modification.
* **lents** (`-m slow`) — chargent CrisperWhisper et transcrivent réellement.
  Ils vérifient la non-régression de bout en bout, mais coûtent une minute.
"""

import numpy as np
import pytest

SAMPLE_RATE = 16_000


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: charge le modèle (lent)")


@pytest.fixture
def rng():
    return np.random.default_rng(0)


@pytest.fixture
def silence():
    return np.zeros(SAMPLE_RATE * 3, dtype=np.float32)


@pytest.fixture
def white_noise(rng):
    """Bruit stationnaire : volume élevé mais énergie plate."""
    return (rng.standard_normal(SAMPLE_RATE * 3) * 0.05).astype(np.float32)


@pytest.fixture
def synthetic_speech(rng):
    """Signal ayant la structure de la parole : alternance son/silence.

    Ce n'est pas de la voix, mais c'est ce que la détection observe —
    une énergie qui module fortement. Permet de tester sans dépendre
    d'enregistrements personnels, qui ne sont pas dans le dépôt.
    """
    frame = int(0.02 * SAMPLE_RATE)
    blocks = []
    for index in range(150):
        loud = (index % 8) < 5          # ~100 ms de parole, ~60 ms de pause
        amplitude = 0.15 if loud else 0.001
        blocks.append(rng.standard_normal(frame) * amplitude)
    return np.concatenate(blocks).astype(np.float32)
