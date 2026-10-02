---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.picker", function()
  local Config
  local Picker

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Picker = require("pigeon.picker")
  end)

  teardown(function()
    package.loaded["fzf-lua"] = nil
    package.loaded["snacks.picker"] = nil
    Helpers.reload_pigeon()
  end)

  it("rejects an unknown picker name at setup", function()
    Config.setup({ picker = "nope" })
    assert.has_error(function()
      Picker.setup()
    end)
    Picker.reset()
  end)

  it("resolves the engine-backed pickers once their engine is loadable", function()
    package.loaded["fzf-lua"] = { fzf_exec = function() end }
    Config.setup({ picker = "fzf-lua" })
    Picker.setup()
    Picker.reset()

    package.loaded["snacks.picker"] = { pick = function() end }
    Config.setup({ picker = "snacks" })
    Picker.setup()
    Picker.reset()
  end)

  it("drains the stream, formats entries, and folds a many pick to one choice", function()
    Config.setup({ picker = "native" })
    Picker.setup()

    local seen
    local original = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      seen = { items = items, opts = opts }
      on_choice(items[2])
    end

    local chosen
    Picker.pick({
      prompt = "Send to: ",
      many = true,
      items = function(emit, done)
        emit({ { text = "a" } })
        emit({ { text = "b" } })
        done()
      end,
    }, function(entries)
      chosen = entries
    end)
    vim.ui.select = original

    assert.are.equal("Send to: ", seen.opts.prompt)
    assert.are.same({ "a", "b" }, vim.tbl_map(seen.opts.format_item, seen.items))
    assert.are.equal(1, #chosen)
    assert.are.equal("b", chosen[1].text)
  end)
end)
