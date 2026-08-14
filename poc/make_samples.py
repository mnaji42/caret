"""Génère des échantillons de test via la synthèse vocale macOS.

Proxy imparfait mais utile pour dégrossir : une voix FR prononce les termes
techniques anglais « à la française », ce qui rend le test PLUS dur que la
réalité (un dev prononce useEffect à l'anglaise). Test conservateur donc.
À remplacer par de vrais enregistrements dès que possible.
"""

import subprocess
import sys
from pathlib import Path

SAMPLES = {
    # --- franglais dev : le coeur du test ---
    "fr_dev_1": ("fr", "Tu as oublié les dépendances dans le useEffect."),
    "fr_dev_2": ("fr", "Je veux modifier le component pour qu'il utilise un state local."),
    "fr_dev_3": ("fr", "Le endpoint renvoie une erreur 500, il faut checker les logs du middleware."),
    "fr_dev_4": ("fr", "Merge la branche feature dans main et fais un rebase avant de commit."),
    "fr_dev_5": ("fr", "Il faut refactorer ce hook, TypeScript se plaint du typage des props."),
    # --- anglais pur : contrôle ---
    "en_dev_1": ("en", "The build failed because the dependency array is missing in the useEffect hook."),
    # --- hésitations : test verbatim vs intended ---
    "fr_disfl_1": ("fr", "Euh donc je, je pense que, enfin, le composant devrait être refactoré."),
    # --- français pur : contrôle ---
    "fr_pure_1": ("fr", "Je voudrais reporter la réunion de demain matin à la semaine prochaine."),
}

# Lexique injecté via <htx>...<ehtx> — le mécanisme de biais entraîné du modèle.
DEV_HOTWORDS = [
    "useEffect", "component", "TypeScript", "endpoint", "middleware",
    "rebase", "commit", "refactor", "hook", "npm", "React", "async",
    "await", "state", "props", "merge", "branch", "deploy", "build", "API",
]


def pick_voice(lang: str) -> str:
    """Choisit une voix système pour la langue demandée."""
    out = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    target = "fr_FR" if lang == "fr" else "en_US"
    # On évite les voix « nouveauté » (Bad News, Bubbles, Bells…) au timbre inexploitable.
    novelty = {"Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos",
               "Good News", "Jester", "Organ", "Superstar", "Trinoids",
               "Whisper", "Wobble", "Zarvox", "Albert", "Eddy", "Flo",
               "Grandma", "Grandpa", "Junior", "Kathy", "Ralph", "Rocko",
               "Sandy", "Shelley", "Reed"}
    for line in out.splitlines():
        if target not in line:
            continue
        name = line.split(target)[0].strip()
        if "(" in name:  # p.ex. « Eddy (Français (France)) »
            name = name.split("(")[0].strip()
        if name not in novelty:
            return name
    raise SystemExit(f"Aucune voix {target} utilisable trouvée.")


def main() -> None:
    out_dir = Path(__file__).parent / "samples"
    out_dir.mkdir(exist_ok=True)

    voices = {"fr": pick_voice("fr"), "en": pick_voice("en")}
    print(f"Voix : FR={voices['fr']}  EN={voices['en']}\n")

    for name, (lang, text) in SAMPLES.items():
        path = out_dir / f"{name}.wav"
        subprocess.run(
            ["say", "-v", voices[lang], "--data-format=LEI16@16000",
             "--file-format=WAVE", "-o", str(path), text],
            check=True,
        )
        print(f"  {path.name:16s} [{lang}] {text}")

    # La transcription attendue sert de référence au scoring.
    ref = out_dir / "references.tsv"
    ref.write_text(
        "\n".join(f"{n}\t{lang}\t{txt}" for n, (lang, txt) in SAMPLES.items()),
        encoding="utf-8",
    )
    print(f"\n{len(SAMPLES)} échantillons + {ref.name}")


if __name__ == "__main__":
    sys.exit(main())
