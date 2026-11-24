#!/usr/bin/env bash

set -euo pipefail

# Resolves the CurseForge game version for this addon and proves CurseForge
# actually knows it.
#
# The version is derived from the .toc's "## Interface" line rather than being
# hand-written into each publish workflow: 120100 -> 12.1.0. One source means
# bumping the .toc for a new patch cannot leave the workflows behind, which is
# exactly how this broke: b17028e set the workflows to "12.1" while CurseForge
# names retail versions with all three parts.
#
# The result is then checked against CurseForge's own version list, because
# itsmeow/curseforge-upload fails *silently* on a name it cannot resolve. It
# filters the API's version list by name and slug, finds nothing, and uploads
# with an empty gameVersions array; CurseForge then labels the file with a
# default version of its own choosing. 0.4.6-beta.60de652 shipped as "3.80.2"
# that way. An unresolvable version has to be a red build, not a quietly
# mislabelled file.
#
# Usage: game_version.sh [override]
#
#   override  Publish against this version instead of the derived one. Used by
#             main.yaml's workflow_dispatch input. Validated the same way.
#
# Env:
#   CURSEFORGE_TOKEN  Enables validation. Absent or unreachable, the derived
#                     version is emitted with a warning rather than failing the
#                     publish on someone else's outage.
#   GAME_ENDPOINT     CurseForge endpoint to validate against (default "wow").

override="${1:-}"
endpoint="${GAME_ENDPOINT:-wow}"

derive_from_toc() {
    local toc iface len
    toc=$(find "$(pwd)" -maxdepth 1 -name "*.toc" | head -n 1)
    if [[ -z "$toc" ]]; then
        echo "game_version: no .toc file found in $(pwd)" >&2
        exit 1
    fi

    iface=$(awk -F': ' '/^## Interface:/ {print $2}' "$toc" | tr -d '\r' | tr -d '[:space:]')
    if [[ ! "$iface" =~ ^[0-9]{5,6}$ ]]; then
        echo "game_version: '## Interface: $iface' in $toc is not a 5- or 6-digit build number" >&2
        exit 1
    fi

    # The last two digit pairs are always minor and patch; whatever precedes
    # them is the major, so this holds for 5-digit Classic builds (11507 ->
    # 1.15.7) as well as 6-digit retail ones (120100 -> 12.1.0).
    len=${#iface}
    echo "$((10#${iface:0:len-4})).$((10#${iface:len-4:2})).$((10#${iface:len-2:2}))"
}

if [[ -n "$override" ]]; then
    version="$override"
    echo "game_version: using override '$version'" >&2
else
    version=$(derive_from_toc)
    echo "game_version: derived '$version' from the .toc interface" >&2
fi

if [[ -z "${CURSEFORGE_TOKEN:-}" ]]; then
    echo "game_version: CURSEFORGE_TOKEN not set, skipping validation" >&2
    echo "$version"
    exit 0
fi

if ! versions=$(curl -fsS --max-time 30 -H "X-Api-Token: ${CURSEFORGE_TOKEN}" \
        "https://${endpoint}.curseforge.com/api/game/versions" 2>/dev/null); then
    echo "game_version: could not reach the CurseForge version API, publishing '$version' unvalidated" >&2
    echo "$version"
    exit 0
fi

if echo "$versions" | jq -e --arg v "$version" 'any(.[]; .name == $v or .slug == $v)' >/dev/null; then
    echo "game_version: CurseForge knows '$version'" >&2
    echo "$version"
    exit 0
fi

{
    echo "game_version: CurseForge does not list a game version named '$version'."
    echo ""
    echo "Uploading with it would not fail - the upload action would silently send an"
    echo "empty version list and CurseForge would label the file with a default."
    echo ""
    echo "Versions it does list under ${version%%.*}.x:"
    echo "$versions" | jq -r --arg p "${version%%.*}." '.[] | select(.name | startswith($p)) | .name' | sort -Vu | tail -15
} >&2
exit 1
