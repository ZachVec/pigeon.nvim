---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.reference", function()
  local Config
  local Reference

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Reference = require("pigeon.reference")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Reference.setup()
  end)

  it("spells a whole-file reference relative to the base", function()
    assert.are.equal("a/b.lua", Reference.reference("/tmp/p", "/tmp/p/a/b.lua"))
  end)

  it("spells a single line as :L<n>", function()
    assert.are.equal("a/b.lua :L42", Reference.reference("/tmp/p", "/tmp/p/a/b.lua", 42))
  end)

  it("spells a range as :L<start>-<end>", function()
    assert.are.equal("a/b.lua :L42-45", Reference.reference("/tmp/p", "/tmp/p/a/b.lua", 42, 45))
  end)

  it("collapses an empty range to a single line", function()
    assert.are.equal("a/b.lua :L42", Reference.reference("/tmp/p", "/tmp/p/a/b.lua", 42, 42))
  end)

  it("leaves the path absolute when the base is unknown", function()
    assert.are.equal("/tmp/p/a/b.lua", Reference.reference(nil, "/tmp/p/a/b.lua"))
  end)

  it("leaves the path absolute when it escapes the base", function()
    assert.are.equal("/etc/passwd", Reference.reference("/tmp/p", "/etc/passwd"))
  end)

  it("has no reference for an empty path", function()
    assert.is_nil(Reference.reference("/tmp/p", ""))
    assert.is_nil(Reference.reference("/tmp/p", nil))
  end)

  it("lets a configured format hook decide the dialect", function()
    Config.setup({
      format = function(file, loc)
        return "@" .. file .. (loc and (" " .. loc) or "")
      end,
    })
    Reference.setup()
    assert.are.equal("@a/b.lua :L7", Reference.reference("/tmp/p", "/tmp/p/a/b.lua", 7))
  end)

  it("treats a hook that declines as no reference", function()
    Config.setup({
      format = function()
        return ""
      end,
    })
    Reference.setup()
    assert.is_nil(Reference.reference("/tmp/p", "/tmp/p/a/b.lua"))
  end)

  it("spells the default dialect when the configured format was not a hook", function()
    Config.setup({ format = "nope" })
    Reference.setup()
    assert.are.equal("a/b.lua", Reference.reference("/tmp/p", "/tmp/p/a/b.lua"))
  end)
end)
