local M = {}

_G.tuim_show_dashboard = function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'tuim_dashboard'

    local logo = {
        "██╗   ██╗██╗██████╗ ███████╗",
        "██║   ██║██║██╔══██╗██╔════╝",
        "██║   ██║██║██║  ██║█████╗  ",
        "╚██╗ ██╔╝██║██║  ██║██╔══╝  ",
        " ╚████╔╝ ██║██████╔╝███████╗",
        "  ╚═══╝  ╚═╝╚═════╝ ╚══════╝",
        "",
        "Ctrl+N     New File",
        "Space f f  Find File",
    }

    local win_height = vim.api.nvim_win_get_height(0)
    local win_width = vim.api.nvim_win_get_width(0)

    local logo_height = #logo
    local logo_width = 30

    local top_padding = math.floor((win_height - logo_height) / 2)
    if top_padding < 0 then top_padding = 0 end

    local lines = {}
    for i = 1, top_padding do
        table.insert(lines, "")
    end

    for _, line in ipairs(logo) do
        local left_padding = math.floor((win_width - 30) / 2)
        if left_padding < 0 then left_padding = 0 end
        local pad = string.rep(" ", left_padding)
        table.insert(lines, pad .. line)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    
    vim.api.nvim_win_set_buf(0, buf)
    
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.cursorline = false
    vim.wo.cursorcolumn = false
    vim.wo.signcolumn = 'no'
    vim.wo.foldcolumn = '0'
    vim.wo.colorcolumn = ''
    vim.wo.wrap = false
    vim.wo.list = false
end

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.fn.argc() == 0 then
            _G.tuim_show_dashboard()
        end
    end
})
