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
  `update`, `uninstall`), plus hidden `__complete-*` subcommands used only by
  the completion function.
- `run-server.sh` — standalone, deliberately not configurable. See "Why
  `run-server` isn't personal" below.
- `lib/worktree-port.sh` — shared `find_free_port` and `oli.env` port-sync
  helpers used by both commands.
- `completions/_worktree` — zsh-only tab completion (bash was explicitly
  scoped out — see "Shell completion" below).
- `install.sh` — clones a managed installation when run via curl, or wires up
  symlinks when run from an existing checkout.

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

### `node_modules`/`deps`: copy vs install

`auto` mode (default) compares the relevant lockfile (`yarn.lock`,
`package-lock.json`, `mix.lock`) byte-for-byte between the base worktree and
the new one. Identical → copy (near-instant via `cp -c` clonefile on APFS,
falling back to `cp -al` hardlinks, falling back to a plain copy).
Different or missing → install for real. This is safe specifically because
lockfile identity is a real correctness signal for these — unlike `_build`
(next section), where there's no equivalent "is this cache still valid"
check we can do cheaply.

### Why `_build` is NOT cached (but `gleam/build` is)

Tried hard to avoid the first `mix compile` being a full compile on every
new worktree:

1. Copy `_build` as-is → full recompile anyway (Mix's manifest tracks
   source mtimes; `git worktree add` stamps checkout time on every file,
   always newer than whatever the manifest recorded).
2. Copy `_build` + restore source mtimes to match the base → still a full
   recompile. Ruled out the mtime theory.
3. Elixir 1.19.2's `elixirc_options: [check_cwd: false]` (per
   [this post](https://ryanzidago.com/posts/reducing-elixir-worktree-setup-time-by-83-percent/),
   which documents Mix embedding the absolute project path in the compile
   manifest) → still a full recompile. The post itself warns this only
   fully worked for a plain Phoenix app in their tests; this project
   apparently has another source of manifest invalidation beyond cwd
   (suspect: `Oli.Cldr`'s compile-time locale generation, unconfirmed).

Conclusion: not worth chasing further for now (noted as a "Future idea" in
the README). `gleam/build`, by contrast, *does* benefit from being copied
first — gleam's own incremental compiler doesn't hit whatever invalidates
Mix's, confirmed by build times dropping from ~2-3s to ~0.1-0.2s.

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
  (`_build` caching, per-worktree DB, `worktree refresh`).
