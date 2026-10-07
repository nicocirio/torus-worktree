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

load support/sort_fixtures

@test "remove by names: default creation order replaces argument order" {
  make_sort_fixture
  run "$WT" remove old new --keep-branches
  [ "$status" -eq 0 ]
  [ "$(awk '/^Removed worktree at/ {sub(/\.$/, "", $NF); sub(/^.*\//, "", $NF); print $NF}' <<< "$output")" = $'new\nold' ]
  ! worktree_exists old
  ! worktree_exists new
}

@test "remove by names: explicit branch order and reverse apply with force and branch deletion" {
  make_sort_fixture
  export SORT_OLD_CREATED="$((SORT_NOW - 10))"
  echo scratch > "$TEST_ROOT/old/untracked"
  run "$WT" remove --reverse new --sort=branch old --force --delete-branches
  [ "$status" -eq 0 ]
  [ "$(awk '/^Removed worktree at/ {sub(/\.$/, "", $NF); sub(/^.*\//, "", $NF); print $NF}' <<< "$output")" = $'new\nold' ]
  ! branch_exists a-branch
  ! branch_exists z-branch
}

@test "remove by names: last-commit order and duplicate arguments" {
  make_sort_fixture
  run "$WT" remove new old old --sort=last-commit --keep-branches
  [ "$status" -eq 0 ]
  [ "$(awk '/^Removed worktree at/ {sub(/\.$/, "", $NF); sub(/^.*\//, "", $NF); print $NF}' <<< "$output")" = $'old\nnew' ]
}

@test "remove --all: default created order applies to preview and removal" {
  make_sort_fixture
  run bash -c 'echo y | "$1" remove --all --keep-branches' _ "$WT"
  [ "$status" -eq 0 ]
  [ "$(awk '/^  - / {print $2}' <<< "$output")" = $'new\nold' ]
  [ "$(awk '/^Removed worktree at/ {sub(/\.$/, "", $NF); sub(/^.*\//, "", $NF); print $NF}' <<< "$output")" = $'new\nold' ]
  [ -d "$BASE" ]
}

@test "remove --all: explicit name sort and reverse order the confirmation" {
  make_sort_fixture
  run bash -c 'echo n | "$1" remove --sort=name --all --reverse' _ "$WT"
  [ "$status" -eq 0 ]
  [ "$(awk '/^  - / {print $2}' <<< "$output")" = $'old\nnew' ]
  worktree_exists old
  worktree_exists new
}

@test "remove: invalid and empty sort fail before any selection or removal" {
  make_sort_fixture
  for mode in old --all --select; do
    for value in bogus ''; do
      run "$WT" remove "$mode" "--sort=$value" --force --delete-branches
      [ "$status" -eq 1 ]
      [[ "$output" == *"Invalid sort key"*"name|branch|created|last-commit"* ]]
      worktree_exists old
      worktree_exists new
    done
  done
}

@test "remove: missing registered directory can be removed by name without pruning others" {
  make_detached_worktree gone
  make_detached_worktree other-gone
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  mv "$TEST_ROOT/other-gone" "$TEST_ROOT/other-unregistered"
  run "$WT" remove gone
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at $TEST_ROOT/gone."* ]]
  run worktree_exists gone
  [ "$status" -eq 1 ]
  worktree_exists other-gone
  [ -d "$TEST_ROOT/unregistered" ]
  [ -d "$TEST_ROOT/other-unregistered" ]
}

@test "remove: missing registered directory outside sibling folder accepts its full path" {
  mkdir "$TEST_ROOT/elsewhere"
  git worktree add -q --detach "$TEST_ROOT/elsewhere/gone"
  mv "$TEST_ROOT/elsewhere/gone" "$TEST_ROOT/elsewhere/unregistered"
  run "$WT" remove "$TEST_ROOT/elsewhere/gone"
  [ "$status" -eq 0 ]
  [ "$(git worktree list --porcelain | awk -v p="$TEST_ROOT/elsewhere/gone" '$0 == "worktree " p {n++} END {print n+0}')" -eq 0 ]
  [ -d "$TEST_ROOT/elsewhere/unregistered" ]
}

@test "remove --all: removes missing registrations as well as existing worktrees" {
  make_detached_worktree gone
  make_worktree kept
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  run bash -c 'echo y | "$1" remove --all --keep-branches' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at $TEST_ROOT/gone."* ]]
  run worktree_exists gone
  [ "$status" -eq 1 ]
  run worktree_exists kept
  [ "$status" -eq 1 ]
  [ -d "$BASE" ]
  [ -d "$TEST_ROOT/unregistered" ]
}

@test "remove: missing registration honors explicit branch deletion" {
  make_worktree gone
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  run "$WT" remove gone --delete-branches
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed worktree at $TEST_ROOT/gone."* ]]
  run worktree_exists gone
  [ "$status" -eq 1 ]
  run branch_exists gone
  [ "$status" -eq 1 ]
  [ -d "$TEST_ROOT/unregistered" ]
}

@test "remove: locked missing registration stays registered even with force" {
  make_detached_worktree gone
  git worktree lock "$TEST_ROOT/gone"
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  run "$WT" remove gone --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"locked"* ]]
  worktree_exists gone
  [ -d "$TEST_ROOT/unregistered" ]
}
