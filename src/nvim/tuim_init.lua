-- Parser generators installed by setup.sh remain private to Tuim.
local tools_bin = vim.fn.stdpath("data") .. "/tools/bin"
vim.env.PATH = tools_bin .. ":" .. (vim.env.PATH or "")
local site = vim.fn.stdpath("data") .. "/site"
vim.opt.rtp:prepend(site)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local plugins_disabled = os.getenv("TUIM_DISABLE_PLUGINS") == "1"
local pending_plugin_notice = nil
local plugin_bootstrapped = false

_G.tuim_native_notice = function(level, message)
  pcall(vim.rpcnotify, 1, "tuim_notice", level, message)
end

if not plugins_disabled and not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  if vim.v.shell_error ~= 0 or not vim.uv.fs_stat(lazypath) then
    plugins_disabled = true
    pending_plugin_notice = "Plugin bootstrap failed; starting offline. Check the log/network, then retry from Settings > Plugins."
  else
    plugin_bootstrapped = true
  end
end
if vim.uv.fs_stat(lazypath) then vim.opt.rtp:prepend(lazypath) end

vim.g.mapleader = " "
vim.opt.hidden = true
vim.opt.shortmess:append("AI")
vim.opt.completeopt = { "menu", "menuone", "noselect" }

local set = vim.opt
set.relativenumber = true
set.number = true
set.tabstop = 4
set.shiftwidth = 4
set.autoindent = true
set.expandtab = true
set.ignorecase = true
set.smartcase = true
set.termguicolors = true
set.background = "dark"
set.signcolumn = "yes"
set.cursorline = false
vim.api.nvim_create_autocmd({ "VimEnter", "WinEnter", "BufWinEnter" }, {
  callback = function()
    vim.wo.cursorline = false
  end,
})
set.colorcolumn = ""
set.clipboard:append("unnamedplus")
if vim.fn.has("clipboard") == 0 then
  vim.defer_fn(function()
    _G.tuim_native_notice("warning", "No Neovim clipboard provider was detected; install xclip, xsel, wl-clipboard, or pbcopy support.")
  end, 150)
end
set.backspace = "indent,eol,start"
set.splitbelow = true
set.splitright = true
set.iskeyword:append("-")
set.scrolloff = 8
set.swapfile = false
set.backup = false
local undodir = vim.fn.stdpath("data") .. "/undo"
vim.fn.mkdir(undodir, "p")
set.undodir = undodir
set.undofile = true
set.incsearch = true
set.updatetime = 50

local user_plugins_path = vim.fn.stdpath("data") .. "/user_plugins.json"

-- One picker language for files, text, buffers and help. Neovim owns the
-- thin borders so they resize and stack with the actual floating windows.
local function configure_pickers()
    local actions = require("telescope.actions")
    local layout_actions = require("telescope.actions.layout")
    local function picker_colors()
        local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
        local normal, float = hl("Normal"), hl("NormalFloat")
        local bg, fg = float.bg or normal.bg or 0x202328, normal.fg or 0xd7dce2
        local accent = hl("Function").fg or hl("Identifier").fg or fg
        local function blend(a, b, weight)
            local value = 0
            for _, shift in ipairs({ 16, 8, 0 }) do
                local av, bv = math.floor(a / 2 ^ shift) % 256, math.floor(b / 2 ^ shift) % 256
                value = value + math.floor(av * weight + bv * (1 - weight)) * 2 ^ shift
            end
            return value
        end
        local border = blend(fg, bg, 0.3)
        for _, name in ipairs({ "TelescopeNormal", "TelescopePromptNormal", "TelescopeResultsNormal", "TelescopePreviewNormal" }) do
            vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg })
        end
        for _, name in ipairs({ "TelescopeBorder", "TelescopePromptBorder", "TelescopeResultsBorder", "TelescopePreviewBorder" }) do
            vim.api.nvim_set_hl(0, name, { fg = border, bg = bg })
        end
        for _, name in ipairs({ "TelescopeTitle", "TelescopePromptTitle", "TelescopeResultsTitle", "TelescopePreviewTitle" }) do
            vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = true })
        end
        vim.api.nvim_set_hl(0, "TelescopeSelection", { fg = fg, bg = blend(accent, bg, 0.15), bold = true })
        vim.api.nvim_set_hl(0, "TelescopeSelectionCaret", { fg = accent, bg = blend(accent, bg, 0.15), bold = true })
        vim.api.nvim_set_hl(0, "TelescopeMatching", { fg = accent, bold = true })
        vim.api.nvim_set_hl(0, "TelescopePromptPrefix", { fg = accent, bg = bg })
    end
    require("telescope").setup({
        defaults = {
            sorting_strategy = "ascending",
            layout_strategy = "horizontal",
            layout_config = {
                width = function(_, columns) return math.min(140, math.max(1, columns - 4)) end,
                height = function(_, _, lines) return math.min(26, math.max(1, lines - 4)) end,
                horizontal = { prompt_position = "top", preview_width = 0.48, preview_cutoff = 110 },
            },
            border = true,
            borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
            prompt_prefix = " > ",
            selection_caret = "> ",
            entry_prefix = "  ",
            path_display = { "filename_first" },
            results_title = false,
            dynamic_preview_title = true,
            winblend = 0,
            mappings = {
                i = { ["<Esc>"] = actions.close, ["<M-p>"] = layout_actions.toggle_preview },
                n = { ["<Esc>"] = actions.close, ["<M-p>"] = layout_actions.toggle_preview },
            },
        },
        pickers = {
            find_files = { prompt_title = "Find files", hidden = true },
            git_files = { prompt_title = "Project files" },
            oldfiles = { prompt_title = "Recent files", cwd_only = true },
            buffers = { prompt_title = "Open files", sort_mru = true, ignore_current_buffer = false },
            live_grep = { prompt_title = "Search project" },
            grep_string = { prompt_title = "Find text" },
            current_buffer_fuzzy_find = { prompt_title = "Search this file", previewer = false },
            help_tags = { prompt_title = "Help" },
            commands = { prompt_title = "Commands", previewer = false },
            diagnostics = { prompt_title = "Problems" },
        },
    })
    picker_colors()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("TuimPickerColors", { clear = true }),
        callback = picker_colors,
    })
end
_G.tuim_configure_pickers = configure_pickers
_G.tuim_picker_action = function(action)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "TelescopePrompt" then
            if action == "preview" then
                require("telescope.actions.layout").toggle_preview(buf)
            else
                local names = { open = "select_default", close = "close", mark = "toggle_selection" }
                local name = names[action]
                if name then require("telescope.actions")[name](buf) end
            end
            return
        end
    end
end

local user_plugins = {}
local up_f = io.open(user_plugins_path, "r")
if up_f then
    local content = up_f:read("*a")
    up_f:close()
    local ok, decoded = pcall(vim.json.decode, content)
    if ok and type(decoded) == "table" then
        user_plugins = decoded
    end
end

-- Keep this list available to the installer and the plugin build hook.
_G.tuim_default_parsers = {
    "bash", "c", "cpp", "css", "go", "html", "javascript", "json", "lua",
    "markdown", "markdown_inline", "python", "query", "rust", "tsx",
    "typescript", "vim", "vimdoc", "zig",
}
_G.tuim_install_parsers = function()
    local ts = require("nvim-treesitter")
    ts.setup({ install_dir = site })
    ts.install(_G.tuim_default_parsers):wait(300000)
    vim.opt.rtp:prepend(site) -- refresh lookup after creating the parser directory
    for _, lang in ipairs(_G.tuim_default_parsers) do
        assert(vim.treesitter.language.add(lang, { path = site .. "/parser/" .. lang .. ".so" }), "Treesitter parser unavailable: " .. lang)
        assert(vim.treesitter.query.get(lang, "highlights"), "Treesitter highlights unavailable: " .. lang)
    end
end

local plugins_setup = {
    {
        "goolord/alpha-nvim",
        lazy = false,
        priority = 1000,
        config = function()
            local dashboard = require("alpha.themes.dashboard")
            dashboard.section.header.val = function()
                return vim.fn.strcharpart('tuim / ' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t'), 0, math.max(8, vim.api.nvim_win_get_width(0) - 6))
            end
            dashboard.section.header.opts.hl = 'Normal'
            dashboard.section.buttons.opts.spacing = 0
            dashboard.config.layout = {
                { type = 'padding', val = 2 }, dashboard.section.header,
                { type = 'padding', val = 2 }, dashboard.section.buttons,
            }

            local function format_key(key)
                if not key or key == "" then return "None" end
                if key:sub(1, 1) == "<" and key:sub(-1) == ">" then
                    local content = key:sub(2, -2)
                    local parts = {}
                    while true do
                        if content:sub(1, 2) == "C-" then
                            table.insert(parts, "Ctrl")
                            content = content:sub(3)
                        elseif content:sub(1, 2) == "M-" then
                            table.insert(parts, "Alt")
                            content = content:sub(3)
                        elseif content:sub(1, 2) == "S-" then
                            table.insert(parts, "Shift")
                            content = content:sub(3)
                        else
                            break
                        end
                    end
                    if #content == 1 then
                        content = content:upper()
                    elseif content:lower() == "esc" then
                        content = "Esc"
                    elseif content:lower() == "cr" or content:lower() == "enter" then
                        content = "Enter"
                    elseif content:lower() == "space" then
                        content = "Space"
                    end
                    table.insert(parts, content)
                    return table.concat(parts, "+")
                end
                return key
            end

            _G.tuim_update_dashboard_keys = function()
                local path = vim.fn.stdpath("data") .. "/settings.json"
                local f = io.open(path, "r")
                local state = {}
                if f then
                    local content = f:read("*a")
                    f:close()
                    local ok, s = pcall(vim.fn.json_decode, content)
                    if ok and type(s) == "table" then
                        state = s
                    end
                end
                
                local kb = state.keybindings or {}
                local raw_new = kb.new_file or "<C-n>"
                local raw_find = kb.find_file or "<C-f>"
                local raw_search = kb.search_project or "<M-g>"
                local raw_quit = kb.quit or "<C-q>"
                local raw_recent = "<C-r>"
                local raw_commands = kb.commands or "<F1>"
                if raw_commands == "" then raw_commands = "<F1>" end
                local raw_help = kb.help or "?"
                if raw_help == "" then raw_help = "?" end
                local width = math.max(12, math.min(44, vim.api.nvim_win_get_width(0) - 6))
                local height = vim.api.nvim_win_get_height(0)
                dashboard.config.layout[3].val = height < 18 and 1 or 2
                local recent_limit = math.max(0, math.min(5, height - 15))
                local function clip(text, limit)
                    while vim.fn.strdisplaywidth(text) > limit do
                        text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
                    end
                    return text
                end
                local function button(key, label, command, muted)
                    local btn = dashboard.button(key, label, command)
                    local shortcut = format_key(key)
                    btn.val = clip(label, math.max(1, width - #shortcut - 2))
                    btn.opts.width = width
                    btn.opts.position = "center"
                    btn.opts.hl = muted and "TuimWelcomeMuted" or "Normal"
                    btn.opts.hl_shortcut = "TuimWelcomeMuted"
                    btn.opts.shortcut = shortcut
                    btn.opts.cursor = 0
                    return btn
                end
                local buttons = {
                    button(raw_new, "New file", "<cmd>enew<cr>"),
                    button(raw_find, "Find file", "<cmd>Telescope find_files<cr>"),
                    button(raw_search, "Search project", "<cmd>Telescope live_grep<cr>"),
                    button(raw_recent, "Recent files", "<cmd>Telescope oldfiles<cr>"),
                    { type = "padding", val = 1 },
                }
                local cwd, recent_count, seen = vim.fn.getcwd(), 0, {}
                for _, path in ipairs(vim.v.oldfiles) do
                    if recent_count >= recent_limit then break end
                    if not seen[path] and vim.fn.filereadable(path) == 1 and path:sub(1, #cwd + 1) == cwd .. '/' then
                        seen[path] = true
                        recent_count = recent_count + 1
                        local item = button(tostring(recent_count), vim.fn.fnamemodify(path, ':.'), nil)
                        item.on_press = function() vim.cmd.edit(vim.fn.fnameescape(path)) end
                        item.opts.keymap = { 'n', tostring(recent_count), item.on_press, { silent = true } }
                        table.insert(buttons, item)
                    end
                end
                if recent_count == 0 and recent_limit > 0 then
                    table.insert(buttons, { type = 'text', val = clip('No recent files in this project', width), opts = { position = 'center', hl = 'TuimWelcomeMuted' } })
                end
                table.insert(buttons, { type = "padding", val = 1 })
                table.insert(buttons, button(raw_commands, "Command menu", "<cmd>lua vim.rpcnotify(1, 'tuim_open_commands')<cr>", true))
                table.insert(buttons, button(raw_help, "Help", "<cmd>HelpMenu<cr>", true))
                table.insert(buttons, button(raw_quit, "Quit", "<cmd>qa<cr>", true))
                dashboard.section.buttons.val = buttons
                local content_height = 1 + dashboard.config.layout[3].val + #buttons
                dashboard.config.layout[1].val = math.max(0, math.floor((height - content_height) / 2))
            end

            _G.tuim_update_dashboard_keys()

            dashboard.opts.opts = {
                noautocmd = true,
            }
            require("alpha").setup(dashboard.config)
            local group = vim.api.nvim_create_augroup("TuimDashboard", { clear = true })
            local function welcome_colors()
                local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
                local fg, bg = normal.fg or 0xd4d4d4, normal.bg or 0x1e1e1e
                local muted = 0
                for _, shift in ipairs({16, 8, 0}) do
                    local f = bit.band(bit.rshift(fg, shift), 255)
                    local b = bit.band(bit.rshift(bg, shift), 255)
                    muted = muted + bit.lshift(math.floor(b + (f - b) * 0.7), shift)
                end
                vim.api.nvim_set_hl(0, 'TuimWelcomeMuted', { fg = muted })
            end
            welcome_colors()
            vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = welcome_colors })
            vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized', 'DirChanged' }, {
                group = group,
                callback = function()
                    if vim.bo.filetype == 'alpha' then
                        _G.tuim_update_dashboard_keys()
                        pcall(function() require('alpha').redraw() end)
                    end
                end,
            })
            vim.api.nvim_create_autocmd({ "FileType" }, {
                group = group,
                pattern = "alpha",
                callback = function()
                    vim.cmd("setlocal nonumber norelativenumber") ;
                    vim.keymap.set("n", "<LeftRelease>", "<LeftRelease><cmd>lua pcall(function() require('alpha').press() end)<CR>", { buffer = true, silent = true })
                    if _G.tuim_update_dashboard_keys then
                        _G.tuim_update_dashboard_keys()
                        pcall(function() require("alpha").redraw() end)
                    end
                end,
            })
        end
    },
    { "nvim-lua/plenary.nvim", lazy = true },
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = configure_pickers,
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
            { "<leader>fb", "<cmd>Telescope buffers<cr>" },
            { "<leader>fh", "<cmd>Telescope help_tags<cr>" },
        }
    },
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        commit = "8b98b4470eb326f1c7b50dae79f8c963568e5720",
        lazy = false,
        build = function() _G.tuim_install_parsers() end,
        config = function()
            require("nvim-treesitter").setup({ install_dir = site })
            local function highlight(buf)
                if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "" then return end
                -- Uninstalled languages keep Vim's syntax fallback. Core parsers
                -- are installed and verified synchronously by setup.sh.
                pcall(vim.treesitter.start, buf)
            end
            vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
                group = vim.api.nvim_create_augroup('TuimTreesitter', { clear = true }),
                callback = function(event) highlight(event.buf) end,
            })
            highlight(vim.api.nvim_get_current_buf())
        end,
    },
    {
        "williamboman/mason.nvim",
        cmd = "Mason",
        keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
        config = true,
    },
    {
        "saghen/blink.cmp",
        lazy = false,
        cond = not vim.g.tuim_is_terminal,
        dependencies = "rafamadriz/friendly-snippets",
        version = "*",
        config = function()
            require("blink.cmp").setup({
                keymap = {
                    preset = "none",
                    ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
                    ["<C-e>"] = { "hide" },
                    ["<CR>"] = { "accept", "fallback" },
                    ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
                    ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
                    ["<C-b>"] = { "scroll_documentation_up", "fallback" },
                    ["<C-f>"] = { "scroll_documentation_down", "fallback" },
                },
                appearance = {
                    use_nvim_cmp_as_default = true,
                    nerd_font_variant = "mono",
                },
                sources = {
                    default = { "lsp", "path", "snippets", "buffer" },
                },
                enabled = function()
                    return vim.g.tuim_autocomplete_enabled ~= false
                end,
            })
        end,
    },
    {
        "neovim/nvim-lspconfig",
        lazy = false,
        cond = not vim.g.tuim_is_terminal,
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "saghen/blink.cmp",
        },
        config = function()
            local lsp_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
            if not lsp_ok then
                _G.tuim_native_notice("error", "LSP setup is unavailable because mason-lspconfig failed to load.")
                return
            end

            local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
            if vim.fn.isdirectory(mason_bin) == 1 then
                vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
            end

            local mason_ok, mason_err = pcall(function()
                require("mason").setup({
                    install_root_dir = vim.fn.stdpath("data") .. "/mason",
                })
            end)
            if not mason_ok then
                _G.tuim_native_notice("error", "Mason setup failed; open Settings > Plugins and retry after checking the log.")
                vim.schedule(function() vim.notify(tostring(mason_err), vim.log.levels.ERROR) end)
                return
            end

            local capabilities = require("blink.cmp").get_lsp_capabilities()

            -- Apply completion capabilities + broad root_markers to all servers.
            -- root_markers is how Neovim 0.12 native LSP determines the project root.
            vim.lsp.config('*', {
                capabilities = capabilities,
                root_markers = {
                    '.git',
                    'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile',
                    'Cargo.toml', 'Cargo.lock',
                    'package.json', 'yarn.lock', 'package-lock.json',
                    'compile_commands.json', 'compile_flags.txt',
                    '.clangd', '.clang-tidy',
                    'build.zig', 'build.zig.zon',
                    '.luarc.json', '.luarc.jsonc',
                    'pyrightconfig.json',
                    'Makefile', 'CMakeLists.txt',
                    'go.mod', 'go.sum',
                    '.hg', '.svn',
                },
            })

            -- Configure lua_ls settings natively
            vim.lsp.config("lua_ls", {
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                    },
                },
            })

            local project_servers = {}
            local seen_servers = {}
            local function recommend(server)
                if not seen_servers[server] then
                    seen_servers[server] = true
                    table.insert(project_servers, server)
                end
            end
            local cwd = vim.fn.getcwd()
            local marker_servers = {
                ["build.zig"] = "zls",
                [".luarc.json"] = "lua_ls",
                ["stylua.toml"] = "lua_ls",
                ["pyproject.toml"] = "pyright",
                ["requirements.txt"] = "pyright",
                ["Cargo.toml"] = "rust_analyzer",
                ["package.json"] = "ts_ls",
                ["go.mod"] = "gopls",
                ["compile_commands.json"] = "clangd",
                ["CMakeLists.txt"] = "clangd",
            }
            for marker, server in pairs(marker_servers) do
                if vim.uv.fs_stat(cwd .. "/" .. marker) then recommend(server) end
            end
            if #project_servers == 0 then
                local ext_server = {
                    zig = "zls", lua = "lua_ls", py = "pyright", rs = "rust_analyzer",
                    js = "ts_ls", jsx = "ts_ls", ts = "ts_ls", tsx = "ts_ls",
                    go = "gopls", c = "clangd", h = "clangd", cpp = "clangd", hpp = "clangd",
                }
                local ext = vim.fn.expand("%:e"):lower()
                if ext_server[ext] then recommend(ext_server[ext]) end
            end
            vim.g.tuim_recommended_servers = project_servers

            mason_lspconfig.setup({
                ensure_installed = project_servers,
                automatic_enable = true,
            })

            if #project_servers > 0 then
                vim.defer_fn(function()
                    _G.tuim_native_notice("info", "Project language tools: " .. table.concat(project_servers, ", "))
                end, 200)
            else
                vim.defer_fn(function()
                    _G.tuim_native_notice("info", "No project language markers detected; choose tools manually in Mason.")
                end, 200)
            end

            -- Enable all installed servers immediately (mason-lspconfig's async refresh
            -- sometimes misses servers on first load)
            local function enable_all()
                local servers = mason_lspconfig.get_installed_servers()
                if #servers > 0 then
                    vim.lsp.enable(servers)
                    pcall(function()
                        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
                                local ft = vim.bo[bufnr].filetype
                                if ft and ft ~= "" then
                                    vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
                                end
                            end
                        end
                    end)
                end
            end

            enable_all()
            vim.defer_fn(enable_all, 500)

            -- Also re-enable on BufReadPost so newly installed servers attach
            vim.api.nvim_create_autocmd("BufReadPost", {
                once = false,
                callback = enable_all,
            })
        end,

    },
    {
        "ThePrimeagen/harpoon",
        keys = {
            { "<leader>a", function() require("harpoon.mark").add_file() end },
            { "<C-e>", function() require("harpoon.ui").toggle_quick_menu() end },
            { "<C-h>", function() require("harpoon.ui").nav_file(1) end },
            { "<C-j>", function() require("harpoon.ui").nav_file(2) end },
            { "<C-k>", function() require("harpoon.ui").nav_file(3) end },
            { "<C-l>", function() require("harpoon.ui").nav_file(4) end },
        }
    },
    { "Mofiqul/vscode.nvim", lazy = false, priority = 1000 },
    { "folke/tokyonight.nvim", lazy = true },
    { "catppuccin/nvim", name = "catppuccin", lazy = true },
    { "ellisonleao/gruvbox.nvim", lazy = true },
    { "shaunsingh/nord.nvim", lazy = true },
    { "scottmckendry/cyberdream.nvim", lazy = true },
    { "rose-pine/neovim", name = "rose-pine", lazy = true },
    { "rebelot/kanagawa.nvim", lazy = true },
    { "EdenEast/nightfox.nvim", lazy = true },
    { "tahayvr/matteblack.nvim", lazy = true },
}
-- Persist desired plugin state separately from plugin code and user options.
local plugin_data = vim.fn.stdpath("data")
local function read_plugin_json(name, fallback)
    local file = io.open(plugin_data .. "/" .. name, "r")
    if not file then return fallback end
    local content = file:read("*a")
    file:close()
    local ok, result = pcall(vim.json.decode, content)
    if ok and type(result) == "table" then return result end
    _G.tuim_native_notice("error", "Cannot read " .. name .. "; repair it before changing plugins.")
    return fallback
end
local plugin_states = read_plugin_json("plugin_states.json", {})
local plugin_inventory = {}
local function register_spec(spec, source, parent)
    if type(spec) == "string" then spec = { spec } end
    if type(spec) ~= "table" or type(spec[1]) ~= "string" then return spec end
    local repo = spec[1]
    local name = spec.name or repo:match("([^/]+)$"):gsub("%.git$", "")
    local entry = plugin_inventory[repo]
    if not entry then
        entry = { name = name, full_name = repo, source = source, required_by = {},
            description = spec.desc or "", enabled = plugin_states[repo] ~= "disabled",
            removed = plugin_states[repo] == "removed" }
        plugin_inventory[repo] = entry
    end
    if parent and not vim.tbl_contains(entry.required_by, parent) then
        table.insert(entry.required_by, parent)
    end
    local deps = spec.dependencies
    if type(deps) == "string" then deps = { deps } end
    if type(deps) == "table" then
        for i, dep in ipairs(deps) do deps[i] = register_spec(dep, "Dependency", repo) end
        spec.dependencies = deps
    end
    return spec
end
for i, spec in ipairs(plugins_setup) do plugins_setup[i] = register_spec(spec, "Bundled") end
for _, repo in ipairs(user_plugins) do
    if type(repo) == "string" and not plugin_inventory[repo] then
        table.insert(plugins_setup, register_spec({ repo }, "Marketplace"))
    end
end
-- Dependency specs discovered by Lazy can also receive persistent overrides.
for repo, _ in pairs(plugin_states) do
    if type(repo) == "string" and repo:match("^[%w_.-]+/[%w_.-]+$") and repo ~= "folke/lazy.nvim" and not plugin_inventory[repo] then
        table.insert(plugins_setup, register_spec({ repo }, "Dependency"))
    end
end
register_spec({ "folke/lazy.nvim" }, "Plugin manager")

-- Overrides are lazy.nvim spec tables: opts, config, keys, events, etc.
-- Keep repository identity and lifecycle controls owned by the manager.
local function configure_spec(spec)
    local repo = spec[1]
    for _, dep in ipairs(spec.dependencies or {}) do configure_spec(dep) end
    if plugin_states[repo] == "removed" then spec.enabled = false; return
    elseif plugin_states[repo] == "disabled" then spec.cond = false; return end
    local config_path = plugin_data .. "/plugin_configs/" .. repo:gsub("/", "_") .. ".lua"
    if not plugins_disabled and vim.fn.filereadable(config_path) == 1 then
        local ok, custom = pcall(dofile, config_path)
        if ok and type(custom) == "table" then
            for key, value in pairs(custom) do
                if type(key) == "string" and not vim.tbl_contains({ "name", "dir", "url", "dependencies", "enabled", "cond" }, key) then
                    if key == "opts" and type(value) == "table" and type(spec.opts) == "table" then
                        spec.opts = vim.tbl_deep_extend("force", spec.opts, value)
                    else spec[key] = value end
                end
            end
        elseif not ok or custom ~= nil then
            _G.tuim_native_notice("error", "Plugin config failed for " .. repo .. ": " .. tostring(custom))
        end
    end
end
for _, spec in ipairs(plugins_setup) do configure_spec(spec) end
_G.tuim_plugin_specs = plugins_setup
_G.tuim_write_plugin_inventory = function()
    local ok, config = pcall(require, "lazy.core.config")
    if ok then
        for name, plugin in pairs(config.plugins or {}) do
            local repo = plugin[1]
            if type(repo) == "string" then
                if not plugin_inventory[repo] then
                    plugin_inventory[repo] = { name = name, full_name = repo, source = "Dependency",
                        required_by = {}, enabled = plugin_states[repo] ~= "disabled" }
                end
                local entry = plugin_inventory[repo]
                entry.name = name
                entry.loaded = plugin._ and plugin._.loaded ~= nil or false
            end
        end
        for _, plugin in pairs(config.plugins or {}) do
            for _, name in ipairs(plugin.dependencies or {}) do
                local dep = config.plugins[name]
                local entry = dep and plugin_inventory[dep[1]]
                if entry and type(plugin[1]) == "string" and not vim.tbl_contains(entry.required_by, plugin[1]) then
                    table.insert(entry.required_by, plugin[1])
                end
            end
        end
    end
    local entries = {}
    for _, entry in pairs(plugin_inventory) do table.insert(entries, entry) end
    table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
    vim.fn.mkdir(plugin_data, "p")
    local path = plugin_data .. "/plugin_inventory.json"
    local tmp = path .. "." .. vim.fn.getpid() .. ".tmp"
    local file = io.open(tmp, "w")
    if file then
        file:write(vim.json.encode(entries)); file:close(); os.rename(tmp, path)
    end
end
_G.tuim_write_plugin_inventory()
vim.api.nvim_create_autocmd("User", {
    pattern = { "LazyDone", "LazyLoad", "LazyInstall", "LazyClean", "LazySync" },
    callback = function() vim.schedule(_G.tuim_write_plugin_inventory) end,
})
-- Clean only plugins explicitly uninstalled by the user, after the new spec loads.
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function()
    if plugins_disabled then return end
    local names = {}
    for repo, entry in pairs(plugin_inventory) do
        if plugin_states[repo] == "removed" and repo ~= "folke/lazy.nvim" then table.insert(names, entry.name) end
    end
    if #names > 0 then
        vim.schedule(function()
            local ok, lazy = pcall(require, "lazy")
            if ok then
                local targets = {}
                for _, plugin in ipairs(require("lazy.core.config").to_clean or {}) do
                    if vim.tbl_contains(names, plugin.name) then table.insert(targets, plugin) end
                end
                if #targets > 0 then lazy.clean({ plugins = targets, show = false }) end
            end
        end)
    end
end })
if not plugins_disabled then
    local lazy_ok, lazy = pcall(require, "lazy")
    if lazy_ok then
      local setup_ok, setup_err = pcall(lazy.setup, plugins_setup, {
        root = vim.fn.stdpath("data") .. "/lazy",
        lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
        performance = {
            rtp = {
                reset = false, -- Prevent lazy.nvim from adding user's ~/.config/nvim back to RTP
            }
        }
      })
      if not setup_ok then
        plugins_disabled = true
        pending_plugin_notice = "Plugin setup failed; Tuim continued without plugins. Use TUIM_DISABLE_PLUGINS=1 to repair safely."
        vim.schedule(function() vim.notify(tostring(setup_err), vim.log.levels.ERROR) end)
      end
    else
      plugins_disabled = true
      pending_plugin_notice = "lazy.nvim is unavailable; Tuim continued offline. Retry plugin sync from Settings > Plugins."
    end
end

if plugins_disabled then
  vim.g.tuim_plugins_disabled = true
end

_G.tuim_retry_plugins = function()
  _G.tuim_native_notice("info", "Retrying plugin bootstrap and synchronization...")
  if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none",
      "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
  end
  if vim.v.shell_error ~= 0 or not vim.uv.fs_stat(lazypath) then
    _G.tuim_native_notice("error", "Plugin retry failed. Check network access and the Tuim log, or continue offline.")
    return
  end
  vim.opt.rtp:prepend(lazypath)
  local lazy_ok, lazy = pcall(require, "lazy")
  local setup_ok, setup_err = false, nil
  if lazy_ok then
    setup_ok, setup_err = pcall(lazy.setup, plugins_setup, {
      root = vim.fn.stdpath("data") .. "/lazy",
      lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
      performance = { rtp = { reset = false } },
    })
  end
  if not lazy_ok or not setup_ok then
    _G.tuim_native_notice("error", "Plugin setup retry failed; continue offline or use TUIM_DISABLE_PLUGINS=1.")
    if setup_err then vim.notify(tostring(setup_err), vim.log.levels.ERROR) end
    return
  end
  plugins_disabled = false
  vim.g.tuim_plugins_disabled = false
  _G.tuim_native_notice("info", "Plugin manager recovered; synchronizing plugins.")
  vim.cmd("Lazy sync")
end

if pending_plugin_notice then
  vim.defer_fn(function() _G.tuim_native_notice("warning", pending_plugin_notice) end, 100)
elseif plugin_bootstrapped then
  vim.defer_fn(function() _G.tuim_native_notice("info", "Plugin manager installed; bundled plugins are synchronizing.") end, 100)
elseif os.getenv("TUIM_DISABLE_PLUGINS") == "1" then
  vim.defer_fn(function() _G.tuim_native_notice("warning", "Plugins are disabled for this recovery session.") end, 100)
end

local ide_mappings = {
    i = {
        ['<Esc>'] = '<nop>',
        ['<C-Left>'] = '<C-o>b', ['<C-Right>'] = '<C-o>w',
        ['<D-Left>'] = '<Home>', ['<D-Right>'] = '<End>',
        ['<S-Left>'] = '<C-o>v<Left>', ['<S-Right>'] = '<C-o>v<Right>',
        ['<S-Up>'] = '<C-o>v<Up>', ['<S-Down>'] = '<C-o>v<Down>',
        ['<S-Home>'] = '<C-o>v<Home>', ['<S-End>'] = '<C-o>v<End>',
        ['<C-S-Left>'] = '<C-o>v<C-Left>', ['<C-S-Right>'] = '<C-o>v<C-Right>',
        ['<D-S-Left>'] = '<C-o>v<C-Left>', ['<D-S-Right>'] = '<C-o>v<C-Right>',
        ['<D-S-Home>'] = '<C-o>v<Home>', ['<D-S-End>'] = '<C-o>v<End>',
    },
    n = { ['<Esc>'] = 'i' },
    v = {
        ['<Esc>'] = '<C-c>i',
        ['<S-Left>'] = '<Left>', ['<S-Right>'] = '<Right>',
        ['<S-Up>'] = '<Up>', ['<S-Down>'] = '<Down>',
        ['<S-Home>'] = '<Home>', ['<S-End>'] = '<End>',
        ['<C-S-Left>'] = 'b', ['<C-S-Right>'] = 'w',
        ['<D-S-Left>'] = 'b', ['<D-S-Right>'] = 'w',
        ['<D-S-Home>'] = '<Home>', ['<D-S-End>'] = '<End>',
        ['<BS>'] = '"_c', ['<Del>'] = '"_c',
    },
}

local save_prompt_buffer = nil

local function ide_startinsert()
    if not save_prompt_buffer and vim.g.tuim_ide_mode and vim.bo.modifiable and
        (vim.bo.buftype == '' or vim.bo.buftype == 'acwrite') then
        vim.schedule(function()
            if not save_prompt_buffer then pcall(vim.cmd, 'startinsert') end
        end)
    end
end

local function ide_clipboard_register()
    local system_clipboard_enabled = vim.o.clipboard:match('unnamedplus') ~= nil
    return vim.fn.has('clipboard') == 1 and system_clipboard_enabled and '+' or '"'
end

-- Native shortcuts such as Ctrl+F can be pressed while a Telescope picker or
-- another floating window owns focus.  Plain `:close` refuses to close a
-- modified prompt buffer (E37), and the resulting RPC error is rendered into
-- the UI.  Let Telescope clean itself up first, then force-close any remaining
-- floats so global actions are safe to repeat.
_G.tuim_close_floating_windows = function()
    local telescope_prompts = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
        if ok and vim.bo[bufnr].filetype == 'TelescopePrompt' then
            telescope_prompts[bufnr] = true
        end
    end

    if next(telescope_prompts) then
        local ok, actions = pcall(require, 'telescope.actions')
        if ok then
            for bufnr in pairs(telescope_prompts) do
                pcall(actions.close, bufnr)
            end
        end
    end

    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local ok, config = pcall(vim.api.nvim_win_get_config, winid)
        if ok and config.relative ~= '' then
            pcall(vim.api.nvim_win_close, winid, true)
        end
    end
end

local function tuim_primary_editor_win()
    local best_win, best_col, best_row = nil, math.huge, math.huge
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(winid)
        local buf = vim.api.nvim_win_get_buf(winid)
        if config.relative == "" and vim.bo[buf].buftype == "" then
            local pos = vim.api.nvim_win_get_position(winid)
            if pos[2] < best_col or (pos[2] == best_col and pos[1] < best_row) then
                best_win, best_col, best_row = winid, pos[2], pos[1]
            end
        end
    end
    return best_win
end

_G.tuim_select_buffer = function(bufnr)
    bufnr = tonumber(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end
    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_set_current_win(winid)
            return true
        end
    end
    local primary = tuim_primary_editor_win()
    if primary and vim.api.nvim_win_is_valid(primary) then vim.api.nvim_set_current_win(primary) end
    vim.api.nvim_set_current_buf(bufnr)
    return true
end

_G.tuim_new_primary_buffer = function()
    local primary = tuim_primary_editor_win()
    if primary and vim.api.nvim_win_is_valid(primary) then vim.api.nvim_set_current_win(primary) end
    vim.cmd("enew")
end

-- Close a specific buffer from Tuim's tab strip.  Using nvim_buf_delete
-- directly gives modified buffers no confirmation UI, which makes the close
-- button appear broken.  Select the requested buffer first so Neovim can show
-- its normal confirmation in the editor window.
_G.tuim_close_buffer = function(bufnr)
    bufnr = tonumber(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end

    -- AI terminals belong to their split rather than the file tab strip. Stop
    -- their job and remove them without Neovim's "add ! to override" prompt.
    if bufnr == _G.last_ai_buf and _G.CloseAITerminal then
        _G.CloseAITerminal()
        return not vim.api.nvim_buf_is_valid(bufnr)
    end

    if vim.bo[bufnr].buftype == 'terminal' then
        local windows = vim.fn.win_findbuf(bufnr)
        -- Closing a terminal buffer explicitly ends its job. Delete first so
        -- Neovim can retain a usable buffer when this is the last window.
        vim.api.nvim_buf_delete(bufnr, { force = true })
        for _, win in ipairs(windows) do
            if vim.api.nvim_win_is_valid(win) and #vim.api.nvim_list_wins() > 1 then
                pcall(vim.api.nvim_win_close, win, false)
            end
        end
        return not vim.api.nvim_buf_is_valid(bufnr)
    end

    if vim.bo[bufnr].modified then
        if vim.api.nvim_get_current_buf() ~= bufnr then _G.tuim_select_buffer(bufnr) end
        vim.cmd('confirm bdelete ' .. bufnr)
    else
        vim.api.nvim_buf_delete(bufnr, {})
    end
    return not vim.api.nvim_buf_is_valid(bufnr)
end

_G.tuim_close_split = function(winid, bufnr)
    winid = tonumber(winid)
    bufnr = tonumber(bufnr)
    if bufnr == _G.last_ai_buf and _G.CloseAITerminal then
        _G.CloseAITerminal()
        return true
    end
    if not winid or not vim.api.nvim_win_is_valid(winid) then return false end
    local ok, err = pcall(vim.api.nvim_win_close, winid, false)
    if not ok then _G.tuim_native_notice("warning", tostring(err)) end
    return ok
end

-- All native save actions share first-save naming, including offline sessions.
_G.tuim_save_file = function()
    if save_prompt_buffer then return end
    local bufnr = vim.api.nvim_get_current_buf()
    local function write(path)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local was_unnamed = vim.api.nvim_buf_get_name(bufnr) == ''
        local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
            vim.cmd('write' .. (path and (' ' .. vim.fn.fnameescape(path)) or ''))
        end)
        if ok then
            _G.tuim_native_notice('info', 'Saved ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':~:.'))
        else
            -- A failed :write may assign the name before discovering an I/O error.
            -- Keep first-save naming available so the user can correct the path.
            if was_unnamed then pcall(vim.api.nvim_buf_set_name, bufnr, '') end
            _G.tuim_native_notice('error', 'Could not save file: ' .. tostring(err))
        end
    end
    if vim.api.nvim_buf_get_name(bufnr) ~= '' or vim.bo[bufnr].buftype ~= '' then
        write()
        return
    end

    save_prompt_buffer = bufnr
    local ok, err = pcall(vim.ui.input, {
        prompt = 'Save new file as (Enter to save, Esc to cancel): ',
        completion = 'file',
    }, function(path)
        save_prompt_buffer = nil
        if path and path ~= '' then
            if vim.uv.fs_stat(path) then
                _G.tuim_native_notice('warning', 'That path already exists. Press Ctrl+S and choose another filename.')
            else
                write(path)
            end
        end
        ide_startinsert()
    end)
    if not ok then
        save_prompt_buffer = nil
        _G.tuim_native_notice('error', 'Could not open filename prompt: ' .. tostring(err))
        ide_startinsert()
    end
end

_G.tuim_ide_action = function(action)
    local mode = vim.api.nvim_get_mode().mode
    local visual = mode:match('[vV\22]') ~= nil
    if action == 'save' then _G.tuim_save_file()
    elseif action == 'undo' then pcall(vim.cmd, 'undo')
    elseif action == 'redo' then pcall(vim.cmd, 'redo')
    elseif action == 'select_all' then vim.cmd('normal! ggVG'); return
    elseif action == 'select_line' then vim.cmd('normal! V'); return
    elseif action == 'copy' and visual then
        vim.cmd('normal! "' .. ide_clipboard_register() .. 'y')
    elseif action == 'cut' and visual then
        vim.cmd('normal! "' .. ide_clipboard_register() .. 'd')
    elseif action == 'paste' then
        if visual then vim.cmd('normal! "_d') end
        vim.cmd('normal! "' .. ide_clipboard_register() .. 'p')
    elseif action == 'find' then vim.cmd('Telescope current_buffer_fuzzy_find')
    elseif action == 'replace' then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(':%s/', true, false, true), 'n', false); return
    elseif action == 'new' then vim.cmd('enew')
    elseif action == 'close' then _G.tuim_close_buffer(vim.api.nvim_get_current_buf())
    elseif action == 'next_buffer' then vim.cmd('bnext')
    elseif action == 'previous_buffer' then vim.cmd('bprevious')
    end
    ide_startinsert()
end

local function ide_action_map(modes, lhs, action)
    vim.keymap.set(modes, lhs, function() _G.tuim_ide_action(action) end,
        { silent = true, desc = 'IDE: ' .. action:gsub('_', ' ') })
end

_G.tuim_enable_ide_mode = function()
    vim.g.tuim_ide_mode = true
    for mode, mappings in pairs(ide_mappings) do
        for lhs, rhs in pairs(mappings) do vim.keymap.set(mode, lhs, rhs, { silent = true, desc = 'IDE mode' }) end
    end
    for _, spec in ipairs({
        { '<C-s>', 'save' }, { '<D-s>', 'save' }, { '<C-z>', 'undo' },
        { '<D-z>', 'undo' }, { '<C-y>', 'redo' }, { '<C-S-z>', 'redo' }, { '<D-S-z>', 'redo' },
        { '<C-a>', 'select_all' }, { '<D-a>', 'select_all' }, { '<C-l>', 'select_line' },
        { '<C-c>', 'copy' }, { '<D-c>', 'copy' }, { '<C-x>', 'cut' }, { '<D-x>', 'cut' },
        { '<C-v>', 'paste' }, { '<D-v>', 'paste' }, { '<C-f>', 'find' }, { '<D-f>', 'find' },
        { '<C-h>', 'replace' }, { '<D-r>', 'replace' },
    }) do ide_action_map({ 'i', 'n', 'v', 's' }, spec[1], spec[2]) end
    ide_startinsert()
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "ModeChanged" }, {
        group = vim.api.nvim_create_augroup("TuimIdeMode", { clear = true }),
        callback = function(event)
            if event.event ~= 'ModeChanged' or vim.api.nvim_get_mode().mode == 'n' then ide_startinsert() end
        end,
    })
end

_G.tuim_disable_ide_mode = function()
    vim.g.tuim_ide_mode = false
    vim.cmd("stopinsert")
    for mode, mappings in pairs(ide_mappings) do
        for lhs in pairs(mappings) do pcall(vim.keymap.del, mode, lhs) end
    end
    for _, lhs in ipairs({ '<C-s>', '<D-s>', '<C-z>', '<D-z>', '<C-y>', '<C-S-z>', '<D-S-z>',
        '<C-a>', '<D-a>', '<C-l>', '<C-c>', '<D-c>', '<C-x>', '<D-x>', '<C-v>', '<D-v>',
        '<C-f>', '<D-f>', '<C-h>', '<D-r>' }) do
        for _, mode in ipairs({ 'i', 'n', 'v', 's' }) do pcall(vim.keymap.del, mode, lhs) end
    end
    pcall(vim.api.nvim_del_augroup_by_name, "TuimIdeMode")
end

-- System reads only the desktop theme spec, never the user's Neovim init.
do
    local enabled, timer, signature, applying = false, nil, nil, false
    local theme_runtime
    local function system_highlight(buf)
        if not enabled or vim.bo[buf].buftype ~= '' then return end
        local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
        if not lang then return end
        local ok, loaded = pcall(vim.treesitter.language.add, lang)
        if not ok or not loaded then
            local data = vim.env.XDG_DATA_HOME or ((vim.env.HOME or vim.fn.expand('~')) .. '/.local/share')
            local site = data .. '/nvim/site'
            -- Reuse only installed parser/query assets, without loading nvim's config.
            ok, loaded = pcall(vim.treesitter.language.add, lang, { path = site .. '/parser/' .. lang .. '.so' })
            if not ok or not loaded then return end
            local query = site .. '/queries/' .. lang .. '/highlights.scm'
            if vim.fn.filereadable(query) == 1 then
                pcall(vim.treesitter.query.set, lang, 'highlights', table.concat(vim.fn.readfile(query), '\n'))
            end
        end
        pcall(vim.treesitter.start, buf, lang)
    end
    local function stop()
        enabled, signature = false, nil
        if timer then timer:stop(); timer:close(); timer = nil end
        _G.tuim_system_palette = nil
        _G.tuim_system_colorscheme = nil
        if theme_runtime then vim.opt.rtp:remove(theme_runtime); theme_runtime = nil end
    end
    local function desktop_theme(path)
        local file = io.open(path, 'r')
        if not file then return nil, '' end
        local content = file:read(65537) or ''
        file:close()
        if #content > 65536 then return nil, '' end
        -- Desktop theme files are declarative Lazy specs. An empty environment
        -- excludes config side effects; unsupported specs use the palette.
        local chunk = loadstring(content, '@' .. path)
        if not chunk then return nil, content end
        setfenv(chunk, {})
        local ok, specs = pcall(chunk)
        if not ok or type(specs) ~= 'table' then return nil, content end
        local name
        for _, spec in ipairs(specs) do
            if type(spec) == 'table' and spec[1] == 'LazyVim/LazyVim' and type(spec.opts) == 'table' then
                name = spec.opts.colorscheme
            end
        end
        if type(name) ~= 'string' or not name:match('^[%w_.-]+$') then return nil, content end
        local data = vim.env.XDG_DATA_HOME or ((vim.env.HOME or vim.fn.expand('~')) .. '/.local/share')
        for _, spec in ipairs(specs) do
            local repo = type(spec) == 'table' and spec[1] or spec
            if type(repo) == 'string' and repo ~= 'LazyVim/LazyVim' then
                local directory = repo:match('^[%w_.-]+/([%w_.-]+)$')
                if directory then
                    for _, root in ipairs({ vim.fn.stdpath('data'), data .. '/nvim' }) do
                        local runtime = root .. '/lazy/' .. directory
                        if vim.uv.fs_stat(runtime .. '/colors/' .. name .. '.lua') or vim.uv.fs_stat(runtime .. '/colors/' .. name .. '.vim') then
                            return { name = name, runtime = runtime }, content .. runtime
                        end
                    end
                end
            end
        end
        return nil, content
    end
    local function mix(a, b, amount)
        local out = '#'
        for i = 2, 6, 2 do
            local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
            out = out .. string.format('%02x', math.floor(x + (y - x) * amount + 0.5))
        end
        return out
    end
    local function read_palette()
        local home = vim.env.HOME or vim.fn.expand('~')
        local state = vim.env.XDG_STATE_HOME or (home .. '/.local/state')
        local config = vim.env.XDG_CONFIG_HOME or (home .. '/.config')
        for _, root in ipairs({ state, config }) do
            local path = root .. '/omarchy/current/theme/colors.toml'
            local file = io.open(path, 'r')
            if file then
                local content = file:read(65537) or ''
                file:close()
                if #content <= 65536 then
                    local p = {}
                    for line in content:gmatch('[^\r\n]+') do
                        local key, value = line:match('^%s*([%w_]+)%s*=%s*["\'](#[%x]+)["\']')
                        if key and #value == 7 then p[key] = value end
                        local mode = line:match('^%s*mode%s*=%s*["\'](%a+)["\']')
                        if mode == 'dark' or mode == 'light' then p.mode = mode end
                    end
                    if p.background and p.foreground then
                        local theme, spec = desktop_theme(root .. '/omarchy/current/theme/neovim.lua')
                        p.desktop_theme = theme
                        return p, path .. '\n' .. content .. '\n' .. spec
                    end
                end
            end
        end
    end
    local function apply(p)
        applying = true
        local bg, fg = p.background, p.foreground
        local brightness = tonumber(bg:sub(2, 3), 16) * 0.299
            + tonumber(bg:sub(4, 5), 16) * 0.587 + tonumber(bg:sub(6, 7), 16) * 0.114
        vim.g.colors_name = nil
        vim.o.background = p.mode or (brightness > 128 and 'light' or 'dark')
        vim.cmd('highlight clear')
        if vim.g.syntax_on then vim.cmd('syntax reset') end
        local accent = p.accent or p.blue or p.color4 or fg
        local sidebar = p.dark_background or mix(bg, fg, 0.04)
        local raised = p.lighter_background or mix(bg, fg, 0.08)
        local muted = p.light_foreground or mix(bg, fg, 0.6)
        local border = p.muted or mix(bg, fg, 0.3)
        local red, green = p.red or p.color1 or accent, p.green or p.color2 or accent
        local yellow, blue = p.yellow or p.color3 or accent, p.blue or p.color4 or accent
        local magenta, cyan = p.magenta or p.color5 or accent, p.cyan or p.color6 or accent
        p.selection_background = p.selection_background or p.selection or mix(bg, accent, 0.35)
        p.selection_foreground = p.selection_foreground or fg
        p.terminal_colors = { p.color0 or bg, red, green, yellow, blue, magenta, cyan,
            p.color7 or fg, p.color8 or muted, p.bright_red or p.color9 or red,
            p.bright_green or p.color10 or green, p.bright_yellow or p.color11 or yellow,
            p.bright_blue or p.color12 or blue, p.bright_magenta or p.color13 or magenta,
            p.bright_cyan or p.color14 or cyan, p.bright_foreground or p.color15 or fg }
        local highlights = {
            Normal = { fg = fg, bg = bg }, NormalNC = { fg = fg, bg = bg },
            NormalFloat = { fg = fg, bg = sidebar }, FloatBorder = { fg = border, bg = sidebar },
            NeoTreeNormal = { fg = fg, bg = sidebar }, NeoTreeNormalNC = { fg = fg, bg = sidebar },
            NvimTreeNormal = { fg = fg, bg = sidebar },
            Comment = { fg = muted, italic = true }, Identifier = { fg = fg },
            Constant = { fg = p.orange or yellow }, String = { fg = green },
            Character = { fg = green }, Number = { fg = p.orange or yellow },
            Boolean = { fg = p.orange or yellow }, Float = { fg = p.orange or yellow },
            Function = { fg = blue }, Statement = { fg = magenta }, Keyword = { fg = magenta },
            Operator = { fg = accent }, PreProc = { fg = cyan }, Type = { fg = yellow },
            Special = { fg = cyan }, Delimiter = { fg = fg }, Underlined = { fg = blue, underline = true },
            Error = { fg = red }, ErrorMsg = { fg = red }, WarningMsg = { fg = yellow },
            Todo = { fg = bg, bg = accent, bold = true },
            DiagnosticError = { fg = red }, DiagnosticWarn = { fg = yellow },
            DiagnosticInfo = { fg = blue }, DiagnosticHint = { fg = cyan },
            Cursor = { fg = bg, bg = p.cursor or fg },
            CursorLine = { bg = raised }, CursorColumn = { bg = raised },
            LineNr = { fg = muted, bg = bg }, CursorLineNr = { fg = accent, bold = true },
            SignColumn = { bg = bg }, FoldColumn = { fg = muted, bg = bg },
            Folded = { fg = muted, bg = raised }, EndOfBuffer = { fg = border },
            WinSeparator = { fg = border, bg = bg }, VertSplit = { fg = border, bg = bg },
            Visual = { fg = p.selection_foreground, bg = p.selection_background },
            Search = { fg = bg, bg = yellow }, IncSearch = { fg = bg, bg = accent },
            Pmenu = { fg = fg, bg = sidebar }, PmenuSel = { fg = bg, bg = accent },
            PmenuSbar = { bg = raised }, PmenuThumb = { bg = muted },
            StatusLine = { fg = bg, bg = accent }, StatusLineNC = { fg = muted, bg = sidebar },
            TabLine = { fg = muted, bg = raised }, TabLineSel = { fg = accent, bg = bg, bold = true },
            TabLineFill = { bg = sidebar }, TuimAccent = { fg = accent },
            DiffAdd = { bg = mix(bg, green, 0.2) }, DiffDelete = { fg = red, bg = mix(bg, red, 0.2) },
            DiffChange = { bg = mix(bg, blue, 0.2) }, DiffText = { bg = mix(bg, blue, 0.35) },
        }
        for name, hl in pairs(highlights) do vim.api.nvim_set_hl(0, name, hl) end
        for name, target in pairs({ ['@variable'] = 'Identifier', ['@function'] = 'Function',
            ['@keyword'] = 'Keyword', ['@string'] = 'String', ['@type'] = 'Type',
            ['@comment'] = 'Comment', ['@constant'] = 'Constant', ['@number'] = 'Number',
            ['@boolean'] = 'Boolean', ['@operator'] = 'Operator' }) do
            vim.api.nvim_set_hl(0, name, { link = target })
        end
        _G.tuim_system_colorscheme = nil
        if theme_runtime then vim.opt.rtp:remove(theme_runtime); theme_runtime = nil end
        if p.desktop_theme then
            theme_runtime = p.desktop_theme.runtime
            vim.opt.rtp:prepend(theme_runtime)
            _G.tuim_system_colorscheme = p.desktop_theme.name
            if not pcall(vim.cmd.colorscheme, p.desktop_theme.name) then
                p.desktop_theme = nil
                return apply(p)
            end
        end
        _G.tuim_system_palette = p
        vim.g.colors_name = 'system'
        vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'system', modeline = false })
        applying = false
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) then system_highlight(buf) end
        end
    end
    local function refresh()
        if not enabled then return end
        local p, content = read_palette()
        -- Omarchy replaces the theme directory during a switch. Retain the
        -- last valid palette through that gap or an incomplete write.
        if p and content ~= signature then
            apply(p)
            signature = content
        end
    end
    local function dark_modern()
        vim.o.background = 'dark'
        local ok, vscode = pcall(require, 'vscode')
        if ok then
            vscode.setup({
                style = 'dark',
                color_overrides = {
                    vscBack = '#1F1F1F', vscFront = '#CCCCCC',
                    vscLeftDark = '#181818', vscPopupBack = '#202020',
                    vscLineNumber = '#6E7681',
                },
                group_overrides = {
                    TuimAccent = { fg = '#0078D4' },
                    WinSeparator = { fg = '#2B2B2B' },
                },
            })
            vscode.load('dark')
        else
            vim.cmd('highlight clear')
            vim.g.colors_name = 'vscode'
            local groups = {
                Normal = { fg = '#CCCCCC', bg = '#1F1F1F' },
                NormalNC = { fg = '#CCCCCC', bg = '#181818' },
                LineNr = { fg = '#6E7681' }, CursorLineNr = { fg = '#CCCCCC' },
                SignColumn = { bg = '#1F1F1F' }, EndOfBuffer = { fg = '#1F1F1F' },
                WinSeparator = { fg = '#2B2B2B' }, TuimAccent = { fg = '#0078D4' },
                Visual = { bg = '#264F78' }, Search = { bg = '#9E6A03' },
                Pmenu = { fg = '#CCCCCC', bg = '#202020' }, PmenuSel = { bg = '#04395E' },
                Comment = { fg = '#6A9955' }, String = { fg = '#CE9178' },
                Character = { fg = '#CE9178' }, Number = { fg = '#B5CEA8' },
                Boolean = { fg = '#569CD6' }, Float = { fg = '#B5CEA8' },
                Identifier = { fg = '#9CDCFE' }, Function = { fg = '#DCDCAA' },
                Statement = { fg = '#C586C0' }, Keyword = { fg = '#569CD6' },
                PreProc = { fg = '#C586C0' }, Type = { fg = '#4EC9B0' },
                Special = { fg = '#D7BA7D' }, Constant = { fg = '#4FC1FF' },
                Operator = { fg = '#D4D4D4' }, Delimiter = { fg = '#CCCCCC' },
                DiagnosticError = { fg = '#F85149' }, DiagnosticWarn = { fg = '#CCA700' },
                DiagnosticInfo = { fg = '#3794FF' }, DiagnosticHint = { fg = '#4EC9B0' },
            }
            for name, attrs in pairs(groups) do vim.api.nvim_set_hl(0, name, attrs) end
            for capture, group in pairs({
                comment = 'Comment', string = 'String', number = 'Number', boolean = 'Boolean',
                variable = 'Identifier', ['variable.member'] = 'Identifier',
                ['function'] = 'Function', ['function.call'] = 'Function',
                ['function.method'] = 'Function', ['function.builtin'] = 'Function',
                keyword = 'Keyword', ['keyword.return'] = 'Statement',
                ['keyword.conditional'] = 'Statement', ['keyword.repeat'] = 'Statement',
                type = 'Type', ['type.builtin'] = 'Type', constant = 'Constant',
                operator = 'Operator', ['punctuation.bracket'] = 'Delimiter',
            }) do vim.api.nvim_set_hl(0, '@' .. capture, { link = group }) end
            vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'vscode', modeline = false })
        end
    end
    _G.tuim_apply_theme = function(name)
        if name ~= 'system' then
            stop()
            if name == 'vscode' then return dark_modern() end
            return vim.cmd.colorscheme(name)
        end
        if not enabled then
            enabled = true
            refresh()
            if not signature then
                applying = true
                vim.cmd.colorscheme('default')
                vim.g.colors_name = 'system'
                vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'system', modeline = false })
                applying = false
                _G.tuim_native_notice('warning', 'System palette unavailable; using default colors until a desktop palette is available.')
            end
            timer = vim.uv.new_timer()
            timer:start(1500, 1500, vim.schedule_wrap(refresh))
        else
            refresh()
        end
    end
    local group = vim.api.nvim_create_augroup('TuimSystemTheme', { clear = true })
    vim.api.nvim_create_autocmd('FileType', { group = group, callback = function(event) system_highlight(event.buf) end })
    vim.api.nvim_create_autocmd({ 'FocusGained', 'VimResume' }, { group = group, callback = refresh })
    vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = function()
        if not applying and vim.g.colors_name ~= 'system' then stop() end
    end })
    vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = stop })
end

_G.tuim_save_settings = function()
    local state = {}
    local path = vim.fn.stdpath("data") .. "/settings.json"
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, s = pcall(vim.fn.json_decode, content)
        if ok and type(s) == "table" then
            state = s
        end
    end
    local mode = "normal"
    if vim.g.tuim_zen_mode then
        mode = "zen"
    elseif vim.g.tuim_ide_mode then
        mode = "ide"
    end
    state.mode = mode
    state.zen = (mode == "zen")
    state.ide = (mode == "ide")
    state.clip = vim.o.clipboard:match("unnamedplus") ~= nil
    state.theme = vim.g.colors_name or "vscode"
    state.autocomplete = vim.g.tuim_autocomplete_enabled ~= false
    state.autoindent = vim.o.autoindent
    state.nerd_fonts = vim.g.tuim_nerd_fonts ~= false
    state.zen_handoff = vim.g.tuim_zen_handoff == true
    local f_w = io.open(path, "w")
    if f_w then f_w:write(vim.fn.json_encode(state)); f_w:close() end
end

local tuim_colorcolumn = ""
local function apply_colorcolumn_to_window(win)
    if not vim.api.nvim_win_is_valid(win) then return end
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.bo[buf].buftype
    local filetype = vim.bo[buf].filetype
    local excluded = buftype ~= "" or filetype == "dashboard" or filetype == "alpha"
        or filetype == "help" or filetype == "tuim-settings"
    vim.wo[win].colorcolumn = excluded and "" or tuim_colorcolumn
end

_G.tuim_apply_colorcolumn = function(value)
    local allowed = { [""] = true, ["80"] = true, ["100"] = true,
        ["120"] = true, ["80,120"] = true }
    tuim_colorcolumn = allowed[value] and value or ""
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        apply_colorcolumn_to_window(win)
    end
end

local colorcolumn_group = vim.api.nvim_create_augroup("TuimColorColumn", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = colorcolumn_group,
    callback = function(args)
        for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
            apply_colorcolumn_to_window(win)
        end
    end,
})

_G.tuim_load_settings = function()
    local f = io.open(vim.fn.stdpath("data") .. "/settings.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, state = pcall(vim.fn.json_decode, content)
        if ok and type(state) == "table" then
            local mode = "normal"
            if state.mode ~= nil then
                mode = state.mode
            elseif state.zen then
                mode = "zen"
            elseif state.ide then
                mode = "ide"
            end
            
            if mode == "zen" then
                vim.g.tuim_zen_mode = true
                vim.g.tuim_ide_mode = false
            elseif mode == "ide" then
                vim.g.tuim_zen_mode = false
                vim.g.tuim_ide_mode = true
                vim.schedule(_G.tuim_enable_ide_mode)
            else
                vim.g.tuim_zen_mode = false
                vim.g.tuim_ide_mode = false
                vim.schedule(_G.tuim_disable_ide_mode)
            end
            
            if state.clip ~= nil then
                vim.o.clipboard = state.clip and "unnamedplus" or ""
            end
            if state.autocomplete ~= nil then
                vim.g.tuim_autocomplete_enabled = state.autocomplete
            else
                vim.g.tuim_autocomplete_enabled = true
            end
            local term = os.getenv("TERM") or ""
            if state.nerd_fonts ~= nil then
                vim.g.tuim_nerd_fonts = state.nerd_fonts
            else
                vim.g.tuim_nerd_fonts = true
            end
            if term == "linux" then
                vim.g.tuim_nerd_fonts = false
            end
            if state.autoindent ~= nil then
                vim.o.autoindent = state.autoindent
            else
                vim.o.autoindent = true
            end
            if state.zen_handoff ~= nil then
                vim.g.tuim_zen_handoff = state.zen_handoff
            else
                vim.g.tuim_zen_handoff = false
            end
            if _G.tuim_apply_colorcolumn then
                _G.tuim_apply_colorcolumn(state.colorcolumn or "")
            end
            if state.theme then
                vim.schedule(function()
                    if not pcall(_G.tuim_apply_theme, state.theme) then
                        pcall(_G.tuim_apply_theme, "vscode")
                    end
                end)
            end
        end
    end
end

local M = {}
local themes = { "system", "vscode", "matteblack", "tokyonight", "tokyonight-storm", "catppuccin", "gruvbox", "nord", "cyberdream", "rose-pine", "kanagawa", "nightfox" }
function M.open()
    if vim.g.tuim_zen_mode == nil then vim.g.tuim_zen_mode = false end
    if vim.g.tuim_ide_mode == nil then vim.g.tuim_ide_mode = false end
    if vim.g.tuim_autocomplete_enabled == nil then vim.g.tuim_autocomplete_enabled = true end
    if vim.g.tuim_zen_handoff == nil then vim.g.tuim_zen_handoff = false end
    local nerd_fonts = vim.g.tuim_nerd_fonts ~= false
    local function get_toggle(is_on)
        if nerd_fonts then
            return is_on and " " or " "
        else
            return is_on and "[x] " or "[ ] "
        end
    end
    local current_theme = vim.g.colors_name or "vscode"
    
    local is_zen = vim.g.tuim_zen_mode == true
    local is_ide = vim.g.tuim_ide_mode == true
    local is_normal = not is_zen and not is_ide

    local width = 45
    local lines = { 
        string.rep(" ", width - 4) .. (nerd_fonts and "󰅖 " or "x "),
        "  General Settings",
        "  " .. get_toggle(is_zen) .. " Zen Mode                      [z]", 
        "  " .. get_toggle(is_ide) .. " IDE Mode                      [i]", 
        "  " .. get_toggle(is_normal) .. " Normal Mode                   [o]",
        "  " .. get_toggle(vim.g.tuim_zen_handoff) .. " Zen Handoff (Native Nvim)     [h]",
        "  " .. get_toggle(vim.o.clipboard:match("unnamedplus")) .. " System Clipboard              [c]",
        "  " .. get_toggle(vim.g.tuim_autocomplete_enabled) .. " Autocomplete                 [a]",
        "  " .. get_toggle(vim.o.autoindent) .. " Autoindent                   [n]",
        "", 
        "  Themes",
    }
    for _, t in ipairs(themes) do 
        table.insert(lines, "  " .. get_toggle(t == current_theme) .. " " .. t .. string.rep(" ", 30 - #t) .. "[t]") 
    end

    local height = #lines + 2
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor', width = width, height = height,
        row = math.floor((vim.o.lines - height) / 2), col = math.floor((vim.o.columns - width) / 2),
        style = 'minimal', border = 'rounded', title = ' Tuim Settings ', title_pos = 'center',
    })
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.cmd("stopinsert")
    
    local function select_mode(mode)
        if mode == "zen" then
            vim.g.tuim_zen_mode = true
            vim.g.tuim_ide_mode = false
            _G.tuim_disable_ide_mode()
            vim.rpcnotify(1, "tuim_toggle_zen")
        elseif mode == "ide" then
            vim.g.tuim_zen_mode = false
            vim.g.tuim_ide_mode = true
            _G.tuim_enable_ide_mode()
            vim.rpcnotify(1, "tuim_toggle_ide")
        elseif mode == "normal" then
            vim.g.tuim_zen_mode = false
            vim.g.tuim_ide_mode = false
            _G.tuim_disable_ide_mode()
            vim.rpcnotify(1, "tuim_settings_changed")
        end
        if _G.tuim_save_settings then _G.tuim_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        if mode ~= "zen" then
            require('tuim_settings').open()
        end
    end
    
    local function toggle_clipboard()
        if vim.o.clipboard:match("unnamedplus") then
            vim.o.clipboard = ""
            print("System Clipboard: OFF")
        else
            vim.o.clipboard = "unnamedplus"
            print("System Clipboard: ON")
        end
        if _G.tuim_save_settings then _G.tuim_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        require('tuim_settings').open()
    end

    local function toggle_autocomplete()
        vim.g.tuim_autocomplete_enabled = not vim.g.tuim_autocomplete_enabled
        if _G.tuim_save_settings then _G.tuim_save_settings() end
        vim.rpcnotify(1, "tuim_settings_changed")
        pcall(vim.api.nvim_win_close, win, true)
        require('tuim_settings').open()
    end

    local function toggle_autoindent()
        vim.o.autoindent = not vim.o.autoindent
        if _G.tuim_save_settings then _G.tuim_save_settings() end
        vim.rpcnotify(1, "tuim_settings_changed")
        pcall(vim.api.nvim_win_close, win, true)
        require('tuim_settings').open()
    end
    
    local function toggle_zen_handoff()
        vim.g.tuim_zen_handoff = not vim.g.tuim_zen_handoff
        if _G.tuim_save_settings then _G.tuim_save_settings() end
        vim.rpcnotify(1, "tuim_settings_changed")
        pcall(vim.api.nvim_win_close, win, true)
        require('tuim_settings').open()
    end
    
    local function set_theme()
        local theme = vim.api.nvim_get_current_line():match("([%w%-]+)%s+%[t%]")
        if theme then 
            _G.tuim_apply_theme(theme)
            if _G.tuim_save_settings then _G.tuim_save_settings() end
            pcall(vim.api.nvim_win_close, win, true)
            require('tuim_settings').open()
        end
    end

    local function handle_click()
        local line = vim.api.nvim_get_current_line()
        if line:match("󰅖") or line:match("x ") or line:match("%[x%]") or vim.api.nvim_win_get_cursor(win)[1] == 1 then pcall(vim.api.nvim_win_close, win, true)
        elseif line:match("Zen Mode") then select_mode("zen")
        elseif line:match("IDE Mode") then select_mode("ide")
        elseif line:match("Normal Mode") then select_mode("normal")
        elseif line:match("Zen Handoff") then toggle_zen_handoff()
        elseif line:match("System Clipboard") then toggle_clipboard()
        elseif line:match("Autocomplete") then toggle_autocomplete()
        elseif line:match("Autoindent") then toggle_autoindent()
        else set_theme() end
    end

    local function do_click()
        vim.cmd("stopinsert")
        handle_click()
    end

    vim.keymap.set({'n', 'v', 'i'}, 'z', function() select_mode("zen") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'i', function() select_mode("ide") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'o', function() select_mode("normal") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'h', toggle_zen_handoff, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'c', toggle_clipboard, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'a', toggle_autocomplete, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'n', toggle_autoindent, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 't', set_theme, { buffer = buf, silent = true })
    
    vim.keymap.set({'n', 'v', 'i'}, '<LeftMouse>', function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "ntx", false)
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<LeftRelease>', function()
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<2-LeftMouse>', function()
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<CR>', do_click, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'q', function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<Esc>', function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
end

function M.sync_theme()
    local function get_color(group, attr)
        local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
        if ok and hl[attr] then return string.format("#%06x", hl[attr]) end
        return nil
    end
    local function adjust_color(hex, amount)
        if type(hex) ~= "string" or #hex ~= 7 then return hex end
        local r = tonumber(hex:sub(2, 3), 16) or 0
        local g = tonumber(hex:sub(4, 5), 16) or 0
        local b = tonumber(hex:sub(6, 7), 16) or 0
        r = math.max(0, math.min(255, r + amount))
        g = math.max(0, math.min(255, g + amount))
        b = math.max(0, math.min(255, b + amount))
        return string.format("#%02x%02x%02x", r, g, b)
    end
    local function get_contrast(hex, level)
        if type(hex) ~= "string" or #hex ~= 7 then return hex end
        local r = tonumber(hex:sub(2, 3), 16) or 0
        local g = tonumber(hex:sub(4, 5), 16) or 0
        local b = tonumber(hex:sub(6, 7), 16) or 0
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        return adjust_color(hex, brightness > 128 and -level or level)
    end

    local bg_editor = get_color("Normal", "bg") or "#1e1e1e"
    local fg_primary = get_color("Normal", "fg") or "#d4d4d4"
    local fg_secondary = get_color("Comment", "fg") or "#858585"
    local border_color = get_color("WinSeparator", "fg") or get_color("VertSplit", "fg") or "#3c3c3c"
    
    local bg_sidebar = get_color("NeoTreeNormal", "bg") or get_color("NvimTreeNormal", "bg") or get_color("NormalNC", "bg")
    if not bg_sidebar or bg_sidebar == bg_editor then
        bg_sidebar = get_contrast(bg_editor, 8)
    end
    
    local bg_tab_inactive = get_color("TabLine", "bg") or border_color
    if not bg_tab_inactive or bg_tab_inactive == bg_editor or bg_tab_inactive == border_color then
        bg_tab_inactive = get_contrast(bg_editor, 15)
    end
    
    local bg_accent = get_color("TuimAccent", "fg") or get_color("Function", "fg") or get_color("Statement", "fg") or "#007acc"

    -- Some colorschemes make Visual indistinguishable from Normal once Tuim
    -- normalizes editor backgrounds. Keep mouse and keyboard selections clear.
    local system = vim.g.colors_name == 'system' and _G.tuim_system_palette or nil
    local selection_bg = system and system.selection_background or (vim.g.colors_name == "vscode" and "#264f78") or get_contrast(bg_editor, 36) or "#264f78"
    local selection_fg = system and system.selection_foreground or nil
    if not _G.tuim_system_colorscheme then
        vim.api.nvim_set_hl(0, "Visual", { fg = selection_fg, bg = selection_bg, bold = true })
        vim.api.nvim_set_hl(0, "VisualNOS", { fg = selection_fg, bg = selection_bg, bold = true })
    end
    
    local fg_statusbar = "#ffffff"
    do
        local r = tonumber(bg_accent:sub(2, 3), 16) or 0
        local g = tonumber(bg_accent:sub(4, 5), 16) or 0
        local b = tonumber(bg_accent:sub(6, 7), 16) or 0
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        if brightness > 128 then
            fg_statusbar = "#1e1e1e"
        end
    end

    -- Set terminal colors for the terminal panel so bash prompt ~ > is legible
    local bg_terminal = bg_editor
    
    vim.g.terminal_color_0  = get_color("Normal", "bg") or "#1e1e1e"
    vim.g.terminal_color_1  = get_color("Error", "fg") or "#f2495a"
    vim.g.terminal_color_2  = get_color("String", "fg") or "#42be65"
    vim.g.terminal_color_3  = get_color("WarningMsg", "fg") or "#ffcc00"
    vim.g.terminal_color_4  = get_color("Function", "fg") or "#007acc"
    vim.g.terminal_color_5  = get_color("Statement", "fg") or "#c678dd"
    vim.g.terminal_color_6  = get_color("Special", "fg") or "#56b6c2"
    vim.g.terminal_color_7  = get_color("Normal", "fg") or "#d4d4d4"
    vim.g.terminal_color_8  = get_color("Comment", "fg") or "#858585"
    vim.g.terminal_color_9  = get_color("Error", "fg") or "#f2495a"
    vim.g.terminal_color_10 = get_color("String", "fg") or "#42be65"
    vim.g.terminal_color_11 = get_color("WarningMsg", "fg") or "#ffcc00"
    vim.g.terminal_color_12 = get_color("Function", "fg") or "#007acc"
    vim.g.terminal_color_13 = get_color("Statement", "fg") or "#c678dd"
    vim.g.terminal_color_14 = get_color("Special", "fg") or "#56b6c2"
    vim.g.terminal_color_15 = "#ffffff"

    if system then
        for i, color in ipairs(system.terminal_colors) do vim.g['terminal_color_' .. (i - 1)] = color end
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == "terminal" then
            for i = 0, 15 do
                vim.api.nvim_buf_set_var(buf, "terminal_color_" .. i, vim.g["terminal_color_" .. i])
            end
            -- Force redraw in terminal buffer by briefly switching to it (optional but ensures update)
        end
    end

    vim.api.nvim_set_hl(0, "NormalFloat", { fg = fg_primary, bg = bg_sidebar })
    vim.api.nvim_set_hl(0, "FloatBorder", { fg = border_color, bg = bg_sidebar })

    pcall(vim.rpcnotify, 1, "tuim_theme_changed", {
        bg_editor = bg_editor, bg_sidebar = bg_sidebar, bg_tab_active = bg_editor,
        bg_tab_inactive = bg_tab_inactive, bg_statusbar = bg_accent, fg_statusbar = fg_statusbar, bg_accent = bg_accent,
        fg_primary = fg_primary, fg_secondary = fg_secondary, fg_accent = fg_primary, border_color = border_color,
        bg_terminal = bg_terminal,
    })
end

package.loaded["tuim_settings"] = M

vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
        if vim.g.colors_name == "matteblack" then
            local highlights = {
                Normal = { fg = "#dcdcdc", bg = "#080808" },
                NormalNC = { fg = "#777777", bg = "#080808" },
                Comment = { fg = "#4a4a4a", italic = true },
                Constant = { fg = "#ffaa66" },
                String = { fg = "#b8b8b8" },
                Character = { fg = "#b8b8b8" },
                Number = { fg = "#ffb86c" },
                Boolean = { fg = "#ffb86c" },
                Float = { fg = "#ffb86c" },
                Identifier = { fg = "#dcdcdc" },
                Function = { fg = "#eeeeee" },
                Statement = { fg = "#ff7300", bold = true },
                Conditional = { fg = "#ff7300", bold = true },
                Repeat = { fg = "#ff7300", bold = true },
                Label = { fg = "#ff7300", bold = true },
                Operator = { fg = "#a0a0a0" },
                Keyword = { fg = "#ff7300", bold = true },
                Exception = { fg = "#ff3333", bold = true },
                PreProc = { fg = "#888888" },
                Type = { fg = "#ffffff", bold = true },
                StorageClass = { fg = "#ffffff", bold = true },
                Structure = { fg = "#ffffff", bold = true },
                Typedef = { fg = "#ffffff", bold = true },
                Special = { fg = "#ffaa66" },
                Underlined = { underline = true },
                Error = { fg = "#ff3333", bg = "NONE", bold = true },
                Todo = { fg = "#080808", bg = "#ff7300", bold = true },
                
                CursorLine = { bg = "#141414" },
                CursorColumn = { bg = "#141414" },
                LineNr = { fg = "#3a3a3a", bg = "#080808" },
                CursorLineNr = { fg = "#ff7300", bg = "#141414", bold = true },
                SignColumn = { bg = "#080808" },
                FoldColumn = { bg = "#080808" },
                Folded = { fg = "#666666", bg = "#141414" },
                WinSeparator = { fg = "#1a1a1a", bg = "#080808" },
                VertSplit = { fg = "#1a1a1a", bg = "#080808" },
                
                Visual = { bg = "#2d1b0d" },
                Search = { fg = "#080808", bg = "#ff7300" },
                IncSearch = { fg = "#080808", bg = "#ffaa66" },
                
                Pmenu = { fg = "#dcdcdc", bg = "#141414" },
                PmenuSel = { fg = "#080808", bg = "#ff7300" },
                PmenuSbar = { bg = "#1a1a1a" },
                PmenuThumb = { bg = "#333333" },
                
                StatusLine = { fg = "#080808", bg = "#ff7300" },
                StatusLineNC = { fg = "#777777", bg = "#141414" },
                TabLine = { fg = "#777777", bg = "#141414" },
                TabLineSel = { fg = "#ff7300", bg = "#080808", bold = true },
                TabLineFill = { bg = "#141414" },
                
                ["@comment"] = { fg = "#4a4a4a", italic = true },
                ["@function"] = { fg = "#eeeeee" },
                ["@keyword"] = { fg = "#ff7300", bold = true },
                ["@string"] = { fg = "#b8b8b8" },
                ["@type"] = { fg = "#ffffff", bold = true },
                ["@variable"] = { fg = "#dcdcdc" },

                NeoTreeNormal = { fg = "#777777", bg = "#0c0c0c" },
                NeoTreeNormalNC = { fg = "#777777", bg = "#0c0c0c" },
                NeoTreeWinSeparator = { fg = "#1a1a1a", bg = "#0c0c0c" },

                TuimAccent = { fg = "#ff7300" },
            }
            for group, opts in pairs(highlights) do
                vim.api.nvim_set_hl(0, group, opts)
            end
        end
        require("tuim_settings").sync_theme()
    end,
})
vim.schedule(function() pcall(function() require("tuim_settings").sync_theme() end) end)

-- Apply the built-in default even when there is no saved settings file.
_G.tuim_apply_theme('vscode')
if _G.tuim_load_settings then _G.tuim_load_settings() end

-- Global function to restart dashboard when tabs close
_G.tuim_alpha_start = function()
    if vim.fn.exists(':Alpha') == 2 then
        vim.cmd("Alpha")
        return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'tuim_dashboard'
    local lines = {
        '', '  tuim / ' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t'), '',
        '  New file          Ctrl+N',
        '  Find file         Ctrl+F', '',
        '  Commands          F1',
        '  Quit              Ctrl+Q',
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_buf(0, buf)
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = 'no'
    vim.wo.colorcolumn = ''
end

-- Force dashboard on initial empty load
if vim.fn.argc() == 0 and not vim.g.tuim_is_terminal then
    vim.schedule(function()
        _G.tuim_alpha_start()
    end)
end

-- Nmux42 Bindings
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "Toggle Neo-tree" })
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]])
vim.keymap.set("i", "<C-c>", "<Esc>")
vim.keymap.set("n", "<C-j>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-k>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "Q", "<nop>")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")
vim.keymap.set("n", "<leader>cc", "<cmd>!php-cs-fixer fix % --using-cache=no<cr>")
vim.keymap.set("n", "<leader>s", [[:s/\<<C-r><C-w>\>//gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
vim.keymap.set('n', '<leader>y', '<Plug>OSCYankOperator')
vim.keymap.set('v', '<leader>y', '<Plug>OSCYankVisual')
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)
vim.keymap.set("n", "<leader>cl", ":cclose<CR>", { silent = true })
vim.keymap.set("n", "<leader>co", ":copen<CR>", { silent = true })
vim.keymap.set("n", "<leader>cn", ":cnext<CR>zz")
vim.keymap.set("n", "<leader>cp", ":cprev<CR>zz")
vim.keymap.set("n", "<leader>mm", "<cmd>make<CR>")
vim.keymap.set("n", "<leader><leader>", function() vim.cmd("so") end)

local function toggle_terminal(direction)
    local term_win = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "terminal" then
            term_win = win
            break
        end
    end
    if term_win then
        pcall(vim.api.nvim_win_close, term_win, true)
    else
        local term_buf = nil
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[buf].buftype == "terminal" then
                local job_id = vim.b[buf].terminal_job_id
                if job_id and vim.fn.jobwait({job_id}, 0)[1] == -2 then
                    local visible = false
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        if vim.api.nvim_win_get_buf(win) == buf then
                            visible = true
                            break
                        end
                    end
                    if not visible then
                        term_buf = buf
                        break
                    end
                end
            end
        end
        if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
            if direction == "bo" then vim.cmd("botright sbuf " .. term_buf) else vim.cmd("vert sbuf " .. term_buf) end
        else
            if direction == "bo" then vim.cmd("bo term") else vim.cmd("vert term") end
        end
        vim.cmd("startinsert")
    end
end
vim.keymap.set("n", "<leader>ot", function() toggle_terminal("bo") end, { desc = "Toggle bottom terminal" })
vim.keymap.set("n", "<leader>oT", function() toggle_terminal("vert") end, { desc = "Toggle vertical terminal" })
vim.keymap.set("n", "<leader>db", _G.tuim_alpha_start, { desc = "Go back to dashboard menu" })

vim.keymap.set("n", "<leader>th", "<cmd>lua require('tuim_settings').open()<cr>")

pcall(dofile, vim.fn.expand("~/.config/nmux42/plugin/vim_bindings.lua"))

local telescope_timer = nil
local prev_mt_rect = vim.NIL
local prev_pr_rect = vim.NIL
local prev_widget_title = vim.NIL

local function rects_eq(r1, r2)
    if r1 == vim.NIL and r2 == vim.NIL then return true end
    if r1 == vim.NIL or r2 == vim.NIL then return false end
    if type(r1) ~= "table" or type(r2) ~= "table" then return r1 == r2 end
    return r1[1] == r2[1] and r1[2] == r2[2] and r1[3] == r2[3] and r1[4] == r2[4]
end

local function notify_telescope()
    pcall(function()
        local mt_top, mt_left, mt_bottom, mt_right = 9999, 9999, -1, -1
        local pr_top, pr_left, pr_bottom, pr_right = 9999, 9999, -1, -1
        local found_mt = false
        local found_pr = false
        local widget_title = nil

        local has_telescope, action_state = pcall(require, "telescope.actions.state")
        local picker = nil
        if has_telescope and action_state then
            for _, w in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_is_valid(w) then
                    local buf = vim.api.nvim_win_get_buf(w)
                    if buf and vim.api.nvim_buf_is_valid(buf) then
                        local ok_ft, ft = pcall(function() return vim.bo[buf].filetype end)
                        if ok_ft and ft == "TelescopePrompt" then
                            local ok_picker, p = pcall(action_state.get_current_picker, buf)
                            if ok_picker and p then
                                picker = p
                                break
                            end
                        end
                    end
                end
            end
        end

        if picker then
            local prompt_win = picker.prompt_win
            local results_win = picker.results_win
            local preview_win = picker.preview_win or (picker.previewer and picker.previewer.state and picker.previewer.state.winid)

            for _, w in ipairs({ prompt_win, results_win }) do
                if w and vim.api.nvim_win_is_valid(w) then
                    local cfg = vim.api.nvim_win_get_config(w)
                    if cfg and cfg.relative ~= "" then
                        local r = math.floor(cfg.row or 0)
                        local c = math.floor(cfg.col or 0)
                        local h = math.floor(cfg.height or 0)
                        local w_w = math.floor(cfg.width or 0)
                        
                        if r < 0 then r = 0 end
                        if c < 0 then c = 0 end

                        found_mt = true
                        widget_title = picker.prompt_title or "Search"
                        if r < mt_top then mt_top = r end
                        if c < mt_left then mt_left = c end
                        if r + h > mt_bottom then mt_bottom = r + h end
                        if c + w_w > mt_right then mt_right = c + w_w end
                    end
                end
            end

            if preview_win and vim.api.nvim_win_is_valid(preview_win) then
                local cfg = vim.api.nvim_win_get_config(preview_win)
                if cfg and cfg.relative ~= "" then
                    local r = math.floor(cfg.row or 0)
                    local c = math.floor(cfg.col or 0)
                    local h = math.floor(cfg.height or 0)
                    local w_w = math.floor(cfg.width or 0)
                    
                    if r < 0 then r = 0 end
                    if c < 0 then c = 0 end

                    found_pr = true
                    if r < pr_top then pr_top = r end
                    if c < pr_left then pr_left = c end
                    if r + h > pr_bottom then pr_bottom = r + h end
                    if c + w_w > pr_right then pr_right = c + w_w end
                end
            end
        end

        local mt_rect = found_mt and { mt_top, mt_left, mt_right - mt_left, mt_bottom - mt_top } or vim.NIL
        local pr_rect = found_pr and { pr_top, pr_left, pr_right - pr_left, pr_bottom - pr_top } or vim.NIL

        if not found_mt then
            for _, w in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_is_valid(w) then
                    local buf = vim.api.nvim_win_get_buf(w)
                    if buf and vim.api.nvim_buf_is_valid(buf) then
                        local ok_ft, ft = pcall(function() return vim.bo[buf].filetype end)
                        if ok_ft and ft == "vimbindings" and (not vim.g.tuim_zen_mode) then
                            local cfg = vim.api.nvim_win_get_config(w)
                            if cfg and cfg.relative ~= "" then
                                local r = math.floor(cfg.row or 0)
                                local c = math.floor(cfg.col or 0)
                                local h = math.floor(cfg.height or 0)
                                local w_w = math.floor(cfg.width or 0)
                                if r < 0 then r = 0 end
                                if c < 0 then c = 0 end
                                found_mt = true
                                widget_title = " Tuim Help Reference "
                                mt_rect = { r, c, w_w, h }
                            end
                            break
                        end
                    end
                end
            end
        end

        if found_mt or found_pr then
            if not telescope_timer then
                telescope_timer = vim.uv.new_timer()
                telescope_timer:start(50, 50, vim.schedule_wrap(notify_telescope))
            end
            if not rects_eq(mt_rect, prev_mt_rect) or not rects_eq(pr_rect, prev_pr_rect) or widget_title ~= prev_widget_title then
                vim.rpcnotify(1, "tuim_telescope_rect", mt_rect, pr_rect, widget_title, picker ~= nil)
                prev_mt_rect = mt_rect
                prev_pr_rect = pr_rect
                prev_widget_title = widget_title
            end
        else
            if telescope_timer then
                telescope_timer:stop()
                telescope_timer:close()
                telescope_timer = nil
            end
            if prev_mt_rect ~= vim.NIL or prev_pr_rect ~= vim.NIL then
                vim.rpcnotify(1, "tuim_telescope_rect", vim.NIL, vim.NIL, vim.NIL)
                prev_mt_rect = vim.NIL
                prev_pr_rect = vim.NIL
                prev_widget_title = vim.NIL
            end
        end
    end)
end

local function notify_win_positions()
    local win_list = {}
    local cur_win = vim.api.nvim_get_current_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) then
            local cfg = vim.api.nvim_win_get_config(w)
            if cfg.relative == "" then
                local pos = vim.api.nvim_win_get_position(w) -- [row, col]
                local width = vim.api.nvim_win_get_width(w)
                local height = vim.api.nvim_win_get_height(w)
                local buf = vim.api.nvim_win_get_buf(w)
                local buf_name = vim.api.nvim_buf_get_name(buf)
                local short_name = vim.fn.fnamemodify(buf_name, ":t")
                if short_name == "" then short_name = "[No Name]" end
                table.insert(win_list, {
                    id = w,
                    bufnr = buf,
                    row = pos[1],
                    col = pos[2],
                    width = width,
                    height = height,
                    active = (w == cur_win),
                    name = short_name
                })
            end
        end
    end
    vim.rpcnotify(1, "tuim_win_positions", win_list)
end

vim.api.nvim_create_autocmd({"WinNew", "WinClosed", "WinEnter", "WinLeave", "BufEnter", "BufWinEnter", "BufFilePost"}, {
    callback = function()
        vim.schedule(notify_telescope)
        vim.schedule(notify_win_positions)
    end
})
vim.schedule(notify_win_positions)

_G.tuim_wincmd = function(dir)
    local current_win = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. dir)
    if vim.api.nvim_get_current_win() == current_win then
        vim.rpcnotify(1, "tuim_boundary_hit", dir)
    end
end

vim.keymap.set({'i', 'n', 'v', 't'}, '<M-h>', function() _G.tuim_wincmd('h') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-j>', function() _G.tuim_wincmd('j') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-k>', function() _G.tuim_wincmd('k') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-l>', function() _G.tuim_wincmd('l') end, { silent = true })

vim.keymap.set({'i', 'n', 'v', 't'}, '<M-v>', function() vim.cmd("vsplit") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-s>', function() vim.cmd("split") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-c>', function() vim.cmd("close") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-o>', function() vim.cmd("wincmd w") end, { silent = true })

vim.schedule(function() pcall(notify_win_positions) end)

-- Native auto-pairs implementation
local autopairs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
    ['"'] = '"',
    ["'"] = "'",
    ['`'] = '`',
}

for open_char, close_char in pairs(autopairs) do
    vim.keymap.set('i', open_char, function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        local next_char = line:sub(col + 1, col + 1)
        if open_char == close_char and next_char == close_char then
            return "<Right>"
        else
            return open_char .. close_char .. "<Left>"
        end
    end, { expr = true, replace_keycodes = true })
end

local closers = { ')', ']', '}', '"', "'", '`' }
for _, close_char in ipairs(closers) do
    vim.keymap.set('i', close_char, function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        local next_char = line:sub(col + 1, col + 1)
        if next_char == close_char then
            return "<Right>"
        else
            return close_char
        end
    end, { expr = true, replace_keycodes = true })
end

vim.keymap.set('i', '<BS>', function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local prev_char = line:sub(col, col)
    local next_char = line:sub(col + 1, col + 1)
    if autopairs[prev_char] == next_char then
        return "<BS><Del>"
    else
        return "<BS>"
    end
end, { expr = true, replace_keycodes = true })

-- --- TUIM HELP WIDGET --- --
local VIM_MOTIONS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │               ⚡  VIM MOTIONS REFERENCE CARD                │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "",
    "  ── MODES ──────────────────────────────────────────────────────",
    "  i / I      Insert mode (before cursor / at line start)",
    "  a / A      Append mode (after cursor / at line end)",
    "  o / O      Open new line below / above and insert",
    "  v / V      Visual mode / Visual Line mode",
    "  <C-v>      Visual Block mode (column editing)",
    "  Esc        Return to Normal mode",
    "  R          Replace mode (overwrite text)",
    "",
    "  ── NAVIGATION ─────────────────────────────────────────────────",
    "  h j k l    Left / Down / Up / Right",
    "  w / W      Jump to next word start (word / WORD)",
    "  e / E      Jump to next word end   (word / WORD)",
    "  b / B      Jump back word start    (word / WORD)",
    "  0 / ^      Start of line / First non-blank char",
    "  $          End of line",
    "  gg / G     First line / Last line of file",
    "  {N}G       Jump to line N (e.g. 42G)",
    "  <C-d>      Scroll down half a page (cursor stays centered)",
    "  <C-u>      Scroll up half a page   (cursor stays centered)",
    "  <C-f>/<C-b>  Scroll full page down / up",
    "  %          Jump to matching bracket/paren/brace",
    "  *          Search forward for word under cursor",
    "  #          Search backward for word under cursor",
    "  n / N      Next / Previous search match",
    "  ''         Jump back to previous position",
    "  zz         Center screen on cursor",
    "  zt / zb    Scroll so cursor is at Top / Bottom",
    "",
    "  ── TEXT OBJECTS ────────────────────────────────────────────────",
    "  iw / aw    Inner word / A word (incl. surrounding space)",
    "  i\" / a\"    Inside quotes / Including quotes",
    "  i( / a(    Inside parens / Including parens",
    "  i{ / a{    Inside braces / Including braces",
    "  i[ / a[    Inside brackets / Including brackets",
    "  it / at    Inside tag / Including tag (HTML/XML)",
    "  ip / ap    Inner paragraph / A paragraph",
    "  is / as    Inner sentence / A sentence",
    "",
    "  ── OPERATORS (combine with motion or text object) ───────────────",
    "  d{motion}  Delete  (e.g. dw, d$, dip, d3j)",
    "  c{motion}  Change  (delete + insert mode)",
    "  y{motion}  Yank    (copy)",
    "  >{motion}  Indent right",
    "  <{motion}  Indent left",
    "  ={motion}  Auto-indent",
    "  gU{motion} Uppercase",
    "  gu{motion} Lowercase",
    "  g~{motion} Toggle case",
    "",
    "  ── EDITING SHORTCUTS ───────────────────────────────────────────",
    "  x / X      Delete char under cursor / before cursor",
    "  s / S      Substitute char / whole line",
    "  dd / D     Delete line / Delete to end of line",
    "  yy / Y     Yank line / Yank to end of line",
    "  p / P      Paste after cursor / before cursor",
    "  u          Undo",
    "  <C-r>      Redo",
    "  .          Repeat last change",
    "  J          Join line below to current line",
    "  r{char}    Replace single character with {char}",
    "  ~          Toggle case of character under cursor",
    "  >>  /  <<  Indent / Unindent current line",
    "  =G         Auto-indent from cursor to end of file",
    "",
    "  ── SEARCH & REPLACE ────────────────────────────────────────────",
    "  /pattern   Search forward  (n=next, N=prev)",
    "  ?pattern   Search backward",
    "  :%s/old/new/g      Replace all in file",
    "  :%s/old/new/gc     Replace all with confirmation",
    "  :s/old/new/g       Replace all in current line",
    "",
    "  ── MARKS & JUMPS ───────────────────────────────────────────────",
    "  m{a-z}     Set local mark  (m{A-Z} for global mark)",
    "  `{mark}    Jump to exact mark position",
    "  '{mark}    Jump to mark's line start",
    "  <C-o>      Jump to previous location in jump list",
    "  <C-i>      Jump to next location in jump list",
    "",
    "  ── MACROS ──────────────────────────────────────────────────────",
    "  q{a-z}     Start recording macro into register {a-z}",
    "  q          Stop recording macro",
    "  @{a-z}     Replay macro from register {a-z}",
    "  @@         Repeat last macro",
    "  {N}@{a-z}  Replay macro N times",
    "",
    "  ── WINDOWS & SPLITS ────────────────────────────────────────────",
    "  <C-w>s     Horizontal split",
    "  <C-w>v     Vertical split",
    "  <C-w>h/j/k/l   Move between splits",
    "  <C-w>q     Close current split",
    "  <C-w>=     Equalize all split sizes",
    "  <C-w>|     Maximize current split width",
    "  <C-w>_     Maximize current split height",
    "",
    "  ── COMMAND MODE ────────────────────────────────────────────────",
    "  :w         Save file",
    "  :q         Quit",
    "  :wq / :x   Save and quit",
    "  :q!        Quit without saving",
    "  :e {file}  Open file",
    "  :bn / :bp  Next / Previous buffer",
    "  :bd        Delete (close) buffer",
    "  :noh       Clear search highlight",
    "  :set nu    Toggle line numbers",
    "  :!{cmd}    Run shell command",
}

local TUIM_KEYS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │                ⚙  TUIM CUSTOM KEYBINDINGS                   │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "  Leader key = <Space>",
    "",
    "  ── TUIM & WORKSPACE ────────────────────────────────────────────",
    "  <Space> e              Toggle File Explorer",
    "  <Space> m t            Toggle IDE / Zen Mode",
    "  <Space> o t            Toggle Bottom Terminal Split",
    "  <Space> o T            Toggle Vertical Terminal Split",
    "  <C-w> s / <C-w> v      Horizontal / Vertical Editor Split",
    "  <C-w> h/j/k/l          Move Between Editor Splits",
    "  <C-w> q                Close Current Editor Split",
    "  <Space> ?              Show Tuim Quickstart Guide",
    "  :TuimOnboarding        Reopen the first-run guide",
    "  <Space> ,              Open Settings",
    "",
    "  ── TTY & KEYBOARD NAVIGATION ───────────────────────────────────",
    "  Ctrl+E                 Toggle and focus File Tree",
    "  Ctrl+T                 Toggle and focus Terminal panel",
    "  <Esc>                  Return focus to Editor from panels",
    "  Alt + Arrow Keys       Resize panels",
    "",
    "  ── TELESCOPE & SEARCH ──────────────────────────────────────────",
    "  <Space> <Space>        Telescope: Show All Commands",
    "  <Space> f f            Telescope: Find Files",
    "  <Space> f g / Alt+G    Telescope: Search Project (ripgrep)",
    "  <Space> f r            Telescope: Open Recent Files",
    "  Ctrl+F                 Telescope / Search",
    "",
    "  ── VSCODE-LIKE ESSENTIALS ──────────────────────────────────────",
    "  Ctrl+S                 Save file",
    "  Ctrl+Q                 Force quit Tuim",
    "  Ctrl+W                 Close current Tab/Buffer",
    "  Ctrl+N / Ctrl+T        Open new Tab/Buffer",
    "  Ctrl+Tab               Next Tab",
    "  Ctrl+Shift+Tab         Previous Tab",
    "  Ctrl+Z                 Undo",
    "  Ctrl+Y                 Redo",
    "  Ctrl+C                 Copy selection to system clipboard",
    "  Ctrl+X                 Cut selection to system clipboard",
    "  Ctrl+V                 Paste from system clipboard",
    "  Ctrl+A                 Select all text",
    "",
    "  ── PORTED NMUX42 KEYS ──────────────────────────────────────────",
    "  J / K (Visual)         Move selected lines down / up",
    "  J (Normal)             Join lines without moving cursor",
    "  Ctrl+D / Ctrl+U        Scroll half page and keep cursor centered",
    "  n / N                  Next / Prev search match and keep centered",
    "  <Space> p (Visual)     Paste over selection without yanking it",
    "  <Space> d              Delete to black hole (without yanking)",
    "  <Space> s              Substitute word under cursor everywhere",
    "  <Space> x              Make current file executable (chmod +x)",
    "",
    "  ── AI CODING WORKSPACE ─────────────────────────────────────────",
    "  AI activity icon       Agents, Context, and Actions workspace",
    "  1 / 2 / 3              Open Agents / Context / Actions section",
    "  Left / Right           Switch AI workspace section",
    "  Up / Down + Enter      Choose and run an AI workspace item",
    "  <Space> a f            Add current file reference to AI context",
    "  <Space> a c            Add current buffer contents to AI context",
    "  <Space> a s (Visual)   Add selected code and line range to context",
}

local state = { active_tab = "vim", buf = nil, win = nil }

local function open_bindings_window()
    local width  = math.min(74, vim.o.columns - 4)
    local height = math.floor(vim.o.lines * 0.85)
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local border_style = (not vim.g.tuim_zen_mode) and "none" or "rounded"
    local title_str = border_style == "rounded" and "  Tuim Help Reference " or nil

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative    = "editor",
        width       = width,
        height      = height,
        row         = row,
        col         = col,
        style       = "minimal",
        border      = border_style,
        title       = title_str,
        title_pos   = border_style == "rounded" and "center" or nil,
    })
    return buf, win
end

local function render()
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

    local tab_vim  = state.active_tab == "vim"
    local tab1_lbl = tab_vim and "●[1] Vim Motions " or "  [1] Vim Motions "
    local tab2_lbl = tab_vim and "  [2] Tuim Keys  " or "●[2] Tuim Keys  "

    local header = {
        "  " .. tab1_lbl .. " │ " .. tab2_lbl,
        "  ────────────────────────────────────────────────────────────",
        "",
    }

    local content = tab_vim and VIM_MOTIONS or TUIM_KEYS
    local lines = {}
    for _, l in ipairs(header) do table.insert(lines, l) end
    for _, l in ipairs(content) do table.insert(lines, l) end
    table.insert(lines, "")
    table.insert(lines, "  [Tab]/[1]/[2] Switch  │  [o] Onboarding  │  [/] Search  │  [q] Close")

    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })

    -- Highlight header
    local ns = vim.api.nvim_create_namespace("vimbindings_hl")
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Title",   0, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", 1, 0, -1)
    -- Highlight section headers
    for i, l in ipairs(lines) do
        if l:match("^%s+──") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Special", i - 1, 0, -1)
        elseif l:match("^%s+╭") or l:match("^%s+│") or l:match("^%s+╰") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "DiagnosticInfo", i - 1, 0, -1)
        elseif l:match("^%s+%[") and i == #lines then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", i - 1, 0, -1)
        end
    end
end

_G.open_help_menu = function()
    -- Stop insert mode if we are in it
    if vim.fn.mode() == 'i' then vim.cmd("stopinsert") end

    state.buf, state.win = open_bindings_window()
    vim.bo[state.buf].buftype   = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile  = false
    vim.bo[state.buf].filetype = "vimbindings"

    local map = function(k, fn, desc)
        vim.keymap.set({"n", "i"}, k, fn, { buffer = state.buf, silent = true, desc = desc })
    end

    map("q",     function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<Esc>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<C-c>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")

    map("<Tab>", function()
        state.active_tab = state.active_tab == "vim" and "tuim" or "vim"
        render()
    end, "Switch tab")
    map("1", function() state.active_tab = "vim";  render() end, "Vim Motions tab")
    map("2", function() state.active_tab = "tuim"; render() end, "Tuim Keys tab")
    map("o", function()
        pcall(vim.api.nvim_win_close, state.win, true)
        vim.schedule(function() vim.cmd('TuimOnboarding') end)
    end, "Open onboarding")

    -- Search within the buffer using built-in /
    map("/", function()
        vim.api.nvim_feedkeys("/", "n", false)
    end, "Search in buffer")

    render()
end



        -- Keymap to open
        -- We bind to normal and visual mode as well. But wait, since tuim forces insert mode,
        -- if the user hits <space> in insert mode it types a space. So we should create a user command.
        vim.api.nvim_create_user_command("HelpMenu", _G.open_help_menu, {})
        vim.keymap.set({ "n", "v" }, "<leader>hk", _G.open_help_menu, { desc = "Show Help Menu" })

-- --- FIRST-RUN ONBOARDING --- --
local onboarding = { buf = nil, win = nil }
local onboarding_marker = vim.fn.stdpath('data') .. '/onboarding-complete'

local function complete_onboarding()
    vim.fn.mkdir(vim.fn.fnamemodify(onboarding_marker, ':h'), 'p')
    vim.fn.writefile({ 'completed' }, onboarding_marker)
    if onboarding.win and vim.api.nvim_win_is_valid(onboarding.win) then pcall(vim.api.nvim_win_close, onboarding.win, true) end
end
_G.tuim_onboarding_dismiss = complete_onboarding

_G.tuim_onboarding_choose = function(mode)
    if mode == 'ide' then
        vim.g.tuim_zen_mode = false
        _G.tuim_enable_ide_mode()
    else
        vim.g.tuim_zen_mode = false
        _G.tuim_disable_ide_mode()
    end
    _G.tuim_save_settings()
    complete_onboarding()
end

_G.open_tuim_onboarding = function()
    if onboarding.win and vim.api.nvim_win_is_valid(onboarding.win) then return end
    if vim.fn.mode() == 'i' then vim.cmd('stopinsert') end
    local width = math.max(1, math.min(76, vim.o.columns - 4))
    local height = math.max(1, math.min(23, vim.o.lines - 4))
    onboarding.buf = vim.api.nvim_create_buf(false, true)
    onboarding.win = vim.api.nvim_open_win(onboarding.buf, true, {
        relative = 'editor', width = width, height = height,
        row = math.max(0, math.floor((vim.o.lines - height) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        style = 'minimal', border = 'rounded', title = ' Welcome to Tuim ', title_pos = 'center',
    })
    vim.bo[onboarding.buf].buftype = 'nofile'
    vim.bo[onboarding.buf].bufhidden = 'wipe'
    vim.bo[onboarding.buf].swapfile = false
    vim.bo[onboarding.buf].filetype = 'tuim-onboarding'
    local lines = {
        '  [ Click to close guide ]  or press Enter / Esc / q',
        '  Closing this guide keeps Tuim open and your current mode.',
        '',
        '  Start here',
        '  1. Open a file: Ctrl+E shows files. Click a file to open it.',
        '     Or press Ctrl+N to create a new file.',
        '  2. Edit: in IDE mode, click in the text and start typing.',
        '     In Normal mode, press i to type; Esc stops typing.',
        '  3. Save: Ctrl+S. For a new file, enter a name when asked.',
        '',
        '  Choose your editing style (press a key to start)',
        '  [i] IDE - type right away, like a regular text editor.',
        '  [n] Normal - Vim controls: i to type, Esc for commands.',
        '  You can change this later in Settings > General.',
        '',
        '  A few useful controls',
        '  Ctrl+F Find   Ctrl+Z Undo   Ctrl+T Open / hide terminal',
        '  Mouse: click to focus, drag text to select, right-click to copy.',
        '  F11 hides the panels; press it again to bring them back.',
        '',
        '  [l] Optional code tools (language servers for code suggestions)',
        '  Reopen this guide from Help: press o on the Help page.',
        '  In Normal mode, you can also type :TuimOnboarding then Enter.',
    }
    vim.api.nvim_buf_set_lines(onboarding.buf, 0, -1, false, lines)
    vim.bo[onboarding.buf].modifiable = false
    vim.wo[onboarding.win].wrap = true
    vim.wo[onboarding.win].linebreak = true
    vim.api.nvim_win_set_cursor(onboarding.win, { 1, 0 })
    local ns = vim.api.nvim_create_namespace('tuim_onboarding')
    vim.api.nvim_buf_add_highlight(onboarding.buf, ns, 'Visual', 0, 2, 26)
    for _, line in ipairs({ 4, 11, 16 }) do
        vim.api.nvim_buf_add_highlight(onboarding.buf, ns, 'Title', line - 1, 0, -1)
    end
    local map = function(key, callback, desc)
        vim.keymap.set({ 'n', 'i' }, key, callback, { buffer = onboarding.buf, silent = true, desc = desc })
    end
    map('n', function() _G.tuim_onboarding_choose('normal') end, 'Choose Normal mode')
    map('i', function() _G.tuim_onboarding_choose('ide') end, 'Choose IDE mode')
    map('<CR>', complete_onboarding, 'Close guide and start editing')
    map('<C-c>', complete_onboarding, 'Dismiss onboarding')
    map('<LeftMouse>', function()
        local mouse = vim.fn.getmousepos()
        if mouse.winid == onboarding.win and mouse.line == 1 then
            complete_onboarding()
        else
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<LeftMouse>', true, false, true), 'n', false)
        end
    end, 'Click to close guide')
    map('q', complete_onboarding, 'Dismiss onboarding')
    map('<Esc>', complete_onboarding, 'Dismiss onboarding')
    map('l', function()
        complete_onboarding()
        -- Use Tuim's native package panel, as Settings > Plugins does.
        -- Opening Mason's Neovim float bypasses that UI and fails when the
        -- plugin command has not been registered yet.
        local ok = pcall(vim.rpcnotify, 1, 'tuim_open_language_tools')
        if not ok then
            local opened, err = pcall(vim.cmd, 'Mason')
            if not opened then
                vim.notify('Language tools are unavailable. Open Settings > Plugins to enable Mason. ' .. tostring(err), vim.log.levels.WARN)
            end
        end
    end, 'Review language servers')
end

vim.api.nvim_create_user_command('TuimOnboarding', _G.open_tuim_onboarding, {})
if vim.env.TUIM_SKIP_ONBOARDING ~= '1' and vim.uv.fs_stat(onboarding_marker) == nil then
    vim.schedule(_G.open_tuim_onboarding)
end

_G.last_ai_job_id = nil
_G.last_ai_command = nil
_G.last_ai_buf = nil
_G.last_ai_win = nil
_G.last_ai_source_win = nil
_G.ai_generation = 0
_G.ai_ready_at = 0
_G.tuim_ai_sessions = {}

local ai_context_limit = 64 * 1024

local function ai_notify_status(command, state)
    pcall(vim.rpcnotify, 1, "tuim_ai_status", command or "", state, command == _G.last_ai_command)
end

local function ai_sanitize(text)
    text = tostring(text or ""):gsub("%z", ""):gsub("\27", "")
    if #text > ai_context_limit then
        text = text:sub(1, ai_context_limit) .. "\n\n[Context truncated by Tuim at 64 KiB]"
    end
    return text
end

function _G.GetActiveAIJob()
    local job_id = _G.last_ai_job_id
    if not job_id then return nil end
    local ok, res = pcall(vim.fn.jobwait, { job_id }, 0)
    if ok and res and res[1] == -1 then return job_id end
    _G.last_ai_job_id = nil
    ai_notify_status(_G.last_ai_command, "stopped")
    return nil
end

local ai_agent_preference = { "codex", "claude", "gemini", "opencode", "agy", "copilot" }

local function ai_notice(level, message)
    _G.tuim_native_notice(level, message)
end

local function require_ai_job()
    local job_id = _G.GetActiveAIJob()
    if job_id then return job_id end
    local command = _G.last_ai_command
    if not command or vim.fn.executable(command) == 0 then
        command = nil
        for _, candidate in ipairs(ai_agent_preference) do
            if vim.fn.executable(candidate) == 1 then command = candidate; break end
        end
    end
    if not command then
        ai_notice("warning", "Install Codex, Claude Code, Gemini, OpenCode, Antigravity, or Copilot to use AI actions.")
        return nil
    end
    _G.OpenAITerminal(command)
    return _G.GetActiveAIJob()
end

local function send_ai_text(text, submit)
    local job_id = require_ai_job()
    if not job_id then return false end
    text = ai_sanitize(text)
    local generation = _G.ai_generation
    local payload = "\27[200~" .. text .. "\27[201~" .. (submit and "\r" or "")
    local function deliver()
        if generation ~= _G.ai_generation or _G.GetActiveAIJob() ~= job_id then
            ai_notice("warning", "The AI session stopped before the context could be delivered.")
            return
        end
        vim.fn.chansend(job_id, payload)
    end

    -- A freshly launched full-screen agent needs a moment to enable its input
    -- parser. Queue the first prompt instead of letting an initializing process
    -- consume or discard bracketed-paste control sequences.
    local delay = math.max(0, (_G.ai_ready_at or 0) - vim.uv.now())
    if delay > 0 then vim.defer_fn(deliver, delay) else deliver() end
    return true
end

local function context_block(kind, metadata, body)
    return string.format("<tuim_context type=%q %s>\n%s\n</tuim_context>\n", kind, metadata or "", ai_sanitize(body))
end

local function source_buffer()
    if _G.last_ai_source_win and vim.api.nvim_win_is_valid(_G.last_ai_source_win) then
        local buf = vim.api.nvim_win_get_buf(_G.last_ai_source_win)
        if vim.bo[buf].buftype == "" then return buf end
    end
    local current = vim.api.nvim_get_current_buf()
    if vim.bo[current].buftype == "" then
        -- Remember the editor window before an AI action changes focus. This is
        -- also needed to leave Visual mode and finalize the '< and '> marks.
        _G.last_ai_source_win = vim.api.nvim_get_current_win()
        return current
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "" then
            _G.last_ai_source_win = win
            return buf
        end
    end
    return nil
end

local function current_file()
    local buf = source_buffer()
    if not buf then return nil end
    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" then return nil end
    return path
end

local function selected_text()
    local buf = source_buffer()
    if not buf then return nil end
    local mode = vim.api.nvim_get_mode().mode
    if (mode:sub(1, 1) == "v" or mode:sub(1, 1) == "V" or mode == "\22") and
        _G.last_ai_source_win and vim.api.nvim_win_is_valid(_G.last_ai_source_win) then
        vim.api.nvim_win_call(_G.last_ai_source_win, function() vim.cmd("normal! \27") end)
    end
    local first = vim.api.nvim_buf_get_mark(buf, "<")
    local last = vim.api.nvim_buf_get_mark(buf, ">")
    if not first or not last or first[1] == 0 or last[1] == 0 then return nil end
    local lines = vim.api.nvim_buf_get_lines(buf, first[1] - 1, last[1], false)
    if #lines == 0 then return nil end
    if vim.fn.visualmode() == "v" then
        lines[#lines] = lines[#lines]:sub(1, last[2] + 1)
        lines[1] = lines[1]:sub(first[2] + 1)
    end
    return table.concat(lines, "\n"), first[1], last[1]
end

local function diagnostics_text()
    local buf = source_buffer()
    if not buf then return "No source buffer is active." end
    local diagnostics = vim.diagnostic.get(buf)
    if #diagnostics == 0 then return "No diagnostics in the current file." end
    local severity = vim.diagnostic.severity
    local names = { [severity.ERROR] = "ERROR", [severity.WARN] = "WARN", [severity.INFO] = "INFO", [severity.HINT] = "HINT" }
    local lines = {}
    for _, diagnostic in ipairs(diagnostics) do
        table.insert(lines, string.format("%s %d:%d %s", names[diagnostic.severity] or "DIAG", diagnostic.lnum + 1, diagnostic.col + 1, diagnostic.message:gsub("\n", " ")))
    end
    return table.concat(lines, "\n")
end

local function git_diff_text()
    local diff = vim.fn.system({ "git", "diff", "--no-ext-diff", "HEAD" })
    if vim.v.shell_error ~= 0 then diff = vim.fn.system({ "git", "diff", "--no-ext-diff" }) end
    if diff == "" then return "Working tree has no tracked changes." end
    return diff
end

function _G.SendSelectionToAI()
    local text, first, last = selected_text()
    if not text then
        ai_notice("warning", "Select some code first, then open the right-click menu.")
        return
    end
    local path = current_file() or "[No Name]"
    if send_ai_text(context_block("selection", string.format("file=%q lines=%q", path, first .. "-" .. last), text), false) then
        vim.notify("Selection added to AI context", vim.log.levels.INFO)
    end
end

function _G.SendFilePathToAI()
    local path = current_file()
    if not path then
        vim.notify("The current buffer has no file path.", vim.log.levels.WARN)
        return
    end
    if send_ai_text(context_block("file", string.format("path=%q", path), "Use this file as context."), false) then
        vim.notify("File reference added to AI context", vim.log.levels.INFO)
    end
end

function _G.SendFileContentToAI()
    local path = current_file() or "[No Name]"
    local buf = source_buffer()
    if not buf then vim.notify("No source buffer is active.", vim.log.levels.WARN); return end
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    if send_ai_text(context_block("buffer", string.format("file=%q", path), text), false) then
        vim.notify("Buffer contents added to AI context", vim.log.levels.INFO)
    end
end

function _G.SendDiagnosticsToAI()
    local path = current_file() or "[No Name]"
    if send_ai_text(context_block("diagnostics", string.format("file=%q", path), diagnostics_text()), false) then
        vim.notify("Diagnostics added to AI context", vim.log.levels.INFO)
    end
end

function _G.SendGitDiffToAI()
    if send_ai_text(context_block("git_diff", "", git_diff_text()), false) then
        vim.notify("Git diff added to AI context", vim.log.levels.INFO)
    end
end

function _G.RunAIAction(action)
    local path = current_file() or "[No Name]"
    local prompt
    if action == "fix_diagnostics" then
        prompt = "Fix the diagnostics in " .. path .. ". Inspect the surrounding code, make the smallest correct edits, and run relevant checks.\n" .. context_block("diagnostics", string.format("file=%q", path), diagnostics_text())
    elseif action == "explain_selection" then
        local text, first, last = selected_text()
        if not text then ai_notice("warning", "Select some code first, then choose Explain with AI."); return end
        prompt = "Explain this code clearly, including intent, important control flow, and likely pitfalls.\n" .. context_block("selection", string.format("file=%q lines=%q", path, first .. "-" .. last), text)
    elseif action == "fix_selection" then
        local text, first, last = selected_text()
        if not text then ai_notice("warning", "Select some code first, then choose Fix / Improve with AI."); return end
        prompt = "Fix or improve the selected code in " .. path .. ". Preserve its intended behavior, follow the surrounding conventions, make the smallest useful edit, and run relevant checks.\n" .. context_block("selection", string.format("file=%q lines=%q", path, first .. "-" .. last), text)
    elseif action == "write_tests" then
        prompt = "Write or improve focused tests for " .. path .. ". Follow the repository's existing test style and run the relevant test command."
    elseif action == "review_changes" then
        prompt = "Review the current working-tree changes for correctness, regressions, security issues, and missing tests. Report findings by severity before proposing edits.\n" .. context_block("git_diff", "", git_diff_text())
    elseif action == "implement_todo" then
        local buf = source_buffer()
        if not buf then vim.notify("No source buffer is active.", vim.log.levels.WARN); return end
        local row = 1
        if _G.last_ai_source_win and vim.api.nvim_win_is_valid(_G.last_ai_source_win) then
            row = vim.api.nvim_win_get_cursor(_G.last_ai_source_win)[1]
        end
        local first = math.max(0, row - 8)
        local last = math.min(vim.api.nvim_buf_line_count(buf), row + 7)
        local nearby = table.concat(vim.api.nvim_buf_get_lines(buf, first, last, false), "\n")
        prompt = "Implement the TODO or unfinished behavior near the cursor in " .. path .. ". Preserve local conventions and run relevant tests.\n" .. context_block("near_cursor", string.format("file=%q lines=%q", path, (first + 1) .. "-" .. last), nearby)
    else
        ai_notice("error", "Unknown AI action: " .. tostring(action))
        return
    end
    if send_ai_text(prompt, true) then vim.schedule(_G.FocusAITerminal) end
end

vim.keymap.set("v", "<leader>as", _G.SendSelectionToAI, { desc = "Send selected text to AI terminal" })
vim.keymap.set("n", "<leader>af", _G.SendFilePathToAI, { desc = "Send current file path to AI terminal" })
vim.keymap.set("n", "<leader>ac", _G.SendFileContentToAI, { desc = "Send entire file content to AI terminal" })

vim.keymap.set({ "n", "v", "i" }, "<M-s>", _G.SendSelectionToAI, { desc = "Send selected text to AI terminal" })
vim.keymap.set({ "n", "v", "i" }, "<M-f>", _G.SendFilePathToAI, { desc = "Send current file path to AI terminal" })
vim.keymap.set({ "n", "v", "i" }, "<M-c>", _G.SendFileContentToAI, { desc = "Send entire file content to AI terminal" })

vim.keymap.set({ "n", "v", "i" }, "<C-M-s>", _G.SendSelectionToAI, { desc = "Send selected text to AI terminal" })
vim.keymap.set({ "n", "v", "i" }, "<C-M-f>", _G.SendFilePathToAI, { desc = "Send current file path to AI terminal" })
vim.keymap.set({ "n", "v", "i" }, "<C-M-c>", _G.SendFileContentToAI, { desc = "Send entire file content to AI terminal" })

function _G.NotifyAIMissing(cmd)
    ai_notice("warning", "AI agent '" .. cmd .. "' is not installed or not available on PATH.")
end

function _G.OpenTerminalRight()
    _G.tuim_close_floating_windows()
    vim.cmd('botright vnew')
    vim.fn.termopen(vim.o.shell)
    vim.bo.bufhidden = 'hide'
    vim.cmd('startinsert')
end

local function configure_ai_winbar(win, command)
    if not win or not vim.api.nvim_win_is_valid(win) then return end
    -- Tuim draws split-owned tabs in its native top strip.
    vim.wo[win].winbar = ""
end

function _G.FocusAITerminal()
    if not require_ai_job() then return end
    if _G.last_ai_win and vim.api.nvim_win_is_valid(_G.last_ai_win) then
        vim.api.nvim_set_current_win(_G.last_ai_win)
        vim.cmd("startinsert")
        return
    end
    if _G.last_ai_buf and vim.api.nvim_buf_is_valid(_G.last_ai_buf) then
        vim.cmd("botright vsplit")
        vim.cmd("wincmd L")
        vim.api.nvim_win_set_buf(0, _G.last_ai_buf)
        _G.last_ai_win = vim.api.nvim_get_current_win()
        configure_ai_winbar(_G.last_ai_win, _G.last_ai_command or "agent")
        vim.cmd("startinsert")
    end
end

function _G.StopAITerminal()
    local job_id = _G.GetActiveAIJob()
    if not job_id then return end
    _G.ai_generation = _G.ai_generation + 1
    _G.last_ai_job_id = nil
    local session = _G.tuim_ai_sessions[_G.last_ai_command]
    if session then session.job = nil end
    pcall(vim.fn.jobstop, job_id)
    ai_notify_status(_G.last_ai_command, "stopped")
    ai_notice("info", "AI session stopped")
end

function _G.CloseAITerminal()
    local job_id = _G.GetActiveAIJob()
    local win = _G.last_ai_win
    local buf = _G.last_ai_buf
    local source_win = _G.last_ai_source_win

    -- Invalidate callbacks before stopping the job so a stale on_exit cannot
    -- overwrite the state of a newly opened agent session.
    _G.ai_generation = _G.ai_generation + 1
    _G.last_ai_job_id = nil
    _G.last_ai_win = nil
    _G.last_ai_buf = nil
    _G.ai_ready_at = 0
    _G.tuim_ai_sessions[_G.last_ai_command or ''] = nil

    if job_id then pcall(vim.fn.jobstop, job_id) end
    if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    if buf and vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    ai_notify_status(_G.last_ai_command, "stopped")

    if source_win and vim.api.nvim_win_is_valid(source_win) then
        pcall(vim.api.nvim_set_current_win, source_win)
    end
    ai_notice("info", "AI panel closed")
end

function _G.TuimCloseAIWinbar()
    _G.CloseAITerminal()
end

function _G.RestartAITerminal()
    local command = _G.last_ai_command
    if not command then
        ai_notice("warning", "No AI session to restart.")
        return
    end
    _G.StopAITerminal()
    vim.schedule(function() _G.OpenAITerminal(command) end)
end

function _G.OpenAITerminal(cmd)
    if vim.fn.executable(cmd) == 0 then _G.NotifyAIMissing(cmd); return end
    local session = _G.tuim_ai_sessions[cmd]
    if session and session.job and vim.fn.jobwait({ session.job }, 0)[1] ~= -1 then session.job = nil end
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_get_current_buf()
    if vim.bo[current_buf].buftype == "" then _G.last_ai_source_win = current_win end
    if _G.last_ai_win and vim.api.nvim_win_is_valid(_G.last_ai_win) then
        vim.api.nvim_set_current_win(_G.last_ai_win)
    else
        vim.cmd("botright vsplit")
        vim.cmd("wincmd L")
    end
    _G.ai_generation = _G.ai_generation + 1
    local generation = _G.ai_generation
    _G.last_ai_command = cmd
    _G.last_ai_win = vim.api.nvim_get_current_win()
    if session and session.job and vim.api.nvim_buf_is_valid(session.buf) then
        _G.last_ai_job_id, _G.last_ai_buf = session.job, session.buf
        _G.ai_ready_at = session.ready_at
        vim.api.nvim_win_set_buf(0, session.buf)
        configure_ai_winbar(_G.last_ai_win, cmd)
        ai_notify_status(cmd, 'running')
        vim.cmd('startinsert')
        return
    end
    if session and vim.api.nvim_buf_is_valid(session.buf) then
        pcall(vim.api.nvim_buf_delete, session.buf, { force = true })
    end
    vim.cmd('enew')
    session = { buf = vim.api.nvim_get_current_buf(), ready_at = vim.uv.now() + 900 }
    _G.tuim_ai_sessions[cmd] = session
    vim.b[session.buf].tuim_ai = true
    -- Launch the agent directly. Going through an interactive shell creates a
    -- race where the first AI prompt can be pasted into the shell before its
    -- `exec` command has replaced it with the agent.
    local job_id = vim.fn.termopen({ cmd }, {
        on_exit = function()
            if _G.tuim_ai_sessions[cmd] ~= session then return end
            session.job = nil
            if _G.last_ai_command == cmd then _G.last_ai_job_id = nil end
            ai_notify_status(cmd, "stopped")
        end,
    })
    _G.last_ai_job_id = job_id
    session.job = job_id > 0 and job_id or nil
    _G.last_ai_command = cmd
    _G.ai_ready_at = session.ready_at
    _G.last_ai_buf = vim.api.nvim_get_current_buf()
    _G.last_ai_win = vim.api.nvim_get_current_win()
    vim.bo[_G.last_ai_buf].bufhidden = "hide"
    vim.api.nvim_buf_set_name(_G.last_ai_buf, string.format("AI: %s [%d]", cmd, generation))
    configure_ai_winbar(_G.last_ai_win, cmd)
    ai_notify_status(cmd, session.job and "running" or "stopped")
    vim.cmd("startinsert")
end

-- Tuim renders its own native editor context menu, so Neovim must not also
-- open or process a second right-click menu in the embedded UI.
for _, mode in ipairs({ 'n', 'v', 'i', 's', 'c' }) do
    vim.keymap.set(mode, '<RightMouse>', '<Nop>', { silent = true })
    vim.keymap.set(mode, '<RightRelease>', '<Nop>', { silent = true })
    vim.keymap.set(mode, '<RightDrag>', '<Nop>', { silent = true })
    vim.keymap.set(mode, '<2-RightMouse>', '<Nop>', { silent = true })
    vim.keymap.set(mode, '<3-RightMouse>', '<Nop>', { silent = true })
    vim.keymap.set(mode, '<4-RightMouse>', '<Nop>', { silent = true })
end

-- Tuim owns the visual tab strip, but Neovim remains the source of truth for
-- buffers. Notify the frontend after every relevant buffer lifecycle event.
local function tuim_notify_buffers()
    local buffers = {}
    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
        -- Split-owned AI terminals have their own winbar tab and should not
        -- masquerade as files in Tuim's global file tab strip.
        if not vim.b[info.bufnr].tuim_ai then
            local name = info.name or ""
            table.insert(buffers, {
                bufnr = info.bufnr,
                name = name,
                relative_name = name == "" and "" or vim.fn.fnamemodify(name, ":."),
                changed = info.changed == 1,
            })
        end
    end
    vim.rpcnotify(1, "tuim_buffers", buffers, vim.api.nvim_get_current_buf())
end

vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufFilePost", "BufModifiedSet", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("TuimBufferSync", { clear = true }),
    callback = function() vim.schedule(tuim_notify_buffers) end,
})
vim.schedule(tuim_notify_buffers)
