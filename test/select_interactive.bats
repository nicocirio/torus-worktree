#!/usr/bin/env bats
#
# Drives the `remove --select` checkbox picker through a real pty (via
# expect — bats itself has no tty). Covers the exact regression we hit:
# a function whose last statement was a bare `for ... && action` died
# under `set -e` whenever the *last-listed* worktree was left unchecked.

load test_helper

RUN_SELECT="$BATS_TEST_DIRNAME/support/run_select.exp"

@test "select: toggling one item and confirming removes only that one" {
  make_worktree foo
  make_worktree bar
  run "$RUN_SELECT" "$BASE" "$WT" "1" "d" "n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at"* ]]
  # exactly one of the two should be gone, the other untouched
  worktree_exists foo || worktree_exists bar
  ! { worktree_exists foo && worktree_exists bar; }
}

@test "select: toggling the LAST-listed item and confirming does not crash (regression)" {
  make_worktree aaa
  make_worktree zzz
  # git worktree list order is insertion order here, so zzz is listed last;
  # toggling only the last entry is exactly the case that used to kill the
  # whole script silently under set -e.
  run "$RUN_SELECT" "$BASE" "$WT" "2" "d" "n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at"* ]]
  worktree_exists aaa
  ! worktree_exists zzz
}

@test "select: 'a' selects all, then confirming removes everything listed" {
  make_worktree foo
  make_detached_worktree bar
  run "$RUN_SELECT" "$BASE" "$WT" "a" "d" "y"
  [ "$status" -eq 0 ]
  ! worktree_exists foo
  ! worktree_exists bar
  ! branch_exists foo
}

@test "select: confirming with nothing checked removes nothing" {
  make_worktree foo
  run "$RUN_SELECT" "$BASE" "$WT" "d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing selected"* ]]
  worktree_exists foo
}

@test "select: 'q' cancels without removing anything" {
  make_worktree foo
  run "$RUN_SELECT" "$BASE" "$WT" "q"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cancelled"* ]]
  worktree_exists foo
}

@test "select: an out-of-range number is ignored, not a crash" {
  make_worktree foo
  run "$RUN_SELECT" "$BASE" "$WT" "99" "d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing selected"* ]]
  worktree_exists foo
}

@test "select: a detached worktree never triggers the branch-deletion prompt" {
  make_detached_worktree foo
  run "$RUN_SELECT" "$BASE" "$WT" "1" "d"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Also delete"* ]]
  ! worktree_exists foo
}
