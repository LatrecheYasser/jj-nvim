local M = {}

local diff = require("jj-nvim.diff")

local config = {
  -- the jj binary path to use
  binary = "jj",

  -- diff highlights configuration
  diff_highlight = {
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
}

M.refresh = diff.refresh

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  diff.setup(config.diff_highlight, config.binary)
end

return M
