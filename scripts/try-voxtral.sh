#!/usr/bin/env bash
# Basculer le moteur de Caspr entre CrisperWhisper et Voxtral, sans rien
# recompiler.
#
# L'application ne change pas d'une ligne : le protocole app ↔ moteur n'a
# jamais nommé de modèle, il envoie du PCM et reçoit du texte. Ce script ne
# fait que réécrire l'agent de lancement et redémarrer le service.
#
#   ./scripts/try-voxtral.sh            # passer à Voxtral
#   ./scripts/try-voxtral.sh --crisper  # revenir à CrisperWhisper
#   ./scripts/try-voxtral.sh --status   # savoir qui répond
set -euo pipefail

LABEL="fr.lyriastudio.caspr.engine"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/Caspr"
PROJECT="$SUPPORT/engine"
LOGDIR="$HOME/Library/Logs/Caspr"
DOMAIN="gui/$(id -u)"
UV="$(command -v uv || echo /opt/homebrew/bin/uv)"

case "${1:-}" in
  --status)
    echo "agent : $([ -f "$PLIST" ] && echo installé || echo absent)"
    if [ -f "$PLIST" ]; then
      /usr/libexec/PlistBuddy -c "Print :ProgramArguments" "$PLIST" 2>/dev/null \
        | tr -d ' ' | tr '\n' ' ' | sed 's/^/  args : /'; echo
    fi
    launchctl list "$LABEL" >/dev/null 2>&1 \
      && echo "service : en marche" || echo "service : arrêté"
    exit 0 ;;
  --crisper) ENGINE=crisper ;;
  *)         ENGINE=voxtral ;;
esac

if [ "$ENGINE" = voxtral ]; then
  echo "→ installation de mlx-audio dans le moteur (une fois)"
  # Additif : mlx cohabite avec torch, rien n'est rétrogradé. Vérifié.
  VIRTUAL_ENV="$PROJECT/.venv" "$UV" pip install --quiet mlx mlx-audio
  ARGS_EXTRA="<string>--engine</string><string>voxtral</string>"
  echo "→ Voxtral Realtime 4B (4-bit MLX) — ~2,9 Go, se charge en ~2 s"
  echo "  Attention : ce modèle ignore le sélecteur « Mot à mot » et le"
  echo "  lexique. C'est un transcripteur pur, pas un modèle à consignes."
else
  ARGS_EXTRA=""
  echo "→ CrisperWhisper turbo"
fi

# Préchauffage, et c'est le correctif qui compte. La première version coupait
# le service puis laissait launchd lancer `uv run --project`, qui commence par
# résoudre l'environnement et peut télécharger des roues. Mesuré : 4 min 39 se
# sont écoulées entre l'arrêt de l'ancien moteur et le démarrage du nouveau —
# et pendant ce temps l'application est retombée en silence sur macOS. Les
# dictées de test ont donc été écrites par macOS, pas par le moteur qu'on
# croyait éprouver.
#
# On paie donc la résolution ici, pendant que l'ancien moteur sert encore.
echo "→ préchauffage de l'environnement"
"$UV" run --project "$PROJECT" python -c "
import importlib, sys
for m in ('mlx', 'mlx_audio') if '$ENGINE' == 'voxtral' else ('torch',):
    importlib.import_module(m)
print('  dépendances résolues')
" || { echo "✗ l'environnement n'est pas prêt — rien n'a été changé"; exit 1; }

mkdir -p "$LOGDIR" "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$UV</string><string>run</string>
    <string>--project</string><string>$PROJECT</string>
    <string>python</string><string>-m</string><string>caspr_engine.server</string>
    $ARGS_EXTRA
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGDIR/engine.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/engine.log</string>
</dict></plist>
PLIST_EOF

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/Caches/caspr/engine.sock"
launchctl bootstrap "$DOMAIN" "$PLIST"

printf "→ chargement "
for _ in $(seq 1 300); do
  [ -S "$HOME/Library/Caches/caspr/engine.sock" ] && break
  printf "."; sleep 1
done
echo

# Interroger le service plutôt que constater un fichier. Un socket présent dit
# qu'un processus écoute, pas lequel — et c'est précisément la confusion qui a
# fait juger macOS en croyant juger Voxtral.
"$PROJECT/.venv/bin/python" - <<'PING'
import json, socket, struct, sys
from pathlib import Path
p = Path.home() / "Library/Caches/caspr/engine.sock"
if not p.exists():
    print("✗ aucun service ne répond. Voir le journal."); sys.exit(1)
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(10)
    s.connect(str(p))
    h = json.dumps({"op": "ping", "payload_bytes": 0}).encode()
    s.sendall(struct.pack(">I", len(h)) + h)
    (n,) = struct.unpack(">I", s.recv(4))
    r = json.loads(s.recv(n))
except Exception as exc:
    print(f"✗ le service ne répond pas : {exc}"); sys.exit(1)
print(f"✓ répond : {r['model']}")
print(f"  prêt : {r['ready']} | calcul : {r['device']}")
print()
print("  Dictez normalement — l'application ne voit pas la différence.")
print("  Pour vérifier après coup QUI a écrit une dictée, la collecte note")
print("  le moteur dans le corpus : c'est la seule preuve qui ne se discute pas.")
PING
rc=$?
[ $rc -eq 0 ] || { tail -6 "$LOGDIR/engine.log" 2>/dev/null; exit 1; }
