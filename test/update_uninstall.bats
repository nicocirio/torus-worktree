#!/usr/bin/env bats
#
# `update`/`uninstall` operate on $TOOL_ROOT (wherever the invoked
# worktree.sh physically lives), so these run against a disposable fake
# install (test/support/fake_install.bash) instead of the real dev
# checkout — uninstall does `rm -rf "$TOOL_ROOT"`.

load test_helper
load support/fake_install

# --- uninstall's safety guard, against the REAL dev checkout ------------------

@test "uninstall: refuses on a checkout with no install marker (safety guard)" {
  run "$WT" uninstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"not marked as an installed copy"* ]]
  # the real dev checkout must still be untouched
  [ -f "$BATS_TEST_DIRNAME/../worktree.sh" ]
}

# --- update ---------------------------------------------------------------

@test "update: reports already up to date when origin hasn't moved" {
  make_fake_install
  run "$FAKE_WT" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
}

@test "update: fast-forwards when origin has new commits" {
  make_fake_install
  push_a_new_commit_to_origin
  run "$FAKE_WT" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated torus-worktree to"* ]]
  grep -q "upstream change" "$FAKE_TOOL_DIR/worktree.sh"
}

@test "update: refuses when the installation has local changes" {
  make_fake_install
  echo "local edit" >> "$FAKE_TOOL_DIR/worktree.sh"
  run "$FAKE_WT" update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to update"*"local changes"* ]]
}

@test "update: refuses when not on main" {
  make_fake_install
  git -C "$FAKE_TOOL_DIR" checkout -qb some-other-branch
  run "$FAKE_WT" update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to update"*"main"* ]]
}

@test "update: refuses when local main has diverged from origin" {
  make_fake_install
  git -C "$FAKE_TOOL_DIR" commit -q --allow-empty -m "local-only commit"
  run "$FAKE_WT" update
  [ "$status" -eq 1 ]
  [[ "$output" == *"diverged"* ]]
}

# --- uninstall (happy paths, against the fake install) ------------------------

@test "uninstall: rejects an unknown option" {
  make_fake_install
  run "$FAKE_WT" uninstall --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for uninstall"* ]]
}

@test "uninstall: declining the confirmation removes nothing" {
  make_fake_install
  run bash -c "echo n | '$FAKE_WT' uninstall"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uninstall cancelled"* ]]
  [ -d "$FAKE_TOOL_DIR" ]
  [ -L "$HOME/.local/bin/worktree" ]
}

@test "uninstall: accepting removes the install dir and the managed symlinks" {
  make_fake_install
  run bash -c "echo y | '$FAKE_WT' uninstall"
  [ "$status" -eq 0 ]
  [[ "$output" == *"torus-worktree uninstalled"* ]]
  [ ! -d "$FAKE_TOOL_DIR" ]
  [ ! -e "$HOME/.local/bin/worktree" ]
  [ ! -e "$HOME/.local/bin/wt" ]
  [ ! -e "$HOME/.local/bin/run-server" ]
}

@test "uninstall: keeps personal config unless --purge-config is given" {
  make_fake_install
  mkdir -p "$HOME/.config/torus-worktree"
  echo "IDE_CMD='my-ide'" > "$HOME/.config/torus-worktree/config.sh"
  run bash -c "echo y | '$FAKE_WT' uninstall"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/torus-worktree/config.sh" ]
}

@test "uninstall --purge-config: also removes the personal config" {
  make_fake_install
  mkdir -p "$HOME/.config/torus-worktree"
  echo "IDE_CMD='my-ide'" > "$HOME/.config/torus-worktree/config.sh"
  run bash -c "echo y | '$FAKE_WT' uninstall --purge-config"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/torus-worktree" ]
}
