#!/bin/bash
set -euo pipefail
SUF="${SUF:-}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
S="$(cd "$(dirname "$0")" && pwd)"
APP="$S/ABS01.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"
swiftc -O -target arm64-apple-macos15.0 "$S/daemon.swift" -o "$APP/Contents/MacOS/s01d-real"
swiftc -O -target arm64-apple-macos15.0 "$S/launcher.swift" -o "$APP/Contents/MacOS/s01d"
swiftc -O -target arm64-apple-macos15.0 "$S/host.swift" -o "$APP/Contents/MacOS/ABS01"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.agentbox.s01test$SUF</string>
<key>CFBundleName</key><string>ABS01</string>
<key>CFBundleExecutable</key><string>ABS01</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>${BV:-1}</string>
<key>CFBundleShortVersionString</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
cat > "$APP/Contents/Library/LaunchAgents/app.agentbox.ptyd.test-s01$SUF.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>app.agentbox.ptyd.test-s01$SUF</string>
<key>BundleProgram</key><string>Contents/MacOS/s01d</string>
<key>AssociatedBundleIdentifiers</key><array><string>app.agentbox.s01test$SUF</string></array>
<key>ProcessType</key><string>Interactive</string>
<key>AbandonProcessGroup</key><true/>
<key>KeepAlive</key><false/>
<key>EnvironmentVariables</key><dict><key>S01_LOG</key><string>/tmp/s01-daemon.log</string></dict>
<key>Sockets</key><dict><key>Listeners</key><dict>
  <key>SecureSocketWithKey</key><string>AGENTBOX_PTYD_SOCK_V1</string>
  <key>SockPathMode</key><integer>384</integer>
</dict></dict>
</dict></plist>
EOF
# Variante sem SMAppService (launchctl bootstrap): Program absoluto, outro label.
sed -e 's#<key>BundleProgram</key><string>Contents/MacOS/s01d</string>#<key>Program</key><string>'"$APP"'/Contents/MacOS/s01d</string>#' \
    -e 's#test-s01#test-s01b#' -e '/AssociatedBundleIdentifiers/d' \
    "$APP/Contents/Library/LaunchAgents/app.agentbox.ptyd.test-s01$SUF.plist" > "$S/app.agentbox.ptyd.test-s01${SUF}b.plist"
codesign --force --options runtime --sign - --identifier app.agentbox.ptyd.real "$APP/Contents/MacOS/s01d-real"
codesign --force --options runtime --sign - --identifier app.agentbox.ptyd "$APP/Contents/MacOS/s01d"
codesign --force --options runtime --sign - --identifier app.agentbox.s01test$SUF "$APP"
codesign --verify --strict "$APP" && echo built-adhoc
