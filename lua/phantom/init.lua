local M = {}

local defaults = {
  session_dir = vim.fn.stdpath("state") .. "/sessions",
  notify = true,
  wipe_on_load = true,

  keymaps = {
    list = "<leader>sls",
  },

  float = {
    border = "rounded",
    width = 60,
    height = 16,
    title = " PHANTOM ",
  },
}

local state = {
  opts = nil,
  float = { win = nil, buf = nil },
  sessions = {},
  list = { first = nil, last = nil }, -- line range of session entries inside the float
}

local function merge_opts(user)
  return vim.tbl_deep_extend("force", {}, defaults, user or {})
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function notify(msg, level)
  if not state.opts.notify then return end
  vim.notify(msg, level or vim.log.levels.INFO, { title = "phantom" })
end

local function safe_cmd(cmd)
  pcall(vim.api.nvim_command, cmd)
end

local function reset_buffers_and_ui()
  safe_cmd("silent! tabonly")
  safe_cmd("silent! only")
  safe_cmd("silent! %bwipeout!")
  safe_cmd("silent! enew")
end

-- Strict: only trims + removes leading dots. Does NOT "fix" invalid characters.
local function normalize_name(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("^%.*", "") -- avoid hidden/weird ".foo"
  return name
end

local function session_path_from_name(name)
  return state.opts.session_dir .. "/" .. name .. ".vim"
end

local function read_sessions()
  ensure_dir(state.opts.session_dir)

  local files = {}
  for name, t in vim.fs.dir(state.opts.session_dir) do
    if t == "file" and name:match("%.vim$") then
      table.insert(files, name)
    end
  end
  table.sort(files)
  return files
end

local function close_float()
  if state.float.win and vim.api.nvim_win_is_valid(state.float.win) then
    vim.api.nvim_win_close(state.float.win, true)
  end
  state.float.win, state.float.buf = nil, nil
end

local function clamp_cursor_to_sessions()
  local win = state.float.win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  if not (state.list.first and state.list.last) then return end

  local row = vim.api.nvim_win_get_cursor(win)[1]
  if row < state.list.first then
    vim.api.nvim_win_set_cursor(win, { state.list.first, 0 })
  elseif row > state.list.last then
    vim.api.nvim_win_set_cursor(win, { state.list.last, 0 })
  end
end

local function render_float()
  local buf = state.float.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

  vim.bo[buf].modifiable = true

  local lines = {}

  if #state.sessions == 0 then
    state.list.first, state.list.last = nil, nil
    lines = {
      ("Dir: %s"):format(state.opts.session_dir),
      "",
      "󰆓 Sessions:",
      "───────────",
      "No sessions found.",
      "",
      " Keys:",
      "s         Save current session",
      "r         Refresh",
      "q / Esc   Close",
    }
  else
    lines = {
      ("Dir: %s"):format(state.opts.session_dir),
      "",
      "󰆓 Sessions:",
      "───────────",
    }

    state.list.first = #lines + 1
    for i, f in ipairs(state.sessions) do
      lines[#lines + 1] = ("%2d  %s"):format(i, f)
    end
    state.list.last = #lines

    lines[#lines + 1] = ""
    lines[#lines + 1] = " Keys:"
    lines[#lines + 1] = "Enter     Load (wipe buffers first)"
    lines[#lines + 1] = "s         Save current session"
    lines[#lines + 1] = "d         Delete selected session"
    lines[#lines + 1] = "r         Refresh"
    lines[#lines + 1] = "q / Esc   Close"
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function get_selected_filename()
  local win = state.float.win
  local buf = state.float.buf
  if not (win and buf) then return nil end

  local row = vim.api.nvim_win_get_cursor(win)[1]
  local line = (vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or "")
  local fname = line:match("^%s*%d+%s+(.*%.vim)%s*$")
  return fname
end

local function load_filename(fname)
  local path = state.opts.session_dir .. "/" .. fname
  if vim.fn.filereadable(path) == 0 then
    notify("Session not found: " .. path, vim.log.levels.WARN)
    return
  end

  if state.opts.wipe_on_load then
    reset_buffers_and_ui()
  end

  safe_cmd("silent! source " .. vim.fn.fnameescape(path))
  notify("Session loaded: " .. fname)
end

local function delete_filename(fname)
  local path = state.opts.session_dir .. "/" .. fname
  if vim.fn.filereadable(path) == 0 then
    notify("Session not found: " .. path, vim.log.levels.WARN)
    return
  end

  local ok, err = os.remove(path)
  if ok then
    notify("Session deleted: " .. fname)
  else
    notify("Failed to delete session: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function save_prompt()
  ensure_dir(state.opts.session_dir)

  vim.ui.input({ prompt = "Session name: " }, function(input)
    if input == nil then return end

    local name = normalize_name(input)
    if name == "" then
      notify("Session name cannot be empty.", vim.log.levels.WARN)
      return
    end

    if #name < 2 then
      notify("Session name too short.", vim.log.levels.WARN)
      return
    end

    if not name:match("^[%w_-]+$") then
      notify("Only letters, numbers, _ and - allowed.", vim.log.levels.WARN)
      return
    end

    local path = session_path_from_name(name)
    local exists = vim.fn.filereadable(path) == 1

    local function do_save()
      safe_cmd("silent! mksession! " .. vim.fn.fnameescape(path))
      notify("Session saved: " .. name .. ".vim")
      state.sessions = read_sessions()
      render_float()
      clamp_cursor_to_sessions()
    end

    if exists then
      vim.ui.select({ "No", "Yes" }, { prompt = "Session exists. Overwrite?" }, function(choice)
        if choice == "Yes" then
          do_save()
        else
          notify("Save cancelled.")
        end
      end)
    else
      do_save()
    end
  end)
end

function M.open()
  -- If already open, do nothing (close with Esc / q).
  if state.float.win and vim.api.nvim_win_is_valid(state.float.win) then
    return
  end

  state.sessions = read_sessions()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "phantom://sessions")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local o = state.opts.float
  local width = o.width
  local height = o.height
  local ui = vim.api.nvim_list_uis()[1]
  local col = math.floor((ui.width - width) / 2)
  local row = math.floor((ui.height - height) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    border = o.border,
    title = o.title,
    title_pos = "center",
  })

  state.float.win, state.float.buf = win, buf
  render_float()

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  local function bmap(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  bmap("q", close_float, "Close")
  bmap("<Esc>", close_float, "Close")

  bmap("r", function()
    state.sessions = read_sessions()
    render_float()
    clamp_cursor_to_sessions()
  end, "Refresh")

  bmap("s", function()
    save_prompt()
  end, "Save current session")

  bmap("<CR>", function()
    local fname = get_selected_filename()
    if not fname then return end
    close_float()
    load_filename(fname)
  end, "Load selected (wipe)")

  bmap("d", function()
    local fname = get_selected_filename()
    if not fname then return end
    delete_filename(fname)
    state.sessions = read_sessions()
    render_float()
    clamp_cursor_to_sessions()
  end, "Delete selected")
  local function move(delta)
    if not (state.list.first and state.list.last) then
      return
    end

    local row2 = vim.api.nvim_win_get_cursor(win)[1]
    if row2 < state.list.first then
      row2 = state.list.first
    elseif row2 > state.list.last then
      row2 = state.list.last
    else
      row2 = row2 + delta
      if row2 < state.list.first then row2 = state.list.first end
      if row2 > state.list.last then row2 = state.list.last end
    end
    vim.api.nvim_win_set_cursor(win, { row2, 0 })
  end

  bmap("j", function() move(1) end, "Down (sessions only)")
  bmap("k", function() move(-1) end, "Up (sessions only)")
  bmap("<Down>", function() move(1) end, "Down (sessions only)")
  bmap("<Up>", function() move(-1) end, "Up (sessions only)")

  -- On open: if sessions exist, place cursor on the first session entry.
  vim.schedule(function()
    clamp_cursor_to_sessions()
  end)
end

function M.setup(opts)
  state.opts = merge_opts(opts)
  ensure_dir(state.opts.session_dir)

  vim.keymap.set("n", state.opts.keymaps.list, function()
    M.open()
  end, { desc = "Phantom: sessions" })

  vim.api.nvim_create_user_command("Phantom", function() M.open() end, {})
end

return M
