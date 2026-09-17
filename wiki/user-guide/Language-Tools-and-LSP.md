# Language Tools & LSP

Tuim provides out-of-the-box syntax highlighting, autocompletion, diagnostics, and language server management through an integrated stack of Treesitter, blink.cmp, and Mason.

---

## 1. Syntax Highlighting via Treesitter

Treesitter is loaded eagerly at startup to ensure instant, accurate, semantic syntax highlighting.

### Precompiled Parsers (19 Default Languages)
The standard Tuim setup installs and precompiles parsers and highlight queries for:
* **Systems & General**: Zig, C, C++, Rust, Go
* **Scripting**: Python, Lua, Bash
* **Web**: JavaScript, TypeScript, TSX, HTML, CSS, JSON
* **Vim/Editor**: Vim, Vimdoc, Query
* **Documentation**: Markdown, Inline Markdown

To verify your installed parsers, queries, and startup loading:
```bash
TUIM_TEST_PLUGIN_DATA=~/.local/share/tuim python3 tests/default_runtime.py
```

---

## 2. Project Detection & Language Server Recommendations

When you open a project, Tuim inspects root directory markers to identify the programming language and recommends the appropriate Language Server Protocol (LSP) package:

| Language | Recognized Markers | Recommended Server |
| :--- | :--- | :--- |
| **Zig** | `build.zig` | `zls` |
| **Rust** | `Cargo.toml` | `rust_analyzer` |
| **Python** | `pyproject.toml`, `requirements.txt` | `pyright` |
| **Go** | `go.mod` | `gopls` |
| **C / C++** | `CMakeLists.txt`, `compile_commands.json` | `clangd` |
| **JS / TS** | `package.json` | `ts_ls` |
| **Lua** | `.luarc.json`, `stylua.toml` | `lua_ls` |

> [!NOTE]
> Projects without recognizable markers remain manual; Tuim will never automatically download or install unrequested tools behind your back.

---

## 3. Managing LSP Servers with Mason

Open **Language tools** to inspect installed and recommended packages:
* From sidebar: Click `< Workspace` → **Language tools**.
* From Command Palette: Press <kbd>F1</kbd> → **Language tools**.
* From Settings: Open <kbd>F1</kbd> → **Settings** → **Plugins** → **Mason Settings**.

### The Language Tools Panel Shows:
* **Health Summary**: Status of active LSP connections and runtime environment.
* **Active Servers**: Language servers currently attached to open buffers.
* **Recommended Packages**: Servers detected based on current project markers.
* **Installed Tools**: Installed language servers, linters, and formatters.
* **Missing Executables**: Notifies you if an installed tool requires a host dependency (e.g. Node.js or a specific runtime).

---

## 4. Autocompletion & In-line Diagnostics

* **Completion Engine**: Powered by `blink.cmp` with preloaded `friendly-snippets`. As you type, fuzzy completion suggestions appear instantly with minimal latency.
* **Diagnostics**: Syntax errors, warnings, and hints appear directly inline in the editor gutter and beside offending lines.
* **Hover Documentation**: Press <kbd>K</kbd> in Normal mode to view type signatures and documentation popups for the symbol under your cursor.

---

## Next Steps

Learn how to connect AI coding assistants in **[AI Coding Assistants](AI-Coding-Assistants.md)**.
