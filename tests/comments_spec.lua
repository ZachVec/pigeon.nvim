---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.commands.comments", function()
  local Comments
  local Config
  local Formats
  local bufs = {}

  --- A named scratch buffer, wiped after the test.
  ---@param path string
  ---@param lines? string[]
  ---@return integer
  local function named(path, lines)
    local buf = Helpers.buffer(lines or { "a", "b", "c" }, path)
    bufs[#bufs + 1] = buf
    return buf
  end

  --- One comment over `start_row..end_row`.
  ---@param buf integer
  ---@param start_row integer
  ---@param end_row integer
  ---@param note string
  ---@return pigeon.Comment
  local function comment(buf, start_row, end_row, note)
    return { buf = buf, start_row = start_row, end_row = end_row, note = note }
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
    Comments = require("pigeon.commands.comments")
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

  it("renders the note after the range's reference", function()
    local buf = named("/tmp/proj/a.lua")
    local one = comment(buf, 2, 3, "needs a guard")
    assert.are.equal("a.lua :L2-3 needs a guard\n", (Comments.render(one, target("/tmp/proj"))))
  end)

  it("spells the reference per target: absolute with no cwd, absolute outside it", function()
    local buf = named("/tmp/proj/src/a.lua")
    local one = comment(buf, 1, 1, "why")
    assert.are.equal("src/a.lua :L1 why\n", (Comments.render(one, target("/tmp/proj"))))
    assert.are.equal("/tmp/proj/src/a.lua :L1 why\n", (Comments.render(one, target(nil))))
    assert.are.equal("/tmp/proj/src/a.lua :L1 why\n", (Comments.render(one, target("/elsewhere"))))
  end)

  it("renders the building blocks {file}, {start} and {end}", function()
    Config.setup({ comments = { item = "{file} {start}-{end}" } })
    local buf = named("/tmp/proj/a.lua")
    assert.are.equal("a.lua 2-4", (Comments.render(comment(buf, 2, 4, "n"), target("/tmp/proj"))))
  end)

  it("spells the reference through the configured format hook", function()
    Config.setup({
      comments = { item = "{lines}" },
      format = function(file, loc)
        return "@" .. file .. (loc and (" " .. loc) or "")
      end,
    })
    Formats.setup()
    local buf = named("/tmp/proj/src/a.lua")
    local one = comment(buf, 2, 3, "n")
    assert.are.equal("@src/a.lua :L2-3", (Comments.render(one, target("/tmp/proj"))))
  end)

  it("fails the render, naming the field, when the range has no reference", function()
    Config.setup({
      format = function()
        return nil
      end,
    })
    Formats.setup()
    local buf = named("/tmp/proj/a.lua")
    local rendered, failed = Comments.render(comment(buf, 1, 1, "n"), target("/tmp/proj"))
    assert.is_nil(rendered)
    assert.are.equal("lines", failed)
  end)

  it("leaves an unknown placeholder literal", function()
    Config.setup({ comments = { item = "{lines} {nope}" } })
    local buf = named("/tmp/proj/a.lua")
    local one = comment(buf, 1, 1, "n")
    assert.are.equal("a.lua :L1 {nope}", (Comments.render(one, target("/tmp/proj"))))
  end)

  it("renders exactly the template, adding no newline of its own", function()
    Config.setup({ comments = { item = "{note}" } })
    local buf = named("/tmp/proj/a.lua")
    assert.are.equal("why", (Comments.render(comment(buf, 1, 1, "why"), target("/tmp/proj"))))
  end)

  it("warns about an item template naming an unknown placeholder", function()
    Config.setup({ comments = { item = "{nope}" } })
    local notes = Helpers.notifications(function()
      Comments.setup()
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("{nope}", 1, true))
  end)
end)
