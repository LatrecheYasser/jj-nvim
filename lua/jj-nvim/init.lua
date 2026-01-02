local M = {}

local diff = require("jj-nvim.diff")

local config = {
  -- the jj binary path to use
  binary = "jj",

  -- diff highlights configuration
  diff_highlight = diff._config,
}

M.refresh = diff.refresh

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  diff.setup(config.diff_highlight, config.binary)
end

return M
