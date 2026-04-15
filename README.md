# jj-nvim

A Neovim plugin for [Jujutsu (jj)](https://github.com/martinvonz/jj) version control, providing inline diff highlights, a diff preview with undo, a bookmark picker, and a changed files panel.

## Features

### Diff Highlights

Automatically highlights changed lines in the sign column and buffer:

- **Added lines** — shown with a green sign
- **Updated lines** — shown with an orange/yellow sign and line highlight
- **Removed lines** — shown with a `_` marker at the deletion point
- **Overlapping changes** (update + removal on the same line) — shown with a combined `▎_` sign

Highlights refresh automatically on `BufEnter` and `BufWritePost`.

### Show Old Version (Diff Preview)

Use `:JJShowDiff` (or the default keymap `<leader>jjd`) on any changed line to open a floating window showing the previous content:

- **Updated lines** — displays old content highlighted in orange
- **Removed lines** — displays removed content highlighted in red
- **Update + removal overlap** — displays both, separated visually
- **Added lines** — no preview (nothing to show)

While the preview is open, press `u` to **revert** the change (restores old content or re-inserts removed lines). The preview closes automatically when you move the cursor.

### Changed Files Panel

Use `:JJStatus` (or `<leader>jjs`) to open a floating panel showing all changed files in the current working copy. From the panel:

- `<CR>` — open the file under the cursor
- `d` — show the diff for the file in a side panel
- `q` / `<Esc>` — close the panel

### Bookmark Picker

Use `:JJBookmarks` (or `<leader>jjb`) to open a floating picker listing all jj bookmarks. From the picker:

- `<CR>` — create a new change on the selected bookmark
- `l` — show the commit log for the selected bookmark in a side panel
- `q` / `<Esc>` — close the picker

## Requirements

- Neovim >= 0.10
- [jj](https://github.com/martinvonz/jj) installed and available in `$PATH`
- Must be inside a jj repository

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "LatrecheYasser/nvim-jj",
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "LatrecheYasser/nvim-jj",
  config = function()
    require("jj-nvim").setup()
  end,
}
```

### Manual

Clone the repository into your Neovim packages directory:

```bash
git clone https://github.com/LatrecheYasser/nvim-jj ~/.local/share/nvim/site/pack/plugins/start/nvim-jj
```

Then in your `init.lua`:

```lua
require("jj-nvim").setup()
```

## Configuration

All options are optional. Below are the defaults:

```lua
require("jj-nvim").setup({
  -- Path to the jj binary
  binary = "jj",

  -- Diff highlight options
  diff_highlight = {
    -- Events that trigger a diff refresh
    update_events = { "BufEnter", "BufWritePost" },

    -- Enable/disable features
    enable_highlights = true,  -- line background highlighting
    enable_signs = true,       -- sign column markers

    -- Sign character for additions and changes
    sign = "▎",

    -- Highlight colors (link to built-in groups or set custom colors)
    -- Example custom: add = { bg = "#1a3320", fg = "#8fd19e" }
    add = { link = "DiffAdd" },
    change = { link = "DiffChange" },
    delete = { link = "DiffDelete" },
  },

  -- Keymaps (set to false to disable all keymaps)
  keymaps = {
    bookmarks = "<leader>jjb",
    show_diff = "<leader>jjd",
    status = "<leader>jjs",
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:JJDiffRefresh` | Manually refresh diff highlights for the current buffer |
| `:JJShowDiff` | Show the old version of the line under the cursor |
| `:JJBookmarks` | Open the bookmark picker |
| `:JJStatus` | Show changed files panel |

## Keymaps

| Keymap | Mode | Description |
|---|---|---|
| `<leader>jjb` | Normal | Open bookmark picker |
| `<leader>jjd` | Normal | Show old version of current line |
| `<leader>jjs` | Normal | Show changed files panel |
| `u` | Normal | Revert change (only while diff preview is open) |

## License

MIT
