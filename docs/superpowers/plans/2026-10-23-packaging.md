# App packaging

> **For agentic workers:** Use superpowers:executing-plans for inline execution.

**Goal:** Give the personal app a simple icon, straightforward installation and a short public-facing README.

**Architecture:** Keep the existing Swift app and adapters. Commit an original robot icon; bundle it with the app. Reuse the bundle script for installation and ZIP packaging. A manual/tag workflow builds a universal app and publishes only on a version tag.

**Tech stack:** AppKit drawing, Swift Package Manager, shell scripts, GitHub Actions.

## Constraints

- Keep the repository private; do not create a release tag for this task.
- Preserve delivery behavior, permissions and third-party attribution.
- State 100% vibe-coded, personal use and as-is in the README.
- No notarization, automatic updater, extra dependencies or license changes.

## Work

- [x] Create and inspect a blue robot icon at macOS icon sizes; include it in the signed bundle.
- [x] Add source installation and ZIP packaging; add a manual/tag universal-build workflow.
- [x] Replace the long README with brief features, installation, caveats and development links.
- [x] Check native and universal bundles, extracted ZIP signatures, installer copy and running-app refusal. Review the final diff.
- [ ] Push the working branch and fast-forward the default branch only if it has no independent commits; run the manual packaging workflow without publishing a release.

## Review focus

Bundle paths with spaces; Intel and Apple silicon; preserving the installed app when a build fails; rejecting an unrelated installation target; keeping unnotarized-build instructions honest; release metadata matching its tag.
