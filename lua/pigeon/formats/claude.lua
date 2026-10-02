--- Claude Code reads an `@` mention, with a range as `#L<start>-<end>`
--- (`@src/a.lua#L42-50`). A path holding anything outside the characters a
--- mention can carry unquoted is wrapped in quotes, as the CLI expects.
---@type pigeon.formats.Profile
return {
  match = function(cmd)
    return cmd:find("%f[%w_]claude%f[^%w_]") ~= nil
  end,
  format = function(file, loc)
    local mention = file:find("[^%w/_%.%-]") and ('"' .. file .. '"') or file
    local suffix = loc and loc:gsub("^:L", "#L") or ""
    return "@" .. mention .. suffix
  end,
}
