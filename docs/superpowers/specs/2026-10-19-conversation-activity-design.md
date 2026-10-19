# Conversation activity backend

The user clarified the scope: ordinary ChatGPT Chat needs activity/completion tracking; Work/Codex also needs native questions and approvals. Claude requires its own verified source contracts. UI/UX work remains deferred. The existing authorization permits planning and building without further review pauses.

## Source decision

Use explicit native turn status from the existing version-11 Work owner stream first. This is an integrated backend increment, not a claim of ordinary Chat or Claude coverage. Keep activity independent from the delivery ledger: observing a completed turn neither accepts an answer nor grants permission.

Regular Chat research found an internal `conversation-turn-complete` event and authenticated pubsub transport. The local catalog's `chatgpt_async_status` column is nullable and every current row is null. Ordinary pubsub logs omit conversation/turn identity; recovery logs cover exceptional recovery, not all turns. These are insufficient for an external, complete lifecycle adapter. Do not inject a renderer, extract credentials, patch the host or infer completion from silence/mtime. A later Chat adapter must establish a usable source before being advertised.

## Model and behavior

- Native phase: running, completed, failed or cancelled. Unknown schemas yield unavailable observations, never completed.
- Attention: required, clear or unknown. A known pending question or supported human approval takes precedence over completed. Unknown/malformed request kinds prevent a claim that attention is clear.
- Freshness: current or unavailable, scoped to an owner epoch and increasing stream revision. Disconnect, sleep, parser failure and owner replacement make the visible status unknown. Retain the last fact for diagnostics; it is not fresh completion evidence.
- One record per followed conversation. Removing a conversation removes its activity record; request delivery state is unaffected. A new process starts without activity until a current snapshot arrives.
- A completed snapshot can describe the latest turn, but this increment emits no completion notifications. It must not replay historical completion alerts or promise durable exactly-once notifications. A notification feature needs its own checkpoint contract later.

`ActivityStore` is a pure value in AgentHandlerCore, owned by the existing adapter actor. It has no response transport, timer, filesystem or UI dependencies. `DesktopActivity` selects a known latest native turn and assesses attention independently from whether question history can be answered. Canonical history needs an exhausted newer boundary and no ambiguous overlay. Missing/empty/unknown turn stores remain unknown.

Expose immutable activity snapshots through DesktopAdapter, AppModel and the read-only diagnostic command. Add terse counts to the existing health text; no new panel, automatic expansion or visual redesign. Existing request counts and answers retain their current behavior.

## Acceptance

Tests must prove stale epochs/revisions cannot revive an old result, disconnect/reconnect stays unknown until a newer snapshot, incomplete canonical history cannot establish completion, failures/cancellation remain distinct, and completed turns with pending questions stay needs-input. Unknown native requests cannot look clear. The available socket-free suite and release/signature checks must pass. Socket fixture and real-host tests remain explicitly pending while this turn disallows sockets; do not label them passed.
