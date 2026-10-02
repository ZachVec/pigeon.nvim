--- Native picker: the live global `vim.ui.select`, including whatever
--- override the user may have installed (dressing.nvim, snacks' ui_select, …).
---
--- `vim.ui.select` takes a fixed list and marks nothing, so the item stream is
--- drained first and a `many` pick degrades to one choice. It has no key
--- surface, so `commands` are ignored.
local M = {}

---@param spec pigeon.PickSpec
---@param on_choices fun(entries: pigeon.picker.Entry[])
function M.pick(spec, on_choices)
  local items, finished = {}, false
  spec.items(function(chunk)
    vim.list_extend(items, chunk)
  end, function()
    finished = true
  end)
  while not finished do
    vim.wait(1000, function()
      return finished
    end, 10)
  end

  vim.ui.select(items, {
    prompt = spec.prompt,
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if entry then
      on_choices({ entry })
    end
  end)
end

return M
