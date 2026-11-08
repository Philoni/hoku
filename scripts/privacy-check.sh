#!/bin/zsh
# Fails if files meant for the public contain personal data.
#   scripts/privacy-check.sh            checks the committed files (without docs/internal)
#   scripts/privacy-check.sh <folder>   checks a folder, e.g. a public export
# Generic checks run always. Personal patterns (your e-mail, name, IDs …) live in the
# git-ignored file .privacy-patterns.local, one extended regex per line, so they never
# end up in the repository themselves.
set -euo pipefail
ROOT="${0:A:h:h}"
TARGET="${1:-}"

if [[ -n "$TARGET" ]]; then
    files=("${(@f)$(cd "$TARGET" && find . -type f ! -path './.git/*' | sed 's#^\./##')}")
    base="$TARGET"
else
    files=("${(@f)$(cd "$ROOT" && git ls-files --cached --others --exclude-standard | grep -v '^docs/internal/')}")
    base="$ROOT"
fi

generic=(
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # e-mail addresses (allow-list below)
    '/Users/[A-Za-z0-9._-]+'                           # home folders
    'DEVELOPMENT_TEAM: *[A-Z0-9]{10}'                  # a hard-coded Apple Team ID
    '(192\.168|10\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+'  # private IPs
    '\b[0-9a-f]{16}\b'                                 # bridge IDs (contain the MAC)
)
allowed='users\.noreply\.github\.com|noreply@anthropic\.com|example\.(com|org)|192\.168\.1\.20|001788fffe[0-9a-f]{6}|0{16}|f{16}'

patterns=("${generic[@]}")
if [[ -f "$ROOT/.privacy-patterns.local" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        patterns+=("$line")
    done < "$ROOT/.privacy-patterns.local"
else
    echo "Hinweis: keine .privacy-patterns.local – nur allgemeine Prüfungen." >&2
fi

found=0
for file in "${files[@]}"; do
    [[ -z "$file" || ! -f "$base/$file" ]] && continue
    # Skip binaries (icons, images).
    if ! grep -Iq . "$base/$file" 2>/dev/null; then continue; fi
    for pattern in "${patterns[@]}"; do
        hits=$(grep -noE -- "$pattern" "$base/$file" 2>/dev/null | grep -vE "$allowed" || true)
        if [[ -n "$hits" ]]; then
            # Show where, but mask the value itself.
            echo "$hits" | while IFS=: read -r line match; do
                masked="${match:0:3}…${match: -2}"
                echo "✗ $file:$line  $masked"
            done
            found=1
        fi
    done
done

if (( found )); then
    echo "Persönliche Daten gefunden – nicht veröffentlichen." >&2
    exit 1
fi
echo "✓ Keine persönlichen Daten gefunden (${#files[@]} Dateien geprüft)."
