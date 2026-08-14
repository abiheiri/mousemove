#!/bin/bash
# Extract one version's section from CHANGELOG.md (Keep a Changelog format).
# Usage: ./extract-changelog.sh <version> [changelog-path]
# Prints the body between "## [<version>]" and the next "## [" heading (or EOF).
set -e

VERSION="${1:?Usage: ./extract-changelog.sh <version> [changelog-path]}"
CHANGELOG="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"

[ -f "$CHANGELOG" ] || { echo "❌ Changelog not found: $CHANGELOG" >&2; exit 1; }

SECTION=$(awk -v version="$VERSION" '
  $0 ~ "^## \\[" version "\\]" { found=1; next }
  found && /^## \[/ { exit }
  found { print }
' "$CHANGELOG" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

[ -n "$SECTION" ] || { echo "❌ No changelog section found for version $VERSION" >&2; exit 1; }

printf '%s\n' "$SECTION"
