# Verification record

## Automated checks

On 2026-10-19, **41 tests across 9 suites passed** using `scripts/test.sh`. The suite uses temporary databases and real Unix sockets owned by synthetic hosts; it never sends answers to a user's agent.

Coverage includes independent IDs, integer/string distinction, duplicate submissions, changed content, stale generations/revisions, scoped withdrawal, durable reservations, restart uncertainty, lost/mismatched receipts, owner changes, pre-send cancellation, revision gaps, frame fragmentation/limits, unknown stream versions, metadata discovery and panel geometry. Storage failure and Desktop's unset metadata flag were reproduced as failing regressions before fixing them.

`scripts/bundle.sh` produces an ad-hoc-signed development app. The CLI `--demo` drives the production controller through a synthetic accepted answer. The socket integration tests exercise the production adapter's framing, question decoding, response encoding and receipt verification.

## Live read-only checks

The native probe recognized the installed Desktop owner stream, including one pending question in the current conversation. Host build and protocol details are in [compatibility.md](compatibility.md). Only counts/status were recorded; no real question or answer contents are included in this repository.

The development app launched in isolated demo mode, then live observation mode. Computer inspection reported that the Mac was locked and automatic unlock failed. The user was asked to unlock it; visual interaction and native-answer acceptance remain pending.

## Process measurement

A 30.02-second sample of the release app in live observation mode used 0.28 CPU seconds, averaging **0.93% of one CPU core**. Resident memory was **75.6 MiB** at both ends (77,456 to 77,424 KiB). The app was watching up to sixteen metadata candidates while this Desktop task continued; the Mac was locked and no UI interactions occurred. This excludes startup and is one short local sample, not an idle battery benchmark, peak-memory bound or long-run performance claim. The development bundle occupies 1.3 MiB on disk.

## Manual acceptance still required

1. In demo mode, select and answer one of two questions; verify the other remains. Enter a free-text answer by keyboard and verify both are eventually cleared.
2. In live mode, answer a harmless question through Agent Handler; verify the response arrives in the source conversation and only that card clears.
3. Repeat with two simultaneous questions; answer one in the source app and one in Agent Handler.
4. Disconnect or quit the host, then reconnect. Pending cards should disable and recover only from fresh authoritative state.
5. Restart Agent Handler after an uncertain send; verify that request cannot be resent.
6. Sleep/wake, move between displays and use the menu fallback. Check focus is only taken after explicitly opening the panel.

Synthetic tests are not proof that these live interaction checks passed. Native approval support is outside this milestone.

## Independent review

One fresh-context reviewer inspected the whole implementation and reproduced three Important defects with independent synthetic harnesses. All three were reproduced by failing repository tests and then fixed:

| Finding | Regression |
| --- | --- |
| Malformed turns were mistaken for authoritative empty state | `malformedTurnStoresCannotEstablishWithdrawal`, `malformedQuestionStateRetainsCardsUntilValidRecovery` |
| Revision-gap recovery could revive an older question | `gapRejectsSnapshotsBelowLatestObservedRevision` |
| One malformed conversation snapshot disabled healthy conversations | `malformedSnapshotDoesNotDisableHealthyConversation` |

Recovery retains a per-owner revision floor through gaps and reconnects, including revisions observed in gaps. Scoped malformed snapshots invalidate that conversation without disconnecting healthy ones. The stricter parser still recognized the current real question in a repeated read-only native probe.

One Minor finding is deferred: discovery failure guidance can be replaced by generic connection status. When metadata discovery fails, use Settings to enter conversation IDs explicitly; the README describes that fallback.

The reviewer did not independently verify actual UI interaction, native response acceptance, real sleep/wake, whole-process termination at each crash boundary, separate-user peer rejection, future host compatibility or notarized distribution. Host-side atomic targeting is unavailable in the private protocol, and neither the review nor the short performance sample proves exhaustive concurrency safety or a fixed RSS/battery bound. These remain limits, not passing results.
