#!/usr/bin/env bats

load test_helper

load_created_epoch() {
  eval "$(sed -n '/^worktree_created_epoch() {/,/^}/p' "$WT")"
}

@test "worktree_created_epoch: reads directory birth time" {
  load_created_epoch
  expected="$(/usr/bin/stat -f %B "$BASE")"
  run worktree_created_epoch "$BASE"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "worktree_created_epoch: missing metadata is zero" {
  load_created_epoch
  run worktree_created_epoch "$TEST_ROOT/missing"
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
}

@test "worktree_created_epoch: failed or zero birth time falls back to mtime" {
  load_created_epoch
  stat() {
    case "$2" in
      %B) if [[ "$BIRTH_MODE" = zero ]]; then echo 0; else return 1; fi ;;
      %m) echo 1000000000 ;;
    esac
  }
  for BIRTH_MODE in zero failed; do
    run worktree_created_epoch "$BASE"
    [ "$status" -eq 0 ]
    [ "$output" = 1000000000 ]
  done
}
