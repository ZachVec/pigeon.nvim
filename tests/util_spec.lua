---@module 'luassert'

local Util = require("pigeon.util")

describe("pigeon.util", function()
  describe("relpath", function()
    it("relativizes a descendant", function()
      assert.are.equal("a/b.lua", Util.relpath("/tmp/pigeon", "/tmp/pigeon/a/b.lua"))
    end)

    it("keeps a path that escapes the base absolute", function()
      assert.are.equal("/etc/passwd", Util.relpath("/tmp/pigeon", "/etc/passwd"))
    end)

    it("keeps the base itself absolute", function()
      assert.are.equal("/tmp/pigeon", Util.relpath("/tmp/pigeon", "/tmp/pigeon"))
    end)

    it("keeps the path unchanged when there is no base", function()
      assert.are.equal("/etc/passwd", Util.relpath(nil, "/etc/passwd"))
      assert.are.equal("/etc/passwd", Util.relpath("", "/etc/passwd"))
    end)

    it("does not treat a sibling with a shared prefix as a descendant", function()
      assert.are.equal("/tmp/pigeon-other/a.lua", Util.relpath("/tmp/pigeon", "/tmp/pigeon-other/a.lua"))
    end)

    it("tolerates a base spelled with a trailing slash", function()
      assert.are.equal("a/b.lua", Util.relpath("/tmp/pigeon/", "/tmp/pigeon/a/b.lua"))
    end)
  end)

  describe("tilde", function()
    it("folds the home directory and leaves everything else alone", function()
      local home = vim.fn.getenv("HOME")
      if home == nil or home == vim.NIL or home == "" then
        return
      end
      assert.are.equal("~", Util.tilde(home))
      assert.are.equal("~/x", Util.tilde(home .. "/x"))
      assert.are.equal("/etc/passwd", Util.tilde("/etc/passwd"))
    end)
  end)

  describe("interpolate", function()
    local allowed = { known = true }

    it("resolves a known placeholder", function()
      local rendered = Util.interpolate("{known}", allowed, function()
        return "v"
      end)
      assert.are.equal("v", rendered)
    end)

    it("leaves an unknown placeholder literal", function()
      local rendered = Util.interpolate("{nope}", allowed, function()
        return "v"
      end)
      assert.are.equal("{nope}", rendered)
    end)

    it("fails, naming the placeholder, when its resolver returns nil", function()
      local rendered, failed = Util.interpolate("{known}", allowed, function()
        return nil
      end)
      assert.is_nil(rendered)
      assert.are.equal("known", failed)
    end)
  end)
end)
