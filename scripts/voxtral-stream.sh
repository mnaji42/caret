#!/usr/bin/env bash
# Service Voxtral **parallèle**, pour la dictée au fil de la parole.
#
# Volontairement séparé du moteur principal, et pas par prudence excessive :
# l'application régénère l'agent de lancement de `fr.lyriastudio.caspr.engine`
# à chaque fois qu'elle réconcilie l'état du service. Un `--engine voxtral`
# ajouté à cet agent-là y survit jusqu'à la prochaine réconciliation, puis
# disparaît sans prévenir — c'est arrivé, et ça a fait juger macOS en croyant
# juger Voxtral.
#
# Ce service-ci a son propre agent et son propre socket. L'application ne le
# connaît pas et ne peut donc pas l'écraser.
#
#   ./scripts/voxtral-stream.sh           # démarrer
#   ./scripts/voxtral-stream.sh --stop    # arrêter
#   ./scripts/voxtral-stream.sh --status  # qui répond
set -euo pipefail

LABEL="fr.lyriastudio.caspr.voxtral"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PROJECT="$HOME/Library/Application Support/Caspr/engine"
SOCK="$HOME/Library/Caches/caspr/voxtral.sock"
LOG="$HOME/Library/Logs/Caspr/voxtral.log"
DOMAIN="gui/$(id -u)"
UV="$(command -v uv || echo /opt/homebrew/bin/uv)"

ping_service() {
  "$PROJECT/.venv/bin/python" - "$SOCK" <<'PING'
import json, socket, struct, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print("  aucun service"); sys.exit(1)
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(10)
    s.connect(str(p))
    h = json.dumps({"op": "ping", "payload_bytes": 0}).encode()
    s.sendall(struct.pack(">I", len(h)) + h)
    (n,) = struct.unpack(">I", s.recv(4))
    r = json.loads(s.recv(n))
except Exception as exc:
    print(f"  ne répond pas : {exc}"); sys.exit(1)
print(f"  ✓ {r['model']}")
print(f"    prêt : {r['ready']} | calcul : {r['device']}")
PING
}

case "${1:-}" in
  --status) ping_service; exit $? ;;
  --stop)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$SOCK"; echo "✓ arrêté"; exit 0 ;;
esac

echo "→ dépendances MLX (une fois)"
VIRTUAL_ENV="$PROJECT/.venv" "$UV" pip install --quiet mlx mlx-audio
echo "→ préchauffage — payé ici, pas dans launchd"
"$UV" run --project "$PROJECT" python -c "import mlx_audio; print('  résolu')"

mkdir -p "$(dirname "$LOG")" "$(dirname "$PLIST")" "$(dirname "$SOCK")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$UV</string><string>run</string>
    <string>--project</string><string>$PROJECT</string>
    <string>python</string><string>-m</string><string>caspr_engine.server</string>
    <string>--engine</string><string>voxtral</string>
    <string>--socket</string><string>$SOCK</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PLIST_EOF

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$SOCK"; sleep 1
launchctl bootstrap "$DOMAIN" "$PLIST"

printf "→ chargement "
for _ in $(seq 1 120); do [ -S "$SOCK" ] && break; printf "."; sleep 1; done
echo
ping_service || { tail -8 "$LOG" 2>/dev/null; exit 1; }
echo
echo "  Socket : $SOCK"
echo "  Le moteur principal n'est pas touché — ⌥ droite continue comme avant."
