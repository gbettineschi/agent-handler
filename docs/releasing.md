# Releasing Agent Handler

The release workflow already builds a universal Apple silicon/Intel app. No signing secrets are needed: builds are ad-hoc signed, not notarized.

1. Run `bash scripts/test.sh`. Commit the release source and push it to this repository.
2. Tag that commit, for example `git tag v0.1.0`, then push the tag with `git push origin v0.1.0`.
3. Wait for **Package macOS app** to finish. It tests the app, verifies both architectures, and publishes `AgentHandler.zip`, `SHA256SUMS` and `agent-handler.rb`.
4. Download **that release's** `agent-handler.rb` and copy it to `Casks/agent-handler.rb` in [gbettineschi/Tetherbug](https://github.com/gbettineschi/Tetherbug), which serves the `gbettineschi/tetherbug` tap. Commit and push the cask. It pins the checksum of the ZIP built in that workflow run.
5. Check the release download and `brew info --cask gbettineschi/tetherbug/agent-handler` after the tap has updated.

Do not use a locally rebuilt ZIP's checksum for a workflow-built download. Rebuilds can differ. The generated cask must accompany the exact ZIP it describes.

For a local packaging check without publishing:

```sh
APP_VERSION=0.1.0 APP_UNIVERSAL=1 bash scripts/package.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
```

Running the workflow manually uploads build artifacts without publishing a release. Use a new version tag for each public release; keep previous tags and downloads intact. Homebrew updates are manual (`brew update`, then `brew upgrade --cask gbettineschi/tetherbug/agent-handler`); the app has no built-in updater.
