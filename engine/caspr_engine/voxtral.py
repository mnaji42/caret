"""Moteur Voxtral — même couture que CrisperWhisper, derrière le même socket.

Aucune ligne de Swift ne change pour l'employer. Le protocole app ↔ moteur ne
nomme aucun modèle : il envoie du PCM et un mode, il reçoit du texte. C'était
la promesse écrite dans `protocol.py` ; ce fichier est ce qui l'éprouve.

## Deux modèles, et ils ne se remplacent pas

`mistralai/Voxtral-Mini-3B-2507` a un encodeur audio **bidirectionnel** hérité
de Whisper : il doit avoir entendu tout le segment avant d'écrire le premier
mot. C'est le meilleur des deux sur un fichier, et le pire dans une dictée qui
attend.

`Voxtral-Mini-4B-Realtime` a un encodeur **causal** à fenêtre glissante : il
écrit au fil de la parole, avec un retard réglable. C'est celui qui a un sens
pour Caspr, et c'est le défaut ici.

## Ce que le mode veut dire ici

CrisperWhisper distingue `verbatim` et `intended` par des tags entraînés.
Voxtral n'a pas ça — c'est un modèle de langage, on le lui demande. La consigne
est donc **écrite en français**, et ce n'est pas un détail de style : mesuré sur
147 s de français, la même consigne rédigée en anglais fait sortir de l'anglais,
y compris quand elle dit « never translate ». La langue de la consigne décide
de la langue de sortie.

## Le lexique

Passé dans la consigne, avec l'ordre explicite de ne pas insérer un terme qui
n'a pas été prononcé — le défaut mesuré de `<htx>` chez CrisperWhisper, qui
glisse « Effects » dans le texte quand l'audio hésite.
"""

from __future__ import annotations

import logging
import time

import mlx.core as mx
import numpy as np

from caspr_engine.contract import SAMPLE_RATE, Timings, Transcription

log = logging.getLogger(__name__)

DEFAULT_MODEL = "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"

#: Consignes par mode, pour le jour où le 3B sera branché ici — lui les
#: honore, mesuré. En français, pour la raison ci-dessus.
CONSIGNES = {
    "intended": (
        "Transcris l'audio en français écrit correct : retire les hésitations "
        "et les faux départs, ponctue normalement, garde chaque idée et chaque "
        "terme technique tel qu'il a été prononcé. Ne traduis pas, ne résume "
        "pas, n'ajoute rien. N'écris que la transcription."
    ),
    "verbatim": (
        "Transcris l'audio exactement tel qu'il est prononcé, hésitations et "
        "répétitions comprises. Ne traduis pas, ne corrige pas, n'ajoute rien. "
        "N'écris que la transcription."
    ),
}

LEXIQUE_SUFFIXE = (
    " Ces termes peuvent apparaître et doivent alors être orthographiés "
    "exactement ainsi : {termes}. N'insère aucun de ces mots s'il n'a pas été "
    "prononcé."
)


class VoxtralEngine:
    """Interface identique à `CrisperWhisperEngine`, vue du serveur.

    Le serveur n'appelle que `load`, `loaded`, `device`, `model_id` et
    `transcribe`. Rien de plus n'est exposé ici : ce qui n'est pas dans le
    contrat n'a pas à exister, sans quoi le prochain moteur devra deviner ce
    qu'il doit imiter.
    """

    def __init__(self, model_id: str = DEFAULT_MODEL, device: str = "auto",
                 delay_ms: int = 480) -> None:
        self.model_id = model_id
        self.device = "mlx"
        self.delay_ms = delay_ms
        self._model = None

    @property
    def honours_modes(self) -> bool:
        """Ce modèle distingue-t-il texte nettoyé et mot à mot ?

        Faux pour le Realtime, et l'application doit pouvoir le savoir plutôt
        que de proposer un réglage sans effet — c'est la règle qu'elle applique
        déjà au lexique sous le moteur de macOS.
        """
        return False

    # -- cycle de vie -------------------------------------------------------

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def load(self) -> float:
        t0 = time.perf_counter()
        from mlx_audio.stt.generate import load_model
        self._model = load_model(self.model_id)
        elapsed = time.perf_counter() - t0
        log.info("modèle %s chargé en %.1fs sur MLX", self.model_id, elapsed)
        return elapsed

    # -- transcription ------------------------------------------------------

    def transcribe(
        self,
        audio: np.ndarray,
        *,
        mode: str = "intended",
        language: str = "fr",
        hotwords: list[str] | None = None,
        keep_disfluencies: bool = False,
        max_new_tokens: int = 2048,
    ) -> Transcription:
        if not self.loaded:
            raise RuntimeError("moteur non chargé : appeler load() d'abord")

        audio = np.asarray(audio, dtype=np.float32)
        duration = len(audio) / SAMPLE_RATE
        if duration < 0.3:
            # Sous ce seuil il n'y a rien à transcrire, et un modèle de langage
            # placé devant presque rien invente une phrase plausible — mesuré
            # sur le corpus : 1,3 s de silence a produit « Il est né à Paris,
            # en France. » Refuser coûte moins cher que d'insérer ça.
            log.info("audio trop court (%.2fs) — ignoré", duration)
            return Transcription(text="", mode=mode, language=language,
                                 window_s=duration, tokens=0)

        if mode == "verbatim" or hotwords:
            # Tracé une fois par appel plutôt que jamais : côté application le
            # sélecteur de mode existe, et sans cette ligne un réglage sans
            # effet ressemble à un réglage cassé.
            log.debug("mode %s et lexique ignorés : %s est un transcripteur pur",
                      mode, self.model_id)

        t0 = time.perf_counter()
        text = self._generate(audio, "", max_new_tokens)
        elapsed_ms = (time.perf_counter() - t0) * 1000

        return Transcription(
            text=text.strip(),
            mode=mode,
            language=language,
            window_s=duration,
            tokens=len(text.split()),
            timings=Timings(mel_ms=0.0, encoder_ms=0.0, decoder_ms=elapsed_ms),
            truncated=False,
        )

    def _generate(self, audio: np.ndarray, consigne: str, max_new_tokens: int) -> str:
        """Appelle mlx-audio.

        ## Pourquoi la consigne n'est pas passée ici

        Première version : `generate_transcription(..., prompt=consigne)`, avec
        un `except TypeError` pour retomber sur l'appel nu. Ça n'a jamais levé
        d'exception et ça n'a jamais rien appliqué non plus — la signature finit
        par `**kwargs`, qui avale n'importe quel argument sans rien dire. Les
        deux modes rendaient un texte identique au caractère près, et c'est ce
        qui l'a trahi.

        Le modèle Realtime **n'accepte pas de consigne** : c'est un
        transcripteur pur, `generate(audio, max_tokens, temperature, stream,
        transcription_delay_ms)`. Les modes et le lexique appartiennent au 3B,
        qui a un gabarit de conversation. Plutôt que de faire semblant, on le
        dit — un moteur qui ignore le mode en silence est pire qu'un moteur qui
        n'en a pas.
        """
        out = self._model.generate(
            mx.array(audio),
            max_tokens=max_new_tokens,
            temperature=0.0,
            transcription_delay_ms=self.delay_ms,
        )
        return getattr(out, "text", None) or str(out)
