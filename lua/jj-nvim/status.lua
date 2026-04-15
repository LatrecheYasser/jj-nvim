local M = {}
local utils = require("jj-nvim.utils")

local repo_root = nil

-- Get colored diff output for a file
local function get_file_diff(binary, path)
  local lines = vim.fn.systemlist({ binary, "-R", repo_root, "diff", "--color=always", "--", path })
  if vim.v.shell_error ~= 0 then return nil end
  return lines
end

function M.show(binary, root)
  repo_root = root

  local cwd = vim.fn.getcwd()
  local files = vim.fn.systemlist({ binary, "diff", "--name-only" })
  if vim.v.shell_error ~= 0 then
    vim.notify("[jj-nvim] Failed to get changed files", vim.log.levels.ERROR)
    return
  end

  if #files == 0 then
    vim.notify("[jj-nvim] No changed files", vim.log.levels.INFO)
    return
  end

  -- Build absolute paths and colored display lines
  local abs_paths = {}
  local display = vim.fn.systemlist({ binary, "-R", repo_root, "status", "--color=always" })

  for i, file in ipairs(files) do
    abs_paths[i] = cwd .. "/" .. vim.trim(file)
  end

  -- Map display lines to files by matching filenames
  local file_map = {} -- display line index -> absolute path
  for i, line in ipairs(display) do
    local plain = line:gsub("%c", ""):gsub("\027%[[^%a]*%a", "")
    for j, file in ipairs(files) do
      if plain:find(vim.trim(file), 1, true) then
        file_map[i] = abs_paths[j]
        break
      end
    end
  end

  local buf, win = utils.create_float(display, 60, " JJ Status ", " <CR>:open  d:diff  q:close ")

  local diff_win = nil

  local function close()
    if diff_win then utils.close_float(diff_win) end
    utils.close_float(win)
  end

  local function open()
    local path = file_map[utils.get_cursor_line(win)]
    if not path then return end
    close()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end

  local function show_diff()
    local path = file_map[utils.get_cursor_line(win)]
    if not path then return end

    if diff_win then
      utils.close_float(diff_win)
      diff_win = nil
    end

    local diff_lines = get_file_diff(binary, path)
    if diff_lines and #diff_lines > 0 then
      local _, new_win = utils.create_side_panel(diff_lines, win, " Diff ")
      diff_win = new_win
    end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", open, opts)
  vim.keymap.set("n", "d", show_diff, opts)
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
end

return M
