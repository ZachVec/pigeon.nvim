--- Codex reads a plain path, with a range as `:L<start>-<end>`. That is the
--- plugin's default format, pinned here so a configured `format` cannot reach
--- a codex pane.
---@type pigeon.formats.Profile
return {
  match = function(cmd)
    return cmd:find("%f[%w_]codex%f[^%w_]") ~= nil
  end,
  format = function(file, loc)
    return file .. (loc and " " .. loc or "")
  end,
}
