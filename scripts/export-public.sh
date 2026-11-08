#!/bin/zsh
# Creates the public copy of Hoku in a new folder: the committed files without
# docs/internal (private planning), checked by scripts/privacy-check.sh, as one fresh
# commit under the anonymous GitHub identity. The private history stays here.
#   scripts/export-public.sh ~/Developer/hoku-public
set -euo pipefail
ROOT="${0:A:h:h}"
TARGET="${1:?Aufruf: scripts/export-public.sh <neuer-ordner>}"
NAME="Philoni"
EMAIL="276918645+Philoni@users.noreply.github.com"

if [[ -e "$TARGET" ]]; then
    echo "Ziel existiert schon: $TARGET" >&2
    exit 1
fi
mkdir -p "$TARGET"
cd "$ROOT"
git archive HEAD | tar -x -C "$TARGET"
rm -rf "$TARGET/docs/internal"

"$ROOT/scripts/privacy-check.sh" "$TARGET"

cd "$TARGET"
git init -q -b main
git add -A
git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "Hoku – initial public release"
git config user.name "$NAME"
git config user.email "$EMAIL"
echo "✓ Öffentliche Kopie: $TARGET ($(git ls-files | wc -l | tr -d ' ') Dateien, 1 Commit als $NAME)"
