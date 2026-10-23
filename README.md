<img src="assets/AppIcon.png" width="80" alt="Agent Handler icon">

# Agent Handler

A small macOS app that keeps an eye on your agents while you do something else.

See which Codex sessions are running, answer questions and handle supported approvals from the menu bar or notch. The panel can open when something needs you, then get out of the way. Finished sessions clear after five minutes.

**The app is fully vibe-coded and built for my own use** when a Codex update in autumn 2026 made unreliable all the existing similar apps. The app and repository are provided as is, without warranty or promised support.**

<img src="docs/images/ui/notch-sessions.png" width="520" alt="Agent Handler notch panel showing example sessions">

## Install

Requires **macOS 14 or later**.

Download `AgentHandler.zip` from [Releases](https://github.com/gbettineschi/agent-handler/releases), when available. Unzip it, move **Agent Handler.app** to Applications, and open it. Release builds support Apple silicon and Intel.

The app is ad-hoc signed, not notarized. macOS may block downloaded builds; see [Apple’s instructions](https://support.apple.com/102445) if you choose to open one.

Or build locally with a **matching Swift 6 toolchain and macOS SDK**:

```sh
git clone https://github.com/gbettineschi/agent-handler.git
cd agent-handler
./scripts/install.sh
```

This installs into `~/Applications`. Quit Agent Handler before updating it. To use another folder, pass it to the installer: `./scripts/install.sh /Applications`.

## A few things to know

- Codex local Work sessions are the main supported surface. Regular ChatGPT Chat is not tracked.
- Claude local activity observation is experimental and read-only; answering Claude prompts is not supported.
- The Codex connection uses private Desktop APIs and may break after updates. Uncertain answers are never automatically resent.
- Click the menu-bar agent to open it, or choose **Notch** in Settings and hover. Escape hides the panel; the header’s **× quits the app**.

## Development

`scripts/test.sh` runs the tests. `scripts/bundle.sh` builds the app; `scripts/package.sh` creates an installable ZIP and checksum. The **Package macOS app** GitHub workflow builds a universal download manually; pushing a `v0.1.0`-style tag also publishes a release.

[Coverage and remaining checks](docs/verification.md) · [Architecture](docs/superpowers/specs/2026-10-19-agent-handler-design.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
