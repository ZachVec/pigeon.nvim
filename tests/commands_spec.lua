---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.commands", function()
  local Commands
  local Config
  local pick_spec
  local pick_choices
  local delivered_render
  local Formats
  local References
  local input_opts
  local original_input
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

  --- Run `:Pigeon` with the given words.
  ---@param fargs string[]
  local function run(fargs)
    Commands.run({ fargs = fargs, line1 = 1, line2 = 1 })
  end

  --- Make the next `vim.ui.input` answer with `note`; nil stands for Esc.
  ---@param note string?
  local function answer_prompt(note)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.input = function(opts, cb)
      input_opts = opts
      cb(note)
    end
  end

  --- The entries a captured pick offers.
  ---@param spec pigeon.PickSpec
  ---@return pigeon.picker.Entry[]
  local function offered(spec)
    local items, finished = {}, false
    spec.items(function(chunk)
      vim.list_extend(items, chunk)
    end, function()
      finished = true
    end)
    assert(finished, "the pick's source did not finish")
    return items
  end

  --- The offered entry whose name is `name`.
  ---@param spec pigeon.PickSpec
  ---@param name string
  ---@return pigeon.picker.Entry
  local function named_entry(spec, name)
    for _, entry in ipairs(offered(spec)) do
      if entry.text == name then
        return entry
      end
    end
    error(("no entry named '%s'"):format(name))
  end

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Formats = require("pigeon.formats")
    original_input = vim.ui.input

    local picker = {}
    --- Faithful to the pickers people actually run: a float-based
    --- `vim.ui.select` (snacks, fzf-lua, dressing) has its own buffer current
    --- while the flow's callback runs, so a flow that reads the buffer or
    --- cursor in `on_choices` is caught here.
    function picker.pick(spec, on_choices)
      pick_spec, pick_choices = spec, on_choices
      local floating = vim.api.nvim_create_buf(false, true)
      bufs[#bufs + 1] = floating
      vim.api.nvim_set_current_buf(floating)
    end
    package.loaded["pigeon.picker"] = picker

    local deliver = {}
    function deliver.run(render)
      delivered_render = render
    end
    function deliver.target()
      return nil
    end
    function deliver.retarget() end
    package.loaded["pigeon.deliver"] = deliver

    package.loaded["pigeon.transport"] = {
      get = function()
        return { peers = function() end }, nil
      end,
      name = function()
        return "tmux"
      end,
    }

    -- The flows capture their seams at load time, so the fakes go in first.
    References = require("pigeon.commands.references")
    Commands = require("pigeon.commands")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Formats.setup()
    pick_spec, pick_choices = nil, nil
    delivered_render, input_opts = nil, nil
  end)

  after_each(function()
    vim.ui.input = original_input
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
  end)

  it("states the usage when given no subcommand", function()
    local notes = Helpers.notifications(function()
      run({})
    end)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find(":Pigeon prompt", 1, true))
  end)

  it("reports an unknown subcommand and states the usage", function()
    local notes = Helpers.notifications(function()
      run({ "nope" })
    end)
    assert.are.equal(2, #notes)
    assert.is_truthy(notes[1]:find("unknown subcommand 'nope'", 1, true))
  end)

  it("completes the subcommand names", function()
    assert.is_truthy(vim.tbl_contains(Commands.complete("", "Pigeon "), "prompt"))
    assert.are.same({ "send", "status" }, Commands.complete("s", "Pigeon "))
    assert.are.same({}, Commands.complete("l", "Pigeon comment "))
  end)

  it("offers the prompt names and renders from the invoking buffer, not the pick", function()
    local buf = named("/tmp/proj/src/a.lua")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    run({ "prompt" })
    assert.are.same(
      { "{file}", "{line}" },
      vim.tbl_map(function(entry)
        return entry.text
      end, offered(pick_spec))
    )

    pick_choices({ named_entry(pick_spec, "{line}") })
    assert.are.equal("src/a.lua :L2", (delivered_render({ cwd = "/tmp/proj" })))
    assert.are.equal("/tmp/proj/src/a.lua :L2", (delivered_render({})))
  end)

  it("offers every configured prompt, user entries included, in a stable order", function()
    Config.setup({ prompts = { review = "Review {file}" } })

    run({ "prompt" })

    -- Byte order: '{' sorts after letters, so the user's name comes first.
    assert.are.same(
      { "review", "{file}", "{line}" },
      vim.tbl_map(function(entry)
        return entry.text
      end, offered(pick_spec))
    )
  end)

  it("delivers the references chosen from a source", function()
    run({ "files" })
    assert.are.equal("Files: ", pick_spec.prompt)
    assert.is_true(pick_spec.many)
    assert.are.equal(References.sources.files.preview, pick_spec.preview)

    pick_choices({ { text = "a.lua", path = "/tmp/proj/a.lua" }, { text = "b.lua", path = "/tmp/proj/b.lua" } })
    assert.are.equal("a.lua\nb.lua", (delivered_render({ cwd = "/tmp/proj" })))
  end)

  it("sends a range verbatim", function()
    local buf = named("/tmp/proj/a.lua", { "one", "two", "three" })
    vim.api.nvim_win_set_buf(0, buf)

    Commands.run({ fargs = { "send" }, line1 = 2, line2 = 3 })
    assert.are.equal("two\nthree", (delivered_render({ cwd = "/tmp/proj" })))
  end)

  it("asks for a note about the range and delivers it", function()
    local buf = named("/tmp/proj/src/a.lua")
    vim.api.nvim_win_set_buf(0, buf)
    answer_prompt("needs a guard")

    Commands.run({ fargs = { "comment" }, line1 = 2, line2 = 3 })

    assert.are.equal("Comment: ", input_opts.prompt)
    assert.are.equal("src/a.lua :L2-3 needs a guard\n", (delivered_render({ cwd = "/tmp/proj" })))
    assert.are.equal("/tmp/proj/src/a.lua :L2-3 needs a guard\n", (delivered_render({})))
  end)

  it("sends nothing when the note is cancelled or left blank", function()
    local buf = named("/tmp/proj/a.lua")
    vim.api.nvim_win_set_buf(0, buf)

    for _, note in ipairs({ "", "   " }) do
      answer_prompt(note)
      run({ "comment" })
      assert.is_nil(delivered_render)
    end
    answer_prompt(nil)
    run({ "comment" })
    assert.is_nil(delivered_render)
  end)

  it("refuses to comment an unnamed buffer, before asking for a note", function()
    local buf = Helpers.buffer({ "a" })
    bufs[#bufs + 1] = buf
    vim.api.nvim_win_set_buf(0, buf)

    local asked = false
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.input = function()
      asked = true
    end
    local notes = Helpers.notifications(function()
      Commands.run({ fargs = { "comment" }, line1 = 1, line2 = 1 })
    end)
    assert.is_truthy(notes[1]:find("named buffer", 1, true))
    assert.is_false(asked)
  end)

  it("reports the detected multiplexer and the target in status", function()
    local notes = Helpers.notifications(function()
      run({ "status" })
    end)
    assert.is_truthy(notes[1]:find("multiplexer: tmux", 1, true))
    assert.is_truthy(notes[1]:find("target: not chosen yet", 1, true))
  end)
end)
