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
# Requires GH_TOKEN env var for git push and GitHub release creation.
# Set it in your .env file or pass it to docker run:
#   docker run -e GH_TOKEN=ghp_xxx ...
#

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "Error: GH_TOKEN environment variable is not set."
    echo "Create a GitHub PAT at https://github.com/settings/tokens"
    echo "Then add GH_TOKEN=ghp_xxx to your .env file."
    exit 1
fi

# Configure git to use the token for HTTPS pushes
git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password=${GH_TOKEN}"; }; f'

# gh CLI also uses GH_TOKEN automatically
export GH_TOKEN

bump_type="${1:-patch}"
pre_release_type="${2:-}"
branch="${3:-develop}"

echo "Bumping (or reading) version ($bump_type) [prerelease: $pre_release_type]..."
raw_version="$(./ci/scripts/version.sh "$bump_type" "$pre_release_type")"
new_version="$(echo "$raw_version" | tr -d '[:cntrl:]')"

echo "Version to publish: [$new_version]"

last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -z "$last_tag" ]]; then
    echo "No previous tags found, generating changelog from initial commit."
    last_tag=$(git rev-list --max-parents=0 HEAD)
fi

# Generate changelog using Claude Code CLI
if command -v claude &> /dev/null; then
    echo "Generating changelog with Claude Code..."

    diff_output=$(git diff "$last_tag"..HEAD --stat)
    commit_log=$(git log "$last_tag"..HEAD --pretty=format:"- %s" --no-merges)
    changed_files=$(git diff "$last_tag"..HEAD --name-only)

    changelog_prompt="Generate a changelog entry for version $new_version of a WoW tank addon called TankAssist.

Previous tag: $last_tag

Commits since last release:
$commit_log

Files changed:
$changed_files

Diff stats:
$diff_output

Output ONLY the changelog section in this exact format (no extra text):
## [$new_version] - $(date +%Y-%m-%d)

### Added
- (list new features, or remove section if none)

### Changed
- (list changes, or remove section if none)

### Fixed
- (list bug fixes, or remove section if none)

Be concise. Group related changes. Skip empty sections."

    changelog_entry=$(echo "$changelog_prompt" | claude --print 2>/dev/null || echo "")

    if [[ -n "$changelog_entry" ]]; then
        echo "Updating CHANGELOG.md..."

        # Insert new entry after the [Unreleased] section
        if [[ -f "CHANGELOG.md" ]]; then
            # Create temp file with new entry inserted
            awk -v entry="$changelog_entry" '
                /^## \[Unreleased\]/ {
                    print
                    print ""
                    print entry
                    next
                }
                { print }
            ' CHANGELOG.md > CHANGELOG.md.tmp
            mv CHANGELOG.md.tmp CHANGELOG.md
            echo "Changelog updated."
        fi
    else
        echo "Claude Code not available or failed, skipping auto-changelog."
    fi
else
    echo "Claude Code CLI not found, skipping auto-changelog."
fi

echo "Committing version bump and changelog..."
git add *.toc CHANGELOG.md .github/ ci/ core/ ui/ specs/ data/ libs/
git commit -m "Bump version to $new_version" || {
    echo "No changes to commit (or commit failed)."
}

new_tag="v${new_version}"
echo "Creating new tag: $new_tag"
git tag -a "$new_tag" -m "Release $new_version"

echo ""
echo "Pushing to remote..."
git push origin "$branch"
git push origin "$new_tag"

echo "Packaging addon..."
./ci/scripts/package.sh

# Find the packaged zip file
zip_file=$(find ci/dist -name "*.zip" | head -n 1)

if [[ -z "$zip_file" ]]; then
    echo "Warning: No zip file found in ci/dist/, skipping GitHub release asset upload."
fi

# Build release notes from changelog entry
release_notes=""
if [[ -n "${changelog_entry:-}" ]]; then
    release_notes="$changelog_entry"
else
    release_notes="Release $new_version"
fi

# Create GitHub release with the tag
if command -v gh &> /dev/null; then
    echo "Creating GitHub release for $new_tag..."

    gh_args=(
        "$new_tag"
        --title "Release $new_version"
        --notes "$release_notes"
    )

    # Mark as pre-release if it contains alpha/beta/rc
    if [[ "$new_version" == *alpha* ]] || [[ "$new_version" == *beta* ]] || [[ "$new_version" == *rc* ]]; then
        gh_args+=(--prerelease)
    fi

    gh release create "${gh_args[@]}"

    # Upload zip as release asset if available
    if [[ -n "$zip_file" ]]; then
        echo "Uploading $zip_file to release..."
        gh release upload "$new_tag" "$zip_file" --clobber
        echo "Release asset uploaded."
    fi

    echo ""
    echo "GitHub release created: $new_tag"
else
    echo "gh CLI not found, skipping GitHub release creation."
    echo ""
    echo "To create a GitHub release manually, run:"
    echo "  gh release create $new_tag --title \"Release $new_version\" --notes-file CHANGELOG.md"
fi

echo ""
echo "To upload to CurseForge:"
if [[ -n "$zip_file" ]]; then
    echo "  Upload $zip_file to CurseForge"
else
    echo "  1. Run: ./ci/scripts/package.sh"
    echo "  2. Upload the zip from ci/dist/ to CurseForge"
fi
