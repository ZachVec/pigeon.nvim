---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.picker.fzf_lua", function()
  local Fzf
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

  --- The lines the captured contents function writes, with the end of input as
  --- a visible marker, plus how many pipe writes they arrived in.
  ---@return string[] lines
  ---@return integer writes
  local function written()
    local lines, writes = {}, 0
    captured.contents(function(line)
      if line == nil then
        lines[#lines + 1] = "<end>"
      else
        writes = writes + 1
        lines[#lines + 1] = line
      end
    end, function(batch)
      writes = writes + 1
      vim.list_extend(lines, batch)
    end)
    return lines, writes
  end

  setup(function()
    Helpers.reload_pigeon()
    items = {
      { text = "first" },
      { text = "second" },
    }
    package.loaded["fzf-lua"] = {
      fzf_exec = function(contents, opts)
        captured = { contents = contents, opts = opts }
      end,
    }
    Fzf = require("pigeon.picker.fzf_lua")
  end)

  teardown(function()
    package.loaded["fzf-lua"] = nil
    Helpers.reload_pigeon()
  end)

  it("writes one prefixed line per entry and ends the input", function()
    Fzf.pick({ prompt = "pick", many = false, items = source(items) }, function() end)

    local lines, writes = written()
    assert.are.same({ "1. first", "2. second", "<end>" }, lines)
    assert.are.equal(1, writes)
    assert.are.equal("2..", captured.opts.fzf_opts["--with-nth"])
    assert.is_nil(captured.opts.fzf_opts["--nth"])
  end)

  it("writes each emitted batch in one pipe write", function()
    Fzf.pick({
      prompt = "pick",
      many = false,
      items = function(emit, done)
        emit({ items[1] })
        emit({ items[2] })
        done()
      end,
    }, function() end)

    local lines, writes = written()
    assert.are.same({ "1. first", "2. second", "<end>" }, lines)
    assert.are.equal(2, writes)
  end)

  it("maps returned lines back to their entries and answers with every choice", function()
    local chosen
    Fzf.pick({ prompt = "pick", many = true, items = source(items) }, function(rows)
      chosen = rows
    end)
    written()

    assert.is_true(captured.opts.fzf_opts["--multi"])
    captured.opts.actions.default({ "2. second", "1. first" })
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(2, #chosen)
    assert.are.equal("second", chosen[1].text)
    assert.are.equal("first", chosen[2].text)
  end)

  it("asks for no marking when the flow acts on one entry", function()
    Fzf.pick({ prompt = "pick", many = false, items = source(items) }, function() end)

    assert.is_nil(captured.opts.fzf_opts["--multi"])
  end)

  it("previews the highlighted entry only when the flow asked for a preview", function()
    Fzf.pick({
      prompt = "pick",
      many = false,
      preview = function(entry)
        return entry.text == "second" and { "two" } or nil
      end,
      items = source(items),
    }, function() end)
    written()

    assert.are.equal("two", captured.opts.preview({ "2. second" }))
    -- A nil answer keeps the pane, empty.
    assert.are.equal("", captured.opts.preview({ "1. first" }))
  end)

  it("shows no preview pane without a preview function", function()
    Fzf.pick({ prompt = "pick", many = false, items = source(items) }, function() end)

    assert.is_nil(captured.opts.preview)
  end)

  it("stops a running stream when the picker closes", function()
    local cancelled = false
    Fzf.pick({
      prompt = "pick",
      many = false,
      items = function(emit)
        emit(items)
        return function()
          cancelled = true
        end
      end,
    }, function() end)

    written()
    captured.opts.winopts.on_close()
    assert.is_true(cancelled)
  end)
end)
