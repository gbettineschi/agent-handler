# Agent Handler

A small native macOS companion for agent questions, built around an independent request controller and a minimal notch interface.

**Development build.** Native Codex/ChatGPT Work questions, one real app-approval flow, and a live shell Allow through Agent Handler have passed. Shell deny/cancel and browser-origin approvals still need native acceptance tests. Work turn activity is tracked; regular ChatGPT Chat is deferred. A read-only Claude local-audit observer is implemented and fixture-tested, but a fresh native Claude turn remains unverified and Claude response delivery is not implemented. Cloud-only Claude chats without local audits are unsupported. The Desktop adapter uses private IPC and can require maintenance after host updates. See the [coverage audit](docs/surface-audit.md) and [verification record](docs/verification.md).

The large-conversation disconnect is fixed: unused snapshot data is discarded during decoding rather than after exhausting the parser's node limit. The snapshot fix passed the full 112-test suite, and a real pending question was recovered across app restart, answered through Agent Handler, and cleared. A fresh eligible app approval still needs its post-fix live check.

## Run locally

Requires macOS 14+ and a Swift 6 toolchain. No package downloads or API keys are needed.

```sh
scripts/test.sh
scripts/bundle.sh
open "dist/Agent Handler.app" --args --demo
```

Quit the demo from the **Agent Handler menu-bar icon** before starting the live connection:

```sh
open "dist/Agent Handler.app"
```

The app starts collapsed and remains available through the **Agent Handler menu-bar icon**. A compact top-center pill shows pending requests or working conversations, including on external displays. Click it to expand. Close the panel with its × button, Escape, or a click outside; pending requests and unfinished drafts remain in the queue. Incoming requests update the pill without expanding it or taking keyboard focus. The sessions view remains available with no pending requests and shows each observed session’s latest known turn status; the live panel has no tracking-count footer. Questions support Command-Return to send; approvals require an explicit button action. Settings select a display, enable the Desktop connection and expose connection details and additional conversation IDs. Approval scopes retain their exact source labels and wrap instead of truncating. Permission buttons have no default keyboard shortcut. Use `--show` only when you explicitly want an expanded launch.

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

The interface takes high-level inspiration from [Open Vibe Island](https://github.com/Octane0411/open-vibe-island), without copying its UI code or assets. It uses system typography and SF Symbols, labeled status, explicit permission actions, and no custom motion, following Apple’s [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [motion](https://developer.apple.com/design/human-interface-guidelines/motion) guidance.

For repeatable UI checks, run `bash scripts/render-ui.sh`. It renders synthetic states in unshown windows without contacting agents or taking over the screen. See the [visual review](docs/ui-review.md) for coverage and limitations.

See [third-party notices](THIRD_PARTY_NOTICES.md) for the narrow Agent HUD code adaptations and their Apache-2.0 license. This repository is private; original project code has no public license grant.
