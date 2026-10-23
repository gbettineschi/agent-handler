#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bundle.sh
codesign --verify --deep --strict 'dist/Agent Handler.app'
ditto -c -k --sequesterRsrc --keepParent 'dist/Agent Handler.app' dist/AgentHandler.zip
(cd dist && shasum -a 256 AgentHandler.zip > SHA256SUMS)
printf '%s\n' 'Created dist/AgentHandler.zip and dist/SHA256SUMS'
