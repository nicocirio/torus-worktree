#!/usr/bin/env bats

load test_helper

load_worktree_dates() {
  eval "$(sed -n '/^worktree_created_epoch() {/,/^}/p' "$WT")"
  eval "$(sed -n '/^relative_time() {/,/^}/p' "$WT")"
  eval "$(sed -n '/^worktree_dates() {/,/^}/p' "$WT")"
}

@test "worktree_dates: missing directory returns placeholders successfully" {
  load_worktree_dates
  run worktree_dates "$TEST_ROOT/missing"
  [ "$status" -eq 0 ]
  [ "$output" = $'—\t—' ]
}

@test "worktree_dates: unavailable commit history still returns a creation date" {
  load_worktree_dates
  mkdir "$TEST_ROOT/not-a-repo"
  run worktree_dates "$TEST_ROOT/not-a-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == "just now"$'\t' ]]
}

@test "worktree_dates: zero birth time falls back to mtime" {
  load_worktree_dates
  stat() {
    case "$2" in
      %B) echo 0 ;;
      %m) echo 1000000000 ;;
      *) return 1 ;;
    esac
  }
  run worktree_dates "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == "$(relative_time 1000000000)"$'\t'* ]]
}
