"""Ce qui se mesure sur un corpus sans vérité terrain.

Le corpus est de la parole spontanée, jamais retranscrite à la main. Il n'y a
donc pas de référence, et pas de WER possible. Fabriquer une référence à partir
d'un des moteurs reviendrait à le sacrer juge de ses concurrents.

Restent quatre signaux qui ne demandent aucun arbitre, et un cinquième qui en
demande un mais l'assume :

  * `repetition` — la part du texte occupée par sa plus longue boucle. Un
    décrochage de décodeur répète un motif court jusqu'à épuiser son budget ;
    le corpus en contient déjà (« And. You. You. You. » sur cent tokens).
  * `terms` — les termes techniques à l'orthographe **exacte**. La casse est
    tout l'objet : « useEffect » écrit « use effect » n'est pas le même mot
    pour qui le colle dans un éditeur.
  * `coverage` — la longueur rapportée au plus long des moteurs sur le *même*
    audio. Un moteur qui avale des mots le dit ici sans qu'on ait à lire.
  * `latency` — mesurée, quand le moteur l'a rapportée.
  * `agreement` — la similarité entre moteurs, qui sert à **trier** : les
    dictées où ils divergent le plus sont celles qui valent la lecture.
"""

from __future__ import annotations

import difflib
import re
import unicodedata

TERMS = [
    "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
    "JavaScript", "hook", "refactor", "merge", "commit", "endpoint",
    "dependencies", "pull request", "branch", "CrisperWhisper", "Whisper",
    "Caspr", "Swift", "SwiftUI", "Python", "macOS", "prompt", "token",
    "socket", "backend", "frontend", "build", "release", "debug", "data",
    "recording", "framework", "package", "API", "JSON", "workflow", "commit",
]


# Repris de `engine/caspr_engine/crisper.py`, constantes comprises. Ce n'est
# pas de la paresse : ces deux valeurs ont été calibrées sur ce corpus-ci et sur
# de la parole volontairement répétitive (« non non non », énumérations,
# bégaiements), dont aucune ne descend sous 0,41 quand le décrochage observé
# tombe à 0,09. Réinventer un seuil ici aurait produit un chiffre non comparable
# à celui que le moteur applique en production — et le mien, écrit d'abord,
# notait 0,04 un texte dont 42 % des mots sont « And. » ou « You. ».
LOOP_WINDOW = 32
MIN_DIVERSITY = 0.25


def repetition(text: str) -> float:
    """Part du texte prise dans une boucle, entre 0 et 1.

    On ne cherche pas *quel* motif se répète — un décrochage dont la période
    varie échappe à toute recherche de motif. On mesure la diversité du
    vocabulaire sur une fenêtre glissante : une boucle l'appauvrit quelle que
    soit sa forme, une parole répétitive légitime reste au-dessus du seuil.
    """
    words = text.split()
    if len(words) < LOOP_WINDOW:
        return 0.0
    flagged = 0
    for i in range(len(words) - LOOP_WINDOW + 1):
        window = words[i:i + LOOP_WINDOW]
        if len(set(window)) / LOOP_WINDOW < MIN_DIVERSITY:
            flagged += 1
    return round(flagged / (len(words) - LOOP_WINDOW + 1), 3)


def terms(text: str) -> dict[str, int]:
    """Termes techniques présents à l'orthographe et à la casse exactes."""
    found: dict[str, int] = {}
    for term in dict.fromkeys(TERMS):
        n = len(re.findall(rf"(?<![\w.]){re.escape(term)}(?![\w])", text))
        if n:
            found[term] = n
    return found


def _fold(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9 ]+", " ", s)


def similarity(a: str, b: str) -> float:
    """Similarité de deux transcriptions, accents et ponctuation ignorés.

    Sert à trier, pas à noter : deux moteurs qui s'accordent à 0,95 sur une
    dictée ne demandent pas de relecture, deux qui tombent à 0,60 si.
    """
    if not a or not b:
        return 0.0
    return round(difflib.SequenceMatcher(
        None, _fold(a).split(), _fold(b).split()).ratio(), 3)


def word_count(text: str) -> int:
    return len(text.split())
