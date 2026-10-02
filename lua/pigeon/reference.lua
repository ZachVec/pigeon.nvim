--- The one reference spelling: how a path, and the range it may name, reads in
--- a message.
---
--- Every command that puts a location in a message spells it through here, so
--- the same code reads the same way in every message. Which format the
--- reference takes is `formats`' business; this module only builds the path
--- and its `:L` suffix. It sits beside `deliver.lua`: the two per-target
--- services every flow needs — how a path reads, and where the message goes.
local Formats = require("pigeon.formats")
local Util = require("pigeon.util")

local M = {}

--- The reference for one location, spelled in the format that target reads.
--- `ctx.cwd` is the base the path is relativized against: the target pane's
--- working directory. A nil `cwd` — an adapter that cannot report one — leaves
--- every path absolute. A nil path is no reference at all, and a format that
--- declines with nil or "" is treated the same way.
---@param ctx pigeon.RenderCtx the target, as the adapter reported it
---@param path string? absolute path, or one already relative to the target's cwd
---@param start_row? integer 1-based first line; nil for a whole-file reference
---@param end_row? integer 1-based last line; only meaningful with `start_row`
---@return string?
function M.reference(ctx, path, start_row, end_row)
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
  local format = Formats.resolve(ctx.process)
  local rendered = format(Util.relpath(ctx.cwd, path), loc)
  if rendered == nil or rendered == "" then
    return nil
  end
  return rendered
end

return M
