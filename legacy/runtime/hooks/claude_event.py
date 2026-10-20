#!/usr/bin/env python3
"""Opt-in Claude Code command hook: append authenticated identity events, never hook content."""
import fcntl
import hashlib
import hmac
import json
import os
import stat
import sys
import time

MAX_STDIN = 65_536
MAX_INBOX = 1_048_576
KINDS = {"SessionStart", "SubagentStart", "SubagentStop"}
MCP_PREFIX = "mcp__racky__computer_"
MAX_CHILD_CONTEXT = 65_536
CHILD_CHUNK_BYTES = 8_000


def child_context_part(source, run_id, token):
    """Emit one numbered slice of the frozen reviewed skill to a native child."""
    if (source.get("hook_event_name") != "SubagentStart" or not run_id or len(token) != 64
            or any(c not in "0123456789abcdef" for c in token)):
        return 0
    try:
        if len(sys.argv) != 7 or sys.argv[1] != "--child-context" or sys.argv[3] != "--sha256" or sys.argv[5] != "--part":
            return 0
        path, expected, index = sys.argv[2], sys.argv[4], int(sys.argv[6])
        if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected) or index < 0:
            return 0
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_mode & 0o077 or not 0 < info.st_size <= MAX_CHILD_CONTEXT):
                return 0
            data = os.read(fd, MAX_CHILD_CONTEXT + 1)
        finally:
            os.close(fd)
        if hashlib.sha256(data).hexdigest() != expected or len(data) > MAX_CHILD_CONTEXT:
            return 0
        content = data.decode("utf-8")
        parts, part, size = [], [], 0
        for character in content:
            width = len(character.encode("utf-8"))
            if size + width > CHILD_CHUNK_BYTES:
                parts.append("".join(part)); part, size = [], 0
            part.append(character); size += width
        if part:
            parts.append("".join(part))
        if index >= len(parts) or len(parts) > 9:
            return 0
        label = f"Reviewed webscraping-expert skill, part {index + 1:02d}/{len(parts):02d}. "
        label += "Combine all numbered parts in order before applying the skill.\n"
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SubagentStart",
              "additionalContext": label + parts[index]}}, separators=(",", ":"), ensure_ascii=False))
    except (OSError, ValueError, TypeError, UnicodeError):
        pass  # A bad snapshot must never expose partial or unverified skill content.
    return 0


def deny_route():
    # The MCP backend also rejects calls without provenance. Keep hook failures
    # from silently letting a child act as the parent.
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
          "permissionDecision": "deny", "permissionDecisionReason": "Computer route unavailable."}}))
    return 0


def route_tool(source, run_id, token):
    try:
        key = bytes.fromhex(token)
        if len(key) != 32 or not run_id:
            return deny_route()
        name = source.get("tool_name")
        session = source.get("session_id")
        agent = source.get("agent_id") or ""
        tool_use = source.get("tool_use_id")
        arguments = source.get("tool_input")
        if (not isinstance(name, str) or not name.startswith(MCP_PREFIX)
                or not isinstance(session, str) or not 0 < len(session.encode()) <= 256
                or not isinstance(agent, str) or len(agent.encode()) > 256
                or not isinstance(tool_use, str) or not 0 < len(tool_use.encode()) <= 256
                or not isinstance(arguments, dict)):
            return deny_route()
        arguments = dict(arguments)
        arguments.pop("route_token", None)  # Never accept a model-supplied route.
        encoded_arguments = json.dumps(arguments, separators=(",", ":"), sort_keys=True,
                                       ensure_ascii=False).encode("utf-8")
        if len(encoded_arguments) > 24_576:
            return deny_route()
        envelope = {"v": 1, "run_id": run_id, "session_id": session, "agent_id": agent,
                    "tool_use_id": tool_use, "tool_name": name, "issued_at": int(time.time()),
                    "nonce": os.urandom(16).hex(), "arguments": arguments}
        payload = json.dumps(envelope, separators=(",", ":"), sort_keys=True,
                             ensure_ascii=False).encode("utf-8")
        if len(payload) > 32_768:
            return deny_route()
        import base64
        signature = hmac.new(key, payload, hashlib.sha256).hexdigest()
        arguments["route_token"] = base64.b64encode(payload).decode("ascii") + "." + signature
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
              "updatedInput": arguments}}, separators=(",", ":"), ensure_ascii=False))
        return 0
    except (OSError, ValueError, TypeError, UnicodeError):
        return deny_route()


def main():
    run_id = os.environ.get("RACKY_HOOK_RUN_ID", "")
    token = os.environ.get("RACKY_HOOK_TOKEN", "")
    path = os.environ.get("RACKY_HOOK_INBOX", "")
    kind = None
    try:
        raw = sys.stdin.buffer.read(MAX_STDIN + 1)
        if len(raw) > MAX_STDIN:
            print("Computer route unavailable.", file=sys.stderr)
            return 2
        source = json.loads(raw)
        if not isinstance(source, dict):
            return 0
        kind = source.get("hook_event_name")
        if len(sys.argv) > 1:
            return child_context_part(source, run_id, token)
        if kind == "PreToolUse" and str(source.get("tool_name", "")).startswith(MCP_PREFIX):
            return route_tool(source, run_id, token)
        if not run_id or len(token) != 64 or not path:
            return 0  # Observation is harmless outside an opt-in Racky launch.
        key = bytes.fromhex(token)
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
        if kind is None or kind == "PreToolUse":
            print("Computer route unavailable.", file=sys.stderr)
            return 2
        pass  # Observation must never prevent Claude from continuing.
    return 0


if __name__ == "__main__":
    sys.exit(main())
