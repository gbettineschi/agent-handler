# Prepare the live approval test

The latest Agent Handler build is already bundled and restarted. The remaining prerequisite is the source conversation's execution policy.

## Confirmed current state

- This conversation has no local project membership.
- Its active turn uses `approvals_reviewer = "user"`.
- Its effective granular policy permits MCP elicitation and permission requests, but automatically rejects sandbox/rule approval requests.
- The installed host uses that granular preset for projectless work. The visible “Ask for approval” label does not by itself establish shell-prompt eligibility.
- The app connector currently lists no projects. Its move tool explicitly requires the user to grant additional source-folder access through the sidebar. Computer use cannot operate `com.openai.codex`.

No agent permission setting has been changed by Agent Handler.

## User handoff

1. In ChatGPT, use **Add new project** beside Chats. The documented shortcut is **Command–O**. Choose a local folder, not a cloud task.
2. In the folder picker, press **Command–Shift–G**, paste the path below, press Return, and choose **Open**:

   ```text
   /Users/gb/Documents/Codex/2026-10-19/we-are-testing-vibe-island-question/agent-handler
   ```

3. Move this existing conversation into the new `agent-handler` project using the sidebar's drag/drop or conversation menu. Confirm only that named folder if the app asks for source access.
4. Keep **Ask for approval** selected in this conversation and send **Ready** here. A new turn is needed to inspect the resulting effective policy; do not select Full access or Approve for me.

The exact sidebar menu wording can vary by host version. If the picker or move action differs, report its visible options rather than changing configuration files.

## What the agent verifies next

Read the new active turn's effective reviewer and approval policy. Project membership is not itself a passing result. Only after native settings permit a human shell prompt should a harmless marker command be requested. Verify the card in Agent Handler, respond through its UI, verify the source command result and card withdrawal, and record receipt limits separately.

Sources: [OpenAI permission modes](https://learn.chatgpt.com/docs/permission-modes), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [project/sidebar troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting). The projectless preset mapping was established from the installed host build, not promised by these public pages.
