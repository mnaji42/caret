"""Choix de l'accélérateur, et de la précision qui va avec.

Écrit après une panne muette sur machine virtuelle. ``mps`` était écrit en
dur : sur un Mac c'est le bon choix, et c'est ce qui a caché le problème. Un
guest macOS a un GPU paravirtualisé mais pas Metal pour le calcul, donc
``.to("mps")`` levait au chargement du modèle, le service mourait avant
d'ouvrir son socket, et launchd le relançait toutes les trente secondes —
pendant que l'application annonçait « le modèle charge, réessayez dans un
instant ».

La règle est la même que côté application : la disponibilité se **mesure**,
elle ne se déduit pas. Et c'est exactement le genre de règle qui se recasse
sans bruit, puisque la machine de développement ne la met jamais en défaut.
"""

import torch

from sofler_engine.crisper import CrisperWhisperEngine, default_dtype, resolve_device


def test_auto_suit_ce_que_torch_repond(monkeypatch):
    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: False)
    assert resolve_device("auto") == "cpu"

    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: True)
    assert resolve_device("auto") == "mps"


def test_un_device_nomme_est_honore(monkeypatch):
    """Forcer reste possible — c'est ce qui permet de comparer les deux."""
    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: True)
    assert resolve_device("cpu") == "cpu"


def test_le_demi_flottant_ne_part_jamais_sur_le_processeur():
    """Plusieurs opérateurs de l'encodeur n'ont pas d'implémentation CPU en
    float16, et ceux qui en ont une sont plus lents qu'en float32. Corriger le
    device en laissant la précision derrière n'aurait rien réparé."""
    assert default_dtype("cpu") is torch.float32
    assert default_dtype("mps") is torch.float16


def test_le_moteur_resout_les_deux_a_la_construction(monkeypatch):
    """Avant tout chargement : `device` est lu par le `ping` du service, donc
    l'application doit pouvoir l'afficher sans qu'un modèle soit en mémoire."""
    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: False)
    engine = CrisperWhisperEngine()
    assert engine.device == "cpu"
    assert engine.dtype is torch.float32
