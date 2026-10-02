--- Shared helpers for the Pigeon plugin.
local M = {}

--- Run a command synchronously via vim.system.
---@param cmd string[]
---@param opts? { cwd?: string }
---@return integer code
---@return string stdout
---@return string stderr
function M.run(cmd, opts)
  local result = vim.system(cmd, { text = true, cwd = opts and opts.cwd or nil }):wait()
  return result.code or 0, result.stdout or "", result.stderr or ""
end

--- Run a command and hand its stdout lines to `on_lines` as they arrive (one
--- call per chunk, complete lines only), then `on_done(code)` when it exits; a
--- trailing partial line is flushed before `on_done`. Returns a cancel function
--- that stops the process — SIGTERM, then SIGKILL if it is still running after
--- a grace period — because a cancelled listing has no other way to stop.
--- `on_done` always reports the run's outcome, cancellation included. A command
--- that cannot be spawned answers the failure code -1 instead of raising.
---@param cmd string[]
---@param opts? { cwd?: string }
---@param on_lines fun(lines: string[])
---@param on_done fun(code: integer)
---@return fun() cancel
function M.run_lines(cmd, opts, on_lines, on_done)
  local carry = ""
  local running = true

  ---@param code integer
  local function finish(code)
    running = false
    if carry ~= "" then
      on_lines({ carry })
      carry = ""
    end
    on_done(code)
  end

  --- Split one chunk into complete lines, carrying a partial tail over.
  ---@param chunk string
  local function feed(chunk)
    local data = carry .. chunk
    local lines = {}
    local from = 1
    while true do
      local nl = data:find("\n", from, true)
      if not nl then
        break
      end
      lines[#lines + 1] = data:sub(from, nl - 1)
      from = nl + 1
    end
    carry = data:sub(from)
    if #lines > 0 then
      on_lines(lines)
    end
  end

  local ok, process = pcall(vim.system, cmd, {
    text = true,
    cwd = opts and opts.cwd or nil,
    stdout = function(_, chunk)
      if chunk then
        feed(chunk)
      end
    end,
  }, function(out)
    -- A signalled process reports code 0: report it as a failure instead
    -- (128 + signal is the shell's convention), or a truncated listing would
    -- look like a finished one.
    finish(out.signal ~= 0 and (128 + out.signal) or (out.code or 0))
  end)
  if not ok then
    -- The child never started: a missing cwd, a vanished binary.
    finish(-1)
    return function() end
  end

  return function()
    if not running then
      return
    end
    process:kill("sigterm")
    vim.defer_fn(function()
      if running then
        process:kill("sigkill")
      end
    end, 200)
  end
end

--- Fold $HOME into ~ for display.
---@param path string
---@return string
function M.tilde(path)
  local home = vim.fn.getenv("HOME")
  if home == nil or home == vim.NIL or home == "" then
    return path
  end
  if path == home then
    return "~"
  end
  if vim.startswith(path, home .. "/") then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

--- Render `{placeholder}` tokens in `template` against a caller-provided
--- whitelist and resolver. Unknown placeholders are left literal; a resolver
--- returning nil fails the render and returns nil with the **first** failing
--- name, so a template with several bad placeholders always reports the same
--- (leftmost) one.
---@param template string
---@param allowed table<string, boolean>
---@param resolve fun(name: string): string?
---@return string?
---@return string? failed placeholder name, when nil is returned
function M.interpolate(template, allowed, resolve)
  local failed
  local out = template:gsub("{([%w_]+)}", function(name)
    if not allowed[name] then
      return "{" .. name .. "}"
    end
    local value = resolve(name)
    if value == nil then
      failed = failed or name
      return ""
    end
    return value
  end)
  if failed then
    return nil, failed
  end
  return out
end

--- Path relative to `cwd`, or the path unchanged when it cannot be spelled
--- relatively — outside `cwd`, equal to it, or with no base at all — in which
--- case it is already absolute.
---@param cwd string? base directory
---@param path string
---@return string
function M.relpath(cwd, path)
  local ok, rel = pcall(vim.fs.relpath, cwd, path)
  if ok and rel and rel ~= "" and rel ~= "." then
    return rel
  end
  return path
end

--- Neovim's global working directory (follows `:cd`, ignores `:lcd`/`:tcd`),
--- which is the tree a file listing walks.
---@return string
function M.cwd()
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(-1, -1), ":p"))
end

--- Notify on Neovim's main loop. `vim.notify`'s default handler calls
--- `nvim_echo`, which raises E5560 in a fast event context — a libuv callback,
--- such as a `vim.system` exit callback — so a notification raised from one is
--- deferred instead of raising.
---@param msg string
---@param level? integer
function M.notify(msg, level)
  local text = "pigeon: " .. msg
  local log_level = level or vim.log.levels.ERROR
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.notify(text, log_level)
    end)
    return
  end
  vim.notify(text, log_level)
end

---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

return M
