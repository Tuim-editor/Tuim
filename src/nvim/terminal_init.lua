vim.g.tuim_is_terminal = true
vim.opt.termguicolors = true
vim.opt.mouse = 'a'
vim.opt.clipboard:append('unnamedplus')
vim.opt.laststatus = 0
vim.opt.showmode = false
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.cmdheight = 0
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = 'no'
vim.opt.foldcolumn = '0'
vim.opt.fillchars:append({ eob = ' ' })

function _G.tuim_ensure_terminal()
    local buf = vim.api.nvim_get_current_buf()
    local job = vim.bo[buf].buftype == 'terminal' and vim.b[buf].terminal_job_id or nil
    if not job or vim.fn.jobwait({ job }, 0)[1] ~= -1 then
        local exited_terminal = vim.bo[buf].buftype == 'terminal'
        vim.cmd('enew')
        if exited_terminal and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
        vim.cmd('terminal')
    end
    vim.cmd('startinsert')
end

local function notify_win_positions()
    local windows = {}
    local current = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local config = vim.api.nvim_win_get_config(win)
            if config.relative == "" then
                local pos = vim.api.nvim_win_get_position(win)
                local buf = vim.api.nvim_win_get_buf(win)
                local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
                table.insert(windows, {
                    id = win,
                    row = pos[1],
                    col = pos[2],
                    width = vim.api.nvim_win_get_width(win),
                    height = vim.api.nvim_win_get_height(win),
                    active = win == current,
                    name = name == "" and "Terminal" or name,
                })
            end
        end
    end
    vim.rpcnotify(1, "tuim_win_positions", windows)
end

vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "WinLeave", "TermOpen" }, {
    group = vim.api.nvim_create_augroup("TuimTerminalFrontend", { clear = true }),
    callback = function() vim.schedule(notify_win_positions) end,
})
-- Let the synchronous nvim_exec_lua setup response reach Tuim before sending
-- notifications that are consumed by the main event loop.
vim.defer_fn(notify_win_positions, 10)
