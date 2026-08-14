#!/usr/bin/env bash
# Installe le moteur comme service de session, démarré à l'ouverture de session.
#
# Sans ça, Caret est inutilisable après un redémarrage tant qu'on n'a pas
# ouvert un terminal pour relancer le moteur à la main — ce qui disqualifie
# l'outil pour un usage quotidien.
#
#   ./scripts/install-service.sh            installe et démarre
#   ./scripts/install-service.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="dev.mnaji.caret.engine"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Caret"

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "▸ service retiré"
    exit 0
fi

UV="$(command -v uv || echo /opt/homebrew/bin/uv)"
if [ ! -x "$UV" ]; then
    echo "uv introuvable — installer avec : brew install uv" >&2
    exit 1
fi

mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$UV</string>
        <string>run</string>
        <string>--project</string>
        <string>$ROOT/engine</string>
        <string>python</string>
        <string>-m</string>
        <string>caret_engine.server</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$ROOT/engine</string>

    <key>RunAtLoad</key>
    <true/>
    <!-- Le modèle occupe ~3 Go de mémoire : on le relance s'il tombe, mais
         sans insister en boucle si le démarrage échoue vraiment. -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/engine.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/engine.log</string>

    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST_EOF

# bootout puis bootstrap : recharger un service déjà présent échoue sinon.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "▸ service installé : $LABEL"
echo "  journal : $LOG_DIR/engine.log"
echo
printf "  chargement du modèle "
for _ in $(seq 1 60); do
    if [ -S "$HOME/Library/Caches/caret/engine.sock" ]; then
        echo "— prêt"
        exit 0
    fi
    printf "."
    sleep 1
done
echo
echo "  le moteur n'a pas répondu, voir $LOG_DIR/engine.log" >&2
exit 1
