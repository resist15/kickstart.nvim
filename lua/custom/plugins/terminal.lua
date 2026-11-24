-- Bottom terminal panel with tabs, like VS Code's.
--
--  <leader>tt  open/focus the panel, or hide it if it's already focused
--  Ctrl+j      same, also from inside the terminal
--  Ctrl+`      same, if your terminal emulator can send it
--
-- Inside the panel:
--  Ctrl+n          new terminal tab
--  Ctrl+Tab        next tab
--  Ctrl+Shift+Tab  previous tab
--  `exit`          closes that tab (the panel closes with the last one)
--
-- Ctrl+Tab / Ctrl+Shift+Tab need the terminal emulator to send them as distinct
-- keys; Alacritty is set up for that in ~/dotfiles/alacritty (CSI-u sequences).
--
-- Shells stay alive while the panel is hidden. If the current file (or the
-- working directory) sits inside a project with `.venv/` or `venv/`, terminals
-- start with that virtualenv active (VIRTUAL_ENV set, its bin/ first in PATH),
-- which works for any shell (fish, bash, zsh) without sourcing activate scripts.

local term = {
  bufs = {}, ---@type integer[] terminal buffers, one per tab
  idx = 0, -- index of the tab shown in the panel
  win = nil, ---@type integer?
  env = nil, ---@type table<string, string>? venv env of the code buffer the panel was opened from
}

---@return table<string, string>?
local function venv_env()
  if vim.env.VIRTUAL_ENV then return nil end -- already inherited from the shell that started nvim
  local root = vim.fs.root(0, { '.venv', 'venv' }) or vim.fs.root(vim.fn.getcwd(), { '.venv', 'venv' })
  if not root then return nil end
  for _, dir in ipairs { '.venv', 'venv' } do
    local venv = vim.fs.joinpath(root, dir)
    if vim.uv.fs_stat(vim.fs.joinpath(venv, 'bin', 'python')) then
      return { VIRTUAL_ENV = venv, PATH = vim.fs.joinpath(venv, 'bin') .. ':' .. vim.env.PATH }
    end
  end
end

local function panel_open() return term.win ~= nil and vim.api.nvim_win_is_valid(term.win) end

-- Tab bar at the top of the panel: " 1  2  3 " with the current one highlighted.
local function update_winbar()
  if not panel_open() then return end
  local tabs = {}
  for i = 1, #term.bufs do
    tabs[#tabs + 1] = (i == term.idx and '%#TabLineSel#' or '%#TabLine#') .. ' ' .. i .. ' %*'
  end
  vim.wo[term.win].winbar = table.concat(tabs, ' ') .. '%=%#Comment#C-n new  C-Tab next  C-S-Tab prev %*'
end

---@param i integer
local function show(i)
  term.idx = i
  vim.api.nvim_win_set_buf(term.win, term.bufs[i])
  update_winbar()
  -- Deferred: when called from a terminal-mode mapping, an immediate startinsert
  -- is undone as the mapping returns, leaving the tab in Normal mode.
  vim.schedule(function()
    if vim.api.nvim_get_current_win() == term.win then vim.cmd.startinsert() end
  end)
end

---@param step integer 1 for next, -1 for previous
local function cycle(step)
  if #term.bufs < 2 then return end
  show((term.idx - 1 + step) % #term.bufs + 1)
end

local new_term

---@param buf integer
local function on_exit(buf)
  local i = vim.fn.index(term.bufs, buf) + 1
  if i == 0 then return end
  table.remove(term.bufs, i)
  if #term.bufs > 0 and panel_open() then
    show(math.min(i, #term.bufs))
  elseif panel_open() and #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.api.nvim_win_close(term.win, true)
    term.win = nil
  end
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

new_term = function()
  -- A tab opened from inside the panel reuses the venv of the code it was opened for.
  if vim.bo.buftype ~= 'terminal' then term.env = venv_env() end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(term.win, buf)
  vim.fn.jobstart(vim.o.shell, { term = true, env = term.env })
  vim.bo[buf].buflisted = false
  table.insert(term.bufs, buf)

  local map = function(lhs, fn, desc) vim.keymap.set({ 'n', 't' }, lhs, fn, { buffer = buf, desc = desc }) end
  map('<C-n>', new_term, 'New terminal tab')
  map('<C-Tab>', function() cycle(1) end, 'Next terminal tab')
  map('<C-S-Tab>', function() cycle(-1) end, 'Previous terminal tab')

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function() vim.schedule(function() on_exit(buf) end) end,
  })

  show(#term.bufs)
end

local function toggle()
  -- Focused panel: hide it and go back to the code. Unfocused: jump into it.
  if panel_open() then
    if vim.api.nvim_get_current_win() == term.win then
      vim.api.nvim_win_hide(term.win)
      term.win = nil
    else
      vim.api.nvim_set_current_win(term.win)
      vim.cmd.startinsert()
    end
    return
  end

  vim.cmd 'botright split'
  term.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(term.win, math.floor(vim.o.lines * 0.3))
  vim.wo[term.win].number = false
  vim.wo[term.win].signcolumn = 'no'

  if #term.bufs == 0 then
    new_term()
  else
    show(term.idx)
  end
end

vim.keymap.set('n', '<leader>tt', toggle, { desc = '[T]oggle [T]erminal (bottom)' })
vim.keymap.set({ 'n', 't' }, '<C-`>', toggle, { desc = 'Toggle bottom terminal' })
-- Ctrl+j toggles too. This replaces init.lua's "focus lower window" for Ctrl+j
-- (the terminal is the lower window anyway).
vim.keymap.set({ 'n', 't' }, '<C-j>', toggle, { desc = 'Toggle bottom terminal' })
