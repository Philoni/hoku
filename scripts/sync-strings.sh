#!/bin/zsh
# Brings the string catalogs up to date with the texts in the source code:
# builds once with string extraction on, then merges new keys into the catalogs
# and marks vanished ones as stale. Translations already entered stay untouched.
#   scripts/sync-strings.sh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
DERIVED="$ROOT/build/StringsDerivedData.noindex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

xcodegen generate --quiet
xcodebuild -project Hoku.xcodeproj -scheme Hoku -configuration Debug -derivedDataPath "$DERIVED" -quiet build \
    SWIFT_EMIT_LOC_STRINGS=YES HOKU_AWAY_REMINDER=YES CODE_SIGNING_ALLOWED=NO
# Only the installed copy may be registered (see scripts/build-app.sh).
"$LSREGISTER" -u "$DERIVED/Build/Products/Debug/Hoku.app" 2>/dev/null || true

# sync <target> <catalog>…: each catalog receives the strings of its own table.
sync() {
    local target=$1 args=()
    shift
    for file in "$DERIVED"/Build/Intermediates.noindex/$target.build/**/*.stringsdata(N); do
        args+=(--stringsdata "$file")
    done
    (( ${#args} )) || { echo "Keine Texte für $target gefunden." >&2; exit 1; }
    xcrun xcstringstool sync "$@" "${args[@]}"
    print -l "✓ "${^@}
}
sync Hoku App/Localizable.xcstrings App/AppShortcuts.xcstrings
sync HueKit Packages/HueKit/Sources/HueKit/Resources/Localizable.xcstrings
