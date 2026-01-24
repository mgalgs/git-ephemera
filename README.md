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

Example workflow:

```
# Step 1: Start work on a new feature by creating .ai/{PRD,PLAN,PROMPT}.md with the help of an LLM

# Step 2: Once those are ready, iterate on the implementation:
claude < .ai/PROMPT.md  # or in a loop for full ralph wiggum goodness

# Step 3: Commit work and stash ephemeral files in the commit notes
git add ...affected files...
# (Remember: don't add anything from .ai/ to git!)
git commit -m "..."
git notestash save .ai/

# Continue iterating (goto Step 2). When implementation is finally complete, clean up the ephemeral files (which are now safely stashed in the commits that they were used to generate)
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

## How It Works

Git notes are attached directly to commits but stored in a separate ref namespace. `git notestash` uses `refs/notes/notestash`, keeping your stashed files separate from other git notes.

## Syncing Notes

### Push notes to remote

```bash
git push origin refs/notes/notestash
```

### Fetch notes from remote

```bash
git fetch origin refs/notes/notestash:refs/notes/notestash
```

### Auto-fetch notes

```bash
git config --add remote.origin.fetch '+refs/notes/notestash:refs/notes/notestash'
```

## Preserving Notes on Rebase

Configure git to rewrite notes when rebasing:

```bash
git config notes.rewrite.rebase true
git config notes.rewriteRef refs/notes/notestash
```

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
