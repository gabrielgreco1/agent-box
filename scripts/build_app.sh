#!/bin/bash
set -euo pipefail
AGENTBOX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$AGENTBOX_ROOT"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release
AGENTBOX_BIN="$(swift build -c release --show-bin-path)"
AGENTBOX_APP="$AGENTBOX_ROOT/build/Agent Box.app"
mkdir -p "$AGENTBOX_APP/Contents/MacOS" "$AGENTBOX_APP/Contents/Resources"
cp "$AGENTBOX_BIN/AgentBox" "$AGENTBOX_APP/Contents/MacOS/AgentBox"
cp -R "$AGENTBOX_BIN/AgentBox_AgentBox.bundle" "$AGENTBOX_APP/Contents/Resources/"
cat > "$AGENTBOX_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentBox</string>
<key>CFBundleIdentifier</key><string>local.agentbox.app</string>
<key>CFBundleName</key><string>Agent Box</string>
<key>CFBundleDisplayName</key><string>Agent Box</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$AGENTBOX_APP"
printf 'App: %s\n' "$AGENTBOX_APP"
