---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.commands.prompts", function()
  local Config
  local Prompts
  local Formats
  local bufs = {}

  --- A named scratch buffer, wiped after the test.
  ---@param path string
  ---@return integer
  local function named(path)
    local buf = Helpers.buffer({ "a", "b", "c" }, path)
    bufs[#bufs + 1] = buf
    return buf
  end

  ---@param buf integer
  ---@param row integer
  ---@return pigeon.commands.prompts.Origin
  local function origin(buf, row)
    return { buf = buf, row = row }
  end

  --- A target with only a working directory.
  ---@param cwd string?
  ---@return pigeon.RenderCtx
  local function target(cwd)
    return { cwd = cwd }
  end

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Prompts = require("pigeon.commands.prompts")
    Formats = require("pigeon.formats")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Formats.setup()
  end)

  after_each(function()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
  end)

  it("spells {file} and {line} relative to the target's cwd", function()
    local buf = named("/tmp/proj/src/a.lua")
    assert.are.equal("src/a.lua", (Prompts.render("{file}", origin(buf, 1))(target("/tmp/proj"))))
    assert.are.equal("src/a.lua :L3", (Prompts.render("{line}", origin(buf, 3))(target("/tmp/proj"))))
  end)

  it("renders per target: absolute with no cwd, absolute outside it", function()
    local buf = named("/tmp/proj/src/a.lua")
    local render = Prompts.render("{file}", origin(buf, 1))
    assert.are.equal("src/a.lua", (render(target("/tmp/proj"))))
    assert.are.equal("/tmp/proj/src/a.lua", (render(target(nil))))
    assert.are.equal("/tmp/proj/src/a.lua", (render(target("/elsewhere"))))
  end)

  it("keeps a multi-line template's shape", function()
    local buf = named("/tmp/proj/a.lua")
    local render = Prompts.render("look at {file}\nand {line}", origin(buf, 2))
    assert.are.equal("look at a.lua\nand a.lua :L2", (render(target("/tmp/proj"))))
  end)

  it("fails the whole render, naming the placeholder, when one resolves empty", function()
    local buf = Helpers.buffer({ "a" }) -- unnamed: {file} has nothing to spell
    bufs[#bufs + 1] = buf
    local rendered, why = Prompts.render("{file} and {line}", origin(buf, 1))(target("/tmp"))
    assert.is_nil(rendered)
    assert.are.equal("{file} resolved empty", why)
  end)

  it("leaves an unknown placeholder literal", function()
    local buf = named("/tmp/proj/a.lua")
    assert.are.equal("x{nope}y", (Prompts.render("x{nope}y", origin(buf, 1))(target("/tmp/proj"))))
  end)

  it("warns about a configured template naming an unknown placeholder", function()
    Config.setup({ prompts = { bad = "hello {nope}" } })
    local notes = Helpers.notifications(function()
      Prompts.setup()
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("{nope}", 1, true))
  end)

  it("drops a template that is not a string", function()
    local notes = Helpers.notifications(function()
      Config.setup({ prompts = { bad = 42 } })
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("bad", 1, true))
    assert.is_nil(Config.options.prompts.bad)
    assert.are.equal("{file}", Config.options.prompts["{file}"])
  end)
end)
