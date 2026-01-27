# git-ephemera

Attach ephemeral development files to git commits via git notes.

## Overview

`git ephemera` captures ephemeral development files (PRDs, plans, specs, scratch notes, etc.) and stores them on the relevant git commit using `git notes`. This keeps development artifacts versioned and attributable to commits without polluting your repository tree or branch history.

For example, an AI-assisted development flow often results in accumulated
context files, e.g.:

```
.ai/PRD.md
.ai/PROMPT.md
.ai/PLAN.md
.ai/specs/*.md
```

It's often helpful to save these files for future reference, but typically not desirable to have them in the main source worktree since they become out-of-date quickly, polluting code search results and cluttering agent context. They mainly make sense in the context of the commit that they were used to create.

`git ephemera` solves this by attaching them to commits as git notes.

## Installation

Place `git-ephemera` on your PATH:

```bash
# Symlink (recommended for development)
ln -s /path/to/git-ephemera ~/.local/bin/git-ephemera

# Or copy
cp git-ephemera ~/.local/bin/
```

Git automatically discovers executables named `git-*` as subcommands.

## Quickstart

One-time (recommended) repo setup:

```bash
# 1) Make notes follow rebases/amends (otherwise notes stay on old SHAs)
git config notes.rewriteRef refs/notes/ephemera

# 2) Make normal `git fetch` also fetch the ephemera notes ref
git ephemera setup-remote
git ephemera setup-remote torvalds   # for remote other than "origin"

# 3) Install the post-rewrite hook to track rebase/amend history in notes
#    (Rewrites only your notes, doesn't touch your commits.)
git ephemera install-hooks
```

Typical day-to-day flow:

```bash
git commit -m "..."

# Attach ephemeral files to the commit as a note
git ephemera save .ai/

# Attach ephemera to a commit other than HEAD
git ephemera save .ai/ --commit <rev>

# Share notes with collaborators/other machines
git ephemera push
```

On a fresh clone / other machine:

```bash
git ephemera setup-remote
git fetch     # now also fetches refs/notes/ephemera
git ephemera install-hooks  # Ensure rewrites (rebase, amend) also fix note references

# Restore ephemera
git ephemera restore

# Restore ephemera from a commit other than HEAD
git ephemera restore --commit <rev>
```

## Usage

```
Usage: git ephemera <command> [options]

Commands:
  save <path>...         Archive files and store as a git note
  restore                Extract files from a commit's note
  show                   Display note header/metadata
  list                   List archived filenames without extracting
  push [<remote>]        Push ephemera notes ref (default: origin)
  fetch [<remote>]       Fetch ephemera notes ref (default: origin)
  setup-remote [<remote>]  Configure remote fetch refspec for notes (default: origin)
  install-hooks          Install post-rewrite hook for commit rewrite tracking
  record-rewrite         Record commit rewrite history (used by post-rewrite hook)

Options for 'save':
  --commit <rev>     Target commit (default: HEAD)
  --message <text>   Optional message stored in header
  --strict           Fail if any path doesn't exist

Options for 'restore':
  --commit <rev>     Source commit (default: HEAD)
  --dest <dir>       Extraction directory (default: .)
  --force            Overwrite existing files
  --dry-run          List files without extracting

Options for 'show':
  --commit <rev>     Source commit (default: HEAD)
  --header           Print only the header
  --payload          Print only the base64 payload

Options for 'list':
  --commit <rev>     Source commit (default: HEAD)

Options for 'push':
  <remote>          Remote name (default: origin)

Options for 'fetch':
  <remote>          Remote name (default: origin)

Options for 'setup-remote':
  <remote>          Remote name (default: origin)

Options for 'install-hooks':
  --force           Overwrite existing post-rewrite hook

Options for 'record-rewrite':
  --ref <notes>     Notes ref to update (default: ephemera)

Examples:
  git ephemera save .ai/
  git ephemera save PRD.md PLAN.md
  git ephemera restore --commit abc123
  git ephemera list
  git ephemera push
  git ephemera fetch
  git ephemera setup-remote
  git ephemera install-hooks
```

### Save files to current commit

```bash
git ephemera save .ai/
git ephemera save PRD.md PLAN.md
git ephemera save 'specs/*.md'
```

### Restore files from a commit

```bash
git ephemera restore
git ephemera restore --commit abc123
git ephemera restore --dest /tmp/restored
```

### List archived files

```bash
git ephemera list
git ephemera list --commit abc123
```

### Show note metadata

```bash
git ephemera show
git ephemera show --commit abc123
```

### Full example workflow using the [Ralph Wiggum technique](https://github.com/ClaytonFarr/ralph-playbook)

#### Step 1: Start work on a new feature by creating `.ai/{PRD,PLAN,PROMPT}.md` (or similar)

(typically with the help of an LLM)

#### Step 2: Once those are ready, iterate on the implementation

```
claude < .ai/PROMPT.md  # or in a loop for full ralph wiggum goodness
```

#### Step 3: Commit work and stash ephemeral files in the commit notes

```
git add ...affected source files...  # _not_ the ephemeral files! i.e. nothing under .ai/
git commit -m "..."
# Now stash the .ai/ files on the newly created commit for tracking
git ephemera save .ai/
```

If you need to continue iterating, goto Step 2.

(In a fully automated setup these commands are part of the prompt/plan).

#### Push work and notes and clean up the ephemeral files

```
git push  # push your actual code changes
git ephemera push  # push your ephemera
rm -rf .ai/*  # clean up notes in worktree to make room for the next task
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

Push the `refs/notes/ephemera` ref to a remote (default: `origin`).

### `fetch [<remote>]`

Fetch the `refs/notes/ephemera` ref from a remote (default: `origin`).

### `setup-remote [<remote>]`

Configure a remote so that a regular `git fetch` will also fetch `refs/notes/ephemera` (default: `origin`).

### `install-hooks`

Install the `post-rewrite` git hook to automatically track commit rewrites. This ensures that when you run `git rebase` or `git commit --amend`, the rewritten commits' notes get updated with their commit history.

| Option      | Description                              |
|-------------|------------------------------------------|
| `--force`   | Overwrite existing `post-rewrite` hook  |

The hook calls `git ephemera record-rewrite` internally when rewrites occur. If a `post-rewrite` hook already exists, use `--force` to overwrite it, or manually add the `git ephemera record-rewrite` call to your existing hook.

### `record-rewrite`

Record commit rewrite history in ephemera notes. This is typically called by the `post-rewrite` hook.

| Option            | Description                              |
|-------------------|------------------------------------------|
| `--ref <notes>`   | Notes ref to update (default: `ephemera`) |

This command reads `old_sha new_sha` pairs from stdin (the format provided by Git's `post-rewrite` hook) and updates the note on `new_sha` to include `old_sha` in its `commitHistory` field.

## How It Works

Git notes are attached directly to commits but stored in a separate ref namespace. `git ephemera` uses `refs/notes/ephemera`, keeping your stashed files separate from other git notes.

## Syncing Notes

### Push notes to remote

```bash
git ephemera push        # defaults to origin
# or: git ephemera push <remote>
```

### Fetch notes from remote

```bash
git ephemera fetch       # defaults to origin
# or: git ephemera fetch <remote>
```

### Auto-fetch notes

Configure the remote so that a regular `git fetch` will also fetch `refs/notes/ephemera`:

```bash
git ephemera setup-remote        # defaults to origin
# or: git ephemera setup-remote <remote>
```

## Preserving Notes on Rebase/Amend

Git notes are attached to commit SHAs. When you rebase or amend, git creates new commits with new SHAs, leaving your notes on the old (orphaned) commits.

Configure git to copy notes to rewritten commits:

```bash
git config notes.rewriteRef refs/notes/ephemera
```

This enables note preservation for both `git rebase` and `git commit --amend`.

## Viewing Notes in Git Log

```bash
git log --show-notes=ephemera
```

## Data Format

Notes are stored as text with a YAML-like header followed by a base64-encoded tar.gz payload:

```
ephemeraVersion: 1
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
