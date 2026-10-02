--- The `:Pigeon` command: one table names every subcommand, the words it takes,
--- and its help, so dispatch, usage and completion all derive from one place.
local Comments = require("pigeon.commands.comments")
local Deliver = require("pigeon.deliver")
local Prompts = require("pigeon.commands.prompts")
local References = require("pigeon.commands.references")
local Transport = require("pigeon.transport")
local Util = require("pigeon.util")

local M = {}

--- The range a command acts on: the range the user typed, or — when a mapping
--- invoked it while Visual mode is still active — the visual selection, whose
--- `'<`/`'>` marks are not written until Visual mode exits.
---@param args table
---@return integer, integer
local function range(args)
  if vim.api.nvim_get_mode().mode:match("[vV\22]") then
    vim.cmd("normal! \27")
    local line1, line2 = vim.fn.line("'<"), vim.fn.line("'>")
    if line1 > line2 then
      line1, line2 = line2, line1
    end
    return line1, line2
  end
  return args.line1, args.line2
end

--- Report which multiplexer was detected and which pane this session sends to.
local function status()
  local transport, reason = Transport.get()
  local multiplexer = transport and Transport.name() or ("none (%s)"):format(reason or "not detected")
  local target = Deliver.target()
  vim.notify(
    table.concat({
      ("multiplexer: %s"):format(multiplexer),
      ("target: %s"):format(target and target:repr() or "not chosen yet"),
    }, "\n"),
    vim.log.levels.INFO
  )
end

--- One `:Pigeon` subcommand. Everything the user sees about it — dispatch, the
--- usage line, and completion — comes from here.
---@class pigeon.Subcommand
---@field name string
---@field help string
---@field run fun(args: table)

---@type pigeon.Subcommand[]
local SUBCOMMANDS = {
  {
    name = "prompt",
    help = "pick a prompt template and send it",
    run = function()
      Prompts.run()
    end,
  },
  {
    name = "files",
    help = "pick files and send their references",
    run = function()
      References.run("files")
    end,
  },
  {
    name = "buffers",
    help = "pick buffers and send their references",
    run = function()
      References.run("buffers")
    end,
  },
  {
    name = "comment",
    help = "send a note about the range (visual selection, or current line)",
    run = function(args)
      local line1, line2 = range(args)
      Comments.run(line1, line2)
    end,
  },
  {
    name = "send",
    help = "send the range verbatim (no template, no references)",
    run = function(args)
      local line1, line2 = range(args)
      local text = table.concat(vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false), "\n")
      Deliver.run(function()
        return text
      end)
    end,
  },
  {
    name = "retarget",
    help = "choose which pane this session sends to",
    run = function()
      Deliver.retarget()
    end,
  },
  {
    name = "status",
    help = "show the target and the detected multiplexer",
    run = status,
  },
}

local function usage()
  local lines = { "Pigeon — send to the other panes of this window", "" }
  for _, sub in ipairs(SUBCOMMANDS) do
    lines[#lines + 1] = ("  :Pigeon %-15s %s"):format(sub.name, sub.help)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param names string[]
---@param arglead string
---@return string[]
local function matching(names, arglead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, arglead)
  end, names)
end

--- The `name` of every entry, whether a subcommand or one of its words.
---@param entries { name: string }[]
---@return string[]
local function names_of(entries)
  return vim.tbl_map(function(entry)
    return entry.name
  end, entries)
end

---@param args table
function M.run(args)
  local fargs = args.fargs
  local name = fargs[1]
  if name == nil then
    usage()
    return
  end

  for _, sub in ipairs(SUBCOMMANDS) do
    if sub.name == name then
      sub.run(args)
      return
    end
  end

  Util.warn(("unknown subcommand '%s'"):format(name))
  usage()
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  -- No word yet, or the first word still being typed: offer the names.
  if cmdline:match("^%s*Pigeon%s*$") or cmdline:match("^%s*Pigeon%s+%S*%s*$") then
    return matching(names_of(SUBCOMMANDS), arglead)
  end
  return {}
end

return M
