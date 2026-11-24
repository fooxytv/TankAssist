#!/usr/bin/env bash

set -euo pipefail

# Prints the tag a changelog range should start from.
#
# Usage: previous_tag.sh <scope> [ref]
#
#   scope  "stable"  the most recent non-prerelease tag (v1.2.3, never
#                    v1.2.3-alpha.abc1234)
#          "any"     the most recent tag of any kind
#   ref    Where to look back from (default HEAD)
#
# Betas and stables are read by people comparing against the last public
# release, so their range has to start at the last stable tag. Starting it at
# the nearest tag of *any* kind puts an internal alpha tag there instead:
# 0.4.6-beta.60de652 published a changelog of three unrelated 0.4.2 commits,
# because an alpha had been tagged on develop moments before the release branch
# was cut, leaving almost nothing in tag..HEAD.
#
# Alphas are incremental - each one is "what changed since the last alpha" - so
# scope "any" preserves that behaviour for main.yaml.
#
# Prints nothing and exits 0 when no such tag exists. Callers pass that through
# to changelog.sh, which falls back to recent history for a first release.

scope="${1:-stable}"
ref="${2:-HEAD}"

case "$scope" in
    stable)
        git describe --tags --abbrev=0 --match 'v*' \
            --exclude '*-alpha*' --exclude '*-beta*' --exclude '*-rc*' \
            "$ref" 2>/dev/null || true
        ;;
    any)
        git describe --tags --abbrev=0 "$ref" 2>/dev/null || true
        ;;
    *)
        echo "previous_tag: unknown scope '$scope' (expected 'stable' or 'any')" >&2
        exit 1
        ;;
esac
