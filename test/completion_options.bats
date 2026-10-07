#!/usr/bin/env bats
# Inspect option candidates passed to zsh's renderer, without a live shell UI.

load test_helper

@test "completion: list and remove offer all sort values and reverse after existing flags" {
  for subcommand in list remove; do
    for position in 3 4; do
      run zsh -c '
        _describe() {
          local list_name=$2
          print -rl -- "${(@P)list_name}"
        }
        worktree() { return 0; }
        CURRENT=$3
        PREFIX=--sort=
        words=(wt "$2" --reverse --sort=)
        source "$1"
      ' _ "$BATS_TEST_DIRNAME/../completions/_worktree" "$subcommand" "$position"
      [ "$status" -eq 0 ]
      [ "$(awk -F: '/^--sort=/ {print $1}' <<< "$output")" = $'--sort=name\n--sort=branch\n--sort=created\n--sort=last-commit' ]
      [ "$(grep -c '^--reverse:' <<< "$output")" -eq 1 ]
    done
  done
}

@test "completion: list still offers size alongside sorting" {
  run zsh -c '
    _describe() { local list_name=$2; print -rl -- "${(@P)list_name}"; }
    CURRENT=3
    PREFIX=--
    words=(wt list --)
    source "$1"
  ' _ "$BATS_TEST_DIRNAME/../completions/_worktree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--size:"* ]]
}
