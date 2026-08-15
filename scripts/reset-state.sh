#!/usr/bin/env bash
# Remet Sofler dans l'état d'une première installation, pour éprouver l'accueil.
#
#   ./scripts/reset-state.sh          réglages, accueil, autorisations
#   ./scripts/reset-state.sh --all    + corpus, modèle, service, application
#
# Par défaut, le corpus n'est PAS touché. C'est le seul contenu irremplaçable
# de la machine : des centaines de dictées réelles, enregistrées pour mesurer
# la qualité des moteurs, et que rien ne permet de reconstituer. Les réglages
# se refont en une minute, le corpus non.
#
# Ce que fait la réinitialisation par défaut, et qui suffit à revoir l'accueil
# exactement comme le verrait quelqu'un qui installe Sofler pour la première
# fois :
#   - efface les réglages et l'historique (UserDefaults)
#   - révoque le micro et l'accessibilité (TCC), donc l'accueil les redemande
set -euo pipefail

BUNDLE_ID="fr.lyriastudio.sofler"
SUPPORT="$HOME/Library/Application Support/Sofler"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALL=0
case "${1:-}" in
    --all) ALL=1 ;;
    "") ;;
    *) echo "argument inconnu : $1" >&2; exit 2 ;;
esac

# --- Arrêter l'application ------------------------------------------------
# Sofler réécrit ses réglages en quittant : les effacer pendant qu'il tourne
# les verrait réapparaître à la seconde suivante.
if pgrep -x Sofler >/dev/null 2>&1; then
    echo "▸ arrêt de Sofler"
    osascript -e 'quit app "Sofler"' 2>/dev/null || pkill -x Sofler || true
    sleep 1
fi

# --- Réglages et historique ------------------------------------------------
# Sauvegarde d'abord. Les réglages ne valent pas le corpus, mais le lexique se
# construit terme par terme sur des semaines d'usage, et `defaults delete` ne
# laisse rien derrière lui. La leçon a été apprise en le perdant une fois.
BACKUP_DIR="$HOME/Library/Application Support/Sofler/backups"
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR"
    BACKUP="$BACKUP_DIR/prefs-$(date +%Y-%m-%dT%H-%M-%S).plist"
    defaults export "$BUNDLE_ID" "$BACKUP"
    echo "▸ réglages sauvegardés"
    echo "  $BACKUP"
    echo "  restauration : defaults import $BUNDLE_ID \"\$fichier\""
fi

echo "▸ effacement des réglages"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
# Le cache de préférences garde une copie en mémoire, qui réécrirait le
# fichier qu'on vient de supprimer.
killall cfprefsd 2>/dev/null || true

# --- Autorisations ---------------------------------------------------------
# Sans ça, l'accueil s'ouvrirait avec le micro et l'accessibilité déjà
# accordés — c'est-à-dire sans montrer ce qu'on cherche justement à vérifier.
echo "▸ révocation des autorisations"
tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 \
    || echo "  (micro : rien à révoquer)"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 \
    || echo "  (accessibilité : rien à révoquer)"

if [ "$ALL" -eq 0 ]; then
    cat <<EOF

  Réinitialisé. Le corpus est intact :
    $SUPPORT/corpus  ($(du -sh "$SUPPORT" 2>/dev/null | cut -f1 || echo "absent"))

  Relancez Sofler : l'accueil s'ouvrira comme au premier jour.

  Pour tout supprimer, corpus compris : ./scripts/reset-state.sh --all
EOF
    exit 0
fi

# --- Tout effacer ----------------------------------------------------------
MODEL="$HOME/.cache/huggingface/hub/models--nyralabs--CrisperWhisper2.0_turbo"

echo
echo "  ⚠ --all va supprimer définitivement :"
for path in "$SUPPORT" "$HOME/Library/Logs/Sofler" "$HOME/Library/Caches/sofler" \
            "$MODEL" "/Applications/Sofler.app"; do
    if [ -e "$path" ]; then
        printf "      %-58s %s\n" "$path" "$(du -sh "$path" 2>/dev/null | cut -f1)"
    fi
done
echo "      le service moteur (launchd)"
echo
printf "  Taper « supprimer » pour confirmer : "
read -r answer
[ "$answer" = "supprimer" ] || { echo "  annulé."; exit 1; }

echo "▸ retrait du service moteur"
"$ROOT/scripts/install-service.sh" --uninstall >/dev/null 2>&1 || true

echo "▸ suppression des données"
# Chemins littéraux, jamais construits par expansion : une variable vide dans
# un rm -rf effacerait la racine.
rm -rf "$SUPPORT"
rm -rf "$HOME/Library/Logs/Sofler"
rm -rf "$HOME/Library/Caches/sofler"
# Seulement le modèle de Sofler. ~/.cache/huggingface est partagé avec tout
# autre projet qui utilise la bibliothèque : l'effacer en entier ferait
# retélécharger des gigaoctets qui ne nous appartiennent pas.
rm -rf "$MODEL"
rm -rf "/Applications/Sofler.app"

echo
echo "  Tout est supprimé. Il ne reste de Sofler que le dépôt."
echo "  Pour repartir de zéro : ./scripts/install.sh"
