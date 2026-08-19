# Fake yarn/npm/mix/gleam for testing `up` without the real oli-torus
# toolchain. Each stub just does the minimal thing worktree.sh's own logic
# depends on seeing afterward (e.g. that node_modules/ exists), and logs
# its invocation to $STUB_LOG so tests can assert whether it actually ran.
#
# Failure simulation: set YARN_STUB_FAIL / NPM_STUB_FAIL / GLEAM_STUB_FAIL
# (to anything) to make that stub exit 1. `mix` has two distinct call
# sites (deps.get, run synchronously before the parallel jobs, and
# compile, run inside the parallel "backend" job) — set MIX_STUB_FAIL to
# the specific subcommand to fail ("deps.get" or "compile"), not a bare
# flag, or you'll fail both and never reach the parallel-jobs phase at all.

make_toolchain_stubs() {
  STUB_LOG="$(mktemp -d)/stub.log"
  : > "$STUB_LOG"

  TOOLCHAIN_STUB_BIN="$(mktemp -d)"

  cat > "$TOOLCHAIN_STUB_BIN/yarn" <<STUB
#!/usr/bin/env bash
echo "yarn \$*" >> "$STUB_LOG"
[[ -n "\${YARN_STUB_FAIL:-}" ]] && exit 1
[[ "\$1" == "install" ]] && mkdir -p node_modules
exit 0
STUB

  cat > "$TOOLCHAIN_STUB_BIN/npm" <<STUB
#!/usr/bin/env bash
echo "npm \$*" >> "$STUB_LOG"
[[ -n "\${NPM_STUB_FAIL:-}" ]] && exit 1
[[ "\$1" == "i" ]] && mkdir -p node_modules
exit 0
STUB

  cat > "$TOOLCHAIN_STUB_BIN/mix" <<STUB
#!/usr/bin/env bash
echo "mix \$*" >> "$STUB_LOG"
[[ -n "\${MIX_STUB_FAIL:-}" && "\$1" == "\${MIX_STUB_FAIL:-}" ]] && exit 1
case "\$1" in
  deps.get) mkdir -p deps ;;
  compile) mkdir -p _build ;;
esac
exit 0
STUB

  cat > "$TOOLCHAIN_STUB_BIN/gleam" <<STUB
#!/usr/bin/env bash
echo "gleam \$*" >> "$STUB_LOG"
[[ -n "\${GLEAM_STUB_FAIL:-}" ]] && exit 1
[[ "\$1" == "build" ]] && mkdir -p build
exit 0
STUB

  chmod +x "$TOOLCHAIN_STUB_BIN"/{yarn,npm,mix,gleam}
  export PATH="$TOOLCHAIN_STUB_BIN:$PATH"
}

# make_up_ready_base — adds the lockfiles/package files worktree.sh's `up`
# expects to find (so `auto` mode's lockfile comparison has something real
# to compare, and `git worktree add` actually checks out these paths into
# new worktrees), and commits them.
make_up_ready_base() {
  mkdir -p "$BASE/assets/automation"
  echo '{}' > "$BASE/assets/package.json"
  echo 'lockfile-v1' > "$BASE/assets/yarn.lock"
  echo '{}' > "$BASE/assets/automation/package.json"
  echo 'lockfile-v1' > "$BASE/assets/automation/package-lock.json"
  echo 'mix-lockfile-v1' > "$BASE/mix.lock"
  git -C "$BASE" add -A
  git -C "$BASE" commit -qm "add lockfiles for up tests"
}
