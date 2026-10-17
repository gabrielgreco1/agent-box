#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DESIGN_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
PREVIEW_APP="$DESIGN_ROOT/Agent Box Preview.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources" "$DESIGN_ROOT/screens"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 \
  "$SOURCE_DIR/AgentBox.swift" "$SOURCE_DIR/Agents.swift" "$SOURCE_DIR/TerminalViews.swift" "$SOURCE_DIR/MotionAssetView.swift" \
  -o "$PREVIEW_APP/Contents/MacOS/AgentBoxPreview" \
  -framework SwiftUI -framework AppKit -framework AVKit
mkdir -p "$PREVIEW_APP/Contents/Resources/Brands"
cp "$DESIGN_ROOT"/assets/brands/*.png "$PREVIEW_APP/Contents/Resources/Brands/"
cp "$SOURCE_DIR"/Fonts/Manrope-*.ttf "$PREVIEW_APP/Contents/Resources/"
cp "$SOURCE_DIR/Info.plist" "$PREVIEW_APP/Contents/Info.plist"
for asset in box-loop.mp4 box-poster.png; do
  if [ -f "$DESIGN_ROOT/motion/$asset" ]; then cp "$DESIGN_ROOT/motion/$asset" "$PREVIEW_APP/Contents/Resources/"; fi
done
"$PREVIEW_APP/Contents/MacOS/AgentBoxPreview" --export "$DESIGN_ROOT/screens"
echo "Build concluído: $PREVIEW_APP"
