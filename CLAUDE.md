# Working in this repo

`torus-worktree` is a personal dev-tool CLI (`worktree.sh`, bash 3.2 / macOS
only — see `docs/design-notes.md` for why). A few conventions to follow
without being asked each time:

- **Tests**: any behavior change needs a matching test in `test/*.bats`
  (one file per subcommand — `list.bats`, `up.bats`, etc.). Follow the
  existing style in the relevant file rather than introducing a new pattern.
- **Run the suite before considering work done** (and before pushing):
  `bats test/`.
- **CHANGELOG.md**: user-facing changes get an entry under `[Unreleased]`
  (`### Added`/`### Fixed`/etc., Keep a Changelog format). Add the commit
  hash to the entry in a small follow-up edit after the real commit lands —
  that's the existing pattern (see recent log entries), not a hash guessed
  in advance.
- **docs/design-notes.md** is where the *why* behind non-obvious decisions
  lives (platform quirks, rejected alternatives). Check it before assuming
  something is an oversight, and add to it when a decision needs that kind
  of justification.
- **README.md** and the `worktree help` text (inside `worktree.sh`) both
  describe user-facing behavior — keep them in sync with any command/flag
  change.
