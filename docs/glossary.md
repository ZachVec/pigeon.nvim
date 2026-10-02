# Pigeon glossary

The words this project uses, and the words it refuses to use for the same
thing. Code, comments, and docs draw from here; when a term stops matching the
code, one of the two is wrong. Structure and rationale live in
[design.md](design.md).

## Delivering

**Multiplexer**:
The terminal multiplexer this Neovim runs inside, which owns the panes. tmux
today; the adapter seam is where another one would be added.
_Avoid_: mux, terminal, backend

**Window**:
In a multiplexer, the frame holding one or more panes. Pigeon's scope is the
other panes in the window its Neovim sits in.
_Avoid_: tab, session

**Pane**:
One region of a multiplexer window. Pigeon sends into panes, never into a
session or a tab.
_Avoid_: split, terminal, window

**Sibling**:
Another pane in the same window as Neovim's pane — the candidate set a send
chooses from.
_Avoid_: other pane, neighbour, target

**Transport**:
The multiplexer side of the seam: detecting which multiplexer this is, listing
its panes, delivering into one.
_Avoid_: backend, driver, client, mux layer

**Adapter**:
One Transport implementation, for one multiplexer.
_Avoid_: backend, driver, plugin, impl

**Peer**:
A handle on one pane a send can be delivered to. Holding a peer is how a
session remembers where it sends.
_Avoid_: target, pane, pane id, destination, handle

**Target**:
The peer a send goes to, once one has been chosen.
_Avoid_: destination, recipient, peer

**Send**:
Delivering text into the target pane. A send is a paste, never a keystroke:
pigeon does not press Enter.
_Avoid_: submit, type, write, input

**Submit**:
Pressing Enter in the target so the delivered text takes effect. Always the
user's keystroke, never pigeon's.
_Avoid_: send, run

**Render**:
The text a send will deliver, produced per target. A Render is a function of
the target's cwd, not a finished string.
_Avoid_: message, payload, content, body

**cwd**:
The target pane's working directory, read at send time. nil means the adapter
cannot tell, which makes every path in the text absolute.
_Avoid_: dir, base, root, cwd of Neovim

## Composing

**Producer**:
One of the four sources of text pigeon composes — prompts, files, buffers,
comments.
_Avoid_: source, gatherer, collector, provider

**compose**:
The act of producing text from Neovim state.
_Avoid_: gather, collect, send, source

**Prompt template**:
A named piece of text with placeholders, offered by `:Pigeon prompt`.
_Avoid_: prompt on its own (see Picker prompt), snippet, macro

**Placeholder**:
A `{...}` token inside a prompt template, resolved when the prompt is sent.
`{file}` and `{line}` are built in.
_Avoid_: variable, field, slot

**Reference**:
A path, with an optional line or range, naming a file or buffer the target can
open.
_Avoid_: link, path, file ref, file

**format**:
The configured hook deciding a reference's dialect — `file`, `file :L42`,
`@file`.
_Avoid_: template, style, dialect

**Comment**:
A note about a line range of a normal file, sent as soon as it is typed.
Comments are not stored, so a second comment is a second send.
_Avoid_: annotation, mark, review

**note**:
The free text of a comment, as opposed to the range it is about.
_Avoid_: text, body, message, content

## Choosing

**Picker**:
The selection-UI seam: the implementation that asks the user to choose among
entries.
_Avoid_: selector, menu, ui, fuzzy finder

**Pick**:
One run of the picker.
_Avoid_: selection, dialog, window, prompt

**Picker prompt**:
The label a pick shows in its own input line.
_Avoid_: prompt on its own (that is a prompt template)

**Entry**:
One thing a pick offers: the line it renders, plus the fields its flow owns.
_Avoid_: item, row, result, record

**Item stream**:
The sequence of entries a pick is fed while it is open; it can still be
producing after the pick has opened.
_Avoid_: source, stream, list

**many**:
How many entries a pick hands its flow. `many = false` acts on one, `true` on
every mark.
_Avoid_: multi, multiple, multi-select, single

**Preview**:
The pane showing details of the highlighted entry. A preview never promises
what a send would produce.
_Avoid_: peek, detail view, side pane

## Orienting

**Command**:
What the user types at `:Pigeon` — one subcommand line.
_Avoid_: subcommand, action, verb

**Flow**:
One command's orchestration: pick, compose a Render, deliver. The code behind
a command.
_Avoid_: command, handler, action, job, pipeline

**Remembered target**:
The peer later sends reuse because a previous pick chose it.
_Avoid_: session target, current target, default target, selection

**Broadcast**:
A send to several peers at once, chosen by a multi-choice. It remembers
nothing.
_Avoid_: fan-out, multicast, send-all
