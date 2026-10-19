#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -c release --product AgentHandlerApp
app="$PWD/dist/Agent Handler.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/AgentHandlerApp "$app/Contents/MacOS/AgentHandler"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp -R LICENSES "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Agent Handler</string>
<key>CFBundleDisplayName</key><string>Agent Handler</string>
<key>CFBundleIdentifier</key><string>dev.gbettineschi.agent-handler</string>
<key>CFBundleExecutable</key><string>AgentHandler</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
