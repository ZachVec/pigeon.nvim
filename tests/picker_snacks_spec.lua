---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.picker.snacks", function()
  local Snacks
  local captured
  local items

  --- A stream that emits its list at once.
  ---@param list pigeon.picker.Entry[]
  ---@return fun(emit: fun(entries: pigeon.picker.Entry[]), done: fun()): (fun()?)
  local function source(list)
    return function(emit, done)
      emit(list)
      done()
    end
  end

  --- A picker surface just wide enough for the adapter.
  ---@param marked? pigeon.picker.Entry[]
  ---@return pigeon.SnacksPicker
  local function picker(marked)
    return {
      close = function() end,
      refresh = function() end,
      selected = function()
        return vim.deepcopy(marked or items)
      end,
    }
  end

  --- A snacks-like async task driving one drain run: `suspend` parks the drain
  --- coroutine, `resume` re-enters it, and `fire_abort` calls the handler the
  --- adapter registered. snacks delivers a run's abort a tick after the finder
  --- call that superseded it, so the test fires it by hand at that moment.
  ---@return table
  local function async_task()
    local self = { suspended = false }
    local co
    function self.suspend()
      self.suspended = true
      coroutine.yield()
    end
    function self.resume()
      if co and self.suspended then
        self.suspended = false
        coroutine.resume(co)
      end
    end
    function self.on(_, event, cb)
      if event == "abort" then
        self.abort_handler = cb
      end
    end
    function self.fire_abort()
      if self.abort_handler then
        self.abort_handler()
      end
    end
    function self.drain(drain)
      co = coroutine.create(drain)
      coroutine.resume(co)
      return self
    end
    return self
  end

  setup(function()
    Helpers.reload_pigeon()
    items = {
      { text = "first row" },
      { text = "second row" },
    }
    package.loaded["snacks.picker"] = {
      pick = function(opts)
        captured = opts
      end,
    }
    Snacks = require("pigeon.picker.snacks")
  end)

  teardown(function()
    package.loaded["snacks.picker"] = nil
    Helpers.reload_pigeon()
  end)

  it("renders a stream that ended in the finder call as a static list, and leaves entries alone", function()
    local before = vim.deepcopy(items[1])
    Snacks.pick({ prompt = "pick", many = false, items = source(items) }, function() end)

    local list = captured.finder({}, {})
    assert.are.equal("first row", list[1].text)
    assert.are.same(before, items[1])
    -- A pick without commands binds no actions and no pane keymaps.
    assert.is_nil(captured.actions)
    assert.is_nil(captured.win.input)
    assert.is_nil(captured.win.list)
  end)

  it("confirms every marked entry when the flow acts on several", function()
    local chosen
    Snacks.pick({ prompt = "pick", many = true, items = source(items) }, function(entries)
      chosen = entries
    end)

    captured.confirm(picker())
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(2, #chosen)
    assert.are.equal("first row", chosen[1].text)
  end)

  it("confirms the entry under the cursor when the flow acts on one", function()
    local chosen
    Snacks.pick({ prompt = "pick", many = false, items = source(items) }, function(entries)
      chosen = entries
    end)

    captured.confirm(picker(), items[2])
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(1, #chosen)
    assert.are.equal("second row", chosen[1].text)
  end)

  it("closes the picker before handing the choice to the flow", function()
    local events = {}
    Snacks.pick({ prompt = "pick", many = false, items = source(items) }, function()
      events[#events + 1] = "choices"
    end)

    local surface = picker()
    surface.close = function()
      events[#events + 1] = "close"
    end
    captured.confirm(surface, items[1])
    vim.wait(500, function()
      return #events == 2
    end)

    assert.are.same({ "close", "choices" }, events)
  end)

  it("closes without a choice when nothing is selected", function()
    local chosen = false
    Snacks.pick({ prompt = "pick", many = true, items = source({}) }, function()
      chosen = true
    end)

    local closed = false
    local surface = picker({})
    surface.close = function()
      closed = true
    end
    captured.confirm(surface, nil)
    vim.wait(100, function()
      return false
    end)

    assert.is_true(closed)
    assert.is_false(chosen)
  end)

  it("previews the highlighted entry when the flow asked for a preview", function()
    local rendered
    Snacks.pick({
      prompt = "pick",
      many = false,
      preview = function()
        return { "line" }
      end,
      items = source(items),
    }, function() end)

    assert.is_not_nil(captured.preview)
    assert.is_not_nil(captured.win.preview.wo)
    captured.preview({
      item = items[1],
      preview = {
        reset = function() end,
        set_title = function() end,
        set_lines = function(_, lines)
          rendered = lines
        end,
      },
    })
    assert.are.same({ "line" }, rendered)
  end)

  it("hides the preview pane without a preview function", function()
    Snacks.pick({ prompt = "pick", many = false, items = source(items) }, function() end)

    assert.is_nil(captured.preview)
    assert.is_false(captured.layout.preview)
    assert.is_nil(captured.win.preview)
  end)

  it("streams a live source inside snacks' async task", function()
    local emit, done
    Snacks.pick({
      prompt = "pick",
      many = false,
      items = function(emit_, done_)
        emit, done = emit_, done_
      end,
    }, function() end)

    local co
    local task = {
      suspend = function()
        coroutine.yield()
      end,
      resume = function()
        coroutine.resume(co)
      end,
      on = function() end,
    }
    local received = {}
    co = coroutine.create(function()
      captured.finder({}, { async = task })(function(item)
        received[#received + 1] = item.text
      end)
    end)
    coroutine.resume(co)

    emit({ { text = "first" } })
    emit({ { text = "second" } })
    done()

    assert.are.same({ "first", "second" }, received)
  end)

  it("stops a live stream when the task aborts", function()
    local abort
    local cancelled = false
    Snacks.pick({
      prompt = "pick",
      many = false,
      items = function(emit)
        emit({ { text = "first" } })
        return function()
          cancelled = true
        end
      end,
    }, function() end)

    local co
    local task = {
      suspend = function()
        coroutine.yield()
      end,
      resume = function()
        coroutine.resume(co)
      end,
      on = function(_, event, cb)
        if event == "abort" then
          abort = cb
        end
      end,
    }
    co = coroutine.create(function()
      captured.finder({}, { async = task })(function() end)
    end)
    coroutine.resume(co)

    abort()
    assert.is_true(cancelled)
  end)

  it("ignores a superseded run's abort and keeps the re-run's stream streaming", function()
    local sources = {}
    Snacks.pick({
      prompt = "pick",
      many = false,
      items = function(emit, done)
        local stream = { emit = emit, done = done, cancelled = false }
        function stream.cancel()
          stream.cancelled = true
        end
        sources[#sources + 1] = stream
        return stream.cancel
      end,
    }, function() end)

    local received = {}
    local function cb(item)
      received[#received + 1] = item.text
    end

    -- Run 1's live stream parks the drain with an empty queue.
    local first = async_task()
    first.drain(function()
      captured.finder({}, { async = first })(cb)
    end)
    assert.is_false(sources[1].cancelled)

    -- A finder re-run (snacks' toggle keys) starts run 2, abandoning run 1.
    local second = async_task()
    second.drain(function()
      captured.finder({}, { async = second })(cb)
    end)
    assert.is_true(sources[1].cancelled)

    -- snacks delivers run 1's abort only after run 2 has started.
    first.fire_abort()
    assert.is_false(sources[2].cancelled)

    -- Run 2's stream is intact: its batches still arrive and it ends on done.
    sources[2].emit({ { text = "fresh" } })
    sources[2].done()
    assert.are.same({ "fresh" }, received)
  end)
end)
