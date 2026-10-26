#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bundle.sh
codesign --verify --deep --strict 'dist/Agent Handler.app'
ditto -c -k --sequesterRsrc --keepParent 'dist/Agent Handler.app' dist/AgentHandler.zip
(cd dist && shasum -a 256 AgentHandler.zip > SHA256SUMS)
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' 'dist/Agent Handler.app/Contents/Info.plist')
checksum=$(awk '{print $1}' dist/SHA256SUMS)
cat > dist/agent-handler.rb <<CASK
cask "agent-handler" do
  version "$version"
  sha256 "$checksum"

  url "https://github.com/gbettineschi/agent-handler/releases/download/v#{version}/AgentHandler.zip"
  name "Agent Handler"
  desc "Agent questions and approvals from the menu bar or notch"
  homepage "https://github.com/gbettineschi/agent-handler"

  depends_on macos: :sonoma

  app "Agent Handler.app"

  uninstall quit: "dev.gbettineschi.agent-handler"

  caveats <<~EOS
    This personal build is ad-hoc signed and not notarized. If macOS blocks it,
    approve it in System Settings > Privacy & Security after trying to open it.
    Quit Agent Handler before upgrading.
  EOS
end
CASK
printf '%s\n' 'Created dist/AgentHandler.zip, dist/SHA256SUMS and dist/agent-handler.rb'
