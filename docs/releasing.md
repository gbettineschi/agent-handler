# Releasing Agent Handler

The release workflow already builds a universal Apple silicon/Intel app. No signing secrets are needed: builds are ad-hoc signed, not notarized.

1. Run `bash scripts/test.sh`. Commit the release source and push it to this repository.
2. Tag that commit, for example `git tag v0.1.0`, then push the tag with `git push origin v0.1.0`.
3. Wait for **Package macOS app** to finish. It tests the app, verifies both architectures, and publishes `AgentHandler.zip`, `SHA256SUMS` and `agent-handler.rb`.
4. The dependent **tap** job downloads that published ZIP, computes its checksum and updates `Casks/agent-handler.rb` in [gbettineschi/homebrew-tap](https://github.com/gbettineschi/homebrew-tap) automatically. No manual cask commit is needed.
5. Check `brew info --cask gbettineschi/tap/agent-handler` after updating the tap. If only catalog publication failed, re-run the failed job or run **Update Homebrew tap** with the existing release tag. Do not rebuild or replace a published ZIP just to retry the tap.

The one-time `TAP_DEPLOY_KEY` Actions secret can write only to the shared tap. The matching public deploy key is stored on that repository. No personal GitHub token or Apple signing key is needed. The catalog refuses older versions and changed checksums for an existing version.

Do not use a locally rebuilt ZIP's checksum for a workflow-built download. Rebuilds can differ. The generated cask must accompany the exact ZIP it describes.

For a local packaging check without publishing:

```sh
APP_VERSION=0.1.0 APP_UNIVERSAL=1 bash scripts/package.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
```

Running the workflow manually builds and verifies the packages without uploading installers or publishing a release. Routine CI keeps tests and builds, saving UI diagnostics only on failure for one day. Tagged releases upload installers directly to GitHub Releases; no duplicate Actions installer artifact is kept. Use a new version tag for each public release; keep previous tags and downloads intact. Homebrew updates are manual (`brew update`, then `brew upgrade --cask gbettineschi/tap/agent-handler`); the app has no built-in updater.
