"""Construction du prompt décodeur CrisperWhisper.

CrisperWhisper conditionne son comportement par des tokens placés *avant*
``<|startoftranscript|>`` — pas via le mécanisme ``<|startofprev|>`` de Whisper.
La séquence complète est :

    [<mode>_1..5]  [<htx> hotwords <ehtx>]  <|sot|> <|lang|> <|transcribe|> <|notimestamps|>

Les cinq tags de mode sont émis en bloc : c'est un soft-prompt où plusieurs
tokens portent un seul signal, pas une échelle de fidélité. Il y a deux modes,
pas dix niveaux.

Ces tokens existent dans les poids open-weight (`<htx>` = 51895, `<ehtx>` =
51896 sur turbo), donc le conditionnement par vocabulaire fonctionne sans
passer par les modèles Pro de Nyra.
"""

from __future__ import annotations

MODES = ("verbatim", "intended")

HOTWORD_START = "<htx>"
HOTWORD_END = "<ehtx>"
CONTEXT_START = "<ctx>"
CONTEXT_END = "<ectx>"

TAG_COUNT = 5


def build(
    tokenizer,
    *,
    mode: str = "intended",
    language: str = "fr",
    hotwords: list[str] | None = None,
    context: str | None = None,
) -> list[int]:
    """Retourne la séquence de tokens à imposer au décodeur.

    L'ordre context-puis-hotwords reproduit celui de l'entraînement ; l'inverser
    place le modèle hors distribution.
    """
    if mode not in MODES:
        raise ValueError(f"mode inconnu : {mode!r}, attendu {MODES}")

    text = "".join(f"[{mode}_{i}]" for i in range(1, TAG_COUNT + 1))
    if context:
        text += f" {CONTEXT_START} {context} {CONTEXT_END}"
    if hotwords:
        text += f" {HOTWORD_START} {' '.join(hotwords)} {HOTWORD_END}"

    ids = tokenizer.encode(text, add_special_tokens=False)
    return ids + [
        tokenizer.convert_tokens_to_ids("<|startoftranscript|>"),
        tokenizer.convert_tokens_to_ids(f"<|{language}|>"),
        tokenizer.convert_tokens_to_ids("<|transcribe|>"),
        tokenizer.convert_tokens_to_ids("<|notimestamps|>"),
    ]
