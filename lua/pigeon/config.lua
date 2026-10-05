--- Configuration for Pigeon: the option table, and the validation of its
--- shape.
---
--- This module is data: the defaults, and the checks that reject a value of the
--- wrong shape. A default that is itself the value — a hook, a template —
--- lives here, in the resolved table everything else reads; what a value
--- *selects* (which picker a name picks, which Profile a pane matches) is
--- resolved by the module that owns it, in that module's own `setup`.
local Util = require("pigeon.util")

--- Renders a path plus its optional `:L` suffix in the user's format. The
--- default of `format` is one, each Profile carries one, and `formats`
--- resolves the one a target reads; the shape `config.lua` accepts.
---@alias pigeon.ReferenceFormat fun(file: string, loc: string?): string?

---@class pigeon.Config
---@field multiplexer string "auto" (detect) | an adapter name
---@field picker string "native" | "fzf-lua" | "snacks"
---@field format pigeon.ReferenceFormat the plain spelling, or the configured hook
---@field prompts table<string, string> named prompt templates (name -> template)
---@field references { join: string } the files/buffers module's options
---@field comments { item: string }

--- What `setup` accepts: the same keys, each optional, merged over the
--- defaults. `pigeon.Config` is the resolved table `M.options` holds.
---@class pigeon.ConfigOverrides
---@field multiplexer? string "auto" (detect) | an adapter name
---@field picker? string "native" | "fzf-lua" | "snacks"
---@field format? pigeon.ReferenceFormat
---@field prompts? table<string, string> named prompt templates (name -> template)
---@field references? { join: string } the files/buffers module's options
---@field comments? { item: string }

local M = {}

---@type pigeon.Config
local defaults = {
  --- Which multiplexer adapter to use. "auto" detects the one this Neovim is
  --- running inside; a name forces it.
  multiplexer = "auto",
  --- Pluggable picker implementation.
  picker = "native",
  --- How a location reads: the relativized path plus its `:L` suffix. A tool
  --- format (an `@` prefix, a URI, ...) is a hook; the default below is the
  --- plain spelling (`src/a.lua :L42`), which a target no Profile recognizes
  --- reads.
  format = function(file, loc)
    return file .. (loc and " " .. loc or "")
  end,
  --- Named prompt templates offered by `:Pigeon prompt`. The built-ins are the
  --- raw references; user entries merge additively, so a name you set
  --- overrides the built-in while names you leave unset are kept.
  prompts = {
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
  },
  --- The files/buffers module's options.
  references = {
    --- Separator between references: "\n" puts one per line, " " one line.
    join = "\n",
  },
  --- Comments: a note about a line range, delivered as soon as it is typed.
  comments = {
    --- What a comment says, rendered for the target pane. Fields: `{note}`
    --- (what you typed), `{lines}` (the range spelled through the format hook),
    --- and the `{file}`/`{start}`/`{end}` building blocks. The default ends in a
    --- newline, so a second comment starts on its own line.
    item = "{lines} {note}\n",
  },
}

---@type pigeon.Config
M.options = vim.deepcopy(defaults)

--- Replace the option table: the defaults, then `opts`, then the shape checks.
---@param opts? pigeon.ConfigOverrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if type(M.options.format) ~= "function" then
    Util.warn("format must be a function; using the default reference format")
    M.options.format = defaults.format
  end
  for name, template in pairs(M.options.prompts) do
    if type(template) ~= "string" then
      Util.warn(("dropping prompts entry '%s' (template is not a string)"):format(tostring(name)))
      M.options.prompts[name] = nil
    end
  end
  if type(M.options.comments.item) ~= "string" then
    Util.warn("comments.item must be a string; using the default")
    M.options.comments.item = defaults.comments.item
  end
end

return M
