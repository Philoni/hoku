#!/bin/zsh
#
# ONE-TIME: creates Hoku's long-lived, self-signed code signing identity "Hoku Release Signing".
# Its SHA-1 ends up in the designated requirement (DR) of every release:
#     identifier "io.github.philoni.hoku" and certificate leaf = H"<sha1>"
# macOS uses that DR to recognise Hoku across updates (local network, login item, …).
# The certificate can never be "renewed" without changing the DR – BACK IT UP (two places).
#
# Usage:
#   scripts/make-signing-cert.sh [--out DIR] [--no-import] [--github OWNER/REPO]
#     --out DIR        where to write the files (default: ~/Desktop/hoku-signing-YYYYMMDD, mode 0700)
#     --no-import      do not import into the login keychain
#     --github REPO    also set the GitHub environment secrets/variable via `gh` (values are never printed)
set -euo pipefail

CN="Hoku Release Signing"
BUNDLE_ID="io.github.philoni.hoku"
DAYS=7305                          # 20 years. Expiry does not invalidate untimestamped signatures (TN2206).
OUT_DIR="$HOME/Desktop/hoku-signing-$(date +%Y%m%d)"
IMPORT=1
GH_REPO=""
GH_ENV="release"

die() { print -u2 "✗ $*"; exit 1; }
while (( $# )); do
    case $1 in
        --out)       OUT_DIR=${2:?}; shift 2 ;;
        --no-import) IMPORT=0; shift ;;
        --github)    GH_REPO=${2:?}; shift 2 ;;
        *)           die "unknown option $1" ;;
    esac
done

# A second certificate with the same name would make codesign ambiguous – and a new one means a new DR.
if security find-certificate -c "$CN" >/dev/null 2>&1; then
    die "A certificate named '$CN' already exists in your keychains. Use it (or remove it deliberately) – do not create a second one."
fi
[[ -e $OUT_DIR ]] && die "$OUT_DIR already exists"

# /usr/bin/openssl is LibreSSL: its PKCS#12 export already uses the legacy algorithms (3DES/RC2/SHA1)
# that macOS imports reliably. OpenSSL 3.x needs -legacy for the same result.
OPENSSL=/usr/bin/openssl
legacy=()
"$OPENSSL" version | grep -q LibreSSL || legacy=(-legacy)

umask 077
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

cat > openssl.cnf <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no
default_md         = sha256

[ dn ]
CN = $CN
O  = Hoku open source project

[ codesign ]
basicConstraints     = critical, CA:FALSE
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
subjectKeyIdentifier = hash
EOF

print "→ creating key and certificate (RSA 3072, SHA-256, $DAYS days)"
"$OPENSSL" req -x509 -new -newkey rsa:3072 -nodes -days "$DAYS" \
    -set_serial "0x$("$OPENSSL" rand -hex 16)" \
    -config openssl.cnf -keyout hoku-release-signing.key -out hoku-release-signing.pem

"$OPENSSL" x509 -in hoku-release-signing.pem -noout -text | grep -A1 -E "Key Usage|Basic Constraints|Not After" || true

export P12_PASSWORD="$("$OPENSSL" rand -base64 33 | tr -d '/+=\n' | cut -c1-32)"
print "→ exporting PKCS#12"
"$OPENSSL" pkcs12 -export "${legacy[@]}" \
    -inkey hoku-release-signing.key -in hoku-release-signing.pem \
    -name "$CN" -out hoku-release-signing.p12 -passout env:P12_PASSWORD
print -r -- "$P12_PASSWORD" > hoku-release-signing.p12.password
rm -f hoku-release-signing.key          # the private key now only lives inside the .p12

SHA1=$("$OPENSSL" x509 -in hoku-release-signing.pem -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
# Expected DR; compare with `codesign -d -r- Hoku.app` after the first real signing.
print -r -- "designated => identifier \"$BUNDLE_ID\" and certificate root = H\"${(L)SHA1}\"" > designated-requirement.txt

if (( IMPORT )); then
    print -n "Import '$CN' into your login keychain (only /usr/bin/codesign may use the key)? [y/N] "
    read -r answer
    if [[ $answer == [yY] ]]; then
        security import hoku-release-signing.p12 -k "$HOME/Library/Keychains/login.keychain-db" \
            -P "$P12_PASSWORD" -f pkcs12 -T /usr/bin/codesign
        # Listed as CSSMERR_TP_NOT_TRUSTED is expected for a self-signed identity.
        security find-identity -p codesigning | grep -i "$SHA1" || true

        print "→ smoke test: signing a throwaway binary by hash (no trust settings changed)"
        smoke=$(mktemp -d)
        cp /usr/bin/true "$smoke/hoku-smoke"
        if codesign --force --sign "$SHA1" --timestamp=none --identifier "$BUNDLE_ID" "$smoke/hoku-smoke"; then
            codesign -d -r- "$smoke/hoku-smoke" 2>&1 | grep designated
            print "  ✓ codesign accepts the untrusted self-signed identity"
        else
            print -u2 "  ✗ codesign refused the identity – see release-pipeline.md §1.1 (trust it for Code Signing once)"
        fi
        rm -rf "$smoke"
    fi
fi

if [[ -n $GH_REPO ]]; then
    command -v gh >/dev/null || die "gh not installed"
    print "→ setting GitHub secrets in environment '$GH_ENV' of $GH_REPO (values are not printed)"
    base64 -i hoku-release-signing.p12 | gh secret set HOKU_SIGNING_P12_BASE64 --env "$GH_ENV" --repo "$GH_REPO"
    print -rn -- "$P12_PASSWORD" | gh secret set HOKU_SIGNING_P12_PASSWORD --env "$GH_ENV" --repo "$GH_REPO"
    gh variable set HOKU_SIGN_SHA1 --body "$SHA1" --repo "$GH_REPO"
fi
unset P12_PASSWORD

cat <<EOF

✓ Done. Files in $OUT_DIR:
    hoku-release-signing.p12            private key + certificate   (SECRET)
    hoku-release-signing.p12.password   its password                (SECRET)
    hoku-release-signing.pem            public certificate          (may be published)
    designated-requirement.txt          → commit as .github/signing/designated-requirement.txt

  SHA-1: $SHA1   (→ GitHub variable HOKU_SIGN_SHA1, README "Signatur prüfen")

NOW, before anything else:
  1. Store the .p12 AND its password in your password manager.
  2. Store a second copy offline (USB stick in a drawer).
  3. Then delete the two secret files here:  rm hoku-release-signing.p12 hoku-release-signing.p12.password
  Losing them means every user has to grant permissions again; leaking them means
  someone else can ship code macOS treats as Hoku (there is no revocation).
EOF
