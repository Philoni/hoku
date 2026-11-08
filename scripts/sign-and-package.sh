#!/bin/zsh
#
# Signs a built (unsigned) Hoku.app with the long-lived self-signed identity
# "Hoku Release Signing", runs the signature guard and packages a Sparkle-ready zip.
# Single source of truth for release signing: used by .github/workflows/release.yml
# and by `make release-zip`.
#
# Usage: scripts/sign-and-package.sh <path/to/Hoku.app> <version> <out-dir>
#
# Environment:
#   HOKU_SIGN_SHA1          SHA-1 (40 hex chars) of the "Hoku Release Signing" certificate (required)
#   HOKU_KEYCHAIN           keychain holding the identity (optional; CI uses a temporary keychain)
#   HOKU_EXPECTED_DR_FILE   expected `designated => …` line (default: .github/signing/designated-requirement.txt)
#   HOKU_SPARKLE_KEY_FILE   expected SUPublicEDKey (default: .github/signing/sparkle-public-key.txt, skipped if missing)
#   HOKU_PREVIOUS_APP       previous release's Hoku.app – the new build must satisfy its DR (optional)
set -euo pipefail

APP=${1:?usage: sign-and-package.sh <Hoku.app> <version> <out-dir>}
VERSION=${2:?version missing}
OUT=${3:?out-dir missing}
ROOT="${0:A:h:h}"
BUNDLE_ID="io.github.philoni.hoku"
CERT_CN="Hoku Release Signing"
EXPECTED_DR_FILE=${HOKU_EXPECTED_DR_FILE:-$ROOT/.github/signing/designated-requirement.txt}
SPARKLE_KEY_FILE=${HOKU_SPARKLE_KEY_FILE:-$ROOT/.github/signing/sparkle-public-key.txt}

die()  { print -u2 "✗ $*"; exit 1; }
step() { print "→ $*"; }

sha_re='^[0-9A-Fa-f]{40}$'
[[ ${HOKU_SIGN_SHA1:-} =~ $sha_re ]] || die "HOKU_SIGN_SHA1 must be the 40-hex SHA-1 of '$CERT_CN'"
[[ -d $APP ]] || die "no app at $APP"
[[ -f $EXPECTED_DR_FILE ]] || die "expected DR file missing: $EXPECTED_DR_FILE"

plist="$APP/Contents/Info.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") == "$BUNDLE_ID" ]] || die "wrong bundle id"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") == "$VERSION" ]] \
    || die "CFBundleShortVersionString != $VERSION"

# Sign by certificate hash: no name matching, and codesign does not require the
# self-signed certificate to be trusted (man codesign, SIGNING IDENTITIES).
# Verified per release by the checks below; if codesign ever refuses, trust the certificate for code signing.
sign_args=(--force --sign "$HOKU_SIGN_SHA1" --options runtime --timestamp=none)
[[ -n ${HOKU_KEYCHAIN:-} ]] && sign_args+=(--keychain "$HOKU_KEYCHAIN")
sign() { codesign "${sign_args[@]}" "$@"; }

# ---------------------------------------------------------------- 1. nested code, inside out
fw="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d $fw ]]; then
    step "Sparkle.framework"
    # Hoku is not sandboxed, so Sparkle's XPC services are unused (Sparkle docs: "Sandboxing").
    # Remove the top-level symlink too, otherwise strict verification sees a dangling link.
    # Re-check this layout for every Sparkle upgrade (2.10.0: Versions/B).
    rm -f "$fw/XPCServices"
    rm -rf "$fw/Versions/B/XPCServices"
    sign "$fw/Versions/B/Autoupdate"
    sign "$fw/Versions/B/Updater.app"
    sign "$fw"
fi
for nested in "$APP"/Contents/Frameworks/*(N) "$APP"/Contents/PlugIns/*(N); do
    [[ $nested == "$fw" ]] && continue
    step "nested: ${nested:t}"
    sign "$nested"
done

# ---------------------------------------------------------------- 2. the app itself
step "Hoku.app"
work=$(mktemp -d -t hoku-sign)
trap 'rm -rf "$work"' EXIT
entitlements="$work/release.entitlements"
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Hardened runtime library validation only accepts code from Apple or the same Team ID.
	     A self-signed identity has no Team ID, so Sparkle.framework would be rejected
	     ("mapped file has no Team ID … signed with custom identity or adhoc?"). -->
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST
sign --entitlements "$entitlements" "$APP"

# ---------------------------------------------------------------- 3. signature guard
step "signature guard"
codesign --verify --deep --strict --verbose=2 "$APP" || die "codesign --verify --deep --strict failed"

info=$(codesign -dvvv "$APP" 2>&1)
grep -qx "Identifier=$BUNDLE_ID"        <<<"$info" || die "unexpected Identifier"
grep -qx "Authority=$CERT_CN"           <<<"$info" || die "not signed by '$CERT_CN'"
grep -qx "TeamIdentifier=not set"       <<<"$info" || die "unexpected Team ID (wrong certificate?)"
grep -q  "flags=.*runtime"              <<<"$info" || die "hardened runtime flag missing"

actual_dr=$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')
expected_dr=$(sed -n 's/^designated => //p' "$EXPECTED_DR_FILE")
[[ -n $expected_dr ]] || die "no 'designated => …' line in $EXPECTED_DR_FILE"
if [[ $actual_dr != "$expected_dr" ]]; then
    print -u2 "expected: $expected_dr"
    print -u2 "actual:   $actual_dr"
    die "designated requirement changed – users would lose their permissions"
fi
[[ $actual_dr == *"certificate leaf = H\"${(L)HOKU_SIGN_SHA1}\""* || $actual_dr == *"certificate root = H\"${(L)HOKU_SIGN_SHA1}\""* ]] || die "DR does not pin the release certificate"
codesign --verify --strict -R "=$expected_dr" "$APP" || die "app does not satisfy its own expected DR"

nested_bad=()
while IFS= read -r -d '' f; do
    file -b "$f" | grep -q 'Mach-O' || continue
    # Capture first: with pipefail, grep -q closing the pipe early would fail the whole line.
    nested_info=$(codesign -dvv "$f" 2>&1 || true)
    grep -qx "Authority=$CERT_CN" <<<"$nested_info" || nested_bad+=("$f")
done < <(find "$APP/Contents" -type f -perm -u+x -print0)
(( ${#nested_bad} == 0 )) || die "code not signed with '$CERT_CN': ${nested_bad[*]}"

codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'disable-library-validation' \
    || die "entitlement disable-library-validation missing"

if [[ -f $SPARKLE_KEY_FILE ]]; then
    key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)
    [[ $key == "$(<"$SPARKLE_KEY_FILE")" ]] || die "SUPublicEDKey differs from $SPARKLE_KEY_FILE"
fi

if [[ -n ${HOKU_PREVIOUS_APP:-} ]]; then
    step "compare with previous release"
    old_dr=$(codesign -d -r- "$HOKU_PREVIOUS_APP" 2>&1 | sed -n 's/^designated => //p')
    # Same check Sparkle (SUCodeSigningVerifier) and TCC perform: new code must satisfy the old DR.
    codesign --verify --strict -R "=$old_dr" "$APP" || die "new build does not satisfy the previous release's DR"
    exe="Contents/MacOS/Hoku"
    old_uuids=$(dwarfdump --uuid "$HOKU_PREVIOUS_APP/$exe" | awk '{print $2}' | sort)
    new_uuids=$(dwarfdump --uuid "$APP/$exe" | awk '{print $2}' | sort)
    # Local network privacy uses the main executable UUID (TN3179) – it must be unique per build.
    [[ $old_uuids != "$new_uuids" ]] || die "main executable UUID unchanged since previous release"
fi

# Not notarized: Gatekeeper rejection is expected. Logged for information only.
spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true

# ---------------------------------------------------------------- 4. package
mkdir -p "$OUT"
zip="$OUT/Hoku-$VERSION.zip"
rm -f "$zip"
step "zip → $zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip"

check_dir="$work/zipcheck"
mkdir -p "$check_dir"
ditto -x -k "$zip" "$check_dir"
codesign --verify --deep --strict "$check_dir/Hoku.app" || die "signature broken inside the zip"
[[ $(codesign -d -r- "$check_dir/Hoku.app" 2>&1 | sed -n 's/^designated => //p') == "$expected_dr" ]] \
    || die "DR differs inside the zip"
# The extracted copy must not stay registered with LaunchServices (duplicates confuse Siri).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$check_dir/Hoku.app" >/dev/null 2>&1 || true

( cd "$OUT" && shasum -a 256 "${zip:t}" > "${zip:t}.sha256" )
print "✓ $(cat "$OUT/${zip:t}.sha256")"
print "✓ designated => $actual_dr"
