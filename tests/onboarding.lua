assert(vim.fn.exists(':TuimOnboarding') == 2)
_G.open_tuim_onboarding()
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].filetype == 'tuim-onboarding')
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
for _, expected in ipairs({
  'Click to close guide', 'Enter / Esc / q', '1. Open a file', '2. Edit', '3. Save',
  '[i] IDE', '[n] Normal', 'i to type, Esc for commands', 'Ctrl+S',
  'Ctrl+F', 'Ctrl+Z', 'Ctrl+E', 'Ctrl+T', 'F11', 'language servers',
}) do
  assert(text:find(expected, 1, true), 'missing onboarding content: ' .. expected)
end
for _, key in ipairs({ 'n', 'i', 'l', 'q', '<Esc>', '<CR>', '<C-c>', '<LeftMouse>' }) do
  assert(vim.fn.maparg(key, 'n', false, true).buffer == 1, 'missing onboarding key: ' .. key)
end
_G.tuim_onboarding_choose('ide')
assert(vim.g.tuim_ide_mode == true)
assert(vim.uv.fs_stat(vim.fn.stdpath('data') .. '/onboarding-complete'))
local settings = vim.fn.json_decode(table.concat(vim.fn.readfile(vim.fn.stdpath('data') .. '/settings.json'), '\n'))
assert(settings.mode == 'ide')
_G.open_tuim_onboarding()
assert(vim.bo[vim.api.nvim_get_current_buf()].filetype == 'tuim-onboarding')
_G.tuim_onboarding_dismiss()
assert(vim.uv.fs_stat(vim.fn.stdpath('data') .. '/onboarding-complete'))
-- The welcome action must request Tuim's native language-tools panel even
-- when plugins are disabled and the :Mason command does not exist.
local original_rpcnotify = vim.rpcnotify
local requested = false
vim.rpcnotify = function(channel, method, ...)
  if method == 'tuim_open_language_tools' then
    assert(channel == 1)
    requested = true
    return nil -- rpcnotify succeeds without a return value
  end
  return original_rpcnotify(channel, method, ...)
end
_G.open_tuim_onboarding()
local guide_win = vim.api.nvim_get_current_win()
vim.api.nvim_feedkeys('l', 'xt', false)
assert(requested, 'language tools shortcut did not request the native panel')
assert(not vim.api.nvim_win_is_valid(guide_win), 'language tools left guide open')
vim.rpcnotify = original_rpcnotify
-- Exercise actual close keys in both editing styles, including a short window.
for _, mode in ipairs({ 'normal', 'ide' }) do
  _G.tuim_onboarding_choose(mode)
  for _, key in ipairs({ '<CR>', '<Esc>', 'q', '<C-c>' }) do
    vim.o.lines = 16
    vim.o.columns = 50
    _G.open_tuim_onboarding()
    local win = vim.api.nvim_get_current_win()
    assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find('Click to close guide', 1, true))
    local input = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(input, 'xt', false)
    assert(not vim.api.nvim_win_is_valid(win), 'close key failed: ' .. key)
    assert(vim.g.tuim_ide_mode == (mode == 'ide'), 'closing changed editing style')
  end
end
vim.cmd('qa!')
