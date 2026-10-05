# Pigeon Design

Pigeon sends text from Neovim into the **other panes of the multiplexer window
this Neovim sits in**. It is the sending half of `vantage.nvim` — the Prompt,
Files, Buffers, and Comments systems — with no agent management: no creating,
attaching to, killing, or listing agents, and no private multiplexer server.

This file is the design record: the seams and their contracts, how the pieces
relate, the decisions taken while designing, and the conditions under which a
decision is worth revisiting.

## Scope

In scope: producing text from Neovim state — prompts, references (files and
buffers), and comments — and delivering it into a peer pane; choosing which
pane to deliver to; reporting what happened.

Out of scope (deliberately dropped from vantage): agent lifecycle, groups,
terminal views, the private tmux socket, `cli.tools`, and any window/terminal
layout management.

## The two axes, and the one seam between them

Pigeon has two jobs that vary independently:

```
produce text from Neovim            deliver text into a peer pane
references · prompts · comments ──▶  the multiplexer adapter
   (ported from vantage)                (the new part)
```

Everything above the arrow knows nothing about tmux. Everything below knows
nothing about Neovim. The seam between them is the only place a multiplexer is
named.

## Seams and contracts

### Transport (the multiplexer seam)

Contract types live here, in `transport/init.lua`, next to the resolution
logic — the same shape as `vantage.Driver` living with the Backend seam.

```lua
---@class pigeon.Peer  a handle on one target pane
---@field repr fun(self: pigeon.Peer): string          -- display name; must distinguish panes
---@field send fun(self: pigeon.Peer, render: pigeon.Render): boolean, string?

---@class pigeon.RenderCtx  one target, as the adapter read it at send time
---@field cwd string?                                   -- nil: every path spells absolute
---@field process string[]?                             -- nil: no Profile can be matched

---@alias pigeon.Render fun(ctx: pigeon.RenderCtx): string?, string?
--                                            ^text    ^reason, when there is nothing to deliver

---@class pigeon.Transport  one multiplexer adapter
---@field peers fun(): pigeon.Peer[]?, string?          -- siblings of the current pane, excluding self
```

Invariants:

- An adapter instance is bound to **one ambient multiplexer instance**, taken
  from the environment (`$TMUX`, `$ZELLIJ`, `$WEZTERM_PANE`, `$KITTY_LISTEN_ON`,
  `$STY`). A peer handle is only meaningful inside it.
- `peers()` never includes the pane this Neovim runs in, and never includes
  panes outside the current window.
- A peer handle is valid for the lifetime of the pane it names. Multiplexers
  that mint stable ids (tmux's `%N`) never hand a dead pane's id to a new pane,
  so holding a handle across invocations is safe; a dead pane fails loudly.
- `send(render)` asks the target for its own context, calls `render(ctx)`, and
  delivers the result **verbatim, without submitting** (no Enter). Bracketed
  paste is how multi-line text survives a TUI.
- What an embedded newline *does* is the receiving application's business: a
  bracketed-paste-aware TUI (the agent CLIs this is for) inserts it, while a
  bare shell treats it as its submit key and runs the line. Pigeon never sends
  Enter itself; pasting multi-line text into a shell is the user's choice.
- `cwd` is the target's working directory at send time, or nil when the adapter
  cannot determine one; a nil `cwd` makes every path in the rendered text
  absolute.
- `process` is the target's command lines at send time, outermost first, or nil
  when the adapter cannot determine them. `formats` matches its Profiles against
  them; a nil leaves only the configured `format`.

Depth behind those two entries: environment detection, socket selection,
`list-panes -F` parsing, self-exclusion, dead-pane filtering, "no server reads
as an empty inventory," bracketed-paste staging, and error mapping.

### Picker (the selection-UI seam)

One method: `pick(spec, on_choices)`. A spec carries the prompt, how many
entries the flow acts on (`many`), an optional `preview` (absent means no
preview pane at all), and the item stream.

Implementations stay presentation-only: they render `entry.text` and call
`spec.preview` — supplied by the flow — only for the highlighted entry.

Two things vantage carried are gone. Its `capabilities.command` existed because
a flow there *branched* on it (the agent list scoped itself differently without
command support), and its `commands` bound extra keys inside a pick; pigeon's
only pick that took a key was the comment list, so both the capability and the
commands went with it — re-adding a key to a pick means re-adding the seam.
Its second entry point, `pick_naive`, had one consumer (the prompt-name pick),
which `many = false` already covers.

All three ship. `native` drains the stream into `vim.ui.select`; `fzf-lua`
pushes each batch into `fzf_exec`'s stdin and round-trips a chosen line back to
its entry through a hidden numeric prefix (fzf returns display strings, not
objects); `snacks` drives the picker's finder and drains a stream that outlives
that call from inside snacks' own async task.

A flow reads the ambient state it acts on — the buffer, the cursor — **before**
it opens a pick. An implementation makes its own window current, so with a
float-based `vim.ui.select` (snacks, fzf-lua, dressing) the buffer is still the
picker's while the flow's callback runs.

`vim.ui.select` takes a fixed list, so `native` drains the item stream before it
opens, and a lister that never ends waits with it. Bounding that would take an
arbitrary timeout or a picker that can stream, which `vim.ui.select` cannot do:
the limitation is accepted (see [gotchas.md](gotchas.md)).

### Entries

An entry is what a pick can offer: `text` plus whatever fields its flow owns.
It is plain data, not an interface — a value the flow produces and the picker
reads, with no behaviour only an implementation could supply.

| kind | fields | preview |
|---|---|---|
| `file` | `path` | first lines of the file |
| `buffer` | `buf`, `path` | live buffer lines, falling back to the file |
| `peer` | `peer` | none (see Q13) |

There is **no `kind` discriminator**. Vantage needed one because a single pick
there mixed kinds (focused/agent/tool in one list, agent/group in another);
every pigeon pick is homogeneous, so a flow pairs its constructor with its
preview function directly.

There is also **no entries module**. Every kind has exactly one producer, so
the entry's fields and its preview live with that producer: file and buffer in
`commands/references.lua`, peer in `deliver.lua`. `picker/init.lua` owns the
contract itself
(`pigeon.picker.Entry = { text }`), because the picker is the consumer.

## Delivery pipeline

```
commands                    deliver                    transport (tmux)
  pick a source  ──▶   resolve target(s)   ──▶   peer:send(render)
  build a Render       (remembered /               ├─ read pane cwd + pid
                        single / pick)             ├─ read the pane's command lines
                                                   ├─ render(ctx)
                                                   └─ set-buffer
                                                      paste-buffer -p
                                                      delete-buffer
```

Splitting responsibility this way means a flow can never render once and send
the same string to several panes: the only way to deliver is through
`Peer.send(render)`, so rendering is per target by construction. Because the
context carries what the target is running, the same Render spells each pane's
references its own way.

## Module map and dependency direction

```
lua/pigeon/
├── init.lua            composition root: read config, set the modules up, install :Pigeon
├── config.lua          options: the defaults, and the shape checks (data only)
├── util.lua            shared helpers
├── transport/
│   ├── init.lua        the seam: Peer + Transport contracts, detection, resolution
│   └── tmux.lua        the tmux adapter
├── deliver.lua         target resolution (remembered / single / pick) + per-target fan-out
├── reference.lua       the one reference spelling every command spells through
├── formats/            the program registry: one Profile per program
│   ├── init.lua        Profile + Match contracts, resolution, matching
│   ├── claude.lua      claude code
│   └── codex.lua       codex
├── picker/             the selection-UI seam + native, fzf_lua, snacks
└── commands/
    ├── init.lua        :Pigeon dispatch, usage, completion
    ├── prompts.lua     named templates, placeholder resolvers, and the pick
    ├── references.lua  files + buffers sources, and the pick
    └── comments.lua    one comment's item template, and the prompt for it
```

Dependencies point one way:

```
composition → commands ──▶ deliver ──▶ transport
                  └────▶ picker
                  └────▶ reference ──▶ formats
                          shared: config, util
```

- A command file owns the text it produces and the flow that delivers it. The
  two halves were separate layers once; they were merged when it turned out
  every producer had exactly one consumer (see #23).
- `reference` and `deliver` are the services every flow needs: how a path
  reads, and where the message goes. Both sit below `commands/` so no command
  spells or targets another's way.
- `formats` sits below `reference`: the one spelling asks it which format this
  target reads. A Profile names a program, never a multiplexer, and a command
  never names a Profile.
- `deliver` owns "whom to send to and how to report it", and is the only place
  the remembered target lives.
- `transport` never depends on the picker or on session state.

## Configuration surface

```lua
require("pigeon").setup({
  multiplexer = "auto",     -- auto | tmux
  picker = "native",        -- native | fzf-lua | snacks

  format = hook,            -- function(file, loc) -> string; the plain spelling by default
  prompts = {},             -- named templates; {file} and {line} are built in
  comments = { item = "{lines} {note}\n" },
  references = { join = "\n" },
})
```

## Command surface

```
:Pigeon prompt                  pick a template, render it per target, deliver
:Pigeon files                   pick files, deliver their path references
:Pigeon buffers                 pick buffers, deliver their path references
:Pigeon comment                 ask for a note about the range, deliver it
:Pigeon send                    range-aware; deliver the selection or line verbatim
:Pigeon retarget                choose which peer pane is the target
:Pigeon status                  the current target, and the detected multiplexer
```

No keymaps are installed.

## Decisions

| # | Decision |
|---|---|
| 1 | **Peer and Transport are two interfaces**, both implemented by one adapter; tests mock both. |
| 2 | **No `id` on Peer.** Remembering a target means holding the handle; no cross-restart persistence. |
| 3 | Several siblings → pick (multi-select covers "all"); exactly one → send directly. |
| 4 | **A send never submits.** It pastes, and it does not press Enter: what you send waits for you to review it. There is no option to do otherwise and none is planned — submitting is the user's keystroke, never the plugin's. |
| 5 | References are spelled per target: relative to that pane's cwd (nil cwd → absolute paths), and in the format that pane's program reads. |
| 6 | All four producers ship, and so do all three pickers (`native`, `fzf-lua`, `snacks`). |
| 7 | **`Peer.send(render)`**, not `send(text)`: the target's context — its cwd, and what it is running — is the implementation's business, and rendering per target is enforced structurally. |
| 8 | Previews **do not** promise "what you see is what gets sent"; the comment list renders against Neovim's cwd. |
| 9 | No target-pane preview (no capture) in v1. |
| 10 | `labels` are a `repr()` function, so adapters compute them lazily. |
| 11 | **`kind` is dropped**: every pick is homogeneous, so flows pair constructor with preview directly. |
| 12 | The files/buffers module stays one module: two sources behind an internal seam, sharing the "path set → Render" half. |
| 13 | **No entries module**: each kind has exactly one producer, so its constructor and preview live with that producer. |
| 14 | `deliver` sits above `transport`, not inside it: it needs the picker, and target policy is not a multiplexer concern. |
| 15 | Comments are `comments`, not `reviews`, and they are **one-shot**: `:Pigeon comment` asks for a note and delivers it in the same breath. Nothing is stored, so there is no registry, no list, no editing float, and no `{comments}` placeholder; a batch accumulates in the target's own input, because pigeon never submits. |
| 16 | `:Pigeon retarget` (not `target`): `status` already answers "what is the target", so the command is an action. |
| 17 | Detection is automatic (`auto`) with a config override; ambiguous nesting prefers the explicit setting. |
| 18 | `peers()` and `send()` are synchronous; file listing stays async and streaming. |
| 19 | Flows are tested against a mock Transport; the tmux adapter is tested against a real tmux server over a private socket, unsandboxed. |
| 20 | The target's cwd is read **at send time**, not frozen at enumeration, so a pane that has changed directory still gets correct relative paths. |
| 21 | The picker seam is **one method**, `pick(spec, on_choices)`: no `capabilities` (vantage's existed for a flow branch pigeon does not have) and no plain-select entry point (`many = false` covers it). |
| 22 | **The picker seam carries no commands.** Vantage's `commands` bound extra keys inside a pick, and its `capabilities.command` let a flow branch on that; pigeon's only pick that took a key was the comment list, so both went with it. |
| 23 | **A producer lives with the command that uses it**: `commands/<name>.lua` holds both the text and the flow. They were separate layers (`compose/` above `commands/`) until every producer turned out to have exactly one consumer; the one exception is the spelling all three share, which sits below them in `reference.lua` beside `deliver.lua`. |
| 24 | A single chosen pane becomes the session's target; a **multi-choice is a one-off broadcast** that remembers nothing (there is no honest way to remember "one of several"). |
| 25 | The producers are named for what they produce, in the plural: `prompts`, `references`, `comments`. `gather` named an act without its object — the same fault as `send` — and the module's substance is the **references** it spells. |
| 26 | **`config.lua` is data**: the defaults — including the default `format` hook itself, so the resolved table shows how a reference reads — plus shape checks (`format` a hook, `comments.item` a string). What a value *selects* — which picker a name picks, which Profile a pane matches — is resolved by the module that owns it, in that module's own `setup`; `formats` consequently owns the matching, not the default. Nothing is called `apply`. |
| 27 | **A comment stays templated.** `comments.item` decides the shape a comment sends in — `{lines} {note}\n` by default, over `{note}`, `{lines}`, `{file}`, `{start}`, and `{end}` — so the arrangement is the user's, not one option per arrangement. The default ends in a newline, so consecutive comments do not run together, and a template that does not want one can leave it off. |
| 28 | **The file lister is resolved once**, in `References.setup`: the first of fd, rg, find on PATH. A machine's tools do not come and go under a session, so a `files` pick never re-probes and never falls through — a lister that fails reports its own failure. Installing one takes another `setup`. |
| 29 | **Which format a reference takes is a fact about the target, not a setting.** `Peer.send` hands the renderer the target's context, and the first **Profile** that recognizes one of the pane's command lines decides; `format` is the fallback for a target no Profile recognizes. |
| 30 | **Profiles are a registry, one file per program**, the shape the transport adapter registry already has: `lua/pigeon/formats/<name>.lua`, a whitelist, resolved in `formats.setup`. The built-ins are the whole set — nothing in `setup()` names a Profile, and `format` stays the only format knob. |
| 31 | **A Profile matches the command line, not the process name.** `ps`'s name column is unreliable (a node process reports its main thread as `MainThread`), and the pane's current command is only the foreground `argv[0]` (`node` for a `#!/usr/bin/env node` program, `./codex` when it is run by path): a program's own name survives in the arguments, and matching the whole line reaches it. |
| 32 | **The process chain is read at send time**, like cwd (#20): breadth-first from the pane's own pid, outermost first, and each command line is tried against the Profiles in order. `pane_start_command` is deliberately not a source — it never changes after the pane is created, so it would report a program the pane no longer runs. |
| 33 | **The lister follows directory symlinks.** fd runs `--follow` (and no longer `--type l`), rg `--follow`, find `-L`, so a linked directory's contents are listed and the link itself is not an entry; following also keeps a symlinked file and drops a broken link. The listed paths stay spelled through the link — the lister reports `link/…`, never the resolved target — so a reference stays under the listing root even when the target is outside it. A following lister exits non-zero on a link it could not follow even when the listing is complete, so a run that produced entries is answered and only a silent non-zero exit is a failure. |

## Reintroduction conditions

Each of these is a deliberate "not now"; each names what would reopen it.

- **`id` on Peer** — when a target must be addressed without re-enumerating, or
  must survive a Neovim restart.
- **A shared "path set → Render" module** — when a third, unrelated consumer
  appears (quickfix, diagnostics), or when the file listing grows enough to
  deserve its own module.
- **An entries module** — when a kind gains a second consumer, so its shape
  stops being one producer's private business.
- **A producer split away from its command** — when a producer gains a second
  consumer: a prompt placeholder reading another producer's output (the old
  `{comments}`), a quickfix source, or a listing of "what pigeon can send".
  Then that producer's text half moves back out, and its consumers spell it.
- **Picker commands** — when a flow needs a key inside a pick (a delete, a
  toggle). That brings back the spec field, the adapters' binding code, and
  `pigeon.picker.Command` together.
- **A stored comment batch** — when a note must be editable, reviewable, or
  wrapped in a prompt template before it goes out. That is the registry, the
  `{comments}` placeholder, and clear-on-send, which were removed together
  precisely because a one-shot note needs none of them.
- **`{code}` in a comment** — when a note must carry the code inline rather
  than a reference the target opens itself. It is the one field the template
  can no longer spell.
- **A liveness check (or `id`) for the remembered target** — a remembered pane
  that dies makes every later send fail. Today the error names the pane and
  `:Pigeon retarget` is the fix; revisit if that proves worse than the check.
- **`kind`** — when a single pick must mix entry kinds; the flow's preview
  function dispatches internally, previews stay at pick level.
- **Target-pane preview (capture)** — when choosing among panes needs more
  than the repr; this is also the signal that Peer needs a second behavior.
- **Env, or richer process records, in the context** — when a program cannot be
  told apart by its command line alone (a wrapper running several CLIs, an
  exclusion like copilot's language server), `ctx.process` grows into records
  carrying `env` and `cwd`.
- **A configured Profile** — when someone needs a program Pigeon does not ship,
  or a different format for claude or codex: `formats` comes back as an option
  (an overlay by name) or as a runtimepath file, and the registry already loads
  by name, so either is a second source for the same table.

## Testing

- Flow tests take a mock Transport and mock Peers: no sockets, no tmux.
- Profile resolution is unit-tested without a pane (`formats_spec`); the tmux
  adapter's own reading of a pane's command lines is tested against the real
  server.
- The tmux adapter is tested against a real tmux server on a private socket.
  Because the sandbox blocks `connect()` to unix sockets, that suite only
  produces trustworthy results when run unsandboxed.
- Suite servers start with `-f /dev/null`: the developer's own tmux
  configuration otherwise shapes the fixtures (`base-index 1` leaves no window
  0; `default-command` changes what a pane runs). Fixtures address panes by id,
  never by position, for the same reason.
