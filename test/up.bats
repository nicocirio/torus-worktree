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
  [[ "$output" == *"Worktree setup timing report (wall-clock)"* ]]
  [ -f "$HOME/.cache/torus-worktree/logs/MER-1234/timings.log" ]
}

@test "up: primes _build and patches its Mix 1.19 manifest" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/_build/dev/lib/oli/.mix"
  echo 'fake manifest' > "$BASE/_build/dev/lib/oli/.mix/compile.elixir"
  git -C "$BASE" branch cached-build

  run "$WT" up cached-build --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" == *"priming _build from the base worktree (Elixir 1.19.2)"* ]]
  [[ "$output" == *"patched the compile manifest for this worktree's path"* ]]
  [ -f "$TEST_ROOT/cached-build/_build/dev/lib/oli/.mix/compile.elixir" ]
  grep -q "^elixir .*patch_mix_manifest_cwd.exs" "$STUB_LOG"
}

@test "up: falls back safely when the copied Mix manifest cannot be patched" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/_build/dev/lib/oli/.mix"
  echo 'fake manifest' > "$BASE/_build/dev/lib/oli/.mix/compile.elixir"
  export PATCH_STUB_EXIT=1
  git -C "$BASE" branch rejected-manifest

  run "$WT" up rejected-manifest --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest patch did not apply; mix compile will validate with its normal fallback"* ]]
  grep -q "^mix compile$" "$STUB_LOG"
}

@test "up: leaves _build unprimed on an unsupported Elixir version" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/_build/dev/lib/oli/.mix"
  echo 'fake manifest' > "$BASE/_build/dev/lib/oli/.mix/compile.elixir"
  export ELIXIR_STUB_VERSION=1.18.3
  git -C "$BASE" branch unsupported-elixir

  run "$WT" up unsupported-elixir --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" != *"priming _build from the base worktree"* ]]
  # The mix stub creates an empty _build for `mix compile`; the copied
  # manifest must not be present when the priming gate rejects this version.
  [ ! -f "$TEST_ROOT/unsupported-elixir/_build/dev/lib/oli/.mix/compile.elixir" ]
  ! grep -q "^elixir .*patch_mix_manifest_cwd.exs" "$STUB_LOG"
  grep -q "^mix compile$" "$STUB_LOG"
}

@test "up: preserves mtimes only for unchanged Mix compile inputs" {
  make_up_ready_base
  make_toolchain_stubs
  touch -t 202001020304 "$BASE/mix.exs" "$BASE/config/config.exs"
  git -C "$BASE" branch matching-input-mtimes

  run "$WT" up matching-input-mtimes --no-ide --no-server

  [ "$status" -eq 0 ]
  [ "$(stat -f %m "$TEST_ROOT/matching-input-mtimes/mix.exs")" = "$(stat -f %m "$BASE/mix.exs")" ]
  [ "$(stat -f %m "$TEST_ROOT/matching-input-mtimes/config/config.exs")" = "$(stat -f %m "$BASE/config/config.exs")" ]
}

@test "up: does not normalize the mtime of a changed compile config input" {
  make_up_ready_base
  make_toolchain_stubs
  touch -t 202001020304 "$BASE/config/config.exs"
  git -C "$BASE" branch changed-config-input
  git -C "$BASE" worktree add -q "$TEST_ROOT/changed-config-input-source" changed-config-input
  echo 'config :example, changed: true' >> "$TEST_ROOT/changed-config-input-source/config/config.exs"
  git -C "$TEST_ROOT/changed-config-input-source" add config/config.exs
  git -C "$TEST_ROOT/changed-config-input-source" commit -qm 'change compile config'
  git -C "$BASE" worktree remove -f "$TEST_ROOT/changed-config-input-source"

  run "$WT" up changed-config-input --no-ide --no-server

  [ "$status" -eq 0 ]
  [ "$(stat -f %m "$TEST_ROOT/changed-config-input/config/config.exs")" -gt "$(stat -f %m "$BASE/config/config.exs")" ]
}

@test "up --assets-deps=link: symlinks matching assets dependencies" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/assets/node_modules"
  echo 'marker' > "$BASE/assets/node_modules/marker.txt"
  git -C "$BASE" branch shared-assets

  run "$WT" up shared-assets --assets-deps=link --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" == *"SHARED NODE_MODULES MODE ENABLED"* ]]
  [[ "$output" == *"symlinking node_modules from the base worktree"* ]]
  [ -L "$TEST_ROOT/shared-assets/assets/node_modules" ]
  [ "$(readlink "$TEST_ROOT/shared-assets/assets/node_modules")" = "$BASE/assets/node_modules" ]
  ! grep -q "^yarn install$" "$STUB_LOG"
}

@test "up --assets-deps=link: installs isolated assets dependencies when the branch lock differs" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/assets/node_modules"
  git -C "$BASE" branch changed-assets-lock
  git -C "$BASE" worktree add -q "$TEST_ROOT/changed-assets-lock-source" changed-assets-lock
  echo 'lockfile-v2' > "$TEST_ROOT/changed-assets-lock-source/assets/yarn.lock"
  git -C "$TEST_ROOT/changed-assets-lock-source" add assets/yarn.lock
  git -C "$TEST_ROOT/changed-assets-lock-source" commit -qm 'change assets lock'
  git -C "$BASE" worktree remove -f "$TEST_ROOT/changed-assets-lock-source"

  run "$WT" up changed-assets-lock --assets-deps=link --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" == *"SHARED NODE_MODULES NOT SAFE — USING AN ISOLATED INSTALL"* ]]
  [[ "$output" == *"installing (link mode fallback)"* ]]
  [ ! -L "$TEST_ROOT/changed-assets-lock/assets/node_modules" ]
  [ -d "$TEST_ROOT/changed-assets-lock/assets/node_modules" ]
  grep -q "^yarn install$" "$STUB_LOG"
}

@test "up --assets-deps=link: installs isolated assets dependencies when package.json differs" {
  make_up_ready_base
  make_toolchain_stubs
  mkdir -p "$BASE/assets/node_modules"
  git -C "$BASE" branch changed-assets-package
  git -C "$BASE" worktree add -q "$TEST_ROOT/changed-assets-package-source" changed-assets-package
  echo '{"name":"changed"}' > "$TEST_ROOT/changed-assets-package-source/assets/package.json"
  git -C "$TEST_ROOT/changed-assets-package-source" add assets/package.json
  git -C "$TEST_ROOT/changed-assets-package-source" commit -qm 'change assets package manifest'
  git -C "$BASE" worktree remove -f "$TEST_ROOT/changed-assets-package-source"

  run "$WT" up changed-assets-package --assets-deps=link --no-ide --no-server

  [ "$status" -eq 0 ]
  [[ "$output" == *"SHARED NODE_MODULES NOT SAFE — USING AN ISOLATED INSTALL"* ]]
  [ ! -L "$TEST_ROOT/changed-assets-package/assets/node_modules" ]
  [ -d "$TEST_ROOT/changed-assets-package/assets/node_modules" ]
  grep -q "^yarn install$" "$STUB_LOG"
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
