#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --product AgentHandlerApp
objects=()
for module in AgentHandlerApp AgentHandlerCore CodexDesktopAdapter ClaudeDesktopAdapter; do
  for source in "Sources/$module/"*.swift; do
    name="${source##*/}"
    # The fixture has its own main.
    [[ "$module/$name" == "AgentHandlerApp/AppMain.swift" ]] && continue
    object=".build/debug/$module.build/$name.o"
    [[ -f "$object" ]] && objects+=("$object")
  done
done
swiftc -parse-as-library -I .build/debug/Modules -I Sources/CSQLite \
  Tests/Visuals/RenderUI.swift "${objects[@]}" -lsqlite3 -o .build/render-ui
.build/render-ui "${1:-.build/ui-snapshots}"
