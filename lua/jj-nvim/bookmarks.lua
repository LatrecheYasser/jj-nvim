local M = {}

local config = {
  -- the jj binary path to use
  binary = "jj",
}

local repo_root = nil
-- Get list of bookmarks from jj
local function get_bookmarks(binary)
  local lines = vim.fn.systemlist({ binary, "-R", repo_root, "bookmark", "list" })
  if vim.v.shell_error ~= 0 then
    vim.notify("[jj-nvim] Failed to list bookmarks", vim.log.levels.ERROR)
    return nil
  end

  local bookmarks = {}
  for _, line in ipairs(lines) do
    -- bookmark list format: "name: change_id commit_id description"
    local name = line:match("^(%S+):")
    if name then
      table.insert(bookmarks, { name = name, display = line })
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

  vim.ui.select(bookmarks, {
    prompt = "Select bookmark to create new change on:",
    format_item = function(item) return item.display end,
  }, function(selected)
    if not selected then return end

    -- Create new change on top of the selected bookmark
    local result = vim.fn.system({ binary, "-R", root, "new", selected.name })
    if vim.v.shell_error ~= 0 then
      vim.notify("[jj-nvim] Failed to create new change: " .. result, vim.log.levels.ERROR)
    else
      vim.notify("[jj-nvim] Created new change on " .. selected.name, vim.log.levels.INFO)
      vim.cmd("checktime")
      if on_complete then on_complete() end
    end
  end)
end

return M

