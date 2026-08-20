#!/usr/bin/env bash
# Produit app/build/Caspr.icns à partir de scripts/make-icon.swift.
#
# Le .icns n'est pas versionné : c'est un artefact, comme le binaire. Sa source
# est le script Swift, qui lui se relit et se modifie.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/make-icon.swift"
ICNS="$ROOT/app/build/Caspr.icns"

# Le dessin, pris là où il est **versionné**.
#
# Il était lu dans `docs/images/svg-assets/`, qui est dans `.gitignore` — ligne
# `docs/`, « documentation locale et prototypes ». Le fichier existe donc sur ma
# machine et sur aucune autre : sur le runner, qui travaille sur un clone frais,
# `swift make-icon.swift` recevait un chemin vide et l'étape « Construire le
# DMG » échouait sans jamais nommer le fichier manquant. C'est ce qui a fait
# échouer la publication de la 0.9.0.
#
# La copie embarquée est **la même**, à l'octet près, et elle voyage déjà dans
# le bundle pour la fenêtre d'installation. Une seule source vaut mieux que deux
# identiques dont une seule est publiée.
ART="$ROOT/app/Sources/Caspr/Resources/icons/caspr-app-icon.svg"
if [ ! -f "$ART" ]; then
    echo "make-icon : dessin introuvable — $ART" >&2
    exit 1
fi

# Compiler le script coûte quelques secondes, et l'icône change une fois par
# an. On ne redessine que si la source est plus récente que le résultat.
if [ -f "$ICNS" ] && [ "$ICNS" -nt "$SRC" ] && [ "$ICNS" -nt "$ART" ]; then
    exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

swift "$SRC" "$ART" "$STAGE/Caspr.iconset"
mkdir -p "$(dirname "$ICNS")"
iconutil -c icns "$STAGE/Caspr.iconset" -o "$ICNS"
echo "  icône : $(basename "$ICNS")"
