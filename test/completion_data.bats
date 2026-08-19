#!/usr/bin/env bats
#
# Covers the hidden `__complete-*` subcommands that completions/_worktree
# shells out to for candidate data. Plain bash, no zsh involved — this is
# the "data layer" of tab completion, not the _describe/compadd widget
# itself (see docs/design-notes.md's "Testing" section for why that split).

load test_helper

# --- __complete-worktrees -----------------------------------------------------

@test "__complete-worktrees: excludes the current worktree" {
  make_worktree foo
  run "$WT" __complete-worktrees
  [ "$status" -eq 0 ]
  [[ "$output" != *"base"* ]]
  [[ "$output" == *"foo"* ]]
}

@test "__complete-worktrees: lists every other worktree by folder name" {
  make_worktree foo
  make_detached_worktree bar
  run "$WT" __complete-worktrees
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | sort)" = "$(printf 'bar\nfoo' | sort)" ]
}

@test "__complete-worktrees: nothing but the current worktree prints nothing" {
  run "$WT" __complete-worktrees
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- __complete-branches -------------------------------------------------------

@test "__complete-branches: lists local branches" {
  git -C "$BASE" branch foo
  git -C "$BASE" branch bar
  run "$WT" __complete-branches
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
  [[ "$output" == *"bar"* ]]
}

@test "__complete-branches: lists remote branches without the origin/ prefix, excludes origin/HEAD" {
  REMOTE="$TEST_ROOT/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$BASE" remote add origin "$REMOTE"
  git -C "$BASE" push -q origin HEAD:refs/heads/main 2>/dev/null
  git -C "$BASE" branch remote-only
  git -C "$BASE" push -q origin remote-only
  git -C "$BASE" branch -D remote-only
  git -C "$BASE" fetch -q origin
  # A bare remote has no default branch to auto-detect ("remote set-head
  # -a" fails with "Cannot determine remote HEAD"), so point it explicitly
  # instead of fighting git plumbing that's incidental to what's tested here.
  git -C "$BASE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  run "$WT" __complete-branches
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote-only"* ]]
  [[ "$output" != *"origin/"* ]]
  [[ "$output" != *"HEAD"* ]]
}

@test "__complete-branches: a branch that's both local and remote-tracked appears once" {
  REMOTE="$TEST_ROOT/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$BASE" remote add origin "$REMOTE"
  git -C "$BASE" branch shared
  git -C "$BASE" push -q origin shared
  git -C "$BASE" fetch -q origin

  run "$WT" __complete-branches
  [ "$status" -eq 0 ]
  [ "$(grep -c '^shared$' <<< "$output")" -eq 1 ]
}

# --- __complete-open-targets ---------------------------------------------------

@test "__complete-open-targets: excludes the current worktree" {
  make_worktree foo
  run "$WT" __complete-open-targets
  [ "$status" -eq 0 ]
  [[ "$output" != *"base"* ]]
}

@test "__complete-open-targets: lists both the folder name and the branch" {
  make_worktree foo
  run "$WT" __complete-open-targets
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
  # branch name here happens to equal the folder name (make_worktree's
  # convention), so just check both lines exist
  [ "$(grep -cx 'foo' <<< "$output")" -eq 2 ]
}

@test "__complete-open-targets: a detached worktree contributes only its folder name" {
  make_detached_worktree bar
  run "$WT" __complete-open-targets
  [ "$status" -eq 0 ]
  [[ "$output" == *"bar"* ]]
  [[ "$output" != *"(detached)"* ]]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}
