--- The files and buffers command: pick path candidates from one source, spell
--- them into references, and deliver them to the target.
---
--- Two sources of path candidates — an external file listing and the buffer
--- list — behind one pick. What they share is the half that turns a chosen set
--- into a message (`M.render`), which is why they live in one module.
local Config = require("pigeon.config")
local Deliver = require("pigeon.deliver")
local Picker = require("pigeon.picker")
local Reference = require("pigeon.reference")
local Util = require("pigeon.util")

local M = {}

--- External file listers, best first. All three skip `.git`, and each one's
--- order is the tool's — the listing is not sorted. `find` is the last resort
--- and the crudest: unlike fd and rg it reads no ignore files, so a find-only
--- machine lists what find sees.
local LISTERS = {
  { name = "fd", argv = { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git" } },
  { name = "rg", argv = { "rg", "--files", "--no-messages", "--color", "never", "-g", "!.git" } },
  { name = "find", argv = { "find", ".", "-type", "f", "-not", "-path", "*/.git/*" } },
}

--- Lines a file preview reads.
local PREVIEW_LINES = 200

--- The lister `M.setup` resolved, or nil when none is installed.
---@type { name: string, argv: string[] }?
local lister

--- Resolve the external file lister from PATH: the first of fd, rg, find that
--- is installed. The resolved program is what every later listing runs — a
--- machine's tools do not come and go under a session — so a lister that fails
--- reports its own failure instead of falling through to the next one, and
--- resolving another takes another `setup`.
function M.setup()
  lister = nil
  for _, candidate in ipairs(LISTERS) do
    if vim.fn.executable(candidate.name) == 1 then
      lister = candidate
      return
    end
  end
end

--- A path candidate: the text a pick shows, and the path a reference is spelled
--- from.
---@class pigeon.commands.references.PathEntry : pigeon.picker.Entry
---@field path string absolute path

--- A buffer candidate, which can also preview its live contents.
---@class pigeon.commands.references.BufferEntry : pigeon.commands.references.PathEntry
---@field buf integer

--- One candidate source.
---@class pigeon.commands.references.Source
---@field prompt string
---@field preview fun(entry: pigeon.commands.references.PathEntry): string[]?
---@field stream fun(cwd: string, emit: fun(entries: pigeon.picker.Entry[]), done: fun()): (fun()?)

--- The first PREVIEW_LINES lines of a file, or nil when it cannot be read.
---@param entry pigeon.commands.references.PathEntry
---@return string[]?
local function file_preview(entry)
  local ok, lines = pcall(vim.fn.readfile, entry.path, "", PREVIEW_LINES)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return lines
end

--- A buffer's live lines, falling back to its file when the buffer is gone.
---@param entry pigeon.commands.references.BufferEntry
---@return string[]?
local function buffer_preview(entry)
  if not vim.api.nvim_buf_is_valid(entry.buf) then
    return file_preview(entry)
  end
  local count = vim.api.nvim_buf_line_count(entry.buf)
  return vim.api.nvim_buf_get_lines(entry.buf, 0, math.min(count, PREVIEW_LINES), false)
end

--- Stream the file candidates under `cwd` — the listing root and display base,
--- the tree the user is browsing. The resolved lister runs live, one batch per
--- chunk of its output; a run that fails reports it and ends, keeping whatever
--- it already produced.
---@param cwd string
---@param emit fun(entries: pigeon.picker.Entry[])
---@param done fun()
---@return fun() cancel
local function stream_files(cwd, emit, done)
  if not lister then
    Util.warn("no file lister (fd, rg, or find)")
    done()
    return function() end
  end
  local name = lister.name
  return Util.run_lines(lister.argv, { cwd = cwd }, function(lines)
    local entries = {}
    for _, line in ipairs(lines) do
      local path = vim.fs.normalize(vim.fs.joinpath(cwd, line))
      entries[#entries + 1] = { text = Util.relpath(cwd, path), path = path }
    end
    emit(entries)
  end, function(code)
    -- `rg --files` exits 1 when it found no files — a project whose files are
    -- all ignored — which is an empty listing, not a failure.
    local empty = code == 0 or (name == "rg" and code == 1)
    if not empty then
      Util.warn(("file listing failed (%s)"):format(name))
    end
    done()
  end)
end

--- Emit the in-memory buffer candidates in one batch: listed, normal-buftype,
--- named, readable-on-disk buffers, most recently used first (path order breaks
--- ties), each displayed relative to `cwd`.
---@param cwd string
---@param emit fun(entries: pigeon.picker.Entry[])
---@param done fun()
local function stream_buffers(cwd, emit, done)
  local rows = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = info.bufnr
    local name = info.name
    if name ~= "" and vim.bo[buf].buftype == "" and vim.fn.filereadable(name) == 1 then
      local path = vim.fs.normalize(name)
      -- A modified buffer's on-disk content is stale; the marker keeps that
      -- visible without leaking into the reference text.
      local text = Util.relpath(cwd, path)
      if vim.bo[buf].modified then
        text = text .. " [+]"
      end
      rows[#rows + 1] = {
        lastused = info.lastused or 0,
        item = { text = text, buf = buf, path = path },
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.lastused ~= b.lastused then
      return a.lastused > b.lastused
    end
    return a.item.path < b.item.path
  end)
  local items = {}
  for _, row in ipairs(rows) do
    items[#items + 1] = row.item
  end
  emit(items)
  done()
end

--- The two candidate sources, by the name the command surface uses.
---@type table<string, pigeon.commands.references.Source>
M.sources = {
  files = { prompt = "Files: ", preview = file_preview, stream = stream_files },
  buffers = { prompt = "Buffers: ", preview = buffer_preview, stream = stream_buffers },
}

--- The message for a chosen set of paths: every reference spelled through the
--- configured dialect for the target's own cwd, joined by `references.join`,
--- with a trailing space so continued typing stays off the last reference.
--- A reference the format hook declines drops the whole message, and so does an
--- empty selection.
---@param chosen pigeon.commands.references.PathEntry[]
---@return pigeon.Render
function M.render(chosen)
  local paths = {}
  for _, entry in ipairs(chosen) do
    paths[#paths + 1] = entry.path
  end
  return function(cwd)
    if #paths == 0 then
      return nil, "nothing chosen"
    end
    local refs = {}
    for _, path in ipairs(paths) do
      local ref = Reference.reference(cwd, path)
      if ref == nil then
        return nil, ("%s has no reference"):format(Util.relpath(cwd, path))
      end
      refs[#refs + 1] = ref
    end
    return table.concat(refs, Config.options.references.join) .. " "
  end
end

--- Pick from `name` ("files" or "buffers") and deliver the chosen references.
---@param name string
function M.run(name)
  local source = M.sources[name]
  if not source then
    error(("pigeon: unknown reference source '%s'"):format(tostring(name)), 0)
  end

  -- Candidates come from the tree the user is browsing; the chosen references
  -- are still spelled against each target's own cwd, so the two bases are
  -- deliberately split.
  local cwd = Util.cwd()
  Picker.pick({
    prompt = source.prompt,
    many = true,
    preview = source.preview,
    items = function(emit, done)
      return source.stream(cwd, emit, done)
    end,
  }, function(chosen)
    if #chosen == 0 then
      return
    end
    ---@cast chosen pigeon.commands.references.PathEntry[]
    Deliver.run(M.render(chosen))
  end)
end

return M
