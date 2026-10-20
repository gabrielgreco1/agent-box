import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("claude_event.py")
TOKEN = "ab" * 32
TOOL = "mcp__racky__computer_input"


class ClaudeHookRouteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.inbox = Path(self.directory.name) / "events.jsonl"
        self.inbox.write_bytes(b"")
        self.inbox.chmod(0o600)
        self.environment = dict(os.environ, RACKY_HOOK_RUN_ID="run-1",
                                RACKY_HOOK_TOKEN=TOKEN,
                                RACKY_HOOK_INBOX=str(self.inbox))

    def emit(self, event, environment=None, arguments=()):
        return subprocess.run([str(SCRIPT), *arguments], input=json.dumps(event).encode(),
                              capture_output=True, env=environment or self.environment,
                              timeout=3, check=False)

    def test_parent_and_child_route_overwrite_model_field_and_sign_original_arguments(self):
        for agent in ("", "child-A"):
            event = {"hook_event_name": "PreToolUse", "tool_name": TOOL,
                     "session_id": "session-A", "agent_id": agent,
                     "tool_use_id": "tool-" + (agent or "parent"),
                     "tool_input": {"kind": "text", "text": "hello 😀", "route_token": "spoofed"}}
            process = self.emit(event)
            self.assertEqual(process.returncode, 0)
            result = json.loads(process.stdout)["hookSpecificOutput"]
            self.assertNotIn("permissionDecision", result)
            self.assertEqual(result["updatedInput"]["text"], "hello 😀")
            payload_text, signature = result["updatedInput"]["route_token"].split(".")
            payload = base64.b64decode(payload_text)
            self.assertEqual(hmac.new(bytes.fromhex(TOKEN), payload, hashlib.sha256).hexdigest(), signature)
            envelope = json.loads(payload)
            self.assertEqual(envelope["agent_id"], agent)
            self.assertEqual(envelope["tool_use_id"], event["tool_use_id"])
            self.assertEqual(envelope["tool_name"], TOOL)
            self.assertEqual(envelope["arguments"], {"kind": "text", "text": "hello 😀"})
        self.assertEqual(self.inbox.read_bytes(), b"")

    def test_missing_configuration_and_oversized_arguments_deny_route(self):
        event = {"hook_event_name": "PreToolUse", "tool_name": TOOL,
                 "session_id": "s", "tool_use_id": "t", "tool_input": {}}
        environment = dict(self.environment)
        environment.pop("RACKY_HOOK_TOKEN")
        process = self.emit(event, environment)
        self.assertEqual(json.loads(process.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
        event["tool_input"] = {"text": "x" * 25_000}
        process = self.emit(event)
        self.assertEqual(json.loads(process.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_existing_identity_event_keeps_authenticated_inbox(self):
        process = self.emit({"hook_event_name": "SubagentStart", "session_id": "session-A",
                             "agent_id": "child-A", "agent_type": "Explore", "prompt": "not-persisted"})
        self.assertEqual(process.returncode, 0)
        self.assertEqual(process.stdout, b"")
        record = json.loads(self.inbox.read_text())
        self.assertEqual(record["agent_id"], "child-A")
        self.assertNotIn("prompt", record)
        message = "\n".join(("run-1", "session-A", "SubagentStart", "child-A", "Explore")) + "\n"
        self.assertEqual(record["signature"], hmac.new(bytes.fromhex(TOKEN), message.encode(), hashlib.sha256).hexdigest())

    def test_numbered_child_context_reconstructs_full_reviewed_skill_in_any_order(self):
        content = "Use only the frozen package.\n" + ("é😀 source and link\n" * 850)
        path = Path(self.directory.name) / "child-skill-context.txt"
        path.write_text(content)
        path.chmod(0o600)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        event = {"hook_event_name": "SubagentStart", "session_id": "s", "agent_id": "child", "agent_type": "Explore"}
        chunks = []
        for index in reversed(range(9)):
            process = self.emit(event, arguments=("--child-context", str(path), "--sha256", digest, "--part", str(index)))
            self.assertEqual(process.returncode, 0)
            if process.stdout:
                message = json.loads(process.stdout)["hookSpecificOutput"]
                self.assertEqual(message["hookEventName"], "SubagentStart")
                label, body = message["additionalContext"].split("\n", 1)
                number = int(label.split("part ")[1].split("/")[0])
                total = int(label.split("/")[1].split(".")[0])
                self.assertLessEqual(len(body.encode()), 8_000)
                chunks.append((number, total, body))
        self.assertEqual(len(chunks), chunks[0][1])
        self.assertEqual("".join(body for _, _, body in sorted(chunks)), content)
        self.assertEqual(self.inbox.read_bytes(), b"")  # Content hooks never write identity events.

    def test_child_context_rejects_tamper_and_symlink_without_leaking_content(self):
        path = Path(self.directory.name) / "child-skill-context.txt"
        path.write_text("private reviewed dummy")
        path.chmod(0o600)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        event = {"hook_event_name": "SubagentStart", "session_id": "s", "agent_id": "child", "agent_type": "Explore"}
        arguments = ("--child-context", str(path), "--sha256", digest, "--part", "0")
        path.write_text("changed private reviewed dummy")
        self.assertEqual(self.emit(event, arguments=arguments).stdout, b"")
        path.unlink()
        target = Path(self.directory.name) / "target"
        target.write_text("private reviewed dummy")
        target.chmod(0o600)
        path.symlink_to(target)
        self.assertEqual(self.emit(event, arguments=arguments).stdout, b"")


if __name__ == "__main__":
    unittest.main()
