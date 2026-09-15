local M = {}
M.win = nil
M.buf = nil

local themes = {
    "system", "vscode", "matteblack", "tokyonight", "tokyonight-storm", "catppuccin", "gruvbox", "nord",
    "cyberdream", "rose-pine", "kanagawa", "nightfox"
}

function M.open()
    if vim.g.tuim_zen_mode == nil then vim.g.tuim_zen_mode = false end
    if vim.g.tuim_ide_mode == nil then vim.g.tuim_ide_mode = false end
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
        "  " .. get_toggle(vim.o.clipboard:match("unnamedplus")) .. " System Clipboard              [c]",
        "", 
        "  Themes",
    }
    for _, t in ipairs(themes) do 
        table.insert(lines, "  " .. get_toggle(t == current_theme) .. " " .. t .. string.rep(" ", 30 - #t) .. "[t]") 
    end

    if M.win and vim.api.nvim_win_is_valid(M.win) then
        pcall(vim.api.nvim_win_close, M.win, true)
    end

    local height = #lines + 2
    local buf = vim.api.nvim_create_buf(false, true)
    M.buf = buf
    
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor', width = width, height = height,
        row = math.floor((vim.o.lines - height) / 2), col = math.floor((vim.o.columns - width) / 2),
        style = 'minimal', border = 'rounded', title = ' Tuim Settings ', title_pos = 'center',
    })
    M.win = win
    
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
        elseif line:match("System Clipboard") then toggle_clipboard()
        else set_theme() end
    end

    local function do_click()
        vim.cmd("stopinsert")
        handle_click()
    end

    vim.keymap.set({'n', 'v', 'i'}, 'z', function() select_mode("zen") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'i', function() select_mode("ide") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'o', function() select_mode("normal") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'c', toggle_clipboard, { buffer = buf, silent = true })
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
    vim.keymap.set({'n', 'v', 'i'}, 'q', function() pcall(vim.api.nvim_win_close, win, true) M.win = nil end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<Esc>', function() pcall(vim.api.nvim_win_close, win, true) M.win = nil end, { buffer = buf, silent = true })
    
    -- Force normal mode via schedule to override any IDE mode startinsert
    vim.schedule(function() vim.cmd("stopinsert") end)
end

return M
