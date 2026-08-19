#!/usr/bin/env bash
# Fabrique le certificat de signature de distribution, et prépare les deux
# secrets GitHub qui vont avec.
#
# À quoi ça sert, concrètement : sans certificat, la CI signe « ad hoc », et
# l'exigence désignée du bundle devient le hash du binaire —
#
#     designated => cdhash H"f82cc3b2…"
#
# Elle change donc à chaque build. macOS y voit une application différente et
# révoque l'accessibilité : **tous les utilisateurs doivent tout ré-accorder à
# chaque mise à jour.** Avec un certificat stable, elle devient
#
#     designated => identifier "fr.lyriastudio.caspr" and certificate leaf = H"…"
#
# qui ne dépend plus du binaire. Les autorisations survivent aux mises à jour.
#
# Ça ne remplace pas la notarisation : Gatekeeper continuera de demander un
# passage par les Réglages Système au premier lancement. Ce sont deux problèmes
# distincts, et celui-ci se règle sans compte Apple.
#
#     ./scripts/make-signing-cert.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_NAME="Caspr Distribution"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OUT="$ROOT/dist/signing"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    cat <<EOF
▸ « $CERT_NAME » existe déjà dans votre trousseau.

  Le regénérer produirait une identité différente, ce qui ferait exactement
  le dommage qu'on cherche à éviter : les autorisations de tous les
  utilisateurs sauteraient à la prochaine mise à jour.

  Pour repartir de zéro malgré tout, supprimez-le d'abord dans Trousseaux
  d'accès, puis relancez.
EOF
    exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ génération du certificat"
# Dix ans : ce certificat ne prouve l'identité de personne, il sert seulement
# à rester le même. Son expiration casserait les autorisations de tout le
# monde, donc autant qu'elle soit lointaine.
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CERT_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

PASSWORD="$(openssl rand -base64 24)"

# Le trousseau macOS ne lit pas le chiffrement PKCS#12 par défaut d'OpenSSL 3 :
# on force les algorithmes hérités qu'il sait ouvrir.
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASSWORD" -name "$CERT_NAME" 2>/dev/null

echo "▸ import dans le trousseau de session"
# Pour que les builds locaux signent avec la même identité que la CI. Sans ça,
# votre machine et vos releases produiraient deux applications différentes aux
# yeux de macOS.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign \
    -P "$PASSWORD" >/dev/null

HASH="$(security find-certificate -c "$CERT_NAME" -Z 2>/dev/null \
        | awk '/SHA-1 hash:/ {print $3; exit}')"

# Les deux valeurs partent dans des fichiers, jamais à l'écran : ce qui
# s'affiche dans un terminal finit dans un historique, une capture, ou le
# journal d'un outil.
base64 -i "$TMP/cert.p12" -o "$OUT/SIGNING_CERTIFICATE_P12.txt"
printf '%s' "$PASSWORD" > "$OUT/SIGNING_CERTIFICATE_PASSWORD.txt"
chmod 600 "$OUT"/*.txt

cat <<EOF

  Certificat créé — empreinte $HASH

  Deux fichiers vous attendent dans dist/signing/ (non versionné) :

      SIGNING_CERTIFICATE_P12.txt
      SIGNING_CERTIFICATE_PASSWORD.txt

  À coller dans GitHub › Settings › Secrets and variables › Actions,
  sous ces deux noms exactement. Le contenu de chaque fichier est la valeur
  du secret du même nom.

  Ensuite : supprimez dist/signing/. Le certificat vit désormais dans votre
  trousseau et dans GitHub ; ces copies en clair n'ont plus de raison d'être.

      rm -rf dist/signing

  ⚠ Ne perdez pas ce certificat. Le remplacer un jour par un autre ferait
    sauter l'accessibilité chez tous ceux qui ont déjà installé Caspr. Une
    sauvegarde du .p12 dans un gestionnaire de mots de passe est raisonnable.
EOF
