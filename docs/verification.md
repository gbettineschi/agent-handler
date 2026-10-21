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

1. Real user-reviewed shell deny/cancel and browser-origin decisions, each through Agent Handler with source refusal/continuation and withdrawal. A live shell Allow passed on 2026-10-20 (see the dated result below). The real Clock app approval is a separate passing result. See the [prepared setup](live-approval-setup.md) for the current saved-versus-active policy discrepancy.
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

Code/test commit `5336575` passed [GitHub macOS verification](https://github.com/gbettineschi/agent-handler/actions/runs/39336171264), including the full synthetic suite, release bundle, controller demo and strict signature. A final read-only native policy check at revision 20713 still reported user/never/dangerFullAccess and zero pending requests. The following documentation-only commit records these results; no production code changed after that CI-tested commit.

## Project-backed approval retest — 20 October 2026

The official app connector confirms this existing conversation now belongs to the local agent-handler project and uses its directory. The new active turn's execution context reports reviewer `user`, `workspace-write`, network disabled, and granular flags `mcp_elicitations: true`, `request_permissions: true`, `sandbox_approval: false`, `rules: false`, `skill_approval: false`. The earlier active `never`/full-access discrepancy is no longer present in this turn. Shell approval eligibility is still absent; no prohibited escalation was attempted. User-level config contained no approval/sandbox override keys.

A controlled IANA browser tab opened without a captured browser-origin approval. The user reported no Chrome access prompt. The existing-tab variation was stopped because the user was actively changing Chrome; no unrelated tab was navigated or closed. These are not browser approval acceptance passes.

Chess and Dictionary app access both returned successfully. The user explicitly said they allowed them in Codex, and that nothing appeared in Agent Handler. The host's own log records MCP acceptance responses at 22:59:45 and 23:02:17 UTC, both with `persist: session`. No Agent Handler submission was recorded for these calls. A concurrent native-UI check did not capture either pending card and cannot establish successful interception or denial.

A fresh diagnostic question then failed to appear too. Computer use observed `Desktop unavailable or incompatible` and no requests; the user independently confirmed this conversation was absent. ChatGPT remained running on the same tested version/build. The current thread was unarchived and within the newest 16 metadata candidates. Thus this pass has a source-connection regression to diagnose before attributing the missing cards to approval parsing.

Read-only shell socket connection is separately denied by the current execution sandbox (`EPERM`); it cannot supply a native source snapshot. That restriction does not establish why the independently launched companion is unavailable. Temporary native-app instrumentation records connection stages, failure categories, frame sizes, snapshot admission and approval structure without transcript or command bodies. The first capture point only ran after a valid snapshot and produced no file during the unavailable state; connection-start and failure capture was added. This is investigation work, not a verified fix, and must be removed before publishing final code. Earlier 105-test/CI evidence applies to the earlier production code, not this temporary instrumentation.

## Large-snapshot connection fix — 20 October 2026

The revised native capture established a specific failure: the selected conversation used the default Codex home and reached its owner, but a **33,126,550-byte** native frame exhausted the JSON parser's **200,000-node** allowance at depth 11. The failure happened before post-parse projection, disconnecting the stream and hiding both questions and approvals. No approval-policy change would repair that decoding failure.

Regressions first reproduced the failure for overlay/canonical histories with large unused metadata and for a valid pending approval. The fix applies the existing projection while parsing the native snapshot path: unused turn, item and unrelated permission-parameter values become discarded markers without allocating their value trees. Raw approvals, effective permission fields, patch values, identities and array positions retain their existing meaning. Skipped values keep duplicate-key, depth, finite-number and key-length checks, plus a separate 1 MiB temporary key budget. Existing oversized-string omission behavior is unchanged. The 200,000 retained-node allowance, 128 MiB frame ceiling and retained-state budgets are unchanged. Oversized replacement patches remain a separate conservative limit.

All temporary capture code and hard-coded conversation targeting were removed. The **112-test / 19-suite** full run passed, including real synthetic-socket delivery of both request scopes, direct snapshot reads, scratch-budget exhaustion/restoration, malformed and escaped duplicate keys, nonfinite numbers and retained-node/depth limits. Independent read-only review found no Critical/Important issue; its 100 projection-equivalence cases and adversarial skip-validator checks passed. Its minor comment and edge-test suggestions were incorporated. Release bundle construction and strict ad-hoc signature verification passed.

With permissions available for the read-only probe, the updated decoder regained this exact native version-11 conversation and reported running activity. A fresh native question was then left pending while the old diagnostic app was stopped and the verified release bundle relaunched. Computer use observed the recovered card in Agent Handler, selected **Recovered after the large snapshot**, and clicked **Send answer**. That exact reply arrived in the source conversation and the card cleared. The delivery ledger contained 13 closed entries, with the new closure at **2026-10-19 23:25:51 UTC** (20 October locally). This verifies pending-question recovery, native answer arrival and durable closure after the fix, without treating a dispatch acknowledgment as execution proof.

A subsequent Font Book access completed without producing any native pending request: the independent read-only watcher observed zero raw and zero supported approvals. The current owner snapshot at revision 24008 reports reviewer `user`, policy `never` and `dangerFullAccess` in both active settings and current permissions. Therefore no post-fix live app Allow/Deny pass is claimed; shell/browser and fresh eligible app approvals remain pending. No source approval setting was changed by Agent Handler.

## 2026-10-20 — shell Allow and compact interface

The user changed this conversation from full access to Ask for approval. A requested escalation ran only `/usr/bin/printf` with a harmless test string. The user confirmed approval in Agent Handler and supplied a screenshot of the exact command, directory, reason and native choices. The command returned successfully and a newly closed delivery-ledger entry was observed at 2026-10-19 23:36:10 UTC (20 October local time). This verifies a real shell Allow through the companion after the large-snapshot fix; it does not verify Deny/Cancel or browser permission decisions.

The UI pass preserves the existing request controller, ledger and response transport. It adds a compact status pill, system typography/SF Symbols, explicit expansion, a small settings view, shared visible warnings, and in-memory drafts keyed to exact request fingerprints. A single hosting tree survives collapse. Completed/withdrawn requests discard their drafts. Questions use a smaller panel than approvals, and the empty state is smaller again. No custom motion, third-party UI dependency, source-app jumping, or automatic approval is introduced. Open Vibe Island was inspected as a visual reference; its UI code and assets were not copied.

Computer use against the isolated in-memory demo verified: option selection does not send; Return does not implicitly answer or approve; explicit Send removes only its own request; a synthetic Cancel removes only that approval; free-text keyboard input; draft retention across Escape/reopen, Settings and request switching; readable multiline command/rule labels; native request/display menus; and smaller empty/question layouts. The demo’s accepted transport never executes a command or contacts an agent, so its Cancel result is UI coverage, not native refusal coverage.

Native automated input exposed an internal-dismissal bug: the local event monitor compared the global cursor location even for events addressed to the panel. Local clicks in the panel are now excluded from outside dismissal; a subsequent click and keyboard entry stayed open and correctly filled the answer. A source review also required deferred focus-loss dismissal to recheck whether the panel had already regained key status. Outside mouse and focus-loss collapse are implemented, but physical outside-click/focus-switch behavior remains a manual acceptance gate: this computer tool’s background app actions did not provide a reliable OS focus transition. Multiple displays, full keyboard navigation, VoiceOver, increased-contrast rendering and actual sleep/wake also remain pending.

The full local suite passes **117 tests across 20 suites**. It includes draft validation (stale options, mutually exclusive text/option answers, exact text and UTF-8 limits), bounded panel geometry and a structured source-approval warning. Independent source review found no remaining Important issues after its focus guard correction. The final release build and strict ad-hoc signature verification also passed. No fresh post-UI native approval is claimed while this conversation uses full access.

The final live check also caught an existing compatibility gap: using the native image-view tool adds an `imageView` turn item, which the question adapter’s observed-type allowlist lacked. Read-only inspection confirmed the 35.7 MB snapshot decoded and its retained cost remained about 4 MB, but questions rejected the new item and Work attention became unknown. A regression failed for both canonical and overlay histories. The adapter now recognizes this observed non-question item; only `agentMessage` can create questions and only native user-answer types can settle them. Unknown item kinds remain rejected. This fix is included in the 117-test result. No transcript or image payload was saved by the read-only diagnostic helpers.

After rebuilding with the observed-item fix, a fresh read-only probe of this conversation reported one compatible v11 owner stream, one running Work turn, zero pending questions/approvals and zero unknown activity. The live app separately showed two connected Desktop conversations and this running turn. It was left in live mode, collapsed. This verifies restored observation after the UI pass; it does not substitute for a new native approval decision.

[GitHub macOS verification 39344381997](https://github.com/gbettineschi/agent-handler/actions/runs/39344381997) passed at code/test commit `32ed16fae320759f5fbc0a7980bcdcaebef7716e` on `macos-15` with Swift 6.1.2: all 117 tests, release bundle, synthetic controller round trip and strict ad-hoc signature check. The subsequent verification-note commit changes documentation only.


## 2026-10-20 — session list and UI polish

The live tracking-count footer was removed. Sessions remain visible without requests, ordered by existing Desktop metadata recency, with their latest known turn status. Pending input takes priority over an unavailable sibling request; stale activity stays unknown rather than presenting an old completion as current. The full local suite passed **120 tests across 21 suites** after the final code changes.

The offscreen renderer uses production views and the real controller with an in-memory synthetic transport. Ten fixtures assert logical panel dimensions and render questions, approvals, long/narrow text, unavailable/uncertain delivery, sessions without requests, settings, a high-contrast window appearance, and the collapsed pill. An actual sizing regression was reproduced: intrinsic hosting size expanded unavailable/uncertain panels beyond their intended frame. Both production and fixture hosts now leave size ownership to the panel, and all ten dimension assertions pass. This is visual inspection plus geometry/state checking, not pixel-diff regression testing.

Before the user resumed using the Mac, native demo testing verified option selection and Command-Return removed only the selected question, and no-request sessions remained visible. Subsequent outside clicks came from concurrent Mac use, so further visible automation was stopped. A demo card confused the user because it had no source counterpart; the app was restored to live mode. Demo rendering does not establish native answer or approval delivery. Full keyboard traversal, VoiceOver, system Increase Contrast, physical outside-click behavior and multiple displays still need manual acceptance. No new native approval decision is claimed in this full-access turn. See [visual review](ui-review.md).

[GitHub macOS verification 39379410036](https://github.com/gbettineschi/agent-handler/actions/runs/39379410036) passed at code/test commit `d1d28cada75827a4c3a0a38cf8fc1439531336d9`: synthetic tests, all ten offscreen renders, release bundle, controller demo and strict ad-hoc signature verification. Synthetic render artifacts are attached to that run. After rebuilding, the running process was verified without `--demo`; a fresh read-only probe reported one compatible v11 owner stream, one running turn, and zero pending questions/approvals. The subsequent commit changes this verification note only.


## 2026-10-20 — menu-bar replacement and live keyboard checks

The floating pill was replaced with a native status item and an anchored panel. UI presentation now tracks observed finish time and dismissals separately from the provider and delivery ledger. Countdown expiry never changes source status. Native title inspection found the discovery database's `title` held the opening prompt while the verified owner state's `title` matched the actual chat name. The adapter exposes bounded presentation titles from already-followed owner snapshots; a real socket fixture checks retrieval, rename, unfollow and absence of answer sends.

The full local suite passed **128 tests across 22 suites**. Added lifecycle regressions cover the exact five-minute boundary, repeated snapshots, persisted countdown/dismissal, resumed/new turns, launch history, new finished chats discovered after startup, offline completion on restart, unknown status and reduced-motion policy. Menu geometry checks cover negative-coordinate displays, small screens and offscreen Ice anchors.

In the rebuilt live app, native accessibility inspection confirmed proper source titles, including this conversation. A single labeled live question was opened from its session row, answered using keyboard text entry and Command-Return, received in this source conversation, and cleared in Agent Handler. An unrelated pending source question remained and was not answered. There was a brief uncertain indication, so clean native receipt settlement is not claimed. Settings opened through Command-comma. Tab/Shift-Tab focus traversed header and tracking controls with a visible ring after temporarily enabling macOS Keyboard Navigation; its original off setting was restored and read back. No permission mode, source setting, or unrelated answer was changed.

Nine offscreen panel fixtures and ten original glyph renders passed. These are bounded state/layout and visual checks, not a full screen-reader or gesture audit. See [UI review](ui-review.md). Full VoiceOver spoken navigation, live finished-row dismissal, and pending provider approval/paid Claude acceptance still require separate evidence.

System Increase Contrast was also tested in the live release: the list remained readable, native labels persisted, and contrast plus automatically changed transparency were restored to their original off values. VoiceOver was briefly enabled, but the computer tool could not expose its caption/cursor window. That attempt is incomplete, not a spoken-output pass; VoiceOver was restored to its original off setting.

The close check initially looked like a failure because computer-use inspection immediately showed the panel again. Temporary lifecycle tracing reproduced **collapse → `panel.isVisible == false` → application reopen → show** for both Escape and the × button. The inspection tool's subsequent reopen event caused the apparent failure. Tracing was removed, the exact committed sources restored, the signed live build rebuilt, and the app launched without `--show` so its panel remained closed for the Ice check. No workaround was added to product dismissal behavior.

[GitHub macOS verification 39381994131](https://github.com/gbettineschi/agent-handler/actions/runs/39381994131) passed at code/test commit `0bc318695ea6b353f89f3e8fb9d020d2d1d86bef`: all synthetic tests, the nine-panel/glyph render matrix, release bundle, controller demo and strict ad-hoc signature check. The subsequent commit updates verification documentation only. Physical Ice reveal/menu-bar click and full spoken VoiceOver acceptance remain pending.


## 2026-10-20 — final detail polish

The user confirmed that Ice exposes the robot icon and clicking it opens the panel. VoiceOver was explicitly removed from scope. Latest-first ordering is retained; rows now give titles full width and put source/state/countdown underneath. Added hover/press feedback, a single focus outline, shorter settings text, truthful empty state, and consistent Open behavior without repeatedly fading an already visible panel.

A finished-turn hide now offers ten-second Undo, with Command-Z mounted only on the sessions route. A small restore menu recovers an individual currently observed hidden finished turn later. Neither resets its countdown or changes provider subscriptions. Regressions cover exact-turn restoration, repeated undo, old-turn refusal, expiry, resumed/unknown source state and hidden filtering. An expanded render exposed demo examples retaining prior hidden rows; a real AppModel regression reproduced two failed assertions, then passed after demo-only reset cleared presentation state.

Local verification passes **133 tests in 22 suites**, fifteen bounded panel renders and the existing glyph matrix. Source review found no Important issues. The live panel showed compact rows and an actual finished session's countdown decreasing toward expiry. A hidden Job tracker row was selected in the native restore menu and returned to the list; the other pre-existing hidden row was left unchanged. Automated coordinate/list-row attempts did not provide conclusive ×/Undo acceptance evidence, so no physical dismissal/reappearance pass is claimed. No source messages, questions or approvals were answered during this polish pass.

[GitHub macOS verification 39433428315](https://github.com/gbettineschi/agent-handler/actions/runs/39433428315) passed at `73ea34fe597c7c436afd5a595d62198cd3c4624d`: synthetic tests, fifteen-panel/glyph render matrix, release bundle, controller demo and strict ad-hoc signature check. The signed live app was rebuilt and launched without demo or show arguments. The following documentation-only commit records this result.


## 2026-10-20 — adaptive panel height

Replaced fixed route heights with natural-content measurements. The window keeps its top anchor, animates height in 0.14 seconds (disabled for Reduce Motion), and caps at 640 points or the display bounds. Scroll content, fixed actions, banners and controls are measured separately; repeated refreshes do not restart an animation toward the same target. Requests, drafts, controller and provider transport are unchanged.

The placement regression first failed with 874 rather than the intended 640-point cap, then passed. All **133 tests in 22 suites** pass. All fifteen offscreen layouts pass using adaptive height, with a bounded convergence check after resizing (including native-scrollbar text reflow). The same hosting tree passed growth/shrink sequence `[337, 213, 357, 213, 375, 213, 213, 337]`; forcing the multiline-banner viewport to 100 points preserved its natural measurement. Review identified constrained-banner measurement, fixed with natural vertical sizing; final review found no remaining Important issues.

In the live app, native × on the finished Job tracker row removed it and exposed Undo; clicking Undo restored that exact row. Screenshots showed the panel shrink and grow (approximately 340 → 311 → 340 logical points including the Undo footer). Settings Connection details expanded the window from 375 to 479 points, then collapsed back to 375; the list returned with the original rows. This closes the earlier native finished-row ×/Undo acceptance gap. No backend request was answered, no source message was sent and no system preference changed.

The first macOS CI pass exposed one native-scrollbar reflow (`499 → 484`) before approval layout settled; the fixture now requires two stable measurements within six layouts, rejecting persistent feedback. [macOS verification 39435266402](https://github.com/gbettineschi/agent-handler/actions/runs/39435266402) passed at `dfc15181b717a2b4cb8a89550f5d4211bd67055c`: synthetic tests, adaptive renders and same-tree transitions, release bundle, controller demo and strict signature. The live app remains the signed non-demo build; the subsequent commit only records verification.


## 2026-10-20 — discovery failure resilience

User screenshot showed discovery unavailable and an empty list. The old catch discarded the actual error and passed an empty discovery set to the adapter, removing subscriptions; unchanged metadata could defer another read for sixty seconds. Original trigger cannot be reconstructed because that build retained no error reason. A concurrent read-only diagnostic at investigation time read sixteen candidates and found a compatible native stream, so permanent file/schema incompatibility was not established.

Discovery now preserves the last successful candidate/title set on any read failure, retries on the next five-second poll regardless of metadata signature, and only an authoritative successful read (including an empty result) replaces that set. Cached IDs never confer response authority or running/completed state. User copy explains automatic retry instead of asking for IDs. Health and unified logs retain fixed operation names and numeric SQLite/errno failures, without chat contents. Failed initial empty discovery does not establish a finished-session baseline.

An exclusive-lock fixture first reproduced the old misdiagnosis (`unsupportedSchema` instead of busy); after the fix it reports busy and reads again after unlock. Retention/repeated failures, authoritative empty success and initial failure/recovery are covered. All **136 tests in 23 suites**, fifteen adaptive render cases and same-tree resizing checks pass. Read-only review found no actionable defects.

The signed live process logged `Conversation catalog ready: 16 candidates`. Native UI inspection then showed four real sessions (Job tracker, this conversation, Vinted and Yaris), with current activity labels and no discovery-warning banner. No response/approval was submitted and the native database was not modified. This demonstrates current recovery after installing the fix, not proof of the original failure's exact cause or a live exclusive-lock test against the user's database.

[macOS verification 39443340475](https://github.com/gbettineschi/agent-handler/actions/runs/39443340475) passed at `a8b45890193f85fd2de3f4a1c7bb38c2cd69cb0b`: all 136 tests, adaptive UI matrix and transitions, release bundle, controller demo and strict ad-hoc signature. The following documentation-only commit records the result.


## 2026-10-20 — source labels and live activity hints

Replaced Work with Codex/Claude source labels, dots with native progress indicators (static gear for Reduce Motion), header dots with the agent glyph, and unlabeled restore history with Hidden. Read-only inspection of native item shapes found running turns whose latest items are reasoning markers without status, and completed command items. Activity hints read only retained type/status; reasoning/message bodies and projection limits are unchanged.

Optional hints are separate from lifecycle/response authority. Latest reasoning markers show Thinking; other supported hints require inProgress. The parser never scans back past a completed or unknown last item. The store clears hints on disconnect, owner replacement, malformed newer snapshots, input and terminal phase. App presentation polls in-memory activity each second. Claude remains generic status with its current read-only adapter.

A nil parser stub first failed the Thinking/Running command expectations; implementation passes. Tests also cover supported/unknown item statuses, no backward revival, stale-revision refusal, hint withdrawal and provider labels. **140 tests in 23 suites**, sixteen adaptive visual cases and same-tree sizing pass locally. Source review found no Important defect and notes Thinking is a latest-marker hint, not proof of continuous model computation.

The signed live build showed two actual Codex conversations. Native inspection first showed this chat Running and Job tracker Thinking; a subsequent screenshot showed Job tracker Running and this chat Thinking. The header robot and labeled Hidden menu were visible. No source question/approval was answered, and no native command was triggered just to produce an activity hint. Other specific activity labels have fixture coverage, not separate live acceptance.

[macOS verification 39446141360](https://github.com/gbettineschi/agent-handler/actions/runs/39446141360) passed at `1954bc45aae25b92df362977e654f9370c87af3a`: 140 tests, sixteen adaptive visual cases and same-tree transitions, release bundle, controller demo and strict signature. The subsequent documentation-only commit records this result.


## 2026-10-21 — finished-session expiry and automatic opening

Finished rows now have a persisted 300-second display deadline. Repeated observations, Undo, Hidden and restarts cannot extend it. Older records migrate from their original known finish time, or receive a display-only grace period when no finish time was known. Unknown or unresolved-input rows never expire; resumed work/new turns return automatically. Source observation continues. Initial terminal history is not a new completion event.

Three persisted switches control automatic opening independently: blocking input defaults on, terminal session endings off, and non-blocking Codex questions off. Only fresh pending request keys qualify; sending/uncertain/unavailable states cannot trigger an opening. Existing pending requests are consumed even with their option off, and reconnects do not replay them. Explicit Claude audit permission waits can reveal the sessions view without granting response authority. Completion, failure and cancellation can trigger the finish option only on newly observed transitions. Automatic presentation never replaces a route already open and does not make the window key.

The red tests first reproduced retained expired rows and the nil automatic-opening stub. All **153 tests in 24 suites** pass, covering exact expiry boundaries across all terminal outcomes, restart/migration, unresolved input, initial history, repeated completion events, independent settings/persistence, paused behavior, reconnects, Claude unknown gaps and more active requests than the history bound. Seventeen adaptive visual cases include the post-expiry list; settings and same-tree height transitions pass. Read-only source review found no Important issues.

Local development tools changed overnight: the default macOS 27 SDK references a missing SwiftUI State macro plugin. Local validation and the signed live bundle used the installed macOS 26.5 SDK with Swift 6.4 and native SwiftPM via task-local wrappers. No system developer setting or project source was altered to bypass that SDK defect. CI remains on its configured macOS toolchain.

Native verification: all three switches were present with defaults on/off/off. Non-blocking was temporarily enabled. A first real asynchronous question arrived while the panel was already open and left its sessions route intact; it was answered through Agent Handler. The panel was then closed explicitly (observing another app to avoid the computer tool's reopen side effect). A second native question triggered the app log `Automatically opened panel; keyboard focus: false` before any subsequent Agent Handler observation. The request view and exact second question were visible; the test answer was submitted there, the card cleared, and the source reply arrived. Non-blocking was restored to off; final switches were verified on/off/off. Calculator's prior 3 × 3 = 9 display was restored after neutral focus setup.

Fresh blocking approvals and native terminal-transition auto-opening have policy/fixture coverage in this pass, not separate new live acceptance. Existing approval response transport was unchanged; paid Claude live tests remain pending as previously scoped. No source approval was granted in this pass. The two emitted questions were harmless self-tests answered via the companion.

[macOS verification 39615534283](https://github.com/gbettineschi/agent-handler/actions/runs/39615534283) passed at `b5feae65d2897eaf9e59bb88d301018c8e785c86`: all 153 tests, seventeen adaptive visual cases and same-tree transitions, release bundle, controller demo and strict ad-hoc signature. The following documentation-only commit records this result. The installed live app retains verified defaults blocking on / finished off / non-blocking off.
