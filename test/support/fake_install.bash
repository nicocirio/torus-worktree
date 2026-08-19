# Helper for testing `update`/`uninstall`, which operate on $TOOL_ROOT —
# wherever the invoked worktree.sh physically lives. Testing them against
# the real dev checkout would be destructive (uninstall does `rm -rf
# "$TOOL_ROOT"`), so this builds a throwaway copy with its own git history
# and its own fake "origin" remote, and symlinks $HOME/.local/bin/* at it
# the same way install.sh would.
#
# Requires test_helper.bash's fake $HOME to already be in place.

make_fake_install() {
  FAKE_ORIGIN="$(mktemp -d)/origin.git"
  git init -q --bare "$FAKE_ORIGIN"
  # A bare repo's HEAD defaults to whatever init.defaultBranch says (often
  # "master"), regardless of which branch actually gets pushed to it later
  # — leaving HEAD dangling and breaking `git clone` for anyone (including
  # push_a_new_commit_to_origin below) who clones it expecting "main".
  git -C "$FAKE_ORIGIN" symbolic-ref HEAD refs/heads/main

  FAKE_TOOL_DIR="$(mktemp -d)/tool"
  mkdir -p "$FAKE_TOOL_DIR"
  # Canonicalize: worktree.sh resolves its own TOOL_ROOT via `cd -P`, so an
  # unresolved /var/... (mktemp's raw output on macOS, a symlink to
  # /private/var/...) would never string-match TOOL_ROOT, and
  # remove_managed_link would silently never recognize these symlinks as
  # its own.
  FAKE_TOOL_DIR="$(cd "$FAKE_TOOL_DIR" && pwd -P)"
  cp "$BATS_TEST_DIRNAME/../worktree.sh" "$FAKE_TOOL_DIR/"
  cp "$BATS_TEST_DIRNAME/../run-server.sh" "$FAKE_TOOL_DIR/"
  cp "$BATS_TEST_DIRNAME/../.gitignore" "$FAKE_TOOL_DIR/"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$FAKE_TOOL_DIR/"
  cp -R "$BATS_TEST_DIRNAME/../completions" "$FAKE_TOOL_DIR/"

  git -C "$FAKE_TOOL_DIR" init -q -b main
  git -C "$FAKE_TOOL_DIR" config user.email "test@test.com"
  git -C "$FAKE_TOOL_DIR" config user.name "Test"
  git -C "$FAKE_TOOL_DIR" add -A
  git -C "$FAKE_TOOL_DIR" commit -qm "initial"
  git -C "$FAKE_TOOL_DIR" remote add origin "$FAKE_ORIGIN"
  git -C "$FAKE_TOOL_DIR" push -q origin main
  git -C "$FAKE_TOOL_DIR" branch --set-upstream-to=origin/main main

  # Gitignored (like in a real install), so it doesn't show as an untracked
  # change and make cmd_update's "clean?" check refuse a fresh fake install.
  touch "$FAKE_TOOL_DIR/.torus-worktree-install"

  FAKE_WT="$FAKE_TOOL_DIR/worktree.sh"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$FAKE_TOOL_DIR/worktree.sh" "$HOME/.local/bin/worktree"
  ln -sfn "$FAKE_TOOL_DIR/worktree.sh" "$HOME/.local/bin/wt"
  ln -sfn "$FAKE_TOOL_DIR/run-server.sh" "$HOME/.local/bin/run-server"
}

# push_a_new_commit_to_origin — clones $FAKE_ORIGIN separately, adds a
# commit there, and pushes it — simulating "origin/main moved on" without
# touching the fake install's own working copy or its git status.
push_a_new_commit_to_origin() {
  local clone_dir
  clone_dir="$(mktemp -d)/upstream-writer"
  git clone -q "$FAKE_ORIGIN" "$clone_dir"
  git -C "$clone_dir" config user.email "test@test.com"
  git -C "$clone_dir" config user.name "Test"
  echo "upstream change" >> "$clone_dir/worktree.sh"
  git -C "$clone_dir" commit -qam "upstream change"
  git -C "$clone_dir" push -q origin main
}
