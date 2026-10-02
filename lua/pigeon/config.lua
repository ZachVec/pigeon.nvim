--- Configuration for Pigeon: the option table, and the validation of its
--- shape.
---
--- This module is data. The behavior a value selects — how a reference is
--- spelled, which implementation a name picks — belongs to the module that
--- owns that behavior, and is resolved by that module's own `setup`.
local Util = require("pigeon.util")

--- Renders a path plus its optional `:L` suffix in the user's dialect. The
--- hook `reference.lua` resolves; the shape `config.lua` accepts.
---@alias pigeon.ReferenceFormat fun(file: string, loc: string?): string?

---@class pigeon.Config
---@field multiplexer string "auto" (detect) | an adapter name | "none"
---@field picker string "native" | "fzf-lua" | "snacks"
---@field format pigeon.ReferenceFormat? absent means the default dialect
---@field prompts table<string, string> named prompt templates (name -> template)
---@field references { join: string } the files/buffers module's options
---@field comments { item: string }

--- What `setup` accepts: the same keys, each optional, merged over the
--- defaults. `pigeon.Config` is the resolved table `M.options` holds.
---@class pigeon.ConfigOverrides
---@field multiplexer? string "auto" (detect) | an adapter name | "none"
---@field picker? string "native" | "fzf-lua" | "snacks"
---@field format? pigeon.ReferenceFormat
---@field prompts? table<string, string> named prompt templates (name -> template)
---@field references? { join: string } the files/buffers module's options
---@field comments? { item: string }

local M = {}

---@type pigeon.Config
local defaults = {
  --- Which multiplexer adapter to use. "auto" detects the one this Neovim is
  --- running inside; a name forces it; "none" disables sending entirely.
  multiplexer = "auto",
  --- Pluggable picker implementation.
  picker = "native",
  --- How a location reference reads: the relativized path plus its `:L`
  --- suffix. A tool dialect (an `@` prefix, a URI, ...) is a format hook;
  --- without one, `reference.lua` spells the default dialect.
  format = nil,
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
    --- What a comment sends, rendered for the target pane. Fields: `{note}`
    --- (what you typed), `{lines}` (the range spelled through the format hook),
    --- and the `{file}`/`{start}`/`{end}` building blocks.
    item = "{lines} {note}",
  },
}

---@type pigeon.Config
M.options = vim.deepcopy(defaults)

--- Replace the option table: the defaults, then `opts`, then the shape checks.
---@param opts? pigeon.ConfigOverrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if M.options.format ~= nil and type(M.options.format) ~= "function" then
    Util.warn("format must be a function; using the default reference dialect")
    M.options.format = nil
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
