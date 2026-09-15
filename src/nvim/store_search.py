#!/usr/bin/env python3
"""Tuim marketplace and offline installed-plugin inventory."""
import json
import os
import pathlib
import re
import sys
import tempfile
import time
import urllib.request

TUIM_DIR = pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "tuim"
DB_PATH = TUIM_DIR / "store_db.json"
USER_PLUGINS_PATH = TUIM_DIR / "user_plugins.json"
STATE_PATH = TUIM_DIR / "plugin_states.json"
INVENTORY_PATH = TUIM_DIR / "plugin_inventory.json"


def read_json(path, default):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, type(default)):
        raise ValueError(f"Invalid data in {path.name}; repair this file first")
    return value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(value, file, indent=2)
            file.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def download_db():
    url = "https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/db_minified.json"
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "Tuim"})
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            raise ValueError("Invalid marketplace catalog")
        write_json(DB_PATH, data)
        return True
    except Exception as error:
        sys.stderr.write(f"Catalog refresh failed: {error}\n")
        return False


def inventory():
    states = read_json(STATE_PATH, {})
    entries = {p["full_name"]: dict(p) for p in read_json(INVENTORY_PATH, [])}
    for repo in read_json(USER_PLUGINS_PATH, []):
        entries.setdefault(repo, {"name": repo.rsplit("/", 1)[-1], "full_name": repo, "source": "Marketplace"})
    known_names = {p["name"] for p in entries.values()}
    root = TUIM_DIR / "lazy"
    if root.is_dir():
        for path in sorted(root.iterdir()):
            if path.is_dir() and path.name not in known_names and not path.name.startswith("."):
                # Preserve visibility of local/orphaned plugins without inventing a repository.
                entries["local:" + path.name] = {"name": path.name, "full_name": "local:" + path.name,
                    "source": "Unmanaged", "description": "Local plugin; manage its source with Lazy."}
    for repo, entry in entries.items():
        state = states.get(repo, "enabled")
        on_disk = (root / entry["name"]).is_dir()
        runtime_enabled = entry.get("enabled", True)
        entry.update(installed=state != "removed" and (on_disk or repo in states or entry.get("source") == "Marketplace"),
                     enabled=state == "enabled", stars=0, protected=repo == "folke/lazy.nvim" or repo.startswith("local:"))
        if state == "removed":
            status = "Removal pending restart" if on_disk else "Not installed"
        elif state == "disabled":
            status = "Disabled"
        elif not on_disk:
            status = "Install pending restart"
        else:
            status = "Enabled"
        if state != "removed" and entry["enabled"] != runtime_enabled:
            status += " (restart)"
        entry["status"] = status
        required = entry.get("required_by", [])
        entry["description"] = entry.get("source", "Plugin") + " | " + status + (" | Required by: " + ", ".join(required) if required else "")
    return entries


def search(query, category="all"):
    installed = inventory()
    if category == "installed":
        # No catalog or network required, and no 50-item cap.
        items = [p for p in installed.values() if p["installed"] or p["status"] == "Removal pending restart"]
        results = sorted(items, key=lambda p: p["name"].lower())
    else:
        if not DB_PATH.exists() or time.time() - DB_PATH.stat().st_mtime > 86400:
            download_db()  # A stale cache remains usable offline.
        items = read_json(DB_PATH, {"items": []}).get("items", [])
        tags = {"colorscheme": ["colorscheme", "theme", "color-scheme"], "ai": ["ai", "llm"],
                "treesitter": ["treesitter", "tree-sitter"], "telescope": ["telescope", "telescope-extension"]}
        if category != "all":
            items = [p for p in items if any(t.lower() in tags.get(category, [category]) for t in p.get("tags", []))]
        results = []
        for item in sorted(items, key=lambda p: p.get("stars", {}).get("curr", 0), reverse=True):
            repo = item.get("full_name", "")
            local = installed.get(repo, {})
            results.append(dict(name=item.get("name", ""), full_name=repo,
                                stars=item.get("stars", {}).get("curr", 0), description=item.get("description") or "",
                                installed=local.get("installed", False), enabled=local.get("enabled", True),
                                protected=local.get("protected", False), status=local.get("status", "Not installed")))
    query = query.casefold()
    results = [p for p in results if query in (p["name"] + " " + p["full_name"] + " " + p["description"]).casefold()]
    return results if category == "installed" else results[:50]


def change_plugin(action, repo):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or any(part in (".", "..") for part in repo.split("/")):
        raise ValueError("Only repository plugins can be managed here")
    if repo == "folke/lazy.nvim":
        raise ValueError("Tuim needs its plugin manager")
    entries = inventory()
    entry = entries.get(repo)
    if action != "add" and (not entry or not entry["installed"]):
        raise ValueError("Plugin is not installed")
    if action in ("disable", "remove"):
        required = [r for r in entry.get("required_by", []) if entries.get(r, {}).get("installed") and entries[r]["enabled"]]
        if required:
            raise ValueError("Required by: " + ", ".join(required) + ". Disable these plugins first.")
    if action in ("add", "enable"):
        disabled_deps = [r for r, p in entries.items() if repo in p.get("required_by", []) and (not p["enabled"] or not p["installed"])]
        if disabled_deps:
            raise ValueError("Enable or reinstall dependencies first: " + ", ".join(disabled_deps))
    plugins = read_json(USER_PLUGINS_PATH, [])
    if action == "add" and not entry and repo not in plugins:
        plugins.append(repo)
        write_json(USER_PLUGINS_PATH, plugins)
    states = read_json(STATE_PATH, {})
    states[repo] = {"add": "enabled", "enable": "enabled", "disable": "disabled", "remove": "removed"}[action]
    write_json(STATE_PATH, states)
    return {"success": True, "message": "Saved. Restart Tuim to apply; plugin configuration is kept."}


def main():
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else ""
        if command == "search":
            result = search(sys.argv[2] if len(sys.argv) > 2 else "", sys.argv[3] if len(sys.argv) > 3 else "all")
        elif command in ("add", "remove", "enable", "disable") and len(sys.argv) == 3:
            result = change_plugin(command, sys.argv[2])
        elif command == "download":
            result = {"success": download_db()}
            if not result["success"]:
                raise ValueError("Catalog download failed")
        else:
            raise ValueError("Usage: store_search.py search|add|remove|enable|disable|download [args]")
        print(json.dumps(result))
    except Exception as error:
        print(json.dumps({"success": False, "message": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
