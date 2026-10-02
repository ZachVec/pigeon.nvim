---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.deliver", function()
  local Deliver
  local pick_spec
  local pick_choices
  local peers
  local peer_list_calls
  local reachable

  --- A stand-in peer: renders for its own working directory, then records what
  --- it was handed (or fails, when asked to).
  ---@param cwd string
  ---@param name string
  ---@param opts? { fail?: boolean }
  local function peer(cwd, name, opts)
    local self = { sent = {} }
    function self:repr()
      return name
    end
    function self:send(render)
      if opts and opts.fail then
        return false, "pane is gone"
      end
      local text, why = render({ cwd = cwd })
      if text == nil then
        return false, why
      end
      self.sent[#self.sent + 1] = text
      return true, nil
    end
    return self
  end

  ---@param p pigeon.Peer
  ---@return pigeon.deliver.PeerEntry
  local function entry(p)
    return { text = p:repr(), peer = p }
  end

  --- The entries a target pick would offer.
  ---@param spec pigeon.PickSpec
  ---@return pigeon.picker.Entry[]
  local function offered(spec)
    local items, finished = {}, false
    spec.items(function(chunk)
      vim.list_extend(items, chunk)
    end, function()
      finished = true
    end)
    assert(finished, "the target pick's source did not finish")
    return items
  end

  setup(function()
    Helpers.reload_pigeon()

    local adapter = {}
    function adapter.peers()
      peer_list_calls = peer_list_calls + 1
      return peers
    end
    package.loaded["pigeon.transport"] = {
      get = function()
        if reachable then
          return adapter, nil
        end
        return nil, "not inside a supported multiplexer"
      end,
    }

    local picker = {}
    function picker.pick(spec, on_choices)
      pick_spec, pick_choices = spec, on_choices
    end
    package.loaded["pigeon.picker"] = picker

    Deliver = require("pigeon.deliver")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    peers = {}
    peer_list_calls = 0
    pick_spec, pick_choices = nil, nil
    reachable = true
    Deliver.reset()
  end)

  it("delivers straight to the only sibling and remembers it", function()
    local only = peer("/tmp/p", "0.1")
    peers = { only }

    local notes = Helpers.notifications(function()
      Deliver.run(function()
        return "hi"
      end)
    end)

    assert.are.same({ "hi" }, only.sent)
    assert.are.same({}, notes)
    assert.are.equal(1, peer_list_calls)

    -- The remembered target is used without asking again.
    Deliver.run(function()
      return "again"
    end)
    assert.are.same({ "hi", "again" }, only.sent)
    assert.are.equal(1, peer_list_calls)
  end)

  it("asks which pane when several siblings are reachable", function()
    local a, b = peer("/tmp/a", "0.1"), peer("/tmp/b", "0.2")
    peers = { a, b }

    Deliver.run(function()
      return "hi"
    end)

    assert.is_true(pick_spec.many)
    assert.are.equal(2, #offered(pick_spec))
    assert.are.same({}, a.sent)
    assert.are.same({}, b.sent)

    pick_choices({ entry(a) })
    assert.are.same({ "hi" }, a.sent)
    assert.are.same({}, b.sent)

    -- A single choice becomes the session's target.
    Deliver.run(function()
      return "again"
    end)
    assert.are.same({ "hi", "again" }, a.sent)
    assert.are.equal(1, peer_list_calls)
  end)

  it("broadcasts to every chosen pane without remembering one", function()
    local a, b = peer("/tmp/a", "0.1"), peer("/tmp/b", "0.2")
    peers = { a, b }

    Deliver.run(function()
      return "hi"
    end)
    pick_choices({ entry(a), entry(b) })

    assert.are.same({ "hi" }, a.sent)
    assert.are.same({ "hi" }, b.sent)
    assert.is_nil(Deliver.target())

    -- Nothing remembered: the next send asks again.
    Deliver.run(function()
      return "again"
    end)
    assert.are.equal(2, peer_list_calls)
  end)

  it("renders once per target, against that pane's own working directory", function()
    local a, b = peer("/tmp/a", "0.1"), peer("/tmp/b", "0.2")
    peers = { a, b }
    local seen = {}

    Deliver.run(function(ctx)
      seen[#seen + 1] = ctx.cwd
      return "x"
    end)
    pick_choices({ entry(a), entry(b) })

    assert.are.same({ "/tmp/a", "/tmp/b" }, seen)
  end)

  it("reports a window with no other pane and sends nothing", function()
    peers = {}
    local notes = Helpers.notifications(function()
      Deliver.run(function()
        return "hi"
      end)
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("no other panes", 1, true))
    assert.is_nil(pick_spec)
  end)

  it("reports when this Neovim is not inside a multiplexer", function()
    reachable = false
    local notes = Helpers.notifications(function()
      Deliver.run(function()
        return "hi"
      end)
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("not inside a supported multiplexer", 1, true))
  end)

  it("reports a failed delivery against the pane it was meant for", function()
    peers = { peer("/tmp/p", "0.1", { fail = true }) }
    local notes = Helpers.notifications(function()
      Deliver.run(function()
        return "hi"
      end)
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("0.1", 1, true))
    assert.is_truthy(notes[1]:find("pane is gone", 1, true))
  end)

  it("reports a renderer that declines instead of delivering", function()
    local only = peer("/tmp/p", "0.1")
    peers = { only }
    local notes = Helpers.notifications(function()
      Deliver.run(function()
        return nil, "no reference to send"
      end)
    end)
    assert.are.same({}, only.sent)
    assert.is_truthy(notes[1]:find("no reference to send", 1, true))
  end)

  it("retargets to a chosen pane and reports the new target", function()
    local a, b = peer("/tmp/a", "0.1"), peer("/tmp/b", "0.2")
    peers = { a, b }

    local notes = Helpers.notifications(function()
      Deliver.retarget()
      assert.is_false(pick_spec.many)
      pick_choices({ entry(b) })
    end)

    assert.are.equal(b, Deliver.target())
    assert.is_truthy(notes[1]:find("0.2", 1, true))
  end)
end)
