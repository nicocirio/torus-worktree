#!/usr/bin/env bats

load test_helper

@test "rename: requires both a name and a new name" {
  make_worktree foo
  run "$WT" rename foo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: worktree rename"* ]]
}

@test "rename: rejects a new name with spaces or slashes" {
  make_worktree foo
  run "$WT" rename foo "bad name"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid name"* ]]
  worktree_exists foo
}

@test "rename: moves the worktree to the new name, git-worktree-move style" {
  make_worktree foo
  run "$WT" rename foo bar
  [ "$status" -eq 0 ]
  [[ "$output" == *"Renamed worktree"* ]]
  ! worktree_exists foo
  worktree_exists bar
  # the underlying branch is untouched by a rename
  branch_exists foo
  [ -d "$TEST_ROOT/bar" ]
  [ ! -d "$TEST_ROOT/foo" ]
}

@test "rename: a nonexistent name is a clear error" {
  run "$WT" rename does-not-exist bar
  [ "$status" -eq 1 ]
  [[ "$output" == *"No worktree found"* ]]
}

@test "rename: refuses when something already exists at the destination" {
  make_worktree foo
  make_worktree bar
  run "$WT" rename foo bar
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
  worktree_exists foo
  worktree_exists bar
}

@test "rename: refuses to rename the worktree you're running it from" {
  run "$WT" rename base something-else
  [ "$status" -eq 1 ]
  [[ "$output" == *"That's the worktree you're running this from"* ]]
}
