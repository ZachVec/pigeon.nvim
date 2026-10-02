--- snacks picker: drive snacks' own picker directly. An entry's `text` is what
--- snacks matches on, renders, and titles the preview with; `confirm` receives
--- the original entry and closes the picker itself.
local M = {}

---@type string
M.requires = "snacks.picker"

--- Preview-pane window options for every preview-capable pick. snacks renders
--- its preview window with the number column on by default; that gutter reads
--- as a code view, wrong for captured file text or a rendered comment, so
--- previews pin it off (relative numbers too).
local NO_PREVIEW_LINENR = { number = false, relativenumber = false }

---@class pigeon.SnacksPreviewPane The snacks preview-object surface pigeon uses.
---@field reset fun(self: pigeon.SnacksPreviewPane)
---@field set_title fun(self: pigeon.SnacksPreviewPane, title: string)
---@field set_lines fun(self: pigeon.SnacksPreviewPane, lines: string[])

---@class pigeon.SnacksPreviewCtx
---@field item pigeon.picker.Entry
---@field preview pigeon.SnacksPreviewPane

---@class pigeon.SnacksPickerTask The slice of snacks' async task surface pigeon drives.
---@field resume fun(self: pigeon.SnacksPickerTask)
---@field suspend fun(self: pigeon.SnacksPickerTask)
---@field on fun(self: pigeon.SnacksPickerTask, event: string, cb: fun())

---@class pigeon.SnacksPicker The slice of the snacks picker surface pigeon drives.
---@field close fun(self: pigeon.SnacksPicker)
---@field refresh fun(self: pigeon.SnacksPicker)
---@field selected fun(self: pigeon.SnacksPicker, opts: { fallback?: boolean }): pigeon.picker.Entry[]

---@class pigeon.SnacksFinderCtx
---@field async pigeon.SnacksPickerTask

--- The pick's item stream, driven through snacks' finder. snacks calls the
--- finder once per run — the opening pick, and again whenever a command
--- reports the list may have changed — and each emitted batch becomes finder
--- items. A stream that ended within the finder call is shown as a static
--- list; a still-running one is drained from inside snacks' own async task,
--- the queue plus suspend/resume shape snacks' own `source/proc.lua` uses, so
--- `cb` is never called from a libuv callback.
---
--- One stream per pick; each `start` is one run of it and resets the fields a
--- run owns. snacks aborts the previous run's task a tick after the next
--- finder call has already started a fresh run, so a run is stamped with its
--- `generation` and a stale abort stops nothing.
---@class pigeon.SnacksStream
---@field source fun(emit: fun(entries: pigeon.picker.Entry[]), done: fun()): (fun()?) the flow's stream, started once per run
---@field generation integer the run that owns the fields below
---@field items pigeon.picker.Entry[] entries the current run has produced
---@field queue pigeon.picker.Entry[] entries its drain has yet to hand to snacks
---@field finished boolean the current run's stream has ended
---@field cancel fun()? stops the current run's stream, when it is still going
---@field task pigeon.SnacksPickerTask? the task draining the current run
local Stream = {}

Stream.__index = Stream

---@param source fun(emit: fun(entries: pigeon.picker.Entry[]), done: fun()): (fun()?)
---@return pigeon.SnacksStream
function Stream.new(source)
  return setmetatable({
    source = source,
    generation = 0,
    items = {},
    queue = {},
    finished = false,
  }, Stream)
end

--- Wake the current run's drain loop when it is parked with nothing queued.
function Stream:resume()
  if self.task then
    self.task:resume()
  end
end

--- Take a batch from the flow: keep it for the pick's commands and queue it
--- for the drain loop.
---@param chunk pigeon.picker.Entry[]
function Stream:emit(chunk)
  vim.list_extend(self.items, chunk)
  vim.list_extend(self.queue, chunk)
  self:resume()
end

--- The flow's stream ended, success or failure.
function Stream:finish()
  self.finished = true
  self:resume()
end

--- Start a fresh run, cancelling the stream the previous run left going.
--- True when this run's stream already ended within the call, so the finder
--- answers with the static list instead of a drain.
---@return boolean
function Stream:start()
  if self.cancel then
    self.cancel()
    self.cancel = nil
  end
  self.generation = self.generation + 1
  self.items, self.queue, self.finished = {}, {}, false
  self.cancel = self.source(function(chunk)
    self:emit(chunk)
  end, function()
    self:finish()
  end)
  return self.finished
end

--- snacks' finder: start this run and answer with its entries when it already
--- ended, or with a function draining it inside snacks' async task when it has
--- not.
---@param ctx pigeon.SnacksFinderCtx
---@return any
function Stream:finder(ctx)
  if self:start() then
    return self.items
  end
  local generation = self.generation
  return function(cb)
    self:drain(ctx.async, cb, generation)
  end
end

--- Hand the run's batches to snacks from inside its own task, parking the loop
--- while the queue is empty. An abort names the run it belongs to: a run the
--- next finder call has already superseded stops nothing.
---@param task pigeon.SnacksPickerTask
---@param cb fun(entry: pigeon.picker.Entry)
---@param generation integer
function Stream:drain(task, cb, generation)
  self.task = task
  task:on("abort", function()
    if generation ~= self.generation then
      return
    end
    if self.cancel then
      self.cancel()
      self.cancel = nil
    end
    self.finished, self.queue = true, {}
  end)
  while not self.finished or #self.queue > 0 do
    if #self.queue == 0 then
      task:suspend()
    else
      local chunk = self.queue
      self.queue = {}
      for _, entry in ipairs(chunk) do
        cb(entry)
      end
    end
  end
  -- A newer run may already own the task; leave its handle alone.
  if self.task == task then
    self.task = nil
  end
end

--- The pick's confirm handler: take the choice, close the picker, and hand the
--- entries to the flow on a later tick — a callback that opens a window (the
--- comment editor's float) must run once the picker's own windows are gone.
---@param spec pigeon.PickSpec
---@param on_choices fun(entries: pigeon.picker.Entry[])
---@return fun(picker: pigeon.SnacksPicker, item: pigeon.picker.Entry?)
local function confirm_handler(spec, on_choices)
  return function(picker, item)
    local chosen = spec.many and picker:selected({ fallback = true }) or (item and { item } or {})
    if #chosen == 0 then
      picker:close()
      return
    end
    vim.schedule(function()
      picker:close()
      vim.schedule(function()
        on_choices(chosen)
      end)
    end)
  end
end

--- The pick's preview function. nil from the flow's own preview means "nothing
--- to preview", so the pane stays, empty.
---@param preview fun(entry: pigeon.picker.Entry): string[]?
---@return fun(ctx: pigeon.SnacksPreviewCtx)
local function preview_pane(preview)
  return function(ctx)
    ctx.preview:reset()
    local item = ctx.item
    if not item then
      return
    end
    local lines = preview(item)
    if not lines then
      return
    end
    ctx.preview:set_title(item.text)
    ctx.preview:set_lines(lines)
  end
end

--- Render a streaming pick through snacks' own picker.
---@param spec pigeon.PickSpec
---@param on_choices fun(entries: pigeon.picker.Entry[])
function M.pick(spec, on_choices)
  local stream = Stream.new(spec.items)
  local pick_opts = {
    ---@param item pigeon.picker.Entry
    format = function(item)
      return { { item.text, "" } }
    end,
    confirm = confirm_handler(spec, on_choices),
    finder = function(_, ctx)
      return stream:finder(ctx)
    end,
    win = {},
  }

  if spec.preview then
    pick_opts.preview = preview_pane(spec.preview)
    pick_opts.win.preview = { wo = NO_PREVIEW_LINENR }
  else
    -- No pane at all: snacks' layout carries a preview window whether or not a
    -- `preview` function is given, so hiding it takes the layout flag.
    pick_opts.layout = { preview = false }
  end

  require("snacks.picker").pick(pick_opts)
end

return M
