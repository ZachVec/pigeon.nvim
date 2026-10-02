NVIM ?= nvim
NVIM_LOG ?= /tmp/pigeon-nvim.log
MASON_BIN ?= $(HOME)/.local/share/nvim/mason/bin

# Resolve a tool from PATH, falling back to the mason bin directory.
find_tool = $(or $(shell command -v $(1) 2>/dev/null),$(if $(wildcard $(MASON_BIN)/$(1)),$(MASON_BIN)/$(1)))

STYLUA := $(call find_tool,stylua)
LUA_LS := $(call find_tool,lua-language-server)

# `nvim --headless -l` falls back to a `nvim.log` in cwd when the user's main
# nvim holds the default log lock; pin the log to /tmp to keep the repo clean.
NVIM_RUN = NVIM_LOG_FILE=$(NVIM_LOG) $(NVIM) --headless -u NONE -l

.PHONY: check style lint test

## check: Lua format + diagnostics + the mini.test suite
check: style lint test

## style: check Lua formatting (stylua)
style:
	@if [ -n "$(STYLUA)" ]; then $(STYLUA) --check .; else echo "note: stylua not installed; skipping Lua format check"; fi

## lint: check Lua diagnostics (lua-language-server)
lint:
	@if [ -n "$(LUA_LS)" ]; then $(LUA_LS) --check="$(CURDIR)" --checklevel=Warning --configpath="$(CURDIR)/.luarc.json"; else echo "note: lua-language-server not installed; skipping Lua diagnostics"; fi

## test: run the mini.test suite (tests/**/*_spec.lua)
## --offline skips lazy.nvim's per-run update check, which otherwise reaches
## the network on every run. The first run still installs the test dependencies
## into .tests/; `rm -rf .tests` is how you ask for a fresh install.
test:
	@$(NVIM_RUN) tests/minit.lua --minitest --offline
