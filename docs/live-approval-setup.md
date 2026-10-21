# Remaining live approval checks

Updated 21 October 2026. The live connection and native question delivery have been rechecked. Earlier approval round trips remain dated evidence; a call that produces no native prompt cannot verify a new approval round trip.

## Connection failure is fixed and live question recovery passed

The missed Chess/Dictionary cards coincided with a broader connection failure: this conversation's 33 MB snapshot exhausted the raw JSON node budget before unused metadata was discarded. The decoder now applies the existing projection while parsing. Retained-node, frame, depth and retained-state limits remain; temporary capture code has been removed.

The full **112-test / 19-suite** run passed and independent review found no blocking issue. The exact live conversation reconnected. A real question survived app restart, was answered through Agent Handler, arrived in the source conversation and closed durably. See [verification.md](verification.md) for the evidence and remaining limits.

## Effective policy: project setup is already complete

This conversation uses the local agent-handler project and directory. Do not ask the user to move it again.

The main implementation turn uses `never` / `dangerFullAccess`, so it cannot generate a shell gate. The user explicitly authorized isolated tests in the existing test chat and switched that chat to human-reviewed **Ask for approval**. A new native turn then reported reviewer `user`, sandbox `workspaceWrite`, and a granular policy with `mcp_elicitations` / `request_permissions` true but `sandbox_approval` / `rules` false. Thus the reviewer change succeeded; the shell escalation category remains disabled. No shell escalation was attempted under that policy and no marker command ran.

The user-reported composer label alone does not prove shell eligibility. Reviewer selection and allowed approval categories are independent settings, as described in the [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). Agent Handler does not change source permissions. App/browser approval categories can be eligible even when shell escalation is disabled.

For the next actual approval test, start a fresh turn using a user-reviewed permission mode that allows the intended prompt category, and verify its effective settings first. The documented manual-review configuration is:

```toml
approval_policy = "on-request"
approvals_reviewer = "user"
sandbox_mode = "workspace-write"
```

The desktop documentation lists **Ask for approval** and **Custom (config.toml)** where available. Managed requirements and existing app/origin grants may affect whether a particular call needs a new prompt. Do not manufacture one, override current permissions through private IPC, or count an unprompted call as acceptance.

On 21 October, a read-only owner-state check reconfirmed this chat's `never` / `dangerFullAccess` and the test chat's human-reviewed granular policy with both shell flags false. Under the user's request to fix the permission for testing, the three documented settings above were temporarily prepared as top-level Custom defaults with a private backup. The user reported that Custom was absent from the menu, so the original configuration was restored byte-for-byte. The test chat was moved into the existing local agent-handler project through the supported app tool; a fresh preflight still reported both shell categories false. Reselecting Ask for approval after that move is the next user action. No shell escalation has been attempted under the disabled categories, and no new shell approval pass is claimed.

## Acceptance gates

1. Completed after this fix: a fresh question survived restart, was answered through Agent Handler and withdrew after native arrival.
2. Completed 21 October: genuine ColorSync Utility Allow-for-conversation and Grapher Deny, including automatic opening, source continuation/refusal, card withdrawal and durable closure.
3. With an effective policy that permits shell prompts, request harmless marker prints in separate turns. Review the exact command/directory and verify **Allow once**, then **Cancel turn** with no execution. Do not save a command rule for this test. The earlier shell Allow passed on 20 October; fresh shell auto-opening and Cancel remain pending.
4. Completed 21 October: genuine IANA origin confirmation, automatic opening, Allow once, page-title read, created-tab cleanup and durable withdrawal. Browser Deny remains separately pending. Creating an agent-owned tab that opens without a prompt is not a browser acceptance test.
5. Preserve uncertain delivery without retry. An approval dispatch acknowledgment alone is not execution or denial proof. Keep source-host restart, true uncertain-send restart and real sleep/wake as separate remaining gates.

Sources: [OpenAI permission modes](https://learn.chatgpt.com/docs/permission-modes), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [approval security](https://learn.chatgpt.com/docs/agent-approvals-security). Local observations apply to the installed host and the specific turn tested.
