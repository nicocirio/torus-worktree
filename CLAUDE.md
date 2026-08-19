# Working in this repo

`torus-worktree` is a personal dev-tool CLI (`worktree.sh`, bash 3.2 / macOS
only — see `docs/design-notes.md` for why). A few conventions to follow
without being asked each time:

- **Tests**: every commit that changes behavior needs a test that covers
  *that specific change* — a new `@test`, or an edit to an existing one's
  assertions. This applies just as much to a quick mid-conversation tweak
  or a refinement to something not pushed yet as to a new feature; "small"
  or "just a follow-up" is not an exemption.
  - One file per subcommand (`list.bats`, `up.bats`, etc.) — follow the
    existing style in the relevant file. A helper shared across
    subcommands (not tied to one) gets its own file named after it (e.g.
    `relative_time.bats`), rather than being skipped for not fitting
    neatly into either subcommand's file.
  - Name the specific assertion(s) that exercise the new behavior before
    treating it as covered. **Running `bats test/` and seeing it pass is
    a regression check, not test coverage** — it passes whether or not
    anything actually asserts the new behavior.
- **Test pacing**: while iterating, run only the relevant file(s) (e.g.
  `bats test/list.bats`) — fast feedback on the thing you're actually
  changing. Run the full `bats test/` exactly once, right before pushing
  (not after every small edit) — that's the actual regression gate.
- **CHANGELOG.md**: user-facing changes get an entry under `[Unreleased]`
  (`### Added`/`### Fixed`/etc., Keep a Changelog format), in the *same*
  commit as the change itself. No trailing commit hash in the entry — that
  used to require a second follow-up commit just to record it, wasn't worth
  it, and existing entries were cleaned up to match.
- **docs/design-notes.md** is where the *why* behind non-obvious decisions
  lives (platform quirks, rejected alternatives). Check it before assuming
  something is an oversight, and add to it when a decision needs that kind
  of justification.
- **README.md** and the `worktree help` text (inside `worktree.sh`) both
  describe user-facing behavior — keep them in sync with any command/flag
  change.
