#!/bin/bash
set -e
APP_NAME="Stat"
APP_REPO="vladstudio/stat"
APP_PATH="/Applications/$APP_NAME.app"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "↓ Downloading $APP_NAME"
curl -fsSL "https://github.com/$APP_REPO/releases/latest/download/$APP_NAME.zip" -o "$TMP/$APP_NAME.zip"

echo "Extracting"
ditto -xk "$TMP/$APP_NAME.zip" "$TMP"
[ -d "$TMP/$APP_NAME.app" ] || { echo "Archive did not contain $APP_NAME.app"; exit 1; }

pkill -x "$APP_NAME" 2>/dev/null || true
[ -w /Applications ] && SUDO= || SUDO=sudo
$SUDO rm -rf "$APP_PATH"
$SUDO ditto "$TMP/$APP_NAME.app" "$APP_PATH"

open "$APP_PATH"
echo "✓ $APP_NAME installed"