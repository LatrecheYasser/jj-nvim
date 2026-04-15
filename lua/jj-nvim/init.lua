local M = {}

local bookmarks = require("jj-nvim.bookmarks")
local diff = require("jj-nvim.diff")
local status = require("jj-nvim.status")

local config = {
  -- the jj binary path to use
  binary = "jj",

  -- diff highlights configuration
  diff_highlight = diff._config,

  -- keymaps configuration (set to false to disable)
  keymaps = {
    bookmarks = "<leader>jjb",
    show_diff = "<leader>jjd",
    status = "<leader>jjs",
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

function M.status()
  status.show(config.binary, repo_root)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  local root = vim.fn.system({ config.binary, "root" })
  if vim.v.shell_error ~= 0 then return end
  repo_root = vim.trim(root)

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

  vim.api.nvim_create_user_command("JJStatus", function()
    M.status()
  end, { desc = "Show changed files" })

  -- Set up keymaps (if not disabled)
  local km = config.keymaps
  if km then
    if km.bookmarks then
      vim.keymap.set("n", km.bookmarks, M.bookmarks, { desc = "JJ: Show bookmarks" })
    end
    if km.show_diff then
      vim.keymap.set("n", km.show_diff, M.show_diff, { desc = "JJ: Show old version of line" })
    end
    if km.status then
      vim.keymap.set("n", km.status, M.status, { desc = "JJ: Show changed files" })
    end
  end
  M.refresh()
end

return M
