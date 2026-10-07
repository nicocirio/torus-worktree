# Design notes

Why `worktree`/`wt`/`run-server` are built the way they are — decisions,
things we tried that didn't work, and bugs that taught us something. The
`README.md` one level up covers *what* this is and *how* to install/use it;
this doc is for *why*, aimed at whoever (including future us) needs to
understand or extend this tool quickly.

## Architecture at a glance

Five files, no dependencies beyond `bash`/`zsh` + git + the project's own
toolchain (yarn, npm, mix, gleam):

- `worktree.sh` — the main tool. A single script, dispatching on the first
  argument (`up`, `open`, `remove`, `rename`, `list`, `config`, `version`,
  `update`, `uninstall`, `help`), plus hidden `__complete-*` subcommands used
  only by the completion function.
- `run-server.sh` — standalone, deliberately not configurable. See "Why
  `run-server` isn't personal" below.
- `lib/worktree-port.sh` — shared `find_free_port` and `oli.env` port-sync
  helpers used by both commands.
- `completions/_worktree` — zsh-only tab completion (bash was explicitly
  scoped out — see "Shell completion" below).
- `install.sh` — clones a managed installation when run via curl, or wires up
  symlinks when run from an existing checkout.
- `test/` — the bats test suite (dev-only, see "Testing" below). Not part of
  what gets installed or run by end users.

`~/.local/bin/worktree`, `~/.local/bin/wt`, and `~/.local/bin/run-server`
are symlinks into this folder, not copies and not shell functions. See "Why
symlinks, not shell functions" below.

### Installation, update, and uninstall

`install.sh` makes `~/.local/share/torus-worktree` the default managed
installation directory and creates absolute symlinks in `~/.local/bin`. It
can also run from a checkout directly, which is useful for contributors. A
small ignored `.torus-worktree-install` marker distinguishes a managed copy
from an arbitrary development checkout so `uninstall` cannot remove the
latter accidentally.

The installer offers zsh completion only when zsh is the current shell. Its
write is deliberately non-fatal: a missing zsh binary, a declined prompt, or
a failure to update `.zshrc` prints an explanation but leaves the command
installation intact. The completion lines are wrapped in unique markers so
`uninstall` can remove only the block it owns, without touching unrelated
shell configuration.

Git is the version source of truth: `version` prints `git describe` (a release
tag when available, otherwise the commit), and `update` fetches `origin/main`
then fast-forwards only when the installation is clean and still on `main`.
This avoids a separate version file that could drift from the code. `uninstall`
removes only symlinks that still point at the managed copy, then removes that
copy after confirmation; personal config survives unless `--purge-config` is
requested.

## Testing

`bats-core` (`brew install bats-core`), not a hand-rolled harness — it's the
standard for testing shell CLIs specifically (setup/teardown per test,
`run`/`$status`/`$output` assertions), and it's a dev-only dependency: never
installed or required to actually use `worktree`/`wt`/`run-server`, same
category as needing `git` to develop this repo at all. Coverage: `remove`
(`test/remove.bats`, `test/select_interactive.bats`), the `__complete-*`
data layer (`test/completion_data.bats` — the zsh widget itself, `_describe`
et al., is not covered; see below), `list`, `rename`, `config`, `version`,
`open` (`test/list.bats`, `test/rename.bats`, `test/config.bats`,
`test/open.bats`), `update`/`uninstall`
(`test/update_uninstall.bats`, against a disposable fake install — see
below), and `up` (`test/up.bats`, against stubbed
`yarn`/`npm`/`mix`/`gleam`/`elixir` — `test/support/toolchain_stubs.bash` — instead
of the real oli-torus toolchain: each stub just does the minimal thing
`worktree.sh`'s own logic depends on seeing afterward, e.g. that
`node_modules/` exists, and logs its invocation so a test can assert
whether it actually ran; `MIX_STUB_FAIL`/etc. let a specific test make one
stub fail, to exercise the "a job failed" reporting path). Every
subcommand has at least some coverage now.

The narrow binary-manifest rewrite has its own `test/patch_mix_manifest_cwd.bats`.
Unlike the orchestration tests, it uses the pinned Erlang/Elixir 1.19.2
toolchain to create and inspect a real Erlang term, covering both the exact
cwd-only rewrite and rejection of malformed input without overwriting it.

Every test gets its own throwaway repo satisfying the oli-torus guard (fake
`mix.exs`/`assets/automation/`/`gleam/gleam.toml`) and its own fake `$HOME`
(`test/test_helper.bash`), so the suite can't read or write the developer's
real `~/.config/torus-worktree`, `~/.cache/torus-worktree`, or worktrees —
same reasoning as the repo-identity guard in `worktree.sh` itself, applied to
testing. The fake `$HOME` also gets a no-op `osascript` stub on `$PATH`,
since `open`/`up`'s "worktree ready" dialog (see "macOS notification" below)
would otherwise pop a real dialog on the developer's screen during every
`open`/`up` test.

`remove --select` hard-requires a real terminal (`-t 0`/`-t 1`), which bats'
plain `run` doesn't provide. `test/support/run_select.exp` drives it through
an actual pty via `expect`, sending each queued input at whichever prompt
(the picker's `> ` or a trailing `[y/N] ` confirmation) appears next — this
is also how the `set -e`/bare-`&&`-as-last-statement regression (see "Bugs
we hit" below) got a permanent regression test
(`select: toggling the LAST-listed item...`), since that bug only reproduced
through a real interactive run, never through static analysis or a
non-interactive one-shot command.

`update`/`uninstall` operate on `$TOOL_ROOT` — wherever the invoked
`worktree.sh` physically lives — and `uninstall` does `rm -rf "$TOOL_ROOT"`,
so testing them against the real dev checkout is out of the question.
`test/support/fake_install.bash` builds a full disposable copy instead (its
own git history, its own bare "origin" remote, `$HOME/.local/bin` symlinks
wired up exactly like `install.sh` would), and that's what surfaced the
`remove_zsh_completion` bug below — a fresh fake install's `$HOME` has no
`.zshrc`, a state real developer machines essentially never have but a
clean test fixture always starts in.

Tab completion's zsh widget itself (`_describe`, `compadd`, the `case` that
picks what to complete at which position) isn't covered — zsh has its own
mechanism for this (`zpty`, the same one its own test suite uses via
`comptest`, driving a real interactive zsh through a pty and reading back
what actually got completed), but it's meaningfully more complex and
fragile to maintain than everything above, so it was deliberately scoped
out for now in favor of just testing the plain-bash data the widget
consumes (`__complete-*`).

## Key decisions and why

### Why symlinks in `~/.local/bin`, not shell functions in `.zshrc`

Early on this lived as two lines in `~/.zshrc`
(`worktree-up() { ~/dev-tools/.../worktree-up.sh "$@"; }`). Moved to
symlinks instead because: a shell function only exists in an interactive
shell that has sourced the rc file — it doesn't work from scripts, doesn't
survive `sh -c`, and requires editing a dotfile every time you add a
command. A symlink in a directory already on `$PATH` works everywhere a
normal command would, needs zero dotfile edits, and updates automatically
when the underlying script changes (it's a pointer, not a copy — editing
`worktree.sh` is instantly live under both `worktree` and `wt`).

`~/.local/bin` specifically because it's a common convention (same family
as `~/.config`, `~/.local/share`) already on this machine's `$PATH` from
other tools (`pipx`, etc.) — not guaranteed on a teammate's machine, hence
the README's setup step to check/add it.

### Why `wt` is a second symlink, not an alias

A shell `alias` only exists in the interactive shell that defined it. A
second symlink (`wt -> worktree.sh`, same target as `worktree`) works
identically to the main name, in any context, with zero duplicated code —
there is exactly one copy of the script on disk regardless of how many
names point at it.

### Repo-identity guard

`worktree` isn't tied to living inside the repo (works from any of *this
project's* worktrees), but it originally only checked "is this *any* git
repo" — which fails confusingly deep inside a parallel job's log (`cd:
assets: No such file or directory`) if run from an unrelated project.
Fixed by checking for `mix.exs` + `assets/automation/` + `gleam/gleam.toml`
right after resolving `$BASE_ROOT`, failing clearly and immediately if
they're missing.

### Worktree naming

Default name is the first `[A-Za-z]+-[0-9]+` ticket-like token found in the
branch name (e.g. `MER-1234` out of
`MER-1234-some-description`), no prefix. Used to default to `review-<ticket>`
but the prefix was dropped — not always a "review", and it's just noise.
Falls back to the sanitized full branch name (`/` → `-`) when no ticket
pattern matches. `worktree rename` exists precisely because this
auto-derived name isn't always descriptive enough, and git has no native
"rename" — it's `git worktree move` (updates git's internal
`.git/worktrees/<name>/gitdir` pointer correctly; a plain `mv` would leave
that stale). Verified safe to run even with a terminal or IDE's cwd
currently inside the worktree being renamed — a background process with
its cwd in the old path was still alive and its cwd (checked via `lsof`)
had already followed to the new path after the move. Not verified: how a
real IDE with open file editors reacts (editor-dependent, no way to test
headlessly here).

### `node_modules`/`deps`: copy vs install, or explicitly share assets

`auto` mode (default) compares the relevant lockfile (`yarn.lock`,
`package-lock.json`, `mix.lock`) byte-for-byte between the base worktree and
the new one. Identical → copy (using `cp -c` clonefile on APFS when
available, falling back to `cp -al` hardlinks, then a plain copy).
Different or missing → install for real. This is safe specifically because
lockfile identity is a real correctness signal for these — unlike `_build`
(below), where cache reuse also depends on compiler inputs and their mtimes.

`--assets-deps=link` is a deliberate opt-in exception for the particularly
large `assets/node_modules` tree. It links the base directory instead of
copying it only when both `assets/yarn.lock` **and** `assets/package.json`
match byte-for-byte. The package manifest is included because it can change
the dependency layout without a lockfile edit. The command warns before
creating the worktree that the linked directory is shared and must not be
modified there. If either file differs (or the base directory is absent), it
prints a second prominent warning and runs an isolated `yarn install`.

### `_build` caching on Elixir 1.19

Oli Torus currently pins Elixir 1.19.2. Mix 1.19's `compile.elixir` manifest
(version 29) stores the absolute project cwd. A copied `_build` therefore
looks stale as soon as a new worktree has a different path, even when its
source and dependency inputs are otherwise reusable.

`lib/patch_mix_manifest_cwd.exs` reads only that known manifest shape and
rewrites its cwd field to the new worktree path. It writes a temporary file
then renames it over the copied manifest. If the Elixir version is not 1.19.x,
the manifest is missing, or its shape is unexpected, priming safely falls
back to ordinary `mix compile` validation rather than guessing at another
Mix version's cache format.

There is a second cause of false invalidation: `git worktree add` gives the
new checkout fresh mtimes. Mix uses `mix.exs` and `config/*.exs` mtimes when
evaluating compile configuration, and Oli's development configuration has
dynamic inputs. After checkout, the tool restores those mtimes only when a
target file is byte-for-byte identical to the base file. A real branch
change is deliberately left untouched, so Mix still detects it. Finally,
`mix compile` always runs; the compiler, not this tool, decides whether the
reused build is valid and which genuine source/config/dependency changes need
recompilation.

This made a matching warm Oli worktree avoid the prior 1,783-file rebuild;
subsequent `mix compile` was a no-op. `gleam/build` remains independently
primed before its always-run incremental build.

### Setup timing report

The final timing report uses wall-clock time, not a sum of its parallel jobs.
It shows preparation, the sequential Mix dependency step, the duration of
the parallel section, and the job that formed its critical path. Individual
job times explain where the wall-clock time went but must not be added
together. `timings.log` records each stage's start and end offsets for more
precise inspection after a run. This made it clear that a perceived pause
after Mix printed `Generated oli app` could be the still-running assets copy,
not the compiler.

### Job ordering: deps sync can't run parallel with `assets`

Real bug, found via a real failure (`yarn install` in a fresh worktree
failing with `Package "phoenix_html" refers to a non-existing file
".../deps/phoenix_html"`). Cause: `assets/package.json` has
`file:../deps/*` dependencies (phoenix, phoenix_html, phoenix_live_view,
etc.) — `yarn install` needs `deps/` to already exist. The `mix`/`deps`
sync used to run inside the same parallel `backend_job` as gleam+compile,
racing against `assets_job`'s `yarn install`. Fixed by pulling the deps
sync out and running it synchronously *before* the three parallel jobs
start (`assets`, `automation`, `backend` — the last now just gleam+compile).
`automation/package.json` has no such `file:` dependency, so it's unaffected.

### Port picking + `run-server`

For a new worktree, `SERVER_PORT` comes from `find_free_port`, starting from
`DEFAULT_PORT`, and is written to `oli.env` as `HTTP_PORT`, `PORT`, and
`PLAYWRIGHT_BASE_URL`. This lets the Phoenix server and Playwright, which run
from separate terminals, consume one shared port configuration. The "already
exists" guidance and final hint reuse the same value, so a run never suggests
two different ports for the same worktree.

`open` deliberately reuses the port already recorded in that worktree's
`oli.env`, without checking whether it is free. An existing worktree may have
its Phoenix server running on that port; treating that listener as a
collision and selecting another port would rewrite the browser/Playwright
configuration while the live server remained on the original port. Only
`run-server`, which is about to start the process, may reassign a port when
the configured one is unavailable. For worktrees made before the three
values were synchronized, `open` also recognizes the port embedded in the
older `PLAYWRIGHT_BASE_URL` setting and migrates it in place.

Before it starts Phoenix, `run-server` validates the port declarations in
`oli.env`. `HTTP_PORT` is authoritative because it controls the listener;
when `PORT` or the explicit port in `PLAYWRIGHT_BASE_URL` disagrees, it prints
the mismatch and normalizes all three values to `HTTP_PORT`. For older
worktrees missing `HTTP_PORT`, it falls back to `PORT` and then to the port in
`PLAYWRIGHT_BASE_URL`. Only after this reconciliation does it check whether
the selected port is available and, if necessary, assign the next free port.

### Why `PLAYWRIGHT_BASE_URL` uses `localhost`, not `127.0.0.1`

`sync_worktree_port_env` (and `run-server`'s own exported copy of the
variable) write `PLAYWRIGHT_BASE_URL` as `http://localhost:<port>` to match
`HOST`, which `oli-torus` defaults to `localhost` (`config/dev.exs`,
`oli.example.env`) and uses to build absolute URLs for OAuth/LTI/payment
redirect flows. Phoenix session cookies are host-scoped with no explicit
`domain`, so if the browser loads the app via one host string while a
redirect sends it to an absolute URL built from a *different* host string,
the browser treats it as a different origin and drops the session —
`check_origin: false` in dev only stops Phoenix from rejecting the request
server-side, it doesn't stop the browser from silently switching origins.
Originally hardcoded to `127.0.0.1`, which happened to also mismatch
`run-server`'s own "Starting Phoenix at http://localhost:$port" message.

### Why `run-server` isn't personal

Originally the idea was a configurable `SERVER_CMD` (personal override,
defaulting to the user's own `~/.zshrc` `server()` function). Dropped in
favor of a fixed, universal `run-server` for two reasons: (1) not everyone
has that personal function, and (2) it sidesteps a real question
that came up — *where* does an auto-started server actually live? A
background job from the setup script has no visible terminal; killing that
terminal would `SIGHUP` it despite `disown` unless explicitly `nohup`'d.
Rather than solve process/terminal ownership, `worktree`/`wt` never starts
the server at all — it only tells you the free port, and `run-server`
is something *you* run, in whichever terminal (or IDE-integrated terminal)
you want it to live in.

### `oli.env`/`postgres.env`/`seeds.json` are copied explicitly

Gitignored, so `git worktree add` (which only checks out tracked files)
never brings them — without this, `run-server` would fail outright
(missing `oli.env`). On copy/open we rewrite `HTTP_PORT`, `PORT`, and
`PLAYWRIGHT_BASE_URL` together so the server and Playwright agree on the
worktree's port.

### DB/MinIO are shared, not per-worktree

Explicit, deliberate scope cut — same Postgres, same MinIO buckets across
all worktrees. Fine as long as branches don't have conflicting migrations
against the same dev DB; flagged as a "Future idea" in the README if that
becomes a real problem.

### "Already exists" → offer to open, don't just fail

Two collision points — the destination path already exists, or `git
worktree add` fails because the branch is checked out elsewhere (git's own
error names the other path) — both now default to "open it instead?"
rather than a dead-end error. `worktree open <name-or-branch>` makes this
explicit and intentional rather than incidental: resolves either a
worktree's folder name or the branch it has checked out (so renaming a
worktree with `rename` doesn't break your ability to find it later by its
branch). All three paths funnel through one `open_existing_worktree`
function — sync the port into `oli.env`, print the `run-server` hint,
notify, open the IDE — so behavior (and now notification wording) stays
consistent regardless of which path got you there.

### `remove --select` / `--all`: batch removal, no external picker

Removing worktrees one at a time, each with its own "also delete the
branch?" prompt, doesn't scale once you're juggling a dozen throwaway
worktrees (e.g. one per exploratory branch). `remove` now accepts multiple
names in one call, plus `--select` (an interactive numbered checkbox
picker) and `--all` (every worktree except the current one) as alternative
ways to build the same list of targets. All three funnel into one batch:
remove everything, then ask about branch deletion **once** for the whole
batch (or skip the question entirely via `--delete-branches`/
`--keep-branches`), instead of once per worktree. `--force` does the same
for the "contains modified or untracked files" retry — one bulk force
instead of a retry prompt per dirty worktree.

`--select` is deliberately implemented in plain bash — no `fzf` or other
external dependency — consistent with the rest of the tool. It's a numbered
list (toggle with `2`, `2 5 7`, or a range like `4-6`; `a`/`n`/`d`/`q`),
redrawn via `clear` each time input is processed. Less slick than a real
TUI, but it works everywhere bash 3.2 does (macOS's system bash) with zero
setup. It hard-requires a real terminal (`-t 0`/`-t 1`) and errors out
immediately with a pointer to `--all`/named args otherwise, rather than
hanging on unreadable input.

**Bug this surfaced**: a `set -e`/bare-`&&`-as-last-statement interaction
that silently killed the whole script whenever the last-listed worktree was
left unchecked — see "Bugs we hit" below for the full writeup.

### Setup logs live in `~/.cache/`, not inside the worktree

Originally `$WORKTREE_PATH/.worktree-setup/`. Moved out because a log dir
*inside* the worktree always shows up as untracked in `git status` — for
literally every worktree, for anyone using this tool — which meant `git
worktree remove` *always* needed `--force`, masking the case where `--force`
should actually mean something (real uncommitted work). Now:
`~/.cache/torus-worktree/logs/<name>/`, printed at the start of setup and on
any failure so it's still discoverable in the moment; `worktree remove`
cleans up the corresponding log dir since it no longer disappears with the
worktree automatically.

### macOS notification: `display notification` → `display dialog`

Wanted a "ready" notification that doesn't auto-dismiss. `display
notification` (Notification Center banner) always follows the OS's
per-app Banners/Alerts setting — not controllable from a script, and
changing it means going into System Settings (explicitly ruled out: "no
quiero tener que configurar nada en mi macOS"). `display dialog` (a modal
window) stays up until dismissed regardless of any system setting — the
tradeoff is it's blocking by nature (osascript waits for the click), so
it's launched in a background subshell (`( osascript ... & )`) so the main
script never waits on it. Final format: title "Worktree ready" (renders
bold/prominent — the closest thing to real emphasis this API offers, since
the dialog body itself is plain text with no rich formatting at all), body
built with explicit `return` concatenation for line breaks:
`Worktree name: <name>`, `Branch: <branch>`, blank line, then the
`run-server` hint.

### Shared list/removal sorting

`list` and every removal mode use the same path/branch record sorter, defaulting
to `created` newest first. Numeric epoch keys avoid ordering by rounded labels
(e.g. two "2 days ago" values can still differ). `last-commit` uses the display's
eligibility rule: a commit predating checkout creation is unknown, rather than
recent work in that checkout. Unknown date keys form a separate final group,
so `--reverse` never pulls missing dates to the top. Full paths break ties in
ascending byte order to keep picker numbering deterministic. Completion data
keeps its existing order; sorting is applied by the user-facing commands.

The interface follows the existing `--assets-deps=MODE` spelling for valued
options and boolean flags for toggles. Named removal targets are validated and
deduplicated before sorting; `--all` and `--select` preserve the same order from
their preview through removal. Dirty targets still follow the existing deferred
batch confirmation, so confirmed forced removals happen after clean removals.

### Shell completion (zsh only)

`#compdef worktree wt` + explicit `compdef _worktree worktree wt` in
`.zshrc` (not fpath+autoload — avoids ordering issues with `compinit`).
`up`'s completion offers both existing worktree names and branches in one
flat list (each candidate has its own inline description) since typing
either is valid for `up` — see "already exists → open instead" above.
`open`/`remove`/`rename` complete against worktree names only (`remove`,
`rename`) or names+branches (`open`, matching what it accepts). The static
commands `version` and `update` need no argument completion; `uninstall`
also offers `--purge-config`.

Bash completion was explicitly scoped out — the zsh function uses
`_describe`, `${(f)...}`, etc. with no bash equivalent; documented as "ask
if you need it" in `--help` rather than half-implemented.

## Bugs we hit (and what they taught us)

- **`read` + EOF + `set -e` = silent early exit.** A `read -p ... var`
  that hits EOF (no more piped input) returns non-zero — under `set -e`,
  that kills the script *after* whatever already printed a success
  message, making a genuinely successful operation report exit code 1.
  Every interactive `read` in the script now ends in `|| true`.
- **`local a=$1 b=${2:-$(fn "$a")}` doesn't work.** Under `set -u`,
  referencing `$a` while computing `b`'s default in the *same* `local`
  statement can see `a` as still-unset. Split into two separate `local`
  statements instead of relying on assignment order within one.
- **Bare `$var:word` in zsh can parse as a modifier, not literal text.**
  `"$raw:existing worktree"` got silently mangled to `"xisting worktree"`
  — zsh parsed `$raw:e` as the `:e` (extension) parameter-expansion
  modifier, consumed it, and left the remainder of the literal string.
  Fix: brace the variable — `"${raw}:existing worktree"` — so the colon
  is unambiguously outside the expansion. This one looked exactly like a
  `zstyle`/tag-order filtering issue at first (a whole completion group
  silently missing); it was actually just string corruption. Worth
  reproducing with a minimal, non-interactive repro (`functions
  _worktree` to check what's actually loaded, then a small test function
  printing the array before calling `_describe`) before assuming the
  zstyle config is the culprit.
- **A function ending on a bare `for ... && action` returns whatever that
  loop's last iteration returned.** `select_worktrees_interactively`'s final
  loop built `$SELECTED_TARGETS` with `[[ checked ]] && SELECTED_TARGETS+=(...)`
  and nothing after it — whenever the *last-listed* worktree was left
  unchecked, that final `&&` evaluated false, the function's implicit return
  status was non-zero, and calling it as a plain statement in the caller
  killed the entire script under `set -e`, silently, with no error message.
  Only reproduced with a real interactive run (see "Testing" above); a
  non-interactive one-shot test never exercises this loop at all. Fixed with
  an explicit `return 0` at the end of the function. General lesson: never
  let a function's final statement be a bare `&&`/`||` list whose truth
  value depends on data — end on something deterministic.
- **`mktemp -d` on macOS returns an unresolved path.** `/var/folders/...`
  is a symlink to `/private/var/folders/...`; `git worktree list` reports
  the resolved form, so a test helper comparing raw `mktemp -d` output
  against git's output silently never matched (every "worktree still
  exists" assertion failed, even when it did). Fixed by resolving with
  `cd "$dir" && pwd -P` immediately after creating it. The same
  unresolved-path issue also broke a test fixture's own `ln -sfn` target,
  which is a separate but related lesson: whenever you compare or store a
  path that has to line up with something git (or another tool) reports
  back resolved, canonicalize it immediately after `mktemp -d`, not later.
- **`grep -v` on zero input lines exits 1 — deadly under `pipefail`.**
  `__complete-branches` piped `git for-each-ref refs/remotes/origin` (empty
  when there's no `origin` remote, or no remote branches at all) into
  `grep -v '^origin/HEAD$'` — grep exits 1 when it has nothing to read,
  and with `pipefail` that took the whole script down in silence, before
  it ever printed anything. Never manifested against the real oli-torus
  repo (it always has `origin`), only surfaced once a test spun up a repo
  with no remote configured at all. Fixed with a trailing `|| true`.
- **A bare `return` reuses the exit status of whatever just failed the
  test before it — same class of bug as the `remove --select` regression
  above, found the same way (a real execution, not code review).**
  `remove_zsh_completion` did `[[ -f "$zshrc" ]] || return` — when there's
  no `.zshrc`, that `return` carries the `1` from the failed `-f` test,
  and since the function is called as a plain statement in
  `cmd_uninstall`, that `1` killed the entire uninstall under `set -e`
  before it ever removed anything or printed a result — silently, and
  only for a `$HOME` with no `.zshrc` at all, which never happens on a
  real dev machine but is exactly the default state of a fresh test
  fixture. Fixed with an explicit `return 0`. Same general lesson as
  before, restated because it recurred: an implicit/inherited exit status
  on an early return or a function's last statement is never safe when
  that status depends on data — make it explicit.
- **Same failure mode again, this time in a plain `var="$(pipe)"`
  assignment.** `up`'s "branch not found" path computed
  `default_branch="$(git symbolic-ref ... refs/remotes/origin/HEAD | sed
  ...)"` to suggest creating the branch from origin's default — when
  there's no `origin/HEAD` ref (no remote configured at all, or one whose
  default branch was never recorded), `symbolic-ref` exits 1, and under
  `pipefail` that failure is the assignment statement's own exit status.
  A bare `var=$(...)` assignment is not exempt from `set -e` just because
  it's "only an assignment" — it killed `up` silently, before ever
  showing the "not found, create it?" prompt, for any branch that doesn't
  exist locally or on origin, whenever origin's default branch isn't on
  record. Real oli-torus checkouts almost always have it (`git clone` sets
  it during the clone), so this hid well in practice; a test repo with no
  remote at all hits it immediately. Fixed with a trailing `|| true`. This
  is the fourth bug this exact shape has produced — worth treating "does
  this command's ordinary, expected 'nothing to report' case exit
  non-zero, and is this statement exempt from set -e" as a standing
  question for every new `var=$(...)` or pipe added to this script, not
  just something to catch after the fact.

- **Registered worktrees can outlive their directories.** A temporary
  review checkout disappeared from `/tmp` but stayed in `git worktree list`.
  The date helper's `stat` then failed inside a process substitution; its
  caller's `read` saw EOF, and `set -e` killed `list` before the buffered
  table printed. Date lookup now returns placeholders when metadata is
  unavailable, and `list` labels missing paths explicitly. It keeps Git's
  registration visible instead of pruning it automatically: a path can
  also be temporarily unavailable (for example, on an unmounted disk).
  Explicit removal now validates against Git's registrations as well as
  directory existence, so a selected missing path can be passed to
  `git worktree remove`. That removes only the chosen registration, unlike
  a global `git worktree prune` which could affect unselected missing paths.

## Things we tried and reverted

- **Two `_describe -t <tag>` calls with distinct tags**, to color
  worktree-name vs branch candidates differently via
  `zstyle ':completion:*:<tag>' list-colors ...` set inside the completion
  function itself (no `.zshrc` line needed). Implemented, didn't visibly
  render differently for the user, reverted to a single flat `_describe`
  call with inline per-candidate descriptions instead. Tags themselves
  turned out not to be the risk we originally worried about (that was the
  `:e` modifier bug, above) — but the color payoff wasn't there either, so
  not worth the extra complexity right now.
- **`usage()` parsing its own header comment via `sed`.** Fragile —
  depended on exact header formatting staying in sync with a `sed` range
  pattern. Replaced with a plain heredoc as the single source of truth;
  the file's top comment is now just a one-line pointer to `usage()`.

## Known open items (identified, not yet implemented)

- **Broken personal config file.** `source "$CONFIG_FILE"` is
  unconditional — a syntax error in a hand-edited
  `~/.config/torus-worktree/config.sh` currently kills the whole script
  with a raw, confusing bash error instead of pointing at `worktree config`
  to regenerate it.
- **A real compile/test failure shouldn't block getting into the IDE.**
  If `mix compile` fails because of an actual bug in the branch's code
  (not a tool problem), `up` currently exits before ever reaching the IDE
  open / `run-server` hint — exactly when you'd most want to get in there
  and fix it. The rest of the environment (deps, the worktree itself) is
  still valid at that point.
- See the README's "Future ideas" section for larger-scope items
  (per-worktree DB, `worktree refresh`).
