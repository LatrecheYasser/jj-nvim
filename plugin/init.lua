if vim.g.loaded_jj_nvim then
  return
end

vim.g.loaded_jj_nvim = true

require("jj-nvim").setup()