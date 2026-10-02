---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon", function()
  setup(function()
    Helpers.reload_pigeon()
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "Pigeon")
    Helpers.reload_pigeon()
  end)

  it("installs :Pigeon once the configuration resolves", function()
    require("pigeon").setup({ multiplexer = "auto", picker = "native" })
    assert.are.equal(2, vim.fn.exists(":Pigeon"))
  end)

  it("leaves no command behind when the picker is unknown", function()
    local ok = pcall(function()
      require("pigeon").setup({ picker = "nope" })
    end)
    assert.is_false(ok)
    assert.are.equal(0, vim.fn.exists(":Pigeon"))
  end)
end)
