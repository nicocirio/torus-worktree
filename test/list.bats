#!/usr/bin/env bats

load test_helper

@test "list: shows the NAME/BRANCH header and marks the current worktree" {
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"*"BRANCH"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
}

@test "list: shows other worktrees, without the (current) marker" {
  make_worktree foo
  make_detached_worktree bar
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"*"foo"* ]]
  [[ "$output" == *"bar"*"(detached)"* ]]
  # only the base row gets "(current)"
  [ "$(grep -c '(current)' <<< "$output")" -eq 1 ]
}

@test "list: rejects an unknown option" {
  run "$WT" list --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for list"* ]]
}

@test "list --size: shows a SIZE column and still marks the current worktree" {
  make_worktree foo
  run "$WT" list --size
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIZE"*"NAME"*"BRANCH"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
  [[ "$output" == *"foo"*"foo"* ]]
}
