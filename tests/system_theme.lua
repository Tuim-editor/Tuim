-- Run with isolated XDG paths and plugins/onboarding disabled by system_theme.py.
local notices, themes = {}, {}
vim.rpcnotify = function(_, method, ...)
    local args = { ... }
    if method == 'tuim_theme_changed' then table.insert(themes, args[1]) end
    if method == 'tuim_notice' then table.insert(notices, args[2]) end
end
dofile('src/nvim/tuim_init.lua')
vim.wait(100, function() return #themes > 0 end)
local root = vim.env.XDG_STATE_HOME .. '/omarchy/current/theme'
vim.fn.mkdir(root, 'p')
local path = root .. '/colors.toml'
local function write(lines) vim.fn.writefile(lines, path) end
local function color(group, attr)
    return string.format('#%06x', vim.api.nvim_get_hl(0, { name = group, link = false })[attr])
end
local function current() return themes[#themes] end

-- Missing palettes have a usable fallback and preserve the System selection.
_G.tuim_apply_theme('system')
assert(vim.g.colors_name == 'system')
assert(notices[#notices]:find('System palette unavailable', 1, true))

write({ 'mode = "dark"', 'background = "#05182e"', 'foreground = "#f6dcac"',
    'accent = "#faa968"', 'dark_background = "#031222"', 'lighter_background = "#0a2540"',
    'red = "#f85525"', 'green = "#028391"', 'blue = "#3f8f8a"',
    'selection = "#134e5a"', 'selection_foreground = "#a7c9c6"' })
assert(vim.wait(3500, function() return color('Normal', 'bg') == '#05182e' end, 30), 'System did not discover the palette')
assert(vim.g.colors_name == 'system' and vim.o.background == 'dark')
assert(color('Normal', 'fg') == '#f6dcac')
assert(color('String', 'fg') == '#028391')
assert(color('Visual', 'bg') == '#134e5a' and color('Visual', 'fg') == '#a7c9c6')
assert(current().bg_editor == '#05182e' and current().bg_sidebar == '#031222')
assert(current().bg_accent == '#faa968')
assert(vim.g.terminal_color_1 == '#f85525')
-- Load the desktop's actual syntax theme, including Tree-sitter captures,
-- without executing the user's Neovim init or importing LazyVim.
local runtime = vim.env.XDG_DATA_HOME .. '/nvim/lazy/test-theme'
vim.fn.mkdir(runtime .. '/colors', 'p')
vim.fn.writefile({
    "vim.cmd('highlight clear')",
    "vim.api.nvim_set_hl(0, 'Normal', {fg='#a7c9c6', bg='#05182e'})",
    "vim.api.nvim_set_hl(0, 'Comment', {fg='#135363'})",
    "vim.api.nvim_set_hl(0, '@function.call', {fg='#faa968'})",
    "vim.api.nvim_set_hl(0, 'Visual', {fg='#a7c9c6', bg='#134e5a'})",
    "vim.g.colors_name = 'test-theme'",
}, runtime .. '/colors/test-theme.lua')
vim.fn.writefile({ "return {{'example/test-theme'}, {'LazyVim/LazyVim', opts={colorscheme='test-theme'}}}" }, root .. '/neovim.lua')
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(_G.tuim_system_colorscheme == 'test-theme')
assert(color('Normal', 'fg') == '#a7c9c6')
assert(color('Comment', 'fg') == '#135363')
assert(color('@function.call', 'fg') == '#faa968')
assert(not vim.api.nvim_get_hl(0, {name='Visual'}).bold)
assert(vim.g.colors_name == 'system')
vim.fn.delete(root .. '/neovim.lua')
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(_G.tuim_system_colorscheme == nil)
assert(color('Normal', 'fg') == '#f6dcac')
_G.tuim_save_settings()
local saved = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath('data') .. '/settings.json'), '\n'))
assert(saved.theme == 'system', 'System selection was replaced by a concrete theme name')

-- Empty/malformed files during a desktop theme swap retain the last good colors.
write({ 'background = "#bad"', 'foreground = "#f6dcac"' })
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(color('Normal', 'bg') == '#05182e')
vim.fn.delete(path)
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(color('Normal', 'bg') == '#05182e')

-- Follow a replacement directory and the old numbered ANSI palette format.
vim.fn.delete(root, 'rf')
vim.fn.mkdir(root, 'p')
write({ "background = '#f8f4ee'", "foreground = '#242424'", "accent = '#805020'",
    "color1 = '#b02020'", "color2 = '#206030'", "color15 = '#ffffff'" })
assert(vim.wait(3500, function() return color('Normal', 'bg') == '#f8f4ee' end, 30), 'Live system palette did not refresh')
assert(vim.o.background == 'light' and current().bg_editor == '#f8f4ee')
assert(vim.g.terminal_color_1 == '#b02020' and vim.g.terminal_color_15 == '#ffffff')

-- Reapplying unchanged System does not continuously clear highlights/redraw.
local updates = #themes
_G.tuim_apply_theme('system')
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(#themes == updates)

-- Choosing a regular theme stops following the desktop, including :colorscheme.
_G.tuim_apply_theme('default')
local default_bg = color('Normal', 'bg')
write({ 'background = "#121212"', 'foreground = "#eeeeee"' })
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(vim.g.colors_name == 'default' and color('Normal', 'bg') == default_bg)
_G.tuim_apply_theme('system')
vim.cmd.colorscheme('default')
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(vim.g.colors_name == 'default' and _G.tuim_system_palette == nil)

-- Legacy Omarchy installs expose the current palette under XDG_CONFIG_HOME.
vim.fn.delete(path)
local legacy = vim.env.XDG_CONFIG_HOME .. '/omarchy/current/theme'
vim.fn.mkdir(legacy, 'p')
vim.fn.writefile({ 'background = "#102030"', 'foreground = "#eeeeee"' }, legacy .. '/colors.toml')
_G.tuim_apply_theme('system')
assert(color('Normal', 'bg') == '#102030')
_G.tuim_apply_theme('default')
print('System theme passed: palette, syntax, chrome, live reload, fallback, legacy paths, persistence, watcher cleanup')
vim.cmd('qa!')
