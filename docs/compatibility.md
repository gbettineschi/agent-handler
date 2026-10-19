# Compatibility

This is a development milestone, not universal agent interception.

| Surface | Implemented | Evidence on 2026-10-19 |
| --- | --- | --- |
| Existing Codex/ChatGPT Desktop async questions | Native observation, free text and single-choice responses | Live owner stream and one real pending question detected; synthetic native receipt round trip passes. User-clicked native answer acceptance still pending. |
| Answering in the source app | Reply envelopes withdraw matching requests | Parser and socket-fixture tests; live acceptance pending. |
| Multiple questions and conversations | Independent request identity and scoped state | Core and synthetic socket tests. |
| Core approval model | Exact native choice IDs; no generic allow-all | Core tests only; no live approval adapter. |
| Command, browser, app and Claude approvals | Not implemented | Continue in the source app. |
| Codex CLI, public app-server, Claude hooks, MCP elicitation | Not implemented | Separate future adapters, each needing an ownership and response contract. |
| Notch and menu fallback | Native AppKit/SwiftUI interface | Geometry tests and app launch pass. Visual/keyboard verification blocked by the locked Mac. |
| Restart and uncertain delivery | Durable ledger and generation fencing | SQLite reopen, concurrency and SIGKILL subprocess checks at three committed ledger checkpoints. Whole-app native restart and sleep/wake acceptance pending. |

## Tested host

- macOS arm64; Swift 6.3.3 Command Line Tools.
- `/Applications/ChatGPT.app`, bundle ID `com.openai.codex`, version **26.1013.40934**, build **20770**.
- Private Desktop owner stream version **11**.
- Read-only metadata: `state_5.sqlite`, required columns `id`, `title`, `archived`, `updated_at`.
- Native probe: 16 discovery candidates; a compatible owner was found. A separate probe of the current conversation found **one compatible stream and one pending question**. No native answer was sent by a probe.

The probe stops on the first compatible owner or after twelve seconds; its count is a sample, not evidence that every candidate is owned or supported. Metadata supplies candidates only. In this host build `has_user_event` is zero on ordinary conversations, so it is deliberately not a visibility filter.

## Protocol boundary

Desktop IPC is undocumented. Agent HUD Open's versioned implementation is the reference, with a pinned upstream revision and notices in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). This does not give the protocol an upstream stability promise.

Before submitting, the adapter verifies the owner, active turn and exact question from its current stream. It validates the owner/method/turn in the receipt. The host submission method does not offer an atomic expected-question compare-and-set; a race remains between preflight and submission. Unknown delivery is retained as uncertain and never retried automatically.

Only stream version 11 and recognized complete question shapes become actionable. A version change, malformed state, revision gap or disconnection disables answering. Local permissions and peer UID are checked; the app does not change agent permission settings. Foreign-UID rejection is implemented, but a separate-UID runtime test has not been performed.

## Limits

- At most 16 followed conversations and 128 unresolved requests.
- Frames at most 128 MiB; supported content fields at most 16 KiB.
- Conservative retained-tree accounting: 8 MiB per conversation, 64 MiB across the followed set, depth under 128. These are projection budgets, not exact RSS limits; receive buffers, parser temporaries and copy-on-write versions add transient memory.
- Candidate file metadata is checked every five seconds; SQL runs when metadata changes or at least every sixty seconds. No periodic full transcript scan.
- Ten-second connection/answer deadline, thirty-second frame deadline and capped recovery/reconnect cadence.

Limit or compatibility failures preserve existing unresolved cards as unavailable. Some previously unseen requests may remain undiscovered; use the source app. The health display currently groups connection, schema and capacity faults into a broad fallback message.

After host updates: run tests, run the read-only probe, then complete the manual acceptance checklist before treating responses as verified on that build. Do not patch around a changed protocol by guessing IDs or accepting an unrecognized receipt.
