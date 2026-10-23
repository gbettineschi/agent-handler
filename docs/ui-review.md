# Menu-bar and notch interface review

In Menu bar mode, a native NSStatusItem opens a bounded panel centered horizontally under its visible button, with edge clamping. Invalid/hidden/offscreen Ice anchors are rejected: a fresh opening uses the top-right of the active display; an already-open panel keeps its position while resizing downward. The button's geometry selects its actual display; the full display validates the button, while the visible work area bounds the panel. A moved/removed display cannot leave the panel anchored in the middle of the screen. This follows the view-relative attachment model of Apple's [popover API](https://developer.apple.com/documentation/appkit/nspopover/show%28relativeto%3Aof%3Apreferrededge%3A%29). Menu bar mode has no hover expansion. Independent settings control automatic opening for blocking input, finished sessions, and non-blocking questions; only blocking input defaults to on. Automatic opening does not take keyboard focus or replace an already-open route. The selected menu-bar item stays highlighted while its panel is open.

## Optional notch presentation

Settings → Appearance selects Menu bar or Notch. The same window, hosting tree, controller and draft storage are retained across the switch. Only one presentation is visible; notch mode hides the menu-bar item. The requested choice survives restart and display fallback. Displays without a verified cutout use the existing menu-bar presentation until the notched screen returns.

The camera gap comes from [NSScreen safe-area rectangles](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc), not a Mac-model width guess. One black surface touches the physical top edge, with attached shoulders and rounded lower corners. Its compact wings reserve the camera's actual width, show the colored moving agent on the left and the running-only count on the right. Attention is orange, failure red, recent completion green and idle/paused gray. Expansion uses a wider 520-point content layout and remains bounded by the work area. The header omits the duplicate agent glyph and uses a fold chevron. The existing quota, session and approval information remains available below the camera.

A 100 ms dwell opens a passive preview without keyboard focus; leaving for 320 ms folds it. Clicking pins it, and Settings/keyboard interaction retain it. Escape applies to the focused panel; a passive preview is dismissed by moving away. No global key monitor or new permission is introduced. Explicit folding only suppresses reopening while the pointer remains over the compact trigger. The shrinking body cannot begin another dwell. Automatic interventions use the existing authoritative close policy; uncertain, sending and unavailable inputs never resolve merely because the pointer leaves. A new automatic target does not navigate away from an already-open route.

One AppKit animation owns geometry (220 ms for notch expansion/collapse), with no simultaneous SwiftUI size spring. The physical top/center stay fixed as content changes. Compact icon/count content fades out in 100 ms on expansion and returns in 160 ms on collapse, leaving the camera band black. Its layout and click surface remain in place; the hidden icon timeline pauses. Reduce Motion disables geometry, icon and compact-content animation. Open Vibe Island's pinned [window controller](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/OverlayPanelController.swift) was inspected for hover, first-click and animation pitfalls. No UI code or artwork was copied.

The notch reveals a content canvas already laid out at its final width and height. Native window bounds clip that canvas during expansion; scroll views do not repeatedly squeeze and reflow through the intermediate window sizes. Opening waits for a natural-height layout pass before choosing its single target frame. Each preparation requests a fresh pass even if the height is unchanged, including a coalesced close/reopen or display fallback/recovery. Short lists therefore stay fitted throughout the reveal, while long content retains real scrolling. The hosting tree and draft owner remain intact.

The outer geometry reader binds the black surface and rounded outline to the actual animated window viewport. The fixed canvas can extend beyond it internally; its minimum width must never enlarge the clipping shape, which would cut off the compact surface's rounded corners. This reader exists in both presentations so switching modes keeps the same view identity.

The native fixture reproduced two timing defects before their fixes: hover-exit incorrectly suppressed the next entry, and the shrinking body could reopen itself before collapse finished. Both now pass through the production panel and pointer-event path, using synthetic geometry/pointer positions without moving the user's cursor. A fresh-context review found the strip's initial toggle-vs-pin error and overbroad Escape wording; both were corrected. The review found no remaining Critical/Important issue. Physical pointer entry while another app is active and a real display removal are separate from this synthetic check.

Native testing on the actual notched Mac verified the compact surface, live titles/counts, mode switching, Command-comma, focused Escape, first-click opening and click-to-pin. A real free-text draft survived Menu bar → Notch → Menu bar → Notch and collapse/reopen. A single submission through the notch reached the explicitly authorized test chat and its card disappeared; source tracking continued. Delivery briefly displayed uncertain before authoritative withdrawal, so no claim is made about the exact idle-turn receipt. The selected live preference was left at Notch.

Synthetic previews: [compact](images/ui/notch-collapsed.png), [sessions](images/ui/notch-sessions.png), [question](images/ui/notch-question.png). These are fixture data, not personal screenshots. The complete matrix now has 35 layouts.

## States and count

| State | Menu-bar treatment |
| --- | --- |
| Working | Original monochrome agent glyph, subtle four-frame motion at 4 fps |
| Question or approval | Exclamation badge; working sessions can still animate |
| Ordinary unavailable session | Hidden immediately; observation continues |
| Unavailable intervention | Retained request or Check Codex/Claude, attention badge |
| Connection/catalog warning | Question-mark badge; details in Settings |
| Failed | Cross badge and labeled failure in the list |
| Recently finished | Check badge when no higher-priority state exists |
| Paused | Pause badge |
| Idle | Still agent glyph and zero |

The number counts active sessions plus observed finishes younger than 300 seconds, once per session. Finished rows disappear after 300 seconds without displaying a countdown; deadlines survive restart. Their × hides only that finished turn; subscriptions continue, and new/resumed activity or unresolved input becomes visible again. Dismissals and finish times survive app restart. Launch-history completions receive only a display expiry grace period, without being counted or announced as new finishes; the initial baseline includes explicit and pinned subscriptions as well as discovered chats. A newly discovered finished chat after that baseline can enter the count.

Reduce Motion stops both glyph motion and the short opening fade. The window has one animation owner and never combines a window resize animation with a SwiftUI spring. Approval choices have no default keyboard action; persistent choices expose their exact scope in a separate local review before confirmation.

## References inspected

The [Open Vibe Island panel](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Views/IslandPanelView.swift) and [window controller](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/OverlayPanelController.swift) demonstrate state-driven surfaces and explain why mixing AppKit and SwiftUI size animations caused jank. Notchi's SessionSpriteView at local checkout `e6f8b8a805cec31b5d3844d2ea8faa7a836ebc7e` shows pausing motion under Reduce Motion. No sprites, artwork or UI code from these references were copied. The menu-bar glyph is original template artwork. Apple's [menu-bar guidance](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [motion](https://developer.apple.com/design/human-interface-guidelines/motion) and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) inform the restrained behavior, system tint, explicit actions and labeled states.

## Repeatable visual checks

Run `bash scripts/render-ui.sh`. Its render matrix creates unshown windows, uses a real controller with an in-memory synthetic transport, and never contacts an agent. Twenty-seven full-panel cases and two production request-view review cases check logical dimensions; images are inspected manually. A separate native lifetime fixture briefly opens its own production panel and asserts actual visibility after controller updates, plus manual/Settings ownership. It does not interact with the installed app or any personal request. Seven icon states and all four working frames are also rendered; see the [glyph sheet](images/ui/status-glyphs.png). This is not pixel-diff regression testing.

| State | Preview |
| --- | --- |
| Question | [Image](images/ui/question.png) |
| Command approval | [Standard](images/ui/approval.png), [narrow](images/ui/approval-narrow.png), [long](images/ui/approval-long.png) |
| Website approval | [Image](images/ui/approval-browser.png) |
| Saved command-rule review, fixed controls | [Standard](images/ui/approval-rule-review.png), [long and narrow](images/ui/approval-rule-review-long.png) |
| Long question | [Standard](images/ui/long-content.png), [narrow](images/ui/long-narrow.png) |
| Unavailable | [Image](images/ui/unavailable.png) |
| Uncertain delivery, no resend | [Image](images/ui/uncertain.png) |
| Sessions without requests, dismiss controls | [Image](images/ui/sessions.png) |
| Ordinary unavailable sessions hidden | [Synthetic image](images/ui/sessions-disconnected.png) |
| Read-only permission wait retained through disconnect | [Synthetic image](images/ui/permission-wait-disconnected.png) |
| Narrow and long titles | [Narrow](images/ui/sessions-narrow.png), [long titles](images/ui/sessions-long-titles.png) |
| Recent finish and Undo | [Recent finish](images/ui/sessions-recent.png), [Undo](images/ui/sessions-undo.png) |
| Seventeen sessions and empty | [Many](images/ui/sessions-many.png), [empty](images/ui/empty.png) |
| Settings | [Image](images/ui/settings.png) |
| High-contrast window appearance | [Image](images/ui/appearance-high-contrast.png) |

All examples are synthetic. Full-panel examples are marked DEMO; rule-review images show the production request body without the app header/footer. The live app launches without `--demo`. High-contrast NSAppearance does not establish system Increase Contrast acceptance.

## Live checks

The live release showed actual native chat titles after fixing the metadata-title mismatch. A labeled native question was opened from its session row; keyboard text entry and Command-Return delivered the answer to the source conversation, and the test card cleared while the unrelated question remained. An intermediate uncertain state was visible; no automatic resend occurred. This confirms arrival and withdrawal, not a separately captured exact native receipt.

Command-comma opens Settings. With macOS Keyboard Navigation temporarily enabled, Tab and Shift-Tab traversed controls and showed the focus outline; the original off preference was restored. Native inspection found named headings, buttons, answer fields, session titles and state labels. System Increase Contrast was enabled temporarily; the live list remained readable and contrast/transparency were both restored. VoiceOver was briefly enabled, but the computer tool could not expose its caption or cursor output; it was restored to off without claiming spoken-output acceptance. Temporary native lifecycle tracing verified Escape and × both make the window invisible. The computer inspection tool then sends an app-reopen event, which explained why observation appeared to undo the close; the tracing was removed and committed sources restored. The user confirmed the robot is visible in Ice and clicking opens the panel. Physical finished-row dismissal/reappearance is not inferred from the synthetic tests. Provider approval and Claude acceptance gaps remain in [verification](verification.md).

## Detail polish

Tracking now starts automatically whenever the live app runs. The former Connect to Desktop switch and its persisted pause gate have been removed. The header keeps separate controls: chevron to hide, Settings/Back, and × to quit the application. Escape and outside clicks still hide without quitting or discarding the in-memory answer draft.

Notch hover also observes native mouse movement in both local and global event scopes, as described in [Apple's event-monitor documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html). The panel explicitly accepts mouse-moved events. Movement only updates dwell on a change of inside/outside state; it adds no idle polling. The cache is invalidated when collapse changes the hit region. A missing view-entry event therefore has a geometric recovery path, while compact-frame suppression and passive focus behavior remain intact.

Chat titles take the full row width, with a compact source/status line underneath. Actionable rows have restrained hover/press feedback; focus has a single outline. Event-based ordering remains stable between interventions and finishes. Settings text is shorter, empty state avoids implying that an unknown job succeeded, the Open command always opens, and an already visible panel does not repeat its fade.

Hide has a ten-second Undo available only on the sessions route, so Command-Z cannot capture answer-field editing. The restore menu recovers individual hidden finished rows after that offer expires. Both use exact source/turn identity and preserve the original finish deadline. A real hidden Job tracker row was restored through this menu while the other pre-existing hidden session was left hidden. Native list-row inspection alone does not establish that the × hit target was exercised successfully; the later content-height pass below exercised × and Undo.

The matrix includes narrow sessions, long titles, finished-session expiry, Undo, sixteen sessions and a fully empty panel. Demo reset clears its own dismissal state between examples. Current test counts are in [verification](verification.md). VoiceOver is out of scope at the user's request.


## Content-driven height

Fixed 260/400/480-point presets are replaced by measured natural content height. Scroll content is measured inside its viewport, separately from header/navigation/actions, banners and Undo. Route removal removes its measurements. The top edge remains anchored while a short AppKit transition changes height; Reduce Motion disables it. The 640-point/display cap keeps long content scrollable. Approval actions retain their own measured area up to 260 points; saved-rule review details scroll separately from the fixed Back/confirmation footer. Session rows use a measured scroll stack, also exposing each finished-row × as an individual native button.

All fifteen render fixtures now use measured sizing and check that measurement stays stable after resizing. A same-hosting-tree sequence covers three sessions → one → multiline banner → clear → settings → list → empty → restored, including a forced 100-point viewport. Live testing exercised Job tracker ×, Undo, and opening/closing Connection details. The row disappeared and returned, and the window resized in both directions. No source request or answer was sent.


## Provider and activity clarity

Rows show Codex or Claude instead of Work. Running rows use the animated blue agent glyph, held still under Reduce Motion. The header uses the original agent glyph; the ambiguous history glyph is replaced with a labeled Hidden menu. Source tooltips describe the Desktop connection and Claude's read-only coverage.

Codex activity hints come only from the latest item in the newest validated running turn. A native reasoning marker may show Thinking; tools/messages need explicit inProgress status for their specific labels. Completed/unknown items fall back to Running rather than reviving older activity. Thinking is a latest-activity hint, not a claim of continuously measured model computation. No reasoning content or message body is read for these hints, and the bounded JSON projection is unchanged. The app reads the in-memory activity state once per second. Hints clear on disconnected/replaced owners, invalid snapshots, input, or completion.

The [thinking fixture](images/ui/sessions-thinking.png) uses the real ActivityStore path. Native live inspection showed Codex labels and successive Running/Thinking changes in two real conversations, plus the labeled Hidden menu. Individual command/edit/search/tool hint shapes are fixture-verified; no native command was launched solely to manufacture a UI state.


## Automatic opening and finished-session expiry

Finished rows have a durable five-minute display deadline, including historical rows first seen at launch. The menu-bar count still distinguishes newly observed finishes from launch history. Expired or dismissed records do not stop source observation; resumed activity, a new turn or unresolved input returns to the list. Undo and Hidden preserve the deadline. An expired manually hidden turn cannot be restored.

The Open automatically settings group has independent blocking input (default on), finish (off), and non-blocking question (off) switches. Current Codex native questions are asynchronous and use the non-blocking switch. Supported pending approvals and Claude's explicit read-only permission-wait signal use blocking. Unknown state never substitutes for a confirmed blocking request. Pending request keys are consumed once, including while options are off; reconnects and re-enabling a preference do not replay them. Terminal notifications come from transitions observed this run; initial terminal snapshots do not open the panel. Completed, failed and cancelled turns all qualify as endings.

Automatic presentation preserves keyboard focus in the other app, and leaves the selected question/settings alone if the panel is already open. Manual opening still makes the panel key for keyboard use. No answer or approval is ever submitted by this policy.

Automatic presentation also owns closing: resolved requests close its panel once no unresolved input remains. Uncertain, sending and unavailable requests keep it open. Claude audit waits require a positive recovery, not missing data. Finish-triggered openings retain the exact newly finished turns; only those notices and later automatic finish events extend the lifetime. Dismissal, expiry or resumed work clears each finish reason. Manual opening or Settings cancels automatic closing. Open menus defer closure while the policy continues observing new waits.

Source-only Codex requests use the same blocking notification lifetime as read-only Claude waits. Their titled session remains visible with Review in Codex and an explicit source-app notice, even beside a retained unavailable card. The vague global approval banner is removed. Ordinary sessions without current activity are hidden, with monitoring and metadata retained. Unresolved typed requests stay visible. Positively observed source-only waits survive unknown data and missing turn IDs, showing Check Codex/Claude until positive recovery. These waits remain counted as intervention, without inventing response controls. Stale activity after a typed Codex response cannot become a persistent source wait. The native panel fixture verifies wait → unknown → positive recovery without hiding the wait early.

The [expired fixture](images/ui/finished-expired.png) verifies that only the still-running session remains after the deadline. Settings rendering includes all three switches within the adaptive height limit.


## Stable ordering and quieter session rows — 21 October 2026

Session ordering is presentation state, persisted separately from lifecycle and delivery. New intervention identities promote a waiting row above ordinary rows; the most recently observed intervention comes first. Running hints, metadata recency, polling, owner reconnects and partially hydrated request scopes cannot reshuffle it. Ordinary rows move on observed finishes, native user input identities and interventions. Native question responses use their accepted input marker; local approval decisions retain exact-key accounting until source withdrawal. Typed approval closures also cover source-app decisions. Withdrawal affects presentation recency and does not establish that a command executed.

The native loading spinner has been replaced with the original agent glyph in blue, gently bobbing and blinking at a low cadence. Reduce Motion leaves a still blue agent. Finished rows have no countdown text; their internal expiry remains unchanged. The smaller muted dismiss control retains its 28-point hit target, keyboard focus outline and stronger hover state.

Regression checks cover stable metadata refresh, newest intervention priority, multiple pending siblings, native input, finishes, unknown gaps, partial startup hydration, delayed answer echoes, mixed question/approval actions and persisted exact-key approval accounting. The offscreen production AppModel check verifies that reversed discovery metadata leaves the list unchanged and native human input promotes its row.
