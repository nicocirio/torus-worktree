# Changelog

Notable changes to `torus-worktree`, aimed at anyone running `worktree
update` and wanting to know what changed. Format follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/). Versions are Git tags
(see `worktree version`) — entries land under **Unreleased** as they're
built, and get a version heading once tagged. For *why* something changed,
not just *what*, see `docs/design-notes.md`.

## [Unreleased]

### Added
- `worktree remove` accepts multiple names in one call, plus `--select`
  (a pure-bash interactive checkbox picker — no external dependency) and
  `--all` (every worktree but the current one) as alternative ways to
  build a batch. All three ask about branch deletion and dirty-worktree
  force-removal once for the whole batch instead of once per worktree;
  `--force`, `--delete-branches`, and `--keep-branches` apply to all three
  forms and skip those questions entirely for scripted use. (1f2a23c)
- A `worktree help` subcommand (same as `-h`/`--help`). (db58dfd)
- `--help`/`-h` now complete at the top level too (`wt <Tab>` offers them
  alongside the subcommands), without breaking partial subcommand matching
  (`wt uni<Tab>` still filters to `uninstall`).
  (3f12aea, 95697b3, f0bdb5d, b784cab)
- zsh tab completion now also covers `version`, `update`, and `uninstall`
  (including `uninstall --purge-config`) — previously only `up`/`open`/
  `remove`/`rename`/`list`/`config` completed. (2cd58a5)
- A `bats` test suite (`test/`, dev-only — see the README's "Testing"
  section), covering `remove` (including `--select` through a real pty via
  `expect`), `list`, `rename`, `config`, `version`, `open`,
  `update`/`uninstall` (against a disposable fake install), and the
  `__complete-*` tab-completion data layer. (581f837, 7d4f598)
- Test coverage for `up` too, against stubbed `yarn`/`npm`/`mix`/`gleam`
  (`test/up.bats`, `test/support/toolchain_stubs.bash`) instead of the
  real oli-torus toolchain. Every subcommand now has at least some test
  coverage. (d3c507f)

### Fixed
- `PLAYWRIGHT_BASE_URL` now uses `localhost` instead of `127.0.0.1`,
  matching `HOST` — the mismatch could silently drop the browser session
  on OAuth/LTI/payment redirect flows. (343e839)
- `__complete-branches` no longer silently crashes tab completion on a
  repo with no `origin` remote configured. (97b4bff)
- `worktree uninstall` no longer aborts partway (before removing anything)
  when `$HOME` has no `.zshrc`. (97b4bff)
- `remove --select` no longer silently dies with no error message when the
  last-listed worktree is left unchecked (a `set -e` edge case). (1f2a23c)
- The README's install command now points at `main` (with a cache-busting
  query string) instead of the frozen `v0.1.0` tag, so a fresh install
  actually gets the latest code. (c9edf2a)
- `install.sh` re-execs the freshly cloned installer via `bash` explicitly,
  instead of relying on it already being executable. (ddd1070)
- `install.sh`'s PATH-setup and zsh-completion prompts no longer fail when
  there's no readable terminal to prompt on — they skip with a clear
  message and leave the commands installed instead. (7398669)
- `worktree up`'s "branch not found" prompt no longer silently aborts the
  whole command when there's no recorded default branch on `origin` (e.g.
  no remote configured at all). (a4a430f)

## [0.1.0] — 2026-08-11

Initial release: `up`, `open`, `remove`, `rename`, `list`, `config`,
`version`, `update`, `uninstall`; managed installation via `install.sh`
(curl-based or from an existing checkout); zsh tab completion.
