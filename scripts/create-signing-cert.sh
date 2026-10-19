#!/usr/bin/env bash
# Creates a self-signed "BadgeBar Local Signing" code-signing identity in your login keychain.
#
# macOS ties privacy permissions (Accessibility, Full Disk Access) to an app's signature.
# Ad-hoc signatures change on every build, which silently invalidates those permissions.
# Signing with a stable local identity keeps them working across rebuilds.
#
# Remove it any time with:  security delete-identity -c "BadgeBar Local Signing"
set -euo pipefail
NAME="BadgeBar Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:badgebar -name "$NAME" 2>/dev/null
security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P badgebar -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\"."
