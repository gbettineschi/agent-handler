# Claude Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Observe fresh local Claude runtime activity and waiting requests from explicit audit events, without manufacturing a response channel.

**Architecture:** ClaudeDesktopAdapter owns bounded audit discovery/tailing and a strict reducer. Immutable observations project into ActivityStore; AppModel manages process/sleep lifecycle and diagnostics exposes read-only counts. No UI redesign or source setting changes.

**Tech Stack:** Swift 6, Foundation, Darwin, AppKit process metadata; macOS 14+, no fetched dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-claude-audit-design.md`

## Global Constraints

- Build a read-only ClaudeDesktopAdapter for local audit files.
- Cloud-only Chat/Cowork sessions without a local audit are not covered.
- This adapter must not create answerable AttentionRequests, send answers, grant permissions or settle delivery-ledger entries.
- On start/resume, baseline existing files at EOF.
- Follow at most 16 changed sessions; discovery at most 512 candidates.
- Read at most 256 KiB per file per tick and 512 KiB per line.
- This increment adds no notification delivery or UI layout.

## Review Focus

- Old audit results must not surface on application restart (Task 2).
- A child result, mismatched session or malformed success record cannot complete the main turn (Task 1).
- A different permission response or assistant output cannot clear a waiting request (Task 1).
- Rotation, truncation, rewrite or an oversized line must not join unrelated bytes into a valid event (Task 2).
- Process loss/resumption must not revive a previous running/completed record as current (Task 2).

### Task 1: Strict native audit reducer

**Files:** Create `Sources/ClaudeDesktopAdapter/ClaudeAuditState.swift`, `Tests/ClaudeDesktopAdapterTests/ClaudeAuditTests.swift`; modify Package.swift with a ClaudeDesktopAdapter target and test target, dependencies on AgentHandlerCore only.

**Interfaces:** `ClaudeAuditState` exposes `observation: (turnID: String, phase: ActivityPhase, attention: ActivityAttention)?`, `isKnown: Bool`, `consume(_ line: Data)`, `invalidate()`. It keeps root init UUID/session ID, distinct permission UUIDs and bounded event fingerprints; no message text is retained.

- [ ] Write tests for explicit init/success/error/interruption, no-init/mismatched/child result rejection, strict boolean/error fields, permission identity, duplicate UUID idempotence/conflicts and new-init recovery.
- [ ] Run `scripts/test.sh --filter ClaudeAuditTests`; expect missing reducer failure.
- [ ] Implement strict bounded JSON parsing and the reducer, with explicit terminal reason checks and native ordered-stream semantics.
- [ ] Run `scripts/test.sh --filter ClaudeAuditTests`; expect all pass. Commit reducer and tests.

### Task 2: Safe incremental local observer and application integration

**Files:** Create `Sources/ClaudeDesktopAdapter/ClaudeAuditFiles.swift`, `Sources/ClaudeDesktopAdapter/ClaudeDesktopObserver.swift`, `Tests/ClaudeDesktopAdapterTests/ClaudeObserverTests.swift`; modify AppModel, Diagnostics, Package.swift dependencies, compatibility/surface-audit/verification documentation.

**Interfaces:** `ClaudeDesktopObserver(root: URL)` actor exposes `poll(sourceInstance: String?)`, `stop()`, `activity() -> [ActivityView]`, `health() -> String`. A changed sourceInstance invalidates and baselines; nil means unavailable. Files implement bounded source enumeration, read-only no-follow open, offset/checkpoint tracking and newline framing. Consumes Task 1 reducer and ActivityStore.

- [ ] Write failing temporary-file integration tests for baseline/no replay, append/partial records, identity collision between accounts, rotation/truncation/checkpoint rewrite, symlink rejection, oversize recovery, source loss/restart and concurrent independent sessions. New files after baseline must be handled deterministically in fixtures without depending on filesystem clock resolution.
- [ ] Run observer tests; expect missing observer failure.
- [ ] Implement file safety and framing, conservative invalidation, limits and actor-owned source generations. Read metadata only for eligibility; parse logs only after new bytes.
- [ ] Integrate into AppModel polling and sleep/wake/disable lifecycle, using Claude PID and launch date as instance metadata. Add `--claude-probe` diagnostics, reporting counts and limitations, with no message bodies or response path.
- [ ] Run the full `scripts/test.sh`, `scripts/bundle.sh`, `codesign --verify --deep --strict 'dist/Agent Handler.app'` and `git diff --check`; expect success.
- [ ] Record the current Work probe and local Claude probe accurately, update compatibility/deferred Chat scope and competitor source explanation, commit, and request a fresh whole-change review. Fix material findings with regressions. Publish the private branch and verify CI if network remains available; do not claim a live Claude pass from fixtures or old files.
