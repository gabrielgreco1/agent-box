#!/usr/bin/env python3
"""Opt-in Claude Code command hook: append authenticated identity events, never hook content."""
import fcntl
import hashlib
import hmac
import json
import os
import stat
import sys

MAX_STDIN = 16_384
MAX_INBOX = 1_048_576
KINDS = {"SessionStart", "SubagentStart", "SubagentStop"}


def main():
    run_id = os.environ.get("AGENT_BOX_HOOK_RUN_ID", "")
    token = os.environ.get("AGENT_BOX_HOOK_TOKEN", "")
    path = os.environ.get("AGENT_BOX_HOOK_INBOX", "")
    if not run_id or len(token) != 64 or not path:
        return 0  # Hook is harmless when run outside its opt-in Agent Box launch.
    try:
        key = bytes.fromhex(token)
        raw = sys.stdin.buffer.read(MAX_STDIN + 1)
        if len(raw) > MAX_STDIN:
            return 0
        source = json.loads(raw)
        kind = source.get("hook_event_name")
        session = source.get("session_id")
        agent = source.get("agent_id", "") if kind != "SessionStart" else ""
        agent_type = source.get("agent_type", "") if kind != "SessionStart" else ""
        fields = (run_id, session, kind, agent, agent_type)
        if kind not in KINDS or any(not isinstance(v, str) or len(v) > 256 or "\n" in v for v in fields):
            return 0
        if not session or (kind != "SessionStart" and (not agent or not agent_type)):
            return 0
        message = ("\n".join(fields) + "\n").encode()
        record = dict(zip(("run_id", "session_id", "hook_event_name", "agent_id", "agent_type"), fields))
        record["signature"] = hmac.new(key, message, hashlib.sha256).hexdigest()
        line = (json.dumps(record, separators=(",", ":")) + "\n").encode()
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:
                return 0
            fcntl.flock(fd, fcntl.LOCK_EX)
            if os.fstat(fd).st_size + len(line) > MAX_INBOX:
                return 0
            os.write(fd, line)
            os.fsync(fd)
        finally:
            os.close(fd)
    except (OSError, ValueError, TypeError, KeyError):
        pass  # Observation must never prevent Claude from continuing.
    return 0


if __name__ == "__main__":
    sys.exit(main())
