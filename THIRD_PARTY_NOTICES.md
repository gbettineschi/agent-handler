# Third-party notices

Parts of `Sources/CodexDesktopAdapter` and its synthetic socket test server are adapted from [Agent HUD Open](https://github.com/jazzenchen/agent-hud-open) by Jazzen Chen and contributors, commit `bf19ac98da11fe0f5967f5a124d42f0da4bf2cf9`, under the Apache License 2.0. The full license is in `LICENSES/AgentHUD-Apache-2.0.txt`.

Origin files: `JSONValue.swift`, `RecordCoding.swift`, `CodexDesktopIPC.swift`, `CodexDesktopPatches.swift`, `CodexDesktopQuestions.swift`, `CodexDesktopPermissions.swift`, `CodexDesktopStream.swift` and `CodexDesktopTestServer.swift`.

Changes include module/type names, a different request controller and delivery ledger, stricter shape and capacity validation, item/turn state projection and discarded-branch patch handling, completed-turn question tracking and native inherited-settings reply submission, socket peer checking, connection and recovery limits, and product-specific response handling. Approval adaptations add independent reconciliation scopes, complete permission-setting checks, exact command-rule choices, restricted browser/app confirmation schemas, whole-request fingerprints and conservative handling of native dispatch acknowledgments. No upstream quota, account or agent-launching modules are included.

This notice does not grant a license to the remaining original Agent Handler code. Third-party portions retain their own license.
