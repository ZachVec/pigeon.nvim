# AGENTS.md

Pigeon is a Neovim plugin that sends text into the other panes of the
multiplexer window Neovim is running in. Read
[docs/design.md](docs/design.md) for the seams, the module map, the dependency
direction, and the decisions behind them, and
[docs/glossary.md](docs/glossary.md) for the words to use, before naming or
changing anything.

## Repository layout

```
lua/pigeon/
  init.lua            composition root: read config, set the modules up, install :Pigeon
  config.lua          options: the defaults + the shape checks (data only)
  util.lua            shared helpers
  health.lua          :checkhealth pigeon
  transport/          the multiplexer seam: init.lua (Peer + Transport) + tmux.lua
  picker/             the selection-UI seam: init.lua + native, fzf_lua, snacks
  deliver.lua         target resolution (remembered / single / pick) + fan-out
  reference.lua       the one reference spelling every command spells through
  formats/            the format registry: one Profile per program + resolution
  commands/           :Pigeon dispatch (init.lua) + one file per command
                      (prompts, references, comments): text and flow together
docs/                 design.md (structure and decisions) + glossary.md + gotchas.md
doc/                  vim help docs (:h pigeon.nvim)
tests/                mini.test specs + bootstrap
Makefile              check entrypoint
stylua.toml           Lua formatting
.github/              CI: the suite on Neovim v0.11.0 (the floor) and stable
LICENSE               MIT
```

## Commands

```sh
make check     # style + lint + test
make style     # stylua --check
make lint      # lua-language-server (every .lua file, tests/ included)
make test      # the mini.test suite (tests/**/*_spec.lua)
```

Tests live in `tests/**/*_spec.lua` and run with `make test`. The tmux adapter
specs drive a real tmux server over a private socket, so `make test` must run
outside a sandbox that blocks unix sockets — see
[docs/gotchas.md](docs/gotchas.md). The test target passes `--offline` to skip
lazy.nvim's per-run update check; the first run still installs the test
dependencies under `.tests/`.

## Conventions

- **Terminology lives in [docs/glossary.md](docs/glossary.md).** Use its words
  in code, comments, docs, and commit messages; when a term changes, change the
  glossary in the same change.
- **Config is data.** `config.lua` carries the option table — every default,
  including a default that is itself the value (a hook, a template) — and
  checks its shape; the behavior an option *selects* is resolved by the module
  that owns it, in that module's own `setup` — `Transport.setup`,
  `Picker.setup`, `Formats.setup`. A module that prepares state exposes
  `setup`, never `apply`.
- Lua 5.1 / LuaJIT only — Neovim's runtime; no features newer than 5.1.
- Every module is `local M = {}` … `return M`; imports use `require("pigeon.…")`,
  sorted by module path.
- Public functions carry LuaLS annotations (`---@param`, `---@return`,
  `---@class`). A seam's contract types live with the seam — `pigeon.Peer` and
  `pigeon.Transport` in `transport/init.lua`, `pigeon.picker.Entry` and
  `pigeon.Picker` in `picker/init.lua` — and options live in `config.lua`.
- Keep the dependency direction: a command file owns its text and its flow; the
  services every flow needs (`reference.lua` for spelling, `deliver.lua` for
  targets) sit below `commands/`; `transport` never depends on the picker or on
  session state.
- Keep the public docs current in the same change: if a change makes
  [README.md](./README.md) or [doc/pigeon.nvim.txt](doc/pigeon.nvim.txt) stale —
  user-facing commands, options, defaults, install, or described behavior —
  update the affected file in that change.
- **User-facing docs say what, not why.** README.md and doc/pigeon.nvim.txt
  describe only what a user does or sees: commands, options, defaults, install,
  and any user-facing trade-off, compressed to what the user decides. Never
  implementation mechanics, Neovim/engine internals, or historical rationale —
  that belongs in code comments or [docs/design.md](docs/design.md).

## External-tool gotchas

See [docs/gotchas.md](docs/gotchas.md).

## Editing these instructions

Keep each rule self-contained while linking high-level docs; condense when
clarity survives.
