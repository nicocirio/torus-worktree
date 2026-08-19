#!/usr/bin/env bats

load test_helper

@test "list: shows the NAME/BRANCH/CREATED/LAST COMMIT header and marks the current worktree" {
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"*"BRANCH"*"CREATED"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
}

@test "list: shows LAST COMMIT once a commit lands in a worktree after it was created" {
  make_worktree foo
  git -C "$TEST_ROOT/foo" commit -q --allow-empty -m "work in foo"
  run "$WT" list
  [ "$status" -eq 0 ]
  foo_line="$(awk '$1 == "foo"' <<< "$output")"
  [[ "$foo_line" != *"—"* ]]
}

@test "list: hides LAST COMMIT when the branch's history predates the worktree" {
  git branch old-branch
  sleep 2
  git worktree add -q "$TEST_ROOT/stale" old-branch
  run "$WT" list
  [ "$status" -eq 0 ]
  stale_line="$(awk '$1 == "stale"' <<< "$output")"
  [[ "$stale_line" == *"—"* ]]
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
  [[ "$output" == *"SIZE"*"NAME"*"BRANCH"*"CREATED"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
  [[ "$output" == *"foo"*"foo"* ]]
}
