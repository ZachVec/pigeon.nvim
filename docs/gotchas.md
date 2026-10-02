# External-tool gotchas

Behaviors of external tools (tmux, Neovim, the test harness) that surprised us
during feature work and caused bugs. Read this before building anything that
interacts with them.

## Tooling · the test runner

### `$NVIM` shadows the Makefile's `NVIM` variable

Neovim exports `NVIM` — the path of its RPC socket — into the environment of
everything it starts. `NVIM ?= nvim` in the Makefile therefore picks up the
socket path, and `make test` tries to execute `/run/user/<uid>/nvim.<pid>.0`
and fails with `not found`. Run `env -u NVIM make test`, or pass `NVIM=nvim`.

### `make test` needs a real socket, and wants `--offline`

The tmux adapter specs drive a real server over a private unix socket. A
sandbox that blocks socket creation or `connect()` — the Codex workspace
sandbox (seccomp) does — makes every tmux operation fail with `error connecting
to /tmp/tmux-<uid>/<name> (Operation not permitted)`, and the specs then fail
deeper with misleading errors. Only an unsandboxed run is authoritative.

The suite passes `--offline` to lazy.nvim's mini.test bootstrap: without it,
every run reaches the network for an update check (measured at 30–60 s per run
versus under a second). The first run still installs mini.test and luassert
into `.tests/`; `rm -rf .tests` is how to ask for a fresh install.

### The suite is how the Neovim floor is checked

`make test NVIM=/path/to/nvim` points the suite at another build. That is how
"Neovim >= 0.11" is verified rather than assumed: every case passes on 0.11.0
and on 0.12.3. Version skew cuts both ways — `vim.fs.relpath` is nil before
0.11, and `vim.health.report_start` (the spelling 0.10 still had) is gone by
0.11 — so a helper the *running* Neovim happens to have is exactly what a
single-version suite cannot catch.

### `--check=lua` is a path, not "all Lua files"

`lua-language-server --check=<value>` takes a **path**, so `--check=lua`
diagnoses the `lua/` directory and silently skips `tests/`. `make lint` passes
the workspace root instead; before that, every diagnostic the editor showed in
a spec was invisible to `make check`.

### A file's `workspace.library` replaces the editor's, it does not extend it

The specs run inside busted's environment — `describe`, `it`, `setup`, and
assertions like `assert.are_not.equal` — which LuaLS knows only when
`workspace.library` names `${3rd}/busted/library` (the globals, and
`assert = require("luassert")`) and `${3rd}/luassert/library` (the assertion
fields). `.tests/`, where the suite installs its own copy of luassert, is
ignored instead: the server would otherwise index a second copy.

That key is not merged with the list an editor plugin injects — lua_ls takes
the file's `workspace.library` as the whole list. A list holding only the two
test libraries therefore drops the project's own `lua/`, which lazydev adds
because it resolves `require` against library roots (`runtime.path` is
`{ "?.lua", "?/init.lua" }`, `pathStrict`) and keeps `ignoreDir = { "/lua" }`
so the workspace scan does not cover the same files. The result is that
`require("pigeon.…")` resolves to nothing: no definitions, no references, and
`(global) vim.api.…` on hover, because the Neovim runtime library went with it.
Measured: without `lua` in the list, `definition` on a `Util.relpath` call
answers nothing; with it, `pigeon/util.lua:146` and 12 references.

`.luarc.json` therefore names the project's own `lua/` and `${env:VIMRUNTIME}/lua`
beside the two test libraries. `${env:…}` is expanded by the server, and
Neovim exports `VIMRUNTIME` to the servers it starts; where nothing sets it
(the CLI lint, CI) the path is simply not there and is ignored.

The luassert meta is also stricter than the library: it declares
`is_true(value)` while the runtime reads a failure message from the next
argument, so `assert.is_true(value, message)` — which works — is a
`redundant-parameter` warning. `assert(value, message)` says the same thing and
type-checks.

## tmux

### Test servers start with `-f /dev/null`

The developer's own tmux configuration shapes the fixtures. `base-index 1`
leaves no window 0 at all, so a positional target like `m:0` fails silently and
a fixture that looks wrong is really a fixture that was configured away.
`default-command` likewise changes what a pane runs. Fixtures therefore start
their server with `-f /dev/null` and address panes by id, never by position.

### `send-keys -l` collapses newlines in some TUIs

`send-keys -l` sends a raw LF, and **claude** collapses those newlines onto one
line (codex preserves them). Multi-line text therefore goes through bracketed
paste instead:

```
tmux set-buffer -b <name> -- <text>
tmux paste-buffer -p -d -t <pane> -b <name>
```

Consequence: bracketed paste inserts the text verbatim, so a trailing newline
becomes a **visible empty line**. Do not append one.

### What an embedded newline does depends on the target

tmux only wraps a paste in bracketed-paste markers when the receiving
application has asked for them. A TUI that has (the agent CLIs pigeon is for)
inserts the newline; a program that has not (a bare `sh`) sees the paste as
typed input, so the newline is its submit key and the line runs:

```
$ hello
sh: 1: hello: not found
```

Pigeon never sends Enter itself. Pasting multi-line text into a shell is the
user's choice, not something pigeon can detect or prevent.

## tmux · processes

### A pane's program is not its process name

Measured on Linux, in a pane running a `#!/usr/bin/env node` script named
`codex`:

| asked | answered |
|---|---|
| `#{pane_current_command}` | `node` |
| `ps -o comm` | `MainThread` |
| `ps -o args` | `node /…/bin/codex` |

tmux reports the foreground process's `argv[0]` verbatim, so a binary run by
path reads `./codex`, and `ps`'s name column for a node process is its main
*thread* name. The program's own name survives only in the arguments — which is
why a Profile matches the whole command line, read with one
`ps -A -ww -o pid,ppid,args` and walked breadth-first from the pane's pid.

### `pane_start_command` is the wrong fact

It is the command the pane was **created** with and never changes afterwards: a
pane where the user typed `codex` into a shell reports `sh`, and a pane launched
as `tmux split-window claude` still reports `claude` after claude has exited.
It cannot stand in for reading the pane at send time, and it fails silently in
both directions.

## Pickers

### Runtimepath is not a reliable dependency check under lazy.nvim

A configured engine can be installed but not yet on `runtimepath` when
`setup()` runs, so `nvim_get_runtime_file("lua/fzf-lua/init.lua", …)` answers
nothing even though the module is loadable on demand. `pigeon.picker.setup`
checks with `pcall(require, …)` instead: fail-fast without misreporting a
lazily-installed engine as missing.

## Pickers · fzf-lua

### `fzf_exec` function contents writes one item per callback

A function contents is invoked as `contents(on_write_nl, on_write, …)`. The
**first** callback (`on_write_nl`) writes ONE item (it appends the EOL); call
it once per item, then call it with `nil` to signal end-of-input. Passing a
whole table to the first callback renders `table: 0x…`. The write lands in a
pipe that stays open until the `nil` call, so a callback may be invoked
**after** the contents function returned, from a libuv callback: that is what
lets a pick push entries as a lister produces them. Batch several items into
one `on_write` call where you can — one pipe write per batch.

### Window options — including `on_close` — live under `winopts`

`fzf_exec(contents, opts)` takes picker-level options (`prompt`, `actions`,
`preview`, `fzf_opts`) at the top level, but every window option lives under
`opts.winopts`. A top-level `on_close` is **silently ignored** — the handler
never runs and nothing errors.

### No preview function means no preview pane

`fzf_exec` hides the pane when `opts.preview` is nil and no explicit
`--preview` is set, which also overrides a preview in `$FZF_DEFAULT_OPTS`.
Omitting the option is therefore how a pick has no preview pane, while a
preview function that returns nothing keeps the pane, empty.

### fzf returns display strings, not objects

Recover the entry with a numeric-prefix round-trip (`"1. text"`, parse the
leading index) and keep that items array in sync across reloads. The prefix
does not have to be visible: `--with-nth=2..` hides it from the list and fzf
still hands actions the original line. Do NOT pair it with `--nth=2..`: fzf
evaluates `--nth` against the *transformed* line, so a single-token path such
as `src/main.lua` is left with an empty search scope and any query empties the
list.

## Pickers · snacks

### Finder signature is `fun(opts, ctx): result`

The finder returns either an items table or an async `fun(cb)`; it is not
`fun(cb)` directly. The async form runs inside snacks' own task, and its `cb`
drives that task's coroutine, so it must not be called straight from a libuv
callback: queue what arrives, resume the task, and call `cb` from inside the
task's own loop — the shape `snacks.picker.source.proc` uses, and what
`pigeon.picker.snacks`' stream does for a lister that outlives the finder call.

### No preview function means an empty pane, not no pane

snacks' layout carries a preview window whether or not a `preview` function is
given, and a nil one leaves it empty. Hiding the pane takes
`layout = { preview = false }`.

### Keymaps field is `win.<pane>.keys`, not `keymaps`

Custom keys live in `win.input.keys` / `win.list.keys` / `win.preview.keys`;
values are action names (a string) or `{ "name", mode = { … } }`. `actions` is
`{ name = fun(picker, item) }`, and `win.*.keys` **merges** with the defaults.

### Refresh, don't reopen

`picker:refresh()` re-runs the finder; a command that reports the list may have
changed refreshes the picker whose finder then re-runs the flow's stream. Same
for fzf-lua, where the in-place equivalent is an action with `reload = true`
over function contents (close/reopen flickers: fzf is a full-screen process).

### Picker entries must not carry a `resolve` field

snacks resolves any item with a `resolve` function during formatting —
`item.resolve(item)`, then sets `item.resolve = nil` — for lazy items. An entry
field named `resolve` therefore gets called by the picker itself, with the
entry as its only argument.

### Schedule picker callbacks that change the UI

A `confirm` callback that jumps, opens a float, or otherwise changes the UI must
run after the picker's own windows are gone. `pigeon.picker.snacks` closes the
picker first and hands the choice to the flow a tick later; the fzf-lua adapter
does the same by scheduling `on_choices`.

## Neovim

### A pick's own window is current while the flow's callback runs

A float-based `vim.ui.select` — snacks', fzf-lua's, dressing's — has its own
buffer current when `on_choices` fires, so a flow that reads the buffer or
cursor inside that callback spells references against the picker instead of the
file. Measured: `{line}` in `:Pigeon prompt` resolved empty (`{line} resolved
empty`) because the context was a nameless picker buffer. Read the context
before the pick opens; `pigeon.commands.prompts` does, and the commands spec's
picker fake keeps its own buffer current so a flow that forgets fails there.

### `vim.ui.select` takes a fixed list, so `native` drains the item stream

`native` cannot open its window until it has the whole list, so it waits for
the stream to end — and a lister that never ends (a `find` across a hung
network mount) waits with it. Bounding that would take an arbitrary timeout or
a picker that can stream, which `vim.ui.select` cannot do, so the limitation is
accepted rather than fixed. `fzf-lua` and `snacks` stream and can be cancelled,
so they are unaffected.

### `vim.fs.relpath` answers three different ways

Measured on 0.12.3: a descendant gives the relative path (`a/b`), a path
outside the base gives `nil`, the base itself gives `"."`, and a nil base
**raises** rather than answering. `pigeon.util.relpath` folds all of those into
"keep the path as it is", which is what makes an outer path come out absolute.
The function landed in 0.11 (it is listed under "Notable changes since Nvim
0.10"), and it is the plugin's version floor.

### `gsub` overwrites a recorded failure

A `gsub` callback that records the failing placeholder must not overwrite it:
`"{file} and {line}"` against an unnamed buffer fails on both, and whichever is
visited last wins — an arbitrary answer. `pigeon.util.interpolate` keeps the
first (`failed = failed or name`).

### `vim.system` reports a signalled process as exit code 0

A process killed by a signal comes back with `code = 0` and `signal = N`, not
as a failure. Treat `signal ~= 0` as `128 + N` (`pigeon.util.run_lines` does),
or a cancelled listing looks like a finished one.

### `vim.notify` raises in a fast event context

The default handler calls `nvim_echo`, which is main-loop only: a notification
raised from a libuv callback — a `vim.system` exit — raises
`E5560: nvim_echo must not be called in a fast event context`, and the raise
unwinds the callback. `pigeon.util.notify` defers through `vim.schedule`.

### `<cmd>` and Lua mappings keep Visual mode active

The `'<`/`'>` marks are not written until Visual mode exits, so a mapping that
reads the visual range must leave Visual mode first (`normal! \27`). Pigeon
does this in one place, `pigeon.commands`' range resolution, for both
`:Pigeon send` and `:Pigeon comment`.
