--- The one reference spelling: how a path, and the range it may name, reads in
--- a message.
---
--- Every command that puts a location in a message spells it through here, so
--- the same code reads the same way in every message and one `format` hook
--- replaces the dialect for all of them at once. It sits beside `deliver.lua`:
--- the two per-target services every flow needs — how a path reads, and where
--- the message goes.
local Config = require("pigeon.config")
local Util = require("pigeon.util")

local M = {}

--- The default dialect: the path and, when there is a position, its `:L`
--- suffix, joined by a space (`src/a.lua :L42`).
---@param file string
---@param loc? string
---@return string
local function default_format(file, loc)
  if loc then
    return file .. " " .. loc
  end
  return file
end

--- The resolved dialect: the configured hook, or the default above. Nothing to
--- roll back — `Config.setup` has already dropped a value that is not a hook —
--- so this module has no `reset`.
---@type pigeon.ReferenceFormat
local format = default_format

--- Resolve the reference dialect from the applied configuration.
function M.setup()
  format = Config.options.format or default_format
end

--- The reference for one location, spelled by the resolved dialect.
--- `cwd` is the base the path is relativized against: the target pane's
--- working directory. A nil `cwd` — an adapter that cannot report one — leaves
--- every path absolute. A nil path is no reference at all, and a hook that
--- declines with nil or "" is treated the same way.
---@param cwd string? relativization base; nil spells absolute paths
---@param path string? absolute path, or one already relative to `cwd`
---@param start_row? integer 1-based first line; nil for a whole-file reference
---@param end_row? integer 1-based last line; only meaningful with `start_row`
---@return string?
function M.reference(cwd, path, start_row, end_row)
  if path == nil or path == "" then
    return nil
  end
  local loc
  if start_row ~= nil then
    if end_row ~= nil and end_row ~= start_row then
      loc = (":L%d-%d"):format(start_row, end_row)
    else
      loc = (":L%d"):format(start_row)
    end
  end
  local rendered = format(Util.relpath(cwd, path), loc)
  if rendered == nil or rendered == "" then
    return nil
  end
  return rendered
end

return M
