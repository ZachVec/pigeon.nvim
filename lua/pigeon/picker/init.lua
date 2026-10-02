--- The selection-UI seam: resolve the configured picker and render a pick
--- through it.

--- One thing a pick can offer: the line the implementation renders, plus the
--- fields the flow owns. The implementation reads `text` and never writes to
--- an entry.
---@class pigeon.picker.Entry
---@field text string

--- A pick's item stream, started by the implementation. `emit` appends a batch
--- as it is produced; `done` ends the run. The optional return stops a run
--- that is still going — the picker closed, or a command restarted it.
---@class pigeon.PickSpec
---@field prompt string
---@field many boolean how many entries the flow acts on
---@field preview? fun(entry: pigeon.picker.Entry): string[]? absent means no preview pane
---@field items fun(emit: fun(entries: pigeon.picker.Entry[]), done: fun()): (fun()?)

--- A selection-UI implementation.
---@class pigeon.Picker
---@field requires? string optional runtime module dependency
---@field pick fun(spec: pigeon.PickSpec, on_choices: fun(entries: pigeon.picker.Entry[]))

local Config = require("pigeon.config")

local M = {}

--- Implementation name -> module path. A whitelist, so a raw user string is
--- never `require`d.
local REGISTRY = {
  native = "pigeon.picker.native",
  ["fzf-lua"] = "pigeon.picker.fzf_lua",
  snacks = "pigeon.picker.snacks",
}

---@type pigeon.Picker?
local resolved

--- Resolve the configured picker. Called by the composition root before any
--- runtime side effects; invalid configuration is a setup error.
function M.setup()
  resolved = nil
  local name = Config.options.picker
  local path = REGISTRY[name]
  if not path then
    error(("pigeon: unknown picker '%s'"):format(tostring(name)), 0)
  end
  local ok, impl = pcall(require, path)
  if not ok then
    error(("pigeon: picker '%s' is unavailable (%s)"):format(name, tostring(impl)), 0)
  end
  if type(impl.pick) ~= "function" then
    error(("pigeon: picker '%s' does not implement pigeon.Picker"):format(name), 0)
  end
  if impl.requires then
    local dep_ok, dep_err = pcall(require, impl.requires)
    if not dep_ok then
      error(("pigeon: picker '%s' requires '%s' (%s)"):format(name, impl.requires, tostring(dep_err)), 0)
    end
  end
  resolved = impl
end

---@return pigeon.Picker
local function get()
  if not resolved then
    error("pigeon: picker not initialized; call require('pigeon').setup() first", 0)
  end
  return resolved
end

--- Test/initialization helper: forget the resolved picker.
function M.reset()
  resolved = nil
end

--- Render a pick through the configured implementation.
---@param spec pigeon.PickSpec
---@param on_choices fun(entries: pigeon.picker.Entry[])
function M.pick(spec, on_choices)
  get().pick(spec, on_choices)
end

return M
