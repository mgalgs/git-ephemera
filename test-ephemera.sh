#!/bin/bash
#
# Unit tests for git-ephemera
#
# Run from the repo root: ./test-ephemera.sh
#

set -euo pipefail

# Isolate tests from user/system git config
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# Path to the script under test (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPHEMERA="$SCRIPT_DIR/git-ephemera"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    NC=''
fi

# Test temp directory (sandbox root)
TEST_DIR=""

setup() {
    # Create sandbox root with subdirectories for isolation
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/repo" "$TEST_DIR/tmp"
    cd "$TEST_DIR/repo"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
}

teardown() {
    cd /
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "%bPASS%b: %s\n" "$GREEN" "$NC" "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "%bFAIL%b: %s\n" "$RED" "$NC" "$1"
    if [[ -n "${2:-}" ]]; then
        printf "      %s\n" "$2"
    fi
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))

    setup

    # Run test in subshell to isolate failures
    if (set -e; "$test_name"); then
        pass "$test_name"
    else
        fail "$test_name"
    fi

    teardown
}

# =============================================================================
# Tests
# =============================================================================

test_add_single_file() {
    echo "# Test PRD" > PRD.md
    git add PRD.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add PRD.md >/dev/null

    # Verify note exists
    git notes --ref ephemera show HEAD >/dev/null 2>&1
}

test_add_multiple_files() {
    echo "# PRD" > PRD.md
    echo "# Plan" > PLAN.md
    git add PRD.md PLAN.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add PRD.md PLAN.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    # Check both files are in the paths
    echo "$note" | grep -q "PRD.md" && echo "$note" | grep -q "PLAN.md"
}

test_add_directory() {
    mkdir -p .ai
    echo "# PRD" > .ai/PRD.md
    echo "# Plan" > .ai/PLAN.md
    git add .ai
    git commit -m "initial" --quiet

    "$EPHEMERA" add .ai/ >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    echo "$note" | grep -q ".ai/PRD.md" && echo "$note" | grep -q ".ai/PLAN.md"
}

test_add_glob_pattern() {
    echo "# PRD 1" > PRD_one.md
    echo "# PRD 2" > PRD_two.md
    echo "# Other" > OTHER.md
    git add .
    git commit -m "initial" --quiet

    "$EPHEMERA" add 'PRD_*.md' >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    # Should have both PRD files but not OTHER
    echo "$note" | grep -q "PRD_one.md" && \
    echo "$note" | grep -q "PRD_two.md" && \
    ! echo "$note" | grep -q "OTHER.md"
}

test_add_with_message() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add --message "Test add message" test.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    # Message with spaces is properly YAML-escaped with single quotes
    echo "$note" | grep -q "message: 'Test add message'"
}

test_add_to_specific_commit() {
    echo "# First" > first.md
    git add first.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"

    echo "# Second" > second.md
    git add second.md
    git commit -m "second" --quiet

    # Save to the first commit
    "$EPHEMERA" add --commit "$first_sha" first.md >/dev/null

    # Note should be on first commit, not HEAD
    git notes --ref ephemera show "$first_sha" >/dev/null 2>&1 && \
    ! git notes --ref ephemera show HEAD >/dev/null 2>&1
}

test_add_strict_mode_fails_on_missing() {
    echo "# Test" > exists.md
    git add exists.md
    git commit -m "initial" --quiet

    # Should fail in strict mode when file doesn't exist
    if "$EPHEMERA" add --strict nonexistent.md >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_add_nonstrict_ignores_missing() {
    echo "# Test" > exists.md
    git add exists.md
    git commit -m "initial" --quiet

    # Should succeed, saving only the existing file
    "$EPHEMERA" add exists.md nonexistent.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"
    echo "$note" | grep -q "exists.md"
}

test_add_no_paths_fails() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    if "$EPHEMERA" add >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_add_overwrites_existing_note() {
    echo "# Version 1" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null
    local first_note
    first_note="$(git notes --ref ephemera show HEAD)"

    # Wait a second so timestamp differs
    sleep 1

    echo "# Version 2" > test.md
    "$EPHEMERA" add test.md >/dev/null
    local second_note
    second_note="$(git notes --ref ephemera show HEAD)"

    # Notes should be different (different updatedAt at minimum)
    [[ "$first_note" != "$second_note" ]]
}

test_add_rejects_path_traversal() {
    # Path traversal test - verifies that patterns matching files outside
    # the repo are rejected. The pattern '../file.txt' would match files
    # in the parent directory which should not be archived.

    echo "# Safe file" > safe.md
    git add safe.md
    git commit -m "initial" --quiet

    # Create a file outside the repo but inside sandbox (in TEST_DIR/tmp)
    local outside_file
    outside_file="$TEST_DIR/tmp/outside_$$.txt"
    echo "outside data" > "$outside_file"

    # Try to add it using a traversal pattern - this should fail
    # The file exists but is outside the repo root
    local result=0
    if "$EPHEMERA" add "../tmp/outside_$$.txt" >/dev/null 2>&1; then
        result=1  # Should have failed
    fi

    return $result
}

test_note_format_has_required_fields() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    echo "$note" | grep -q "ephemeraVersion: 1" && \
    echo "$note" | grep -q "encoding: tar+gzip+base64" && \
    echo "$note" | grep -q "createdAt:" && \
    echo "$note" | grep -q "commit:" && \
    echo "$note" | grep -q "paths:" && \
    echo "$note" | grep -q "^---$"
}

test_payload_is_valid_base64_targz() {
    echo "# Test content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    # Extract payload (everything after ---)
    local payload
    payload="$(echo "$note" | sed -n '/^---$/,$ p' | tail -n +2 | tr -d '\n')"

    # Decode and list tar contents
    echo "$payload" | base64 -d | tar -tzf - | grep -q "test.md"
}

test_payload_preserves_file_content() {
    local content="This is test content with special chars: <>&'\""
    echo "$content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local note
    note="$(git notes --ref ephemera show HEAD)"

    local payload
    payload="$(echo "$note" | sed -n '/^---$/,$ p' | tail -n +2 | tr -d '\n')"

    # Extract to sandbox temp dir and verify content
    local extract_dir
    extract_dir="$TEST_DIR/tmp/extract_$$"
    mkdir -p "$extract_dir"
    echo "$payload" | base64 -d | tar -xzf - -C "$extract_dir"

    local extracted
    extracted="$(cat "$extract_dir/test.md")"

    [[ "$extracted" == "$content" ]]
}

test_requires_git_repo() {
    # Use sandbox temp dir (outside repo but inside sandbox)
    local tmpdir
    tmpdir="$TEST_DIR/tmp/norepo_$$"
    mkdir -p "$tmpdir"
    cd "$tmpdir"
    if "$EPHEMERA" add test.md >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_help_shows_usage() {
    # Need to be in a git repo for this
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" --help 2>&1 | grep -qi "usage"
}

# =============================================================================
# Restore command tests
# =============================================================================

test_restore_single_file() {
    echo "# Test content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    # Remove the file and restore it
    rm test.md
    "$EPHEMERA" restore >/dev/null

    # File should be restored
    [[ -f test.md ]] && grep -q "Test content" test.md
}

test_restore_multiple_files() {
    echo "# PRD" > PRD.md
    echo "# Plan" > PLAN.md
    git add PRD.md PLAN.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add PRD.md PLAN.md >/dev/null

    rm PRD.md PLAN.md
    "$EPHEMERA" restore >/dev/null

    [[ -f PRD.md ]] && [[ -f PLAN.md ]]
}

test_restore_directory_structure() {
    mkdir -p .ai/specs
    echo "# PRD" > .ai/PRD.md
    echo "# Spec" > .ai/specs/feature.md
    git add .ai
    git commit -m "initial" --quiet

    "$EPHEMERA" add .ai/ >/dev/null

    rm -rf .ai
    "$EPHEMERA" restore >/dev/null

    [[ -f .ai/PRD.md ]] && [[ -f .ai/specs/feature.md ]]
}

test_restore_to_custom_dest() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local restore_dir
    restore_dir="$TEST_DIR/tmp/restore_$$"
    mkdir -p "$restore_dir"
    "$EPHEMERA" restore --dest "$restore_dir" >/dev/null

    [[ -f "$restore_dir/test.md" ]]
}

test_restore_from_specific_commit() {
    echo "# First" > first.md
    git add first.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"
    "$EPHEMERA" add first.md >/dev/null

    echo "# Second" > second.md
    git add second.md
    git commit -m "second" --quiet
    "$EPHEMERA" add second.md >/dev/null

    local restore_dir
    restore_dir="$TEST_DIR/tmp/restore_commit_$$"
    mkdir -p "$restore_dir"
    "$EPHEMERA" restore --commit "$first_sha" --dest "$restore_dir" >/dev/null

    # Should have first.md, not second.md
    [[ -f "$restore_dir/first.md" ]] && [[ ! -f "$restore_dir/second.md" ]]
}

test_restore_fails_on_existing_file() {
    echo "# Original" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    # File already exists, should fail without --force
    if "$EPHEMERA" restore >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_restore_force_overwrites() {
    echo "# Original" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    # Modify the file
    echo "# Modified" > test.md

    # Restore with --force should overwrite
    "$EPHEMERA" restore --force >/dev/null

    grep -q "Original" test.md
}

test_restore_dry_run() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null
    rm test.md

    local output
    output="$("$EPHEMERA" restore --dry-run 2>&1)"

    # Dry run should list files without restoring
    echo "$output" | grep -q "test.md" && [[ ! -f test.md ]]
}

test_restore_no_note_fails() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    # No add was done, restore should fail
    if "$EPHEMERA" restore >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_restore_preserves_file_content() {
    local content="Multi-line content
with special chars: <>&'\"
and tabs:	here"
    echo "$content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null
    rm test.md
    "$EPHEMERA" restore >/dev/null

    local restored
    restored="$(cat test.md)"
    [[ "$restored" == "$content" ]]
}

# =============================================================================
# Show/List command tests
# =============================================================================

test_show_default_outputs_header() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local output
    output="$("$EPHEMERA" show 2>&1)"

    echo "$output" | grep -q "ephemeraVersion: 1" && \
    echo "$output" | grep -q "encoding: tar+gzip+base64" && \
    echo "$output" | grep -q "paths:" && \
    ! echo "$output" | grep -q "^---$"
}

test_show_payload_outputs_only_payload() {
    echo "# Test content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local payload
    payload="$("$EPHEMERA" show --payload)"

    # Should be decodable and contain our file
    ! echo "$payload" | grep -q "ephemeraVersion" && \
    echo "$payload" | base64 -d | tar -tzf - | grep -q "test.md"
}

test_list_outputs_filenames() {
    mkdir -p .ai
    echo "# PRD" > .ai/PRD.md
    git add .ai/PRD.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add .ai/ >/dev/null

    local output
    output="$("$EPHEMERA" list)"

    echo "$output" | grep -q "\.ai/PRD.md"
}

# =============================================================================
# Remote/clone integration tests
# =============================================================================

test_fetch_notes_from_remote() {
    # Create origin repo under sandbox tmp
    local origin_dir clone_dir
    origin_dir="$TEST_DIR/tmp/origin_$$"
    clone_dir="$TEST_DIR/tmp/clone_$$"
    mkdir -p "$origin_dir" "$clone_dir"

    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    # Add remote and push initial content
    git remote add origin "$origin_dir"

    echo "# PRD content" > PRD.md
    git add PRD.md
    git commit -m "add PRD" --quiet
    git push origin master --quiet 2>/dev/null

    # Add ephemera and push notes to origin
    "$EPHEMERA" add PRD.md >/dev/null
    "$EPHEMERA" push >/dev/null 2>&1

    # Clone to a new location (under sandbox)
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"

    # Notes should NOT be there yet (git clone doesn't fetch notes by default)
    if "$EPHEMERA" restore --dry-run >/dev/null 2>&1; then
        return 1  # Notes shouldn't be available yet
    fi

    # Fetch the notes
    "$EPHEMERA" fetch >/dev/null 2>&1

    # Now restore should work
    "$EPHEMERA" restore >/dev/null

    [[ -f PRD.md ]] && grep -q "PRD content" PRD.md
}

test_notes_available_after_clone_with_fetch_config() {
    # Create origin repo under sandbox tmp
    local origin_dir clone_dir restore_dir
    origin_dir="$TEST_DIR/tmp/origin2_$$"
    clone_dir="$TEST_DIR/tmp/clone2_$$"
    restore_dir="$TEST_DIR/tmp/restore2_$$"
    mkdir -p "$origin_dir" "$clone_dir" "$restore_dir"

    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    git remote add origin "$origin_dir"

    echo "# Plan content" > PLAN.md
    git add PLAN.md
    git commit -m "add PLAN" --quiet
    git push origin master --quiet 2>/dev/null

    "$EPHEMERA" add PLAN.md >/dev/null
    "$EPHEMERA" push >/dev/null 2>&1

    # Clone and configure auto-fetch for notes (under sandbox)
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"

    # Configure fetch refspec for notes
    "$EPHEMERA" setup-remote origin

    # Now fetch should bring in notes
    git fetch origin --quiet 2>/dev/null

    # Restore should work
    "$EPHEMERA" restore --dest "$restore_dir" >/dev/null

    [[ -f "$restore_dir/PLAN.md" ]] && grep -q "Plan content" "$restore_dir/PLAN.md"
}

test_multiple_commits_notes_sync() {
    # Create origin repo under sandbox tmp
    local origin_dir clone_dir first_restore second_restore
    origin_dir="$TEST_DIR/tmp/origin3_$$"
    clone_dir="$TEST_DIR/tmp/clone3_$$"
    first_restore="$TEST_DIR/tmp/first_restore_$$"
    second_restore="$TEST_DIR/tmp/second_restore_$$"
    mkdir -p "$origin_dir" "$clone_dir" "$first_restore" "$second_restore"

    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    git remote add origin "$origin_dir"

    # First commit with ephemera
    echo "# First PRD" > PRD.md
    git add PRD.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"
    "$EPHEMERA" add PRD.md >/dev/null

    # Second commit with different ephemera
    echo "# Second PRD" > PRD.md
    git add PRD.md
    git commit -m "second" --quiet
    "$EPHEMERA" add PRD.md >/dev/null

    # Push everything
    git push origin master --quiet 2>/dev/null
    "$EPHEMERA" push origin >/dev/null 2>&1

    # Clone and fetch notes (under sandbox)
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"
    "$EPHEMERA" fetch origin >/dev/null 2>&1

    # Restore from first commit
    "$EPHEMERA" restore --commit "$first_sha" --dest "$first_restore" >/dev/null

    # Restore from second commit (HEAD)
    "$EPHEMERA" restore --dest "$second_restore" >/dev/null

    grep -q "First PRD" "$first_restore/PRD.md" && \
    grep -q "Second PRD" "$second_restore/PRD.md"
}

# =============================================================================
# record-rewrite tests
# =============================================================================

test_record_rewrite_updates_commit_history() {
    # Create initial commit with ephemera
    echo "# Initial" > test.md
    git add test.md
    git commit -m "initial" --quiet
    local old_sha
    old_sha="$(git rev-parse HEAD)"

    "$EPHEMERA" add test.md >/dev/null

    # Simulate a rewrite (amend)
    echo "# Updated" >> test.md
    git add test.md
    git commit --amend --no-edit --quiet
    local new_sha
    new_sha="$(git rev-parse HEAD)"

    # Manually move note (simulating git notes rewrite behavior)
    local note_content
    note_content="$(git notes --ref ephemera show "$old_sha")"
    printf '%s\n' "$note_content" | git notes --ref ephemera add -F - "$new_sha"
    git notes --ref ephemera remove "$old_sha" 2>/dev/null || true

    # Run record-rewrite
    echo "$old_sha $new_sha" | "$EPHEMERA" record-rewrite >/dev/null

    # Verify commitHistory is in the note
    local updated_note
    updated_note="$("$EPHEMERA" show --commit "$new_sha" 2>&1)"

    echo "$updated_note" | grep -q "^commitHistory:" && \
    echo "$updated_note" | grep -qF "$old_sha"
}

test_record_rewrite_idempotent() {
    # Create initial commit with ephemera
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet
    local old_sha
    old_sha="$(git rev-parse HEAD)"

    "$EPHEMERA" add test.md >/dev/null

    # Simulate a rewrite
    git commit --amend --no-edit --quiet
    local new_sha
    new_sha="$(git rev-parse HEAD)"

    # Move note manually
    local note_content
    note_content="$(git notes --ref ephemera show "$old_sha")"
    printf '%s\n' "$note_content" | git notes --ref ephemera add -F - "$new_sha"
    git notes --ref ephemera remove "$old_sha" 2>/dev/null || true

    # Run record-rewrite twice
    echo "$old_sha $new_sha" | "$EPHEMERA" record-rewrite >/dev/null
    echo "$old_sha $new_sha" | "$EPHEMERA" record-rewrite >/dev/null

    # Check that old_sha appears only once in commitHistory
    local updated_note
    updated_note="$("$EPHEMERA" show --commit "$new_sha" 2>&1)"

    # Count occurrences of old_sha in commitHistory section
    local count
    count="$(echo "$updated_note" | grep -cF "$old_sha")" || count=0

    [[ $count -eq 1 ]]
}


test_record_rewrite_handles_old_notes_without_history() {
    # Create initial commit
    echo "# Old format" > test.md
    git add test.md
    git commit -m "initial" --quiet
    local original_sha
    original_sha="$(git rev-parse HEAD)"

    # Save a note
    "$EPHEMERA" add test.md >/dev/null

    # Get the note content and remove commitHistory to simulate old format
    local note_content
    note_content="$(git notes --ref ephemera show "$original_sha")"
    local old_format_note
    old_format_note="$(echo "$note_content" | sed '/^commitHistory:/d')"

    # Force-add old format note back
    printf '%s\n' "$old_format_note" | git notes --ref ephemera add -f -F - "$original_sha"

    # Verify old format note doesn't have commitHistory
    local check_note
    check_note="$(git notes --ref ephemera show "$original_sha")"
    if echo "$check_note" | grep -q "^commitHistory:"; then
        return 1  # commitHistory should not exist
    fi

    # Simulate a rewrite - create a "new" commit (normally from amend/rebase)
    # Change the message to ensure a new SHA
    git commit --amend -m "amended" --quiet
    local rewritten_sha
    rewritten_sha="$(git rev-parse HEAD)"

    # Manually copy the old-format note to the rewritten commit
    # (simulating what git's notes.rewriteRef would do)
    printf '%s\n' "$old_format_note" | git notes --ref ephemera add -f -F - "$rewritten_sha"

    # Run record-rewrite with original_sha -> rewritten_sha
    echo "$original_sha $rewritten_sha" | "$EPHEMERA" record-rewrite >/dev/null

    # Verify commitHistory is now present
    local updated_note
    updated_note="$("$EPHEMERA" show --commit "$rewritten_sha" 2>&1)"

    echo "$updated_note" | grep -q "^commitHistory:" && \
    echo "$updated_note" | grep -qF "$original_sha"
}
test_record_rewrite_multiple_commits() {
    # Create first commit with ephemera
    echo "# First" > first.md
    git add first.md
    git commit -m "first" --quiet
    local first_old
    first_old="$(git rev-parse HEAD)"
    "$EPHEMERA" add first.md >/dev/null

    # Create second commit with ephemera
    echo "# Second" > second.md
    git add second.md
    git commit -m "second" --quiet
    local second_old
    second_old="$(git rev-parse HEAD)"
    "$EPHEMERA" add second.md >/dev/null

    # Amend both - first amend second commit, then simulate first being rewritten
    git commit --amend --no-edit --quiet
    local second_new
    second_new="$(git rev-parse HEAD)"
    # Reset to modify first commit
    git reset --hard HEAD~1 --quiet
    git commit --amend --no-edit --quiet
    local first_new
    first_new="$(git rev-parse HEAD)"

    # Move notes manually with force
    local note_content
    note_content="$(git notes --ref ephemera show "$first_old")"
    printf '%s\n' "$note_content" | git notes --ref ephemera add -f -F - "$first_new"
    git notes --ref ephemera remove "$first_old" 2>/dev/null || true

    note_content="$(git notes --ref ephemera show "$second_old")"
    printf '%s\n' "$note_content" | git notes --ref ephemera add -f -F - "$second_new"
    git notes --ref ephemera remove "$second_old" 2>/dev/null || true

    # Run record-rewrite for both pairs
    echo "$first_old $first_new" | "$EPHEMERA" record-rewrite >/dev/null
    echo "$second_old $second_new" | "$EPHEMERA" record-rewrite >/dev/null

    # Verify both notes have commitHistory
    local first_note
    first_note="$("$EPHEMERA" show --commit "$first_new" 2>&1)"
    local second_note
    second_note="$("$EPHEMERA" show --commit "$second_new" 2>&1)"

    echo "$first_note" | grep -qF "$first_old" && \
    echo "$second_note" | grep -qF "$second_old"
}

# =============================================================================
# install-hooks tests
# =============================================================================

test_install_hooks_creates_post_rewrite_hook() {
    "$EPHEMERA" install-hooks >/dev/null

    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    local hook_file="$git_dir/hooks/post-rewrite"

    [[ -f "$hook_file" ]] && \
    grep -q "git ephemera record-rewrite" "$hook_file"
}

test_install_hooks_fails_on_second_run() {
    # First run should succeed
    "$EPHEMERA" install-hooks >/dev/null

    # Second run without --force should fail
    ! "$EPHEMERA" install-hooks >/dev/null 2>&1
}

test_install_hooks_fails_with_existing_hook() {
    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    local hook_file="$git_dir/hooks/post-rewrite"

    # Create an existing hook without our marker
    echo "# Custom hook" > "$hook_file"

    # Should fail
    if "$EPHEMERA" install-hooks >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_install_hooks_force_overwrites() {
    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    local hook_file="$git_dir/hooks/post-rewrite"

    # Create an existing hook without our marker
    echo "# Custom hook" > "$hook_file"

    # Should succeed with --force
    "$EPHEMERA" install-hooks --force >/dev/null

    # Should now have our invocation
    grep -q "git ephemera record-rewrite" "$hook_file" && \
    ! grep -q "# Custom hook" "$hook_file"
}

test_new_add_has_commit_history_field() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$EPHEMERA" add test.md >/dev/null

    local note
    note="$("$EPHEMERA" show 2>&1)"

    echo "$note" | grep -q "^commitHistory: \[\]$"
}

test_add_merge_preserves_created_at_and_commit_history() {
    # Create initial commit with ephemera
    echo "# Initial" > test.md
    git add test.md
    git commit -m "initial" --quiet
    local old_sha
    old_sha="$(git rev-parse HEAD)"

    "$EPHEMERA" add test.md >/dev/null

    # Simulate a rewrite to introduce commitHistory on the note
    echo "# Updated" >> test.md
    git add test.md
    git commit --amend --no-edit --quiet
    local new_sha
    new_sha="$(git rev-parse HEAD)"

    # Manually move note (simulating git notes rewrite behavior)
    local note_content
    note_content="$(git notes --ref ephemera show "$old_sha")"
    printf '%s\n' "$note_content" | git notes --ref ephemera add -f -F - "$new_sha"
    git notes --ref ephemera remove "$old_sha" 2>/dev/null || true

    # Record rewrite history so commitHistory is present
    echo "$old_sha $new_sha" | "$EPHEMERA" record-rewrite >/dev/null

    # Capture createdAt and commitHistory before a merge-add
    local before
    before="$("$EPHEMERA" show --commit "$new_sha")"

    local created_at_before
    created_at_before="$(echo "$before" | sed -n 's/^createdAt: //p' | head -n 1)"
    [[ -n "$created_at_before" ]]

    echo "$before" | grep -q "^commitHistory: \[" && echo "$before" | grep -qF "$old_sha"

    # Merge-add: add another file to existing note
    echo "# Another" > another.md
    "$EPHEMERA" add another.md --commit "$new_sha" >/dev/null

    local after
    after="$("$EPHEMERA" show --commit "$new_sha")"

    # createdAt should be preserved
    local created_at_after
    created_at_after="$(echo "$after" | sed -n 's/^createdAt: //p' | head -n 1)"
    [[ "$created_at_after" == "$created_at_before" ]]

    # commitHistory should still contain the old sha
    echo "$after" | grep -q "^commitHistory: \[" && echo "$after" | grep -qF "$old_sha"

    # updatedAt should exist after merge
    echo "$after" | grep -q "^updatedAt: "
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "Running git-ephemera tests..."
    echo ""

    # Verify script exists
    if [[ ! -x "$EPHEMERA" ]]; then
        echo "Error: $EPHEMERA not found or not executable"
        exit 1
    fi

    run_test test_add_single_file
    run_test test_add_multiple_files
    run_test test_add_directory
    run_test test_add_glob_pattern
    run_test test_add_with_message
    run_test test_add_to_specific_commit
    run_test test_add_strict_mode_fails_on_missing
    run_test test_add_nonstrict_ignores_missing
    run_test test_add_no_paths_fails
    run_test test_add_overwrites_existing_note
    run_test test_add_rejects_path_traversal
    run_test test_note_format_has_required_fields
    run_test test_payload_is_valid_base64_targz
    run_test test_payload_preserves_file_content
    run_test test_requires_git_repo
    run_test test_help_shows_usage

    # Restore tests
    run_test test_restore_single_file
    run_test test_restore_multiple_files
    run_test test_restore_directory_structure
    run_test test_restore_to_custom_dest
    run_test test_restore_from_specific_commit
    run_test test_restore_fails_on_existing_file
    run_test test_restore_force_overwrites
    run_test test_restore_dry_run
    run_test test_restore_no_note_fails
    run_test test_restore_preserves_file_content

    # Show/List tests
    run_test test_show_default_outputs_header
    run_test test_show_payload_outputs_only_payload
    run_test test_list_outputs_filenames

    # Remote/clone integration tests
    run_test test_fetch_notes_from_remote
    run_test test_notes_available_after_clone_with_fetch_config
    run_test test_multiple_commits_notes_sync

    # record-rewrite tests
    run_test test_record_rewrite_updates_commit_history
    run_test test_record_rewrite_idempotent
    run_test test_record_rewrite_handles_old_notes_without_history
    run_test test_record_rewrite_multiple_commits

    # install-hooks tests
    run_test test_install_hooks_creates_post_rewrite_hook
    run_test test_install_hooks_fails_on_second_run
    run_test test_install_hooks_fails_with_existing_hook
    run_test test_install_hooks_force_overwrites
    run_test test_new_add_has_commit_history_field
    run_test test_add_merge_preserves_created_at_and_commit_history

    echo ""
    echo "========================================="
    echo "Tests run:    $TESTS_RUN"
    printf "Tests passed: %b%d%b\n" "$GREEN" "$TESTS_PASSED" "$NC"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf "Tests failed: %b%d%b\n" "$RED" "$TESTS_FAILED" "$NC"
        exit 1
    else
        echo "Tests failed: $TESTS_FAILED"
        printf "%bAll tests passed!%b\n" "$GREEN" "$NC"
    fi
}

main "$@"
