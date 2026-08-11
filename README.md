# torus-worktree

A wrapper that extends `git worktree` for
[oli-torus](https://github.com/Simon-Initiative/oli-torus), to speed up
creating worktrees and simplify managing them — so you can work on several
branches in parallel without each one costing you a full `yarn install` /
`mix deps.get` / `mix compile` from scratch.

This is intentionally tailored to `oli-torus` and its local development
toolchain. In its current form, its worktrees share the same local Postgres
and MinIO instances.

This doc covers what it is and how to install/use it. For *why* it's built
the way it is — decisions, dead ends, bugs we hit — see
[`docs/design-notes.md`](docs/design-notes.md).

## The problem this solves

Working on more than one branch at a time normally means either constantly
switching branches in the same checkout (stashing/losing your place), or
manually creating a `git worktree`, then walking through the whole
environment setup by hand every time: `yarn` in `assets/`, `npm i` in
`assets/automation/`, `mix deps.get`, the Gleam build step, compiling,
copying over the `.env` files that aren't tracked in git, picking a free
port so it doesn't collide with whatever else you have running...

This tool automates all of that, and reuses what it can from your existing
checkout instead of redoing the work:
- `node_modules` (`assets/`, `assets/automation/`) and `deps` are **copied**
  from your existing checkout when the relevant lockfile matches exactly
  (instant, via clonefile/hardlink), and only actually re-installed when it
  doesn't.
- `gleam/build` is primed the same way before running `gleam build` — its
  incremental compilation benefits from the warm cache.
- `mix compile` always runs fully (tried caching `_build` across worktrees
  too; doesn't help for this project — see `worktree --help` for why), but
  it runs during setup instead of surprising you the first time you start
  the server.
- The gitignored `oli.env` / `postgres.env` / `seeds.json` get copied over,
  since `git worktree add` only brings tracked files.
- It picks a free port automatically and keeps `oli.env`'s `HTTP_PORT`,
  `PORT`, and `PLAYWRIGHT_BASE_URL` in sync with it.
- Setup logs live in `~/.cache/torus-worktree/logs/<name>/`, not inside the
  worktree — printed at the start of setup and on any failure. Kept outside
  on purpose: a log dir inside the worktree would always show up as
  untracked in `git status` and make `worktree remove` always need --force.
  `remove` cleans these up too.

Postgres and MinIO are **shared** across worktrees in this version (same DB,
same buckets) — not isolated per worktree. Fine as long as branches don't
have conflicting migrations against the same dev DB.

This is also what makes it practical to run **parallel Claude Code / Codex
sessions** on different branches at the same time — each worktree is a fully
independent checkout with its own environment and its own server, so one
agent's commits, running server, and in-progress changes never interfere
with another's.

## What's here

- `worktree.sh` — the main tool. Subcommands: `up` (create), `remove`,
  `list`, `config`. Run `worktree --help` for the full reference (flags,
  how the port/deps logic works, shell completion setup, etc.).
- `run-server.sh` — starts the Phoenix server using the port recorded in that
  worktree's `oli.env` (`run-server`), from inside whichever worktree you
  want to serve.
  Not personal/configurable on purpose, so it works the same for anyone.
- `completions/_worktree` — optional zsh tab-completion (branches for `up`,
  worktree names for `remove`).
- `lib/worktree-port.sh` — shared port discovery and `oli.env` synchronization
  used by both commands.

## Setup

1. Install it. This clones a managed copy into `~/.local/share/torus-worktree`
   and creates `worktree`, `wt`, and `run-server` symlinks in
   `~/.local/bin`:

   ```bash
   curl -fsSL "https://raw.githubusercontent.com/nicocirio/torus-worktree/main/install.sh?cachebust=$(date +%s)" | bash
   ```

   The installer offers to add `~/.local/bin` to your shell PATH if needed.
   To inspect it first instead, clone the repository and run `./install.sh`
   from its root.

2. Confirm it works:

   ```bash
   worktree --help
   ```

3. (Optional) Set your personal IDE command and default port:

   ```bash
   worktree config
   ```

4. The installer offers to enable zsh tab-completion when zsh is your current
   shell. It is optional: if zsh is unavailable or the setup cannot be
   written, `worktree`, `wt`, and `run-server` still work normally. To enable
   it later, see the "Shell completion" section of `worktree --help`.

## Basic usage

```bash
worktree config                       # optionally set your IDE command and preferred starting port
worktree up MER-1234-some-branch      # create a worktree, set it up, open your IDE
worktree open a-more-descriptive-name # jump straight to one you already have (by folder name or branch)
worktree list                         # see your worktrees (fast, no sizes)
worktree list --size                  # same, with disk usage per worktree
worktree rename MER-1234-some-branch a-more-descriptive-name  # rename the folder
worktree remove MER-1234-some-branch  # clean one up when you're done
run-server                            # from inside a worktree, start Phoenix on its assigned port
```

Run `worktree --help` for the full picture — every flag, how `up` behaves
when the branch or the worktree already exists, and the shell completion
setup.

## Updating and uninstalling

```bash
worktree version                   # show the installed commit or release tag
worktree update                    # fast-forward to the latest origin/main
worktree uninstall                 # remove commands and installed copy; keep personal config
worktree uninstall --purge-config  # also remove ~/.config/torus-worktree
```

`update` refuses to overwrite local changes in the installation. Releases
are identified with Git tags; until a tag exists, `version` shows the exact
commit.

## Future ideas

- **Avoid the first `mix compile` entirely.** Keep investigating whether
  `_build` can be replicated across worktrees so a fresh one doesn't need a
  full compile at all. Copying it as-is doesn't work for this project (see
  `worktree --help`), but there may be another angle worth trying (e.g. a
  persistent build server, or fixing whatever specifically invalidates the
  manifest beyond cwd).
- **Per-worktree dev DB.** Right now Postgres (and MinIO) are shared across
  all worktrees. If branches with conflicting migrations become a real
  problem, worth adding an option for an isolated DB (and MinIO bucket set)
  per worktree — at the cost of losing the "shared data across branches"
  convenience.
- **`worktree refresh <name>`.** Re-sync deps/gleam/`mix compile` against an
  *existing* worktree, for when the base's lockfiles or deps have moved on
  since that worktree was created and recreating it from scratch isn't
  worth it. Everything `up` already does for a new worktree would apply the
  same way to an existing one — mostly a matter of exposing it as its own
  subcommand.
