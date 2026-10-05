---@module 'luassert'

local Helpers = require("helpers")

describe("pigeon.commands.references", function()
  local Config
  local Formats
  local References
  local tmp
  local original_path
  local bufs = {}
  local dirs = {}

  --- Drain a candidate source and return what it emitted.
  ---@param stream fun(cwd: string, emit: fun(entries: any[]), done: fun()): (fun()?)
  ---@param cwd string
  ---@return any[]
  local function collect(stream, cwd)
    local items, finished = {}, false
    stream(cwd, function(chunk)
      vim.list_extend(items, chunk)
    end, function()
      finished = true
    end)
    vim.wait(5000, function()
      return finished
    end, 10)
    assert(finished, "the source did not finish")
    return items
  end

  ---@param items any[]
  ---@return string[]
  local function texts(items)
    return vim.tbl_map(function(item)
      return item.text
    end, items)
  end

  --- Let a notification raised from a process-exit callback land: those are
  --- deferred to the main loop, and `collect` can return before they run.
  local function settle()
    vim.wait(100, function()
      return false
    end, 10)
  end

  --- Write a file under the fixture root and answer its absolute path.
  ---@param relpath string
  ---@param lines? string[]
  ---@return string
  local function write(relpath, lines)
    local path = vim.fs.joinpath(tmp, relpath)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines or { "x" }, path)
    return path
  end

  --- Run `fn` with PATH holding only a directory of executable fake listers,
  --- one shell script per name, so the resolution is fully determined.
  ---@param scripts table<string, string>
  ---@param fn fun()
  local function with_listers(scripts, fn)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    dirs[#dirs + 1] = dir
    for name, body in pairs(scripts) do
      local path = vim.fs.joinpath(dir, name)
      vim.fn.writefile({ "#!/bin/sh", body }, path)
      vim.fn.setfperm(path, "rwxr-xr-x")
    end
    vim.env.PATH = dir
    -- The lister is resolved from PATH, so the fake PATH has to be in place
    -- before the resolution runs.
    References.setup()
    local ok, err = pcall(fn)
    vim.env.PATH = original_path
    if not ok then
      error(err)
    end
  end

  --- A listed, on-disk buffer.
  ---@param path string
  ---@param lines string[]
  ---@return integer
  local function listed_buffer(path, lines)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buflisted = true
    vim.bo[buf].modified = false
    bufs[#bufs + 1] = buf
    return buf
  end

  setup(function()
    Helpers.reload_pigeon()
    Config = require("pigeon.config")
    Formats = require("pigeon.formats")
    References = require("pigeon.commands.references")
  end)

  teardown(function()
    Helpers.reload_pigeon()
  end)

  before_each(function()
    Config.setup()
    Formats.setup()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    original_path = vim.env.PATH
  end)

  after_each(function()
    vim.env.PATH = original_path
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
    vim.fn.delete(tmp, "rf")
    for _, dir in ipairs(dirs) do
      vim.fn.delete(dir, "rf")
    end
    dirs = {}
  end)

  it("streams file candidates relative to the listing root", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })

    with_listers({ fd = "printf 'a.lua\\nsub/b.lua\\n'" }, function()
      local listed = texts(collect(References.sources.files.stream, tmp))
      table.sort(listed)
      assert.are.same({ "a.lua", "sub/b.lua" }, listed)
    end)
  end)

  it("asks the file lister to follow symlinks", function()
    local args_file = vim.fs.joinpath(tmp, "fd-args")
    with_listers({ fd = ("printf '%%s\\n' \"$@\" > %s"):format(args_file) }, function()
      collect(References.sources.files.stream, tmp)
    end)
    assert.are.same({ "--type", "f", "--follow", "--color", "never", "-E", ".git" }, vim.fn.readfile(args_file))
  end)

  it("treats rg's exit 1 as an empty listing rather than falling through", function()
    local items, notes
    local ran = vim.fs.joinpath(tmp, "find-ran")
    with_listers({ rg = "exit 1", find = ("touch %s"):format(ran) }, function()
      notes = Helpers.notifications(function()
        items = collect(References.sources.files.stream, tmp)
        settle()
      end)
    end)
    assert.are.same({}, items)
    assert.are.equal(0, vim.fn.filereadable(ran))
    assert.are.same({}, notes)
  end)

  it("keeps a listing a followed symlink made the lister exit non-zero on", function()
    local items, notes
    with_listers({ rg = "printf 'a.lua\\n'; exit 2" }, function()
      notes = Helpers.notifications(function()
        items = collect(References.sources.files.stream, tmp)
        settle()
      end)
    end)
    assert.are.same({ "a.lua" }, texts(items))
    assert.are.same({}, notes)
  end)

  it("reports a failing lister instead of falling through to the next one", function()
    local items, notes
    local ran = vim.fs.joinpath(tmp, "rg-ran")
    with_listers({ fd = "exit 2", rg = ("touch %s"):format(ran) }, function()
      notes = Helpers.notifications(function()
        items = collect(References.sources.files.stream, tmp)
        settle()
      end)
    end)
    assert.are.same({}, items)
    assert.are.equal(0, vim.fn.filereadable(ran))
    assert.is_truthy(notes[1]:find("file listing failed (fd)", 1, true))
  end)

  it("does not report a cancelled listing as a failure", function()
    local sleeper = vim.fn.exepath("sleep")
    local notes
    with_listers({ fd = ("exec %s 5"):format(sleeper) }, function()
      notes = Helpers.notifications(function()
        local cancel = References.sources.files.stream(tmp, function() end, function() end)
        cancel()
        vim.wait(300, function()
          return false
        end, 10)
      end)
    end)
    assert.are.same({}, notes)
  end)

  it("resolves the lister once, not per run", function()
    local items
    with_listers({ fd = "printf 'from-fd\\n'" }, function()
      assert.are.same({ "from-fd" }, texts(collect(References.sources.files.stream, tmp)))

      -- A second PATH that has only rg: the run still uses the resolved fd
      -- rather than looking for a lister again.
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      dirs[#dirs + 1] = dir
      local script = vim.fs.joinpath(dir, "rg")
      vim.fn.writefile({ "#!/bin/sh", "printf 'from-rg\\n'" }, script)
      vim.fn.setfperm(script, "rwxr-xr-x")
      vim.env.PATH = dir

      local notes = Helpers.notifications(function()
        items = collect(References.sources.files.stream, tmp)
        settle()
      end)
      assert.are.same({}, items)
      assert.is_truthy(notes[1]:find("file listing failed (fd)", 1, true))
    end)
  end)

  it("reports when no lister is installed", function()
    local notes
    with_listers({}, function()
      notes = Helpers.notifications(function()
        collect(References.sources.files.stream, tmp)
      end)
    end)
    assert.is_truthy(notes[1]:find("no file lister", 1, true))
  end)

  it("previews a file with its first lines", function()
    local path = write("a.lua", { "one", "two" })
    with_listers({ fd = "printf 'a.lua\\n'" }, function()
      local items = collect(References.sources.files.stream, tmp)
      assert.are.equal(1, #items)
      assert.are.equal(path, items[1].path)
      assert.are.same({ "one", "two" }, References.sources.files.preview(items[1]))
    end)
  end)

  it("lists listed file buffers and marks a modified one", function()
    local a = write("a.lua", { "a" })
    write("b.lua", { "b" })
    local scratch = Helpers.buffer({ "x" }) -- unnamed: not a candidate
    bufs[#bufs + 1] = scratch
    listed_buffer(a, { "a" })
    local b = listed_buffer(vim.fs.joinpath(tmp, "b.lua"), { "b" })
    vim.bo[b].modified = true

    local listed = texts(collect(References.sources.buffers.stream, tmp))
    table.sort(listed)
    assert.are.same({ "a.lua", "b.lua [+]" }, listed)
  end)

  it("previews a buffer from its live lines", function()
    local path = write("a.lua", { "on-disk" })
    local buf = listed_buffer(path, { "live-1", "live-2" })
    local entries = collect(References.sources.buffers.stream, tmp)
    local entry
    for _, candidate in ipairs(entries) do
      if candidate.buf == buf then
        entry = candidate
      end
    end
    assert.is_not_nil(entry)
    assert.are.same({ "live-1", "live-2" }, References.sources.buffers.preview(entry))
  end)

  it("joins the chosen references for the target's own cwd", function()
    local chosen = { { path = "/tmp/proj/a.lua" }, { path = "/tmp/proj/sub/b.lua" } }
    local render = References.render(chosen)
    assert.are.equal("a.lua\nsub/b.lua", (render({ cwd = "/tmp/proj" })))
    assert.are.equal("/tmp/proj/a.lua\n/tmp/proj/sub/b.lua", (render({})))
  end)

  it("honours the configured separator", function()
    Config.setup({ references = { join = " " } })
    local render = References.render({ { path = "/tmp/p/a.lua" }, { path = "/tmp/p/b.lua" } })
    assert.are.equal("a.lua b.lua", (render({ cwd = "/tmp/p" })))
  end)

  it("declines the whole message when a reference is declined", function()
    Config.setup({
      references = { join = " " },
      format = function(file)
        if file == "b.lua" then
          return nil
        end
        return file
      end,
    })
    Formats.setup()
    local chosen = { { path = "/tmp/p/a.lua" }, { path = "/tmp/p/b.lua" } }
    local rendered, why = References.render(chosen)({ cwd = "/tmp/p" })
    assert.is_nil(rendered)
    assert.is_truthy(why:find("b.lua", 1, true))
  end)

  it("declines an empty selection", function()
    local rendered, why = References.render({})({ cwd = "/tmp/p" })
    assert.is_nil(rendered)
    assert.are.equal("nothing chosen", why)
  end)
end)
