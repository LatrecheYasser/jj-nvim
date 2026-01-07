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
local function parse_changes(lines)
  -- each one will store the start and end line number of the changes, and the content of the change. 
  local added_changes, updated_changes, removed_changes = {}, {}, {}
  
  -- pending changes with start, end and content 
  local pending_removals = { start_line = nil, end_line = nil, contents = {} } -- store content of pending removed lines
  local pending_updates = { start_line = nil, end_line = nil, old_contents = {} , new_contents = {} } -- store content of pending updates
  local pending_additions = { start_line = nil, end_line = nil} -- store content of pending additions
  
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

  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, opts)
end

local function apply_marks(bufnr, changes)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if line_count == 0 then return end
  print(vim.inspect(changes))
  -- make sure we can display signs
  if config.enable_signs then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].signcolumn = "yes:1"
    end
  end
  -- Build sets of lines for each change type
  local added_lines = {}
  local updated_lines = {}
  
  for _, change in ipairs(changes.added) do
    for i = change.start_line, change.end_line do
      added_lines[i] = true
    end
  end
  
  for _, change in ipairs(changes.updated) do
    for i = change.start_line, change.end_line do
      updated_lines[i] = true
    end
  end
  
  -- Find where removal anchors overlap with updates or additions
  local delete_and_update = {}  -- lines with both delete and update
  local delete_and_add = {}     -- lines with both delete and addition
  local delete_only = {}        -- lines with only delete
  
  for _, removal in ipairs(changes.removed) do
    -- anchor removal at start_line - 1 (the line before the gap)
    local anchor = math.max(1, math.min(removal.start_line - 1, line_count))
    removal._anchor = anchor
    
    if updated_lines[anchor] then
      table.insert(delete_and_update, anchor)
    elseif added_lines[anchor] then
      table.insert(delete_and_add, anchor)
    else
      table.insert(delete_only, anchor)
    end
  end
  
  -- Apply marks
  for _, change in ipairs(changes.added) do
    for i = change.start_line, change.end_line do
      mark(bufnr, line_count, i, HL_ADD)
    end
  end
  
  for _, change in ipairs(changes.updated) do
    for i = change.start_line, change.end_line do
      mark(bufnr, line_count, i, HL_CHANGE)
    end
  end
  
  -- Mark delete-only lines (don't double-mark lines with updates/adds)
  for _, lnum in ipairs(delete_only) do
    mark(bufnr, line_count, lnum, HL_DELETE)
  end

  for _, lnum in ipairs(delete_and_update) do
    mark(bufnr, line_count, lnum, HL_DELETE_AND_UPDATE)
  end

  for _, lnum in ipairs(delete_and_add) do
    mark(bufnr, line_count, lnum, HL_DELETE_AND_ADD)
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

  local changes = parse_changes(lines)
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
  local is_removal = false
  -- for removals, clamp to line_count since file may have shrunk
  local change = check_if_line_in_changes(cursor_line, changes.removed, line_count)
  if change then
    is_removal = true
  else 
    change = check_if_line_in_changes(cursor_line, changes.updated)
    if change then
      is_update = true
    end
  end

  if not change then
    vim.notify("[jj-nvim] No previous version for this line", vim.log.levels.INFO)
    return
  end

  -- Show as floating window below the cursor
  local hl = is_removal and HL_DELETE or HL_CHANGE
  local contents = is_removal and change.contents or change.old_contents

  -- Create floating window buffer
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, contents)
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].filetype = vim.bo[bufnr].filetype -- inherit syntax highlighting

  -- Calculate window dimensions (full width of current window)
  local win_width = vim.api.nvim_win_get_width(0)
  local width = win_width - 2 -- account for border
  local height = math.min(#contents, 10)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]

  -- Open floating window
  local float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = "win",
    win = 0,
    row = cursor_row,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = is_removal and " Removed " or " Previous ",
    title_pos = "center",
  })

  -- Apply highlight to the window
  vim.api.nvim_set_option_value("winhl", "Normal:" .. hl .. ",FloatBorder:" .. hl, { win = float_win })

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
