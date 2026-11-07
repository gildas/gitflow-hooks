-include .env

# Goodies
V = 0
Q = $(if $(filter 1,$V),,@)
E :=
S := $E $E
M = $(shell printf "\033[34;1m▶\033[0m")
P = echo -e

# Folders
HOOKS_DIR ?= hooks

# Version, branch, and project
BRANCH  != git symbolic-ref --short HEAD
COMMIT  != git rev-parse --short HEAD
VERSION != awk -F'"' '/^\[/{ in_package = ($$0 == "[package]") } in_package && /^version *=/{ print $$2; exit }' Cargo.toml
ifeq ($(VERSION),)
VERSION != git describe --tags --always --dirty="-dev"
endif
PROJECT != awk -F'"' '/^\[/{ in_package = ($$0 == "[package]") } in_package && /^name *=/{ print $$2; exit }' Cargo.toml
ifeq ($(PROJECT),)
PROJECT != basename "$(PWD)"
endif
BINARY  ?= hook-it
export PROJECT VERSION BRANCH COMMIT

# Tools
CARGO      ?= cargo
BASH       ?= bash
SHELLCHECK ?= shellcheck
AWK        ?= awk

# Flags
CARGO_FLAGS   ?= $(if $(filter 1,$V),--verbose,--quiet)
INSTALL_FLAGS ?=
ifneq ($(what),)
TEST_ARG := $(what)
else
TEST_ARG :=
endif

ifeq ($(OS), Windows_NT)
  OSTYPE = windows
  include Makefile.windows
else
  OSTYPE != uname -s
  ifeq ($(OSTYPE), Linux)
    OSTYPE = linux
    include Makefile.linux
  else ifeq ($(OSTYPE), Darwin)
    OSTYPE = darwin
    include Makefile.linux
  else ifeq ($(OSTYPE),)
    $(error Please use GNU Make 4 at least)
  else
    $(error Unsupported Operating System)
  endif
endif

# Main Recipes
.PHONY: all build clean dep fmt help install lint lint-hooks lint-rust test uninstall version

help: Makefile; @ ## Display this help
	@$P "$(PROJECT) version $(VERSION) in $(BRANCH) branch ($(COMMIT))"
	@$P "Make recipes you can run: "
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		$(AWK) 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: lint test build; @ ## Lint, Test, and Build the application

build:; $(info $(M) Building $(BINARY) $(VERSION)...) @ ## Build the application (the hooks are embedded in the binary)
	$Q $(CARGO) build $(CARGO_FLAGS) --release

install:; $(info $(M) Installing $(BINARY) $(VERSION) with the current hooks...) @ ## Install the application with cargo install
	$Q $(CARGO) install $(CARGO_FLAGS) $(INSTALL_FLAGS) --path .
	$(info $(M)   Get some help with $(BINARY) --help)

uninstall:; $(info $(M) Uninstalling $(BINARY)...) @ ## Uninstall the application installed with cargo install
	$Q $(CARGO) uninstall $(CARGO_FLAGS) $(PROJECT)

test:; $(info $(M) Running tests...) @ ## Run the Unit Tests (make test what='test_name')
	$Q $(CARGO) test $(CARGO_FLAGS) $(TEST_ARG)

lint: lint-rust lint-hooks; @ ## Lint the Rust code and the hooks

lint-rust:; $(info $(M) Linting the Rust code...) @ ## Lint the Rust code with clippy
	$Q $(CARGO) clippy $(CARGO_FLAGS) --all-targets -- -D warnings

lint-hooks:; $(info $(M) Linting the hooks...) @ ## Check the syntax of the hooks (and run shellcheck if installed)
	$Q $(foreach hook, $(HOOKS), $(BASH) -n $(hook) || exit 1 ;)
	$(SHELLCHECK_RUN)

fmt:; $(info $(M) Formatting the code...) @ ## Format the code following the rustfmt rules
	$Q $(CARGO) fmt

dep:; $(info $(M) Updating dependencies...) @ ## Update the dependencies in Cargo.lock
	$Q $(CARGO) update $(CARGO_FLAGS)

clean:; $(info $(M) Cleaning up folders and files...) @ ## Clean up
	$Q $(CARGO) clean $(CARGO_FLAGS)

version:; @ ## Get the version of this project
	@$P "$(VERSION)"
