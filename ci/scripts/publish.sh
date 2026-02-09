#!/bin/bash

set -euo pipefail

# Usage examples:
#   ./publish.sh           # defaults to patch
#   ./publish.sh patch     # explicit patch
#   ./publish.sh none      # skip bump, just publish
#
#   or with pre-release types:
#   ./publish.sh minor alpha
#

bump_type="${1:-patch}"
pre_release_type="${2:-}"
branch="${3:-main}"

echo "Bumping (or reading) version ($bump_type) [prerelease: $pre_release_type]..."
raw_version="$(./ci/scripts/version.sh "$bump_type" "$pre_release_type")"
new_version="$(echo "$raw_version" | tr -d '[:cntrl:]')"

echo "Version to publish: [$new_version]"

echo "Committing version bump (if any changes)..."
git add .
git commit -m "Bump version to $new_version" || {
    echo "No changes to commit (or commit failed)."
}

last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -z "$last_tag" ]]; then
    echo "No previous tags found, so we may be generating a full changelog from the start."
    last_tag=$(git rev-list --max-parents=0 HEAD)
fi

new_tag="v${new_version}"
echo "Creating new tag: $new_tag"
git tag -a "$new_tag" -m "Release $new_version"

echo ""
echo "Tag created: $new_tag"
echo ""
echo "To push to remote and create a GitHub release, run:"
echo "  git push origin $branch"
echo "  git push origin $new_tag"
echo ""
echo "To create a CurseForge release:"
echo "  1. Run: ./ci/scripts/package.sh"
echo "  2. Upload the zip from ci/dist/ to CurseForge"
