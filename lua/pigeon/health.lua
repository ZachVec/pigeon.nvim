--- :checkhealth pigeon
local M = {}

local start = vim.health.start
local ok = vim.health.ok
local warn = vim.health.warn
local err = vim.health.error

function M.check()
  start("pigeon")

  if vim.fn.has("nvim-0.11") == 1 then
    ok("Neovim >= 0.11")
  else
    err("Neovim >= 0.11 is required")
    return
  end

  local checked, transport = pcall(require, "pigeon.transport")
  if not checked then
    err(tostring(transport))
    return
  end
  local resolved, reason = transport.get()
  if resolved then
    ok(("multiplexer: %s"):format(transport.name()))
  else
    warn(("multiplexer: none (%s)"):format(reason or "not detected"))
  end

  local picker = require("pigeon.config").options.picker
  ok(("picker: %s"):format(picker))
end

return M
