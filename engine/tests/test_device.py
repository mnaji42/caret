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

from sofler_engine import crisper
from sofler_engine.crisper import CrisperWhisperEngine, default_dtype, resolve_device


def _metal(monkeypatch, *, present: bool, correct: bool = True):
    """Décrit la machine qu'on simule.

    Les deux axes sont indépendants, et c'est tout le sujet : une machine peut
    avoir Metal et calculer faux. Les tests ne doivent dépendre d'aucun GPU
    réel, sinon ils passeraient ici et nulle part ailleurs — soit exactement la
    cécité qu'ils existent pour corriger.
    """
    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: present)
    monkeypatch.setattr(crisper, "mps_computes", lambda *_, **__: correct)


def test_auto_suit_ce_que_torch_repond(monkeypatch):
    _metal(monkeypatch, present=False)
    assert resolve_device("auto") == "cpu"

    _metal(monkeypatch, present=True)
    assert resolve_device("auto") == "mps"


def test_metal_present_mais_faux_repli_sur_le_processeur(monkeypatch):
    """Le cas qui n'a l'air de rien et ne se voit nulle part.

    Le backend existe, le modèle se charge, le service annonce « Prêt » et
    répond à chaque requête — avec une chaîne vide, toujours. Aucune exception,
    aucune trace. Un accélérateur qui rend du vide n'écrit jamais ; le
    processeur est lent, mais il écrit.
    """
    _metal(monkeypatch, present=True, correct=False)
    assert resolve_device("auto") == "cpu"


def test_un_device_nomme_est_honore(monkeypatch):
    """Forcer reste possible — c'est ce qui permet de comparer les deux."""
    _metal(monkeypatch, present=True)
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
    _metal(monkeypatch, present=False)
    engine = CrisperWhisperEngine()
    assert engine.device == "cpu"
    assert engine.dtype is torch.float32


def test_la_verification_ne_leve_jamais(monkeypatch):
    """Elle tourne au démarrage du service : une exception y coûterait le
    service entier, c'est-à-dire précisément la panne qu'elle prévient."""
    def explode(*_, **__):
        raise RuntimeError("Metal a disparu")

    monkeypatch.setattr(torch, "ones", explode)
    assert crisper.mps_computes() is False
