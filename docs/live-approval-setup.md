# Remaining live approval checks

Updated 20 October 2026. Diagnose the current Desktop connection failure before another approval test. Earlier Clock approval and native question/restart results remain historical evidence; they do not establish that the latest running connection is healthy.

## Connection failure is fixed and live question recovery passed

The missed Chess/Dictionary cards coincided with a broader connection failure: this conversation's 33 MB snapshot exhausted the raw JSON node budget before unused metadata was discarded. The decoder now applies the existing projection while parsing. Retained-node, frame, depth and retained-state limits remain; temporary capture code has been removed.

The full **112-test / 19-suite** run passed and independent review found no blocking issue. The exact live conversation reconnected. A real question survived app restart, was answered through Agent Handler, arrived in the source conversation and closed durably. See [verification.md](verification.md) for the evidence and remaining limits.

## Effective policy: project setup is already complete

This conversation uses the local agent-handler project and directory. Do not ask the user to move it again.

The current resumed turn's native owner snapshot reports reviewer `user`, policy `never`, sandbox `dangerFullAccess`. The Font Book check produced zero native pending requests, so no post-fix app Allow/Deny result is established. Shell commands cannot produce human approvals in this mode.

An earlier project-backed turn used granular workspace permissions with MCP prompts enabled but shell/rule categories disabled. The user-reported composer label alone did not prove shell eligibility. These are observations from different turns, not evidence that Agent Handler selects or changes source permissions.

For the next actual approval test, start a fresh turn using a user-reviewed permission mode that allows the intended prompt category, and verify its effective settings first. The documented manual-review configuration is:

```toml
approval_policy = "on-request"
approvals_reviewer = "user"
sandbox_mode = "workspace-write"
```

The desktop documentation lists **Ask for approval** and **Custom (config.toml)** where available. Managed requirements and existing app/origin grants may affect whether a particular call needs a new prompt. Do not manufacture one, override current permissions through private IPC, or count an unprompted call as acceptance.

## Acceptance gates

1. Completed after this fix: a fresh question survived restart, was answered through Agent Handler and withdrew after native arrival.
2. Produce a fresh eligible app approval. Capture the exact native request while pending; verify the Agent Handler card and exact Allow/Deny scope, source continuation/refusal and authoritative withdrawal.
3. With an effective policy that permits shell prompts, request a harmless marker print. Review the exact command/directory, choose **Allow once**, then verify the command result and withdrawal. Do not save a command rule for this test.
4. Produce a genuine browser-origin confirmation for a harmless public page. Verify its native scope, the Agent Handler response, source continuation and withdrawal. Creating an agent-owned tab that opens without a prompt is not a browser acceptance test.
5. Preserve uncertain delivery without retry. An approval dispatch acknowledgment alone is not execution or denial proof. Keep source-host restart, true uncertain-send restart and real sleep/wake as separate remaining gates.

Sources: [OpenAI permission modes](https://learn.chatgpt.com/docs/permission-modes), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [approval security](https://learn.chatgpt.com/docs/agent-approvals-security). Local observations apply to the installed host and the specific turn tested.
