#!/usr/bin/env bats
#
# `config`/`version` are resolved before the oli-torus repo guard, so they
# work from anywhere — but still run inside the fake-repo/fake-$HOME
# fixture for consistency with the rest of the suite.

load test_helper

CONFIG_FILE_PATH() { echo "$HOME/.config/torus-worktree/config.sh"; }

@test "config: first run writes the config file using defaults on blank input" {
  run bash -c "printf '\n\n' | '$WT' config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Saved"* ]]
  [ -f "$(CONFIG_FILE_PATH)" ]
  grep -q '^IDE_CMD=' "$(CONFIG_FILE_PATH)"
  grep -q '^DEFAULT_PORT=4001' "$(CONFIG_FILE_PATH)"
}

@test "config: accepts a custom IDE command and port" {
  run bash -c "printf 'my-ide\n5000\n' | '$WT' config"
  [ "$status" -eq 0 ]
  grep -q "IDE_CMD='my-ide'" "$(CONFIG_FILE_PATH)"
  grep -q '^DEFAULT_PORT=5000' "$(CONFIG_FILE_PATH)"
}

@test "config: re-prompts until the port is numeric" {
  run bash -c "printf '\nabc\n6000\n' | '$WT' config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Please enter a number."* ]]
  grep -q '^DEFAULT_PORT=6000' "$(CONFIG_FILE_PATH)"
}

@test "config: re-running shows the previous values and backs up the old file" {
  bash -c "printf '\n\n' | '$WT' config" >/dev/null
  run bash -c "printf '\n\n' | '$WT' config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Current:"* ]]
  ls "$HOME/.config/torus-worktree/" | grep -q '\.bak\.'
}

# --- version -------------------------------------------------------------------

@test "version: reports a version line and the install path" {
  run "$WT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"torus-worktree"* ]]
  [[ "$output" == *"Installed at"* ]]
}
