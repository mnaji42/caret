"""Moteur CrisperWhisper — inférence directe, sans le runtime de Nyra.

Le package officiel n'est pas utilisé ici pour trois raisons mesurées pendant
le POC :

  * son backend CTranslate2 n'a pas de wheel Apple Silicon (Linux x86_64
    uniquement), donc sur Mac il retombe sur PyTorch de toute façon ;
  * ses protections anti-hallucination importent ``ctranslate2`` en dur et
    sont donc inactives sur Mac ;
  * son pipeline ajoute ~1,5 s de surcoût par transcription, soit deux fois
    le coût du calcul lui-même.

On refait donc le strict nécessaire : mel, encodeur, boucle greedy. Mesuré à
~0,45 s sur M4 Pro pour une dictée courte, contre ~2,3 s via le package.
"""

from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field

import numpy as np
import torch

from caret_engine import prompt as prompt_mod

log = logging.getLogger(__name__)

SAMPLE_RATE = 16_000
MEL_FRAMES_PER_S = 100          # le feature extractor produit un hop de 10 ms
MAX_WINDOW_S = 30.0             # limite architecturale de Whisper

# En dessous de 15 s la troncature devient imprévisible : mesuré sur clips
# courts, un échantillon restait intact jusqu'à 4 s quand un autre se
# dégradait dès 10 s ("Tu as oublié" -> "State a oublié"). 15 s est le
# plancher où la sortie est restée strictement identique à la fenêtre pleine.
MIN_WINDOW_S = 15.0

# Marqueurs de disfluence émis en mode verbatim.
DISFLUENCY_RE = re.compile(
    r"\[(UM|UH|laughter|sniff|throatclearing|cough|sigh|breath|lipsmack|"
    r"yawn|noise|crying|fart|scream|sneeze)\]"
)
PROMPT_ARTIFACT_RE = re.compile(
    r"\[(verbatim|intended)_\d+\]|<htx>.*?<ehtx>|<ctx>.*?<ectx>|<vtx>.*?<evtx>",
    re.DOTALL,
)

DEFAULT_LEXICON = [
    "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
    "hook", "refactor", "merge", "commit", "endpoint", "dependencies",
    "pull request", "branch", "async", "await", "props", "state",
]


@dataclass
class Timings:
    mel_ms: float = 0.0
    encoder_ms: float = 0.0
    decoder_ms: float = 0.0

    @property
    def total_ms(self) -> float:
        return self.mel_ms + self.encoder_ms + self.decoder_ms


@dataclass
class Transcription:
    text: str
    mode: str
    language: str
    window_s: float
    tokens: int
    timings: Timings = field(default_factory=Timings)
    truncated: bool = False


class CrisperWhisperEngine:
    """Charge le modèle une fois, transcrit à la demande.

    Le modèle reste chaud : les ~8 s de chargement sont payées au démarrage du
    service, pas à chaque dictée.
    """

    def __init__(
        self,
        model_id: str = "nyralabs/CrisperWhisper2.0_turbo",
        device: str = "mps",
        dtype: torch.dtype = torch.float16,
    ) -> None:
        self.model_id = model_id
        self.device = device
        self.dtype = dtype
        self._model = None
        self._processor = None
        self._eos = -1

    # -- cycle de vie -------------------------------------------------

    def load(self) -> float:
        from transformers import WhisperForConditionalGeneration, WhisperProcessor

        t0 = time.perf_counter()
        self._model = (
            WhisperForConditionalGeneration
            .from_pretrained(self.model_id, dtype=self.dtype)
            .to(self.device)
            .eval()
        )
        self._processor = WhisperProcessor.from_pretrained(self.model_id)
        self._eos = self._processor.tokenizer.convert_tokens_to_ids("<|endoftext|>")
        elapsed = time.perf_counter() - t0
        log.info("modèle %s chargé en %.1fs sur %s", self.model_id, elapsed, self.device)
        self._warmup()
        return elapsed

    def _warmup(self) -> None:
        """Force la compilation des kernels Metal.

        Sans ça la première dictée réelle paie ~0,5 s de compilation. Trois
        passes suffisent à stabiliser les temps (mesuré pendant le POC).
        """
        silence = np.zeros(int(MIN_WINDOW_S * SAMPLE_RATE), dtype=np.float32)
        for _ in range(3):
            self.transcribe(silence)
        log.info("warmup terminé")

    @property
    def loaded(self) -> bool:
        return self._model is not None

    # -- inférence ----------------------------------------------------

    def _sync(self) -> None:
        if self.device == "mps":
            torch.mps.synchronize()
        elif self.device == "cuda":
            torch.cuda.synchronize()

    def _window_for(self, duration_s: float) -> tuple[float, bool]:
        """Fenêtre d'encodage à utiliser, et si l'audio a dû être coupé."""
        if duration_s > MAX_WINDOW_S:
            return MAX_WINDOW_S, True
        return max(MIN_WINDOW_S, min(duration_s + 1.0, MAX_WINDOW_S)), False

    def _encode(self, mel):
        """Encode un mel plus court que 30 s.

        WhisperEncoder impose trois contraintes cohérentes entre elles :
        un contrôle de longueur exacte, ``config.max_source_positions``, et
        ``embed_positions.num_embeddings`` par lequel il indexe les positions.
        Les trois sont abaissées ensemble, le temps de l'appel. Les positions
        conservées gardent leur indice d'origine — la sémantique temporelle
        est intacte.
        """
        enc = self._model.model.encoder
        n_pos = mel.shape[-1] // 2
        saved = (
            enc.config.max_source_positions,
            enc.embed_positions.num_embeddings,
            enc.embed_positions.weight,
        )
        if n_pos < saved[1]:
            enc.config.max_source_positions = n_pos
            enc.embed_positions.num_embeddings = n_pos
            enc.embed_positions.weight = torch.nn.Parameter(
                saved[2][:n_pos].clone(), requires_grad=False
            )
        try:
            with torch.no_grad():
                return enc(mel)
        finally:
            (enc.config.max_source_positions,
             enc.embed_positions.num_embeddings,
             enc.embed_positions.weight) = saved

    @torch.no_grad()
    def _decode(self, enc_out, prompt_ids: list[int], max_new: int) -> list[int]:
        """Décodage greedy avec cache KV.

        On n'utilise pas ``model.generate()`` : sur Whisper il réécrit le
        prompt du décodeur (tokens de langue forcés, logique longform) et
        écrase les tags CrisperWhisper, ce qui produit des sorties vides.
        """
        out: list[int] = []
        cur = torch.tensor([prompt_ids], device=self.device)
        past = None
        for _ in range(max_new):
            res = self._model(
                encoder_outputs=enc_out,
                decoder_input_ids=cur,
                past_key_values=past,
                use_cache=True,
            )
            past = res.past_key_values
            nxt = int(res.logits[0, -1].argmax())
            if nxt == self._eos:
                break
            out.append(nxt)
            cur = torch.tensor([[nxt]], device=self.device)
        return out

    def transcribe(
        self,
        audio: np.ndarray,
        *,
        mode: str = "intended",
        language: str = "fr",
        hotwords: list[str] | None = None,
        keep_disfluencies: bool = False,
        max_new_tokens: int = 256,
    ) -> Transcription:
        if not self.loaded:
            raise RuntimeError("moteur non chargé : appeler load() d'abord")

        audio = np.asarray(audio, dtype=np.float32)
        duration_s = len(audio) / SAMPLE_RATE
        window_s, truncated = self._window_for(duration_s)

        t0 = time.perf_counter()
        feats = self._processor.feature_extractor(
            audio, sampling_rate=SAMPLE_RATE, return_tensors="pt"
        )
        mel = feats.input_features[:, :, : int(window_s * MEL_FRAMES_PER_S)]
        mel = mel.to(self.device, self.dtype)
        self._sync()
        t_mel = time.perf_counter() - t0

        t0 = time.perf_counter()
        enc_out = self._encode(mel)
        self._sync()
        t_enc = time.perf_counter() - t0

        prompt_ids = prompt_mod.build(
            self._processor.tokenizer,
            mode=mode,
            language=language,
            hotwords=hotwords if hotwords is not None else DEFAULT_LEXICON,
        )

        t0 = time.perf_counter()
        tokens = self._decode(enc_out, prompt_ids, max_new_tokens)
        self._sync()
        t_dec = time.perf_counter() - t0

        raw = self._processor.tokenizer.decode(tokens, skip_special_tokens=True)
        text = self._clean(raw, keep_disfluencies=keep_disfluencies)

        return Transcription(
            text=text,
            mode=mode,
            language=language,
            window_s=window_s,
            tokens=len(tokens),
            truncated=truncated,
            timings=Timings(t_mel * 1000, t_enc * 1000, t_dec * 1000),
        )

    @staticmethod
    def _clean(text: str, *, keep_disfluencies: bool) -> str:
        text = PROMPT_ARTIFACT_RE.sub("", text)
        if not keep_disfluencies:
            text = DISFLUENCY_RE.sub("", text)
        return " ".join(text.split()).strip()
