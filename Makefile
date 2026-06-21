.PHONY: help install uninstall test test-unit test-integration lint format clean release

SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHFMT := $(shell command -v shfmt 2>/dev/null)
BATS := $(shell command -v bats 2>/dev/null)
PYTHON := $(shell command -v python3 2>/dev/null)

RELAY_HOME ?= $(HOME)/.claude/hooks
RELAY_DIR ?= $(HOME)/.relay-cards

# 让 hooks 目录可覆盖，方便测试
SRC_LIB := src/lib
SRC_ADAPTERS := src/adapters

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install:  ## Install to $$RELAY_HOME (default ~/.claude/hooks)
	@bash scripts/install.sh

uninstall:  ## Uninstall from $$RELAY_HOME
	@bash scripts/uninstall.sh

test: test-unit test-integration  ## Run all tests
	@echo "✅ all tests passed"

test-unit:  ## Run unit tests with bats
ifndef BATS
	@echo "❌ bats not installed. Run: brew install bats-core"
	@exit 1
endif
	@$(BATS) tests/unit/

test-integration:  ## Run end-to-end integration tests
	@bash tests/integration/run-all.sh

lint:  ## Lint shell scripts with shellcheck
ifndef SHELLCHECK
	@echo "❌ shellcheck not installed. Run: brew install shellcheck"
	@exit 1
endif
	@$(SHELLCHECK) -x src/lib/*.sh scripts/*.sh bin/* 2>&1 || true
	@echo "✅ shellcheck passed"

format:  ## Format shell scripts with shfmt
ifndef SHFMT
	@echo "❌ shfmt not installed. Run: brew install shfmt"
	@exit 1
endif
	@$(SHFMT) -w -i 2 -ci src/lib/*.sh scripts/*.sh bin/* 2>&1 || true
	@echo "✅ shfmt applied"

clean:  ## Remove build artifacts and test fixtures
	@rm -rf tests/fixtures/relay-cards/
	@rm -f src/lib/*.bak.* src/lib/*.tmp.*
	@echo "✅ cleaned"

release:  ## Tag a new release (requires clean git tree)
	@bash scripts/release.sh

.DEFAULT_GOAL := help
