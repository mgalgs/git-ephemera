#!/bin/bash
#
# Unit tests for git-notestash
#
# Run from the repo root: ./test-notestash.sh
#

set -euo pipefail

# Path to the script under test (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTESTASH="$SCRIPT_DIR/git-notestash"

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

# Test temp directory
TEST_DIR=""

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
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
    printf "%sPASS%s: %s\n" "$GREEN" "$NC" "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "%sFAIL%s: %s\n" "$RED" "$NC" "$1"
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

test_save_single_file() {
    echo "# Test PRD" > PRD.md
    git add PRD.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save PRD.md >/dev/null

    # Verify note exists
    git notes --ref notestash show HEAD >/dev/null 2>&1
}

test_save_multiple_files() {
    echo "# PRD" > PRD.md
    echo "# Plan" > PLAN.md
    git add PRD.md PLAN.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save PRD.md PLAN.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    # Check both files are in the paths
    echo "$note" | grep -q "PRD.md" && echo "$note" | grep -q "PLAN.md"
}

test_save_directory() {
    mkdir -p .ai
    echo "# PRD" > .ai/PRD.md
    echo "# Plan" > .ai/PLAN.md
    git add .ai
    git commit -m "initial" --quiet

    "$NOTESTASH" save .ai/ >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    echo "$note" | grep -q ".ai/PRD.md" && echo "$note" | grep -q ".ai/PLAN.md"
}

test_save_glob_pattern() {
    echo "# PRD 1" > PRD_one.md
    echo "# PRD 2" > PRD_two.md
    echo "# Other" > OTHER.md
    git add .
    git commit -m "initial" --quiet

    "$NOTESTASH" save 'PRD_*.md' >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    # Should have both PRD files but not OTHER
    echo "$note" | grep -q "PRD_one.md" && \
    echo "$note" | grep -q "PRD_two.md" && \
    ! echo "$note" | grep -q "OTHER.md"
}

test_save_with_message() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save --message "Test save message" test.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    echo "$note" | grep -q "message: Test save message"
}

test_save_to_specific_commit() {
    echo "# First" > first.md
    git add first.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"

    echo "# Second" > second.md
    git add second.md
    git commit -m "second" --quiet

    # Save to the first commit
    "$NOTESTASH" save --commit "$first_sha" first.md >/dev/null

    # Note should be on first commit, not HEAD
    git notes --ref notestash show "$first_sha" >/dev/null 2>&1 && \
    ! git notes --ref notestash show HEAD >/dev/null 2>&1
}

test_save_strict_mode_fails_on_missing() {
    echo "# Test" > exists.md
    git add exists.md
    git commit -m "initial" --quiet

    # Should fail in strict mode when file doesn't exist
    if "$NOTESTASH" save --strict nonexistent.md >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_save_nonstrict_ignores_missing() {
    echo "# Test" > exists.md
    git add exists.md
    git commit -m "initial" --quiet

    # Should succeed, saving only the existing file
    "$NOTESTASH" save exists.md nonexistent.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"
    echo "$note" | grep -q "exists.md"
}

test_save_no_paths_fails() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    if "$NOTESTASH" save >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_save_overwrites_existing_note() {
    echo "# Version 1" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null
    local first_note
    first_note="$(git notes --ref notestash show HEAD)"

    # Wait a second so timestamp differs
    sleep 1

    echo "# Version 2" > test.md
    "$NOTESTASH" save test.md >/dev/null
    local second_note
    second_note="$(git notes --ref notestash show HEAD)"

    # Notes should be different (different createdAt at minimum)
    [[ "$first_note" != "$second_note" ]]
}

test_note_format_has_required_fields() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    echo "$note" | grep -q "notestashVersion: 1" && \
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

    "$NOTESTASH" save test.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

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

    "$NOTESTASH" save test.md >/dev/null

    local note
    note="$(git notes --ref notestash show HEAD)"

    local payload
    payload="$(echo "$note" | sed -n '/^---$/,$ p' | tail -n +2 | tr -d '\n')"

    # Extract to temp location and verify content
    local extract_dir
    extract_dir="$(mktemp -d)"
    echo "$payload" | base64 -d | tar -xzf - -C "$extract_dir"

    local extracted
    extracted="$(cat "$extract_dir/test.md")"
    rm -rf "$extract_dir"

    [[ "$extracted" == "$content" ]]
}

test_requires_git_repo() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    if "$NOTESTASH" save test.md >/dev/null 2>&1; then
        rm -rf "$tmpdir"
        return 1  # Should have failed
    fi
    rm -rf "$tmpdir"
    return 0
}

test_help_shows_usage() {
    # Need to be in a git repo for this
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" --help 2>&1 | grep -qi "usage"
}

# =============================================================================
# Restore command tests
# =============================================================================

test_restore_single_file() {
    echo "# Test content" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null

    # Remove the file and restore it
    rm test.md
    "$NOTESTASH" restore >/dev/null

    # File should be restored
    [[ -f test.md ]] && grep -q "Test content" test.md
}

test_restore_multiple_files() {
    echo "# PRD" > PRD.md
    echo "# Plan" > PLAN.md
    git add PRD.md PLAN.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save PRD.md PLAN.md >/dev/null

    rm PRD.md PLAN.md
    "$NOTESTASH" restore >/dev/null

    [[ -f PRD.md ]] && [[ -f PLAN.md ]]
}

test_restore_directory_structure() {
    mkdir -p .ai/specs
    echo "# PRD" > .ai/PRD.md
    echo "# Spec" > .ai/specs/feature.md
    git add .ai
    git commit -m "initial" --quiet

    "$NOTESTASH" save .ai/ >/dev/null

    rm -rf .ai
    "$NOTESTASH" restore >/dev/null

    [[ -f .ai/PRD.md ]] && [[ -f .ai/specs/feature.md ]]
}

test_restore_to_custom_dest() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null

    local restore_dir
    restore_dir="$(mktemp -d)"
    "$NOTESTASH" restore --dest "$restore_dir" >/dev/null

    [[ -f "$restore_dir/test.md" ]]
    rm -rf "$restore_dir"
}

test_restore_from_specific_commit() {
    echo "# First" > first.md
    git add first.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"
    "$NOTESTASH" save first.md >/dev/null

    echo "# Second" > second.md
    git add second.md
    git commit -m "second" --quiet
    "$NOTESTASH" save second.md >/dev/null

    local restore_dir
    restore_dir="$(mktemp -d)"
    "$NOTESTASH" restore --commit "$first_sha" --dest "$restore_dir" >/dev/null

    # Should have first.md, not second.md
    [[ -f "$restore_dir/first.md" ]] && [[ ! -f "$restore_dir/second.md" ]]
    rm -rf "$restore_dir"
}

test_restore_fails_on_existing_file() {
    echo "# Original" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null

    # File already exists, should fail without --force
    if "$NOTESTASH" restore >/dev/null 2>&1; then
        return 1  # Should have failed
    fi
    return 0
}

test_restore_force_overwrites() {
    echo "# Original" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null

    # Modify the file
    echo "# Modified" > test.md

    # Restore with --force should overwrite
    "$NOTESTASH" restore --force >/dev/null

    grep -q "Original" test.md
}

test_restore_dry_run() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    "$NOTESTASH" save test.md >/dev/null
    rm test.md

    local output
    output="$("$NOTESTASH" restore --dry-run 2>&1)"

    # Dry run should list files without restoring
    echo "$output" | grep -q "test.md" && [[ ! -f test.md ]]
}

test_restore_no_note_fails() {
    echo "# Test" > test.md
    git add test.md
    git commit -m "initial" --quiet

    # No save was done, restore should fail
    if "$NOTESTASH" restore >/dev/null 2>&1; then
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

    "$NOTESTASH" save test.md >/dev/null
    rm test.md
    "$NOTESTASH" restore >/dev/null

    local restored
    restored="$(cat test.md)"
    [[ "$restored" == "$content" ]]
}

# =============================================================================
# Remote/clone integration tests
# =============================================================================

test_fetch_notes_from_remote() {
    # Create origin repo with a notestash
    local origin_dir
    origin_dir="$(mktemp -d)"
    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    # Add remote and push initial content
    git remote add origin "$origin_dir"

    echo "# PRD content" > PRD.md
    git add PRD.md
    git commit -m "add PRD" --quiet
    git push origin master --quiet 2>/dev/null

    # Save notestash and push notes to origin
    "$NOTESTASH" save PRD.md >/dev/null
    git push origin refs/notes/notestash --quiet 2>/dev/null

    # Clone to a new location
    local clone_dir
    clone_dir="$(mktemp -d)"
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"

    # Notes should NOT be there yet (git clone doesn't fetch notes by default)
    if "$NOTESTASH" restore --dry-run >/dev/null 2>&1; then
        rm -rf "$origin_dir" "$clone_dir"
        return 1  # Notes shouldn't be available yet
    fi

    # Fetch the notes
    git fetch origin refs/notes/notestash:refs/notes/notestash --quiet 2>/dev/null

    # Now restore should work
    "$NOTESTASH" restore >/dev/null

    local result=0
    if [[ ! -f PRD.md ]] || ! grep -q "PRD content" PRD.md; then
        result=1
    fi

    rm -rf "$origin_dir" "$clone_dir"
    return $result
}

test_notes_available_after_clone_with_fetch_config() {
    # Create origin repo
    local origin_dir
    origin_dir="$(mktemp -d)"
    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    git remote add origin "$origin_dir"

    echo "# Plan content" > PLAN.md
    git add PLAN.md
    git commit -m "add PLAN" --quiet
    git push origin master --quiet 2>/dev/null

    "$NOTESTASH" save PLAN.md >/dev/null
    git push origin refs/notes/notestash --quiet 2>/dev/null

    # Clone and configure auto-fetch for notes
    local clone_dir
    clone_dir="$(mktemp -d)"
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"

    # Configure fetch refspec for notes
    git config --add remote.origin.fetch '+refs/notes/notestash:refs/notes/notestash'

    # Now fetch should bring in notes
    git fetch origin --quiet 2>/dev/null

    # Restore should work
    local restore_dir
    restore_dir="$(mktemp -d)"
    "$NOTESTASH" restore --dest "$restore_dir" >/dev/null

    local result=0
    if [[ ! -f "$restore_dir/PLAN.md" ]] || ! grep -q "Plan content" "$restore_dir/PLAN.md"; then
        result=1
    fi

    rm -rf "$origin_dir" "$clone_dir" "$restore_dir"
    return $result
}

test_multiple_commits_notes_sync() {
    # Create origin repo
    local origin_dir
    origin_dir="$(mktemp -d)"
    git clone --bare . "$origin_dir" --quiet 2>/dev/null

    git remote add origin "$origin_dir"

    # First commit with notestash
    echo "# First PRD" > PRD.md
    git add PRD.md
    git commit -m "first" --quiet
    local first_sha
    first_sha="$(git rev-parse HEAD)"
    "$NOTESTASH" save PRD.md >/dev/null

    # Second commit with different notestash
    echo "# Second PRD" > PRD.md
    git add PRD.md
    git commit -m "second" --quiet
    "$NOTESTASH" save PRD.md >/dev/null

    # Push everything
    git push origin master --quiet 2>/dev/null
    git push origin refs/notes/notestash --quiet 2>/dev/null

    # Clone and fetch notes
    local clone_dir
    clone_dir="$(mktemp -d)"
    git clone "$origin_dir" "$clone_dir" --quiet 2>/dev/null
    cd "$clone_dir"
    git fetch origin refs/notes/notestash:refs/notes/notestash --quiet 2>/dev/null

    # Restore from first commit
    local first_restore
    first_restore="$(mktemp -d)"
    "$NOTESTASH" restore --commit "$first_sha" --dest "$first_restore" >/dev/null

    # Restore from second commit (HEAD)
    local second_restore
    second_restore="$(mktemp -d)"
    "$NOTESTASH" restore --dest "$second_restore" >/dev/null

    local result=0
    if ! grep -q "First PRD" "$first_restore/PRD.md"; then
        result=1
    fi
    if ! grep -q "Second PRD" "$second_restore/PRD.md"; then
        result=1
    fi

    rm -rf "$origin_dir" "$clone_dir" "$first_restore" "$second_restore"
    return $result
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "Running git-notestash tests..."
    echo ""

    # Verify script exists
    if [[ ! -x "$NOTESTASH" ]]; then
        echo "Error: $NOTESTASH not found or not executable"
        exit 1
    fi

    run_test test_save_single_file
    run_test test_save_multiple_files
    run_test test_save_directory
    run_test test_save_glob_pattern
    run_test test_save_with_message
    run_test test_save_to_specific_commit
    run_test test_save_strict_mode_fails_on_missing
    run_test test_save_nonstrict_ignores_missing
    run_test test_save_no_paths_fails
    run_test test_save_overwrites_existing_note
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

    # Remote/clone integration tests
    run_test test_fetch_notes_from_remote
    run_test test_notes_available_after_clone_with_fetch_config
    run_test test_multiple_commits_notes_sync

    echo ""
    echo "========================================="
    echo "Tests run:    $TESTS_RUN"
    printf "Tests passed: %s%d%s\n" "$GREEN" "$TESTS_PASSED" "$NC"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf "Tests failed: %s%d%s\n" "$RED" "$TESTS_FAILED" "$NC"
        exit 1
    else
        echo "Tests failed: $TESTS_FAILED"
        printf "%sAll tests passed!%s\n" "$GREEN" "$NC"
    fi
}

main "$@"
