#!/bin/bash
#
# release.sh - Build and release the Axon Bridge VS Code extension
#
# Creates versioned releases in the releases/ folder with automatic
# manifest generation for dynamic download links.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASES_DIR="$PROJECT_DIR/releases"

# Get version from package.json
VERSION=$(node -p "require('$PROJECT_DIR/package.json').version")
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create date folder if needed
DATE_DIR="$RELEASES_DIR/$DATE"
mkdir -p "$DATE_DIR"

echo "Building Axon Bridge v$VERSION..."

# Compile TypeScript
cd "$PROJECT_DIR"
npm run compile

# Package the extension
npm run package

# Move VSIX to releases folder with versioned name
VSIX_NAME="axon-bridge-$VERSION.vsix"
VSIX_PATH="$DATE_DIR/$VSIX_NAME"

mv "$PROJECT_DIR/axon-bridge-$VERSION.vsix" "$VSIX_PATH"

echo "Created: $VSIX_PATH"

# Also create/update a "latest" symlink
LATEST_DIR="$RELEASES_DIR/latest"
mkdir -p "$LATEST_DIR"
cp "$VSIX_PATH" "$LATEST_DIR/axon-bridge-latest.vsix"

# Update the releases manifest
MANIFEST_FILE="$RELEASES_DIR/releases.json"

# Read existing manifest or create new one
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST=$(cat "$MANIFEST_FILE")
else
    MANIFEST='{"releases":[]}'
fi

# Create new release entry
NEW_RELEASE=$(cat <<EOF
{
    "version": "$VERSION",
    "date": "$DATE",
    "timestamp": "$TIMESTAMP",
    "filename": "$VSIX_NAME",
    "path": "$DATE/$VSIX_NAME",
    "downloadUrl": "https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/$DATE/$VSIX_NAME",
    "changelog": "Remote Mode support - VS Code can now act as server for LAN connections from Axon"
}
EOF
)

# Add to manifest (prepend to releases array)
echo "$MANIFEST" | node -e "
const fs = require('fs');
let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
    const manifest = JSON.parse(data);
    const newRelease = $NEW_RELEASE;

    // Remove any existing release with same version
    manifest.releases = manifest.releases.filter(r => r.version !== newRelease.version);

    // Add new release at the beginning
    manifest.releases.unshift(newRelease);

    // Update latest pointer
    manifest.latest = {
        version: newRelease.version,
        downloadUrl: newRelease.downloadUrl,
        latestUrl: 'https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix'
    };

    console.log(JSON.stringify(manifest, null, 2));
});
" > "$MANIFEST_FILE"

echo ""
echo "Release complete!"
echo "  Version:  $VERSION"
echo "  Date:     $DATE"
echo "  File:     $VSIX_PATH"
echo ""
echo "Download URLs:"
echo "  Specific: https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/$DATE/$VSIX_NAME"
echo "  Latest:   https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix"
echo ""
echo "Manifest:   $MANIFEST_FILE"
