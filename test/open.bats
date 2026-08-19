#!/usr/bin/env bats
#
# `--no-ide` is passed in every test here to avoid evaluating the default
# IDE_CMD (`cursor "$WORKTREE_PATH" --profile=Second`), which doesn't exist
# in the test environment. The one IDE_CMD-related test configures an empty
# IDE_CMD instead, so it can exercise that code path without `--no-ide`.

load test_helper

@test "open: requires a target" {
  run "$WT" open
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: worktree open"* ]]
}

@test "open: rejects an unknown option" {
  make_worktree foo
  run "$WT" open foo --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for open"* ]]
}

@test "open: resolves by folder name" {
  make_worktree foo
  run "$WT" open foo --no-ide
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-server"* ]]
}

@test "open: resolves by branch name when it differs from the folder name" {
  git -C "$BASE" branch some-branch
  git -C "$BASE" worktree add -q "$TEST_ROOT/differently-named" some-branch
  run "$WT" open some-branch --no-ide
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-server"* ]]
}

@test "open: refuses to open the worktree you're running it from" {
  run "$WT" open base --no-ide
  [ "$status" -eq 1 ]
  [[ "$output" == *"That's the worktree you're running this from"* ]]
}

@test "open: a nonexistent target is a clear error" {
  run "$WT" open does-not-exist --no-ide
  [ "$status" -eq 1 ]
  [[ "$output" == *"No worktree found matching"* ]]
}

@test "open --no-server: suppresses the run-server hint" {
  make_worktree foo
  run "$WT" open foo --no-ide --no-server
  [ "$status" -eq 0 ]
  [[ "$output" != *"run-server"* ]]
}

@test "open: an empty configured IDE_CMD is reported, not evaluated as a command" {
  mkdir -p "$HOME/.config/torus-worktree"
  cat > "$HOME/.config/torus-worktree/config.sh" <<'EOF'
IDE_CMD=''
DEFAULT_PORT=4001
EOF
  make_worktree foo
  run "$WT" open foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDE_CMD is empty in your config, skipping IDE launch"* ]]
}

@test "open: reuses a worktree's already-recorded port instead of picking a new one" {
  make_worktree foo
  cat > "$TEST_ROOT/foo/oli.env" <<'EOF'
HTTP_PORT=4321
PORT=4321
PLAYWRIGHT_BASE_URL=http://localhost:4321
EOF
  run "$WT" open foo --no-ide
  [ "$status" -eq 0 ]
  [[ "$output" == *":4321"* ]]
  grep -q '^HTTP_PORT=4321' "$TEST_ROOT/foo/oli.env"
  grep -q '^PLAYWRIGHT_BASE_URL=http://localhost:4321' "$TEST_ROOT/foo/oli.env"
}
