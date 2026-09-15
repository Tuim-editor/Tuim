assert(type(_G.tuim_enable_ide_mode) == 'function')
assert(type(_G.tuim_disable_ide_mode) == 'function')
assert(type(_G.tuim_ide_action) == 'function')
assert(type(_G.tuim_close_buffer) == 'function')
assert(type(_G.tuim_close_floating_windows) == 'function')
assert(vim.fn.maparg(' ot', 'n') ~= '', 'missing bottom terminal split mapping: <Space> o t')
assert(vim.fn.maparg(' oT', 'n') ~= '', 'missing vertical terminal split mapping: <Space> o T')

_G.open_help_menu()
vim.api.nvim_feedkeys('2', 'x', false)
local help_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
for _, expected in ipairs({
  '<Space> o t            Toggle Bottom Terminal Split',
  '<Space> o T            Toggle Vertical Terminal Split',
  '<C-w> s / <C-w> v      Horizontal / Vertical Editor Split',
}) do
  assert(help_text:find(expected, 1, true), 'missing help text: ' .. expected)
end
vim.api.nvim_win_close(0, true)

vim.cmd('enew!')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta', 'gamma' })

-- Repeating a global shortcut while a modified prompt-like float has focus
-- must not raise E37 or damage the edited file underneath it.
local edited_buffer = vim.api.nvim_get_current_buf()
local floating_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(floating_buffer, 0, -1, false, { 'query' })
vim.bo[floating_buffer].modified = true
local floating_window = vim.api.nvim_open_win(floating_buffer, true, {
  relative = 'editor', row = 1, col = 1, width = 20, height = 1, style = 'minimal',
})
_G.tuim_close_floating_windows()
_G.tuim_close_floating_windows()
assert(not vim.api.nvim_win_is_valid(floating_window))
assert(vim.api.nvim_get_current_buf() == edited_buffer)
assert(vim.bo[edited_buffer].modified == true)

_G.tuim_enable_ide_mode()
assert(vim.g.tuim_ide_mode == true)

for _, lhs in ipairs({ '<Esc>', '<Home>', '<End>', '<C-Left>', '<C-Right>', '<D-Left>', '<D-Right>',
    '<S-Left>', '<S-Right>', '<S-Home>', '<S-End>', '<C-S-Left>', '<C-S-Right>' }) do
  if lhs == '<Home>' or lhs == '<End>' then
    -- Neovim supplies these familiar defaults; the rest are IDE-owned.
    assert(vim.fn.maparg(lhs, 'i') == '')
  else
  assert(vim.fn.maparg(lhs, 'i') ~= '', 'missing insert mapping: ' .. lhs)
  end
end
for _, lhs in ipairs({ '<C-s>', '<C-z>', '<C-y>', '<C-a>', '<C-c>', '<C-x>', '<C-v>', '<C-f>', '<C-h>' }) do
  assert(vim.fn.maparg(lhs, 'i') ~= '', 'missing IDE shortcut: ' .. lhs)
end

_G.tuim_ide_action('select_all')
assert(vim.api.nvim_get_mode().mode:match('[vV\22]'))
vim.cmd('normal! \27')
_G.tuim_ide_action('undo')
_G.tuim_ide_action('redo')

vim.cmd('stopinsert')
-- Keep this headless test independent of the host pasteboard. This also checks
-- that IDE actions respect the user's disabled System Clipboard setting.
vim.o.clipboard = ''
vim.fn.setreg('"', { 'pasted from IDE' }, 'l')
_G.tuim_ide_action('paste')
assert(vim.api.nvim_get_current_line() == 'pasted from IDE')

local first_buffer = vim.api.nvim_get_current_buf()
_G.tuim_ide_action('new')
assert(vim.api.nvim_get_current_buf() ~= first_buffer)
_G.tuim_ide_action('previous_buffer')
assert(vim.api.nvim_get_current_buf() == first_buffer)
_G.tuim_ide_action('next_buffer')
assert(vim.api.nvim_get_current_buf() ~= first_buffer)

local disposable_buffer = vim.api.nvim_get_current_buf()
assert(_G.tuim_close_buffer(disposable_buffer) == true)
assert(not vim.api.nvim_buf_is_valid(disposable_buffer))
assert(vim.api.nvim_get_current_buf() == first_buffer)

-- First-save naming works without plugins and protects existing files.
local original_input, original_notice = vim.ui.input, _G.tuim_native_notice
local callback, notice
vim.ui.input = function(opts, done)
  assert(opts.completion == 'file')
  callback = done
end
_G.tuim_native_notice = function(_, message) notice = message end
vim.cmd('enew!')
local unnamed = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'new file content' })
_G.tuim_save_file()
callback(nil)
assert(vim.api.nvim_buf_get_name(unnamed) == '')
assert(vim.bo[unnamed].modified)
_G.tuim_save_file()
callback('')
assert(vim.api.nvim_buf_get_name(unnamed) == '')
_G.tuim_save_file()
callback(vim.fn.tempname() .. '/missing-parent/file.txt')
assert(vim.api.nvim_buf_get_name(unnamed) == '', 'Failed first save must allow choosing another name')
assert(vim.bo[unnamed].modified)
local target = vim.fn.tempname() .. ' with spaces.txt'
vim.fn.writefile({ 'existing content' }, target)
_G.tuim_save_file()
callback(target)
assert(vim.fn.readfile(target)[1] == 'existing content')
assert(vim.api.nvim_buf_get_name(unnamed) == '')
assert(notice:find('already exists', 1, true))
vim.fn.delete(target)
_G.tuim_save_file()
callback(target)
assert(vim.fn.readfile(target)[1] == 'new file content')
assert(not vim.bo[unnamed].modified)
vim.ui.input = function() error('Named files must not prompt') end
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { 'updated content' })
_G.tuim_ide_action('save')
assert(vim.fn.readfile(target)[1] == 'updated content')
vim.fn.delete(target)
vim.ui.input, _G.tuim_native_notice = original_input, original_notice

_G.tuim_disable_ide_mode()
assert(vim.g.tuim_ide_mode == false)
assert(vim.fn.maparg('<S-Left>', 'i') == '')
vim.cmd('qa!')
