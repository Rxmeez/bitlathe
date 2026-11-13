#!/bin/zsh
# One-time setup for self-signed releases (scripts/ship.sh): creates the two release keys and stores them in 1Password.
#
#   1. Sparkle update key (EdDSA): signs every update so installed copies only accept releases you published.
#      Its public half goes into project.yml (SU_PUBLIC_ED_KEY).
#   2. "Bitlathe" code-signing certificate (self-signed): every release is signed with it, so macOS treats each
#      update as the same app (the sandbox container, and any permissions, carry over).
#
# Both live only in the 1Password vault "Bitlathe" afterwards; local copies are removed.
# Needs the 1Password CLI (`op`), signed in, and Touch ID.     Usage: scripts/setup-signing-keys.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
VAULT="Bitlathe"
SPARKLE_ITEM="Sparkle update key"
CERT_ITEM="Bitlathe signing certificate"
ACCOUNT="bitlathe"
BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"

[[ -x "$BIN/generate_keys" ]] || die "build once first so Sparkle's tools are downloaded: make build"
command -v op >/dev/null || die "install the 1Password CLI: brew install 1password-cli"

if op item get "$SPARKLE_ITEM" --vault "$VAULT" >/dev/null 2>&1 || op item get "$CERT_ITEM" --vault "$VAULT" >/dev/null 2>&1; then
  die "keys already exist in 1Password vault \"$VAULT\". Refusing to create new ones: replacing them would stop existing installs from accepting updates."
fi
op vault get "$VAULT" >/dev/null 2>&1 || op vault create "$VAULT" >/dev/null
say "Using 1Password vault \"$VAULT\""

TMP=$(mktemp -d); chmod 700 "$TMP"
cleanup() {
  rm -rf "$TMP"
  security delete-generic-password -a "$ACCOUNT" -s "https://sparkle-project.org" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Sparkle update key ---------------------------------------------------------
"$BIN/generate_keys" --account "$ACCOUNT" >/dev/null
PUBLIC_KEY=$("$BIN/generate_keys" --account "$ACCOUNT" -p)
"$BIN/generate_keys" --account "$ACCOUNT" -x "$TMP/ed25519"
python3 - "$TMP/ed25519" "$PUBLIC_KEY" <<'PY' | op item create --vault "$VAULT" - >/dev/null
import json, sys
print(json.dumps({
    "title": "Sparkle update key",
    "category": "API_CREDENTIAL",
    "fields": [
        {"id": "credential", "type": "CONCEALED", "label": "credential", "value": open(sys.argv[1]).read().strip()},
        {"id": "public_key", "type": "STRING", "label": "public key", "value": sys.argv[2]},
        {"id": "notesPlain", "type": "STRING", "purpose": "NOTES",
         "value": "EdDSA key that signs Bitlathe updates (Sparkle). The public key is SU_PUBLIC_ED_KEY in project.yml. Never replace it: installed copies would stop accepting updates."},
    ],
}))
PY
say "Stored the Sparkle update key"

# --- Code-signing certificate ---------------------------------------------------
cat > "$TMP/cfg" <<'CFG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Bitlathe
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cfg" 2>/dev/null
P12_PASSWORD=$(openssl rand -base64 24)
LEGACY=""
openssl pkcs12 -help 2>&1 | grep -q -- -legacy && LEGACY="-legacy"
openssl pkcs12 -export ${=LEGACY} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "Bitlathe" -out "$TMP/bitlathe.p12" -passout "pass:$P12_PASSWORD"
python3 - "$TMP/bitlathe.p12" "$P12_PASSWORD" <<'PY' | op item create --vault "$VAULT" - >/dev/null
import base64, json, sys
print(json.dumps({
    "title": "Bitlathe signing certificate",
    "category": "API_CREDENTIAL",
    "fields": [
        {"id": "p12_base64", "type": "CONCEALED", "label": "p12_base64", "value": base64.b64encode(open(sys.argv[1], "rb").read()).decode()},
        {"id": "password", "type": "CONCEALED", "label": "password", "value": sys.argv[2]},
        {"id": "notesPlain", "type": "STRING", "purpose": "NOTES",
         "value": "Self-signed code-signing identity \"Bitlathe\" for releases. Keeping the same certificate keeps each update the same app to macOS."},
    ],
}))
PY
say "Stored the signing certificate"

# --- Public key into the app ------------------------------------------------------
sed -i '' -E "s|^( *SU_PUBLIC_ED_KEY:).*|\1 \"$PUBLIC_KEY\"|" project.yml
grep -q "SU_PUBLIC_ED_KEY: \"$PUBLIC_KEY\"" project.yml || die "could not write SU_PUBLIC_ED_KEY into project.yml; set it by hand to $PUBLIC_KEY"
say "Done. Public update key (now in project.yml): $PUBLIC_KEY"
echo "Commit project.yml; the private keys exist only in 1Password."
