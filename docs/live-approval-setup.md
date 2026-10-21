# Live approval checks

Updated 21 October 2026. Native shell Allow/Cancel, app Allow/Deny and browser-origin Allow/Deny have passed through Agent Handler, including automatic opening for blocking approvals. A call that produces no native prompt cannot verify an approval round trip. See the dated evidence in [verification.md](verification.md).

## Connection failure is fixed and live question recovery passed

The missed Chess/Dictionary cards coincided with a broader connection failure: this conversation's 33 MB snapshot exhausted the raw JSON node budget before unused metadata was discarded. The decoder now applies the existing projection while parsing. Retained-node, frame, depth and retained-state limits remain; temporary capture code has been removed.

The full **112-test / 19-suite** run passed and independent review found no blocking issue. The exact live conversation reconnected. A real question survived app restart, was answered through Agent Handler, arrived in the source conversation and closed durably. See [verification.md](verification.md) for the evidence and remaining limits.

## Effective policy: project setup is already complete

Both this conversation and the existing “Test interactive question tool” chat now use the local agent-handler project and directory. Do not ask the user to move them again.

The main implementation chat remains `never` / `dangerFullAccess`. The user explicitly authorized isolated tests in the existing test chat and reselected **Ask for approval** after its project move. The three actual acceptance-test turns reported reviewer `user`, sandbox `workspaceWrite` and `on-request`. Their shell Allow/Cancel and browser Deny completed end to end.

Earlier test turns used granular approval with `mcp_elicitations` / `request_permissions` true but `sandbox_approval` / `rules` false. No shell escalation was attempted under those disabled categories. The owner's separate base `currentPermissions` field retained those old values even during the later working turns. Evaluate the actual pending request's turn parameters first, as the adapter does; a base-field snapshot alone is not proof of the current turn's execution policy.

The user-reported composer label alone does not prove shell eligibility. Reviewer selection and allowed approval categories are independent settings, as described in the [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). Agent Handler does not change source permissions. App/browser approval categories can be eligible even when shell escalation is disabled.

For a future approval test, start a fresh turn using a user-reviewed permission mode that allows the intended prompt category, and verify its effective settings first. The documented manual-review configuration is:

```toml
approval_policy = "on-request"
approvals_reviewer = "user"
sandbox_mode = "workspace-write"
```

The desktop documentation lists **Ask for approval** and **Custom (config.toml)** where available. Managed requirements and existing app/origin grants may affect whether a particular call needs a new prompt. Do not manufacture one, override current permissions through private IPC, or count an unprompted call as acceptance.

During setup, the three documented settings above were temporarily prepared as top-level Custom defaults with a private backup. The user reported that Custom was absent from the menu, so the original configuration was restored byte-for-byte. The test chat joined the existing local project through the supported app tool, and the user reselected Ask for approval. Subsequent actual turns used the working policy above. A final hash comparison confirmed the original global configuration remained intact. No global Custom configuration is needed for the now-passing setup.

## Acceptance gates

1. Completed after this fix: a fresh question survived restart, was answered through Agent Handler and withdrew after native arrival.
2. Completed 21 October: genuine ColorSync Utility Allow-for-conversation and Grapher Deny, including automatic opening, source continuation/refusal, card withdrawal and durable closure.
3. Completed 21 October: separate harmless shell marker requests, automatic opening, **Allow once** with native output/exit 0, then **Cancel turn** with native interruption before execution. Both cards withdrew; no saved-rule choice or retry was used.
4. Completed 21 October: genuine IANA origin confirmation, automatic opening, Allow once, page-title read, created-tab cleanup and durable withdrawal. A separate RFC Editor origin request passed **Deny** with an exact source-tool refusal, card withdrawal and durable closure. Creating an agent-owned tab that opens without a prompt is not a browser acceptance test.
5. Preserve uncertain delivery without retry. An approval dispatch acknowledgment alone is not execution or denial proof. Keep source-host restart, true uncertain-send restart and real sleep/wake as separate remaining gates.

Sources: [OpenAI permission modes](https://learn.chatgpt.com/docs/permission-modes), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [approval security](https://learn.chatgpt.com/docs/agent-approvals-security). Local observations apply to the installed host and the specific turn tested.
