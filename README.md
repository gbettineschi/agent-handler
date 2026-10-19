# Agent Handler

A small native macOS companion for agent questions, built around an independent request controller and a minimal notch interface.

**Development build.** Native Codex/ChatGPT Work questions and one real app-approval flow have passed. Shell and browser-origin approvals still need native acceptance tests. Work turn activity is tracked; regular ChatGPT Chat is deferred. A read-only Claude local-audit observer is implemented and fixture-tested, but a fresh native Claude turn remains unverified and Claude response delivery is not implemented. Cloud-only Claude chats without local audits are unsupported. The Desktop adapter uses private IPC and can require maintenance after host updates. See the [coverage audit](docs/surface-audit.md) and [verification record](docs/verification.md).

The large-conversation disconnect is fixed: unused snapshot data is discarded during decoding rather than after exhausting the parser's node limit. The full 112-test suite passes, and a real pending question was recovered across app restart, answered through Agent Handler, and cleared. A fresh eligible app approval still needs its post-fix live check.

## Run locally

Requires macOS 14+ and a Swift 6 toolchain. No package downloads or API keys are needed.

```sh
scripts/test.sh
scripts/bundle.sh
open "dist/Agent Handler.app" --args --demo
```

Quit the demo from the **AH** menu before starting the live connection:

```sh
open "dist/Agent Handler.app"
```

The app starts collapsed and remains available through the **AH** menu. On a notched display a small indicator expands into the request queue; other displays use the menu and floating panel. Close the panel with its × button or Escape; pending requests remain in the queue. It does not bring the panel forward for each incoming question. Settings select a display, enable the Desktop connection and accept additional conversation IDs. Use `--show` only when you explicitly want an expanded launch.

The live adapter observes at most 16 recent local conversations, prioritizing already-pending requests and explicitly selected IDs. Local metadata supplies candidates; only a verified owner stream makes a question actionable. Discovery uses `state_5.sqlite`; an unsupported metadata schema requires explicit IDs until its adapter is updated. `CODEX_HOME` is honored when supplied to the process, otherwise `~/.codex` is used.

## Core guarantees and limits

- Independent request IDs: simultaneous questions do not replace one another.
- Responses are tied to the displayed request fingerprint and native owner.
- An answer is durably reserved before sending; a socket write is not acceptance.
- Unconfirmed delivery remains uncertain and is never automatically retried, including after restart.
- Unknown state disables answering and preserves unresolved requests.
- A second live instance cannot acquire the same broker lock.

The source app remains responsible for executing agents and enforcing permissions. Unknown forms, unsupported versions and uncertain deliveries belong in the source app. The native protocol has a race between preflight and submission; this utility cannot manufacture a host-side atomic request check.

The private SQLite delivery ledger is stored in `~/Library/Application Support/AgentHandler`. It contains hashes, attempt IDs, status and timestamps, without question text, answers or transcripts. Demo data uses a separate temporary location and an in-memory ledger. No telemetry or network listener is included.

The build is ad-hoc signed for local development. It is not a notarized distribution, and launch-at-login registration may be unavailable until installed as a normal app. Automatic updates are not included.

## Development

The [approved design](docs/superpowers/specs/2026-10-19-agent-handler-design.md) and [implementation plan](docs/superpowers/plans/2026-10-19-first-desktop-companion.md) describe the boundaries and test strategy. Native state belongs to the provider adapter; request and delivery state belongs to the controller; the UI consumes snapshots.

Tests bind temporary Unix sockets for synthetic hosts and never connect to a real agent. A restricted development sandbox may need permission to bind those fixture sockets. The test script supports the Command Line Tools Swift Testing framework layout and keeps compiler caches inside `.build`.

After building tests, run `.build/debug/AgentHandlerDiagnostics --demo` for a synthetic controller check, or `--probe [--thread ID]` for a read-only native compatibility sample. The probe never submits an answer. `--claude-probe` separately reports read-only local-audit activity counts; it baselines existing files and has no response transport. See the [compatibility matrix](docs/compatibility.md) and [verification record](docs/verification.md) for measured results and pending manual checks.

See [third-party notices](THIRD_PARTY_NOTICES.md) for the narrow Agent HUD code adaptations and their Apache-2.0 license. This repository is private; original project code has no public license grant.
