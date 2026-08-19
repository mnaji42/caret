#!/usr/bin/env bash
# Crée le certificat de signature local utilisé pour le développement.
#
# Pourquoi ce détour plutôt qu'une signature ad hoc : macOS attache les
# autorisations (accessibilité, micro) à une « designated requirement »
# dérivée de la signature. En ad hoc, cette exigence contient le cdhash du
# binaire — qui change à chaque compilation, donc l'autorisation saute et il
# faut re-cocher la case après chaque build.
#
# Signé avec un certificat, l'exigence devient :
#
#     identifier "fr.lyriastudio.caspr" and certificate leaf = H"<empreinte>"
#
# Elle ne dépend plus du binaire : on recompile autant qu'on veut, les
# autorisations tiennent.
#
# Le certificat reste auto-signé et local : il ne sert qu'à cette machine et
# ne remplace pas un certificat Apple Developer pour la distribution.
set -euo pipefail

CERT_NAME="Caspr Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

existing_hash() {
    security find-certificate -c "$CERT_NAME" -Z 2>/dev/null \
        | awk '/SHA-1 hash:/ {print $3; exit}'
}

if HASH="$(existing_hash)" && [ -n "$HASH" ]; then
    echo "▸ certificat déjà présent : $HASH"
    echo "$HASH"
    exit 0
fi

echo "▸ génération du certificat « $CERT_NAME »" >&2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CERT_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Le trousseau macOS ne lit pas le chiffrement PKCS#12 par défaut d'OpenSSL 3 :
# on force les algorithmes hérités qu'il sait ouvrir.
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:caspr -name "$CERT_NAME" 2>/dev/null

# -T /usr/bin/codesign autorise codesign à utiliser la clé sans redemander
# l'accès au trousseau à chaque signature.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P caspr >/dev/null

HASH="$(existing_hash)"
if [ -z "$HASH" ]; then
    echo "échec : certificat non retrouvé après import" >&2
    exit 1
fi

echo "▸ certificat créé : $HASH" >&2
echo "$HASH"
