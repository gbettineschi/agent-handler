# Interface review

The panel uses system typography, SF Symbols, explicit permission actions and a compact collapsed state. Sessions show the latest known status even when no question or approval is pending. “All sessions” returns from an input card to the list. Connection details live in Settings rather than a tracking-count footer.

## Synthetic render matrix

Run `bash scripts/render-ui.sh` on macOS. The helper creates unshown windows, uses an in-memory demo controller and never connects to an agent. It checks fixture states and exact logical dimensions; images are inspected manually. It does not compare pixels to a golden baseline.

| State | Preview |
| --- | --- |
| Question | [Image](images/ui/question.png) |
| Approval with exact wrapping rule label | [Image](images/ui/approval.png) |
| Long question and narrow layout | [Standard](images/ui/long-content.png), [narrow](images/ui/long-narrow.png) |
| Unavailable source | [Image](images/ui/unavailable.png) |
| Uncertain delivery, no resend | [Image](images/ui/uncertain.png) |
| Sessions without requests | [Image](images/ui/sessions.png) |
| Settings | [Image](images/ui/settings.png) |
| High-contrast window appearance | [Image](images/ui/appearance-high-contrast.png) |
| Collapsed | [Image](images/ui/collapsed.png) |

All examples are synthetic and marked DEMO. Their answers contact no agent. The live app launches without `--demo`. High-contrast NSAppearance is a window-level fixture; it does not verify the system Increase Contrast setting.

## Verified and pending

The 120-test local suite includes session recency, stale activity, provider identity and pending-input priority. Native demo tests checked question selection, Command-Return and no-request sessions. The render matrix checks bounded sizing, wrapping and disabled unavailable/uncertain actions. Independent source review found no remaining Important issues.

VoiceOver, full keyboard traversal, real outside-click dismissal and multiple displays remain manual checks. The user was actively using the Mac, so further visible automation was stopped. No native approval result is inferred from these demos. Backend acceptance gaps remain recorded in [verification](verification.md).
