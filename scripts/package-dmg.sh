#!/usr/bin/env bash
# Fabrique le .dmg de distribution : Sofler.app à côté d'un raccourci vers
# /Applications, la disposition attendue sous macOS.
#
# Le fichier s'appelle toujours Sofler.dmg, sans numéro de version. C'est ce
# qui rend l'URL de téléchargement stable — la landing page pointe une fois
# sur .../releases/latest/download/Sofler.dmg et n'est plus jamais à modifier.
# La version reste lisible : elle nomme le volume monté, et elle est dans le
# bundle.
#
# Ce paquet est signé ad hoc, pas avec un certificat Apple Developer. Sur une
# autre machine, macOS refusera de l'ouvrir au premier essai ; l'utilisateur
# devra passer par Réglages Système › Confidentialité et sécurité. C'est
# assumé pour l'instant et documenté dans le README — pas un oubli.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sofler"
. "$ROOT/scripts/version.sh"
DMG="$ROOT/dist/$APP_NAME.dmg"

"$ROOT/scripts/install.sh" release --no-launch

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "▸ préparation de l'image"
cp -R "$ROOT/app/build/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
rm -f "$DMG"

echo "▸ création du .dmg"
# Le nom du volume porte la version : c'est ce que l'utilisateur voit dans le
# Finder quand l'image est montée, et le seul endroit où il peut vérifier ce
# qu'il installe avant de le glisser dans /Applications.
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

echo "▸ prêt : $DMG  ($VERSION, build $BUILD)"

if [ "$IS_RELEASE" != 1 ]; then
    cat <<'EOF'

  ⚠ Ce build ne correspond pas exactement à un tag, ou l'arbre a des
    modifications non commitées. Il est bon pour un essai, pas pour une
    release : l'app se signalera comme build de développement et ne
    proposera aucune mise à jour.
EOF
fi

cat <<'EOF'

  Le jour où le compte Apple Developer sera pris, il restera à :
    - codesign --options runtime avec le certificat Developer ID Application
    - xcrun notarytool submit --wait && xcrun stapler staple
  Les deux se branchent dans .github/workflows/release.yml, qui prévoit déjà
  l'emplacement des secrets.
EOF
