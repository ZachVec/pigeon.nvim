---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.formats", function()
  local Config
  local Formats

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Formats = require("pigeon.formats")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Formats.setup()
  end)

  --- What one location reads as for a target whose one command line is `cmd`.
  ---@param cmd string
  ---@return string
  local function spell(cmd)
    return Formats.resolve({ cmd })("a/b.lua", ":L7")
  end

  it("ships a claude profile: an @ mention with a #L range", function()
    local cmd = "/nvm/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
    assert.are.equal("@a/b.lua#L7", spell(cmd))
  end)

  it("quotes a claude mention whose path leaves the characters a mention carries", function()
    local hook = Formats.resolve({ "claude" })
    assert.are.equal('@"a b.lua"#L7', hook("a b.lua", ":L7"))
  end)

  it("ships a codex profile: a plain path with a :L range", function()
    assert.are.equal("a/b.lua :L7", spell("node /nvm/bin/codex"))
  end)

  it("recognizes a program only as a whole word", function()
    assert.are.equal("a/b.lua :L7", spell("vim /home/u/mycodex_helper"))
    assert.are.equal("a/b.lua :L7", spell("vim /home/u/myclaude_notes"))
  end)

  it("reads the default format when nothing is recognized", function()
    assert.are.equal("a/b.lua :L7", Formats.resolve({ "sh", "vim a/b.lua" })("a/b.lua", ":L7"))
    assert.are.equal("a/b.lua", Formats.resolve(nil)("a/b.lua", nil))
  end)

  it("falls back to the configured hook, which a Profile still beats", function()
    Config.setup({
      format = function(file, loc)
        return "!" .. file .. (loc or "")
      end,
    })
    Formats.setup()
    assert.are.equal("!a/b.lua:L7", spell("vim a/b.lua"))
    assert.are.equal("@a/b.lua#L7", spell("claude"))
  end)

  it("asks the outermost process first", function()
    -- Both programs appear in the chain; the one nearer the pane decides.
    local hook = Formats.resolve({ "sh -c codex", "claude" })
    assert.are.equal("a/b.lua :L7", hook("a/b.lua", ":L7"))
  end)

  it("resolves the built-in profiles in order", function()
    assert.are.same({ "claude", "codex" }, Formats.names())
  end)
end)
