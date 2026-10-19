# Agent Handler first Desktop companion implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a private, testable macOS question companion with a reliable request core, native Desktop integration and a minimal notch.

**Architecture:** A single controller actor owns request and delivery state. A provider adapter reconciles native observations and validates native receipts. SQLite records attempted deliveries before sending; the SwiftUI/AppKit interface consumes snapshots.

**Tech Stack:** Swift 6, SwiftPM, Foundation, system SQLite, CryptoKit, AppKit, SwiftUI and Swift Testing; no fetched package dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-agent-handler-design.md`

## Global Constraints

- Target macOS 14 or newer; Swift 6 language mode.
- Repository `gbettineschi/agent-handler` remains private.
- Existing agent apps remain execution and permission owners.
- Only explicit user actions send real answers; tests use isolated synthetic sources.
- Stable request keys exclude connection generation; generations fence observations and completion callbacks.
- Unknown state never means an empty authoritative snapshot; socket writes never mean acceptance.
- Preserve integer/string IDs, exact content fingerprints, response capabilities and native turn identity.
- At most 16 followed conversations, 128 pending requests, 128 MiB frames, 16 KiB content fields, 8 MiB retained state per conversation and 64 MiB overall.
- Connection/answer deadline 10 seconds; snapshot receive deadline 30 seconds; recovery snapshot minimum interval 30 seconds; owner confirmation interval 60 seconds; reconnect backoff 1–30 seconds with jitter.
- No answer retry after uncertain delivery, including restart. Unavailable persistence disables answering.
- Include upstream Apache-2.0 license and attribution for adapted Agent HUD code at `bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9`.
- Keep transport and parser failures observable without recording question or answer contents.

## Review Focus

- A response races native cancellation, owner transfer or content replacement: no stale request is marked accepted and no response silently changes targets (Tasks 1 and 3).
- Process death between durable reservation, first write and receipt: restart never automatically sends another answer (Tasks 2 and 3).
- A partial/malformed/oversized observation arrives while another conversation is healthy: preserve unresolved cards and isolate the fault (Tasks 1 and 3).
- Sleep/wake or a second app instance changes connection ownership: invalidate freshness, fence callbacks and preserve pending requests (Tasks 3 and 4).
- Missing/changed metadata, unsupported stream version or a screen without a notch: usable source-app fallback, explicit health and no false claim of full support (Tasks 3–5).

## File structure

- `Sources/AgentHandlerCore/{Request,RequestStore,RequestController,DeliveryLedger,SQLiteLedger}.swift`: domain, pure transitions, actor and persistence.
- `Sources/CSQLite/{module.modulemap,shim.h}`: system SQLite module.
- `Sources/CodexDesktopAdapter/{JSONValue,RecordCoding,DesktopIPC,DesktopPatches,DesktopQuestions,DesktopStream,DesktopAdapter,ThreadDiscovery}.swift`: bounded native protocol, question contract and discovery.
- `Sources/AgentHandlerApp/{AppMain,AppModel,NotchPanel,RequestView}.swift`: native app composition and UI.
- `Sources/AgentHandlerDiagnostics/main.swift`: fixture demo and read-only probe.
- `Tests/AgentHandlerCoreTests/`: lifecycle, concurrency, persistence and restart tests.
- `Tests/CodexDesktopAdapterTests/`: synthetic real-socket transport and provider contract tests.
- `scripts/{test.sh,bundle.sh}`, `.github/workflows/ci.yml`: reproducible verification and build.
- `README.md`, `docs/{compatibility,verification}.md`, `THIRD_PARTY_NOTICES.md`, `LICENSES/`: setup, evidence and provenance.

## Task 1: Request identity and single-owner controller

**Interfaces:**
- `RequestKey: Hashable, Codable, Sendable` identifies installation/conversation/turn/native ID.
- `AttentionRequest: Equatable, Sendable` contains key, fingerprint, title, content, owner and revision.
- `RequestStore` is a pure value type; `begin(scope:) -> UUID`, `apply(snapshot:)`, `invalidate(scope:epoch:)`, `views` expose deterministic transitions.
- `RequestController` actor consumes store, `DeliveryLedger` and `ResponseTransport`; exposes `begin(scope:)`, `observe(_:)`, `invalidate(scope:epoch:)`, `snapshot()`, `updates()` and `respond(key:fingerprint:answer:using:) async throws`.
- `ResponseTransport.deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome` returns accepted, notSent, rejected or uncertain.

- [x] Write core tests for two independent same-wording requests, integer/string IDs, stale epoch/revision, per-scope withdrawal, malformed snapshots, content replacement, duplicate clicks and late delivery results. Use a suspended fake transport to control races.
- [x] Run `scripts/test.sh --filter CoreTests`; expected failures establish absent lifecycle behavior, rather than toolchain problems.
- [x] Implement typed domain and pure store, then the controller. Reserve an attempt synchronously before the first await. UI answers carry the expected fingerprint; only advertised response types are valid.
- [x] Run `scripts/test.sh`; expected all core tests pass, including rejected stale actions and one transport call for double submission.
- [x] Commit `feat: add request lifecycle and single-owner controller`.

## Task 2: Durable delivery ledger

**Interfaces:**
- `DeliveryLedger.reserve(key:fingerprint:attemptID:) throws`, `finish(key:attemptID:outcome:) throws`, `status(for:) throws -> LedgerStatus?`, `close(key:) throws` are synchronous and serialized by implementations.
- `SQLiteLedger.init(url:) throws` opens or migrates schema version 1 and recovers in-flight attempts as uncertain. The ledger persists hashes rather than user text.

- [x] Write tests using a temporary SQLite database: reservation survives restart; changed fingerprint does not unlock uncertainty; confirmed acceptance survives replay; definitive notSent permits a newly validated attempt; wrong attempt ID cannot overwrite a newer result; newer schema and unwritable storage fail safely.
- [x] Run `scripts/test.sh --filter LedgerTests`; expected failures for missing persistence and reservation uniqueness.
- [x] Implement SQLite transactions, WAL/FULL, prepared statements, schema checks and ledger error handling. Add private directory permissions and an advisory instance lock in the application runtime setup.
- [x] Run `scripts/test.sh`; expected restart, content privacy, concurrency and original core tests pass. Inspect the temporary database schema in the test to verify no answer/prompt columns.
- [x] Commit `feat: persist delivery attempts before sending`.

## Task 3: Desktop protocol and question adapter

**Interfaces:**
- `DesktopIPC` owns a single Unix socket, length framing, deadlines, peer validation and request correlation.
- `DesktopQuestions.parse(state:threadID:owner:installation:) throws -> [AttentionRequest]` validates complete supported question shapes.
- `DesktopStream` publishes typed per-conversation known/unknown observations with generation and revision; maps snapshots and patches without inventing empty state.
- `DesktopAdapter` implements `ResponseTransport`, owns the stream and routes observations to `RequestController`; `start(threadIDs:)`, `stop()` and `health` provide lifecycle control.

- [x] Write parser tests for canonical history, multiple questions, answered envelopes, missing fields, large/truncated content, unsupported shapes and duplicate IDs. Write socket fixture tests for split frames, interleaved broadcasts, EOF, timeout, foreign peers/version, owner change and receipt mismatch.
- [x] Run `scripts/test.sh --filter Desktop`; expected failures for missing provider behavior.
- [x] Adapt the narrow upstream JSON, IPC and patch utilities with notices. Enforce bounds before retaining state, unknown-state invalidation, idempotent close and explicit cancellation. Implement stream owner discovery/following and capped recovery/backoff.
- [x] Implement question extraction and native response encoding, checking owner and current exact question immediately before sending. Mark any possibly-written but unconfirmed attempt uncertain; preserve native receipt identity. Do not automatically retry.
- [x] Run `scripts/test.sh`; expected real-socket provider tests and all core/ledger tests pass. Add a diagnostic fixture scenario using the same controller and adapter.
- [x] Commit `feat: connect Desktop questions with verified receipts`.

## Task 4: Minimal native app and bounded discovery

**Interfaces:**
- `ThreadDiscovery` reads only candidate IDs and titles from supported local metadata; discovery has no response authority.
- `AppModel` subscribes to controller updates, dispatches explicit responses, reports adapter health and opens the source application.
- `NotchPanel` owns AppKit window geometry; `RequestView` renders current requests and exact supported choices.

- [x] Add tests for candidate limits, unsupported metadata, bounded selection, single-instance lock and panel placement on notched/non-notched screens through pure geometry helpers.
- [x] Run the new tests; expected failures for absent behavior.
- [x] Implement read-only discovery with change coalescing and periodic bounded reconciliation, preserving explicitly selected conversations and pending requests. Wire sleep/wake invalidation.
- [x] Add notch attention count, expandable queue, question text/choices/free text, explicit Send and Open in source. Keep sending/unknown/uncertain visible. Include clearly labeled demo mode, display selection, adapter toggle and launch-at-login setting.
- [x] Run `scripts/test.sh` and `scripts/bundle.sh`; expected passing tests and a runnable development `.app` under ignored `dist/`.
- [ ] Inspect demo UI in the running app, including keyboard entry and multiple simultaneous questions; verify only the selected fixture request settles.
- [x] Commit `feat: add minimal notch companion and source navigation`.

## Task 5: Compatibility evidence, review and private delivery

**Interfaces:** diagnostic commands and the packaged app use the exact production modules.

- [ ] Add macOS CI and concise setup, compatibility, provenance and verification documentation. Clearly distinguish core approval tests from live approval support.
- [ ] Run the entire test suite and release build. Run a read-only host compatibility probe; record host build, stream version, discovery result and parser outcome without storing private conversation contents.
- [ ] Run a synthetic end-to-end answer scenario and measure bounded idle process behavior. Real user answers and sleep/wake acceptance remain explicitly pending until performed by the user; never label synthetic evidence as native acceptance.
- [ ] Obtain an independent whole-branch review under the requesting-code-review skill. Fix material findings with failing-then-passing regression tests; rerun the full suite.
- [ ] Commit verified source and docs, fast-forward the new repository's main branch, push to the authorized private remote and verify visibility plus commit SHA. Report the app location and any live acceptance still required.

## Execution decisions

The user approved this design and explicitly waived further planning approval pauses. Execute inline, then request one independent final review. This is a fresh dedicated repository with no pre-existing product code or concurrent user changes; use the `feat/first-desktop-companion` branch in this checkout rather than adding a second checkout. Publishing to the requested private repository is authorized.

## Verification qualifications

Core, persistence, adapter and app implementation steps are complete. The separate-UID peer rejection path is implemented but was not exercised with a foreign-UID process. Visual/keyboard checks and live user-clicked responses remain pending because the Mac was locked; these are not claimed as passed. Native read-only discovery and pending-question parsing succeeded. Detailed evidence is in `docs/verification.md` and `docs/compatibility.md`.
