#!/bin/bash
set -euo pipefail
AGENTBOX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$AGENTBOX_ROOT"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
AGENTBOX_RUNNING="$AGENTBOX_ROOT/build/Agent Box.app/Contents/MacOS/AgentBox"
if pgrep -f "^${AGENTBOX_RUNNING}$" >/dev/null; then
  printf 'Feche o Agent Box antes de substituir o build em execução.\n' >&2
  exit 1
fi
swift build -c release
AGENTBOX_BIN="$(swift build -c release --show-bin-path)"
AGENTBOX_OUTPUT="$AGENTBOX_ROOT/build/Agent Box.app"
# Stage outside file-provider folders; otherwise Finder metadata can reappear during signing.
AGENTBOX_STAGE="$(mktemp -d /private/tmp/agentbox-package.XXXXXX)"
trap 'rm -rf "$AGENTBOX_STAGE"' EXIT
AGENTBOX_APP="$AGENTBOX_STAGE/Agent Box.app"
mkdir -p "$AGENTBOX_APP/Contents/MacOS" "$AGENTBOX_APP/Contents/Resources"
cp "$AGENTBOX_BIN/AgentBox" "$AGENTBOX_APP/Contents/MacOS/AgentBox"
cp "$AGENTBOX_BIN/AgentBoxMCP" "$AGENTBOX_APP/Contents/MacOS/AgentBoxMCP"
for AGENTBOX_RESOURCE in "$AGENTBOX_BIN"/*.bundle; do
  [[ -d "$AGENTBOX_RESOURCE" ]] || continue
  # SwiftPM resources can be read-only. Replace the generated bundle instead of overwriting its files.
  AGENTBOX_RESOURCE_NAME="$(basename "$AGENTBOX_RESOURCE")"
  rm -rf "$AGENTBOX_APP/Contents/Resources/$AGENTBOX_RESOURCE_NAME"
  cp -R "$AGENTBOX_RESOURCE" "$AGENTBOX_APP/Contents/Resources/"
done
cp "$AGENTBOX_ROOT/Sources/AgentBox/Resources/Brands/AgentBox.icns" "$AGENTBOX_APP/Contents/Resources/AgentBox.icns"
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
<key>CFBundleIconFile</key><string>AgentBox</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSDocumentsFolderUsageDescription</key><string>Abrir projetos e executar os terminais nas pastas que você escolher.</string>
<key>NSDesktopFolderUsageDescription</key><string>Abrir projetos selecionados na Mesa.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Abrir arquivos de trabalho e downloads selecionados.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Finder may attach presentation metadata after the previous local launch.
# Remove only those two generated-bundle attributes; preserve other attributes.
xattr -rd com.apple.FinderInfo "$AGENTBOX_APP" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$AGENTBOX_APP" 2>/dev/null || true
codesign --force --deep --sign - "$AGENTBOX_APP"
codesign --verify --deep --strict "$AGENTBOX_APP"
mkdir -p "$AGENTBOX_ROOT/build"
rm -rf "$AGENTBOX_OUTPUT"
mv "$AGENTBOX_APP" "$AGENTBOX_OUTPUT"
codesign --verify --deep --strict "$AGENTBOX_OUTPUT"
printf 'App: %s\n' "$AGENTBOX_OUTPUT"
