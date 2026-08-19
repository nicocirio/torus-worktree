# Changelog

Notable changes to `torus-worktree`, aimed at anyone running `worktree
update` and wanting to know what changed. Format follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/). Versions are Git tags
(see `worktree version`) — entries land under **Unreleased** as they're
built, and get a version heading once tagged. For *why* something changed,
not just *what*, see `docs/design-notes.md`.

## [Unreleased]

### Added
- `worktree list` (with or without `--size`) and the `remove --select`
  picker now show CREATED and LAST COMMIT columns for every worktree.
  CREATED is the worktree directory's birth time; LAST COMMIT is the
  latest commit's date, but only shown when it's at-or-after the
  worktree's own creation — otherwise it's a branch with older history
  checked out into a fresh worktree, and showing that commit would
  misread as recent activity in this worktree. Both are cheap
  (`stat`/`git log -1`, no `du`), so they're on unconditionally, no new
  flag. Relative times only ever show minutes, hours, or days (e.g.
  "810 days ago") — no rounding up to weeks/months/years, which would
  have hidden how far apart two "1 week ago" entries could actually be.
- `worktree remove` accepts multiple names in one call, plus `--select`
  (a pure-bash interactive checkbox picker — no external dependency) and
  `--all` (every worktree but the current one) as alternative ways to
  build a batch. All three ask about branch deletion and dirty-worktree
  force-removal once for the whole batch instead of once per worktree;
  `--force`, `--delete-branches`, and `--keep-branches` apply to all three
  forms and skip those questions entirely for scripted use.
- A `worktree help` subcommand (same as `-h`/`--help`).
- `--help`/`-h` now complete at the top level too (`wt <Tab>` offers them
  alongside the subcommands), without breaking partial subcommand matching
  (`wt uni<Tab>` still filters to `uninstall`).
- zsh tab completion now also covers `version`, `update`, and `uninstall`
  (including `uninstall --purge-config`) — previously only `up`/`open`/
  `remove`/`rename`/`list`/`config` completed.
- A `bats` test suite (`test/`, dev-only — see the README's "Testing"
  section), covering `remove` (including `--select` through a real pty via
  `expect`), `list`, `rename`, `config`, `version`, `open`,
  `update`/`uninstall` (against a disposable fake install), and the
  `__complete-*` tab-completion data layer.
- Test coverage for `up` too, against stubbed `yarn`/`npm`/`mix`/`gleam`
  (`test/up.bats`, `test/support/toolchain_stubs.bash`) instead of the
  real oli-torus toolchain. Every subcommand now has at least some test
  coverage.

### Fixed
- `PLAYWRIGHT_BASE_URL` now uses `localhost` instead of `127.0.0.1`,
  matching `HOST` — the mismatch could silently drop the browser session
  on OAuth/LTI/payment redirect flows.
- `__complete-branches` no longer silently crashes tab completion on a
  repo with no `origin` remote configured.
- `worktree uninstall` no longer aborts partway (before removing anything)
  when `$HOME` has no `.zshrc`.
- `remove --select` no longer silently dies with no error message when the
  last-listed worktree is left unchecked (a `set -e` edge case).
- The README's install command now points at `main` (with a cache-busting
  query string) instead of the frozen `v0.1.0` tag, so a fresh install
  actually gets the latest code.
- `install.sh` re-execs the freshly cloned installer via `bash` explicitly,
  instead of relying on it already being executable.
- `install.sh`'s PATH-setup and zsh-completion prompts no longer fail when
  there's no readable terminal to prompt on — they skip with a clear
  message and leave the commands installed instead.
- `worktree up`'s "branch not found" prompt no longer silently aborts the
  whole command when there's no recorded default branch on `origin` (e.g.
  no remote configured at all).
- The uninstall safety-guard test no longer runs against the real dev
  checkout, which spuriously failed on any machine where `install.sh` was
  run in place from that checkout (a supported mode — it leaves a
  `.torus-worktree-install` marker right there). It now runs against a
  disposable never-installed copy instead
  (`test/support/fake_install.bash`'s `make_bare_checkout`).

## [0.1.0] — 2026-08-11

Initial release: `up`, `open`, `remove`, `rename`, `list`, `config`,
`version`, `update`, `uninstall`; managed installation via `install.sh`
(curl-based or from an existing checkout); zsh tab completion.
