# Third-party notices

Parts of `Sources/CodexDesktopAdapter` and its synthetic socket test server are adapted from [Agent HUD Open](https://github.com/jazzenchen/agent-hud-open) by Jazzen Chen and contributors, commit `bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9`, under the Apache License 2.0. The full license is in `LICENSES/AgentHUD-Apache-2.0.txt`.

Origin files: `JSONValue.swift`, `RecordCoding.swift`, `CodexDesktopIPC.swift`, `CodexDesktopPatches.swift`, `CodexDesktopQuestions.swift`, `CodexDesktopStream.swift` and `CodexDesktopTestServer.swift`.

Changes include module/type names, a different request controller and delivery ledger, stricter shape and capacity validation, question-focused item/turn state projection and discarded-branch patch handling, completed-turn question tracking and native inherited-settings reply submission, socket peer checking, connection and recovery limits, and product-specific question response handling. No upstream quota, account or agent-launching modules are included.

The remaining original Agent Handler code is private project code. This notice does not grant a license to that original code. Third-party portions retain their own license.
