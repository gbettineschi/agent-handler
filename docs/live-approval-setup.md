# Prepare the remaining live approval tests

Updated 20 October 2026. Agent Handler is bundled and running with the reconnect recovery fix. Native questions, the earlier real Clock approval, connection disable/re-enable and a whole-app pending-question restart have passed. Shell and browser-origin approval acceptance remain unverified because no eligible human request was produced in this pass.

## Observed settings, kept separate

- The user reports **Ask for approval** in this conversation's composer.
- The saved local selection is `agentMode: granular`. Its saved thread preset uses reviewer `user`, workspace permissions, `sandbox_approval: false`, `rules: false`, `skill_approval: false`, `request_permissions: true` and `mcp_elicitations: true`.
- A read-only version-11 owner-stream snapshot of the active turn reported reviewer `user`, `approvalPolicy: never` and `sandboxPolicy.type: dangerFullAccess`. The current-permissions object reported the same values. This is a real saved-versus-active discrepancy; it is not evidence of automatic review.
- The active execution environment independently reports approval policy `never`. A shell command in this turn cannot request escalation. No escalation was attempted and no policy was overridden.
- A harmless navigation to `https://example.org` completed without a card; the temporary tab was closed. That is not a passing browser approval test.

The saved projectless granular preset also disables shell prompts. Ending this turn alone is therefore not a guaranteed fix. The exact reason the active turn has full access while the composer shows the saved preset has not been established. Agent Handler does not select or modify either policy.

## Prepared source-app handoff

Computer use is blocked from operating `com.openai.codex`, and no supported project-management connector is exposed in this turn. Only the user can complete this source-app setup:

1. After this run finishes, use **Add new project** beside Chats, or **Command–O**, and choose this local folder:

   ```text
   /Users/gb/Documents/Codex/2026-10-19/we-are-testing-vibe-island-question/agent-handler
   ```

   In a folder picker, **Command–Shift–G** accepts the full path. This selects the named project folder, without granting unrelated source access.
2. Move this existing conversation into that local project through the sidebar or its conversation menu, and keep **Ask for approval** selected.
3. Start a fresh run with **“Continue the shell/browser approval tests.”** Do this after the current run ends; an answer sent while it is active can become a steering message rather than establish a new turn.

This handoff is a prerequisite to rechecking the effective policy, not a promise that project membership fixes the host discrepancy. If a fresh owner snapshot still reports `never`, automatic review or disabled shell categories, retain the blocked native result and investigate the host; never manufacture requests or change permissions through private IPC.

## Acceptance gates

- Confirm the new active native turn has user review and permits the prompt category before requesting anything.
- Request a harmless marker print, show the exact command/directory in Agent Handler, choose **Allow once**, observe the source command result and authoritative withdrawal. Do not save a command rule as part of this test.
- For browser coverage, request a harmless public origin that needs a native confirmation. Verify the native scope advertised on the card, respond through Agent Handler, observe the tool continuation and withdrawal. A navigation that executes without a card remains a non-test.
- Treat a dispatch acknowledgment separately from execution/acceptance. Preserve truly uncertain sends without retry.

Sources: [OpenAI permission modes](https://learn.chatgpt.com/docs/permission-modes), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [approval security](https://learn.chatgpt.com/docs/agent-approvals-security). Native and saved-setting observations are specific to the installed host; the public docs do not guarantee that a composer label matches an already-running turn.
