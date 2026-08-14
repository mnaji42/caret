#!/usr/bin/env bash
# Fabrique le .dmg de distribution : Caret.app à côté d'un raccourci vers
# /Applications, la disposition attendue sous macOS.
#
# Attention avant toute diffusion : ce paquet est signé avec le certificat de
# développement local, pas avec un certificat Apple Developer. Gatekeeper le
# refusera sur une autre machine tant qu'il n'est pas signé puis notarisé avec
# un compte Apple. Le script sert à valider le format, pas encore à publier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Caret"
VERSION="$(awk -F'[<>]' '/CFBundleShortVersionString/{getline; print $3}' \
    "$ROOT/app/build/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "0.1.0")"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"

"$ROOT/scripts/install.sh" release --no-launch

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "▸ préparation de l'image"
cp -R "$ROOT/app/build/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
rm -f "$DMG"

echo "▸ création du .dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

echo "▸ prêt : $DMG"
echo
echo "  Pour une vraie distribution il faudra encore :"
echo "    - un certificat Developer ID Application"
echo "    - codesign --options runtime avec ce certificat"
echo "    - xcrun notarytool submit && xcrun stapler staple"
