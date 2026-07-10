#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${OBSERVER_LOCAL_CODESIGN_NAME:-Observer Local Development}"
KEYCHAIN="${OBSERVER_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
SIGNING_DIR="${OBSERVER_SIGNING_DIR:-$HOME/Library/Application Support/Observer/Signing}"
PASSWORD_FILE="$SIGNING_DIR/p12-password"
CERT_FILE="$SIGNING_DIR/observer-local-development.crt"
KEY_FILE="$SIGNING_DIR/observer-local-development.key"
P12_FILE="$SIGNING_DIR/observer-local-development.p12"

existing_identity() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | awk -v name="$IDENTITY_NAME" 'index($0, name) { print $2; exit }'
}

if identity_hash="$(existing_identity)" && [[ -n "$identity_hash" ]]; then
  echo "$identity_hash"
  exit 0
fi

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ -f "$PASSWORD_FILE" ]]; then
  P12_PASSWORD="$(<"$PASSWORD_FILE")"
else
  P12_PASSWORD="$(openssl rand -hex 24)"
  printf '%s' "$P12_PASSWORD" > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
fi

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -sha256 \
  -subj "/CN=$IDENTITY_NAME/" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" >/dev/null 2>&1

chmod 600 "$KEY_FILE"

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$KEY_FILE" \
  -in "$CERT_FILE" \
  -out "$P12_FILE" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12_FILE" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_FILE" >/dev/null

if identity_hash="$(existing_identity)" && [[ -n "$identity_hash" ]]; then
  echo "$identity_hash"
  exit 0
fi

echo "Could not create a valid local code signing identity." >&2
exit 1
