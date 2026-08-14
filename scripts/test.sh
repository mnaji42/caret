#!/usr/bin/env bash
# Lance toute la vérification du projet.
#
#   ./scripts/test.sh          rapide — logique pure, quelques secondes
#   ./scripts/test.sh --full   ajoute la non-régression avec le modèle (~1 min)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL=0
[ "${1:-}" = "--full" ] && FULL=1
failures=0

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }

step "Moteur — logique pure"
cd "$ROOT/engine"
uv run pytest -q || failures=$((failures + 1))

step "Application — composition du texte"
cd "$ROOT/app"
swift test 2>&1 | tail -3 || failures=$((failures + 1))

if [ "$FULL" -eq 1 ]; then
    step "Non-régression — modèle chargé"
    cd "$ROOT/engine"
    uv run pytest -m slow -q || failures=$((failures + 1))

    step "Performance — référence chiffrée"
    uv run python benchmark.py --label "courant" -o benchmarks/latest.json \
        2>/dev/null | tail -6
    if [ -f benchmarks/pytorch-mps.json ]; then
        uv run python benchmark.py --compare benchmarks/pytorch-mps.json \
            benchmarks/latest.json 2>/dev/null | head -12
    fi
fi

if [ "$failures" -eq 0 ]; then
    printf "\n\033[32m  tout passe\033[0m\n"
else
    printf "\n\033[31m  %d étape(s) en échec\033[0m\n" "$failures"
    exit 1
fi
