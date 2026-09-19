vim.rpcnotify = function() end
vim.fn.mkdir(vim.fn.stdpath('data') .. '/lazy/lazy.nvim', 'p')
vim.opt.rtp:prepend(assert(vim.env.TUIM_TEST_ALPHA))
package.preload.lazy = function()
    return { setup = function(specs)
        for _, spec in ipairs(specs) do
            if spec[1] == 'goolord/alpha-nvim' then spec.config() end
        end
    end }
end
local recent = vim.fn.getcwd() .. '/recent example.txt'
vim.fn.writefile({'recent file content'}, recent)
vim.v.oldfiles = {recent, recent, vim.fn.getcwd() .. '/missing.txt'}
dofile(assert(vim.env.TUIM_TEST_ROOT) .. '/src/nvim/tuim_init.lua')
assert(vim.wait(1000, function() return vim.bo.filetype == 'alpha' end))
local function content() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
assert(content():find('tuim /', 1, true))
assert(content():find('Ctrl+P', 1, true))
assert(content():find('Command menu', 1, true))
assert(content():find('F1', 1, true))
assert(content():find('recent example.txt', 1, true))
local dashboard = require('alpha.themes.dashboard')
local recent_button, command_button, quit_button
for _, item in ipairs(dashboard.section.buttons.val) do
    if item.type == 'button' and item.opts.shortcut == '1' then recent_button = item end
    if item.type == 'button' and item.opts.shortcut == 'F1' then command_button = item end
    if item.type == 'button' and item.val == 'Quit' then quit_button = item end
end
assert(recent_button)
assert(command_button)
assert(quit_button)
assert(command_button.opts.keymap[3]:find('tuim_open_commands', 1, true))
assert(quit_button.opts.keymap[3]:find('tuim_confirm_quit', 1, true))
recent_button.on_press()
assert(vim.api.nvim_buf_get_name(0) == recent)
_G.tuim_alpha_start()
vim.o.columns = 36
vim.api.nvim_exec_autocmds('VimResized', {})
assert(content():find('New file', 1, true))
for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    assert(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(0), line)
end
print('Welcome passed: project title, Ctrl+P, confirmed quit, deduplicated recent files, opening paths with spaces, narrow layout')
vim.cmd('qa!')
