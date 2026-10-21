# Menu-bar interface review

The floating notch pill has been removed. A native NSStatusItem opens a bounded panel under its actual button. A hidden/offscreen Ice anchor is clamped to the display; reopening the app bundle provides a way to reach the panel before revealing the item. No hover expansion is used. Independent settings control automatic opening for blocking input, finished sessions, and non-blocking questions; only blocking input defaults to on. Automatic opening does not take keyboard focus or replace an already-open route. The selected menu-bar item stays highlighted while its panel is open.

## States and count

| State | Menu-bar treatment |
| --- | --- |
| Working | Original monochrome agent glyph, subtle four-frame motion at 4 fps |
| Question or approval | Exclamation badge; working sessions can still animate |
| Unknown/disconnected source | Question-mark badge; never presented as success |
| Failed | Cross badge and labeled failure in the list |
| Recently finished | Check badge when no higher-priority state exists |
| Paused | Pause badge |
| Idle | Still agent glyph and zero |

The number counts active sessions plus observed finishes younger than 300 seconds, once per session. Finished rows disappear after 300 seconds without displaying a countdown; deadlines survive restart. Their × hides only that finished turn; subscriptions continue, and new/resumed activity or unresolved input becomes visible again. Dismissals and finish times survive app restart. Launch-history completions receive only a display expiry grace period, without being counted or announced as new finishes; the initial baseline includes explicit and pinned subscriptions as well as discovered chats. A newly discovered finished chat after that baseline can enter the count.

Reduce Motion stops both glyph motion and the short opening fade. The window has one animation owner and never combines a window resize animation with a SwiftUI spring. Exact approval choices remain multiline buttons without a default keyboard action.

## References inspected

The [Open Vibe Island panel](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Views/IslandPanelView.swift) and [window controller](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/OverlayPanelController.swift) demonstrate state-driven surfaces and explain why mixing AppKit and SwiftUI size animations caused jank. Notchi's SessionSpriteView at local checkout `e6f8b8a805cec31b5d3844d2ea8faa7a836ebc7e` shows pausing motion under Reduce Motion. No sprites, artwork or UI code from these references were copied. The menu-bar glyph is original template artwork. Apple's [menu-bar guidance](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [motion](https://developer.apple.com/design/human-interface-guidelines/motion) and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) inform the restrained behavior, system tint, explicit actions and labeled states.

## Repeatable visual checks

Run `bash scripts/render-ui.sh`. It creates unshown windows, uses a real controller with an in-memory synthetic transport, and never contacts an agent. Seventeen panel cases assert logical dimensions; images are inspected manually. Seven icon states and all four working frames are also rendered; see the [glyph sheet](images/ui/status-glyphs.png). This is not pixel-diff regression testing.

| State | Preview |
| --- | --- |
| Question | [Image](images/ui/question.png) |
| Exact wrapping approval rule | [Image](images/ui/approval.png) |
| Long question | [Standard](images/ui/long-content.png), [narrow](images/ui/long-narrow.png) |
| Unavailable | [Image](images/ui/unavailable.png) |
| Uncertain delivery, no resend | [Image](images/ui/uncertain.png) |
| Sessions without requests, dismiss controls | [Image](images/ui/sessions.png) |
| Narrow and long titles | [Narrow](images/ui/sessions-narrow.png), [long titles](images/ui/sessions-long-titles.png) |
| Recent finish and Undo | [Recent finish](images/ui/sessions-recent.png), [Undo](images/ui/sessions-undo.png) |
| Seventeen sessions and empty | [Many](images/ui/sessions-many.png), [empty](images/ui/empty.png) |
| Settings | [Image](images/ui/settings.png) |
| High-contrast window appearance | [Image](images/ui/appearance-high-contrast.png) |

All examples are synthetic and marked DEMO. The live app launches without `--demo`. High-contrast NSAppearance does not establish system Increase Contrast acceptance.

## Live checks

The live release showed actual native chat titles after fixing the metadata-title mismatch. A labeled native question was opened from its session row; keyboard text entry and Command-Return delivered the answer to the source conversation, and the test card cleared while the unrelated question remained. An intermediate uncertain state was visible; no automatic resend occurred. This confirms arrival and withdrawal, not a separately captured exact native receipt.

Command-comma opens Settings. With macOS Keyboard Navigation temporarily enabled, Tab and Shift-Tab traversed controls and showed the focus outline; the original off preference was restored. Native inspection found named headings, buttons, answer fields, session titles and state labels. System Increase Contrast was enabled temporarily; the live list remained readable and contrast/transparency were both restored. VoiceOver was briefly enabled, but the computer tool could not expose its caption or cursor output; it was restored to off without claiming spoken-output acceptance. Temporary native lifecycle tracing verified Escape and × both make the window invisible. The computer inspection tool then sends an app-reopen event, which explained why observation appeared to undo the close; the tracing was removed and committed sources restored. The user confirmed the robot is visible in Ice and clicking opens the panel. Physical finished-row dismissal/reappearance is not inferred from the synthetic tests. Provider approval and Claude acceptance gaps remain in [verification](verification.md).

## Detail polish

Chat titles now take the full row width, with compact source/status/countdown underneath. Actionable rows have restrained hover/press feedback; focus has a single outline. The latest-first ordering stays intact. Settings text is shorter, empty state avoids implying that an unknown job succeeded, the Open command always opens, and an already visible panel does not repeat its fade.

Hide has a ten-second Undo available only on the sessions route, so Command-Z cannot capture answer-field editing. The restore menu recovers individual hidden finished rows after that offer expires. Both use exact source/turn identity and preserve the original countdown. A real hidden Job tracker row was restored through this menu while the other pre-existing hidden session was left hidden. Native list-row inspection alone does not establish that the × hit target was exercised successfully.

The expanded matrix adds narrow sessions, long titles, countdowns, Undo, sixteen sessions and a fully empty panel. Demo reset now clears its own dismissal state between examples. The full local suite passes 133 tests. VoiceOver is out of scope at the user's request.


## Content-driven height

Fixed 260/400/480-point presets are replaced by measured natural content height. Scroll content is measured inside its viewport, separately from header/navigation/actions, banners and Undo. Route removal removes its measurements. The top edge remains anchored while a short AppKit transition changes height; Reduce Motion disables it. The 640-point/display cap keeps long content scrollable. Approval actions retain their own measured area up to 180 points. Session rows use a measured scroll stack, also exposing each finished-row × as an individual native button.

All fifteen render fixtures now use measured sizing and check that measurement stays stable after resizing. A same-hosting-tree sequence covers three sessions → one → multiline banner → clear → settings → list → empty → restored, including a forced 100-point viewport. Live testing exercised Job tracker ×, Undo, and opening/closing Connection details. The row disappeared and returned, and the window resized in both directions. No source request or answer was sent.


## Provider and activity clarity

Rows show Codex or Claude instead of Work. Running rows have a native progress indicator, with a static gear under Reduce Motion. The header uses the original agent glyph; the ambiguous history glyph is replaced with a labeled Hidden menu. Source tooltips describe the Desktop connection and Claude's read-only coverage.

Codex activity hints come only from the latest item in the newest validated running turn. A native reasoning marker may show Thinking; tools/messages need explicit inProgress status for their specific labels. Completed/unknown items fall back to Running rather than reviving older activity. Thinking is a latest-activity hint, not a claim of continuously measured model computation. No reasoning content or message body is read for these hints, and the bounded JSON projection is unchanged. The app reads the in-memory activity state once per second. Hints clear on disconnected/replaced owners, invalid snapshots, input, or completion.

The [thinking fixture](images/ui/sessions-thinking.png) uses the real ActivityStore path. Native live inspection showed Codex labels and successive Running/Thinking changes in two real conversations, plus the labeled Hidden menu. Individual command/edit/search/tool hint shapes are fixture-verified; no native command was launched solely to manufacture a UI state.


## Automatic opening and finished-session expiry

Finished rows have a durable five-minute display deadline, including historical rows first seen at launch. The menu-bar count still distinguishes newly observed finishes from launch history. Expired or dismissed records do not stop source observation; resumed activity, a new turn or unresolved input returns to the list. Undo and Hidden preserve the deadline. An expired manually hidden turn cannot be restored.

The Open automatically settings group has independent blocking input (default on), finish (off), and non-blocking question (off) switches. Current Codex native questions are asynchronous and use the non-blocking switch. Supported pending approvals and Claude's explicit read-only permission-wait signal use blocking. Unknown state never substitutes for a confirmed blocking request. Pending request keys are consumed once, including while options are off; reconnects and re-enabling a preference do not replay them. Terminal notifications come from transitions observed this run; initial terminal snapshots do not open the panel. Completed, failed and cancelled turns all qualify as endings.

Automatic presentation preserves keyboard focus in the other app, and leaves the selected question/settings alone if the panel is already open. Manual opening still makes the panel key for keyboard use. No answer or approval is ever submitted by this policy.

The [expired fixture](images/ui/finished-expired.png) verifies that only the still-running session remains after the deadline. Settings rendering includes all three switches within the adaptive height limit.


## Stable ordering and quieter session rows — 21 October 2026

Session ordering is presentation state, persisted separately from lifecycle and delivery. New intervention identities promote a waiting row above ordinary rows; the most recently observed intervention comes first. Running hints, metadata recency, polling, owner reconnects and partially hydrated request scopes cannot reshuffle it. Ordinary rows move on observed finishes, native user input identities and interventions. Native question responses use their accepted input marker; local approval decisions retain exact-key accounting until source withdrawal. Typed approval closures also cover source-app decisions. Withdrawal affects presentation recency and does not establish that a command executed.

The native loading spinner has been replaced with the original agent glyph in blue, gently bobbing and blinking at a low cadence. Reduce Motion leaves a still blue agent. Finished rows have no countdown text; their internal expiry remains unchanged. The smaller muted dismiss control retains its 28-point hit target, keyboard focus outline and stronger hover state.

Regression checks cover stable metadata refresh, newest intervention priority, multiple pending siblings, native input, finishes, unknown gaps, partial startup hydration, delayed answer echoes, mixed question/approval actions and persisted exact-key approval accounting. The offscreen production AppModel check verifies that reversed discovery metadata leaves the list unchanged and native human input promotes its row.
