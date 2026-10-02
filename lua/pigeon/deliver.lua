--- Whom a message goes to, and delivering it there.
---
--- The target is remembered for the session: a fresh pick happens only when
--- nothing is remembered and the window has several siblings. Rendering is
--- per target by construction — the only way out is `Peer.send(render)`, which
--- hands the renderer that target's own working directory.
local Picker = require("pigeon.picker")
local Transport = require("pigeon.transport")
local Util = require("pigeon.util")

local M = {}

--- The pane this session sends to, once one has been chosen.
---@type pigeon.Peer?
local remembered

--- A target-pick entry: the pane's own name, and the pane itself.
---@class pigeon.deliver.PeerEntry : pigeon.picker.Entry
---@field peer pigeon.Peer

--- Test/initialization helper: forget the remembered target.
function M.reset()
  remembered = nil
end

--- The pane this session sends to, or nil while nothing has been chosen.
---@return pigeon.Peer?
function M.target()
  return remembered
end

--- The entries a target pick offers, in the order `peers()` reported them.
---@param peers pigeon.Peer[]
---@return pigeon.deliver.PeerEntry[]
local function entries(peers)
  local out = {}
  for _, peer in ipairs(peers) do
    out[#out + 1] = { text = peer:repr(), peer = peer }
  end
  return out
end

--- Render for each target and deliver, reporting every failure against the
--- pane it was meant for. Answers whether anything actually reached a pane.
---@param peers pigeon.Peer[]
---@param render pigeon.Render
---@return boolean delivered
local function deliver_to(peers, render)
  local delivered = false
  for _, peer in ipairs(peers) do
    local ok, err = peer:send(render)
    if ok then
      delivered = true
    else
      Util.warn(("send to %s failed: %s"):format(peer:repr(), err or "unknown error"))
    end
  end
  return delivered
end

--- Pick target pane(s) from `peers`.
---@param peers pigeon.Peer[]
---@param prompt string
---@param many boolean
---@param after fun(chosen: pigeon.Peer[])
local function choose(peers, prompt, many, after)
  Picker.pick({
    prompt = prompt,
    many = many,
    items = function(emit, done)
      emit(entries(peers))
      done()
    end,
  }, function(chosen)
    local out = {}
    for _, entry in ipairs(chosen or {}) do
      ---@cast entry pigeon.deliver.PeerEntry
      out[#out + 1] = entry.peer
    end
    after(out)
  end)
end

--- The live sibling panes, or nil plus the reason there are none to reach.
---@return pigeon.Peer[]?
---@return string?
local function siblings()
  local transport, reason = Transport.get()
  if not transport then
    return nil, reason or "not inside a supported multiplexer"
  end
  local peers, err = transport.peers()
  if not peers then
    return nil, err or "can't list panes"
  end
  if #peers == 0 then
    return nil, "no other panes in this window"
  end
  return peers, nil
end

--- Deliver `render`, resolving a target first when none is remembered. With a
--- single sibling there is nothing to choose; with several, a pick decides.
--- A single choice becomes the session's target, while a multi-choice is a
--- one-off broadcast that remembers nothing.
---
--- `after` runs once the attempt is over — after a deferred pick resolves, not
--- when `run` returns — and is handed whether anything was delivered. That is
--- what lets a flow react to a send whose text is produced at delivery time.
---@param render pigeon.Render
---@param after? fun(delivered: boolean)
function M.run(render, after)
  local function finish(delivered)
    if after then
      after(delivered)
    end
  end

  if remembered then
    finish(deliver_to({ remembered }, render))
    return
  end

  local peers, err = siblings()
  if not peers then
    Util.warn(err or "can't resolve a target")
    finish(false)
    return
  end
  if #peers == 1 then
    remembered = peers[1]
    finish(deliver_to(peers, render))
    return
  end

  choose(peers, "Send to: ", true, function(chosen)
    if #chosen == 0 then
      finish(false)
      return
    end
    if #chosen == 1 then
      remembered = chosen[1]
    end
    finish(deliver_to(chosen, render))
  end)
end

--- Choose the session's target, replacing any remembered one.
function M.retarget()
  local peers, err = siblings()
  if not peers then
    Util.warn(err or "can't resolve a target")
    return
  end
  if #peers == 1 then
    remembered = peers[1]
    Util.notify(("target: %s"):format(remembered:repr()), vim.log.levels.INFO)
    return
  end

  choose(peers, "Target: ", false, function(chosen)
    if #chosen == 0 then
      return
    end
    remembered = chosen[1]
    Util.notify(("target: %s"):format(remembered:repr()), vim.log.levels.INFO)
  end)
end

return M
