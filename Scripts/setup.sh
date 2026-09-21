#!/bin/bash
# One-time setup: a stable self-signed code-signing identity.
#
# macOS keys TCC grants (Accessibility, Screen Recording) to the code signature's
# designated requirement. An ad-hoc signature gets a fresh cdhash every build, so the
# Accessibility toggle stays visibly ON while every call quietly fails. A stable
# identity makes grants survive rebuilds.
#
# Idempotent.
set -euo pipefail

NAME="${1:-TabSwitcher Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# NOT `find-identity -v`: a self-signed identity reports CSSMERR_TP_NOT_TRUSTED and is
# filtered out by -v, yet signs perfectly well. Trust is a Gatekeeper concern.
if security find-identity -p codesigning | grep -q "$NAME"; then
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
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

# LibreSSL, which macOS ships as `openssl`, writes a PKCS#12 MAC that `security`
# rejects when the password is empty. Hence the throwaway one.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:tabswitcher -name "$NAME"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P tabswitcher -A -T /usr/bin/codesign

cat <<EOF

created identity: $NAME

The first build will ask for keychain access to use its private key — click
"Always Allow". If you see errSecInternalComponent instead, the dialog could not
appear; run the build again from an interactive Terminal.
EOF
