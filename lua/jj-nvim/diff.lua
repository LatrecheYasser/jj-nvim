local M = {}

local ns = vim.api.nvim_create_namespace("jj-nvim-diff")
local ns_preview = vim.api.nvim_create_namespace("jj-nvim-diff-preview")
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

-- module-level state
local binary = "jj"
local repo_root = nil
local buffer_changes = {} -- store changes per buffer for lookup

local function set_highlights()
  vim.api.nvim_set_hl(0, HL_ADD, config.add or {})
  vim.api.nvim_set_hl(0, HL_CHANGE, config.change or {})
  vim.api.nvim_set_hl(0, HL_DELETE, config.delete or {})
end

-- parse_changes will parse the diff lines and return the added, changed, and removed lines
local function parse_changes(lines)
  -- each one will store the start and end line number of the changes, and the content of the change. 
  local added_changes, updated_changes, removed_changes = {}, {}, {}
  
  -- pending changes with start, end and content 
  local pending_removals = { start_line = nil, end_line = nil, contents = {} } -- store content of pending removed lines
  local pending_updates = { start_line = nil, end_line = nil, old_contents = {} , new_contents = {} } -- store content of pending updates
  local pending_additions = { start_line = nil, end_line = nil, contents = {} } -- store content of pending additions
  
  -- commit the pending changes to the changes tables
  local function commit_pending_changes()
    if #pending_removals.contents > 0 then
        table.insert(removed_changes, pending_removals)
        pending_removals = { start_line = nil, end_line = nil, contents = {} }
    end
    if #pending_updates.old_contents > 0 then
        table.insert(updated_changes, pending_updates)
        pending_updates = { start_line = nil, end_line = nil, old_contents = {} , new_contents = {} }
    end 
    if #pending_additions.contents > 0 then
        table.insert(added_changes, pending_additions)
        pending_additions = { start_line = nil, end_line = nil, contents = {} }
    end
end

local in_diff, line_number = false, 0
  for _, line in ipairs(lines) do
    local start = line:match(changes_line_matcher)
    if start then
      in_diff, line_number = true, tonumber(start)
    elseif in_diff then
      local c = line:sub(1, 1)
      local content = line:sub(2) -- line content without +/- prefix

      if c == "+" then
        -- if we have pending removals it means we have an update and it's not really a removal.
        if #pending_removals.contents > 0 then
            if #pending_updates.old_contents == 0 then
                pending_updates.start_line = pending_removals.start_line
            end
            pending_updates.end_line = pending_removals.start_line
            table.insert(pending_updates.old_contents, pending_removals.contents[1])
            table.insert(pending_updates.new_contents, content)
            -- update the pending removal, by incr the start, and remove the first content
            pending_removals.contents = vim.list_slice(pending_removals.contents, 2)
            pending_removals.start_line = pending_removals.start_line + 1
            if #pending_removals.contents == 0 then
                pending_removals = { start_line = nil, end_line = nil, contents = {} }
            end
        else 
            if #pending_additions.contents == 0 then
                pending_additions.start_line = line_number
            end 
            pending_additions.end_line = line_number
            table.insert(pending_additions.contents, content)
            line_number = line_number + 1
        end 
      elseif c == "-" then
        if #pending_removals.contents == 0  then
            pending_removals.start_line = line_number
        end
        table.insert(pending_removals.contents, content)
        pending_removals.end_line = line_number
        line_number = line_number + 1
      elseif c == " " then
        commit_pending_changes()
        line_number = line_number + 1
      end
    end
  end

  commit_pending_changes()

  return {
    added = added_changes,
    updated = updated_changes,
    removed = removed_changes,
  }
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

local function apply_marks(bufnr, changes)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if line_count == 0 then return end

  -- make sure we can display signs
  if config.enable_signs then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].signcolumn = "yes:1"
    end
  end
  print("changes", vim.inspect(changes))
  -- print the changes
  for _, change in ipairs(changes.added) do
    print("added", change.start_line, change.end_line, table.concat(change.contents, "\n"))
  end
  for _, change in ipairs(changes.updated) do
    print("updated", change.start_line, change.end_line, table.concat(change.old_contents, "\n"), table.concat(change.new_contents, "\n"))
  end
  for _, change in ipairs(changes.removed) do
    print("removed", change.start_line, change.end_line, table.concat(change.contents, "\n"))
  end
--   for _, l in ipairs(changes.added.line_numbers) do mark(bufnr, line_count, l, HL_ADD) end
--   for _, l in ipairs(changes.updated.line_numbers) do mark(bufnr, line_count, l, HL_CHANGE) end
--   for _, l in ipairs(changes.removed.line_numbers) do mark(bufnr, line_count, l, HL_DELETE) end
end

local function refresh(bufnr)
  if not repo_root then return end

  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local path = vim.api.nvim_buf_get_name(bufnr)
  -- the buffer should be a normal file, and we also should have a path
  if bt ~= "" or path == "" then return end

  -- extracts the relative path of the file from the root.
  local rel = path:sub(#repo_root + 2)
  local lines = vim.fn.systemlist({ binary, "-R", repo_root, "diff", "--git", "--", rel })

  if vim.v.shell_error ~= 0 or #lines == 0 then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    buffer_changes[bufnr] = nil
    return
  end

  local changes = parse_changes(lines)
  buffer_changes[bufnr] = changes
  apply_marks(bufnr, changes)
end

-- Show the old version of the line under cursor as virtual text
local function show_old_version(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  -- Clear any existing preview
  vim.api.nvim_buf_clear_namespace(bufnr, ns_preview, 0, -1)

  local changes = buffer_changes[bufnr]

  if not changes then
    return
  end

  -- get the current line number 
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local old_content = {}
  local change_type = nil
  local prev_line_number = nil
  -- Check if cursor is on an updated line
  for i, lnum in ipairs(changes.updated.line_numbers) do
    if lnum == cursor_line then
      table.insert(old_content, changes.updated.lines[i])
      change_type = "updated"
      if not prev_line_number then
        prev_line_number = lnum
      elseif lnum == prev_line_number + 1 then
        table.insert(old_content, changes.updated.lines[i])
        prev_line_number = lnum
      else 
        break
      end 
    end
  end

  if not old_content then
    vim.notify("[jj-nvim] No previous version for this line", vim.log.levels.INFO)
    return
  end

  -- Show as virtual text below the current line
  local hl = change_type == "updated" and HL_CHANGE or HL_DELETE
  local prefix = change_type == "updated" and "- " or "✗ "

  vim.api.nvim_buf_set_extmark(bufnr, ns_preview, cursor_line - 1, 0, {
    virt_lines = { { { prefix .. old_content .. "  (press u to revert)", hl } } },
    virt_lines_above = false,
  })

  -- Function to clean up preview and keymap
  local function cleanup()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_preview, 0, -1)
    pcall(vim.keymap.del, "n", "u", { buffer = bufnr })
  end

  -- Set up 'u' keymap to revert the line
  vim.keymap.set("n", "u", function()
    if change_type == "updated" then
      -- Replace current line with old content
      vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line, false, { old_content })
      vim.notify("[jj-nvim] Reverted line to previous version", vim.log.levels.INFO)
    elseif change_type == "removed" then
      -- Insert the removed line at the current position
      vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line - 1, false, { old_content })
      vim.notify("[jj-nvim] Restored removed line", vim.log.levels.INFO)
    end
    cleanup()
  end, { buffer = bufnr, nowait = true, desc = "JJ: Revert to old version" })

  -- Clear on cursor move (but not on 'u' press)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
    buffer = bufnr,
    once = true,
    callback = cleanup,
  })
end

M._config = config
M.refresh = refresh
M.show_old_version = show_old_version

function M.setup(opts, jj_binary, jj_repo_root)
  config = vim.tbl_deep_extend("force", config, opts or {})
  binary = jj_binary or binary
  repo_root = jj_repo_root
  set_highlights()

  -- Create autocommands for auto-refresh
  local group = vim.api.nvim_create_augroup("jj-nvim-diff", { clear = true })

  vim.api.nvim_create_autocmd(config.update_events, {
    group = group,
    callback = function(args)
      refresh(args.buf)
    end,
  })
end

return M
