# Menu-bar interface review

The floating notch pill has been removed. A native NSStatusItem opens a bounded panel under its actual button. A hidden/offscreen Ice anchor is clamped to the display; reopening the app bundle provides a way to reach the panel before revealing the item. No hover expansion or incoming-request auto-open is used. The selected menu-bar item stays highlighted while its panel is open.

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

The number counts active sessions plus observed finishes younger than 300 seconds, once per session. Finished rows show the remaining countdown and remain in the list after the number expires. Their × hides only that finished turn; subscriptions continue, and new/resumed activity or unresolved input becomes visible again. Dismissals and finish times survive app restart. Launch-history completions do not receive a fresh countdown; the initial baseline includes explicit and pinned subscriptions as well as discovered chats. A newly discovered finished chat after that baseline can enter the count.

Reduce Motion stops both glyph motion and the short opening fade. The window has one animation owner and never combines a window resize animation with a SwiftUI spring. Exact approval choices remain multiline buttons without a default keyboard action.

## References inspected

The [Open Vibe Island panel](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Views/IslandPanelView.swift) and [window controller](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/OverlayPanelController.swift) demonstrate state-driven surfaces and explain why mixing AppKit and SwiftUI size animations caused jank. Notchi's SessionSpriteView at local checkout `e6f8b8a805cec31b5d3844d2ea8faa7a836ebc7e` shows pausing motion under Reduce Motion. No sprites, artwork or UI code from these references were copied. The menu-bar glyph is original template artwork. Apple's [menu-bar guidance](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [motion](https://developer.apple.com/design/human-interface-guidelines/motion) and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) inform the restrained behavior, system tint, explicit actions and labeled states.

## Repeatable visual checks

Run `bash scripts/render-ui.sh`. It creates unshown windows, uses a real controller with an in-memory synthetic transport, and never contacts an agent. Nine panel cases assert logical dimensions; images are inspected manually. Seven icon states and all four working frames are also rendered; see the [glyph sheet](images/ui/status-glyphs.png). This is not pixel-diff regression testing.

| State | Preview |
| --- | --- |
| Question | [Image](images/ui/question.png) |
| Exact wrapping approval rule | [Image](images/ui/approval.png) |
| Long question | [Standard](images/ui/long-content.png), [narrow](images/ui/long-narrow.png) |
| Unavailable | [Image](images/ui/unavailable.png) |
| Uncertain delivery, no resend | [Image](images/ui/uncertain.png) |
| Sessions without requests, dismiss controls | [Image](images/ui/sessions.png) |
| Settings | [Image](images/ui/settings.png) |
| High-contrast window appearance | [Image](images/ui/appearance-high-contrast.png) |

All examples are synthetic and marked DEMO. The live app launches without `--demo`. High-contrast NSAppearance does not establish system Increase Contrast acceptance.

## Live checks

The live release showed actual native chat titles after fixing the metadata-title mismatch. A labeled native question was opened from its session row; keyboard text entry and Command-Return delivered the answer to the source conversation, and the test card cleared while the unrelated question remained. An intermediate uncertain state was visible; no automatic resend occurred. This confirms arrival and withdrawal, not a separately captured exact native receipt.

Command-comma opens Settings. With macOS Keyboard Navigation temporarily enabled, Tab and Shift-Tab traversed controls and showed the focus outline; the original off preference was restored. Native accessibility inspection found named headings, buttons, answer fields, session titles and state labels. System Increase Contrast was enabled temporarily; the live list remained readable and contrast/transparency were both restored. VoiceOver was briefly enabled, but the computer tool could not expose its caption or cursor output; it was restored to off without claiming spoken-output acceptance. Temporary native lifecycle tracing verified Escape and × both make the window invisible. The computer inspection tool then sends an app-reopen event, which explained why observation appeared to undo the close; the tracing was removed and committed sources restored. Physical menu-bar/Ice reveal and a live finished-row dismissal remain to be recorded separately. Provider approval and Claude acceptance gaps remain in [verification](verification.md).
