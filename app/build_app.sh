#!/usr/bin/env bash
# Assemble Caret.app à partir du binaire SwiftPM.
#
# Le bundle n'est pas cosmétique : macOS rattache les autorisations micro et
# accessibilité à un identifiant de bundle signé. Un exécutable nu les fait
# attribuer au terminal parent, et elles seraient redemandées à chaque build.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="Caret.app"
BUNDLE_ID="dev.mnaji.caret"

echo "▸ compilation ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Caret"

echo "▸ assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Caret"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Caret</string>
    <key>CFBundleDisplayName</key>     <string>Caret</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>Caret</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- Barre de menus uniquement : pas d'icône au Dock, pas de vol de focus. -->
    <key>LSUIElement</key>             <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Caret transcrit votre voix en texte. L'audio est traité sur votre Mac et n'est jamais envoyé ailleurs.</string>
</dict>
</plist>
PLIST

# Signature ad hoc : suffit à donner une identité stable aux autorisations en
# développement. La notarisation viendra pour la distribution.
echo "▸ signature ad hoc"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" 2>/dev/null

echo "▸ prêt : $(pwd)/$APP"
echo
echo "  lancer :   open $APP"
echo "  journal :  log stream --predicate 'process == \"Caret\"' --level debug"
