--- The comment command: ask for a note about a line range, render it through
--- the configured item template, and deliver it.
---
--- A comment is not stored. The flow takes the text the user typed, spells the
--- range for the target pane, and delivers it in one go — a second note is a
--- second send, and the target's own input is where a batch accumulates. What
--- this module owns is the template's vocabulary and the rendering of one
--- comment against a target's cwd.
local Config = require("pigeon.config")
local Deliver = require("pigeon.deliver")
local Reference = require("pigeon.reference")
local Util = require("pigeon.util")

local M = {}

--- The fields a comment's `item` template may name.
local FIELDS = { note = true, lines = true, file = true, start = true, ["end"] = true }

--- One comment: the range it is about, and the note the user typed.
---@class pigeon.Comment
---@field buf integer source buffer
---@field start_row integer 1-based inclusive
---@field end_row integer 1-based inclusive
---@field note string

--- Warn about a configured template naming a field nothing resolves —
--- `Util.interpolate` would type it literally. The vocabulary is the fields
--- this module can spell, and the check runs on the applied config.
function M.setup()
  local unknown = {}
  for token in Config.options.comments.item:gmatch("{([%w_]+)}") do
    if not FIELDS[token] then
      unknown[token] = true
    end
  end
  local names = vim.tbl_map(function(token)
    return "{" .. token .. "}"
  end, vim.tbl_keys(unknown))
  if #names > 0 then
    table.sort(names)
    Util.warn(("comments.item: unknown placeholder(s) %s"):format(table.concat(names, ", ")))
  end
end

--- Render one comment through the configured `item` template for `cwd`, ending
--- it with a newline: a comment is a whole thought, so the next one — and
--- whatever you type next — starts on its own line. nil when a location field
--- has no reference, naming the field: the flow reports the reason instead of
--- sending a note with no anchor.
---@param comment pigeon.Comment
---@param cwd string?
---@return string?
---@return string? failed placeholder name, when nil is returned
function M.render(comment, cwd)
  -- One path per comment, however many fields spell it. `lines` and `file` are
  -- spellable only while the format hook accepts them; nil is no reference.
  local path = vim.api.nvim_buf_get_name(comment.buf)
  local text, failed = Util.interpolate(Config.options.comments.item, FIELDS, function(name)
    if name == "note" then
      return comment.note
    elseif name == "lines" then
      return Reference.reference(cwd, path, comment.start_row, comment.end_row)
    elseif name == "file" then
      return Reference.reference(cwd, path)
    elseif name == "start" then
      return tostring(comment.start_row)
    elseif name == "end" then
      return tostring(comment.end_row)
    end
    return "" -- unknown name: unreachable from whitelisted callers
  end)
  if text == nil then
    return nil, failed
  end
  return text .. "\n"
end

--- Ask for a note about lines `line1..line2` and deliver it to the target.
--
-- Esc cancels, an empty note sends nothing, and nothing is kept between sends:
-- a second note is a second send, so the target's own input is where a batch
-- accumulates.
---@param line1 integer
---@param line2 integer
function M.run(line1, line2)
  -- Read the buffer before the prompt, not after it: `vim.ui.input` may be a
  -- float (dressing, snacks), and the note stays about the buffer the command
  -- was invoked from.
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) == "" then
    Util.warn("a comment needs a named buffer — save the file first")
    return
  end

  vim.ui.input({ prompt = "Comment: " }, function(note)
    note = vim.trim(note or "")
    if note == "" then
      return
    end
    local comment = { buf = buf, start_row = line1, end_row = line2, note = note }
    Deliver.run(function(cwd)
      local text, failed = M.render(comment, cwd)
      if text == nil then
        return nil, ("{%s} resolved empty"):format(failed)
      end
      return text
    end)
  end)
end

return M
