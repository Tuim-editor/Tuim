#!/usr/bin/env python3
"""Offline lifecycle tests using isolated data and real Neovim startup."""
import importlib.util
import json
import os
import pathlib
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("store", ROOT / "src/nvim/store_search.py")
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class PluginManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tuim-plugins-")
        self.base = pathlib.Path(self.temp.name)
        store.TUIM_DIR = self.base / "data/tuim"
        store.DB_PATH = store.TUIM_DIR / "store_db.json"
        store.USER_PLUGINS_PATH = store.TUIM_DIR / "user_plugins.json"
        store.STATE_PATH = store.TUIM_DIR / "plugin_states.json"
        store.INVENTORY_PATH = store.TUIM_DIR / "plugin_inventory.json"
        self.env = dict(os.environ, NVIM_APPNAME="tuim", XDG_DATA_HOME=str(self.base / "data"),
                        XDG_CONFIG_HOME=str(self.base / "config"), XDG_STATE_HOME=str(self.base / "state"),
                        XDG_CACHE_HOME=str(self.base / "cache"), TUIM_DISABLE_PLUGINS="1", TUIM_SKIP_ONBOARDING="1")

    def tearDown(self):
        self.temp.cleanup()

    def fixture(self, entries):
        store.write_json(store.INVENTORY_PATH, entries)
        for entry in entries:
            (store.TUIM_DIR / "lazy" / entry["name"]).mkdir(parents=True, exist_ok=True)

    def nvim(self, lua):
        script = self.base / "check.lua"
        script.write_text(lua + '\nvim.cmd("qa!")\n')
        result = subprocess.run(["nvim", "--headless", "--clean", "-u", str(ROOT / "src/nvim/tuim_init.lua"),
                                 "-l", str(script)], env=self.env, capture_output=True, text=True, timeout=25)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_offline_complete_inventory(self):
        self.fixture([dict(name=f"plugin-{i}", full_name=f"owner/plugin-{i}", source="Bundled") for i in range(65)])
        (store.TUIM_DIR / "lazy/local-only").mkdir()
        with patch.object(store, "download_db", side_effect=AssertionError("Network used")):
            results = store.search("", "installed")
        self.assertEqual(len(results), 66)
        self.assertTrue(next(p for p in results if p["name"] == "local-only")["protected"])
        self.assertEqual(len(store.search("plugin-64", "installed")), 1)

    def test_lifecycle_preserves_config_and_disabled_files(self):
        self.fixture([dict(name="demo", full_name="owner/demo", enabled=True)])
        config = store.TUIM_DIR / "plugin_configs/owner_demo.lua"
        config.parent.mkdir()
        config.write_text("return {opts = {answer = 42}}")
        store.change_plugin("disable", "owner/demo")
        self.assertFalse(store.inventory()["owner/demo"]["enabled"])
        self.assertTrue((store.TUIM_DIR / "lazy/demo").exists())
        store.change_plugin("enable", "owner/demo")
        store.change_plugin("remove", "owner/demo")
        self.assertEqual(store.inventory()["owner/demo"]["status"], "Removal pending restart")
        store.change_plugin("add", "owner/demo")
        self.assertTrue(store.inventory()["owner/demo"]["enabled"])
        self.assertEqual(config.read_text(), "return {opts = {answer = 42}}")

    def test_dependency_and_manager_protection(self):
        self.fixture([dict(name="parent", full_name="owner/parent"),
                      dict(name="dep", full_name="owner/dep", required_by=["owner/parent"])])
        with self.assertRaisesRegex(ValueError, "Required by"):
            store.change_plugin("remove", "owner/dep")
        store.change_plugin("disable", "owner/parent")
        store.change_plugin("disable", "owner/dep")
        with self.assertRaisesRegex(ValueError, "dependencies first"):
            store.change_plugin("enable", "owner/parent")
        with self.assertRaisesRegex(ValueError, "plugin manager"):
            store.change_plugin("disable", "folke/lazy.nvim")

    def test_corrupt_state_not_overwritten_and_cli_fails(self):
        store.TUIM_DIR.mkdir(parents=True)
        store.STATE_PATH.write_text("broken json")
        result = subprocess.run(["python3", str(ROOT / "src/nvim/store_search.py"), "add", "owner/demo"],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)["success"])
        self.assertEqual(store.STATE_PATH.read_text(), "broken json")

    def test_stale_catalog_fallback(self):
        store.write_json(store.DB_PATH, {"items": [{"name": "demo", "full_name": "owner/demo"}]})
        os.utime(store.DB_PATH, (1, 1))
        with patch.object(store, "download_db", return_value=False):
            self.assertEqual(store.search("demo")[0]["name"], "demo")

    def test_startup_overrides_and_persistent_state(self):
        store.write_json(store.USER_PLUGINS_PATH, ["owner/demo", "owner/broken"])
        store.write_json(store.STATE_PATH, {"folke/tokyonight.nvim": "disabled", "shaunsingh/nord.nvim": "removed"})
        configs = store.TUIM_DIR / "plugin_configs"
        configs.mkdir()
        (configs / "owner_demo.lua").write_text('return {opts={answer=42}, config=function(_, opts) vim.g.plugin_answer=opts.answer end}')
        (configs / "owner_broken.lua").write_text('return invalid lua!')
        (configs / "folke_tokyonight.nvim.lua").write_text('error("Disabled config must not execute")')
        self.nvim('''
local specs = {}
for _, p in ipairs(_G.tuim_plugin_specs) do specs[p[1]] = p end
assert(specs["folke/tokyonight.nvim"].cond == false)
assert(specs["shaunsingh/nord.nvim"].enabled == false)
assert(specs["owner/demo"].opts == nil, "Recovery executed user configuration")
assert(vim.g.plugin_answer == nil)
assert(specs["owner/broken"] ~= nil, "Bad config broke startup")
''')
        entries = store.read_json(store.INVENTORY_PATH, [])
        self.assertTrue(any(p["source"] == "Dependency" for p in entries))
        self.assertTrue(any(p["full_name"] == "folke/lazy.nvim" for p in entries))
        self.assertFalse(next(p for p in entries if p["full_name"] == "folke/tokyonight.nvim")["enabled"])

    def test_real_lazy_load_disable_and_targeted_uninstall(self):
        lazy = pathlib.Path.home() / ".local/share/tuim/lazy/lazy.nvim"
        if not lazy.is_dir():
            self.skipTest("Requires a locally installed lazy.nvim")
        self.nvim("assert(_G.tuim_plugin_specs)")
        states = {p["full_name"]: "removed" for p in store.read_json(store.INVENTORY_PATH, []) if p["full_name"] != "folke/lazy.nvim"}
        states.update({"owner/old": "removed", "owner/sleeping": "disabled"})
        store.write_json(store.STATE_PATH, states)
        store.write_json(store.USER_PLUGINS_PATH, ["owner/live", "owner/old", "owner/sleeping", "owner/broken"])
        root = store.TUIM_DIR / "lazy"
        root.mkdir(exist_ok=True)
        shutil.copytree(lazy, root / "lazy.nvim")
        for name in ("live", "old", "sleeping", "unrelated", "broken"):
            (root / name).mkdir()
            subprocess.run(["git", "init", "-q", str(root / name)], check=True)
            subprocess.run(["git", "-C", str(root / name), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "Fixture"], check=True)
        configs = store.TUIM_DIR / "plugin_configs"
        configs.mkdir()
        (configs / "owner_live.lua").write_text('return {lazy=false, opts={answer=73}, config=function(_, opts) vim.g.live_answer=opts.answer end}')
        (configs / "owner_sleeping.lua").write_text('vim.g.disabled_config_ran=true; return {}')
        (configs / "owner_old.lua").write_text('return {}')
        (configs / "owner_broken.lua").write_text('return invalid lua!')
        self.env.pop("TUIM_DISABLE_PLUGINS")
        self.nvim('''assert(vim.wait(2000, function() return vim.g.live_answer == 73 end), "Plugin options did not reach setup")
assert(not vim.g.disabled_config_ran, "Disabled config executed")
vim.api.nvim_exec_autocmds("VimEnter", {})
assert(vim.wait(5000, function() return vim.fn.isdirectory(vim.fn.stdpath("data") .. "/lazy/old") == 0 end), "Uninstall did not delete plugin")
''')
        self.assertTrue((root / "sleeping").is_dir())
        self.assertTrue((root / "unrelated").is_dir())
        self.assertTrue((configs / "owner_old.lua").exists())


if __name__ == "__main__":
    unittest.main()
