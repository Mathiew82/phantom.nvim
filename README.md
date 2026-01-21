# 👻 phantom.nvim

Minimal session manager for Neovim with a floating UI.

Phantom lets you manage sessions from a single window:

- List sessions
- Load sessions (with buffer wipe)
- Save current session
- Delete sessions

No commands to remember.  
One key. One UI.

---

## Features

- Single floating interface
- Save / load / delete from the same window
- Buffer wipe before loading (no mixing)
- Cursor restricted to session entries
- Nerd Font icons (optional, auto-detects)
- Minimal dependencies (pure Lua)
- Works with lazy.nvim
- Safe filename validation

---

## Installation (Lazy.nvim / LazyVim)

```lua
{
  "Mathiew82/phantom.nvim",
  config = function()
    require("phantom").setup()
  end,
}
```
