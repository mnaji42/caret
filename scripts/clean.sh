#!/usr/bin/env bash
# Libère l'espace pris par les expérimentations.
#
# Tout ce qui est retiré ici se régénère : poids depuis HuggingFace,
# environnements avec uv, modèles Core ML via coreml_probe.py. Les résultats
# des mesures, eux, sont conservés — ce sont les conclusions qui comptent, pas
# les gigaoctets qui ont servi à les obtenir.
#
#   ./scripts/clean.sh          montre ce qui serait supprimé
#   ./scripts/clean.sh --yes    supprime
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HF="$HOME/.cache/huggingface/hub"
DRY=1
[ "${1:-}" = "--yes" ] && DRY=0

# Chemin, puis raison de sa suppression.
TARGETS=(
    "$HF/models--nyralabs--CrisperWhisper2.0_large|modèle large — mesuré plus lent et pas meilleur que turbo"
    "$HF/models--nyralabs--CrisperWhisper2.0_medium|modèle medium — jamais retenu"
    "$HF/models--nyralabs--CrisperWhisper2.0_small|modèle small — jamais retenu"
    "$ROOT/engine/coreml|encodeurs Core ML — sonde terminée, conclusions dans le dépôt"
    "$ROOT/poc/.venv|environnement des POC — doublon de engine/.venv"
    "$ROOT/poc/__pycache__|caches Python"
    "$ROOT/app/.build|objets de compilation Swift"
)

total=0
echo
for entry in "${TARGETS[@]}"; do
    path="${entry%%|*}"
    reason="${entry##*|}"
    [ -e "$path" ] || continue
    size_kb=$(du -sk "$path" 2>/dev/null | cut -f1)
    total=$((total + size_kb))
    printf "  %-8s %s\n" "$(du -sh "$path" 2>/dev/null | cut -f1)" "${path/#$HOME/~}"
    printf "           %s\n" "$reason"
    [ "$DRY" -eq 0 ] && rm -rf "$path"
done

printf "\n  %s au total\n" "$(echo "$total" | awk '{printf "%.1f Go", $1/1048576}')"
if [ "$DRY" -eq 1 ]; then
    echo "  (simulation — relancer avec --yes pour supprimer)"
else
    echo "  supprimé."
    echo
    echo "  Pour reconstruire si besoin :"
    echo "    cd poc && uv venv --python 3.12 && uv pip install -e ../engine soundfile"
    echo "    cd engine && uv run python coreml_probe.py convert"
fi
