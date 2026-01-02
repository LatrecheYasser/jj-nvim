local M = {}

local ns = vim.api.nvim_create_namespace("jj-nvim-diff")
local changes_line_matcher = "^@@ %-%d+,?%d* %+(%d+),?%d* @@"

-- highlight group names
local HL_ADD = "JJDiffAdd"
local HL_CHANGE = "JJDiffChange"
local HL_DELETE = "JJDiffDelete"

local config = {
  -- the events to update the diff highlights
  update_events = { "BufEnter", "BufWritePost" },

  -- enable/disable features
  enable_highlights = true,  -- show line background highlighting
  enable_signs = true,       -- show signs in the sign column

  -- sign characters used to display the diff for additions and changes
  sign = "▎",

  -- custom colors extracted from the colorscheme,
  -- to set a color you can use something like this:
  -- add = { bg = "#1a3320", fg = "#8fd19e" },
  add = { link = "DiffAdd" },
  change = { link = "DiffChange" },
  delete = { link = "DiffDelete" },
}

local binary = "jj"

local function set_highlights()
  vim.api.nvim_set_hl(0, HL_ADD, config.add or {})
  vim.api.nvim_set_hl(0, HL_CHANGE, config.change or {})
  vim.api.nvim_set_hl(0, HL_DELETE, config.delete or {})
end

-- find_repo_root will try to find the .jj directory in the parent directories of the given path
local function find_repo_root(path)
  -- try to find the .jj folder
  local found = vim.fs.find(".jj", { upward = true, path = vim.fs.dirname(path), type = "directory" })[1]
  -- return the repo path
  return found and vim.fs.dirname(found)
end

-- parse_changes will parse the diff lines and return the added, changed, and removed lines
local function parse_changes(lines)
  local added_lines, updated_lines, removed_lines = {}, {}, {}
  local in_diff, line_number = false, 0
  local pending_removals = 0 -- track how many deletions without matching additions => updates

  for _, line in ipairs(lines) do
    local start = line:match(changes_line_matcher)
    if start then
      -- commit any pending removals from previous hunk
      if pending_removals > 0 then
        table.insert(removed_lines, math.max(line_number, 1))
      end
      in_diff, line_number, pending_removals = true, tonumber(start), 0
    elseif in_diff then
      local c = line:sub(1, 1)
      if c == "+" then
        if pending_removals > 0 then
          -- this is a modification (had `-` before), not pure addition
          table.insert(updated_lines, line_number)
          pending_removals = pending_removals - 1
        else
          -- pure addition
          table.insert(added_lines, line_number)
        end
        line_number = line_number + 1
      elseif c == "-" then
        pending_removals = pending_removals + 1
      elseif c == " " then
        -- context line: commit any remaining pending removals as actual deletions
        if pending_removals > 0 then
          table.insert(removed_lines, line_number)
          pending_removals = 0
        end
        line_number = line_number + 1
      else
        -- other line (diff header, etc): commit pending removals
        if pending_removals > 0 then
          table.insert(removed_lines, line_number)
          pending_removals = 0
        end
      end
    end
  end

  -- commit any remaining pending removals at end of diff
  if pending_removals > 0 then
    table.insert(removed_lines, line_number)
  end

  return added_lines, updated_lines, removed_lines
end

local function mark(bufnr, line_count, lnum, hl)
  lnum = math.min(math.max(lnum, 1), line_count)

  local opts = { priority = 100 }

  if config.enable_highlights and hl ~= HL_DELETE then
    opts.line_hl_group = hl
  end

  if config.enable_signs then
    opts.sign_text = config.sign
    opts.sign_hl_group = hl
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, opts)
end

local function apply_marks(bufnr, added_lines, updated_lines, removed_lines)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if line_count == 0 then return end

  -- make sure we can display signs
  if config.enable_signs then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].signcolumn = "yes:1"
    end
  end

  for _, l in ipairs(added_lines) do mark(bufnr, line_count, l, HL_ADD) end
  for _, l in ipairs(updated_lines) do mark(bufnr, line_count, l, HL_CHANGE) end
  for _, l in ipairs(removed_lines) do mark(bufnr, line_count, l, HL_DELETE) end
end

local function refresh(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local path = vim.api.nvim_buf_get_name(bufnr)
  -- the buffer should be a normal file, and we also should have a path
  if bt ~= "" or path == "" then return end

  local root = find_repo_root(path)
  if not root then return end

  -- extracts the relative path of the file from the root.
  local rel = path:sub(#root + 2)
  local lines = vim.fn.systemlist({ binary, "-R", root, "diff", "--git", "--", rel })

  if vim.v.shell_error ~= 0 or #lines == 0 then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    return
  end

  apply_marks(bufnr, parse_changes(lines))
end

M.refresh = refresh

function M.setup(opts, jj_binary)
  config = vim.tbl_deep_extend("force", config, opts or {})
  binary = jj_binary or binary
  set_highlights()

  local group = vim.api.nvim_create_augroup("JJDiff", { clear = true })
  vim.api.nvim_create_autocmd(config.update_events, {
    group = group,
    callback = function(e) refresh(e.buf) end,
  })

  vim.api.nvim_create_user_command("JJDiffRefresh", function()
    refresh(0)
  end, { desc = "Refresh jj diff highlights" })
end

return M

