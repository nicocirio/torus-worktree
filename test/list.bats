#!/usr/bin/env bats

load test_helper

@test "list: shows the NAME/BRANCH/CREATED/LAST COMMIT header and marks the current worktree" {
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"*"BRANCH"*"CREATED"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
}

@test "list: shows LAST COMMIT once a commit lands in a worktree after it was created" {
  make_worktree foo
  git -C "$TEST_ROOT/foo" commit -q --allow-empty -m "work in foo"
  run "$WT" list
  [ "$status" -eq 0 ]
  foo_line="$(awk '$1 == "foo"' <<< "$output")"
  [[ "$foo_line" != *"—"* ]]
}

@test "list: hides LAST COMMIT when the branch's history predates the worktree" {
  git branch old-branch
  sleep 2
  git worktree add -q "$TEST_ROOT/stale" old-branch
  run "$WT" list
  [ "$status" -eq 0 ]
  stale_line="$(awk '$1 == "stale"' <<< "$output")"
  [[ "$stale_line" == *"—"* ]]
}

@test "list: shows other worktrees, without the (current) marker" {
  make_worktree foo
  make_detached_worktree bar
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"*"foo"* ]]
  [[ "$output" == *"bar"*"(detached)"* ]]
  # only the base row gets "(current)"
  [ "$(grep -c '(current)' <<< "$output")" -eq 1 ]
}

@test "list: rejects an unknown option" {
  run "$WT" list --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for list"* ]]
}

@test "list --size: shows a SIZE column and still marks the current worktree" {
  make_worktree foo
  run "$WT" list --size
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIZE"*"NAME"*"BRANCH"*"CREATED"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master"*"(current)"* ]]
  [[ "$output" == *"foo"*"foo"* ]]
}

@test "list: missing registered worktree does not abort the table" {
  make_worktree gone
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  run "$WT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master (current)"* ]]
  gone_line="$(awk '$1 == "gone"' <<< "$output")"
  [[ "$gone_line" == *"gone (missing)"*"—"*"—" ]]
  [ "$(grep -o '(missing)' <<< "$gone_line" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "list --size: missing registered worktree shows unknown size and dates" {
  make_worktree gone
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  run "$WT" list --size
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIZE"*"NAME"*"LAST COMMIT"* ]]
  [[ "$output" == *"base"*"master (current)"* ]]
  gone_line="$(awk '$2 == "gone"' <<< "$output")"
  [[ "$gone_line" == "—"*"gone (missing)"*"—"*"—" ]]
}

load support/sort_fixtures

@test "list: defaults to newest-created first, including with --size" {
  make_sort_fixture
  run "$WT" list
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'new\nold\nbase' ]
  run "$WT" list --size
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 2 {print $2}' <<< "$output")" = $'new\nold\nbase' ]
}

@test "list: reverse without sort uses oldest-created first" {
  make_sort_fixture
  run "$WT" list --reverse
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'base\nold\nnew' ]
}

@test "list: name, branch, created and last-commit select distinct orderings" {
  make_sort_fixture
  run "$WT" list --sort=name
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'base\nnew\nold' ]
  run "$WT" list --sort=branch
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'old\nbase\nnew' ]
  run "$WT" list --sort=created
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'new\nold\nbase' ]
  run "$WT" list --sort=last-commit
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 1 {print $1}' <<< "$output")" = $'old\nnew\nbase' ]
}

@test "list --size: explicit sort and reverse combine in any flag order" {
  make_sort_fixture
  run "$WT" list --reverse --size --sort=name
  [ "$status" -eq 0 ]
  [ "$(awk 'NR > 2 {print $2}' <<< "$output")" = $'old\nnew\nbase' ]
}

@test "list: missing creation and hidden last commit stay last in either direction" {
  make_sort_fixture
  make_worktree gone
  mv "$TEST_ROOT/gone" "$TEST_ROOT/unregistered"
  git worktree add -q "$TEST_ROOT/stale" -b stale master
  for args in '--sort=created' '--sort=created --reverse'; do
    run "$WT" list $args
    [ "$status" -eq 0 ]
    [ "$(awk 'END {print $1}' <<< "$output")" = gone ]
  done
  for args in '--sort=last-commit' '--sort=last-commit --reverse'; do
    run "$WT" list $args
    [ "$status" -eq 0 ]
    [ "$(awk 'NR > 1 {print $1}' <<< "$output" | tail -2)" = $'gone\nstale' ]
  done
}

@test "list: invalid and empty sort values fail clearly" {
  for value in size bogus ''; do
    run "$WT" list "--sort=$value"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid sort key"*"name|branch|created|last-commit"* ]]
  done
}
