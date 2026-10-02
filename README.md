# pigeon.nvim

Send text from Neovim into the **other panes of the multiplexer window this
Neovim is running in**: a prompt template, a reference to a file or buffer, a
comment on a line or selection, or the text you select.

## Requirements

- Neovim ≥ 0.11
- tmux 3.0+ (the only multiplexer adapter today)

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ZachVec/pigeon.nvim",
  cmd = "Pigeon",
  opts = {},
}
```

The plugin loads on the first `:Pigeon`. See `:h pigeon.nvim` for the full
reference.

## Usage

```vim
:Pigeon prompt            " pick a prompt template and send it
:Pigeon files             " pick files and send their references
:Pigeon buffers           " pick buffers and send their references
:Pigeon comment           " send a note about the selection or current line
:Pigeon send              " send the selection or line verbatim
:Pigeon retarget          " choose which pane this session sends to
:Pigeon status            " the target, and the detected multiplexer
```

No keymaps are installed.

The target is another pane of this Neovim's window. With one sibling there is
nothing to choose — it becomes the session's target. With several, a pick
decides, and your choice becomes the target for later sends; mark several to
broadcast once without remembering any of them. `:Pigeon retarget` chooses a
different one.

Sends are pasted, not typed: pigeon never presses Enter, so what you send waits
in the other pane for you to review. Whether an embedded newline submits is the
receiving program's business — an agent CLI inserts it, a bare shell runs the
line.

## Configuration

```lua
require("pigeon").setup({
  multiplexer = "auto",     -- auto | tmux | none
  picker = "native",        -- native | fzf-lua | snacks

  format = function(file, loc) -- how a location reads; see References
    return file .. (loc and " " .. loc or "")
  end,

  prompts = {               -- add or override prompt templates
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
  },

  comments = {
    item = "{lines} {note}\n", -- what a comment sends
  },

  references = {
    join = "\n",             -- separator between file/buffer references
  },
})
```

An unknown or unavailable `multiplexer`/`picker` is an error at setup. `auto`
detects the multiplexer this Neovim is running inside; `none` disables sending.

### References

A reference is a path relative to the **target pane's** working directory
(absolute when the path lies outside it, and when the adapter cannot report a
working directory at all), plus its `:L` position when there is one:

```
src/a.lua
src/a.lua :L42
src/a.lua :L42-45
```

Which format a reference takes depends on the program running in the target
pane:

| The target pane runs | A reference reads |
|----------------------|-------------------|
| claude | `@src/a.lua`, `@src/a.lua#L42-50` |
| codex | `src/a.lua`, `src/a.lua :L42-50` |
| anything else | `src/a.lua`, `src/a.lua :L42-50` |

A program launched through an interpreter still counts: detection reads the
command lines of the pane's processes, so a `node …/codex` pane is recognized
as codex.

`format` replaces the fallback — the format a pane running anything else reads;
claude and codex keep their own. Its default is the `src/a.lua` /
`src/a.lua :L42` spelling above:

```lua
require("pigeon").setup({
  format = function(file, loc)
    return "@" .. file .. (loc and (" " .. loc) or "")
  end,
})
```

A format that returns `nil` or `""` declines that reference, and pigeon sends
nothing rather than half a message.

### Prompts

`prompts` maps names to templates. The built-in names are `{file}` and
`{line}`; user entries merge with them, so a name you set overrides the
built-in while names you leave unset are kept.

| Placeholder | Expands to |
|-------------|------------|
| `{file}` | `path/to/file.lua` |
| `{line}` | `path/to/file.lua :L42` |

```lua
require("pigeon").setup({
  prompts = { review = "Review {file} for bugs." },
})
```

### Files and buffers

`files` lists files under Neovim's global cwd (`:cd`; not `:lcd`/`:tcd`) — the
tree you are browsing — using `fd`, then `ripgrep`, then `find`; all three skip
`.git`. `buffers` lists listed buffers whose file exists on disk, most recently
used first, marking a modified buffer `[+]` because the panes read the on-disk
version. Chosen paths are spelled as references (above), joined with
`references.join` — nothing is added around them.

### Comments

`comment` asks for a note about the selection or the current line and sends it
there and then. Enter sends, `Esc` cancels, and a blank note sends nothing.
Nothing is kept between sends — a second note is a second send, so several
notes stack up in the receiving pane's own input, waiting for the one Enter
that submits them together.

`comments.item` decides what a comment sends and supports `{note}`, `{lines}`,
`{file}`, `{start}`, and `{end}`; `{lines}` and `{file}` are spelled in the
target pane's format. The default puts the reference first, then your note:

```lua
require("pigeon").setup({
  comments = { item = "{lines} {note}\n" },
})
```

The default ends with a newline, so a second comment — and anything you type
next — starts on its own line.

## Pickers

`picker` selects the UI used for prompt names, files, buffers, and the target
pane:

| Picker | Provided by | Previews |
|--------|-------------|----------|
| `"native"` | `vim.ui.select` | — |
| `"fzf-lua"` | fzf-lua | yes |
| `"snacks"` | snacks.nvim | yes |

An engine does not have to be loaded before `setup` — a plugin manager may
install it lazily — but an engine that is not installed at all is an error at
setup. The engine-backed pickers stream, so a listing that is still being
produced can be searched and cancelled; `native` waits for it to finish.

`native` marks nothing, so a pick that accepts several entries sends one at a
time.

## License

Apache-2.0.
