"""Observe callback availability only. Never emit a permission or answer directive."""
import hashlib
import json
import os
import stat
import sys
import time


def main():
    # The payload may contain private tool inputs. Do not persist or print them.
    raw = sys.stdin.buffer.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        return
    payload = json.loads(raw)
    event = payload.get("hook_event_name")
    if event not in {"SessionStart", "PreToolUse", "PermissionRequest", "PostToolUse"}:
        return
    record = {"event": event, "time": time.time(), "question_tool": payload.get("tool_name") == "AskUserQuestion"}
    for key in ("session_id", "tool_use_id"):
        value = payload.get(key)
        if isinstance(value, str):
            record[key + "_hash"] = hashlib.sha256(value.encode()).hexdigest()
    path = "/private/tmp/agent-handler-claude-hook-probe-" + str(os.getuid()) + ".jsonl"
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            return
        os.write(fd, (json.dumps(record, sort_keys=True) + "\n").encode())
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # A diagnostic failure must not alter the source agent's behavior.
    print("{}")
