#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 ]]; then
  printf '%s\n' 'Usage: scripts/install.sh [destination folder]' >&2
  exit 1
fi
ensure_stopped() {
  if pgrep -u "$(id -u)" -x 'AgentHandler|AgentHandlerApp' >/dev/null; then
    printf '%s\n' 'Quit Agent Handler before installing or updating it.' >&2
    exit 1
  fi
}
ensure_stopped
destination="${1:-$HOME/Applications}"
target="$destination/Agent Handler.app"
if [[ -L "$target" ]] || { [[ -e "$target" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)" != dev.gbettineschi.agent-handler ]]; }; then
  printf '%s\n' 'The destination already contains an unrelated item named Agent Handler.app.' >&2
  exit 1
fi
bash scripts/bundle.sh
ensure_stopped
mkdir -p "$destination"
staging="$(mktemp -d "$destination/.agent-handler.XXXXXX")"
cleanup() {
  if [[ -d "$staging/previous.app" && ! -e "$target" ]]; then
    if ! mv "$staging/previous.app" "$target"; then
      printf 'Previous app preserved at %s\n' "$staging/previous.app" >&2
      return
    fi
  fi
  rm -rf "$staging"
}
trap cleanup EXIT
ditto 'dist/Agent Handler.app' "$staging/Agent Handler.app"
codesign --verify --deep --strict "$staging/Agent Handler.app"
if [[ -e "$target" ]]; then mv "$target" "$staging/previous.app"; fi
mv "$staging/Agent Handler.app" "$target"
printf 'Installed: %s\nOpen it in Finder to start tracking.\n' "$target"
