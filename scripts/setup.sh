#!/usr/bin/env bash
# Installation complète de Caret, en une commande.
#
# Enchaîne : environnement Python, service moteur, application signée. Chaque
# étape est idempotente — relancer le script répare une installation partielle
# plutôt que de tout refaire.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }

step "Vérification des prérequis"
[ "$(uname -m)" = "arm64" ] || { echo "  Caret exige un Mac Apple Silicon." >&2; exit 1; }
command -v uv >/dev/null || { echo "  uv manquant. Installer avec : brew install uv" >&2; exit 1; }
command -v swift >/dev/null || { echo "  Outils Swift manquants. Installer Xcode." >&2; exit 1; }
echo "  Apple Silicon, uv et Swift présents."

step "Environnement Python du moteur"
cd engine
[ -d .venv ] || uv venv --python 3.12
uv pip install -e . --quiet
uv pip install soundfile --quiet
cd "$ROOT"
echo "  dépendances installées."

step "Téléchargement du modèle (~1,5 Go au premier lancement)"
echo "  Les poids CrisperWhisper sont sous licence Nyra Health"
echo "  Non-Commercial Research. Voir README.md avant tout usage professionnel."

step "Service moteur"
./scripts/install-service.sh

step "Application"
./scripts/install.sh --no-launch

cat <<'DONE'

  Installation terminée.

  Il reste deux autorisations à accorder, que macOS n'accepte pas de
  déléguer à une application :

    1. Micro         — demandé au premier lancement
    2. Accessibilité — Réglages Système › Confidentialité et sécurité
                       › Accessibilité → ajouter Caret

  Puis : ouvrir Caret, taper Option droite, parler, taper à nouveau.

DONE
open /Applications/Caret.app
