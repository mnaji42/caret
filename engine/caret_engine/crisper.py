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

# Découpage long-format. Calibré contre des frontières connues : à 0,35 s on
# ne retrouvait que 2 coupes sur 7, à 0,20 s les 7. Les pauses de la parole
# spontanée sont bien plus brèves qu'on ne l'imagine.
MIN_PAUSE_S = 0.20
# Part de l'écart fond/voix au-dessus de laquelle on considère qu'il y a
# parole. Trop bas, les pauses passent inaperçues ; trop haut, chaque syllabe
# devient une frontière.
SILENCE_RATIO = 0.15
# Longueur minimale d'un segment : couper trop court multiplie les appels au
# modèle sans rien gagner.
MIN_SEGMENT_S = 5.0
# Progression minimale par fenêtre en long-format, pour ne jamais piétiner.
MIN_ADVANCE_S = 1.0
# Pas des tokens temporels de Whisper.
TIMESTAMP_STEP_S = 0.02
# Mots repris d'un segment à l'autre via <ctx>…<ectx>.
CONTEXT_WORDS = 12

# Marqueurs de disfluence émis en mode verbatim.
DISFLUENCY_RE = re.compile(
    r"\[(UM|UH|laughter|sniff|throatclearing|cough|sigh|breath|lipsmack|"
    r"yawn|noise|crying|fart|scream|sneeze)\]"
)
PROMPT_ARTIFACT_RE = re.compile(
    r"\[(verbatim|intended)_\d+\]|<htx>.*?<ehtx>|<ctx>.*?<ectx>|<vtx>.*?<evtx>",
    re.DOTALL,
)

# Termes ajoutés au fil des ratés constatés à l'usage : « chunk » ressortait
# en « chun-teint », « commit » en « commis ». Un mot n'a sa place ici que
# s'il a réellement échoué — une liste gonflée à titre préventif dilue le
# conditionnement.
DEFAULT_LEXICON = [
    # React / front
    "useEffect", "useState", "useMemo", "useRef", "component", "React",
    "Next.js", "TypeScript", "hook", "props", "state",
    # git / flux de travail
    "refactor", "merge", "commit", "rebase", "branch", "pull request",
    "review", "deploy", "build",
    # back / données
    "endpoint", "middleware", "dependencies", "async", "await", "API",
    "JSON", "query", "schema", "cache", "buffer",
    # vocabulaire du domaine
    "chunk", "chunking", "prompt", "token", "embedding", "latence",
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
    #: Dernier instant horodaté par le modèle, en secondes depuis le début de
    #: la fenêtre. Renseigné seulement quand les horodatages sont demandés ;
    #: c'est lui qui pilote l'avance en long-format.
    last_timestamp: float | None = None


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
        beam_size: int = 1,
    ) -> None:
        # Faisceau désactivé par défaut : mesuré sur voix réelle, il produit
        # un texte *strictement identique* au glouton pour 60 % de latence en
        # plus. Le paramètre reste exposé pour re-mesurer sur d'autres voix.
        self.beam_size = beam_size
        self.model_id = model_id
        self.device = device
        self.dtype = dtype
        self._model = None
        self._processor = None
        self._eos = -1
        self._timestamp_begin = -1

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
        tok = self._processor.tokenizer
        self._eos = tok.convert_tokens_to_ids("<|endoftext|>")
        # Premier token temporel : tout id au-dessus encode un instant.
        self._timestamp_begin = tok.convert_tokens_to_ids("<|0.00|>")
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
    def _decode_beam(self, enc_out, prompt_ids: list[int], max_new: int,
                     beam_size: int) -> list[int]:
        """Décodage par faisceau.

        Le décodage glouton choisit le token le plus probable à chaque pas sans
        jamais revenir dessus. Chaque choix est défendable localement mais la
        phrase produite peut être absurde : « en utilisant » ressort en « en un
        vivant », suite de tokens plausibles un à un, insensée mise bout à bout.
        Le faisceau garde plusieurs hypothèses et tranche sur le score de la
        séquence entière, ce qui rattrape précisément ce type d'erreur.

        Coût réel modeste ici : le décodage ne pèse que ~0,15 s sur une dictée
        courte, contre ~0,45 s pour l'encodeur qui, lui, ne tourne qu'une fois.
        """
        beams = enc_out.last_hidden_state.expand(beam_size, -1, -1).contiguous()
        expanded = type(enc_out)(last_hidden_state=beams)

        ids = torch.tensor([prompt_ids] * beam_size, device=self.device)
        # Seule la première hypothèse est active au départ : sans ça, les
        # beam_size copies identiques produiraient beam_size fois la même suite.
        scores = torch.full((beam_size,), float("-inf"), device=self.device)
        scores[0] = 0.0

        finished: list[tuple[float, list[int]]] = []
        sequences: list[list[int]] = [[] for _ in range(beam_size)]
        past = None
        cur = ids

        for step in range(max_new):
            out = self._model(encoder_outputs=expanded, decoder_input_ids=cur,
                              past_key_values=past, use_cache=True)
            past = out.past_key_values
            logprobs = torch.log_softmax(out.logits[:, -1].float(), dim=-1)

            total = scores.unsqueeze(1) + logprobs
            flat = total.view(-1)
            top_scores, top_flat = flat.topk(beam_size)
            beam_index = top_flat // logprobs.shape[-1]
            token_index = top_flat % logprobs.shape[-1]

            new_sequences: list[list[int]] = []
            keep: list[int] = []
            keep_scores: list[float] = []
            keep_tokens: list[int] = []

            for score, origin, token in zip(top_scores.tolist(),
                                            beam_index.tolist(),
                                            token_index.tolist()):
                seq = sequences[origin] + [token]
                if token == self._eos:
                    # Normaliser par la longueur, sinon les phrases courtes
                    # gagnent systématiquement : leur score cumule moins de
                    # termes négatifs.
                    finished.append((score / max(len(seq), 1), seq[:-1]))
                else:
                    new_sequences.append(seq)
                    keep.append(origin)
                    keep_scores.append(score)
                    keep_tokens.append(token)

            if not new_sequences or len(finished) >= beam_size:
                break

            # Recompléter le faisceau pour garder une forme de lot constante,
            # ce qu'exige la réorganisation du cache.
            while len(new_sequences) < beam_size:
                new_sequences.append(new_sequences[-1])
                keep.append(keep[-1])
                keep_scores.append(float("-inf"))
                keep_tokens.append(keep_tokens[-1])

            sequences = new_sequences
            scores = torch.tensor(keep_scores, device=self.device)
            past.reorder_cache(torch.tensor(keep, device=self.device))
            cur = torch.tensor([[t] for t in keep_tokens], device=self.device)

        if finished:
            return max(finished, key=lambda item: item[0])[1]
        return sequences[0] if sequences else []

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
        if len(audio) / SAMPLE_RATE > MAX_WINDOW_S:
            return self._transcribe_longform(
                audio, mode=mode, language=language, hotwords=hotwords,
                keep_disfluencies=keep_disfluencies, max_new_tokens=max_new_tokens)
        return self._transcribe_window(
            audio, mode=mode, language=language, hotwords=hotwords,
            keep_disfluencies=keep_disfluencies, max_new_tokens=max_new_tokens)

    def _transcribe_longform(
        self,
        audio: np.ndarray,
        **kwargs,
    ) -> Transcription:
        """Transcrit un audio plus long que la fenêtre de 30 s du modèle.

        Découper à l'aveugle ne marche pas : Whisper émet volontiers une fin de
        séquence sur un silence interne et abandonne le reste de sa fenêtre.
        Une fenêtre de 25 s contenant deux phrases séparées par une pause perd
        la seconde — mesuré, la moitié des échantillons disparaissait.

        On procède donc comme Whisper en long-format : décoder **avec**
        horodatages, lire le dernier instant réellement transcrit, et faire
        repartir la fenêtre suivante exactement de là. Un arrêt prématuré
        cesse d'être une perte : il devient simplement une fenêtre plus courte,
        et la suite est reprise au tour d'après.
        """
        segments = self._split_at_silence(audio)
        texts: list[str] = []
        timings = Timings()
        tokens = 0
        context: str | None = None

        for index, segment in enumerate(segments):
            part = self._transcribe_window(segment, context=context, **kwargs)
            if part.text:
                texts.append(part.text)
                # Contexte court : trop long, le modèle paraphrase ce qui
                # précède au lieu de poursuivre.
                context = " ".join(" ".join(texts).split()[-CONTEXT_WORDS:])
            timings.mel_ms += part.timings.mel_ms
            timings.encoder_ms += part.timings.encoder_ms
            timings.decoder_ms += part.timings.decoder_ms
            tokens += part.tokens
            log.debug("  segment %d/%d (%.1fs) : %d mots", index + 1,
                      len(segments), len(segment) / SAMPLE_RATE,
                      len(part.text.split()))

        log.info("longform : %.0fs en %d segments, %d mots",
                 len(audio) / SAMPLE_RATE, len(segments),
                 len(" ".join(texts).split()))

        return Transcription(
            text=" ".join(texts).strip(),
            mode=kwargs.get("mode", "intended"),
            language=kwargs.get("language", "fr"),
            window_s=MAX_WINDOW_S,
            tokens=tokens,
            truncated=False,
            timings=timings,
        )

    @staticmethod
    def _silence_boundaries(audio: np.ndarray) -> list[int]:
        """Indices d'échantillon au milieu de chaque pause détectée.

        Le seuil est relatif au niveau de la voix — un seuil absolu ne marche
        ni sur un micro de casque ni dans une pièce bruyante. On prend un
        centile bas de l'énergie comme référence de fond et on marque comme
        pause tout ce qui reste proche de ce fond assez longtemps.
        """
        frame = int(0.02 * SAMPLE_RATE)
        usable = (len(audio) // frame) * frame
        if usable < frame:
            return []

        frames = audio[:usable].reshape(-1, frame)
        energy = np.sqrt((frames.astype(np.float64) ** 2).mean(axis=1))

        floor = np.percentile(energy, 10)
        speech = np.percentile(energy, 90)
        if speech <= floor:
            return []                     # pas de parole distinguable du fond
        threshold = floor + SILENCE_RATIO * (speech - floor)

        quiet = energy < threshold
        min_frames = int(MIN_PAUSE_S / 0.02)

        boundaries: list[int] = []
        start = None
        for index, is_quiet in enumerate(quiet):
            if is_quiet and start is None:
                start = index
            elif not is_quiet and start is not None:
                if index - start >= min_frames:
                    boundaries.append(((start + index) // 2) * frame)
                start = None
        if start is not None and len(quiet) - start >= min_frames:
            boundaries.append(((start + len(quiet)) // 2) * frame)
        return boundaries

    @classmethod
    def _split_at_silence(cls, audio: np.ndarray) -> list[np.ndarray]:
        """Découpe l'audio en segments d'au plus 30 s, aux pauses réelles.

        Couper à intervalle fixe ne suffit pas : Whisper émet volontiers une
        fin de séquence sur un silence interne et abandonne le reste de la
        fenêtre. Un segment de 30 s contenant deux phrases séparées par une
        pause perd donc la seconde — constaté en test, un échantillon entier
        disparaissait de la transcription.

        On aligne donc les coupes sur les pauses de la parole : chaque segment
        correspond à un souffle continu, ce que le modèle sait transcrire d'un
        bout à l'autre. Sans pause exploitable (débit ininterrompu), on coupe
        à la limite de la fenêtre.
        """
        window = int(MAX_WINDOW_S * SAMPLE_RATE)
        if len(audio) <= window:
            return [audio]

        # Couper à *chaque* pause, pas seulement quand la fenêtre déborde :
        # c'est la pause à l'intérieur d'un segment qui déclenche l'arrêt
        # prématuré, donc en laisser une passer suffit à perdre la suite.
        cuts = [0, *cls._silence_boundaries(audio), len(audio)]

        segments: list[np.ndarray] = []
        start = cuts[0]
        for end in cuts[1:]:
            if end - start < MIN_SEGMENT_S * SAMPLE_RATE and end != len(audio):
                continue        # trop court : on prolonge jusqu'à la pause suivante
            while end - start > window:
                segments.append(audio[start:start + window])
                start += window
            if end > start:
                segments.append(audio[start:end])
            start = end

        return [s for s in segments if len(s) > 0]

    def _transcribe_window(
        self,
        audio: np.ndarray,
        *,
        mode: str = "intended",
        language: str = "fr",
        hotwords: list[str] | None = None,
        keep_disfluencies: bool = False,
        max_new_tokens: int = 256,
        context: str | None = None,
        timestamps: bool = False,
    ) -> Transcription:
        duration_s = len(audio) / SAMPLE_RATE
        window_s, truncated = self._window_for(duration_s)

        t0 = time.perf_counter()
        feats = self._processor.feature_extractor(
            audio, sampling_rate=SAMPLE_RATE, return_tensors="pt"
        )
        # La seconde convolution de l'encodeur a un pas de 2 : un nombre impair
        # de trames donne une longueur attendue qui ne retombe pas sur la
        # longueur fournie, et le contrôle interne de Whisper échoue. Les
        # fenêtres fixes de 15 s et 30 s tombaient juste par chance ; les
        # segments long-format, de durée variable, non.
        n_frames = int(window_s * MEL_FRAMES_PER_S)
        n_frames -= n_frames % 2
        mel = feats.input_features[:, :, :n_frames]
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
            context=context,
            timestamps=timestamps,
        )

        t0 = time.perf_counter()
        tokens = (self._decode_beam(enc_out, prompt_ids, max_new_tokens, self.beam_size)
                  if self.beam_size > 1
                  else self._decode(enc_out, prompt_ids, max_new_tokens))
        self._sync()
        t_dec = time.perf_counter() - t0

        last_ts = None
        if timestamps:
            stamps = [t for t in tokens if t >= self._timestamp_begin]
            if stamps:
                last_ts = (stamps[-1] - self._timestamp_begin) * TIMESTAMP_STEP_S
            tokens = [t for t in tokens if t < self._timestamp_begin]

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
            last_timestamp=last_ts,
        )

    @staticmethod
    def _clean(text: str, *, keep_disfluencies: bool) -> str:
        text = PROMPT_ARTIFACT_RE.sub("", text)
        if not keep_disfluencies:
            text = DISFLUENCY_RE.sub("", text)
        return " ".join(text.split()).strip()
