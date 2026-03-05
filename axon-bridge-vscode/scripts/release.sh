#!/bin/bash
#
# release.sh - Build and release the Axon Bridge VS Code extension
#
# Creates versioned releases in the releases/ folder with automatic
# manifest generation for dynamic download links.
# cd axon-bridge-vscode/scripts && bash release.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASES_DIR="$PROJECT_DIR/releases"
MANIFEST_FILE="$RELEASES_DIR/releases.json"
README_FILE="$PROJECT_DIR/README.md"

# Get current version from package.json
CURRENT_VERSION=$(node -p "require('$PROJECT_DIR/package.json').version")

# Auto-bump patch version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
NEW_PATCH=$((PATCH + 1))
VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# Generate timestamps
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HUMAN_TIME=$(date +"%m%d%Y_at_%I%M%p")
RELEASE_DATETIME=$(date +"%B %d, %Y at %I:%M %p")

# Create date folder if needed
DATE_DIR="$RELEASES_DIR/$DATE"
mkdir -p "$DATE_DIR"

# Get changelog from git commits since last release tag (or last 10 commits)
cd "$PROJECT_DIR"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
    CHANGELOG=$(git log --oneline "$LAST_TAG"..HEAD 2>/dev/null | head -20 | sed 's/^[a-f0-9]* /- /' || echo "- Various improvements and bug fixes")
else
    CHANGELOG=$(git log --oneline -10 2>/dev/null | sed 's/^[a-f0-9]* /- /' || echo "- Various improvements and bug fixes")
fi

# If no commits found, use default message
if [ -z "$CHANGELOG" ]; then
    CHANGELOG="- Various improvements and bug fixes"
fi

# VSIX filename with timestamp
VSIX_NAME="axon-bridge-${VERSION}_${HUMAN_TIME}.vsix"
VSIX_PATH="$DATE_DIR/$VSIX_NAME"

echo "═══════════════════════════════════════════════════════════════"
echo "  Building Axon Bridge v$VERSION"
echo "  Previous version: $CURRENT_VERSION"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Update package.json with new version using Node
node -e "
const fs = require('fs');
const pkgPath = '$PROJECT_DIR/package.json';
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.version = '$VERSION';
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
console.log('Updated package.json to v$VERSION');
"

# Compile TypeScript
echo ""
echo "Compiling TypeScript..."
npm run compile

# Package the extension
echo ""
echo "Packaging extension..."
npm run package

# Move VSIX to releases folder with versioned name + timestamp
mv "$PROJECT_DIR/axon-bridge-$VERSION.vsix" "$VSIX_PATH"
echo ""
echo "Created: $VSIX_PATH"

# Also create/update a "latest" copy
LATEST_DIR="$RELEASES_DIR/latest"
mkdir -p "$LATEST_DIR"
cp "$VSIX_PATH" "$LATEST_DIR/axon-bridge-latest.vsix"

# Export variables for Node scripts
export MANIFEST_FILE README_FILE VERSION DATE TIMESTAMP HUMAN_TIME RELEASE_DATETIME VSIX_NAME CHANGELOG

# Update the releases manifest using Node with proper JSON handling
node << 'NODESCRIPT'
const fs = require('fs');

const manifestFile = process.env.MANIFEST_FILE;
const version = process.env.VERSION;
const date = process.env.DATE;
const timestamp = process.env.TIMESTAMP;
const humanTime = process.env.HUMAN_TIME;
const vsixName = process.env.VSIX_NAME;
const changelog = process.env.CHANGELOG;

// Read existing manifest or create new one
let manifest = { releases: [] };
try {
    const existing = fs.readFileSync(manifestFile, 'utf8');
    if (existing.trim()) {
        manifest = JSON.parse(existing);
    }
} catch (e) {
    // File doesn't exist or is invalid, use default
}

const newRelease = {
    version: version,
    date: date,
    timestamp: timestamp,
    humanTime: humanTime,
    filename: vsixName,
    path: `${date}/${vsixName}`,
    downloadUrl: `https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/${date}/${vsixName}`,
    changelog: changelog
};

// Remove any existing release with same version
manifest.releases = manifest.releases.filter(r => r.version !== version);

// Add new release at the beginning
manifest.releases.unshift(newRelease);

// Update latest pointer
manifest.latest = {
    version: version,
    downloadUrl: newRelease.downloadUrl,
    latestUrl: 'https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix'
};

fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
console.log('Updated releases.json');
NODESCRIPT

# Update README with release info using Node
node << 'NODESCRIPT'
const fs = require('fs');

const readmeFile = process.env.README_FILE;
const version = process.env.VERSION;
const releaseDateTime = process.env.RELEASE_DATETIME;
const vsixName = process.env.VSIX_NAME;
const date = process.env.DATE;
const changelog = process.env.CHANGELOG;

let readme = fs.readFileSync(readmeFile, 'utf8');

// Build release info section
const releaseInfo = `## Current Release

**Version ${version}** - Released ${releaseDateTime}

**Filename:** \`${vsixName}\`

### Changes in this release:
${changelog}

### Download
- [Download Latest VSIX](https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix)
- [Download This Version](https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/${date}/${vsixName})

---

`;

// Remove existing 'Current Release' section if present
readme = readme.replace(/## Current Release[\s\S]*?---\s*\n/m, '');

// Find insertion point (before ## Features)
const insertPoint = readme.indexOf('## Features');
if (insertPoint !== -1) {
    readme = readme.slice(0, insertPoint) + releaseInfo + readme.slice(insertPoint);
}

fs.writeFileSync(readmeFile, readme);
console.log('Updated README.md with release info');
NODESCRIPT

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RELEASE COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Version:    $VERSION (was $CURRENT_VERSION)"
echo "  Date/Time:  $RELEASE_DATETIME"
echo "  Filename:   $VSIX_NAME"
echo ""
echo "  File Location:"
echo "    $VSIX_PATH"
echo ""
echo "  Download URLs:"
echo "    Latest:   https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix"
echo "    Specific: https://github.com/tooury/Axon/raw/main/axon-bridge-vscode/releases/$DATE/$VSIX_NAME"
echo ""
echo "  Changes:"
echo "$CHANGELOG"
echo ""
echo "  Updated Files:"
echo "    - package.json (version bump)"
echo "    - README.md (release info)"
echo "    - releases/releases.json (manifest)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
