#!/bin/bash
# Creates a stable self-signed code-signing identity in the login keychain.
#
# Why this matters more than it looks: macOS keys TCC grants (Accessibility, Screen
# Recording) to the code signature's designated requirement. An ad-hoc signed binary
# gets a fresh cdhash on every build, so the Accessibility toggle stays visibly ON
# while every AX call quietly fails. A stable identity makes the grant survive
# rebuilds, which is the difference between a usable dev loop and a maddening one.
#
# Idempotent: re-running is a no-op if the identity already exists.
set -euo pipefail

NAME="${1:-TabSwitcher Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "identity already present: $NAME"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = codesign
prompt = no
[dn]
CN = $NAME
[codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf"

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:tabswitcher -name "$NAME"

# -T codesign so codesign can use the key without prompting on every build.
# LibreSSL (what macOS ships as `openssl`) writes a PKCS#12 MAC that `security`
# rejects when the password is empty, so use a throwaway one.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P tabswitcher -A -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "created identity: $NAME"
security find-identity -v -p codesigning | grep "$NAME"
