--- fzf-lua picker: drive fzf-lua's own `fzf_exec`.
---
--- fzf hands back the display string rather than the entry, so every emitted
--- line carries a numeric prefix that round-trips the entry index — the scheme
--- fzf-lua's own `ui_select` shim uses. The pick's item stream is pushed into
--- fzf's stdin as it arrives: a function contents hands every line of a batch
--- to `on_write` (one pipe write per batch) and takes nil as end of input,
--- over a pipe that stays open until then (see docs/gotchas.md).
local M = {}

---@type string
M.requires = "fzf-lua"

local function fzf()
  return require("fzf-lua")
end

--- "1. text" lines; the prefix encodes the 1-based index so a returned display
--- string maps back to its entry. Emitted one per callback, matching
--- fzf-lua's function-contents contract.
local PREFIX = "%d. %s"

--- The numeric prefix exists only to round-trip a line back to its entry; hide
--- it from the list with `--with-nth`, the way fzf-lua's own providers do. fzf
--- still hands the original line to actions, so the round-trip holds. No
--- `--nth`: fzf evaluates it against the *transformed* line, so `--nth=2..`
--- would drop the line's own first field and leave a single-token path with an
--- empty search scope.
local PREFIX_HIDDEN = { ["--with-nth"] = "2.." }

--- Recover the 1-based item index from one returned entry string.
---@param entry string
---@return integer?
local function index_of(entry)
  return tonumber(entry:match("^%s*(%d+)%."))
end

--- Render a pick through `fzf_exec`. The flow's stream is started once, by the
--- contents function fzf calls for its input.
---@param spec pigeon.PickSpec
---@param on_choices fun(entries: pigeon.picker.Entry[])
function M.pick(spec, on_choices)
  local items = {}
  local cancel ---@type fun()?

  --- Map fzf's returned display strings back to their entries, in returned
  --- order.
  ---@param selected string[]?
  ---@return pigeon.picker.Entry[]
  local function chosen_of(selected)
    local out = {}
    for _, line in ipairs(selected or {}) do
      local entry = items[index_of(line) or 0]
      if entry then
        out[#out + 1] = entry
      end
    end
    return out
  end

  --- Write each batch's prefixed lines in one pipe write, and nil as end of
  --- input.
  ---@param on_write_nl fun(line: string?)
  ---@param on_write fun(lines: string[])
  local function content(on_write_nl, on_write)
    cancel = spec.items(function(chunk)
      local lines = {}
      for _, entry in ipairs(chunk) do
        items[#items + 1] = entry
        lines[#lines + 1] = PREFIX:format(#items, entry.text)
      end
      if #lines > 0 then
        on_write(lines)
      end
    end, function()
      on_write_nl(nil)
    end)
  end

  ---@type table<string, any>
  local actions = {
    ["default"] = function(selected)
      local chosen = chosen_of(selected)
      if #chosen > 0 then
        vim.schedule(function()
          on_choices(chosen)
        end)
      end
    end,
  }
  local fzf_opts = vim.tbl_extend("force", {}, PREFIX_HIDDEN)
  if spec.many then
    fzf_opts["--multi"] = true
  end

  -- fzf runs in its own terminal window, and every window option — `on_close`
  -- included — belongs under `winopts`; fzf-lua silently ignores a top-level
  -- one (see docs/gotchas.md).
  local pick_opts = {
    prompt = spec.prompt,
    fzf_opts = fzf_opts,
    actions = actions,
    winopts = {
      on_close = function()
        if cancel then
          cancel()
          cancel = nil
        end
      end,
    },
  }
  if spec.preview then
    ---@type fun(entry: pigeon.picker.Entry): string[]?
    local preview = spec.preview
    pick_opts.preview = function(selected)
      local entry = chosen_of(selected)[1]
      if not entry then
        return ""
      end
      local lines = preview(entry)
      if not lines then
        return ""
      end
      return table.concat(lines, "\n")
    end
  end

  fzf().fzf_exec(content, pick_opts)
end

return M
