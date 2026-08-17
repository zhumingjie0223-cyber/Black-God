"""servers.json read/write — mcpServers object format (Claude-Desktop compatible).

Shared by iOS (iSH) and Android (PRoot). The same file is also read/written by
the native Settings UI (Swift MCPStore / Kotlin), so the on-disk schema must
stay exactly the mcpServers object form:

    {
      "mcpServers": {
        "<name>": {
          "url": "...", "headers": {...},        # HTTP transport, OR
          "command": "...", "args": [...], "env": {...},  # STDIO transport
          "note": "...",
          "enabled": true
        }
      }
    }
"""

import json
import os

CONFIG_DIR = "/var/shuyu/mcp-servers"
CONFIG_PATH = os.path.join(CONFIG_DIR, "servers.json")


def _ensure_dir():
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
    except OSError:
        pass


def load_config():
    """Return the parsed config dict ({"mcpServers": {...}}). Empty on missing
    or unparseable file (callers treat that as "no servers")."""
    _ensure_dir()
    if not os.path.exists(CONFIG_PATH):
        return {"mcpServers": {}}
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {"mcpServers": {}}
    if not isinstance(data, dict) or not isinstance(data.get("mcpServers"), dict):
        return {"mcpServers": {}}
    return data


def save_config(config):
    """Write the config back atomically (write temp + rename) so a concurrent
    reader (Settings UI / agent) never sees a half-written file."""
    _ensure_dir()
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
    os.replace(tmp, CONFIG_PATH)


def get_servers():
    """Return the mcpServers dict (name -> server object)."""
    return load_config().get("mcpServers", {})


def get_server(name):
    """Return one server object or None."""
    return get_servers().get(name)


def upsert_server(name, server):
    """Add or overwrite a server (last-write-wins on name collision)."""
    config = load_config()
    config.setdefault("mcpServers", {})[name] = server
    save_config(config)


def remove_server(name):
    """Delete a server. Returns True if it existed."""
    config = load_config()
    servers = config.setdefault("mcpServers", {})
    if name in servers:
        del servers[name]
        save_config(config)
        return True
    return False


def set_enabled(name, enabled):
    """Flip a server's enabled flag. Returns True if the server existed."""
    config = load_config()
    server = config.get("mcpServers", {}).get(name)
    if server is None:
        return False
    server["enabled"] = bool(enabled)
    save_config(config)
    return True


def is_http(server):
    return bool(server.get("url"))


def is_stdio(server):
    return bool(server.get("command"))
