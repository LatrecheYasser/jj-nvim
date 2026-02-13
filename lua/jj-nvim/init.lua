local M = {}

local bookmarks = require("jj-nvim.bookmarks")
local utils = require("jj-nvim.utils")
local diff = require("jj-nvim.diff")

local config = {
  -- the jj binary path to use
  binary = "jj",

  -- diff highlights configuration
  diff_highlight = diff._config,

  -- keymaps configuration (set to false to disable)
  keymaps = {
    bookmarks = "<leader>jjb",
    show_diff = "<leader>jjd",
  },
}

local repo_root = nil

M.refresh = function()
  diff.refresh(0)
end

function M.bookmarks()
  bookmarks.pick(config.binary, repo_root, function()
    diff.refresh(0)
  end)
end

function M.show_diff()
  diff.show_old_version(0)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  local bufnr = vim.api.nvim_get_current_buf()

  local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local path = vim.api.nvim_buf_get_name(bufnr)
  -- the buffer should be a normal file, and we also should have a path
  if bt ~= "" or path == "" then return end

  repo_root = utils._find_repo_root(path)

  if not repo_root then
    vim.notify("[jj-nvim] Not in a jj repository - " .. path, vim.log.levels.WARN)
    return
  end

  diff.setup(config.diff_highlight, config.binary, repo_root)

  vim.api.nvim_create_user_command("JJDiffRefresh", function()
    M.refresh()
  end, { desc = "Refresh jj diff highlights" })

  vim.api.nvim_create_user_command("JJBookmarks", function()
    M.bookmarks()
  end, { desc = "Show jj bookmarks" })

  vim.api.nvim_create_user_command("JJShowDiff", function()
    M.show_diff()
  end, { desc = "Show old version of changed line" })

  -- Set up keymaps (if not disabled)
  local km = config.keymaps
  if km then
    if km.bookmarks then
      vim.keymap.set("n", km.bookmarks, M.bookmarks, { desc = "JJ: Show bookmarks" })
    end
    if km.show_diff then
      vim.keymap.set("n", km.show_diff, M.show_diff, { desc = "JJ: Show old version of line" })
    end
  end
  M.refresh()
end

return M
