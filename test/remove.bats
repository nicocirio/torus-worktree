#!/usr/bin/env bats
#
# Covers `worktree remove`: single name (backward compat), multiple names,
# --select, --all, and the --force/--delete-branches/--keep-branches flags.

load test_helper

# --- single name (backward compatibility) ----------------------------------

@test "remove <name>: removes the worktree, declines branch deletion by default" {
  make_worktree foo
  run bash -c "echo n | '$WT' remove foo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at"* ]]
  [[ "$output" == *"Also delete these local branches?"* ]]
  ! worktree_exists foo
  branch_exists foo
}

@test "remove <name>: accepting the prompt also deletes the branch" {
  make_worktree foo
  run bash -c "echo y | '$WT' remove foo"
  [ "$status" -eq 0 ]
  ! worktree_exists foo
  ! branch_exists foo
}

@test "remove <name>: a detached worktree never asks about a branch" {
  make_detached_worktree foo
  run "$WT" remove foo
  [ "$status" -eq 0 ]
  [[ "$output" != *"Also delete"* ]]
  ! worktree_exists foo
}

# --- multiple names ----------------------------------------------------------

@test "remove <name1> <name2>: removes both with a single batch branch question" {
  make_worktree foo
  make_worktree bar
  run bash -c "echo y | '$WT' remove foo bar"
  [ "$status" -eq 0 ]
  # exactly one "Also delete" block, not one per worktree
  [ "$(grep -c 'Also delete these local branches?' <<< "$output")" -eq 1 ]
  [[ "$output" == *"- foo"* ]]
  [[ "$output" == *"- bar"* ]]
  ! worktree_exists foo
  ! worktree_exists bar
  ! branch_exists foo
  ! branch_exists bar
}

@test "remove <name> <name>: the same name twice is deduped, not double-removed" {
  make_worktree foo
  run bash -c "echo n | '$WT' remove foo foo"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^Removed worktree at' <<< "$output")" -eq 1 ]
  ! worktree_exists foo
}

# --- --select -----------------------------------------------------------------

@test "remove --select: refuses without a real terminal" {
  make_worktree foo
  run "$WT" remove --select
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs an interactive terminal"* ]]
  worktree_exists foo
}

# --- --all --------------------------------------------------------------------

@test "remove --all: with nothing else to remove, does nothing" {
  run "$WT" remove --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"No other worktrees to remove"* ]]
}

@test "remove --all: declining the confirmation removes nothing" {
  make_worktree foo
  make_worktree bar
  run bash -c "echo n | '$WT' remove --all"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cancelled"* ]]
  worktree_exists foo
  worktree_exists bar
}

@test "remove --all: accepting removes every worktree but the current one" {
  make_worktree foo
  make_detached_worktree bar
  run bash -c "printf 'y\ny\n' | '$WT' remove --all"
  [ "$status" -eq 0 ]
  ! worktree_exists foo
  ! worktree_exists bar
  ! branch_exists foo
}

# --- flags: --force / --delete-branches / --keep-branches --------------------

@test "remove --delete-branches: no prompt, branch is deleted" {
  make_worktree foo
  run "$WT" remove foo --delete-branches
  [ "$status" -eq 0 ]
  [[ "$output" != *"Also delete"* ]]
  ! worktree_exists foo
  ! branch_exists foo
}

@test "remove --keep-branches: no prompt, branch survives" {
  make_worktree foo
  run "$WT" remove foo --keep-branches
  [ "$status" -eq 0 ]
  [[ "$output" != *"Also delete"* ]]
  ! worktree_exists foo
  branch_exists foo
}

@test "remove --delete-branches --keep-branches: rejected as contradictory" {
  make_worktree foo
  run "$WT" remove foo --delete-branches --keep-branches
  [ "$status" -eq 1 ]
  [[ "$output" == *"Can't combine"* ]]
  worktree_exists foo
}

@test "remove: a dirty worktree is reported, not removed, without --force" {
  make_worktree foo
  echo "scratch" > "$TEST_ROOT/foo/untracked.txt"
  run bash -c "echo n | '$WT' remove foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modified or untracked files"* ]]
  worktree_exists foo
}

@test "remove: accepting the batch force-prompt removes a dirty worktree" {
  make_worktree foo
  echo "scratch" > "$TEST_ROOT/foo/untracked.txt"
  run bash -c "echo y | '$WT' remove foo --keep-branches"
  [ "$status" -eq 0 ]
  ! worktree_exists foo
}

@test "remove --force: a dirty worktree is force-removed without asking" {
  make_worktree foo
  echo "scratch" > "$TEST_ROOT/foo/untracked.txt"
  run "$WT" remove foo --force --keep-branches
  [ "$status" -eq 0 ]
  [[ "$output" != *"modified or untracked"*"? [y/N]"* ]]
  ! worktree_exists foo
}

# --- error / edge cases -------------------------------------------------------

@test "remove: no arguments prints usage and exits non-zero" {
  run "$WT" remove
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: worktree remove"* ]]
}

@test "remove --select <name>: rejected as mutually exclusive" {
  make_worktree foo
  run "$WT" remove --select foo
  [ "$status" -eq 1 ]
  [[ "$output" == *"not combined"* ]]
}

@test "remove: a nonexistent name is skipped, not an error that touches anything" {
  run "$WT" remove does-not-exist
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree found"* ]]
  [[ "$output" == *"Nothing to remove"* ]]
}

@test "remove: refuses to remove the worktree you're running it from" {
  run "$WT" remove base
  [ "$status" -eq 1 ]
  [[ "$output" == *"that's the worktree you're running this from"* ]]
}
