local M = {}

-- find_repo_root will try to find the .jj directory in the parent directories of the given path
M._find_repo_root = function(path)
  -- try to find the .jj folder
  local found = vim.fs.find(".jj", { upward = true, path = path, type = "directory" })[1]
  -- return the repo path
  return found and vim.fs.dirname(found)
end

-- Create a centered floating window with ANSI color support
function M.create_float(lines, width, title, footer)
  local height = math.min(#lines, 20)

  -- Calculate max width from content (strip ANSI codes for width calculation)
  for _, line in ipairs(lines) do
    local plain = line:gsub("\027%[[%d;]*m", "") -- strip ANSI codes
    width = math.max(width, vim.fn.strdisplaywidth(plain) + 4)
  end
  width = math.min(width, vim.o.columns - 4)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = footer or " <CR>:select  q:close ",
    footer_pos = "center",
  })

  -- Use nvim_open_term to render ANSI escape codes (colors)
  local term = vim.api.nvim_open_term(buf, {})
  local content = table.concat(lines, "\r\n")
  vim.api.nvim_chan_send(term, content)

  -- Exit terminal mode to allow normal keymaps to work
  vim.cmd("stopinsert")

  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  return buf, win
end

-- Close a floating window
function M.close_float(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

-- Get the current line index in a window (1-indexed)
function M.get_cursor_line(win)
  return vim.api.nvim_win_get_cursor(win)[1]
end

-- Create a side panel floating window with terminal colors (to the right of a parent window)
function M.create_side_panel(lines, parent_win, title)
  local parent_config = vim.api.nvim_win_get_config(parent_win)

  -- Handle col/row which might be tables like {[false] = 0} in some neovim versions
  local parent_width = parent_config.width or 60
  local parent_col = type(parent_config.col) == "number" and parent_config.col or 0
  local parent_row = type(parent_config.row) == "number" and parent_config.row or 0

  -- Calculate available space
  local available_width = vim.o.columns - parent_width - parent_col - 6
  if available_width < 20 then
    -- Not enough space on the right, put it below instead
    parent_row = parent_row + (parent_config.height or 10) + 2
    parent_col = parent_col
    available_width = vim.o.columns - 4
  end

  local width = math.max(40, math.min(100, available_width))
  local height = math.max(1, math.min(#lines, 30))

  local col = parent_col + parent_width + 2
  if col + width > vim.o.columns then
    col = math.max(0, vim.o.columns - width - 2)
  end

  -- Create buffer and open terminal to render ANSI colors
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = parent_row - (parent_config.height /2 ),
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    focusable = false,
  })

  -- Use nvim_open_term to render ANSI escape codes (colors)
  local term = vim.api.nvim_open_term(buf, {})
  local content = table.concat(lines, "\r\n")
  vim.api.nvim_chan_send(term, content)

  return buf, win
end

return M
