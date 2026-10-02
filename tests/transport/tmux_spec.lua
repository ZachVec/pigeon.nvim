---@module 'luassert'

local Util = require("pigeon.util")

describe("pigeon.transport.tmux", function()
  local adapter
  local socket
  local generation = 0
  local saved_tmux
  local saved_pane

  local function tmux(...)
    local code, stdout, stderr = Util.run({ "tmux", "-L", socket, ... })
    return { code = code, stdout = stdout, stderr = stderr }
  end

  --- Stop whatever server this socket names and move to a fresh socket:
  --- `kill-server` returns before the server has released its socket, so a
  --- server started under the same name races that teardown and dies with
  --- "server exited unexpectedly" (measured 10 of 10 restarts on the GitHub
  --- runner, where it failed 2 of the cases below). A fresh name per server
  --- cannot race it, and the dying one still removes its own socket.
  local function reset_server()
    tmux("kill-server") -- exit 1 when no server exists; that is expected here
    generation = generation + 1
    socket = ("pigeon-test-%d-%d"):format(vim.fn.getpid(), generation)
  end

  --- Start a fresh server with an empty config. Without `-f /dev/null` the
  --- developer's own tmux configuration shapes the fixtures — `base-index 1`,
  --- for one, leaves no window 0 and silently breaks positional targets.
  ---@param command string
  local function start(command)
    local result = tmux("-f", "/dev/null", "new-session", "-d", "-s", "m", "-x", "120", "-y", "30", command)
    assert(result.code == 0, "could not start the private server: " .. tostring(result.stderr))
  end

  --- Make the adapter see this private server the way an ambient pane would:
  --- $TMUX names the socket, $TMUX_PANE names "self".
  ---@param pane string
  local function enter(pane)
    local result = tmux("display-message", "-p", "#{socket_path}")
    assert(result.code == 0, "could not read the private socket path: " .. tostring(result.stderr))
    vim.env.TMUX = vim.trim(result.stdout) .. ",0,0"
    vim.env.TMUX_PANE = pane
  end

  --- The panes of %0's window other than %0, by id.
  ---@return string[]
  local function siblings()
    local window = tmux("display-message", "-t", "%0", "-p", "#{window_id}").stdout or ""
    local listed = tmux("list-panes", "-t", vim.trim(window), "-F", "#{pane_id}").stdout or ""
    local ids = {}
    for line in listed:gmatch("[^\r\n]+") do
      if line ~= "%0" then
        ids[#ids + 1] = line
      end
    end
    return ids
  end

  setup(function()
    if vim.fn.executable("tmux") ~= 1 then
      error("tmux is required for pigeon.transport.tmux specs")
    end
    adapter = require("pigeon.transport.tmux")
    socket = "pigeon-test-" .. vim.fn.getpid()
    saved_tmux, saved_pane = vim.env.TMUX, vim.env.TMUX_PANE
    reset_server()
  end)

  before_each(function()
    reset_server()
  end)

  teardown(function()
    reset_server()
    vim.env.TMUX = saved_tmux
    vim.env.TMUX_PANE = saved_pane
  end)

  it("matches when this Neovim is inside tmux", function()
    vim.env.TMUX = nil
    assert.is_false(adapter.matches())
    vim.env.TMUX = saved_tmux or "/tmp/pigeon,0,0"
    assert.is_true(adapter.matches())
  end)

  it("lists only the current window's siblings, never itself", function()
    start("sleep 300")
    tmux("split-window", "-t", "m", "-d", "sleep 300") -- this window: three panes
    tmux("split-window", "-t", "m", "-d", "sleep 300")
    tmux("new-window", "-t", "m", "-n", "other", "sleep 300")
    tmux("split-window", "-t", "m", "-d", "sleep 300") -- another window: two
    enter("%0")

    local peers, err = adapter.peers()
    assert.are.equal(nil, err)
    assert.are.equal(2, #peers)
  end)

  it("reports an empty inventory when the window has no siblings", function()
    start("sleep 300")
    enter("%0")

    local peers, err = adapter.peers()
    assert.are.equal(nil, err)
    assert.are.same({}, peers)
  end)

  it("drops a dead pane from the inventory", function()
    start("sleep 300")
    tmux("set-option", "-t", "m", "remain-on-exit", "on")
    tmux("split-window", "-t", "m", "-d", "true") -- exits at once; lingers as a corpse
    tmux("split-window", "-t", "m", "-d", "sleep 300")
    enter("%0")

    local died = vim.wait(2000, function()
      local listed = tmux("list-panes", "-t", "m", "-F", "#{pane_dead}").stdout or ""
      return listed:find("1", 1, true) ~= nil
    end, 20)
    assert(died, "the fixture pane never reported as dead")

    local peers, err = adapter.peers()
    assert.are.equal(nil, err)
    assert.are.equal(1, #peers)
  end)

  it("reads a stopped server as an empty inventory, not an error", function()
    start("sleep 300")
    enter("%0")
    reset_server()

    local peers, err = adapter.peers()
    assert.are.equal(nil, err)
    assert.are.same({}, peers)
  end)

  it("names every pane distinctly in its repr", function()
    start("sleep 300")
    tmux("split-window", "-t", "m", "-d", "sleep 300")
    tmux("split-window", "-t", "m", "-d", "sleep 300")
    enter("%0")

    local peers = adapter.peers()
    assert.are.equal(2, #peers)

    local seen = {}
    for _, p in ipairs(peers) do
      local repr = p:repr()
      assert.are.equal("string", type(repr))
      assert(#repr > 0, "repr must not be empty")
      assert(seen[repr] == nil, "two panes share a repr: " .. repr)
      seen[repr] = true
    end
  end)

  it("hands the renderer the target pane's working directory", function()
    start("cat")
    tmux("split-window", "-t", "m", "-d", "-c", "/etc", "cat")
    enter("%0")

    local seen
    local ok, err = adapter.peers()[1]:send(function(ctx)
      seen = ctx
      return "pigeon"
    end)
    assert.is_true(ok)
    assert.are.equal(nil, err)
    assert.are.equal("/etc", seen.cwd)
  end)

  it("hands the renderer the target pane's own command lines", function()
    start("cat")
    tmux("split-window", "-t", "m", "-d", "sleep 300")
    enter("%0")

    local seen
    local ok = adapter.peers()[1]:send(function(ctx)
      seen = ctx
      return "pigeon"
    end)
    assert.is_true(ok)

    local found = false
    for _, cmd in ipairs(seen.process or {}) do
      if cmd:find("sleep 300", 1, true) then
        found = true
      end
    end
    assert(found, "the pane's own command line must be in the process chain")
  end)

  it("delivers multi-line text verbatim", function()
    start("cat")
    tmux("split-window", "-t", "m", "-d", "cat")
    local target = siblings()[1]
    enter("%0")

    local ok, err = adapter.peers()[1]:send(function()
      return "pigeon-one\npigeon-two"
    end)
    assert.is_true(ok)
    assert.are.equal(nil, err)

    vim.wait(300)
    local captured = tmux("capture-pane", "-t", target, "-p").stdout or ""
    assert.is_truthy(captured:find("pigeon-one", 1, true))
    assert.is_truthy(captured:find("pigeon-two", 1, true))
  end)

  it("delivers without submitting", function()
    start("sh")
    tmux("split-window", "-t", "m", "-d", "sh")
    local target = siblings()[1]
    enter("%0")

    local ok, err = adapter.peers()[1]:send(function()
      return "echo PIGEON_MARKER"
    end)
    assert.is_true(ok)
    assert.are.equal(nil, err)

    vim.wait(300)
    local captured = tmux("capture-pane", "-t", target, "-p").stdout or ""
    -- The typed text is echoed on the prompt line; an executed command would
    -- leave a line that is exactly the marker.
    assert.is_truthy(captured:find("echo PIGEON_MARKER", 1, true))
    for line in captured:gmatch("[^\r\n]+") do
      assert.are_not.equal("PIGEON_MARKER", vim.trim(line))
    end
  end)
end)
