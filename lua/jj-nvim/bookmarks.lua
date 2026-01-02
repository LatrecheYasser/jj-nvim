local M = {}
local utils = require("jj-nvim.utils")

local repo_root = nil

-- Get log for a bookmark (limited to  30 to avoid performance issues)
local function get_bookmark_log(binary, bookmark_name,limit, with_colors)
    limit = limit or 30
    limit = math.min(limit, 30)
    with_colors = with_colors or false
    local color_flag = with_colors and "--color=always" or "--color=never"
  -- execute jj -R <repo_root> log --color=always -n 30 -r '::<bookmark_name> | <bookmark_name>::@'
  -- to get the logs for the bookmark's path until the revision @
  local rev = "::" .. bookmark_name .. " | " .. bookmark_name .. "::@"
  local lines = vim.fn.systemlist({
    binary, "-R", repo_root, "log", color_flag, "-n", limit, "-r", rev,
  })

  if vim.v.shell_error ~= 0 then
    return nil
  end
  return lines
end

-- Get list of bookmarks from jj
local function get_bookmarks(binary)
    local lines = vim.fn.systemlist({ binary, "-R", repo_root, "bookmark", "list", "--color=always" })
    if vim.v.shell_error ~= 0 then
      vim.notify("[jj-nvim] Failed to list bookmarks", vim.log.levels.ERROR)
      return nil
    end
  
    local bookmarks = {}
    for _, line in ipairs(lines) do
      -- bookmark list format: "name: change_id commit_id description"
      -- extract the name from the colored line
      local plain = line:gsub("\027%[[%d;]*m", "")
      local name = plain:match("^(%S+):")
      -- get the last rev
      local last_rev = get_bookmark_log(binary, name, 1,false)
      local last_rev_id = nil
      if last_rev and #last_rev > 0 then
        last_rev_id = vim.split(last_rev[1], "%s+")[2]
      end
  
      if name then
        table.insert(bookmarks, { name = name, display = line, last_rev = last_rev_id })
      end
    end
  
    return bookmarks
  end

-- Show bookmark picker and create new change on selected bookmark
function M.pick(binary, root, on_complete)
  repo_root = root

  local bookmarks = get_bookmarks(binary)
  if not bookmarks or #bookmarks == 0 then
    vim.notify("[jj-nvim] No bookmarks found", vim.log.levels.INFO)
    return
  end
  -- Prepare display lines
  local lines = {}
  for _, b in ipairs(bookmarks) do
    table.insert(lines, b.display)
  end

  local buf, win = utils.create_float(lines, 60, " JJ Bookmarks ", " <CR>:select  l:log  q:close ")

  -- the side log window
  local log_win = nil

 -- close both the picker and the log window if it's open
  local function close()
    if log_win then utils.close_float(log_win) end
    utils.close_float(win)
  end

  -- select a bookmark and create a new change on it
  local function select()
    local idx = utils.get_cursor_line(win)
    local selected = bookmarks[idx]
    close()

    if selected then
      local result = vim.fn.system({ binary, "-R", root, "new", selected.last_rev })
      if vim.v.shell_error ~= 0 then
        vim.notify("[jj-nvim] Failed to create new change: " .. result, vim.log.levels.ERROR)
      else
        vim.notify("[jj-nvim] Created new change on " .. selected.last_rev .. "(" .. selected.name .. ")", vim.log.levels.INFO)
        vim.cmd("checktime")
        if on_complete then on_complete() end
      end
    end
  end

  -- show the log for a bookmark
  local function show_log()
    local idx = utils.get_cursor_line(win)
    local selected = bookmarks[idx]

    if not selected then return end

    -- Close previous log window if open
    if log_win then
      utils.close_float(log_win)
      log_win = nil
    end

    local log_lines = get_bookmark_log(binary, selected.name, 30, true)

    if log_lines and #log_lines > 0 then
      local ok, _, new_log_win = pcall(utils.create_side_panel, log_lines, win, " Log: " .. selected.name .. " ")
      if ok and new_log_win then
        log_win = new_log_win
      end
    end
  end

  -- Keymaps
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", select, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "l", show_log, opts)
end

return M
