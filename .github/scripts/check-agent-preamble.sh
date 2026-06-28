#!/usr/bin/env bash
# check-agent-preamble.sh
#
# Vendored from juro-platform/scripts/check-agent-preamble.sh.
# juro-platform is private, so cross-repo checkout from this
# workflow fails on the default GITHUB_TOKEN — vendoring removes
# that dependency. The canonical agent-preamble contract is
# vendored alongside this script at .github/contracts/agent-preamble.md.
#
# When juro-platform/contracts/agent-preamble.md is bumped, re-vendor
# both this script and the canonical contract here. The canonical
# propagation entry point is juro-platform/scripts/propagate-agent-preamble.sh.
#
# Verifies that the canonical agent preamble block appears verbatim
# in the files passed as arguments — typically CLAUDE.md and AGENTS.md
# in this repo's root.
#
# Version is extracted from the canonical file's opening marker:
#   <!-- juro:agent-preamble:vN -->
#
# Each target file must contain the same block, between the same
# versioned markers. Stale, missing, or modified blocks cause failure.
#
# Usage:
#   ./check-agent-preamble.sh <file> [<file>...]
#
# Exits 0 on success, 1 on any failure, 2 on usage errors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL="$SCRIPT_DIR/../contracts/agent-preamble.md"

if [[ ! -f "$CANONICAL" ]]; then
  echo "ERROR: canonical file not found at $CANONICAL" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <file> [<file>...]" >&2
  exit 2
fi

# Extract current version from canonical
CURRENT_VERSION=$(grep -oE '<!-- juro:agent-preamble:v[0-9]+ -->' "$CANONICAL" | head -1 | grep -oE 'v[0-9]+' || true)

if [[ -z "$CURRENT_VERSION" ]]; then
  echo "ERROR: no version marker found in canonical file" >&2
  exit 2
fi

# Extract canonical block (between markers, inclusive)
extract_block() {
  local file="$1"
  local version="$2"
  awk -v v="$version" '
    $0 ~ "<!-- juro:agent-preamble:" v " -->" { capture=1 }
    capture { print }
    $0 ~ "<!-- /juro:agent-preamble:" v " -->" { capture=0 }
  ' "$file"
}

CANONICAL_BLOCK=$(extract_block "$CANONICAL" "$CURRENT_VERSION")

if [[ -z "$CANONICAL_BLOCK" ]]; then
  echo "ERROR: canonical block for $CURRENT_VERSION not found in $CANONICAL" >&2
  exit 2
fi

FAILED=0

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "✗ $file: file not found"
    FAILED=1
    continue
  fi

  FILE_BLOCK=$(extract_block "$file" "$CURRENT_VERSION")

  if [[ -z "$FILE_BLOCK" ]]; then
    echo "✗ $file: preamble $CURRENT_VERSION not found"
    FAILED=1
    continue
  fi

  if [[ "$FILE_BLOCK" != "$CANONICAL_BLOCK" ]]; then
    echo "✗ $file: preamble $CURRENT_VERSION is stale or modified"
    diff <(echo "$CANONICAL_BLOCK") <(echo "$FILE_BLOCK") | head -20
    FAILED=1
    continue
  fi

  echo "✓ $file: preamble $CURRENT_VERSION matches canonical"
done

if [[ $FAILED -eq 1 ]]; then
  echo ""
  echo "Fix: run juro-platform/scripts/propagate-agent-preamble.sh <file>..."
  echo "     (or manually update each file to match $CANONICAL)"
  exit 1
fi

echo ""
echo "✓ all $# file(s) contain canonical preamble $CURRENT_VERSION"
