# Shared setup/teardown for all .bats files in this directory.
#
# Every test gets its own throwaway git repo (satisfying worktree.sh's
# oli-torus guard: mix.exs, assets/automation/, gleam/gleam.toml) and its
# own fake $HOME, so tests never touch the real ~/.config/torus-worktree,
# ~/.cache/torus-worktree, or any of the developer's actual worktrees.

WT="$BATS_TEST_DIRNAME/../worktree.sh"

setup() {
  # Resolve to the canonical path right away: mktemp -d on macOS returns a
  # /var/... path that's actually a symlink to /private/var/..., and `git
  # worktree list` reports the resolved form — comparing against the
  # unresolved one silently never matches.
  TEST_HOME="$(mktemp -d)"
  TEST_HOME="$(cd "$TEST_HOME" && pwd -P)"
  export HOME="$TEST_HOME"

  TEST_ROOT="$(mktemp -d)"
  TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
  BASE="$TEST_ROOT/base"
  mkdir -p "$BASE"
  git -C "$BASE" init -q
  git -C "$BASE" config user.email "test@test.com"
  git -C "$BASE" config user.name "Test"
  touch "$BASE/mix.exs"
  mkdir -p "$BASE/assets/automation" "$BASE/gleam"
  touch "$BASE/gleam/gleam.toml"
  git -C "$BASE" add -A
  git -C "$BASE" commit -qm "initial"

  cd "$BASE"
}

teardown() {
  cd /
  rm -rf "$TEST_ROOT" "$TEST_HOME"
}

# make_worktree <name> — sibling worktree checked out on a same-named branch.
make_worktree() {
  local name="$1"
  git -C "$BASE" branch "$name"
  git -C "$BASE" worktree add -q "$TEST_ROOT/$name" "$name"
}

# make_detached_worktree <name> — sibling worktree with no branch.
make_detached_worktree() {
  local name="$1"
  git -C "$BASE" worktree add -q --detach "$TEST_ROOT/$name"
}

# worktree_exists <name> — true if git still lists a worktree at that path.
worktree_exists() {
  git -C "$BASE" worktree list --porcelain | grep -q "^worktree $TEST_ROOT/$1\$"
}

# branch_exists <name>
branch_exists() {
  git -C "$BASE" branch --list "$1" | grep -q "$1"
}
