vim.rpcnotify = function() end
vim.opt.shell = '/bin/sh'
dofile('src/nvim/terminal_init.lua')
assert(not vim.o.ruler and not vim.o.showcmd and vim.o.cmdheight == 0)

_G.tuim_ensure_terminal()
local first_buf = vim.api.nvim_get_current_buf()
local first_job = vim.b.terminal_job_id
assert(vim.fn.jobwait({first_job}, 0)[1] == -1)
_G.tuim_ensure_terminal()
assert(vim.b.terminal_job_id == first_job, 'Reopening replaced a live shell')

vim.fn.chansend(first_job, 'exit\n')
assert(vim.wait(2000, function() return vim.fn.jobwait({first_job}, 0)[1] ~= -1 end))
_G.tuim_ensure_terminal()
local second_job = vim.b.terminal_job_id
assert(second_job ~= first_job and vim.fn.jobwait({second_job}, 0)[1] == -1)
assert(not vim.api.nvim_buf_is_valid(first_buf), 'Exited terminal leaked its buffer')

-- Neovim may already have removed the exited terminal after a keypress.
vim.fn.chansend(second_job, 'exit\n')
assert(vim.wait(2000, function() return vim.fn.jobwait({second_job}, 0)[1] ~= -1 end))
vim.api.nvim_buf_delete(0, {force=true})
_G.tuim_ensure_terminal()
assert(vim.bo.buftype == 'terminal' and vim.b.terminal_job_id ~= second_job)
vim.fn.jobstop(vim.b.terminal_job_id)
print('Bottom terminal passed: preserves live shell, restarts after exit and after buffer removal')
vim.cmd('qa!')
