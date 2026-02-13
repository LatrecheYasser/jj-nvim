local M = {}

local ns = vim.api.nvim_create_namespace("jj-nvim-diff")
local ns_preview = vim.api.nvim_create_namespace("jj-nvim-diff-preview")
local changes_line_matcher = "^@@ %-%d+,?%d* %+(%d+),?%d* @@"

-- highlight group names
local HL_ADD = "JJDiffAdd"
local HL_CHANGE = "JJDiffChange"
local HL_DELETE = "JJDiffDelete"
local HL_DELETE_AND_UPDATE = "JJDiffDeleteAndUpdate"
local HL_DELETE_AND_ADD = "JJDiffDeleteAndAdd"

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
local function parse_changes(bufnr, lines)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  -- each one will store the start and end line number of the changes, and the content of the change. 
  local added_changes, updated_changes, removed_changes = {}, {}, {}
  
  -- pending changes with start, end and content 
  local pending_removals = { start_line = nil, end_line = nil, contents = {} } -- store content of pending removed lines
  local pending_updates = { start_line = nil, end_line = nil, old_contents = {} , new_contents = {} } -- store content of pending updates
  local pending_additions = { start_line = nil, end_line = nil} -- store content of pending additions
  
  -- commit the pending changes to the changes tables
  local function commit_pending_changes()
    if #pending_removals.contents > 0 then
        pending_removals.start_line = math.min(math.max(pending_removals.start_line-1, 1), line_count)
        pending_removals.end_line = math.min(pending_removals.end_line, line_count)
        vim.inspect("commit pending removals", pending_removals)
        table.insert(removed_changes, pending_removals)
        pending_removals = { start_line = nil, end_line = nil, contents = {} }
    end
    if #pending_updates.old_contents > 0 then
        table.insert(updated_changes, pending_updates)
        pending_updates = { start_line = nil, end_line = nil, old_contents = {} , new_contents = {} }
    end 
    if pending_additions.start_line then
        table.insert(added_changes, pending_additions)
        pending_additions = { start_line = nil, end_line = nil, contents = {} }
    end
end

local in_diff, line_number = false, 0
  for _, line in ipairs(lines) do
    local start = line:match(changes_line_matcher)
    if start then
      in_diff, line_number = true, tonumber(start)
      if line_number < 1 then
        line_number = 1
      end
    elseif in_diff then
      local c = line:sub(1, 1)
      local content = line:sub(2) -- line content without +/- prefix

      if c == "+" then
        -- if we have pending removals it means we have an update and it's not really a removal.
        if #pending_removals.contents > 0 then
            if #pending_updates.old_contents == 0 then
                pending_updates.start_line = pending_removals.start_line
            end
            pending_updates.end_line = line_number
            table.insert(pending_updates.old_contents, pending_removals.contents[1])
            table.insert(pending_updates.new_contents, content)
            -- update the pending removal, by incr the start, and remove the first content
            pending_removals.contents = vim.list_slice(pending_removals.contents, 2)
            pending_removals.start_line = line_number + 1   
            pending_removals.end_line = pending_removals.start_line + #pending_removals.contents - 1
            if #pending_removals.contents == 0 then
                pending_removals = { start_line = nil, end_line = nil, contents = {} }
            end
        else 
            if not pending_additions.start_line then
                pending_additions.start_line = line_number
            end 
            pending_additions.end_line = line_number
        end 
        line_number = line_number + 1
      elseif c == "-" then
        if #pending_removals.contents == 0  then
            pending_removals.start_line = line_number
        end
        table.insert(pending_removals.contents, content)
        pending_removals.end_line = pending_removals.start_line + #pending_removals.contents - 1
      elseif c == " " then
        commit_pending_changes()
        line_number = line_number + 1
      end
    end
  end

  commit_pending_changes()
  -- find overlaps between the removals and the updates and the additions
  local removal_overlaps_updates = {}
  for i, removal in ipairs(removed_changes) do
    for _, update in ipairs(updated_changes) do
      if removal.start_line <= update.end_line and removal.end_line >= update.start_line then
        removal_overlaps_updates[removal.start_line] = { update = update, removal = removal }
      end
    end
  end

  local removal_overlaps_additions = {}
  for i, removal in ipairs(removed_changes) do
    for _, addition in ipairs(added_changes) do
      if removal.start_line <= addition.end_line and removal.end_line >= addition.start_line then
        removal_overlaps_additions[removal.start_line] = { addition = addition, removal = removal }
      end
    end
  end
  return {
    added = added_changes,
    updated = updated_changes,
    removed = removed_changes,
    removal_overlaps_updates = removal_overlaps_updates,
    removal_overlaps_additions = removal_overlaps_additions,
  }
end

local function mark(bufnr, lnum, hl)

  local opts = { priority = 100 }

  if config.enable_highlights and hl ~= HL_DELETE then
    opts.line_hl_group = hl
  end

  if config.enable_signs then
    if hl == HL_DELETE_AND_UPDATE or hl == HL_DELETE_AND_ADD then 
      opts.sign_text = config.sign .. "_"
    elseif hl == HL_DELETE then
      opts.sign_text = " _"
    else 
      opts.sign_text = config.sign
    end

    if hl == HL_DELETE_AND_UPDATE then
      opts.sign_hl_group = HL_CHANGE
    elseif hl == HL_DELETE_AND_ADD then
      opts.sign_hl_group = HL_ADD
    else
      opts.sign_hl_group = hl
    end
  end
  print("marking line ", lnum-1, " with hl ", hl, opts.sign_text)
  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum-1, 0, opts)
end

local function apply_marks(bufnr, changes)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if line_count == 0 then return end
  -- print(vim.inspect(changes))
  -- make sure we can display signs
  if config.enable_signs then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].signcolumn = "yes:1"
    end
  end
  
  -- Apply marks
  for _, change in ipairs(changes.added) do
    for i = change.start_line, change.end_line do
      mark(bufnr, i, HL_ADD)
    end
  end
  
  for _, change in ipairs(changes.updated) do
    for i = change.start_line, change.end_line do
      mark(bufnr, i, HL_CHANGE)
    end
  end

  for _, removal in ipairs(changes.removed) do
    mark(bufnr, removal.start_line, HL_DELETE)
  end

  for lnum, _ in pairs(changes.removal_overlaps_updates) do
    mark(bufnr, lnum, HL_DELETE_AND_UPDATE)
  end

  for lnum, _ in pairs(changes.removal_overlaps_additions) do
    mark(bufnr, lnum, HL_DELETE_AND_ADD)
  end
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

  local changes = parse_changes(bufnr, lines)
  print(vim.inspect(changes))
  buffer_changes[bufnr] = changes
  apply_marks(bufnr, changes)
end

-- checks if the line number is in the changes table and returns element of the change
-- if line_count is provided, clamp the change bounds to it (for removals in shrunk files)
local function check_if_line_in_changes(line_number, changes, line_count)
   for _, change in ipairs(changes) do
    local start_line = change.start_line
    local end_line = change.end_line
    if line_count then
      start_line = math.min(start_line, line_count)
      end_line = math.min(end_line, line_count)
    end
    if line_number >= start_line and line_number <= end_line then
        return change
    end
   end 
   return nil
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
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  -- Added-only: do nothing
  local add_change = check_if_line_in_changes(cursor_line, changes.added, line_count)
  if add_change then return end

  -- Detect update / removal
  local update_change = check_if_line_in_changes(cursor_line, changes.updated, line_count)
  local removal_change = check_if_line_in_changes(cursor_line, changes.removed, line_count)

  -- Check if this update also has an overlapping removal (from overlaps table)
  local overlapping_removal = nil
  if update_change and changes.removal_overlaps_updates then
    for _, pair in pairs(changes.removal_overlaps_updates) do
      if pair.update == update_change then
        overlapping_removal = pair.removal
        break
      end
    end
  end

  -- Build display lines and highlight mapping
  local display_lines = {}
  local highlights = {}
  local title = "Previous"

  if update_change and overlapping_removal then
    title = "Updated + Removed"
    -- old updated lines (orange)
    for _, line in ipairs(update_change.old_contents or {}) do
      table.insert(display_lines, line)
      table.insert(highlights, HL_CHANGE)
    end
    -- spacer
    table.insert(display_lines, "")
    table.insert(highlights, nil)
    -- removed lines (red)
    for _, line in ipairs(overlapping_removal.contents or {}) do
      table.insert(display_lines, line)
      table.insert(highlights, HL_DELETE)
    end
  elseif update_change then
    title = "Updated"
    for _, line in ipairs(update_change.old_contents or {}) do
      table.insert(display_lines, line)
      table.insert(highlights, HL_CHANGE)
    end
  elseif removal_change then
    title = "Removed"
    for _, line in ipairs(removal_change.contents or {}) do
      table.insert(display_lines, line)
      table.insert(highlights, HL_DELETE)
    end
  else
    vim.notify("[jj-nvim] No previous version for this line", vim.log.levels.INFO)
    return
  end

  if #display_lines == 0 then
    vim.notify("[jj-nvim] No previous version for this line", vim.log.levels.INFO)
    return
  end

  -- Create floating window buffer
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, display_lines)
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].filetype = vim.bo[bufnr].filetype -- inherit syntax highlighting

  -- Apply per-line highlights
  for i, hl in ipairs(highlights) do
    if hl then
      vim.api.nvim_buf_add_highlight(float_buf, -1, hl, i - 1, 0, -1)
    end
  end

  -- Calculate window dimensions (align to text column, not sign/number columns)
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local wininfo = vim.fn.getwininfo(win)[1] or { textoff = 0 }
  local textoff = wininfo.textoff or 0  -- columns taken by sign/number/fold columns
  local width = math.max(20, math.min(win_width - textoff, win_width - 2))
  local height = math.min(#display_lines, 15)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- row is 0-based for float

  -- Open floating window
  local float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = "win",
    win = 0,
    row = cursor_row,
    col = textoff,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  -- Apply highlight to the window
  vim.api.nvim_set_option_value("winhl", "Normal:Normal,FloatBorder:FloatBorder", { win = float_win })

  -- Revert logic for 'u'
  local function revert()
    if update_change and overlapping_removal then
      if update_change.old_contents then
        vim.api.nvim_buf_set_lines(bufnr, update_change.start_line - 1, update_change.end_line, false, update_change.old_contents)
      end
      if overlapping_removal.contents then
        vim.api.nvim_buf_set_lines(bufnr, overlapping_removal.start_line - 1, overlapping_removal.start_line - 1, false, overlapping_removal.contents)
      end
      vim.notify("[jj-nvim] Reverted update and restored removed lines", vim.log.levels.INFO)
    elseif update_change then
      if update_change.old_contents then
        vim.api.nvim_buf_set_lines(bufnr, update_change.start_line - 1, update_change.end_line, false, update_change.old_contents)
        vim.notify("[jj-nvim] Reverted updated lines", vim.log.levels.INFO)
      end
    elseif removal_change then
      if removal_change.contents then
        vim.api.nvim_buf_set_lines(bufnr, removal_change.start_line - 1, removal_change.start_line - 1, false, removal_change.contents)
        vim.notify("[jj-nvim] Restored removed lines", vim.log.levels.INFO)
      end
    end
  end

  -- Function to clean up preview and keymap
  local function cleanup()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    if vim.api.nvim_buf_is_valid(float_buf) then
      vim.api.nvim_buf_delete(float_buf, { force = true })
    end
    pcall(vim.keymap.del, "n", "u", { buffer = bufnr })
  end

  -- Set up 'u' keymap to revert the line
  vim.keymap.set("n", "u", function()
    revert()
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
