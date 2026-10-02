--- Pigeon: send text from Neovim to the other panes of the window this Neovim
--- sits in.
---
--- This module is the composition root. It applies configuration, resolves the
--- configured multiplexer adapter and picker, and installs the `:Pigeon`
--- command.
local Commands = require("pigeon.commands")
local Comments = require("pigeon.commands.comments")
local Config = require("pigeon.config")
local Picker = require("pigeon.picker")
local Prompts = require("pigeon.commands.prompts")
local Reference = require("pigeon.reference")
local References = require("pigeon.commands.references")
local Transport = require("pigeon.transport")

local M = {}

---@param opts? pigeon.ConfigOverrides
function M.setup(opts)
  Config.setup(opts)

  -- Resolve the pluggable implementations before installing any runtime side
  -- effect, so a bad configuration leaves no command behind while
  -- `Config.options` keeps the attempted values for health.
  local ok, err = pcall(function()
    Transport.setup({ multiplexer = Config.options.multiplexer })
    Picker.setup()

    Reference.setup()
    Prompts.setup()
    Comments.setup()
    References.setup()

    vim.api.nvim_create_user_command("Pigeon", function(args)
      Commands.run(args)
    end, {
      nargs = "*",
      range = true, -- `:Pigeon send` and `:Pigeon comment` use the range
      complete = function(arglead, cmdline)
        return Commands.complete(arglead, cmdline)
      end,
      desc = "Send to the other panes of this window",
    })
  end)
  if not ok then
    Transport.reset()
    Picker.reset()
    error(err, 0)
  end
end

return M
