# Deterministic birth times: APFS birth time cannot be set with touch.
# Real worktrees/commits still exercise the CLI; only stat is stubbed.
make_sort_fixture() {
  export SORT_NOW="$(date +%s)"
  GIT_COMMITTER_DATE="@$((SORT_NOW - 5000)) +0000" git -C "$BASE" commit -q --amend --no-edit
  git -C "$BASE" branch a-branch
  git -C "$BASE" worktree add -q "$TEST_ROOT/old" a-branch
  git -C "$BASE" branch z-branch
  git -C "$BASE" worktree add -q "$TEST_ROOT/new" z-branch
  GIT_COMMITTER_DATE="@$((SORT_NOW - 30)) +0000" git -C "$TEST_ROOT/old" commit -q --allow-empty -m old
  GIT_COMMITTER_DATE="@$((SORT_NOW - 50)) +0000" git -C "$TEST_ROOT/new" commit -q --allow-empty -m new
  cat > "$STUB_BIN/stat" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == -f && ( "$2" == %B || "$2" == %m ) && -d "$3" ]]; then
  case "${3##*/}" in
    base) echo "$((SORT_NOW - 7200))"; exit 0 ;;
    old) echo "${SORT_OLD_CREATED:-$((SORT_NOW - 3600))}"; exit 0 ;;
    new) echo "$((SORT_NOW - 60))"; exit 0 ;;
    stale) echo "$((SORT_NOW - 1200))"; exit 0 ;;
  esac
fi
exec /usr/bin/stat "$@"
STUB
  chmod +x "$STUB_BIN/stat"
}
