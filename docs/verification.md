# Verification record

## Automated checks

On 2026-10-19, **37 tests across 9 suites passed** using `scripts/test.sh`. The suite uses temporary databases and real Unix sockets owned by synthetic hosts; it never sends answers to a user's agent.

Coverage includes independent IDs, integer/string distinction, duplicate submissions, changed content, stale generations/revisions, scoped withdrawal, durable reservations, restart uncertainty, lost/mismatched receipts, owner changes, pre-send cancellation, revision gaps, frame fragmentation/limits, unknown stream versions, metadata discovery and panel geometry. Storage failure and Desktop's unset metadata flag were reproduced as failing regressions before fixing them.

`scripts/bundle.sh` produces an ad-hoc-signed development app. The CLI `--demo` drives the production controller through a synthetic accepted answer. The socket integration tests exercise the production adapter's framing, question decoding, response encoding and receipt verification.

## Live read-only checks

The native probe recognized the installed Desktop owner stream, including one pending question in the current conversation. Host build and protocol details are in [compatibility.md](compatibility.md). Only counts/status were recorded; no real question or answer contents are included in this repository.

The development app launched in isolated demo mode, then live observation mode. Computer inspection reported that the Mac was locked and automatic unlock failed. The user was asked to unlock it; visual interaction and native-answer acceptance remain pending.

## Manual acceptance still required

1. In demo mode, select and answer one of two questions; verify the other remains. Enter a free-text answer by keyboard and verify both are eventually cleared.
2. In live mode, answer a harmless question through Agent Handler; verify the response arrives in the source conversation and only that card clears.
3. Repeat with two simultaneous questions; answer one in the source app and one in Agent Handler.
4. Disconnect or quit the host, then reconnect. Pending cards should disable and recover only from fresh authoritative state.
5. Restart Agent Handler after an uncertain send; verify that request cannot be resent.
6. Sleep/wake, move between displays and use the menu fallback. Check focus is only taken after explicitly opening the panel.

Synthetic tests are not proof that these live interaction checks passed. Native approval support is outside this milestone.
