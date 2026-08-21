#!/usr/bin/env bash

set -euo pipefail

# Emit a markdown changelog: a heading line, a blank line, then one bullet per
# non-merge commit in a range. This is the single definition shared by the three
# publish workflows (main/beta/release) and publish.sh, so the format only ever
# lives in one place.
#
# Usage: changelog.sh <previous_ref> <current_ref> [heading]
#
#   previous_ref  Tag/commit the range starts after. If empty, falls back to the
#                 last 20 commits (first release, no prior tag).
#   current_ref   Tag/commit the range ends at (defaults to HEAD).
#   heading       Markdown heading printed above the commits (e.g. "## v1.2.3").
#                 Omitted -> just the bullet list.

previous_ref="${1:-}"
current_ref="${2:-HEAD}"
heading="${3:-}"

if [[ -n "$previous_ref" ]]; then
    commits=$(git log --pretty=format:"- %s" "${previous_ref}..${current_ref}" --no-merges)
else
    commits=$(git log --pretty=format:"- %s" --no-merges -20)
fi

if [[ -n "$heading" ]]; then
    printf '%s\n\n%s\n' "$heading" "$commits"
else
    printf '%s\n' "$commits"
fi
