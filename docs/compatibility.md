# Compatibility

This is a development milestone, not universal agent interception. The current backend suite passes 105 test functions across 18 suites; native acceptance is listed separately below.

| Surface | Implemented | Evidence through 2026-10-20 |
| --- | --- | --- |
| Codex/ChatGPT Work Desktop async questions | Native observation, free text and single-choice responses | Option and typed answers arrived in the native conversation. A completed-turn Blue/Green question was also detected and answered; the native reply started a new turn. Clean receipt settlement for that idle path still needs a fresh live check. |
| Codex/ChatGPT Work activity | Latest-turn backend and socket integration pass | All 76 earlier tests passed once permissions allowed sockets. A read-only native probe of this conversation reported one running Work turn. Native completion/reconnect/sleep-wake checks and completion notifications remain separate. |
| ChatGPT regular Chat mode | Deferred for now | User suggested deferring regular Chat after the source limitations were explained; work continues on Claude. No verified external lifecycle source is established. No support is advertised. |
| Claude local-runtime activity / waiting state | Read-only audit adapter implemented; fresh live check pending | Explicit local `system/init`, root `result`, permission-request/response records. EOF baseline, bounded incremental reads and conservative gap handling. Native probe read the existing store and displayed no historical sessions. Full suite passes 96 tests after independent review fixes. This does not verify a fresh Claude turn. |
| Claude ordinary cloud Chat / cloud-only Cowork | No adapter | No verified companion event/response attachment. Consumer Chat does not run plugin hooks. Local audit support only applies when that runtime actually writes the compatible files. |
| Claude answer / approval delivery | Not implemented | Reading a permission log is not a live callback. The source app still handles responses; the new observer never creates answerable requests. CLI was signed out and Desktop showed Free during inspection. |
| Answering in the source app | Reply envelopes withdraw matching requests | Two user replies in the source conversation cleared their previously visible Agent Handler cards. The computer tool cannot itself click the source app; cleanup was checked in Agent Handler. |
| Multiple questions and conversations | Independent request identity and scoped state | Two simultaneous native questions tested; answering one retained the other. Multiple conversations remain core/socket-fixture tested. |
| Codex command approvals | Adapter implemented; native acceptance unverified | Exact command/directory/reason, native choices including a bounded saved command rule, current owner and whole-request/settings fingerprint. A real request was captured on an automatic-review turn. The saved projectless granular preset disables shell/rule prompts; a later active native turn reports user/never/full access despite the composer label. See live-approval-setup.md. Native shell acceptance remains pending. |
| Codex app approvals | Restricted adapter; live Clock round trip passed | The user allowed the waiting Clock access request through Agent Handler. The native computer tool resumed with Clock's interface, the card cleared, and the latest ledger entry closed. Complete user-reviewed settings and enabled MCP category required. Exact scope button/accepted receipt was not captured. |
| Codex browser-origin approvals | Restricted adapter implemented; synthetic evidence | Known empty-form confirmations and native persistence scopes only. Controlled socket routing, deny/scope preservation, changed-request reconnect and SQLite reopen tests pass. The native navigation produced no card; browser acceptance remains pending. |
| File diffs, network/additional permission grants, arbitrary forms and Claude approvals | Not implemented | Continue in the source app. |
| Codex CLI, public app-server, Claude hooks, MCP elicitation | Not implemented | Separate future adapters, each needing an ownership and response contract. |
| Notch and menu fallback | Native AppKit/SwiftUI interface | Panel, text entry, option selection, request selector, × close button, Escape and collapse/reopen tested through computer use. Menu fallback, multiple displays and full keyboard navigation remain pending. |
| Restart and uncertain delivery | Durable ledger and generation fencing | Fresh native pending-question recovery and an answer through the restarted app passed again. Controlled EOF/reconnect, stop-before-write, SQLite reopen and crash checks pass. Definite non-delivery can recover only with fresh state; uncertain sends stay blocked. Source-host restart, native uncertain-send restart and real sleep/wake remain pending. |

## Tested host

- macOS arm64; Swift 6.3.3 Command Line Tools.
- `/Applications/ChatGPT.app`, bundle ID `com.openai.codex`, version **26.1013.40934**, build **20770**.
- Private Desktop owner stream version **11**.
- Read-only metadata: `state_5.sqlite`, required columns `id`, `title`, `archived`, `updated_at`.
- Native probe: 16 discovery candidates; a compatible owner was found. A separate probe of the current conversation found **one compatible stream and one pending question**. No native answer was sent by a probe.

The probe stops on the first compatible owner or after twelve seconds; its count is a sample, not evidence that every candidate is owned or supported. Metadata supplies candidates only. In this host build `has_user_event` is zero on ordinary conversations, so it is deliberately not a visibility filter.

## Protocol boundary

Desktop IPC is undocumented. Agent HUD Open's versioned implementation is the reference, with a pinned upstream revision and notices in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). This does not give the protocol an upstream stability promise.

Before submitting, the adapter verifies the owner, current turn and exact question from its current stream. It validates the owner/method/turn in the receipt. The host submission method does not offer an atomic expected-question compare-and-set; a race remains between preflight and submission. Unknown delivery is retained as uncertain and never retried automatically.

Running-turn answers use the native steer method. Completed-turn answers use the native start-turn method with inherited host settings; they do not override permissions, model or collaboration mode. A valid accepted receipt can settle a temporarily unavailable request only with the same epoch and fingerprint.

Approvals reconcile in their own scope, independently of question-history completeness. The parser binds the full native request and complete relevant settings into the displayed fingerprint. A native approval `ok` response is only a dispatch acknowledgment; even a missing request can receive it. The send remains uncertain until authoritative withdrawal closes the card, and cannot be retried. Automatic review and unknown policy/schema values remain disabled. Known approval parsing failures add a health warning; this is not exhaustive detection of every unsupported request kind.

Only stream version 11 and recognized complete question shapes become actionable. A version change, malformed state, revision gap or disconnection disables answering. Local permissions and peer UID are checked; the app does not change agent permission settings. Foreign-UID rejection is implemented, but a separate-UID runtime test has not been performed.

## Limits

- At most 16 followed conversations and 128 unresolved requests.
- Frames at most 128 MiB; supported content fields at most 16 KiB.
- Conservative retained-tree accounting: 8 MiB per conversation, 64 MiB across the followed set, depth under 128. These are projection budgets, not exact RSS limits; receive buffers, parser temporaries and copy-on-write versions add transient memory.
- Unused item and turn metadata fields are discarded before retained-budget admission. Identity, question content and accepted-answer envelopes stay intact; markers preserve paths for later native updates. Required oversized content is still unsupported.
- Completed questions remain visible across consecutive native reply turns. A new ordinary prompt ends that earlier group. Gaps, partial item history, empty hydrating turns and unknown input types cannot establish withdrawal. Source-local Skip/dismiss state is not a verified protocol signal.
- Candidate file metadata is checked every five seconds; SQL runs when metadata changes or at least every sixty seconds. No periodic full transcript scan.
- Ten-second connection/answer deadline, thirty-second frame deadline and capped recovery/reconnect cadence.
- Activity records describe the latest native Work turn, not completion of an entire agent tree or an external follow-up queue. Visible pending submissions, active goals and queued messages prevent a completed classification. The app emits no completion notifications in this milestone; durable alert delivery and ordinary Chat/cloud-only Claude activity sources remain future work.
- Claude audit observation is local and read-only: at most 512 discovered sources, 16 followed sources, 256 KiB read per source/tick and 512 KiB per record/metadata file. Existing files start at EOF. Unknown records, partial lines, backlog, source loss, rewriting/truncation and unreadable inputs disable current classification. Audit order and SDK session ID correlate facts; no native atomic turn/response targeting or audit-HMAC verification is claimed. A quiet log cannot prove the individual runtime is alive; the surviving Desktop process is only an availability check.

Limit or compatibility failures preserve existing unresolved cards as unavailable. Some previously unseen requests may remain undiscovered; use the source app. The health display currently groups connection, schema and capacity faults into a broad fallback message.

After host updates: run tests, run the read-only probe, then complete the manual acceptance checklist before treating responses as verified on that build. Do not patch around a changed protocol by guessing IDs or accepting an unrecognized receipt.
