# Conversation Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track verified Work turn activity without confusing completion, human input and source unavailability, and establish the remaining ordinary Chat source gap accurately.

**Architecture:** A pure ActivityStore holds one current observation per conversation, fenced by owner epoch and revision. DesktopActivity translates existing version-11 state; DesktopAdapter owns it alongside the response controller. AppModel and diagnostics consume snapshots, without new UI behavior or response authority.

**Tech Stack:** Swift 6, macOS 14+, existing SwiftPM targets; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-conversation-activity-design.md`

## Global Constraints

- UI/UX work remains deferred.
- Native phase: running, completed, failed or cancelled.
- Attention: required, clear or unknown.
- One record per followed conversation.
- This increment emits no completion notifications.
- Do not inject a renderer, extract credentials, patch the host or infer completion from silence/mtime.

## Review Focus

- A delayed owner callback cannot mark a replacement connection complete (Task 1).
- A completed turn can still contain an unanswered asynchronous question (Task 2).
- A partial canonical history or ambiguous overlay cannot identify the latest turn (Task 2).
- Unsupported native requests must not appear to require no attention (Task 2).
- Unfollowing and stopping must remove or invalidate activity without affecting response delivery (Task 2).

### Task 1: Fenced activity snapshots

**Files:** Create `Sources/AgentHandlerCore/ActivityStore.swift`, `Tests/AgentHandlerCoreTests/ActivityTests.swift`.

**Interfaces:** Produces ActivityPhase, ActivityAttention, ActivityStatus, ActivityView, ActivitySnapshot and ActivityStore. Store methods: `begin(scope:) -> UUID`, `observe(_:) -> Bool`, `invalidate(scope:epoch:)`, `remove(scope:)`, and `views: [ActivityView]`. Snapshot carries scope, epoch, revision, turnID, phase, attention. View exposes computed status; unavailable always unknown, then required attention takes precedence, then unknown attention, then phase.

- [x] Write failing tests for phase mapping, required/unknown attention, invalid identity, stale epoch/revision, unavailable reconnect and independent scopes/removal. Expectations use literal statuses.
- [x] Run `scripts/test.sh --filter ActivityTests`; expect failure because ActivityStore does not exist.
- [x] Implement the pure store; increasing revisions and exact epochs gate every observation. Invalid higher revisions invalidate and consume the revision floor. Reject empty or over-256-byte turn IDs.
- [x] Run `scripts/test.sh --filter ActivityTests`; expect all activity tests pass.
- [x] Commit the core and its tests.

### Task 2: Native Work projection and integration

**Files:** Create `Sources/CodexDesktopAdapter/DesktopActivity.swift`, `Tests/CodexDesktopAdapterTests/DesktopActivityTests.swift`; modify DesktopQuestions (structural turn helper visibility only), DesktopAdapter, AppModel, Diagnostics and compatibility/verification/audit documentation.

**Interfaces:** Consumes Task 1 ActivityStore. Produces `DesktopActivity.parse(state:threadID:owner:installation:) throws -> (turnID: String, phase: ActivityPhase, attention: ActivityAttention)` and `DesktopAdapter.activity() -> [ActivityView]`.

- [x] Write parser tests: legacy/canonical phases; completed question -> needs input; malformed question/unknown request -> unknown attention; exhausted newer boundary required; overlay ambiguity/empty turns/unknown status rejected. Write a socket fixture integration test for running -> completed, disconnect -> unknown, stop -> unknown and unfollow -> removal.
- [x] Run parser tests; expect failure because DesktopActivity does not exist.
- [x] Implement the projection. Reuse structural turn decoding without weakening question withdrawal rules. Unknown native request methods cannot establish clear attention. Track owner epochs and invalidate missing/unsupported states in the adapter, with existing generation checks after awaits.
- [x] Publish snapshots in AppModel and add phase counts to existing health text and diagnostics JSON. Do not change question selection, answer encoding or notification behavior.
- [x] Run `scripts/test.sh --skip 'DesktopSocketTests/|DesktopAdapterTests/|nativeApprovalDispatchIsNotAnExecutionReceipt|approvalsStayIndependentFromIncompleteQuestionHistory'`; expect available tests pass. Run the complete suite once and report any denied socket cases by suite, without escalation requests.
- [x] Run `scripts/bundle.sh`, `codesign --verify --deep --strict 'dist/Agent Handler.app'`, and `git diff --check`; expect success.
- [x] Update docs with actual evidence, ordinary Chat activity-only scope and outstanding source/host checks; commit. Request a fresh whole-change review, address material findings with regression tests, then rerun affected checks.
