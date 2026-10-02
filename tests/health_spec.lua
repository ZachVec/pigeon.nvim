---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.health", function()
  local Health
  local reports

  --- What `:checkhealth pigeon` would print, as `{ level, message }` rows.
  local function report(check)
    local saved = vim.health
    local stub = {}
    reports = {}
    for _, name in ipairs({ "start", "ok", "warn", "error" }) do
      stub[name] = function(msg)
        reports[#reports + 1] = { name, msg }
      end
    end
    -- `health.lua` captures these at load time, so the stub goes in first.
    vim.health = setmetatable(stub, { __index = saved })
    Helpers.reload_pigeon()
    Health = require("pigeon.health")
    local ok, err = pcall(check)
    vim.health = saved
    Helpers.reload_pigeon()
    assert(ok, err)
  end

  teardown(function()
    package.preload["pigeon.transport"] = nil
    Helpers.reload_pigeon()
  end)

  it("reports the version, the multiplexer, and the picker", function()
    report(function()
      package.loaded["pigeon.transport"] = {
        get = function()
          return {}, nil
        end,
        name = function()
          return "tmux"
        end,
      }
      require("pigeon.config").setup({ picker = "snacks" })
      Health.check()
    end)

    assert.are.same({ "start", "pigeon" }, reports[1])
    assert.are.same({ "ok", "Neovim >= 0.11" }, reports[2])
    assert.are.same({ "ok", "multiplexer: tmux" }, reports[3])
    assert.are.same({ "ok", "picker: snacks" }, reports[4])
  end)

  it("warns, with the reason, when no multiplexer is detected", function()
    report(function()
      package.loaded["pigeon.transport"] = {
        get = function()
          return nil, "TMUX_PANE is not set"
        end,
        name = function()
          return "tmux"
        end,
      }
      Health.check()
    end)

    assert.are.same({ "warn", "multiplexer: none (TMUX_PANE is not set)" }, reports[3])
  end)

  it("stops at the transport when it cannot be loaded", function()
    report(function()
      package.loaded["pigeon.transport"] = nil
      package.preload["pigeon.transport"] = function()
        error("boom")
      end
      Health.check()
    end)

    assert.are.equal(3, #reports, "the picker line must not run after a load failure")
    assert.are.equal("error", reports[3][1])
    assert.is_truthy(reports[3][2]:find("boom", 1, true))
  end)
end)
