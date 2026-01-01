local M = {}

-- find_repo_root will try to find the .jj directory in the parent directories of the given path
M._find_repo_root = function(path)
  -- try to find the .jj folder
  local found = vim.fs.find(".jj", { upward = true, path = search_path, type = "directory" })[1]
  -- return the repo path
  return found and vim.fs.dirname(found)
end

return M
