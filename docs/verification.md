# Verification record

## Automated checks

On 2026-10-19, the expanded approval suite passed **61 tests across 12 suites locally and in macOS CI** using `scripts/test.sh`. The suite uses temporary databases and real Unix sockets owned by synthetic hosts; it never sends answers to a user's agent.

Coverage includes independent IDs, integer/string distinction, duplicate submissions, changed content, stale generations/revisions, scoped withdrawal, durable reservations, restart uncertainty, lost/mismatched receipts, owner changes, pre-send cancellation, revision gaps, frame fragmentation/limits, unknown stream versions, metadata discovery and panel geometry. Storage failure and Desktop's unset metadata flag were reproduced as failing regressions before fixing them.

`scripts/bundle.sh` produces an ad-hoc-signed development app. The CLI `--demo` drives the production controller through a synthetic accepted answer. The socket integration tests exercise the production adapter's framing, question decoding, response encoding and receipt verification.

`ProcessCrashTests` launches a separate test-only executable against temporary ledgers and terminates it with SIGKILL, without running SQLite close or object cleanup. Three checkpoints pass: a committed reservation reopens as uncertain and blocks another attempt, committed acceptance stays accepted, and a committed definitely-not-sent outcome permits a new reservation. This exercises abrupt process death after those commits; it does not simulate power loss or every possible crash instruction.

[GitHub verification run 39298108820](https://github.com/gbettineschi/agent-handler/actions/runs/39298108820), at code/test commit `17a668ae6bf194b318cc368835bb0c71f6bbd51d`, passed on the `macos-15` ARM64 runner with Swift 6.1.2. It ran all 45 tests, built the release app, ran the controller demo and verified the ad-hoc signature. Local verification used Swift 6.3.3.

[GitHub verification run 39304238702](https://github.com/gbettineschi/agent-handler/actions/runs/39304238702), at code/test commit `46ea6e3326569147f412f6c8a548a05977a7a70f`, passed all 51 tests, the release build, controller demo and signature verification. Later documentation-only commits do not change the tested code.

[GitHub verification run 39319407861](https://github.com/gbettineschi/agent-handler/actions/runs/39319407861), at code/test commit `f1199769c335637752e4a0fa90d2bec0cbee6bbf`, passed all 61 tests, the release build, controller demo and signature verification on `macos-15` with Swift 6.1.2. Local release signature verification and the controller demo also passed.

The first CI runs exposed socket-fixture timeouts that did not reproduce locally. Each fixture's lifetime-long accept loop now owns a dedicated thread instead of occupying the shared dispatch pool. The subsequent CI run passed; shared-pool starvation is the suspected cause of the original failures, not a separately proven diagnosis. Test deadlines were not increased.

The expanded CI suite exposed a separate cancellation-test race: a fixed 200 ms preflight delay could expire before the test task was scheduled to cancel. Delaying that task by 400 ms reproduced the failure locally. The fixture now holds discovery replies until the test explicitly cancels and releases them; the delayed reproduction then passed. The permanent test uses this explicit gate, without the artificial delay. Production cancellation code was unchanged.

## UI and native acceptance checks

The native probe recognized the installed Desktop owner stream, including one pending question in the current conversation. Host build and protocol details are in [compatibility.md](compatibility.md). Only counts/status were recorded; no real question or answer contents are included in this repository.

After the Mac was unlocked, computer-use tests passed for demo keyboard text entry, option selection, two independent requests, the request selector, and collapse/reopen with pending requests retained. Each answer removed only its corresponding request.

The user explicitly delegated harmless native test answers to computer use. Two labeled test questions appeared together in Agent Handler. An option was selected and sent through its UI; the answer arrived in the source conversation and the second question remained. A fresh diagnostic controller with an empty in-memory ledger independently saw exactly one native pending question. Agent Handler was restarted, recovered that question, and submitted a typed free-text answer through its UI. That reply also arrived in the source conversation, the panel cleared, and a fresh native probe reported zero pending questions. The diagnostics never submitted answers.

Direct source-app UI interaction was blocked by the computer tool's app-access restriction. Later, the user answered two visible question cards in the source conversation; Agent Handler then showed “Nothing needs your attention”. This verifies user-driven source-answer cleanup, without claiming that the computer tool clicked the source app. The × button was clicked successfully, Escape was checked, and collapsed launch was verified.

After the approval expansion, a fresh harmless native question survived a restart into the latest release bundle. Launch was collapsed. Disabling the Desktop connection retained the card with its option, text field and Send button disabled. Re-enabling the connection restored the option after fresh source discovery. Computer use selected and sent the test answer; it arrived in the source conversation and the card cleared. An intermediate frame showed uncertain delivery. A read-only check of the latest ledger row showed `closed`, not `accepted`, so this verifies native answer arrival and authoritative withdrawal rather than exact receipt settlement. The panel was left collapsed. This tested Agent Handler's connection toggle and process restart; it did not quit or restart the source host.

## Long-conversation regression

Live testing exposed an overly broad retained projection: the current conversation occupied about 10.2 MB under the accounting formula, exceeding the 8 MiB per-conversation limit even though its active turn used about 0.7 MB. The stream rejected it before questions reached the controller.

`DesktopProjection` now retains item identity, questions and native answer envelopes while marking unrelated item fields as discarded. Nested patches into those deliberately discarded branches are ignored; required fields omitted because of size retain a distinct marker and still fail closed. Array positions, history ordering, revision checks and the 8 MiB limit are unchanged. Snapshots and patch replacements are compacted before budget admission. The regression first failed for both history formats, then passed with large tool output, a nested output patch, a changed question, and an accepted native answer. The previously rejected live conversation then became compatible and passed both answer tests.

## Completed-turn questions and reply confirmation

The user's separate Blue/Green screenshot exposed an actual missed case: a question can remain open after its generating turn completes. A read-only native snapshot contained one completed turn and one unanswered question, while the previous parser returned no requests. The parser now follows a complete, contiguous latest question group through native answer-only turns. Empty hydrating turns, incomplete item pagination, multiple history islands and unknown user-input kinds invalidate the scope instead of withdrawing requests. A temporal socket regression checks pending → unavailable → pending for the unanswered sibling.

The installed host's native submission code uses steer for a running turn and start-turn for a completed one. The adapter now mirrors that distinction, inheriting settings on start instead of rebuilding the permission/model configuration. Synthetic socket tests verify both acknowledged and lost-receipt paths and the exact outbound method/version.

In the live completed-turn test, Agent Handler displayed Blue/Green; computer use selected Blue and sent it. A fresh native observation then showed a second turn, the accepted native answer envelope, and zero pending questions. The panel briefly showed uncertain delivery. The exact native receipt was not captured, so this does not verify clean receipt settlement for that path.

Investigation independently reproduced a controller race: temporary invalidation changed sending to uncertain, and a later valid accepted receipt updated the ledger but could not settle the UI. A failing regression reproduced this and now passes. Accepted receipts may settle the same uncertain request only within the same epoch and fingerprint; changed requests, new owners/epochs and closed cards remain fenced. This explains a possible cause of the live symptom, not a proven diagnosis of its exact receipt. A brief uncertain indication before the receipt arrives remains possible. No test answer was resent, and no durable ledger entry was removed.

The separate test's local metadata identifies the Work Desktop originator. Regular Chat mode has not been independently verified. Claude Desktop 2.42304.2 rendered a native question in its Chat and Cowork interface, but there is no Claude adapter in this build. Displaying that Claude question is not evidence of Agent Handler integration.

Further live inspection also found large `hookRuns` turn metadata exceeding the same retained-state budget. Turn projection now preserves turn identity, status, items and pagination while discarding unused metadata. Both history formats pass the large-metadata and nested-patch regression; the live Work conversation was retained at approximately 1.8 MB under the unchanged 8 MiB limit.

## Process measurement

A 30.02-second sample of the release app in live observation mode used 0.28 CPU seconds, averaging **0.93% of one CPU core**. Resident memory was **75.6 MiB** at both ends (77,456 to 77,424 KiB). The app was watching up to sixteen metadata candidates while this Desktop task continued; the Mac was locked and no UI interactions occurred. This excludes startup and is one short local sample, not an idle battery benchmark, peak-memory bound or long-run performance claim. The development bundle occupies 1.3 MiB on disk.

After the retention fix, another 30.02-second live sample used 0.17 CPU seconds (**0.57% of one core**) and 101,888 to 100,944 KiB RSS (**99.5 to 98.6 MiB**). The Mac was unlocked and this conversation continued during the sample, with the panel idle. The conversation and workload had changed, so these two short samples are not a controlled before/after benchmark.

## Acceptance still required

1. Complete a fresh completed-turn question and confirm the native start-turn receipt settles cleanly after the controller fix. The previous answer reached the source, but its exact receipt was not captured.
2. Disconnect or quit the host, then reconnect. Pending cards should disable and recover only from fresh authoritative state.
3. Restart the whole app after an uncertain native send; verify that request cannot be resent. Ledger subprocess crash checks and synthetic uncertain-delivery tests already pass.
4. Real sleep/wake, multiple displays, menu fallback, full keyboard navigation and focus behavior while another app is active.
5. Independently exercise regular Chat mode and design/test a separate Claude Desktop adapter. Neither is covered by the Work-mode results.

Synthetic tests are not proof that these live interaction checks passed. Selected native approval contracts are now implemented, but their native acceptance remains unverified.

## Approval expansion and surface audit

The approval tests cover exact integer/string IDs, complete settings, automatic-review rejection, malformed/oversized requests, unknown decisions, exact command-rule objects, restricted empty confirmation forms, changes under the same request ID, separate question/approval scopes, exact native routing, lost/negative/positive dispatch acknowledgments, no retry and authoritative withdrawal. Tests reproduced the review findings before fixes: omitted permission settings were accepted, and unknown JSON Schema validation keywords could be mistaken for an empty form.

A native harmless print request was captured from the real owner stream. The initial parser rejected its structured `acceptWithExecpolicyAmendment` choice; that exact shape now has a regression and bounded native mapping. A separate read-only snapshot showed `auto_review` for the current turn and `guardian_subagent` for current permissions despite a user-reported human approval. The adapter does not reinterpret these as user review. No native approval was answered through Agent Handler, and its native command/browser/app acceptance tests remain open.

Independent review found no remaining blocker after the setting/schema fixes and command-rule mapping. Long saved-rule labels now explicitly wrap in the scrollable request view; a long native rule still needs a visual acceptance check. Diagnostics report question and approval counts separately. Unsupported approval parsing now produces a health warning, and the empty panel says “No requests to show” rather than asserting that the user has no pending work anywhere.

One intermediate full test run reported an intermittent completed-question test failure; the exact failure detail was truncated. Its isolated rerun and subsequent full runs passed. Review identified a real fixture shutdown hazard: closing a listener before its accept loop exits permits descriptor reuse by another concurrent fixture. Teardown now joins that loop before closing and shuts down peer descriptors under the fixture lock. The final 61-test run passed. This correction is not proof that the hazard caused the earlier failure.

See [surface-audit.md](surface-audit.md) for the regular Chat/Claude contract findings, official sources and temporary hook experiment. Neither a rendered source question nor a listed plugin hook is counted as Agent Handler integration.

## Granular-policy follow-up

A later active turn changed from `auto_review` to `user`, confirmed in its execution record. It uses the installed host's projectless granular preset: shell/rule/skill approval prompts are disabled, while MCP elicitation and permission requests are enabled. The user confirmed the composer says “Ask for approval.” Saved host state selected `granular`; read-only thread metadata and the app connector confirmed no local project membership. This is distinct from the earlier automatic-review turn. See [live-approval-setup.md](live-approval-setup.md) for the prepared source-project handoff; effective policy must be inspected again after it, not assumed from membership.

The string-only approval-policy parser rejected a valid native MCP confirmation under this preset. The new parser regression failed with `unsupported` before strict granular decoding and category gating were added, then passed. It also checks unknown/missing/non-Boolean flags, each command category disabled independently, exact MCP payloads and fingerprint changes after effective-policy changes. A read-only reviewer found no blocking defect; command-category edge cases suggested in review were added.

The complete local invocation ran 62 tests and reported 22 socket-related case issues in `DesktopSocketTests`, `DesktopAdapterTests`, `nativeApprovalDispatchIsNotAnExecutionReceipt`, and `approvalsStayIndependentFromIncompleteQuestionHistory`: the sandbox disallowed fixture sockets. Escalation was explicitly rejected by the granular policy before execution. The filtered **46 tests across 10 suites passed**, and the updated release bundle and ad-hoc signature verified. The earlier 61-test CI result remains attached to its earlier code commit; the granular change does not yet have a full passing suite or CI result.

The user restarted the updated bundle. A Calculator access check and a public example-page navigation completed without an observed approval card; Agent Handler had no approval to answer. They are **not** passing approval tests. The page was closed. No approval policy was changed, unknown sends retried, or production ledger entries deleted.

A subsequent fresh Clock access request **passed the real app-approval flow**. The user explicitly confirmed “I allowed the clock from agent handler.” The waiting `cua.getApp("Clock")` call then returned Clock's native interface. Agent Handler showed “No requests to show”; a read-only ledger check showed a new `closed` entry at 21:07:51 UTC. Card display and selection are user-confirmed; native tool completion, empty panel and durable closure were independently observed. The exact persistence choice and accepted receipt were not captured, so this does not verify a particular Allow scope or prove execution from a dispatch acknowledgment alone. Shell and browser-origin approvals remain separate pending checks.

Claude's native Chat test accepted Blue in the source UI, but the installed event-only probe produced no local callback file. The Cowork attempt produced neither the requested temporary file nor a native question; the account UI showed Free plan, which does not meet Anthropic's documented paid-plan requirement. This is an unavailable test environment, not a failed or verified Cowork adapter. The probe was disabled through the Plugins UI and its switch was verified off. Its uploaded copy is retained, inactive. No paid upgrade or permission change was made.

## Independent review

One fresh-context reviewer inspected the whole implementation and reproduced three Important defects with independent synthetic harnesses. All three were reproduced by failing repository tests and then fixed:

| Finding | Regression |
| --- | --- |
| Malformed turns were mistaken for authoritative empty state | `malformedTurnStoresCannotEstablishWithdrawal`, `malformedQuestionStateRetainsCardsUntilValidRecovery` |
| Revision-gap recovery could revive an older question | `gapRejectsSnapshotsBelowLatestObservedRevision` |
| One malformed conversation snapshot disabled healthy conversations | `malformedSnapshotDoesNotDisableHealthyConversation` |

Recovery retains a per-owner revision floor through gaps and reconnects, including revisions observed in gaps. Scoped malformed snapshots invalidate that conversation without disconnecting healthy ones. The stricter parser still recognized the current real question in a repeated read-only native probe.

The Minor discovery-guidance finding has been fixed: metadata errors remain visible alongside connection status and clear after successful discovery. When metadata discovery fails, Settings accepts explicit conversation IDs.

A focused independent review of `adddbdc7..ee42e38` found no blocking defects in the retention fix. Its isolated harness passed 22 mutation/failure cases across both history formats, including discarded-branch deletion/re-addition, item/array/root replacement, shifted array positions and malformed required fields. These cases were adapted into permanent `DesktopProjectionTests`; the reviewer did not operate the native host or perform UI testing.

The reviewer did not independently verify actual UI interaction, native response acceptance, real sleep/wake, whole-process termination at each crash boundary, separate-user peer rejection, future host compatibility or notarized distribution. The later subprocess tests cover the three ledger checkpoints described above. Host-side atomic targeting is unavailable in the private protocol, and neither the review nor the short performance sample proves exhaustive concurrency safety or a fixed RSS/battery bound. These remain limits, not passing results.

A focused fresh-context review of completed-question handling identified premature withdrawal during empty reply-turn hydration and unsafe traversal across history gaps. The fixes passed isolated reproductions and now have permanent parser/socket regressions. The review also reproduced the accepted-receipt settlement race; its temporary minimal fix passed 14 focused tests, including epoch, body, closure and no-retry controls. The production fix retains those same fences. The reviewer did not operate the native host.
