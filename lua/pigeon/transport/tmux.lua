--- The tmux adapter: peers over the ambient server, delivery via bracketed
--- paste.
---
--- This adapter talks to the server this Neovim is attached to, named by
--- `$TMUX` — never by a private socket. `$TMUX_PANE` says which pane is "self",
--- so its window's other panes are the targets.
local Util = require("pigeon.util")

local M = {}

--- Pane rows: id, `<window>.<pane>` index, command, working directory, dead.
--- The index and command make a repr that distinguishes panes; the directory is
--- the reference base handed to the renderer.
local PANE_FMT = table.concat({
  "#{pane_id}",
  "#{window_index}.#{pane_index}",
  "#{pane_current_command}",
  "#{pane_current_path}",
  "#{pane_dead}",
}, "\t")

--- Sequence for staging-buffer names, so two sends can never collide.
local buffer_seq = 0

--- Run tmux against the ambient server.
---@return { code: integer, stdout: string, stderr: string }
local function exec(...)
  local code, stdout, stderr = Util.run({ "tmux", ... })
  return { code = code, stdout = stdout, stderr = stderr }
end

---@param prefix string
---@param result { code: integer, stdout: string, stderr: string }
---@return string
local function fail(prefix, result)
  local detail = vim.trim(result.stderr or "")
  if detail == "" then
    return prefix
  end
  return ("%s: %s"):format(prefix, detail)
end

--- True when tmux's stderr says the server/socket is not there.
---@param text string
---@return boolean
local function missing_server(text)
  return text:find("no server running", 1, true) ~= nil or text:find("error connecting", 1, true) ~= nil
end

---@return string?
local function self_pane()
  local pane = vim.env.TMUX_PANE
  if pane == nil or pane == "" then
    return nil
  end
  return pane
end

--- The window this Neovim's pane sits in.
---@return string? window
---@return string? err
---@return boolean? gone true when the server itself is not running
local function current_window()
  local pane = self_pane()
  if not pane then
    return nil, "TMUX_PANE is not set", nil
  end
  local result = exec("display-message", "-t", pane, "-p", "#{window_id}")
  if result.code ~= 0 then
    if missing_server(result.stderr) then
      return nil, nil, true
    end
    return nil, fail("can't resolve the current window", result), nil
  end
  local window = vim.trim(result.stdout)
  if window == "" then
    return nil, "can't resolve the current window", nil
  end
  return window, nil, nil
end

--- Deliver `text` verbatim into a pane, without submitting. Bracketed paste is
--- what keeps embedded newlines intact in a TUI; a bare trailing newline would
--- show up as an empty line, so the caller must not add one.
---@param pane_id string
---@param text string
---@return boolean
---@return string?
local function paste(pane_id, text)
  buffer_seq = buffer_seq + 1
  local name = ("pigeon-%d-%d"):format(vim.fn.getpid(), buffer_seq)

  local staged = exec("set-buffer", "-b", name, "--", text)
  if staged.code ~= 0 then
    return false, fail("failed to stage the message", staged)
  end

  -- -d deletes the buffer as part of pasting; on failure it has not run, so
  -- clean up best-effort rather than leaking the buffer.
  local pasted = exec("paste-buffer", "-p", "-d", "-t", pane_id, "-b", name)
  if pasted.code ~= 0 then
    local message = fail(("failed to paste into %s"):format(pane_id), pasted)
    local cleaned = exec("delete-buffer", "-b", name)
    if cleaned.code ~= 0 then
      message = message .. "; " .. fail("failed to clean the send buffer", cleaned)
    end
    return false, message
  end
  return true, nil
end

--- The command lines of `pid` and its descendants, outermost first, as `ps`
--- reports them; nil when `ps` cannot be asked.
---
--- The whole command line, not the process name: a program launched through an
--- interpreter — codex is a `#!/usr/bin/env node` script — keeps its name in
--- the arguments, while the name column only ever shows the interpreter.
---@param pid integer
---@return string[]?
local function commands(pid)
  local code, stdout = Util.run({ "ps", "-A", "-ww", "-o", "pid,ppid,args" })
  if code ~= 0 then
    return nil
  end

  local cmd = {} ---@type table<integer, string>
  local children = {} ---@type table<integer, integer[]>
  for line in (stdout or ""):gmatch("[^\r\n]+") do
    -- The header's first column is not a number, so it never reaches here.
    local ps_pid, ppid, args = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
    local child, parent = tonumber(ps_pid or ""), tonumber(ppid or "")
    if child and parent and args and args ~= "" then
      cmd[child] = args
      children[parent] = children[parent] or {}
      children[parent][#children[parent] + 1] = child
    end
  end

  -- Breadth-first from the pane's own process: an outer program is asked about
  -- before anything it spawned.
  local out, seen = {}, {}
  local todo = { pid }
  while #todo > 0 do
    local current = table.remove(todo, 1)
    if not seen[current] then
      seen[current] = true
      if cmd[current] then
        out[#out + 1] = cmd[current]
      end
      vim.list_extend(todo, children[current] or {})
    end
  end
  return out
end

--- The target's context, read at send time: its working directory, and the
--- command lines of the processes running in it, outermost first. Either half
--- is nil when the pane cannot be asked.
---@param pane_id string
---@return pigeon.RenderCtx
local function probe(pane_id)
  local ctx = { cwd = nil, process = nil }
  local result = exec("display-message", "-t", pane_id, "-p", "#{pane_current_path}\t#{pane_pid}")
  if result.code ~= 0 then
    return ctx
  end
  local cwd, pid = (result.stdout or ""):match("^(.-)\t(%d+)")
  if cwd and cwd ~= "" then
    ctx.cwd = cwd
  end
  local pane_pid = tonumber(pid or "")
  if pane_pid then
    ctx.process = commands(pane_pid)
  end
  return ctx
end

--- One peer handle over `pane_id`. The context is deliberately read again at
--- send time: a pane that has changed directory since the pick must get
--- references relative to where it is now, and a pane whose programs have
--- changed must get the format of what runs there now.
---@param pane_id string
---@param index string
---@param command string
---@param cwd string
---@return pigeon.Peer
local function peer(pane_id, index, command, cwd)
  local self = {}

  function self:repr()
    return ("%s · %s · %s"):format(index, command ~= "" and command or "?", Util.tilde(cwd))
  end

  function self:send(render)
    local text, why = render(probe(pane_id))
    if text == nil then
      return false, why or "nothing to send"
    end
    return paste(pane_id, text)
  end

  return self
end

--- True when this Neovim is running inside tmux on a server we can reach.
---@return boolean
function M.matches()
  return vim.fn.executable("tmux") == 1 and (vim.env.TMUX or "") ~= ""
end

--- The other panes of this Neovim's window. A missing server reads as an empty
--- inventory, not an error; dead panes are dropped because nothing can reach
--- them.
---@return pigeon.Peer[]?
---@return string?
function M.peers()
  local window, err, gone = current_window()
  if gone then
    return {}, nil
  end
  if not window then
    return nil, err
  end

  local result = exec("list-panes", "-t", window, "-F", PANE_FMT)
  if result.code ~= 0 then
    if missing_server(result.stderr) then
      return {}, nil
    end
    return nil, fail("can't list panes", result)
  end

  local self_id = self_pane()
  local peers = {}
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    local fields = vim.split(line, "\t", { plain = true })
    local id, index, command, cwd, dead = fields[1], fields[2], fields[3], fields[4], fields[5]
    if id ~= nil and id ~= "" and id ~= self_id and dead ~= "1" then
      peers[#peers + 1] = peer(id, index or "", command or "", cwd or "")
    end
  end
  return peers, nil
end

return M
