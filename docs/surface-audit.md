# Host integration audit — 19 October 2026

The feasible architecture is one controller with separate host adapters. Existing companions prove several useful paths; they do not establish one universal request/response interface. Detection, response delivery and confirmation must be assessed separately.

## Hooks, native connections and logs

| Input | Useful authority | Remaining work |
| --- | --- | --- |
| Native pending-request stream | Current request identity, advertised decisions, owner and withdrawal | Pin versions; handle gaps/reconnects; preflight the exact request; distinguish acknowledgment from acceptance |
| Blocking native hook | One live callback can carry a question/permission decision back to its agent | Give each invocation its own identity and lifetime; handle cancellation, host fallback and unknown delivery; verify the host actually loads it |
| Transcript/audit log | Activity, recovery hints, sometimes a correlated native result | A historical request is not necessarily pending. Rotation, lag, partial writes and repeated identical questions require handling. Logs alone provide no response channel |
| Cooperative MCP question tool | Reliable control of requests that actually call that tool | Does not intercept arbitrary native questions or permissions |
| Accessibility/UI automation | Can interact with a visible source card | Requires permissions and a visible, identifiable UI. Focus/layout changes and hidden sessions make it a separate, less capable adapter |

Logs are useful supplementary inputs. Do not turn a transcript entry into an actionable approval without a verified current response target. A native tool result may confirm an answer if it carries the same request identity and exact answer; a generic “resolved” event may also mean cancellation.

## Existing implementations

- **Agent HUD Open**, pinned at `bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9`, supplies the relevant existing-Desktop question and app/browser elicitation reference. Agent Handler adapts these narrow pieces with attribution. [Questions](https://github.com/jazzenchen/agent-hud-open/blob/bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9/Sources/AgentHUDCore/Providers/Codex/CodexDesktopQuestions.swift), [permissions](https://github.com/jazzenchen/agent-hud-open/blob/bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9/Sources/AgentHUDCore/Providers/Codex/CodexDesktopPermissions.swift).
- **OpenIsland**, inspected at `01aa0924fd96bf319a64e75646765c55cae4e2c5`, has a genuine blocking Claude-family hook/socket path. Its Claude answer maps to native `updatedInput`. The audited implementation keys pending responses by session, clears UI before confirmed delivery and does not retain unknown delivery durably. These are engineering defects to avoid, not evidence that hooks cannot work. Its Desktop Code-mode support does not establish general Claude Chat/Cowork coverage. [Bridge](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift), [hook entry point](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandHooks/OpenIslandHooksCLI.swift).
- **CodeIsland**, inspected at `31cf9b57ba8f8f9926a2c353184069e7c27f51be`, reads Claude's local agent-session audit files for Cowork and compatible local Chat observation. It leaves those approvals in Claude. Its reducer can clear pending requests on main-assistant output or on an unmatched permission response; our observer instead removes only an exactly matching permission ID or an explicit terminal result. Its silence cleanup is presentation policy, not evidence of successful completion. [Audit parser/reducer](https://github.com/wxtsky/CodeIsland/blob/31cf9b57ba8f8f9926a2c353184069e7c27f51be/Sources/CodeIslandCore/CoworkAuditLog.swift), [watcher integration](https://github.com/wxtsky/CodeIsland/blob/31cf9b57ba8f8f9926a2c353184069e7c27f51be/Sources/CodeIsland/AppState%2BCoworkWatch.swift). No CodeIsland source code was copied into Agent Handler.

## Codex / ChatGPT Work Desktop

Installed host: ChatGPT 26.1013.40934, build 20770; private owner stream version 11. The new approval adapter handles complete command requests, the known execpolicy amendment choice, and restricted empty-form computer/browser-origin confirmations. Network grants, file diffs, arbitrary elicitation forms and unknown browser methods remain unsupported.

Static host dispatch inspection established that `thread-follower-command-approval-decision` and the MCP response method can return `ok: true` even when their native request lookup finds nothing. That is a dispatch acknowledgment, not proof of execution. Agent Handler preserves an uncertain send and lets authoritative request withdrawal close its card, without retrying.

A real command approval was captured on the current conversation's stream. Its choices were `accept`, an `acceptWithExecpolicyAmendment` object, and `cancel`. The initial string-only parser rejected this request. The revised parser preserves the full native object and explicitly labels the saved rule; its regression failed before the change and passed afterward.

The live session also exposed a review-state mismatch: a read-only snapshot reported `auto_review` in the then-current turn and `guardian_subagent` in current permissions while the user reported a human-facing Codex approval. These are not treated as `user` review. At that stage native approval display/answer/withdrawal had not passed. The later user-reviewed granular turn and Clock result are recorded below; automatic review remains disabled in the adapter.

The public [app-server protocol](https://learn.chatgpt.com/docs/app-server) and [approval documentation](https://learn.chatgpt.com/docs/agent-approvals-security) help establish schemas, but do not turn Desktop's private owner connection into a supported public API.

### Follow-up: Ask for approval and the granular preset

The earlier active turn's execution record confirms `approvals_reviewer: auto_review`. The subsequent turn after the model change confirms `approvals_reviewer: user` with `approval_policy: {granular: {sandbox_approval: false, rules: false, skill_approval: false, request_permissions: true, mcp_elicitations: true}}`. The user reported “Ask for approval” in the composer. Read-only metadata showed no project membership; the supported app connector listed no projects. Saved host state selected `granular`.

In the installed host, `nwo` selects the granular default for projectless work; the preset in `app-shared-52443cbe9ac4.js` has exactly those five flags and the `user` reviewer. Thus a human reviewer and disabled shell-prompt categories can coexist under that label. The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) confirms that false granular categories reject prompts rather than display them. This establishes the current restriction; it does not prove precisely which earlier UI transition kept the old Astra turn on automatic review.

Agent Handler had a separate compatibility defect: it only accepted string approval policies. A regression reproduced rejection of an otherwise valid MCP confirmation under the native granular preset. The parser now validates all five boolean flags exactly, permits MCP only when `mcp_elicitations` is true, and conservatively requires both command categories because the wire request does not identify which one triggered it. Unknown/missing flags and automatic reviewers still disable responding. This change does not alter source settings.

At that earlier stage, the sandbox denied direct socket probes and socket fixture setup. The 46 socket-free tests passed, including the new parser regression; the complete 62-test invocation had 22 socket-related case issues. The release bundle and signature passed. These are partial verification results, not a replacement for the full suite or a live approval round trip. Calculator access and a public example-page navigation produced no observed approval card; neither counts as native approval acceptance.

The later Clock test did pass a native app approval: the user confirmed allowing it through Agent Handler, the waiting computer tool returned Clock's interface, the panel cleared and a new durable ledger entry closed. This establishes app-approval response delivery and host continuation under the granular preset. It does not cover shell prompts, browser-origin prompts, every persistence scope, or an exact accepted receipt.

## Regular ChatGPT Chat

The user's revised scope is **activity and completion tracking only** for regular Chat; interactive questions and approvals remain Work capabilities in our implementation scope. The earlier question audit below is historical protocol evidence, not an outstanding request for another Chat question test.

In the follow-up the user asked whether competitors simply read logs and suggested deferring regular Chat. The current implementation proceeds on that basis, keeping ordinary ChatGPT Chat out of advertised coverage.

The installed renderer handles a Chat `conversation-turn-complete` pubsub event and separate streaming/async state. The official [notification documentation](https://learn.chatgpt.com/docs/notifications) describes completion alerts and the Activity view, but does not establish an external event subscription for companions. The same host's Work `turn-completed` event is not interchangeable with this Chat event.

Read-only inspection of `~/.codex/sqlite/codex-dev.db` found `local_thread_catalog.chatgpt_async_status`; all 2,056 Chat-source rows were null at the time of inspection (including 28 Work-origin `tpp` entries). This is catalog metadata, not a current lifecycle feed. The timeline ledger contained four records for a VS Code source and none for Chat. Ordinary `chatgpt_pubsub_conversation_update_received` log lines omit conversation and turn identity. Exceptional transport-recovery messages contain a conversation ID, but do not cover all starts/completions. Neither file modification times, unread flags nor reconnection imply a completed response. No ordinary Chat activity adapter was implemented from these incomplete signals.

The installed renderer includes Chat-style question widgets carrying `codex_request_user_input` metadata and a tool-role `codex_request_user_input_response` continuation with response-acceptance checks. That path differs from the Work owner's steer/start envelope. Its conversation fetching and live updates belong to authenticated host services; no supported external companion attachment was established in this audit.

Internal preload MessagePorts and the host's loopback MCP service are trusted-renderer/executor plumbing, not demonstrated external integration points. No credentials were extracted, backend requests made, or source-app UI restrictions bypassed. A cooperative plugin could expose its own question tool, but that would not capture every native prompt. See [OpenAI plugin extensions](https://developers.openai.com/plugins/build/extensions).

The official [MCP Events integration](https://developers.openai.com/plugins/build/mcp-events), checked on 19 October, delivers updates from a plugin's server **into** Work Cloud chats or dots. It is not documented as an outbound subscription to ordinary Chat completions. The [Codex hooks reference](https://learn.chatgpt.com/docs/hooks) documents lifecycle hooks including Stop and Interrupt; its presence does not establish that ordinary Chat runs them. These mechanisms remain distinct from the missing ordinary Chat companion feed.

The earlier Blue/Green test used the local owner stream and has Work Desktop origin metadata. That metadata and its screenshot do not independently verify regular Chat-mode coverage. This remains unverified, not a claim of impossibility.

## Claude Desktop / Cowork

Installed host: Claude Desktop 2.42304.2. The visible UI combines Chat and Cowork; a real native Blue/Green card was observed. Static native code has `tool_permission_request` and `LocalAgentModeSessions.respondToToolPermission`, but those are trusted Electron renderer channels. Its authenticated remote-control bridge is likewise not an established third-party attachment interface. No private renderer injection, session token access or native IPC impersonation was used.

Native `respondToToolPermission` can return normally for a stale ID. Its resolution event does not include the chosen decision and is also emitted for cancellation/supersession. These signals cannot be promoted to exact answer acceptance without further evidence.

Official [Claude Code hooks](https://code.claude.com/docs/en/hooks) provide a promising supported path: `PreToolUse` can supply an answer to `AskUserQuestion`, and `PermissionRequest` can carry permission decisions. A hook adapter must use per-invocation identity and lifetime; session ID plus input text is insufficient. Exact correlated `PostToolUse` results can provide stronger evidence than merely returning a hook directive.

Claude's [Cowork plugin documentation](https://claude.com/docs/cowork/guide/plugins) supports bundled hooks. [Cowork loads account-enabled plugins at session start](https://claude.com/docs/cowork/overview), separately from CLI-only `~/.claude` configuration. The [third-party-provider Desktop documentation](https://claude.com/docs/third-party/claude-desktop/extensions#plugin-hooks) additionally documents Chat hooks from version 1.52386.0. Its deployment scope must not be silently generalized to the consumer account tested here.

The consumer [plugin help article](https://support.claude.com/en/articles/13837440-use-plugins-in-claude), checked again on 19 October, explicitly limits plugin hooks and sub-agents to Cowork and Claude Code; they do not run in ordinary Chat. It likewise excludes plugin-local MCP servers from Chat. This supplies a documented reason that a listed hook is not consumer Chat coverage. The different third-party-provider deployment documentation does not override that consumer limitation.

Anthropic separately documents [Enterprise inference hooks](https://support.claude.com/en/articles/16059458-inference-hooks-overview), checked on 19 October: a centrally hosted policy endpoint can inspect prompts/tool calls across Enterprise Claude products. The fetched page says generally available; the search snippet still said beta, so the fetched page is the evidence. This is an Enterprise organization feature managed by owners, not a hook capability demonstrated on this Free consumer account. Its native question-response and completion semantics have not been validated here.

The current [Cowork architecture overview](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview) describes cloud execution by default, with local execution retained for existing deployments. Device access uses Anthropic's broker and the desktop app. A future hook adapter must establish its execution location and permitted return channel; it cannot assume every hook runs on the Mac or can reach a Mac Unix socket. The existing Mac-only probe file path is not a universal hook-execution detector.

### Live plugin experiment

The temporary [event-only probe](../experiments/claude-hook-probe) was uploaded through Claude's own UI. Claude confirmed installation, enabled it and displayed all four hooks: SessionStart, PreToolUse/AskUserQuestion, PermissionRequest and PostToolUse/AskUserQuestion. A fresh Chat conversation produced a native question; selecting Blue in the source UI submitted it. No probe event file appeared on the Mac. No matching probe-name entries were found in the ordinary text logs checked.

This verifies plugin installation and native source interaction, **not hook execution or Agent Handler integration**. The absence of the local file does not distinguish an unloaded hook from execution in another environment or a hook error.

A fresh Cowork test requested only a labeled file in the repository's temporary test directory and a native question. Neither appeared. The account UI showed Free plan; Anthropic's [Cowork requirements](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork) specify a paid plan. This account therefore did not provide a usable Cowork execution test. No subscription or permission policy was changed. The probe was disabled through Claude's UI, and its switch was verified off; the uploaded copy remains available for a future test. Cowork hook execution and an adapter round trip remain open.

## Next acceptance gates

### Native Claude audit increment

Read-only inspection found nine native local-session metadata/audit pairs on this Mac, latest modified in June. Actual records confirmed `system/init` UUIDs, SDK session IDs, root result/error fields and native permission UUIDs. Only schema/aggregate metadata was inspected; personal transcripts and credentials were not copied into the repository. The new original observer uses fabricated fixtures of these shapes, opens files read-only without following parent/file symlinks and baselines existing files at EOF. Malformed/gapped/oversize data cannot supply completion; child results and unrelated permission responses cannot clear the main state. It has no response transport.

The current Code CLI's supported `auth status` command reported signed out. Claude Desktop still showed Free, and the user confirmed on 20 October that no paid Claude account is currently available. A read-only observer probe found no new activity; historical audits did not reappear. Fresh native local observation is pending an available runtime. Current cloud Cowork execution may not produce the same local audit store, so paid access alone is not a passing integration test. Source visibility and a fresh init/result sequence must be verified.

1. Native command Cancel and browser Deny, plus fresh shell auto-opening under an eligible user-reviewed policy. Shell Allow, app Allow/Deny and browser Allow have live passing evidence in [verification.md](verification.md).
2. A fresh completed-turn question: exact native reply receipt and sibling retention, without resending an old request.
3. Claude: verify a fresh local audit init/result/wait sequence and separately establish live response ownership, callback lifetime/cancellation and acceptance before implementing response delivery.
4. Regular Chat is deferred. Revisit only with a usable lifecycle source or an explicitly selected alternative surface.
5. Real host reconnect, sleep/wake and uncertain-send restart, plus multiple-display placement in [verification.md](verification.md). Keyboard and adaptive sizing checks have passed; VoiceOver is excluded at the user's request.
