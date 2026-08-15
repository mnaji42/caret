#!/usr/bin/env bash
# Compile Sofler et l'installe dans /Applications.
#
# /Applications est l'emplacement canonique, y compris en développement :
# c'est là que macOS s'attend à trouver une app dans le sélecteur des
# Réglages Système, et ça correspond à ce que fera le .dmg. Le bundle n'est
# jamais laissé dans le dépôt.
#
#   ./scripts/install.sh              compile en debug et installe
#   ./scripts/install.sh release      compile optimisé
#   ./scripts/install.sh --no-launch  installe sans relancer
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
BUNDLE_ID="fr.lyriastudio.sofler"
APP_NAME="Sofler"
INSTALL_PATH="/Applications/$APP_NAME.app"

CONFIG="debug"
LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        release|debug) CONFIG="$arg" ;;
        --no-launch)   LAUNCH=0 ;;
        *) echo "argument inconnu : $arg" >&2; exit 2 ;;
    esac
done

# --- 1. certificat stable ------------------------------------------------
CERT_HASH="$("$ROOT/scripts/dev-cert.sh" | tail -1)"

# --- 2. compilation ------------------------------------------------------
echo "▸ compilation ($CONFIG)"
cd "$APP_DIR"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

# --- 3. assemblage du bundle --------------------------------------------
STAGE="$APP_DIR/build/$APP_NAME.app"
echo "▸ assemblage du bundle"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BINARY" "$STAGE/Contents/MacOS/$APP_NAME"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <!-- Barre de menus seule : pas d'icône au Dock, jamais de vol de focus,
         ce qui est indispensable puisque le texte doit atterrir dans l'app
         que l'utilisateur a devant lui. -->
    <key>LSUIElement</key>                <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Sofler transcrit votre voix en texte. L'audio est traité sur votre Mac et n'est jamais envoyé ailleurs.</string>
    <!-- Uniquement pour l'aperçu en direct affiché dans la barre pendant la
         dictée, qui passe par le moteur de reconnaissance de macOS. La
         transcription réelle, elle, ne l'utilise pas. -->
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Sofler affiche pendant la dictée un aperçu de ce qu'il entend, reconnu sur votre Mac. Rien n'est envoyé ailleurs.</string>
</dict>
</plist>
PLIST

echo "▸ signature (certificat $CERT_HASH)"
# --options runtime sera exigé par la notarisation ; il impose en retour de
# déclarer explicitement l'accès micro, faute de quoi le runtime le refuse
# sans qu'aucun dialogue n'apparaisse.
codesign --force --sign "$CERT_HASH" --identifier "$BUNDLE_ID" \
         --options runtime --timestamp=none \
         --entitlements "$APP_DIR/Sofler.entitlements" "$STAGE" 2>/dev/null

if ! codesign -d --entitlements - "$STAGE" 2>/dev/null | grep -q "audio-input"; then
    echo "  ✗ entitlement micro absent — le micro serait muet" >&2
    exit 1
fi
echo "  entitlement micro présent"

# --- 4. installation -----------------------------------------------------
# Remplacer le bundle sous une app qui tourne laisse un process orphelin
# pointant sur des fichiers supprimés.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "▸ arrêt de l'instance en cours"
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || pkill -x "$APP_NAME" || true
    for _ in $(seq 1 20); do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

echo "▸ installation dans $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$STAGE" "$INSTALL_PATH"

# Le cache de services de lancement garde une trace de l'ancien bundle ;
# sans ça, les Réglages Système peuvent afficher une entrée périmée.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_PATH" 2>/dev/null || true

echo "▸ vérification"
codesign --verify --deep --strict "$INSTALL_PATH" && echo "  signature valide"
codesign -d -r- "$INSTALL_PATH" 2>&1 | grep -F "designated =>" | sed 's/^/  /'

if [ "$LAUNCH" -eq 1 ]; then
    echo "▸ lancement"
    open "$INSTALL_PATH"
fi

cat <<EOF

  installé : $INSTALL_PATH

  Si l'accessibilité n'est pas encore accordée :
    Réglages Système › Confidentialité et sécurité › Accessibilité → ajouter Sofler

  Grâce au certificat stable, cette autorisation persiste d'un build à l'autre.
  Elle n'est à refaire que si le certificat change (cf. scripts/dev-cert.sh).
EOF
