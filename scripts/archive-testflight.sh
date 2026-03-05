#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../ios"
ARCHIVE_DIR="$SCRIPT_DIR/../build/archives"
PROJECT_YML="$PROJECT_DIR/project.yml"

echo "=== Kuri TestFlight Archive ==="

# 1. Bump build number
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: $CURRENT_BUILD/CURRENT_PROJECT_VERSION: $NEW_BUILD/" "$PROJECT_YML"
echo "[1/5] Build number: $CURRENT_BUILD → $NEW_BUILD"

# 2. Regenerate Xcode project
cd "$PROJECT_DIR"
xcodegen generate --quiet
echo "[2/5] Xcode project regenerated"

# 3. Resolve SPM packages
xcodebuild -resolvePackageDependencies \
  -project Kuri.xcodeproj \
  -scheme KuriApp \
  -quiet
echo "[3/5] Packages resolved"

# 4. Archive
ARCHIVE_PATH="$ARCHIVE_DIR/Kuri-$NEW_BUILD.xcarchive"
mkdir -p "$ARCHIVE_DIR"
xcodebuild archive \
  -project Kuri.xcodeproj \
  -scheme KuriApp \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_STYLE=Automatic \
  -quiet
echo "[4/5] Archived → $ARCHIVE_PATH"

# 5. Upload to App Store Connect
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
  -exportPath "$ARCHIVE_DIR/export-$NEW_BUILD" \
  -quiet
echo "[5/5] Uploaded build $NEW_BUILD to App Store Connect"
echo ""
echo "Check TestFlight in ~15 minutes for processing."
