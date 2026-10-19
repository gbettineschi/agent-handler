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

1. Real user-reviewed shell and browser-origin decisions, each through Agent Handler with source continuation and withdrawal. The real Clock app approval is a separate passing result. See the [prepared setup](live-approval-setup.md) for the current saved-versus-active policy discrepancy.
2. A fresh completed-turn question with an exact native start-turn receipt. Answer arrival and withdrawal have passed; clean idle-receipt settlement remains unverified.
3. Source-host loss/restart, distinct from the passing Agent Handler connection toggle and application restart. Controlled socket EOF/reconnect cases pass.
4. Whole-app restart after a truly uncertain native send. Synthetic SQLite/controller reopen and ledger SIGKILL checks pass; they do not establish this native case.
5. Real sleep/wake. Display/keyboard/UI checks stay deferred with UI work. Ordinary ChatGPT Chat remains deferred and paid Claude live tests remain pending.

Synthetic tests are not proof that these live interaction checks passed.

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

## Activity backend follow-up

The user's clarified ordinary Chat scope is activity/completion tracking, without interactive questions. The implemented backend increment consumes the existing Work owner stream only; ordinary Chat and Claude activity integrations are still pending.

`ActivityTests` and `DesktopActivityTests` cover phase distinctions, attention precedence, scoped owner epochs, revisions, disconnect invalidation, canonical history boundaries, unknown request kinds and visible continuations. They were written before implementation; the new types were initially missing. Additional regressions reproduced a running turn preceding a completed turn and visible pending continuations being classified completed, then passed after conservative rejection was added. The core records latest facts only; it has no notification or response side effects.

The available socket-free command passed **59 test functions across 12 suites**. The complete invocation ran **76 test functions across 14 suites** and reported **23 socket-denial issues**: 15 cases in DesktopAdapterTests, five in DesktopApprovalTests (the native dispatch and incomplete-question-history socket tests), and three in DesktopSocketTests. These include the new completion/disconnect/stop/unfollow fixture, which therefore remains unexecuted here. The release bundle built and `codesign --verify --deep --strict` passed. `git diff --check` passed. No escalation was requested because this turn rejects sandbox approvals. These results do not replace a native activity check, real reconnect/sleep/wake test or full macOS CI run for this revision.

A fresh-context reviewer inspected `cde4938..14b97e0` and relevant existing stream/request code. It found no Critical/Important issue. A Minor misleading health summary omitted failed/cancelled counts; both counts were added. The reviewer did not independently rerun tests or operate the host. Ordinary Chat/Claude sources, whole-agent-tree completion, notification delivery and native lifecycle checks remain outside that review result.

The activity branch remains local: `git ls-remote origin HEAD` failed because this session could not resolve github.com. No new CI result is available. The previously running app has not been restarted onto the activity build.

## Independent review

### Follow-up with unrestricted local access

The complete pre-Claude suite passed **76 test functions across 14 suites**, including the previously blocked native-activity socket fixture. A current read-only Work probe reported one compatible version-11 owner stream, zero pending requests and one running turn. Network access to the private repository was also restored (`git ls-remote` succeeded).

The new Claude reducer and observer passed **92 test functions across 16 suites** in the complete suite. Tests include native phase/permission semantics, strict boolean flags, child/mismatched results, duplicate IDs, untrusted message content, incremental/partial/oversized records, EOF baseline, newly discovered old files, account separation, rotation/truncation/rewrite, symlink refusal, archives, source restart and presentation capacity. All fixtures are fabricated, with no copied personal chat content.

The read-only `--claude-probe` returned empty activity counts and `responseTransport: false`, correctly avoiding all historical local audits. The current CLI reports signed out and Desktop shows Free. This is a passing no-replay/probe check, not a live Claude turn, question or approval round trip. Cloud-only sessions without a local audit remain unsupported. The audit stream is an observation source; it does not prove per-runtime heartbeat liveness or exact answer acceptance.

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


## Claude audit review — 20 October 2026

An independent reviewer reproduced four Important defects against `b69eff9`. Each was reproduced by a failing permanent regression before the production fix:

| Finding | Fix and regression |
| --- | --- |
| EOF inside an unfinished line accepted a valid-looking suffix as a fresh init | Baselines discard through the next newline; `eofBaselineDiscardsTheRestOfAnUnfinishedRecord` |
| Audit/metadata failures retained a partially read init across a gap | Drop the cursor and preserve a required EOF baseline through repeated failures; `unavailableInputDiscardsPartialInitAndRequiresAnEofBaseline` covers both input paths |
| Unknown or contradictory error subtype/reason pairs became terminal states | Exact supported pairs only; `unknownAndContradictoryErrorSchemasRemainUnknown`. The placeholder `execution_error` fixture was replaced by the native `api_error` reason |
| A FIFO could block before descriptor-based regular-file validation | Open leaf paths with `O_NONBLOCK`, retaining the regular-file check; `nonRegularAuditFileIsRejectedBeforeWaitingForAWriter` |

The follow-up reviewer copied the current source and tests into its isolated checkout. All **24 test functions across four suites** passed, including its four independent reproductions. It found no remaining Critical/Important issue in the focused fixes. It did not verify a fresh Claude runtime, response transport or the UI.

Executor checks: the complete **96-test / 16-suite** suite passed, the release bundle built, its strict ad-hoc signature verified, and `git diff --check` passed. The repeated native Claude probe showed zero current sessions and `responseTransport: false`, without replaying history.

The previously running development app was stopped and the verified bundle relaunched. Computer use confirmed live Work activity counts and the separate `Claude local audits · 0 current · 0 need input · read-only` health line. No requests were pending. The panel was collapsed again. This verifies startup/integration, not a fresh Claude turn or real sleep/wake.

The user confirmed that no paid Claude account is available at present. Fresh Cowork/Code observation and response tests remain unavailable; ordinary cloud Claude Chat and cloud-only sessions without compatible local audits remain unsupported. Claude question/approval response delivery is not implemented. Regular ChatGPT Chat remains deferred. No subscription or source permission setting was changed.

The private branch `fix/granular-approval-policy` was published. Code commit `bd0c24e` passed [GitHub macOS verification](https://github.com/gbettineschi/agent-handler/actions/runs/39333576868): synthetic suite, release bundle, controller demo and strict signature verification all succeeded. This supersedes the earlier network/sandbox-limited results for the same backend work.


## Codex approval and reconnect pass — 20 October 2026

The user requested remaining shell/browser approval and reconnect checks before UI, leaving paid Claude live tests pending.

### Native observations

The composer was user-reported as **Ask for approval**. A read-only check of the exact saved thread preset found the granular workspace selection with shell/rule categories disabled. A separate native owner-stream snapshot (revision 19615) reported reviewer `user`, policy `never` and sandbox `dangerFullAccess` in both active-turn parameters and current permissions. The execution environment also reports `never`. These are different stored and active facts, not an automatic-review finding. The cause of the host discrepancy is still unproven. No source policy was changed, and a prohibited shell escalation was not attempted.

One harmless browser navigation completed with no human approval. Agent Handler showed only the test question, with no browser approval; the tab was closed. This is not a browser acceptance pass.

A fresh native reconnect card remained visible with its option, text and Send controls disabled while the Desktop connection was off. Re-enabling showed unavailable state first, followed by a compatible owner. User-submitted replies withdrew both test cards. This verifies disconnect/fresh recovery and source-reply cleanup, not an automated answer through Agent Handler for that first card.

A second fresh native question was left pending while the Agent Handler process was terminated and relaunched into the updated release bundle. The app launched collapsed, recovered the exact card and enabled its option only after native discovery. Computer use selected **Restart verified** and clicked **Send answer**. That exact answer arrived in the source conversation, the panel cleared and a read-only production-ledger check showed one additional `closed` entry at **2026-10-19 22:33:10 UTC** (20 October locally). The fresh read-only Work probe then found one version-11 owner, zero pending questions and zero approvals. This verifies whole-Agent-Handler restart, answer arrival and durable withdrawal; it does not capture an exact accepted receipt or restart the source host. The panel was left collapsed.

### Definite non-delivery recovery fix

New controlled socket tests reproduced an availability defect for both command and browser approvals: stop during owner-discovery preflight sent no decision, but a new epoch retained the request as uncertain even after the ledger recorded `notSent`. Core regressions reproduced both snapshot/receipt arrival orders with a changed request body; `notSent` and `rejected` failed recovery while genuinely uncertain delivery remained blocked.

The controller now restores an uncertain record to pending only when current native state is fresh and a durable ledger entry proves definite non-delivery. If the old preflight finishes after a new snapshot, the controller checks the persisted entry and attempt identity before restoring the new explicit choice. It never resends the old choice. Existing accepted-receipt owner/epoch/body guards remain intact. A real SQLite control verifies a late non-delivery result cannot undo durable closure or unlock a reused identity.

The new socket suite covers exact browser accept/deny routing and persistence scope, EOF/reconnect with changed command/browser payloads and stale click rejection, lost or acknowledged decisions across SQLite/controller reopen, and stop/cancellation before the decision write. The complete **105-test / 18-suite** suite passed; the release bundle and strict signature verified. Native shell/browser decisions remain separate pending acceptance gates.


Independent review of `663253d..14b7264` found no Critical/Important/Minor defect. Its isolated socket/controller/safety run passed 17 test functions across three suites, including 10 extra SQLite owner-change, late-closure and read-failure cases. Those three controls were retained as `RecoverySafetyTests`; the executor's full 105-test run includes them. The reviewer did not independently operate the native host and did not verify shell/browser acceptance, source-host restart or native uncertain-send restart.
