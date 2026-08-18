#!/usr/bin/env python3
"""Compare le wording du prototype React à celui du code Swift.

Vérifier à l'œil ne marche pas : le prototype fait 5 600 lignes, le Swift
autant, et une phrase reformulée ne se voit pas dans un diff qu'on parcourt.
Ce script extrait les chaînes visibles par l'utilisateur des deux côtés et
signale celles du prototype qui n'ont pas d'équivalent en face.

    python3 scripts/audit-wording.py            # composants déjà portés
    python3 scripts/audit-wording.py --all      # tout le prototype

Les faux positifs existent — une phrase peut être coupée autrement en Swift —
mais ils sont peu nombreux, et chacun demande un coup d'œil plutôt qu'une
relecture intégrale.
"""
import re, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROTO = ROOT / "docs/ProjetOrganisation/prototype-react/src"
SWIFT = ROOT / "app/Sources/Sofler"

# Les écrans déjà repris. Le reste viendra avec eux.
PORTED = {
    "WelcomeCard.jsx", "LanguagePicker.jsx", "UsageHabitsCard.jsx",
    "TriggerCard.jsx", "TrialSandbox.jsx", "AppleEngineCard.jsx",
    "CrisperEngineCard.jsx", "FinalEngineCard.jsx", "CompletionView.jsx",
    "DestinationCard.jsx", "SettingsView.jsx", "HistoryView.jsx",
    "CollectView.jsx", "SettingsToggleRow.jsx", "HeaderNav.jsx",
}

def normalise(s: str) -> str:
    """Ramène une phrase à ce qui compte pour la comparer."""
    s = unicodedata.normalize("NFC", s)
    # Le Swift concatène ses chaînes : les espaces et retours varient.
    s = re.sub(r"\s+", " ", s)
    # Les marqueurs de style ne sont pas du texte.
    s = re.sub(r"[*`_]", "", s)
    # Apostrophes et guillemets sont écrits différemment des deux côtés.
    s = s.replace("’", "'").replace(" ", " ")
    return s.strip().lower()

def join_literals(swift: str) -> str:
    """Recolle les littéraux que Swift concatène.

    Le code écrit ses phrases sur plusieurs lignes — `"début " + "suite"` — et
    comparer le source brut ferait manquer toute phrase de plus de 70 caractères,
    c'est-à-dire la majorité de celles qui comptent.
    """
    return re.sub(r'"\s*\+\s*"', "", swift)


def french_strings(text: str) -> set[str]:
    """Les chaînes qui ressemblent à de la prose destinée à l'utilisateur."""
    found = set()
    # Texte entre balises JSX, et littéraux à guillemets doubles seulement.
    #
    # Les apostrophes simples sont exclues comme délimiteurs : en français elles
    # apparaissent *dans* le texte (« l'aperçu »), et les traiter comme des
    # bornes coupait chaque phrase en fragments qui ne correspondaient à rien.
    for pattern in (r">([^<>{}\n][^<>{}]{14,})<",
                    r'"([^"\n]{15,})"'):
        for raw in re.findall(pattern, text):
            s = raw.strip()
            # Écarte le code : styles, classes, imports, chemins, URL, et les
            # fragments d'objets de style qui commencent par une virgule.
            if re.search(r"[{}\\]|^[,.]|^https?:|^[a-z-]+/|=>|px\b|rgba?\(", s):
                continue
            # Écarte les valeurs CSS et les noms de classes.
            if re.search(r"^[a-z][a-z0-9 -]*$", s) or "ease" in s or ":" == s[-1:]:
                continue
            # Écarte ce qui n'a pas d'accent ni d'espace : identifiants.
            if " " not in s:
                continue
            # Doit contenir des lettres françaises courantes.
            if not re.search(r"[a-zà-ÿ]{3}", s, re.I):
                continue
            found.add(s)
    return found

def main() -> int:
    everything = "--all" in sys.argv
    swift = " ".join(normalise(join_literals(p.read_text(encoding="utf-8")))
                     for p in SWIFT.glob("*.swift"))

    total_missing = 0
    for jsx in sorted(PROTO.rglob("*.jsx")):
        if not everything and jsx.name not in PORTED:
            continue
        strings = french_strings(jsx.read_text(encoding="utf-8"))
        missing = sorted(s for s in strings if normalise(s) not in swift)
        if not missing:
            continue
        print(f"\n── {jsx.name} — {len(missing)}/{len(strings)} absentes du Swift")
        for s in missing:
            print(f"   • {s[:150]}")
        total_missing += len(missing)

    print(f"\n{total_missing} chaînes du prototype sans équivalent trouvé.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
