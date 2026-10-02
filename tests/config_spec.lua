---@module 'luassert'

local Helpers = require("helpers")

--- The option table and its shape checks. What a value *selects* — the format
--- a format hook spells, the picker a name resolves to — is the owning
--- module's spec (`references_spec`, `picker_spec`).
describe("pigeon.config", function()
  local Config

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  it("fills in the documented defaults", function()
    Config.setup()
    assert.are.equal("auto", Config.options.multiplexer)
    assert.are.equal("native", Config.options.picker)
    assert.are.equal("a/b.lua :L42", Config.options.format("a/b.lua", ":L42"))
    assert.are.equal("a/b.lua", Config.options.format("a/b.lua", nil))
    assert.are.equal("\n", Config.options.references.join)
    assert.are.equal("{lines} {note}\n", Config.options.comments.item)
  end)

  it("merges opts over the defaults without dropping their siblings", function()
    Config.setup({ comments = { item = "{note}" } })
    assert.are.equal("{note}", Config.options.comments.item)
    assert.are.equal("{line}", Config.options.prompts["{line}"])
  end)

  it("drops a format that is not a hook, and says so", function()
    local notes = Helpers.notifications(function()
      Config.setup({ format = "nope" })
    end)
    assert.are.equal("a/b.lua :L42", Config.options.format("a/b.lua", ":L42"))
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("format", 1, true))
  end)

  it("says nothing when no format was configured", function()
    local notes = Helpers.notifications(function()
      Config.setup()
    end)
    assert.are.same({}, notes)
  end)

  it("falls back to the default item when comments.item is not a string", function()
    local notes = Helpers.notifications(function()
      Config.setup({ comments = { item = 42 } })
    end)
    assert.are.equal("{lines} {note}\n", Config.options.comments.item)
    assert.are.equal(1, #notes)
  end)
end)
