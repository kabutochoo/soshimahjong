#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo 'Usage: TEAM_ID=<Apple Developer team ID> bash scripts/archive.sh'
    echo 'Creates a signed Release xcarchive on a Mac. Does not upload or submit it.'
    exit 0
fi

if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This command needs macOS and Xcode.' >&2
    exit 1
fi
if [[ -z "${TEAM_ID:-}" ]]; then
    echo 'Set TEAM_ID to your Apple Developer team ID, or archive using Xcode.' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
archive_path="${ARCHIVE_PATH:-$repo_root/DerivedData/Archives/Soshima.xcarchive}"
if [[ -e "$archive_path" ]]; then
    echo 'Archive already exists. Choose another ARCHIVE_PATH to keep the existing archive.' >&2
    exit 1
fi

xcodebuild -project "$repo_root/Soshima.xcodeproj" -scheme Soshima \
    -destination 'generic/platform=iOS' -configuration Release \
    -archivePath "$archive_path" DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates archive
