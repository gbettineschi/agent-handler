# Native approvals and surface coverage implementation plan

> Use superpowers:executing-plans. The user authorized implementation without further plan-review pauses.

**Goal:** Add supported Desktop approval responses and establish actual integration boundaries for regular Chat and Claude, while closing outstanding live checks where the host permits them.

**Architecture:** Preserve the existing controller/ledger. Reconcile approvals in a separate source scope so malformed question history cannot withdraw approvals. Bind the full native approval payload and effective review settings into the displayed request fingerprint. Use the native owner's versioned response methods; no automatic approval or permission-policy changes. Regular Chat and Claude require independent contracts and must not be represented as Work coverage.

**Tech stack:** Existing Swift 6/macOS 14 project; no new dependencies.

**Spec:** ../specs/2026-10-19-agent-handler-design.md; user extension request of 19 October.

## Constraints and review focus

- Preserve existing request hashes when the new optional native fingerprint is absent, so old uncertain attempts stay blocked.
- Keep the existing 16 conversation / 128 unresolved / 8 MiB per-state limits.
- Suppress automatically reviewed prompts. Require recognized complete permission settings before acting.
- Command approvals must show the exact command, directory and reason; network or additional-permission requests require explicit rendering or remain unsupported.
- File approvals require complete proposed changes; never display a generic file Allow button without the actual change.
- Unknown, oversized or changed native request bodies disable responding; integer/string request IDs remain distinct.
- Native approval `ok` receipts are dispatch acknowledgments and can be returned for stale IDs. Do not equate them with proof of execution or a selected decision. Preserve uncertain delivery until authoritative withdrawal; never retry it.
- Do not access session credentials, patch vendor apps, inject into private renderers, or bypass computer-tool app restrictions to cover regular Chat/Claude.

## Task 1: Native approval parsing and submission

Files: new DesktopApprovals.swift and DesktopApprovalTests.swift; DesktopAdapter, DesktopProjection, Request, FixtureDesktopServer, AppModel and RequestView.

- [x] Add failing parser tests for native identity, request changes, review filtering, unavailable choices, malformed shapes and complete presentation data. Long-label visual acceptance remains open.
- [x] Implement `DesktopApprovals.pending(state:threadID:owner:installation:)` returning exact request and allowed native reply payloads. Begin with command and known computer/browser MCP confirmation contracts; leave unsupported file diffs/network grants explicit.
- [x] Preserve only the permission fields needed in turn projection; bind native raw request hash through optional `AttentionRequest.sourceFingerprint`.
- [x] Add socket tests proving exact response routing, no retries, lost/negative/positive acknowledgments, stale-request refusal and independent question/approval invalidation.
- [x] Integrate independent approval scope observation and guarded submission. Keep native command/MCP action maps separate from questions.
- [x] Run the complete suite and independent review, then bundle.

## Task 2: Native acceptance and remaining verification

- [ ] Test a harmless real user-reviewed approval through the running app; confirm the source tool outcome and withdrawal, record what acknowledgment actually proves.
- [x] Test connection disable/re-enable and app restart with a real pending request. Verify only fresh state re-enables actions. Answer arrival and withdrawal passed; the ledger closed without an exact accepted receipt. Source-host restart remains untested.
- [ ] Retest a completed-turn question only with a fresh request; never resend the previously answered Blue request.
- [x] Audit regular Chat's actual question protocol and Claude Desktop Chat/Cowork transports/hooks. If no external adapter contract can be established, document the precise missing interface and feasible compromises instead of shipping a fake integration.
- [x] Record real sleep/wake/display/access restrictions honestly; do not interrupt unrelated tasks or fabricate live acceptance from fixtures.
- [x] Publish tested changes and exact evidence in compatibility/verification documentation. Code/test commit `f119976` passed all 61 tests, bundle, demo and signature verification in CI run `39319407861`.
