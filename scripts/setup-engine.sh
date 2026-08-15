#!/usr/bin/env bash
# Installe le moteur CrisperWhisper, et rien d'autre.
#
# Distinct de setup.sh, qui compile aussi l'application et suppose Xcode. Ici
# on part du principe que Sofler est déjà installé — téléchargé depuis le .dmg
# — et qu'il ne manque que le moteur Python.
#
# C'est le seul passage obligé par le Terminal, et il n'a lieu qu'une fois.
# À la fin, ce script dépose un descripteur que l'application lit pour savoir
# où le moteur s'est installé. À partir de là elle sait tout faire elle-même :
# installer le service, le démarrer, l'arrêter, changer de modèle.
#
#   ./scripts/setup-engine.sh              installe, modèle turbo
#   ./scripts/setup-engine.sh --model small
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/Sofler"
DESCRIPTOR="$SUPPORT/engine.json"
MODEL="turbo"

while [ $# -gt 0 ]; do
    case "$1" in
        --model) MODEL="${2:-turbo}"; shift 2 ;;
        *) echo "argument inconnu : $1" >&2; exit 2 ;;
    esac
done

case "$MODEL" in
    small|medium|turbo|large) ;;
    *) echo "modèle inconnu : $MODEL (small, medium, turbo, large)" >&2; exit 2 ;;
esac
MODEL_ID="nyralabs/CrisperWhisper2.0_$MODEL"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }

# --- 1. prérequis ---------------------------------------------------------
step "Vérification des prérequis"

if [ "$(uname -m)" != "arm64" ]; then
    echo "  ✗ CrisperWhisper exige un Mac Apple Silicon (M1 ou plus récent)." >&2
    echo "    Le moteur intégré de macOS, lui, fonctionne sans rien installer." >&2
    exit 1
fi
echo "  ✓ Apple Silicon"

# uv n'est pas installé automatiquement : télécharger et exécuter un
# installateur à la place de quelqu'un, sans qu'il l'ait vu passer, est une
# habitude qu'on ne prend pas. La commande est donnée, il la lance s'il veut.
if ! command -v uv >/dev/null 2>&1; then
    cat >&2 <<'EOF'
  ✗ uv est manquant. C'est le gestionnaire d'environnements Python utilisé ici.

    Avec Homebrew :        brew install uv
    Sans Homebrew :        voir https://docs.astral.sh/uv/

    Puis relancez ce script.
EOF
    exit 1
fi
UV="$(command -v uv)"
echo "  ✓ uv — $UV"

# --- 2. environnement Python ---------------------------------------------
step "Environnement Python (~1,2 Go de bibliothèques)"
cd "$ROOT/engine"
[ -d .venv ] || uv venv --python 3.12
uv pip install -e . --quiet
uv pip install soundfile --quiet
cd "$ROOT"
echo "  ✓ torch, transformers et leurs dépendances installés"

# --- 3. modèle ------------------------------------------------------------
step "Modèle $MODEL"
cat <<EOF
  Les poids de CrisperWhisper sont distribués par Nyra Health sous une
  licence de recherche non commerciale. Sous une lecture stricte, dicter un
  courriel professionnel peut déjà en relever.

  https://huggingface.co/$MODEL_ID/blob/main/LICENSE.md

EOF
printf "  Télécharger le modèle et accepter cette licence ? [o/N] "
read -r answer
case "$answer" in
    [oO]*|[yY]*) ;;
    *) echo "  Annulé. Rien n'a été téléchargé."; exit 1 ;;
esac

# Le téléchargement passe par la bibliothèque plutôt que par curl : elle gère
# la reprise, la vérification et l'arborescence du cache, qu'il faudrait sinon
# reproduire à l'identique pour que le serveur retrouve ses fichiers.
uv run --project "$ROOT/engine" python - <<PY
from huggingface_hub import snapshot_download
print("  téléchargement de $MODEL_ID …")
snapshot_download("$MODEL_ID")
print("  ✓ modèle en place")
PY

# --- 4. descripteur -------------------------------------------------------
# C'est ce fichier qui affranchit l'utilisateur du Terminal pour la suite.
step "Déclaration auprès de l'application"
mkdir -p "$SUPPORT"
cat > "$DESCRIPTOR" <<JSON
{
  "model" : "$MODEL",
  "project" : "$ROOT/engine",
  "uv" : "$UV"
}
JSON
echo "  ✓ $DESCRIPTOR"

cat <<'DONE'

  Le moteur est installé.

  Retournez dans Sofler : l'accueil et les réglages détectent maintenant
  CrisperWhisper, et un bouton suffit à démarrer le service, l'arrêter ou
  changer de modèle. Vous n'aurez plus besoin du Terminal.

DONE
