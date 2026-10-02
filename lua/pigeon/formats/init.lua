--- The formats registry: which reference format a target pane reads.
---
--- A program running in a pane spells references its own way, so which format
--- to use is a fact about the target, not a setting. Each program is one
--- Profile — how to recognize it in the pane's process chain, and the format it
--- reads — and this module resolves the built-ins. `reference.lua` asks it
--- which format to spell with; no module above it names a program.
local Config = require("pigeon.config")

local M = {}

--- One command line a pane is running, as `ps` reports it. The predicate
--- answers whether that line names the program this Profile is about.
---@alias pigeon.formats.Match fun(cmd: string): boolean

--- One program: how to recognize it in a pane, and how its references read.
---@class pigeon.formats.Profile
---@field match pigeon.formats.Match
---@field format pigeon.ReferenceFormat

--- The built-in profiles, in the order a process chain is asked about them. A
--- whitelist, so a name is never `require`d as a path.
local BUILTIN = { "claude", "codex" }

--- The resolved profiles, in the order a process chain is asked about them.
---@type { name: string, profile: pigeon.formats.Profile }[]
local order = {}

--- Load one built-in profile by name.
---@param name string
---@return pigeon.formats.Profile?
local function builtin(name)
  local ok, profile = pcall(require, "pigeon.formats." .. name)
  if not ok or type(profile) ~= "table" then
    return nil
  end
  ---@cast profile pigeon.formats.Profile
  return profile
end

--- Resolve the built-in profiles.
function M.setup()
  order = {}
  for _, name in ipairs(BUILTIN) do
    local profile = builtin(name)
    if profile then
      order[#order + 1] = { name = name, profile = profile }
    end
  end
end

--- The format a target reads: the first Profile that recognizes any of the
--- pane's command lines — the outermost process first — else the `format`
--- option, which is the plain spelling until a hook replaces it.
---@param process string[]?
---@return pigeon.ReferenceFormat
function M.resolve(process)
  for _, cmd in ipairs(process or {}) do
    for _, entry in ipairs(order) do
      if entry.profile.match(cmd) then
        return entry.profile.format
      end
    end
  end
  return Config.options.format
end

--- The resolved profile names, in trial order, for health and status output.
---@return string[]
function M.names()
  local names = {}
  for _, entry in ipairs(order) do
    names[#names + 1] = entry.name
  end
  return names
end

return M
