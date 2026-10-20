#!/bin/bash
set -euo pipefail
RACKY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RACKY_ROOT"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
RACKY_RUNNING="$RACKY_ROOT/build/Racky.app/Contents/MacOS/Racky"
RACKY_BUILD_KEY="$(printf '%s' "$RACKY_ROOT" | shasum -a 256 | cut -c1-16)"
RACKY_CACHE_ROOT="$HOME/Library/Caches/Racky/Builds/$RACKY_BUILD_KEY"
RACKY_CACHED_APP="$RACKY_CACHE_ROOT/Racky.app"
if pgrep -f "^${RACKY_RUNNING}$" >/dev/null || pgrep -f "^${RACKY_CACHED_APP}/Contents/MacOS/Racky$" >/dev/null; then
  printf 'Feche o Racky antes de substituir o build em execução.\n' >&2
  exit 1
fi
swift build -c release
RACKY_BIN="$(swift build -c release --show-bin-path)"
RACKY_OUTPUT="$RACKY_ROOT/build/Racky.app"
# Stage outside file-provider folders; otherwise Finder metadata can reappear during signing.
RACKY_STAGE="$(mktemp -d /private/tmp/racky-package.XXXXXX)"
trap 'rm -rf "$RACKY_STAGE"' EXIT
RACKY_APP="$RACKY_STAGE/Racky.app"
mkdir -p "$RACKY_APP/Contents/MacOS" "$RACKY_APP/Contents/Resources"
mkdir -p "$RACKY_APP/Contents/Resources/Hooks"
cp "$RACKY_BIN/Racky" "$RACKY_APP/Contents/MacOS/Racky"
cp "$RACKY_BIN/RackyMCP" "$RACKY_APP/Contents/MacOS/RackyMCP"
install -m 755 "$RACKY_ROOT/runtime/hooks/claude_event.py" "$RACKY_APP/Contents/Resources/Hooks/claude_event.py"
for RACKY_RESOURCE in "$RACKY_BIN"/*.bundle; do
  [[ -d "$RACKY_RESOURCE" ]] || continue
  # SwiftPM resources can be read-only. Replace the generated bundle instead of overwriting its files.
  RACKY_RESOURCE_NAME="$(basename "$RACKY_RESOURCE")"
  rm -rf "$RACKY_APP/Contents/Resources/$RACKY_RESOURCE_NAME"
  cp -R "$RACKY_RESOURCE" "$RACKY_APP/Contents/Resources/"
done
cp "$RACKY_ROOT/Sources/Racky/Resources/Brands/Racky.icns" "$RACKY_APP/Contents/Resources/Racky.icns"
cat > "$RACKY_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Racky</string>
<key>CFBundleIdentifier</key><string>local.racky.app</string>
<key>CFBundleName</key><string>Racky</string>
<key>CFBundleDisplayName</key><string>Racky</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>Racky</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSDocumentsFolderUsageDescription</key><string>Abrir projetos e executar os terminais nas pastas que você escolher.</string>
<key>NSDesktopFolderUsageDescription</key><string>Abrir projetos selecionados na Mesa.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Abrir arquivos de trabalho e downloads selecionados.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Finder may attach presentation metadata after the previous local launch.
# Remove only those two generated-bundle attributes; preserve other attributes.
xattr -rd com.apple.FinderInfo "$RACKY_APP" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$RACKY_APP" 2>/dev/null || true
codesign --force --deep --sign - "$RACKY_APP"
codesign --verify --deep --strict "$RACKY_APP"
mkdir -p "$RACKY_ROOT/build"
# A File Provider may immediately reattach FinderInfo to a bundle in Documents,
# even after signing in /private/tmp. Keep the executable development bundle in
# the local cache; the checkout exposes a link, not another synchronized copy.
mkdir -p "$RACKY_CACHE_ROOT"
rm -rf "$RACKY_CACHED_APP"
mv "$RACKY_APP" "$RACKY_CACHED_APP"
codesign --verify --deep --strict "$RACKY_CACHED_APP"
rm -rf "$RACKY_OUTPUT"
ln -s "$RACKY_CACHED_APP" "$RACKY_OUTPUT"
codesign --verify --deep --strict "$RACKY_OUTPUT"
printf 'App: %s\n' "$RACKY_OUTPUT"
