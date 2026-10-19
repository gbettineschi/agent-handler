# Temporary Claude hook probe

This experiment tests whether the installed Claude Desktop session actually loads plugin hooks. It is not a Claude adapter and must not be advertised as question or approval support.

The probe writes only recognized hook event types, timestamps, a question-tool boolean and hashes of session/tool IDs to `/private/tmp/agent-handler-claude-hook-probe-<uid>.jsonl`. It never stores prompts, tool inputs, answers or credentials. It emits `{}` and never approves, denies, answers or changes a permission policy. Hook definitions have five-second timeouts.

Upload a ZIP containing `.claude-plugin/`, `hooks/`, and `scripts/` through Claude's own Plugins UI. Use a fresh labeled test conversation with a native Blue/Green question. Check for SessionStart and question-related callbacks; answer only the labeled test. Compare callbacks after the answer. Disable or uninstall the temporary plugin when the test is complete. No callback is not proof that all Claude modes lack hooks: record the mode, host build, installation/loading state and any error first.

On 2026-10-19, Claude Desktop 2.42304.2 recognized all four hook definitions. A fresh native Chat question was answered in the source UI, without a local probe event file appearing. Cowork execution was unavailable on the tested Free account. The probe was then disabled and its switch verified off. See [the surface audit](../../docs/surface-audit.md) for scope and remaining checks.
