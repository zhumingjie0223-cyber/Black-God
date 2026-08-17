"""HTTP MCP transport — JSON-RPC 2.0 over HTTP POST.

Flow: initialize -> tools/list / tools/call. Supports the streamable-HTTP MCP
endpoints (single POST returning either application/json or an SSE
`text/event-stream` body, both of which we parse for the JSON-RPC reply).

`$ENV_VAR` references in headers (and URL) are expanded from the process
environment so secrets live in env, not the config file. 5-minute timeout.

Errors are raised as `MCPError(code, message)`; main.py renders the unified
{"error","code","server"} envelope.
"""

import json
import os
import re

try:
    import httpx
except ImportError:  # pragma: no cover - the sh wrapper installs httpx first
    httpx = None

TIMEOUT_SECONDS = 300  # 5 min

# $VAR and $$VAR both expand from the process env; the UI picker emits $$VAR to
# make a reference visually explicit. The optional second `$` is consumed in the
# same match (no double-expansion), so $$VAR / $${VAR} resolve identically to
# $VAR / ${VAR}.
_ENV_RE = re.compile(r"\$\$?\{?([A-Za-z_][A-Za-z0-9_]*)\}?")


class MCPError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def expand_env(value):
    """Replace $VAR / ${VAR} / $$VAR / $${VAR} with the environment value (empty
    if unset)."""
    if not isinstance(value, str):
        return value
    return _ENV_RE.sub(lambda m: os.environ.get(m.group(1), ""), value)


def _expand_headers(headers):
    out = {}
    for k, v in (headers or {}).items():
        out[k] = expand_env(v)
    return out


def _parse_response(resp):
    """Extract the JSON-RPC object from either a JSON body or an SSE stream."""
    ctype = resp.headers.get("content-type", "")
    text = resp.text
    if "text/event-stream" in ctype:
        # SSE: pull the last `data:` payload that parses as JSON-RPC.
        result = None
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                payload = line[len("data:"):].strip()
                try:
                    result = json.loads(payload)
                except ValueError:
                    continue
        if result is None:
            raise MCPError("PARSE_ERROR", "no JSON-RPC payload in SSE stream")
        return result
    try:
        return json.loads(text)
    except ValueError as exc:
        raise MCPError("PARSE_ERROR", "invalid JSON response: %s" % exc)


class HTTPTransport:
    def __init__(self, server, server_name):
        self.url = expand_env(server.get("url", ""))
        self.headers = _expand_headers(server.get("headers"))
        self.server_name = server_name
        self._id = 0
        self._session_id = None

    def _next_id(self):
        self._id += 1
        return self._id

    def _post(self, method, params=None, notify=False):
        if httpx is None:
            raise MCPError("CONNECTION_ERROR", "httpx unavailable")
        body = {"jsonrpc": "2.0", "method": method}
        if not notify:
            body["id"] = self._next_id()
        if params is not None:
            body["params"] = params
        # Force the MCP Streamable HTTP (2025-03-26) required Accept and
        # Content-Type regardless of how the user configured server.headers.
        # setdefault is case-sensitive, so a user-supplied "accept" /
        # "content-type" (any casing) or an incomplete Accept that omits
        # text/event-stream would slip through and some gateways reject it
        # (e.g. 401 "oauth token is not found"). Drop any case-variant of these
        # two keys, then set the canonical values; all other headers
        # (Authorization, etc.) keep their original casing and value.
        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in ("accept", "content-type")
        }
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json, text/event-stream"
        if self._session_id:
            headers["Mcp-Session-Id"] = self._session_id
        try:
            resp = httpx.post(
                self.url, json=body, headers=headers, timeout=TIMEOUT_SECONDS
            )
        except httpx.TimeoutException:
            raise MCPError("TIMEOUT", "request timed out after %ds" % TIMEOUT_SECONDS)
        except httpx.HTTPError as exc:
            raise MCPError("CONNECTION_ERROR", str(exc))
        # Capture a session id handed back by the server (streamable-HTTP).
        sid = resp.headers.get("mcp-session-id")
        if sid:
            self._session_id = sid
        if resp.status_code >= 400:
            raise MCPError(
                "CONNECTION_ERROR", "HTTP %d: %s" % (resp.status_code, resp.text[:200])
            )
        if notify:
            return None
        rpc = _parse_response(resp)
        if isinstance(rpc, dict) and rpc.get("error"):
            err = rpc["error"]
            raise MCPError("MCP_ERROR", err.get("message", json.dumps(err)))
        return rpc.get("result") if isinstance(rpc, dict) else rpc

    def initialize(self):
        result = self._post(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "shuyu-mcp-cli", "version": "1.0.0"},
            },
        )
        # MCP requires a notifications/initialized after a successful init.
        try:
            self._post("notifications/initialized", notify=True)
        except MCPError:
            pass
        return result

    def list_tools(self):
        self.initialize()
        result = self._post("tools/list")
        return (result or {}).get("tools", [])

    def call_tool(self, tool, arguments):
        self.initialize()
        return self._post("tools/call", {"name": tool, "arguments": arguments or {}})

    def ping(self):
        """Round-trip initialize as a reachability check."""
        self.initialize()
        return True
