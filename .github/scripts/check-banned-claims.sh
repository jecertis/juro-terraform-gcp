#!/usr/bin/env bash
# check-banned-claims.sh
#
# Vendored from juro-platform/scripts/check-banned-claims.sh.
# Source of truth for the canonical banned-claims policy lives at
# juro-platform/contracts/banned-claims.md; that repo is private, so
# cross-repo checkout from this workflow fails on the default
# GITHUB_TOKEN. Vendoring eliminates the cross-repo dependency.
#
# When the canonical list changes, update the BANNED_PHRASES /
# UNSUPPORTED_REGULATIONS arrays below and the same arrays in any
# other repo's vendored copy. juro-platform/scripts/propagate-agent-preamble.sh
# is the propagation entry point.
#
# Fails if marketing copy contains claims that contradict
# juro-workspace/AXIOMS.md or VISION.md. Run against README files,
# package.json, and any other customer-facing marketing surface.
#
# Usage:
#   ./check-banned-claims.sh <file> [<file>...]
#
# Exits 0 if clean, 1 if any banned claim is found.

set -euo pipefail

# Phrases that overclaim compliance posture or product category.
BANNED_PHRASES=(
  "SOC 2 compliant"
  "SOC2 compliant"
  "SOC 2 certified"
  "SOC2 certified"
  "enterprise-grade"
  "Enterprise-Grade"
  "enterprise grade"
  "AI-powered compliance"
  "trust management platform"
  "Trust Center"
  "trust center"
  "GRC platform"
  "complete compliance platform"
  "comprehensive compliance platform"
)

# Regulations Juro does not support as primary targets.
# (GDPR, DORA, DPDP are in scope — see juro-workspace/AXIOMS.md)
UNSUPPORTED_REGULATIONS=(
  "MiCA"
  "AI Act"
  "HIPAA"
  "ISO 27001"
  "ISO27001"
  "OWASP Top 10"
  "PCI DSS"
  "NIS2"
)

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <file> [<file>...]" >&2
  exit 2
fi

found=0

check_phrase() {
  local phrase="$1"
  local file="$2"
  local label="$3"
  if grep -Fn -- "$phrase" "$file" > /dev/null 2>&1; then
    echo "✗ ${label}: \"${phrase}\" in ${file}"
    grep -Fn -- "$phrase" "$file" | sed 's/^/    /'
    found=1
  fi
}

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "warn: ${file} not found, skipping" >&2
    continue
  fi

  for phrase in "${BANNED_PHRASES[@]}"; do
    check_phrase "$phrase" "$file" "banned claim"
  done

  for reg in "${UNSUPPORTED_REGULATIONS[@]}"; do
    check_phrase "$reg" "$file" "unsupported regulation"
  done
done

if [[ $found -eq 1 ]]; then
  echo ""
  echo "Fix: align copy with juro-workspace/AXIOMS.md and VISION.md."
  echo "Canonical banned-claim list: juro-platform/contracts/banned-claims.md"
  exit 1
fi

echo "✓ no banned claims found in $#  file(s)"
