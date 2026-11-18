# A minimal MCP client over stdio for the CI checks in this folder: starts
# clipforge-mcp, does the handshake and calls tools. Standard library only.
import json
import os
import subprocess
import sys
import threading


class Server:
    def __init__(self, command, projects_dir, env=None, new_group=False):
        full_env = dict(os.environ)
        # Always the program under test, not a helper installed on this computer.
        full_env["CLIPFORGE_MCP_NO_HANDOVER"] = "1"
        full_env.update(env or {})
        kwargs = {}
        if new_group and os.name != "nt":
            kwargs["start_new_session"] = True
        self.process = subprocess.Popen(
            list(command) + ["--projects-dir", projects_dir],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=full_env, **kwargs)
        self._next = 1
        self.stderr_lines = []
        threading.Thread(target=self._drain, daemon=True).start()
        self.progress = []

    def _drain(self):
        for line in self.process.stderr:
            self.stderr_lines.append(line.decode("utf-8", "replace").rstrip())

    def request(self, method, params=None):
        ident = self._next
        self._next += 1
        message = {"jsonrpc": "2.0", "id": ident, "method": method}
        if params is not None:
            message["params"] = params
        self.process.stdin.write((json.dumps(message) + "\n").encode("utf-8"))
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("the server closed its output\n" + "\n".join(self.stderr_lines[-30:]))
            reply = json.loads(line.decode("utf-8"))
            if reply.get("id") == ident:
                if "error" in reply:
                    raise RuntimeError("%s: %s" % (method, reply["error"]))
                return reply["result"]
            if reply.get("method") == "notifications/progress":
                self.progress.append(reply["params"].get("message"))

    def initialize(self):
        result = self.request("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "clipforge-ci", "version": "1"}})
        self.process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.process.stdin.flush()
        return result

    def call(self, tool, arguments=None, progress=False):
        params = {"name": tool, "arguments": arguments or {}}
        if progress:
            params["_meta"] = {"progressToken": "ci"}
        result = self.request("tools/call", params)
        text = result["content"][0]["text"]
        if result.get("isError"):
            raise RuntimeError("%s failed: %s" % (tool, text))
        return text, result.get("structuredContent") or {}

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=30)
        except Exception:
            self.process.kill()


def fail(message):
    print("FAILED: " + message, file=sys.stderr)
    sys.exit(1)
