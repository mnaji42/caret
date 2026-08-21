"""Mesurer la qualité du texte, pas sa ressemblance à un autre texte.

L'accord mot à mot du premier banc répondait à « ces deux moteurs disent-ils la
même chose », ce qui n'est pas la question posée. Deux transcriptions peuvent
s'accorder à 0,94 et l'une être lisible, l'autre hachée — c'est même le cas le
plus fréquent, puisque la ponctuation ne pèse presque rien dans une comparaison
de mots.

Les défauts relevés ici sont nommables, vérifiables à l'œil sur un exemple, et
choisis parce qu'ils abîment un texte qu'on va coller dans un éditeur :

  * `points_baladeurs` — un point suivi d'une minuscule. « Et puis voilà. et
    aussi » n'est pas une phrase, c'est une coupure au mauvais endroit. C'est
    le défaut que Mehdi a repéré à l'œil sur CrisperWhisper.
  * `fragments` — une « phrase » de trois mots ou moins coincée entre deux
    longues. « Diagnostic. » seul sur sa ligne vient d'un point de trop.
  * `bafouillages` — un même mot ou groupe répété d'affilée. Distinct des
    boucles du décodeur : ici c'est court, et ça survit au nettoyage.
  * `apostrophes_mixtes` — l'apostrophe droite et la courbe dans le même texte.
    Invisible en lecture, pénible à l'usage : une recherche sur « c'est » ne
    trouve pas « c’est ».
  * `phrase_moyenne` — la longueur moyenne d'une phrase. Trop courte, le texte
    est haché ; c'est la trace d'une ponctuation posée au hasard.
"""

from __future__ import annotations

import re
import statistics

MINUSCULE = "a-zà-öø-ÿ"
POINT_BALADEUR = re.compile(rf"[{MINUSCULE}]\.\s+[{MINUSCULE}]")
FIN_PHRASE = re.compile(r"(?<=[.!?])\s+")
MOT = re.compile(rf"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)?")


def points_baladeurs(text: str) -> int:
    """Points suivis d'une minuscule — une coupure au mauvais endroit."""
    return len(POINT_BALADEUR.findall(text))


def phrases(text: str) -> list[str]:
    return [p.strip() for p in FIN_PHRASE.split(text) if p.strip()]


def fragments(text: str) -> int:
    """Phrases de trois mots ou moins entourées de phrases longues.

    Bornée aux textes d'au moins quatre phrases : « D'accord. » seul est une
    transcription juste, pas un fragment.
    """
    ph = phrases(text)
    if len(ph) < 4:
        return 0
    longs = [len(p.split()) for p in ph]
    n = 0
    for i in range(1, len(ph) - 1):
        if longs[i] <= 3 and longs[i - 1] > 6 and longs[i + 1] > 6:
            n += 1
    return n


def bafouillages(text: str) -> int:
    """Mot ou groupe de deux mots répété d'affilée, casse ignorée."""
    w = [m.group().lower() for m in MOT.finditer(text)]
    n = 0
    for i in range(len(w) - 1):
        if w[i] == w[i + 1]:
            n += 1
    for i in range(len(w) - 3):
        if w[i:i + 2] == w[i + 2:i + 4]:
            n += 1
    return n


def apostrophes_mixtes(text: str) -> bool:
    return "'" in text and "’" in text


def phrase_moyenne(text: str) -> float:
    ph = phrases(text)
    if not ph:
        return 0.0
    return round(statistics.mean(len(p.split()) for p in ph), 1)


def analyse(text: str) -> dict:
    mots = len(text.split())
    return {
        "mots": mots,
        "pointsBaladeurs": points_baladeurs(text),
        "fragments": fragments(text),
        "bafouillages": bafouillages(text),
        "apostrophesMixtes": apostrophes_mixtes(text),
        "phraseMoyenne": phrase_moyenne(text),
        "phrases": len(phrases(text)),
    }
