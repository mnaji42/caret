#!/usr/bin/env bash
# Produit app/build/Caspr.icns à partir de scripts/make-icon.swift.
#
# Le .icns n'est pas versionné : c'est un artefact, comme le binaire. Sa source
# est le script Swift, qui lui se relit et se modifie.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/make-icon.swift"
ICNS="$ROOT/app/build/Caspr.icns"

# Compiler le script coûte quelques secondes, et l'icône change une fois par
# an. On ne redessine que si la source est plus récente que le résultat.
ART="$ROOT/docs/images/svg-assets/caspr-app-icon.svg"
if [ -f "$ICNS" ] && [ "$ICNS" -nt "$SRC" ] && [ "$ICNS" -nt "$ART" ]; then
    exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

swift "$SRC" "$ROOT/docs/images/svg-assets/caspr-app-icon.svg" \
      "$STAGE/Caspr.iconset"
mkdir -p "$(dirname "$ICNS")"
iconutil -c icns "$STAGE/Caspr.iconset" -o "$ICNS"
echo "  icône : $(basename "$ICNS")"
