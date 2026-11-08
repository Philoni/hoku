#!/bin/zsh
# Builds Hoku with Xcode (signed with your Apple Development certificate),
# installs it to ~/Applications and launches it. Pass --no-install to only build.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
APP_NAME="Hoku"
INSTALL_DIR="$HOME/Applications"
# ".noindex" keeps Spotlight away from build products: no extra "Hoku" in search results.
DERIVED="$ROOT/build/DerivedData.noindex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Team ID = the OU of your "Apple Development" certificate (free Apple ID works).
if [[ -z "${HOKU_TEAM:-}" ]]; then
    HOKU_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi
if [[ -z "$HOKU_TEAM" ]]; then
    echo "Kein Apple-Development-Zertifikat gefunden. In Xcode: Einstellungen → Accounts → Apple ID → Manage Certificates → +." >&2
    exit 1
fi
export HOKU_TEAM

echo "→ xcodegen (Team $HOKU_TEAM)"
xcodegen generate --quiet

echo "→ xcodebuild"
# Local builds include features not yet released (App/Support/Features.swift);
# HOKU_AWAY_REMINDER=NO ./scripts/build-app.sh builds exactly what the public gets.
xcodebuild -project Hoku.xcodeproj -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build \
    HOKU_AWAY_REMINDER="${HOKU_AWAY_REMINDER:-YES}"

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ "${1:-}" == "--no-install" ]]; then
    # Xcode registers what it builds; only an installed copy should be known to macOS.
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    echo "✓ built $APP"
    exit 0
fi

echo "→ installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
osascript -e "tell application id \"io.github.philoni.hoku\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.5
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/"
# Only the installed copy may be registered: with several copies of the same bundle ID
# (Xcode's build products), Siri and Shortcuts pick the wrong one and show no actions.
find "$DERIVED/Build/Products" -name "$APP_NAME.app" -maxdepth 2 -exec "$LSREGISTER" -u {} \; 2>/dev/null || true
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME.app"
open "$INSTALL_DIR/$APP_NAME.app"
echo "✓ $APP_NAME läuft – schau oben in die Menüleiste."
