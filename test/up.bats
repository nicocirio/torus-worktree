#!/usr/bin/env bats
#
# Tests `up` against stubbed yarn/npm/mix/gleam (test/support/toolchain_stubs.bash)
# instead of the real oli-torus toolchain — see docs/design-notes.md's
# "Testing" section for why. `--no-ide` avoids evaluating the default
# IDE_CMD (`cursor`, which doesn't exist here); the fake `osascript` from
# test_helper.bash already covers the "worktree ready" dialog.

load test_helper
load support/toolchain_stubs

@test "up: requires a branch argument" {
  run "$WT" up
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "up: rejects an invalid deps mode" {
  git -C "$BASE" branch some-branch
  run "$WT" up some-branch --assets-deps=bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid deps mode"* ]]
}

@test "up: creates a worktree from an existing local branch, running the stubbed toolchain" {
  make_up_ready_base
  make_toolchain_stubs
  git -C "$BASE" branch MER-1234-some-feature
  run "$WT" up MER-1234-some-feature --no-ide --no-server
  [ "$status" -eq 0 ]
  [[ "$output" == *"Environment ready"* ]]
  [ -d "$TEST_ROOT/MER-1234" ]
  worktree_exists MER-1234
  # auto mode with no matching node_modules/deps at the base falls back to
  # actually installing — the stubs should have been invoked
  grep -q "^yarn install$" "$STUB_LOG"
  grep -q "^npm i$" "$STUB_LOG"
  grep -q "^mix deps.get$" "$STUB_LOG"
  grep -q "^mix compile$" "$STUB_LOG"
  grep -q "^gleam deps download$" "$STUB_LOG"
}

@test "up: derives the worktree name from a ticket-like token in the branch" {
  make_up_ready_base
  make_toolchain_stubs
  git -C "$BASE" branch MER-9999-anything-else
  run "$WT" up MER-9999-anything-else --no-ide --no-server
  [ "$status" -eq 0 ]
  [ -d "$TEST_ROOT/MER-9999" ]
}

@test "up: sanitizes the branch name for the worktree when there's no ticket token" {
  make_up_ready_base
  make_toolchain_stubs
  git -C "$BASE" branch feature/some-thing
  run "$WT" up feature/some-thing --no-ide --no-server
  [ "$status" -eq 0 ]
  [ -d "$TEST_ROOT/feature-some-thing" ]
}

@test "up --assets-deps=copy: copies node_modules instead of running yarn when the lockfile matches" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/assets/node_modules"
  echo "marker" > "$BASE/assets/node_modules/marker.txt"
  git -C "$BASE" branch some-branch
  run "$WT" up some-branch --no-ide --no-server --assets-deps=copy
  [ "$status" -eq 0 ]
  [ -f "$TEST_ROOT/some-branch/assets/node_modules/marker.txt" ]
  ! grep -q "^yarn install$" "$STUB_LOG"
}

@test "up: a failing step is reported without crashing the whole run" {
  make_up_ready_base
  make_toolchain_stubs
  git -C "$BASE" branch some-branch
  export MIX_STUB_FAIL="compile"
  run "$WT" up some-branch --no-ide --no-server
  [ "$status" -eq 1 ]
  [[ "$output" == *"Step 'backend' failed"* ]]
  [[ "$output" == *"Environment has errors"* ]]
}

@test "up: an existing target, declining to open, leaves guidance and exits non-zero" {
  make_up_ready_base
  make_toolchain_stubs
  make_worktree conflict-name
  run bash -c "echo n | '$WT' up conflict-name --no-ide --no-server"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Something already exists at"* ]]
  [[ "$output" == *"worktree remove"* ]]
}

@test "up: an existing target, accepting, opens it instead of recreating it" {
  make_up_ready_base
  make_toolchain_stubs
  make_worktree conflict-name
  run bash -c "echo y | '$WT' up conflict-name --no-ide --no-server"
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-server"* ]]
  # nothing from the stubbed toolchain should have run — it's an open, not a build
  [ ! -s "$STUB_LOG" ]
}

@test "up: a branch that doesn't exist anywhere, declining to create it, does nothing" {
  make_up_ready_base
  make_toolchain_stubs
  run bash -c "echo '' | '$WT' up brand-new-branch --no-ide --no-server"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found locally or on origin"* ]]
  [ ! -d "$TEST_ROOT/brand-new-branch" ]
}

@test "up: a branch that doesn't exist anywhere, creating it from HEAD" {
  make_up_ready_base
  make_toolchain_stubs
  run bash -c "echo 1 | '$WT' up brand-new-branch --no-ide --no-server"
  [ "$status" -eq 0 ]
  [ -d "$TEST_ROOT/brand-new-branch" ]
  branch_exists brand-new-branch
}
