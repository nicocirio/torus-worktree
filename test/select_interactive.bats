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
  # Pin alphabetical order so the last-listed item is always zzz.
  # Selecting it used to expose an implicit nonzero function return.
  run "$RUN_SELECT" "$BASE" "$WT" --sort=name -- "2" "d" "n"
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

@test "select: shows CREATED and LAST COMMIT columns, same as list" {
  make_worktree foo
  run "$RUN_SELECT" "$BASE" "$WT" "q"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"*"BRANCH"*"CREATED"*"LAST COMMIT"* ]]
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

load support/sort_fixtures

@test "select: default created order determines row numbers and selection" {
  make_sort_fixture
  run "$RUN_SELECT" "$BASE" "$WT" "1" "d" "n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 [ ] new"*"2 [ ] old"* ]]
  ! worktree_exists new
  worktree_exists old
}

@test "select: name sort and reverse determine row numbers and removal" {
  make_sort_fixture
  run "$RUN_SELECT" "$BASE" "$WT" --sort=name --reverse --keep-branches -- "1" "d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 [ ] old"*"2 [ ] new"* ]]
  ! worktree_exists old
  worktree_exists new
}

@test "select: last-commit sort and reverse apply to all selected targets" {
  make_sort_fixture
  run "$RUN_SELECT" "$BASE" "$WT" --reverse --sort=last-commit --keep-branches -- "a" "d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 [ ] new"*"2 [ ] old"* ]]
  [[ "$output" == *"Removed worktree at $TEST_ROOT/new."*"Removed worktree at $TEST_ROOT/old."* ]]
  ! worktree_exists old
  ! worktree_exists new
}

@test "select: selected missing registration is removed without pruning unselected entries" {
  make_detached_worktree aaa-gone
  make_detached_worktree zzz-gone
  mv "$TEST_ROOT/aaa-gone" "$TEST_ROOT/aaa-unregistered"
  mv "$TEST_ROOT/zzz-gone" "$TEST_ROOT/zzz-unregistered"
  run "$RUN_SELECT" "$BASE" "$WT" --sort=name -- "1" "d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(detached) (missing)"* ]]
  [[ "$output" == *"Removed worktree at $TEST_ROOT/aaa-gone."* ]]
  run worktree_exists aaa-gone
  [ "$status" -eq 1 ]
  worktree_exists zzz-gone
  [ -d "$TEST_ROOT/aaa-unregistered" ]
  [ -d "$TEST_ROOT/zzz-unregistered" ]
}
