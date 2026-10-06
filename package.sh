#!/usr/bin/env bash
# Builds a CurseForge-ready zip containing only the addon code.
# Usage: ./package.sh [version]   (defaults to `git describe`)
set -euo pipefail

cd "$(dirname "$0")"

ADDON="EnhancedQuestTracker"
VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
RELEASE_DIR=".release"
STAGE="$RELEASE_DIR/$ADDON"
ZIP="$RELEASE_DIR/$ADDON-$VERSION.zip"

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE"

cp -r src media "$STAGE/"
cp LICENSE "$STAGE/"
sed "s/@project-version@/$VERSION/g" "$ADDON.toc" > "$STAGE/$ADDON.toc"

(cd "$RELEASE_DIR" && zip -rq "$(basename "$ZIP")" "$ADDON")
rm -rf "$STAGE"

echo "Created $ZIP"
