--- Shared helpers for Pigeon specs.
local M = {}

--- Drop every loaded Pigeon module so each spec starts from fresh module state
--- (defaults, registries, fakes). Other specs' loaded modules are the only
--- shared process state.
function M.reload_pigeon()
  for name in pairs(package.loaded) do
    if name == "pigeon" or name:find("^pigeon%.") == 1 then
      package.loaded[name] = nil
    end
  end
end

--- Create a real scratch buffer with `lines`, optionally named `name`.
---@param lines string|string[]
---@param name? string
---@return integer
function M.buffer(lines, name)
  lines = type(lines) == "string" and vim.split(lines, "\n", { plain = true }) or lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if name and name ~= "" then
    vim.api.nvim_buf_set_name(buf, name)
  end
  return buf
end

--- Wipe a test buffer.
---@param buf integer
function M.wipe(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

--- Every message raised through `vim.notify` while `fn` runs. Pigeon's own
--- notifications reach `vim.notify` synchronously on the main loop, which is
--- where specs run.
---@param fn fun()
---@return string[]
function M.notifications(fn)
  local seen = {}
  local original = vim.notify
  -- The real signature: this assignment is what types `vim.notify` for the
  -- whole workspace, and a one-parameter stub would read as "level is a
  -- redundant argument" at every `vim.notify(msg, level)` call site.
  ---@param msg string
  ---@param _ integer?
  vim.notify = function(msg, _)
    seen[#seen + 1] = msg
  end
  local ok, err = pcall(fn)
  vim.notify = original
  if not ok then
    error(err)
  end
  return seen
end

return M
