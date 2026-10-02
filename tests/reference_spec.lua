---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.reference", function()
  local Config
  local Formats
  local Reference

  --- A target with only a working directory: nothing runs there that a profile
  --- recognizes, so the configured format and the default are what apply.
  ---@param cwd string?
  ---@return pigeon.RenderCtx
  local function target(cwd)
    return { cwd = cwd }
  end

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Formats = require("pigeon.formats")
    Reference = require("pigeon.reference")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Formats.setup()
  end)

  it("spells a whole-file reference relative to the base", function()
    assert.are.equal("a/b.lua", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua"))
  end)

  it("spells a single line as :L<n>", function()
    assert.are.equal("a/b.lua :L42", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua", 42))
  end)

  it("spells a range as :L<start>-<end>", function()
    assert.are.equal("a/b.lua :L42-45", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua", 42, 45))
  end)

  it("collapses an empty range to a single line", function()
    assert.are.equal("a/b.lua :L42", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua", 42, 42))
  end)

  it("leaves the path absolute when the base is unknown", function()
    assert.are.equal("/tmp/p/a/b.lua", Reference.reference(target(nil), "/tmp/p/a/b.lua"))
  end)

  it("leaves the path absolute when it escapes the base", function()
    assert.are.equal("/etc/passwd", Reference.reference(target("/tmp/p"), "/etc/passwd"))
  end)

  it("has no reference for an empty path", function()
    assert.is_nil(Reference.reference(target("/tmp/p"), ""))
    assert.is_nil(Reference.reference(target("/tmp/p"), nil))
  end)

  it("spells through the profile of the program running in the target", function()
    local node = { cwd = "/tmp/p", process = { "sh", "node /nvm/bin/claude" } }
    assert.are.equal("@a/b.lua", Reference.reference(node, "/tmp/p/a/b.lua"))
    assert.are.equal("@a/b.lua#L42-45", Reference.reference(node, "/tmp/p/a/b.lua", 42, 45))
  end)

  it("spells the default format for a target running nothing a profile knows", function()
    local vim = { cwd = "/tmp/p", process = { "sh", "vim a/b.lua" } }
    assert.are.equal("a/b.lua :L42", Reference.reference(vim, "/tmp/p/a/b.lua", 42))
  end)

  it("lets a configured format hook decide the format", function()
    Config.setup({
      format = function(file, loc)
        return "@" .. file .. (loc and (" " .. loc) or "")
      end,
    })
    Formats.setup()
    assert.are.equal("@a/b.lua :L7", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua", 7))
  end)

  it("treats a hook that declines as no reference", function()
    Config.setup({
      format = function()
        return ""
      end,
    })
    Formats.setup()
    assert.is_nil(Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua"))
  end)

  it("spells the default format when the configured format was not a hook", function()
    Config.setup({ format = "nope" })
    Formats.setup()
    assert.are.equal("a/b.lua", Reference.reference(target("/tmp/p"), "/tmp/p/a/b.lua"))
  end)
end)
