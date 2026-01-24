# Development Guide for Agents

This document provides instructions for AI agents working on the git-notestash codebase.

## Project Overview

`git-notestash` is a Bash CLI tool that attaches ephemeral development files to git commits via git notes. See `README.md` for user-facing documentation.

## Codebase Map (high-signal files)

- `git-notestash`: the CLI implementation (Bash). Command dispatch lives in `main()`.
- `test-notestash.sh`: unit + integration tests (creates temp repos, includes remote/clone tests).
- `Makefile`: `make check`, `make test`, `make all`.

## Notes Ref + Remote Sync

- Notes are stored under the git notes ref **`refs/notes/notestash`** (see `git-notestash`, constant `NOTESTASH_NOTES_REF`).
- Convenience subcommands exist to reduce sync friction:
  - `git notestash push [<remote>]` (default `origin`) pushes `refs/notes/notestash`.
  - `git notestash fetch [<remote>]` (default `origin`) fetches `refs/notes/notestash` into the local `refs/notes/notestash`.
    - Behavior is fast-forward only; divergence will fail.
  - `git notestash setup-remote [<remote>]` (default `origin`) adds the refspec `+refs/notes/notestash:refs/notes/notestash` to `remote.<name>.fetch` so normal `git fetch` brings notes along.

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

## Agent Maintenance (keep this file fresh)

When you learn something that would save future agents exploration time, update this file in the same PR/change-set.

Minimum rule (follow every time):
- If you touched command dispatch, notes refs, remote syncing, tests, or build tooling, add a short bullet to the most relevant section above (or create a new short section).

Guidelines:
- Prefer **actionable facts** (file names, commands, constants, where to modify behavior).
- Keep it short; remove stale info rather than growing endlessly.

## Before Submitting Changes

1. Run `make all` (or `make check && make test`)
3. Update `README.md` if CLI surface changed
4. Update `CLAUDE.md` with any new high-signal navigation/maintenance lessons
