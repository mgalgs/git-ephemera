# Development Guide for Agents

This document provides instructions for AI agents working on the git-notestash codebase.

## Project Overview

`git-notestash` is a Bash CLI tool that attaches ephemeral development files to git commits via git notes. See `README.md` for user-facing documentation and `.ai/PRD.md` for product requirements.

## Implementation Status

Check `.ai/PLAN.md` for current implementation status and remaining work.

## Running Tests and Linting

Use the Makefile targets:

```bash
make check   # Run shellcheck linting
make test    # Run test suite
make all     # Run both (default)
```

Or run directly:

```bash
./test-notestash.sh
shellcheck git-notestash test-notestash.sh
```

Tests create isolated git repos in temp directories. All tests must pass and shellcheck must report no warnings before submitting changes.

If a shellcheck warning is intentional (e.g., glob expansion), add a `# shellcheck disable=SCXXXX` directive with a comment explaining why.

## Code Style

- Use `set -euo pipefail` at the top of scripts
- Quote variables unless glob expansion is intentional
- Use `local` for function-scoped variables
- Prefer `[[ ]]` over `[ ]` for conditionals
- Use `die "message"` helper for fatal errors

## Before Submitting Changes

1. Run `make all` (or `make check && make test`)
2. Update `.ai/PLAN.md` if implementation status changed
3. Update `README.md` if CLI surface changed
