#!/usr/bin/env bats

load test_helper
load support/sort_fixtures

load_sort_worktrees() {
  eval "$(sed -n '/^worktree_created_epoch() {/,/^}/p' "$WT")"
  eval "$(sed -n '/^sort_worktrees() {/,/^}/p' "$WT")"
}

@test "sort_worktrees: equal epochs use full path ascending in either direction" {
  make_sort_fixture
  load_sort_worktrees
  export SORT_OLD_CREATED="$((SORT_NOW - 60))"
  for reverse in false true; do
    run sort_worktrees created "$reverse" <<< "$(printf '%s\tz-branch\n%s\ta-branch\n' "$TEST_ROOT/old" "$TEST_ROOT/new")"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\ta-branch\n%s\tz-branch' "$TEST_ROOT/new" "$TEST_ROOT/old")" ]
  done
}

@test "sort_worktrees: name sorting uses basename and preserves paths with spaces" {
  load_sort_worktrees
  run sort_worktrees name false <<< $'/zzz/alpha tree\tfeature/z\n/aaa/zulu tree\tfeature/a'
  [ "$status" -eq 0 ]
  [ "$output" = $'/zzz/alpha tree\tfeature/z\n/aaa/zulu tree\tfeature/a' ]
  run sort_worktrees branch false <<< $'/zzz/alpha tree\tfeature/z\n/aaa/zulu tree\tfeature/a'
  [ "$status" -eq 0 ]
  [ "$output" = $'/aaa/zulu tree\tfeature/a\n/zzz/alpha tree\tfeature/z' ]
}

@test "sort_worktrees: empty input succeeds without manufacturing records" {
  load_sort_worktrees
  run sort_worktrees created false < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
