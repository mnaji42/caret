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

from caspr_engine import crisper
from caspr_engine.crisper import CrisperWhisperEngine, default_dtype, resolve_device


def _metal(monkeypatch, *, present: bool):
    """Décrit la machine qu'on simule.

    Les tests ne doivent dépendre d'aucun GPU réel, sinon ils passeraient sur
    la machine de développement et nulle part ailleurs — soit exactement la
    cécité qu'ils existent pour corriger.
    """
    monkeypatch.setattr(torch.backends.mps, "is_available", lambda: present)


def test_auto_suit_ce_que_torch_repond(monkeypatch):
    _metal(monkeypatch, present=False)
    assert resolve_device("auto") == "cpu"

    _metal(monkeypatch, present=True)
    assert resolve_device("auto") == "mps"


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


def test_la_sonde_ne_leve_jamais(monkeypatch):
    """Elle tourne au chargement du modèle : une exception y coûterait le
    service entier, c'est-à-dire précisément la panne qu'elle prévient."""
    def explose(*_, **__):
        raise RuntimeError("Metal a disparu")

    monkeypatch.setattr(torch, "randn", explose)
    assert crisper.mps_linear_is_broken() is False


def test_le_defusionnement_ne_touche_que_metal_avec_biais():
    """Le contournement est un remplacement global de `F.linear` : il doit
    rendre exactement le noyau d'origine partout ailleurs, sinon on corrigerait
    une machine virtuelle en dégradant tous les vrais Mac."""
    import torch.nn.functional as F
    origine = F.linear
    try:
        crisper._linear_defusionne = False
        crisper.defuse_mps_linear()
        assert F.linear is not origine, "le remplaçant n'a pas été posé"

        g = torch.Generator().manual_seed(0)
        x = torch.randn(1, 8, 16, generator=g)
        poids = torch.randn(16, 16, generator=g)
        biais = torch.randn(16, generator=g)
        # Sur processeur, avec ou sans biais, le résultat doit être au bit près
        # celui du noyau d'origine.
        assert torch.equal(F.linear(x, poids, biais), origine(x, poids, biais))
        assert torch.equal(F.linear(x, poids, None), origine(x, poids, None))
    finally:
        F.linear = origine
        crisper._linear_defusionne = False


def test_le_defusionnement_est_idempotent():
    """La sonde peut être appelée à chaque chargement : empiler les remplaçants
    ajouterait une indirection par appel de couche, sur des millions d'appels."""
    import torch.nn.functional as F
    origine = F.linear
    try:
        crisper._linear_defusionne = False
        crisper.defuse_mps_linear()
        pose = F.linear
        crisper.defuse_mps_linear()
        assert F.linear is pose
    finally:
        F.linear = origine
        crisper._linear_defusionne = False
