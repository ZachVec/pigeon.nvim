--- The multiplexer seam: the Peer and Transport contracts, adapter detection,
--- and resolution.
---
--- Everything above this module knows nothing about tmux; everything below
--- knows nothing about Neovim. This is the one place a multiplexer is named.

--- One target pane, as the adapter that owns it presents it. A handle is only
--- meaningful inside the ambient multiplexer instance it came from, and stays
--- valid for the pane's lifetime: a multiplexer that mints stable ids never
--- hands a dead pane's id to a new pane, so a stale handle fails loudly rather
--- than quietly addressing someone else.
---@class pigeon.Peer
---@field repr fun(self: pigeon.Peer): string the display name; must distinguish panes
---@field send fun(self: pigeon.Peer, render: pigeon.Render): boolean, string?

--- What a renderer is handed for one target: the target's own context, read at
--- send time. A nil `cwd` means the adapter cannot tell the working directory,
--- and every path in the text stays absolute; a nil `process` means it cannot
--- tell what is running in the pane, and only the configured format applies.
---@class pigeon.RenderCtx
---@field cwd string? the target's working directory
---@field process string[]? the target's command lines, outermost process first

--- A message to deliver, resolved once per target: the adapter hands `render`
--- the target's own context, so a reference comes out relative to the pane
--- that will read it and in a format that pane understands. Returning
--- `nil, reason` means there is nothing to deliver to that target.
---@alias pigeon.Render fun(ctx: pigeon.RenderCtx): string?, string?

--- A multiplexer adapter.
---@class pigeon.Transport
---@field peers fun(): pigeon.Peer[]?, string? the current pane's siblings, excluding self

local M = {}

--- Adapter name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  tmux = "pigeon.transport.tmux",
}

--- Detection order for `multiplexer = "auto"`. Nested multiplexers set several
--- of these at once and the environment cannot say which one directly hosts
--- Neovim, so an ambiguous setup is expected to name its adapter explicitly.
local ORDER = {
  "tmux",
}

---@type pigeon.Transport?
local resolved
---@type string?
local resolved_name
---@type string?
local reason
local initialized = false

--- Load and validate one adapter by name.
---@param name string
---@return { matches: fun(): boolean, peers: fun(): pigeon.Peer[]?, string? }?
---@return string?
local function load(name)
  local path = REGISTRY[name]
  if not path then
    return nil, ("unknown multiplexer '%s'"):format(tostring(name))
  end
  local ok, impl = pcall(require, path)
  if not ok then
    return nil, ("multiplexer '%s' is unavailable (%s)"):format(name, tostring(impl))
  end
  if type(impl.matches) ~= "function" or type(impl.peers) ~= "function" then
    return nil, ("multiplexer '%s' does not implement pigeon.Transport"):format(name)
  end
  return impl, nil
end

--- Resolve the adapter once. `auto` picks the first adapter that answers for
--- this environment; a name forces one; `none` disables sending. An unknown or
--- misconfigured name is a setup error; simply being outside every multiplexer
--- is not.
---@param opts? { multiplexer?: string }
function M.setup(opts)
  initialized = true
  resolved, resolved_name, reason = nil, nil, nil

  local want = (opts and opts.multiplexer) or "auto"
  if want == "none" then
    reason = 'sending is disabled (multiplexer = "none")'
    return
  end

  if want == "auto" then
    for _, name in ipairs(ORDER) do
      local impl = load(name)
      if impl and impl.matches() then
        resolved, resolved_name = impl, name
        return
      end
    end
    reason = "not inside a supported multiplexer"
    return
  end

  local impl, err = load(want)
  if not impl then
    error("pigeon: " .. err, 0)
  end
  if not impl.matches() then
    reason = ("configured multiplexer '%s' is not the one this Neovim is running in"):format(want)
    return
  end
  resolved, resolved_name = impl, want
end

--- The resolved adapter, or nil plus the reason nothing could be resolved.
---@return pigeon.Transport?
---@return string?
function M.get()
  if not initialized then
    error("pigeon: transport not initialized; call require('pigeon').setup() first", 0)
  end
  return resolved, reason
end

--- The resolved adapter's name, for health and status output.
---@return string?
function M.name()
  return resolved_name
end

--- Test/initialization helper: forget the resolved adapter.
function M.reset()
  initialized = false
  resolved, resolved_name, reason = nil, nil, nil
end

return M
