--- The prompt command: named templates whose placeholders are spelled for a
--- target, picked by name and delivered.
---
--- A prompt renders to a `Render`, not to a finished string: the same template
--- produces different text for panes with different working directories, so
--- the resolvers take the target's cwd and the text is produced inside
--- `Peer.send`.
local Config = require("pigeon.config")
local Deliver = require("pigeon.deliver")
local Picker = require("pigeon.picker")
local Reference = require("pigeon.reference")
local Util = require("pigeon.util")

local M = {}

--- What a prompt renders against: the buffer and cursor the flow was invoked
--- from.
---@class pigeon.commands.prompts.Ctx
---@field buf integer
---@field row integer

--- One resolver per placeholder. `cwd` is the target pane's working directory;
--- nil means the adapter could not report one, and every path stays absolute.
---@type table<string, fun(ctx: pigeon.commands.prompts.Ctx, cwd: string?): string?>
local resolvers = {
  file = function(ctx, cwd)
    return Reference.reference(cwd, vim.api.nvim_buf_get_name(ctx.buf))
  end,
  line = function(ctx, cwd)
    return Reference.reference(cwd, vim.api.nvim_buf_get_name(ctx.buf), ctx.row)
  end,
}

--- The placeholder vocabulary: the resolvers' own keys, so a name can never be
--- known without something to resolve it.
---@type table<string, boolean>
local PLACEHOLDERS = {}
for name in pairs(resolvers) do
  PLACEHOLDERS[name] = true
end

--- Warn about a configured template naming a placeholder no resolver knows —
--- `Util.interpolate` would type it literally. The vocabulary is the
--- resolvers' keys, and the check runs here, on the applied config.
function M.setup()
  local unknown = {}
  for _, template in pairs(Config.options.prompts) do
    for token in template:gmatch("{([%w_]+)}") do
      if not PLACEHOLDERS[token] then
        unknown[token] = true
      end
    end
  end
  local names = vim.tbl_map(function(token)
    return "{" .. token .. "}"
  end, vim.tbl_keys(unknown))
  if #names > 0 then
    table.sort(names)
    Util.warn(("prompts: unknown placeholder(s) %s"):format(table.concat(names, ", ")))
  end
end

--- Render `template` into a per-target message. A placeholder that resolves
--- empty fails the whole render, naming the placeholder, so the caller skips
--- the send with a reason instead of delivering half a prompt.
---@param template string
---@param ctx pigeon.commands.prompts.Ctx
---@return pigeon.Render
function M.render(template, ctx)
  local lines = vim.split(template, "\n", { plain = true })
  return function(cwd)
    local out = {}
    for _, line in ipairs(lines) do
      local rendered, failed = Util.interpolate(line, PLACEHOLDERS, function(name)
        return resolvers[name](ctx, cwd)
      end)
      if rendered == nil then
        return nil, ("{%s} resolved empty"):format(failed)
      end
      out[#out + 1] = rendered
    end
    return table.concat(out, "\n"), nil
  end
end

--- A prompt-name entry for the pick.
---@class pigeon.commands.prompts.NameEntry : pigeon.picker.Entry
---@field name string

--- Pick a prompt name and send the rendered prompt to the target.
function M.run()
  local names = vim.tbl_keys(Config.options.prompts)
  if #names == 0 then
    Util.warn("no prompts are configured")
    return
  end
  -- The config is a name -> template map, so it has no order of its own; the
  -- pick shows the names in one stable order instead.
  table.sort(names)

  -- Read the context now, not inside the callback: a float-based picker
  -- (snacks', fzf-lua's or dressing's `vim.ui.select`) makes its own buffer
  -- current, so reading it later would spell {file}/{line} against the picker
  -- instead of the file.
  local ctx = {
    buf = vim.api.nvim_get_current_buf(),
    row = vim.api.nvim_win_get_cursor(0)[1],
  }

  Picker.pick({
    prompt = "Prompt: ",
    many = false,
    items = function(emit, done)
      local entries = {}
      for _, name in ipairs(names) do
        entries[#entries + 1] = { text = name, name = name }
      end
      emit(entries)
      done()
    end,
  }, function(chosen)
    local entry = chosen[1]
    ---@cast entry pigeon.commands.prompts.NameEntry
    if not entry then
      return
    end

    local template = Config.options.prompts[entry.name]
    Deliver.run(M.render(template, ctx))
  end)
end

return M
