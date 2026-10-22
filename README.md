# Agent Handler

A small native macOS companion for agent questions, built around an independent request controller and a compact menu-bar interface.

**Development build.** Native Codex/ChatGPT Work questions, live shell Allow/Cancel, app Allow/Deny and browser-origin Allow/Deny through Agent Handler have passed, including automatic opening for blocking approvals. Work turn activity is tracked; regular ChatGPT Chat is deferred. A read-only Claude local-audit observer is implemented and fixture-tested, but a fresh native Claude turn remains unverified and Claude response delivery is not implemented. Cloud-only Claude chats without local audits are unsupported. The Desktop adapter uses private IPC and can require maintenance after host updates. See the [coverage audit](docs/surface-audit.md) and [verification record](docs/verification.md).

The large-conversation disconnect is fixed: unused snapshot data is discarded during decoding rather than after exhausting the parser's node limit. A real pending question was recovered across app restart, answered through Agent Handler, and cleared. Fresh shell Allow/Cancel, app Allow/Deny and browser Allow/Deny subsequently passed with automatic opening, source continuation/refusal and card withdrawal.

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

The app starts with a native **menu-bar agent icon** and no floating pill. Click the icon to open its panel; Control-click or right-click for commands. Escape, × or an outside click closes the panel. Questions support Command-Return to send; permissions require an explicit button action. The panel fits its current content automatically, growing down from the menu-bar item. Height is capped at 640 points or the available display space; longer content scrolls. Temporary conversation-catalog read failures preserve existing subscriptions and retry automatically. Settings has independent automatic-opening switches for blocking input (on by default), finished sessions (off), and non-blocking questions (off). Automatic opening keeps keyboard focus in your current app and leaves an already-open panel alone. Reopening the app bundle also opens its panel, which is useful while Ice hides its menu-bar item.

An automatically opened panel closes when its input is resolved, including any other unresolved requests that arrived meanwhile. Sending, uncertain delivery and unavailable source state do not count as resolution. A finish notice stays until its specific notified turns expire, are dismissed or resume; unrelated older finishes do not prolong it. Manual opening and Settings keep the panel open. Menu tracking delays closing without discarding incoming state.

Session rows identify the provider as Codex or Claude. New intervention requests appear first, newest first. The remaining rows move only after a finish, native human input or an intervention, with their order preserved through ordinary activity updates and restarts. A blue animated agent marks running rows. Codex can show a live activity hint such as Thinking or Running command from the latest native item; unsupported activity falls back to Running. These hints never determine completion or approval state. The Hidden menu restores finished sessions you dismissed.

The panel header shows the signed-in Codex account's remaining allowance and time until reset. It refreshes once a minute using the bundled Codex engine's read-only [app-server quota API](https://learn.chatgpt.com/docs/app-server), without starting a conversation or reading raw credentials. When several windows apply, the least remaining allowance is shown; hover for all windows and exact reset times. Crowded headers use a shorter label and keep reset details in the tooltip. Missing, stale or expired readings show `Codex —` until refreshed. The engine must already be signed in; Agent Handler never starts login, purchases credits or consumes a quota reset. Quota lookup pauses with tracking or sleep and is separate from request delivery.

The original monochrome menu-bar glyph moves while a session is working and stays still otherwise. Reduce Motion stops both agent animations, panel fade and height transitions. Shape badges distinguish attention, unavailable state, failure, recent completion and paused tracking. The number includes active sessions and finishes observed in the last five minutes, counted once per session. Finished rows disappear after five minutes; the saved deadline survives restarts. The countdown is not displayed. Historical completions first seen at launch get a five-minute display grace period without being counted or announced as new finishes. Existing completions at launch are not replayed as new finishes.

Finished rows have a small, muted × to dismiss that turn. A ten-second Undo (Command-Z in the sessions view) restores an accidental dismissal; the Hidden menu can recover a hidden finished row before its deadline. Both preserve its original expiry deadline. Observation continues, so a new turn, resumed work or unresolved input brings the session back. Current chat titles come from the verified native owner stream, with discovery metadata as a fallback. Settings contains connection details, launch at login and additional conversation IDs. Tab/Shift-Tab navigation follows the macOS Keyboard Navigation preference.

The live adapter observes at most 16 recent local conversations, prioritizing already-pending requests and explicitly selected IDs. Local metadata supplies candidates; only a verified owner stream makes a question actionable. Discovery uses `state_5.sqlite`; an unsupported metadata schema is reported in connection details while discovery retries automatically. `CODEX_HOME` is honored when supplied to the process, otherwise `~/.codex` is used.

Ordinary sessions disappear from the list immediately when their current activity becomes unavailable; observation continues and fresh activity brings them back. They are not declared completed. Actual unresolved questions/approvals stay visible, as do positively observed source-only permission waits through unknown gaps. These retained waits use Check Codex/Claude without gaining invented response controls. Requests that cannot be handled here show Review in Codex on that chat, with its title; they do not expire as finished sessions. Blocking auto-opening covers source-only requests, and an unknown gap does not count as resolution. Image attachments do not disable native question tracking; their bytes are not interpreted as questions or answers.

The panel opens directly below its visible menu-bar button, horizontally centered when space permits and clamped inside the display edges. Hidden/offscreen Ice positions are rejected. If the button cannot be located, a fresh opening uses the top-right of the active display. An already-open panel keeps its top and horizontal position when Ice hides the button; content changes resize downward. The full display locates the button, while the available work area bounds the panel, including displays with a side Dock.

## Core guarantees and limits

- Independent request IDs: simultaneous questions do not replace one another.
- Responses are tied to the displayed request fingerprint and native owner.
- An answer is durably reserved before sending; a socket write is not acceptance.
- Unconfirmed delivery remains uncertain and is never automatically retried, including after restart.
- Unknown state disables answering and preserves unresolved requests.
- A second live instance cannot acquire the same broker lock.

The source app remains responsible for executing agents and enforcing permissions. Unknown forms, unsupported versions and uncertain deliveries belong in the source app. The native protocol has a race between preflight and submission; this utility cannot manufacture a host-side atomic request check.

The private SQLite delivery ledger is stored in `~/Library/Application Support/AgentHandler`. It contains hashes, attempt IDs, status and timestamps, without question text, answers or transcripts. Separate bounded UI preferences store session, turn, native input and request identifiers, event order, dismissal state and observed finish times. Ordering, expiry and dismissals survive an app restart; no titles or message bodies are stored there. Demo data uses a separate temporary location and an in-memory ledger. No telemetry or network listener is included.

The build is ad-hoc signed for local development. It is not a notarized distribution, and launch-at-login registration may be unavailable until installed as a normal app. Automatic updates are not included.

## Development

The [approved design](docs/superpowers/specs/2026-10-19-agent-handler-design.md) and [implementation plan](docs/superpowers/plans/2026-10-19-first-desktop-companion.md) describe the boundaries and test strategy. Native state belongs to the provider adapter; request and delivery state belongs to the controller; the UI consumes snapshots.

Tests bind temporary Unix sockets for synthetic hosts and never connect to a real agent. A restricted development sandbox may need permission to bind those fixture sockets. The test script supports the Command Line Tools Swift Testing framework layout and keeps compiler caches inside `.build`.

Build the diagnostic executable with `swift build --product AgentHandlerDiagnostics`, then run `.build/debug/AgentHandlerDiagnostics --demo` for a synthetic controller check, or `--probe [--thread ID]` for a read-only native compatibility sample. The probe never submits an answer. It reports the connection and fixed observation-issue counts without native messages, answers, paths or error text; Settings → Connection details explains the same failures. A missing owner, changed protocol, tracking limit and temporary resynchronization are distinct. `--claude-probe` separately reports read-only local-audit activity counts; it baselines existing files and has no response transport. See the [compatibility matrix](docs/compatibility.md) and [current acceptance checklist](docs/verification.md#acceptance-still-required) for measured results and remaining checks.

The interface takes high-level inspiration from [Open Vibe Island](https://github.com/Octane0411/open-vibe-island), without copying its UI code or assets. It uses system typography and SF Symbols, labeled status, explicit permission actions, and restrained motion that respects Reduce Motion, following Apple’s [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [motion](https://developer.apple.com/design/human-interface-guidelines/motion) guidance.

For repeatable UI checks, run `bash scripts/render-ui.sh`. It renders synthetic states in unshown windows and briefly exercises its own native test panel, without contacting agents. See the [visual review](docs/ui-review.md) for coverage and limitations.

See [third-party notices](THIRD_PARTY_NOTICES.md) for the narrow Agent HUD code adaptations and their Apache-2.0 license. This repository is private; original project code has no public license grant.
