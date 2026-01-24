# git-notestash

Attach ephemeral development files to git commits via git notes.

## Overview

`git notestash` captures ephemeral development files (PRDs, plans, specs, scratch notes, etc.) and stores them on the relevant git commit using `git notes`. This keeps development artifacts versioned and attributable to commits without polluting your repository tree or branch history.

For example, an AI-assisted development flow often results in accumulated
context files, e.g.:

```
.ai/PRD.md
.ai/PROMPT.md
.ai/PLAN.md
.ai/specs/*.md
```

It's often helpful to save these files for future reference, but typically not desirable to check them in to source control since they become out-of-date quickly; they mainly make sense in the context of the commit that they were used to create.

`git notestash` solves this by attaching them to commits as git notes.

### Example workflow

#### Step 1: Start work on a new feature by creating `.ai/{PRD,PLAN,PROMPT}.md`

(typically with the help of an LLM)

#### Step 2: Once those are ready, iterate on the implementation

```
claude < .ai/PROMPT.md  # or in a loop for full ralph wiggum goodness
```

#### Step 3: Commit work and stash ephemeral files in the commit notes

```
git add ...affected source files...  # _not_ the ephemeral files!
git commit -m "..."
git notestash save .ai/
```

If you need to continue iterating, goto Step 2.

#### Push notes and clean up the ephemeral files

```
git notestash push
rm -rf .ai/*
```

## Installation

Place `git-notestash` on your PATH:

```bash
# Symlink (recommended for development)
ln -s /path/to/git-notestash ~/.local/bin/git-notestash

# Or copy
cp git-notestash ~/.local/bin/
```

Git automatically discovers executables named `git-*` as subcommands.

## Usage

### Save files to current commit

```bash
git notestash save .ai/
git notestash save PRD.md PLAN.md
git notestash save 'specs/*.md'
```

### Restore files from a commit

```bash
git notestash restore
git notestash restore --commit abc123
git notestash restore --dest /tmp/restored
```

### List archived files

```bash
git notestash list
git notestash list --commit abc123
```

### Show note metadata

```bash
git notestash show
git notestash show --commit abc123
```

## Commands

### `save <path>...`

Archive files and store as a git note.

| Option             | Description                       |
|--------------------|-----------------------------------|
| `--commit <rev>`   | Target commit (default: `HEAD`)   |
| `--message <text>` | Optional message stored in header |
| `--strict`         | Fail if any path doesn't exist    |

### `restore`

Extract files from a commit's note.

| Option           | Description                         |
|------------------|-------------------------------------|
| `--commit <rev>` | Source commit (default: `HEAD`)     |
| `--dest <dir>`   | Extraction directory (default: `.`) |
| `--force`        | Overwrite existing files            |
| `--dry-run`      | List files without extracting       |

### `list`

List archived filenames without extracting.

| Option           | Description                     |
|------------------|---------------------------------|
| `--commit <rev>` | Source commit (default: `HEAD`) |

### `show`

Display note header/metadata.

| Option           | Description                     |
|------------------|---------------------------------|
| `--commit <rev>` | Source commit (default: `HEAD`) |
| `--header`       | Print only the header           |
| `--payload`      | Print only the base64 payload   |

### `push [<remote>]`

Push the `refs/notes/notestash` ref to a remote (default: `origin`).

### `fetch [<remote>]`

Fetch the `refs/notes/notestash` ref from a remote (default: `origin`).

### `setup-remote [<remote>]`

Configure a remote so that a regular `git fetch` will also fetch `refs/notes/notestash` (default: `origin`).

## How It Works

Git notes are attached directly to commits but stored in a separate ref namespace. `git notestash` uses `refs/notes/notestash`, keeping your stashed files separate from other git notes.

## Syncing Notes

### Push notes to remote

```bash
git notestash push        # defaults to origin
# or: git notestash push <remote>
```

### Fetch notes from remote

```bash
git notestash fetch       # defaults to origin
# or: git notestash fetch <remote>
```

### Auto-fetch notes

Configure the remote so that a regular `git fetch` will also fetch `refs/notes/notestash`:

```bash
git notestash setup-remote        # defaults to origin
# or: git notestash setup-remote <remote>
```

## Preserving Notes on Rebase/Amend

Git notes are attached to commit SHAs. When you rebase or amend, git creates new commits with new SHAs, leaving your notes on the old (orphaned) commits.

Configure git to copy notes to rewritten commits:

```bash
git config notes.rewriteRef refs/notes/notestash
```

This enables note preservation for both `git rebase` and `git commit --amend`.

## Viewing Notes in Git Log

```bash
git log --show-notes=notestash
```

## Data Format

Notes are stored as text with a YAML-like header followed by a base64-encoded tar.gz payload:

```
notestashVersion: 1
encoding: tar+gzip+base64
createdAt: 2026-01-24T12:34:56Z
commit: abc123...
paths:
  - PRD.md
  - PLAN.md
---
H4sIAAAAA...
```

## License

MIT
