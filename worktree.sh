#!/usr/bin/env bash
# Creates and manages git worktrees for this project — see `usage()` below
# (or run `worktree --help`) for the full rundown of subcommands.

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SCRIPT_SOURCE" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "$SCRIPT_DIR/lib/worktree-port.sh"

CONFIG_DIR="$HOME/.config/torus-worktree"
CONFIG_FILE="$CONFIG_DIR/config.sh"
TOOL_ROOT="$SCRIPT_DIR"

# Built-in defaults, used whenever $CONFIG_FILE doesn't exist or doesn't set a
# given variable. Personalize them by running: worktree config
BUILTIN_IDE_CMD='cursor "$WORKTREE_PATH" --profile=Second'
BUILTIN_DEFAULT_PORT=4001

IDE_CMD="$BUILTIN_IDE_CMD"
DEFAULT_PORT="$BUILTIN_DEFAULT_PORT"

HAS_CONFIG=false
if [[ -f "$CONFIG_FILE" ]]; then
  HAS_CONFIG=true
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

sh_single_quote() {
  local s="$1"
  printf "'%s'" "${s//\'/\'\\\'\'}"
}

write_config_file() {
  local ide_cmd="$1" port="$2"
  cat > "$CONFIG_FILE" <<EOF
# Personal settings for the worktree tool.
# Not part of the repo (lives outside it, in ~/.config/torus-worktree/).
# Regenerate with: worktree config

# Command to open your IDE in the new worktree. \$WORKTREE_PATH is available.
IDE_CMD=$(sh_single_quote "$ide_cmd")

# First port worktree checks when picking a free port to suggest for
# \`run-server\`. If it's taken, it walks forward until it finds a free one.
DEFAULT_PORT=$port
EOF
}

cmd_config() {
  mkdir -p "$CONFIG_DIR"

  echo "Configure your personal worktree settings."
  echo "Press Enter to keep the value shown as Current (or Example, if there's no Current)."
  echo

  echo "IDE command to open the new worktree (\$WORKTREE_PATH available)"
  $HAS_CONFIG && echo "  Current: $IDE_CMD"
  echo "  Example: $BUILTIN_IDE_CMD"
  read -r -p "> " input_ide_cmd || true
  new_ide_cmd="${input_ide_cmd:-$IDE_CMD}"
  echo

  echo "First port to try when picking a free port for \`run-server\`"
  $HAS_CONFIG && echo "  Current: $DEFAULT_PORT"
  echo "  Example: $BUILTIN_DEFAULT_PORT"
  new_port=""
  while true; do
    read -r -p "> " input_port || true
    new_port="${input_port:-$DEFAULT_PORT}"
    [[ "$new_port" =~ ^[0-9]+$ ]] && break
    echo "Please enter a number."
  done
  echo

  if $HAS_CONFIG; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
  fi

  write_config_file "$new_ide_cmd" "$new_port"
  echo "Saved $CONFIG_FILE"
}

cmd_version() {
  local version
  version="$(git -C "$TOOL_ROOT" describe --tags --always --dirty 2>/dev/null || echo "unknown")"
  echo "torus-worktree $version"
  echo "Installed at $TOOL_ROOT"
}

cmd_update() {
  if [[ -n "$(git -C "$TOOL_ROOT" status --porcelain)" ]]; then
    echo "Refusing to update: the tool installation has local changes." >&2
    echo "Commit, stash, or discard them first: $TOOL_ROOT" >&2
    exit 1
  fi

  local branch ahead behind
  branch="$(git -C "$TOOL_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ "$branch" != "main" ]]; then
    echo "Refusing to update: expected the main branch, found '${branch:-a detached commit}'." >&2
    exit 1
  fi

  git -C "$TOOL_ROOT" fetch --tags origin main
  read -r ahead behind < <(git -C "$TOOL_ROOT" rev-list --left-right --count HEAD...origin/main)

  if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
    echo "torus-worktree is already up to date."
    return
  fi

  if [[ "$ahead" != "0" ]]; then
    echo "Refusing to update: local main has diverged from origin/main." >&2
    exit 1
  fi

  git -C "$TOOL_ROOT" merge --ff-only origin/main
  echo "Updated torus-worktree to $(git -C "$TOOL_ROOT" describe --tags --always)."
}

remove_managed_link() {
  local link="$1" target="$2"
  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    rm "$link"
    echo "Removed $link"
  fi
}

remove_zsh_completion() {
  local zshrc="$HOME/.zshrc" tmp
  [[ -f "$zshrc" ]] || return
  tmp="$(mktemp "${zshrc}.torus-worktree.XXXXXX")"

  awk '
    /^# >>> torus-worktree completion >>>$/ { skipping = 1; next }
    /^# <<< torus-worktree completion <<<$/ { skipping = 0; next }
    !skipping { print }
  ' "$zshrc" > "$tmp"
  mv "$tmp" "$zshrc"
}

cmd_uninstall() {
  local purge_config=false
  for arg in "$@"; do
    case "$arg" in
      --purge-config) purge_config=true ;;
      *) echo "Unknown option for uninstall: $arg" >&2; exit 1 ;;
    esac
  done

  if [[ ! -f "$TOOL_ROOT/.torus-worktree-install" ]]; then
    echo "This checkout is not marked as an installed copy; refusing to remove it." >&2
    echo "It is safe to remove only the symlinks manually if that is what you intended." >&2
    exit 1
  fi

  echo "This removes the managed installation at $TOOL_ROOT."
  $purge_config && echo "It will also remove $CONFIG_DIR."
  read -r -p "Continue? [y/N] " choice || true
  if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    return
  fi

  remove_managed_link "$HOME/.local/bin/worktree" "$TOOL_ROOT/worktree.sh"
  remove_managed_link "$HOME/.local/bin/wt" "$TOOL_ROOT/worktree.sh"
  remove_managed_link "$HOME/.local/bin/run-server" "$TOOL_ROOT/run-server.sh"
  remove_zsh_completion
  rm -rf "$TOOL_ROOT"
  $purge_config && rm -rf "$CONFIG_DIR"
  echo "torus-worktree uninstalled."
}

usage() {
  cat <<'EOF'
Creates and manages git worktrees for this project: sets up their dev
environment (assets/, assets/automation/, mix deps, gleam, and compiling),
opens your IDE in them, and tells you the free port + command to start the
Phoenix server yourself. Also lists and removes worktrees you're done with.

`wt` is a short alias for `worktree` (same binary, same completion) — use
whichever you prefer.

Usage:
  worktree up <branch> [name] [options]
  worktree open <name-or-branch> [--no-ide] [--no-server]
  worktree remove <name>
  worktree rename <name> <new-name>
  worktree list [--size]
  worktree config
  worktree version
  worktree update
  worktree uninstall [--purge-config]
  worktree help | -h | --help

up:
  Arguments:
    branch                   Branch to check out in the new worktree. Fetched
                             from origin automatically if not present locally.
    name                     Worktree directory name, created as a sibling of
                             this repo (../<name>). Defaults to <TICKET> when
                             the branch name contains a ticket-like token
                             (e.g. MER-1234), otherwise the sanitized branch
                             name.

  Options:
    --assets-deps=MODE       auto (default) | copy | install
    --automation-deps=MODE   auto (default) | copy | install
    --mix-deps=MODE          auto (default) | copy | install
                             auto: copy node_modules/deps from this worktree
                             when the relevant lockfile is identical,
                             otherwise install for real. Doesn't apply to
                             _build (see below).
    --no-ide                 Skip opening the IDE.
    --no-server              Skip printing the "how to start the server" hint.

  Compiling (gitignored like node_modules/deps, so a fresh worktree has none):
    gleam/build   primed by copying it from this worktree first, then always
                  built (`gleam build --target erlang`) — gleam's incremental
                  compilation actually benefits from the warm cache.
    _build        NOT primed. Tried copying it (with mtime fixes and Elixir
                  1.19's check_cwd:false, per
                  https://ryanzidago.com/posts/reducing-elixir-worktree-setup-time-by-83-percent/)
                  — Mix still fully recompiles regardless, since this project
                  invalidates the manifest cache across worktree paths for
                  reasons beyond cwd (likely Cldr's compile-time locale
                  generation, among others). So `mix compile` here is always
                  a full compile — still worth running during setup rather
                  than at first `run-server`.

  Starting the server is not automated — run the printed `run-server` command
  yourself, from whichever terminal you want it to live in. The worktree's
  oli.env records the port it will use for Phoenix and Playwright.

  Shared across worktrees in this version (not isolated per worktree): the
  Postgres dev DB and the MinIO instance (ports 9000/9001).

  Setup logs (assets/automation/mix+gleam/mix-deps) live in
  ~/.cache/torus-worktree/logs/<name>/, not inside the worktree — printed at
  the start of setup and on any failure. Kept outside on purpose: a log dir
  inside the worktree would always show up as untracked in `git status` and
  make `remove` always need --force. `remove` cleans these up too.

open:
  worktree open <name-or-branch>
                             Jump straight to an existing worktree — the same
                             "already there, open it?" shortcut `up` falls
                             back to when the branch/path you gave it already
                             has a worktree, but explicit and without the
                             detour through branch/path resolution. Matches
                             either the worktree's folder name or the branch
                             it has checked out. Updates oli.env's
                             PLAYWRIGHT_BASE_URL with a freshly-checked free
                             port, prints the `run-server` hint, opens your
                             IDE — same as `up`. --no-ide / --no-server work
                             here too.

remove:
  worktree remove <name>     <name> is either a sibling directory name (like
                              the ones `up` creates) or a full path. Handles
                              the "contains modified or untracked files" error
                              by offering to retry with --force, and
                              separately offers to delete the local branch
                              (default no — that one's harder to undo).

rename:
  worktree rename <name> <new-name>
                             Uses `git worktree move` (not a plain `mv`),
                             so git's internal bookkeeping stays correct.
                             <new-name> must be letters/numbers/'.'/'_'/'-'
                             only — no spaces or slashes, since it becomes a
                             directory name. Safe even if a terminal or IDE
                             currently has that worktree open — processes
                             follow the move automatically, they don't lock
                             the directory.

list:
  worktree list               Fast — just the path/branch of each worktree,
                               no disk usage. Doesn't shell out to `du`.
  worktree list --size        Also shows disk usage per worktree (`du -sh`,
                               run in parallel across all of them so the wait
                               is bounded by the single biggest one, not the
                               sum — still not instant, expect a few seconds
                               with node_modules-sized trees).

config:
  Create/regenerate ~/.config/torus-worktree/config.sh, the personal
  overrides for IDE_CMD and DEFAULT_PORT. Optional — everything else works
  fine with the built-in defaults.

version:
  Show the installed tool version (the nearest Git tag or exact commit) and
  its installation path.

update:
  Fetch origin/main and fast-forward the installed tool when a newer version
  is available. Refuses to update when the installation has local changes or
  is not on main.

uninstall:
  Remove this managed installation and its worktree/wt/run-server symlinks
  and its installer-managed zsh completion after confirmation. Personal
  settings in ~/.config/torus-worktree are kept by default; pass
  --purge-config to remove them too.

Shell completion (tab-complete subcommands, branches for `up`, worktree names
for `open`/`remove`/`rename`, and `uninstall --purge-config`) — optional,
purely a convenience, everything above works fine without it:
  zsh (default on modern macOS):
    Add these two lines near the end of ~/.zshrc, then open a new terminal:
      source /path/to/completions/_worktree
      compdef _worktree worktree wt
    (adjust the path to wherever completions/_worktree actually lives on
    your machine — same folder as this script, under completions/. Drop
    " wt" from the compdef line if you didn't set up that alias.)

  bash: not implemented. The completion function above is zsh-specific
  (uses `_describe`, `${(f)...}`, etc.) — a bash version would need
  `complete -F` and a different function body. Ask if you need it.
EOF
}

SUBCOMMAND="${1:-}"
[[ $# -gt 0 ]] && shift

case "$SUBCOMMAND" in
  config)
    cmd_config
    exit 0
    ;;
  version)
    cmd_version
    exit 0
    ;;
  update)
    cmd_update
    exit 0
    ;;
  uninstall)
    cmd_uninstall "$@"
    exit 0
    ;;
  help|-h|--help|"")
    usage
    exit 0
    ;;
esac

# The tool isn't tied to living inside the repo — it works from whichever
# checkout (any worktree) you run it from, and uses that one as the "base"
# to copy node_modules/deps from.
if ! BASE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "Run this from inside a checkout of this project (any worktree)." >&2
  exit 1
fi

# Guards against running this from some other, unrelated git repo — which
# would otherwise fail confusingly later (e.g. "cd: assets: No such file or
# directory" buried in a parallel job's log) instead of failing clearly here.
if [[ ! -f "$BASE_ROOT/mix.exs" ]] || [[ ! -d "$BASE_ROOT/assets/automation" ]] || [[ ! -f "$BASE_ROOT/gleam/gleam.toml" ]]; then
  echo "This doesn't look like the oli-torus repo (missing mix.exs, assets/automation/, or gleam/gleam.toml)." >&2
  echo "Run this from inside a checkout of that project instead." >&2
  exit 1
fi

log() { echo "[$1] ${*:2}"; }

# list_worktrees — path<TAB>branch, one per line, one per worktree. Parses
# --porcelain instead of the human-readable columns, which don't survive
# whitespace in paths/branch names as cleanly.
list_worktrees() {
  git -C "$BASE_ROOT" worktree list --porcelain | awk '
    /^worktree / { path=substr($0, 10) }
    /^branch /   { branch=substr($0, 8); sub("refs/heads/", "", branch) }
    /^detached$/ { branch="(detached)" }
    /^$/         { if (path != "") print path "\t" branch; path=""; branch="" }
    END          { if (path != "") print path "\t" branch }
  '
}

# Shared by `open` and `up` (when it discovers the worktree it was about to
# create already exists) — moved up here so both can use them.
OPEN_IDE=true
OFFER_SERVER=true

# Initial candidate for a new worktree. `open` replaces it with an existing
# worktree's recorded port when one is available.
SERVER_PORT="$(find_free_port "${DEFAULT_PORT:-4001}")"

# read_worktree_port <worktree path> — returns the worktree's existing port,
# if it has one. Prefer the fully synchronized values, then the older
# Playwright-only setting so opening an active worktree made by a previous
# version never changes the port its server is already using.
read_worktree_port() {
  local env_file="$1/oli.env" http_port public_port playwright_url playwright_port
  [[ -f "$env_file" ]] || return 1

  http_port="$(awk -F= '$1 == "HTTP_PORT" { value=$2 } END { print value }' "$env_file")"
  public_port="$(awk -F= '$1 == "PORT" { value=$2 } END { print value }' "$env_file")"
  playwright_url="$(awk -F= '$1 == "PLAYWRIGHT_BASE_URL" { value=$2 } END { print value }' "$env_file")"

  if [[ "$http_port" =~ ^[0-9]+$ && "$http_port" == "$public_port" ]]; then
    echo "$http_port"
    return 0
  fi

  playwright_port="$(echo "$playwright_url" | sed -nE 's#^https?://[^/:]+:([0-9]+)(/.*)?$#\1#p')"
  if [[ "$playwright_port" =~ ^[0-9]+$ ]]; then
    echo "$playwright_port"
    return 0
  fi

  if [[ "$http_port" =~ ^[0-9]+$ ]]; then
    echo "$http_port"
    return 0
  fi

  if [[ "$public_port" =~ ^[0-9]+$ ]]; then
    echo "$public_port"
    return 0
  fi

  return 1
}

# Reuse an existing worktree's port even if its server currently occupies it.
# `open` is not an instruction to start a second server; changing the stored
# port here would make the browser and Playwright target diverge from the
# already-running Phoenix process. Only `run-server` may reassign a port,
# because it is about to start the process that will use it.
ensure_worktree_port() {
  local path="$1" existing_port
  if existing_port="$(read_worktree_port "$path")"; then
    SERVER_PORT="$existing_port"
  else
    SERVER_PORT="$(find_free_port "${DEFAULT_PORT:-4001}")"
  fi

  if [[ -f "$path/oli.env" ]]; then
    sync_worktree_port_env "$path/oli.env" "$SERVER_PORT"
  fi
}

# Opens a worktree directly — used by `open`, by `up` when the worktree it
# was about to create turns out to already exist (treats "already there" as
# a shortcut, instead of a dead end), and by `up`'s own success path once a
# new worktree finishes setup. So the macOS notification below fires for all
# three, not just the "created a brand new worktree" case.
open_existing_worktree() {
  local path="$1"
  local wt_name="${2:-$(basename "$path")}"
  local wt_branch="${3:-}"
  if [[ -z "$wt_branch" ]]; then
    wt_branch="$(list_worktrees | awk -F'\t' -v p="$path" '$1==p{print $2}')"
  fi

  ensure_worktree_port "$path"

  local hint=""
  if $OFFER_SERVER; then
    hint="From \"$path\", run \`run-server\` to start the server on http://localhost:$SERVER_PORT (that port is already confirmed free)."
    echo "$hint"
  fi

  if command -v osascript >/dev/null 2>&1; then
    # display dialog instead of display notification: notifications always
    # respect the system's per-app Banners/Alerts setting (uncontrollable
    # from here), auto-dismissing under Banners regardless of what we do.
    # A dialog stays up until dismissed, no matter what. It's also blocking
    # (osascript waits for the click), so it runs in the background — the
    # script keeps going (opening the IDE etc.) without waiting on it.
    local run_line="Ready."
    [[ -n "$hint" ]] && run_line="Run \`run-server\` to start it on http://localhost:$SERVER_PORT (already confirmed that port is free)."
    (
      osascript -e "display dialog \"Worktree name: $wt_name\" & return & \"Branch: $wt_branch\" & return & return & \"$run_line\" with title \"Worktree ready\" buttons {\"OK\"} default button \"OK\"" \
        >/dev/null 2>&1 &
    )
  fi

  if $OPEN_IDE; then
    if [[ -z "${IDE_CMD:-}" ]]; then
      echo "(IDE_CMD is empty in your config, skipping IDE launch)"
    else
      WORKTREE_PATH="$path" eval "$IDE_CMD"
    fi
  fi
}

case "$SUBCOMMAND" in
  list)
    show_size=false
    for arg in "$@"; do
      case "$arg" in
        --size) show_size=true ;;
        *) echo "Unknown option for list: $arg" >&2; exit 1 ;;
      esac
    done

    if ! $show_size; then
      rows=()
      NAME_HEADER="NAME"
      name_width=${#NAME_HEADER}
      while IFS=$'\t' read -r path branch; do
        name="$(basename "$path")"
        marker=""
        [[ "$path" == "$BASE_ROOT" ]] && marker=" (current)"
        (( ${#name} > name_width )) && name_width=${#name}
        rows+=("$name"$'\t'"$branch$marker")
      done < <(list_worktrees)
      printf "%-${name_width}s %s\n" "$NAME_HEADER" "BRANCH"
      for row in "${rows[@]}"; do
        IFS=$'\t' read -r name rest <<< "$row"
        printf "%-${name_width}s %s\n" "$name" "$rest"
      done
      exit 0
    fi

    echo "Calculating sizes in parallel (a few seconds)..."
    tmp_dir="$(mktemp -d)"
    i=0
    while IFS=$'\t' read -r path branch; do
      i=$((i + 1))
      idx="$(printf "%03d" "$i")"
      printf '%s\t%s\n' "$path" "$branch" > "$tmp_dir/$idx.meta"
      ( du -sh "$path" 2>/dev/null | cut -f1 > "$tmp_dir/$idx.size" ) &
    done < <(list_worktrees)
    wait

    # Two passes: first measure the widest name so columns line up whatever
    # `rename` (or the ticket-based default) produced, then print.
    NAME_HEADER="NAME"
    name_width=${#NAME_HEADER}
    for meta in "$tmp_dir"/*.meta; do
      IFS=$'\t' read -r path branch < "$meta"
      name="$(basename "$path")"
      (( ${#name} > name_width )) && name_width=${#name}
    done

    printf "%-8s %-${name_width}s %s\n" "SIZE" "$NAME_HEADER" "BRANCH"
    for meta in "$tmp_dir"/*.meta; do
      IFS=$'\t' read -r path branch < "$meta"
      size="$(cat "${meta%.meta}.size" 2>/dev/null)"
      marker=""
      [[ "$path" == "$BASE_ROOT" ]] && marker=" (current)"
      printf "%-8s %-${name_width}s %s%s\n" "$size" "$(basename "$path")" "$branch" "$marker"
    done
    rm -rf "$tmp_dir"
    exit 0
    ;;

  # Plumbing for shell completion (see `worktree --help` for setup) — not
  # meant to be typed by hand, so they're left out of the main subcommand list.
  __complete-worktrees)
    while IFS=$'\t' read -r path branch; do
      [[ "$path" == "$BASE_ROOT" ]] && continue
      basename "$path"
    done < <(list_worktrees)
    exit 0
    ;;

  __complete-branches)
    {
      git -C "$BASE_ROOT" for-each-ref --format='%(refname:short)' refs/heads
      git -C "$BASE_ROOT" for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v '^origin/HEAD$' | sed 's#^origin/##'
    } | sort -u
    exit 0
    ;;

  __complete-open-targets)
    while IFS=$'\t' read -r path branch; do
      [[ "$path" == "$BASE_ROOT" ]] && continue
      basename "$path"
      [[ "$branch" != "(detached)" ]] && echo "$branch"
    done < <(list_worktrees)
    exit 0
    ;;

  remove)
    name="${1:-}"
    if [[ -z "$name" ]]; then
      echo "Usage: worktree remove <name>" >&2
      exit 1
    fi

    if [[ -d "$name" ]]; then
      remove_path="$(cd "$name" && pwd)"
    else
      remove_path="$(dirname "$BASE_ROOT")/$name"
    fi

    if [[ "$remove_path" == "$BASE_ROOT" ]]; then
      echo "That's the worktree you're running this from — not removing it." >&2
      exit 1
    fi

    if [[ ! -e "$remove_path" ]]; then
      echo "No worktree found at $remove_path." >&2
      echo "See your current worktrees: worktree list" >&2
      exit 1
    fi

    remove_branch="$(list_worktrees | awk -F'\t' -v p="$remove_path" '$1==p{print $2}')"

    set +e
    remove_output="$(git -C "$BASE_ROOT" worktree remove "$remove_path" 2>&1)"
    remove_status=$?
    set -e

    if [[ $remove_status -ne 0 ]]; then
      echo "$remove_output" >&2
      if echo "$remove_output" | grep -q "contains modified or untracked files"; then
        read -r -p "Retry with --force (discards uncommitted changes in that worktree)? [y/N] " force_choice || true
        if [[ "$force_choice" =~ ^[Yy]$ ]]; then
          git -C "$BASE_ROOT" worktree remove --force "$remove_path"
        else
          exit 1
        fi
      else
        exit 1
      fi
    fi

    echo "Removed worktree at $remove_path."

    # Setup logs live outside the worktree (see `up`) precisely so removing
    # a dirty worktree doesn't need --force just because of them — but that
    # also means they don't disappear on their own, so clean them up here.
    rm -rf "$HOME/.cache/torus-worktree/logs/$(basename "$remove_path")"

    if [[ -n "$remove_branch" && "$remove_branch" != "(detached)" ]]; then
      read -r -p "Also delete the local branch '$remove_branch'? [y/N] " delete_branch_choice || true
      if [[ "$delete_branch_choice" =~ ^[Yy]$ ]]; then
        git -C "$BASE_ROOT" branch -D "$remove_branch"
      fi
    fi
    exit 0
    ;;

  rename)
    old_name="${1:-}"
    new_name="${2:-}"
    if [[ -z "$old_name" || -z "$new_name" ]]; then
      echo "Usage: worktree rename <name> <new-name>" >&2
      exit 1
    fi

    # New name becomes a directory basename (and git's internal
    # .git/worktrees/<name> key) — keep it to safe, unambiguous characters.
    if [[ ! "$new_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      echo "Invalid name: '$new_name' (only letters, numbers, '.', '_', '-' — no spaces or slashes)." >&2
      exit 1
    fi

    if [[ -d "$old_name" ]]; then
      rename_old_path="$(cd "$old_name" && pwd)"
    else
      rename_old_path="$(dirname "$BASE_ROOT")/$old_name"
    fi

    if [[ "$rename_old_path" == "$BASE_ROOT" ]]; then
      echo "That's the worktree you're running this from — not renaming it." >&2
      exit 1
    fi

    if [[ ! -e "$rename_old_path" ]]; then
      echo "No worktree found at $rename_old_path." >&2
      echo "See your current worktrees: worktree list" >&2
      exit 1
    fi

    rename_new_path="$(dirname "$BASE_ROOT")/$new_name"

    if [[ -e "$rename_new_path" ]]; then
      echo "Something already exists at $rename_new_path — pick another name." >&2
      exit 1
    fi

    git -C "$BASE_ROOT" worktree move "$rename_old_path" "$rename_new_path"
    echo "Renamed worktree: $rename_old_path -> $rename_new_path"
    exit 0
    ;;

  open)
    open_target="${1:-}"
    if [[ -z "$open_target" ]]; then
      echo "Usage: worktree open <name-or-branch>" >&2
      exit 1
    fi
    shift || true
    for arg in "$@"; do
      case "$arg" in
        --no-ide) OPEN_IDE=false ;;
        --no-server) OFFER_SERVER=false ;;
        *) echo "Unknown option for open: $arg" >&2; exit 1 ;;
      esac
    done

    # Try it as a worktree folder name first (sibling dir or full path),
    # then fall back to matching it against the branch each worktree has
    # checked out — either way is a valid way to refer to one.
    if [[ -d "$open_target" ]]; then
      open_path="$(cd "$open_target" && pwd)"
    else
      candidate_path="$(dirname "$BASE_ROOT")/$open_target"
      if [[ -e "$candidate_path" ]]; then
        open_path="$candidate_path"
      else
        open_path="$(list_worktrees | awk -F'\t' -v b="$open_target" '$2==b{print $1; exit}')"
      fi
    fi

    if [[ -z "${open_path:-}" || ! -e "$open_path" ]]; then
      echo "No worktree found matching '$open_target' (as a folder name or branch)." >&2
      echo "See your current worktrees: worktree list" >&2
      exit 1
    fi

    if [[ "$open_path" == "$BASE_ROOT" ]]; then
      echo "That's the worktree you're running this from." >&2
      exit 1
    fi

    open_existing_worktree "$open_path"
    exit 0
    ;;

  up)
    ;;

  *)
    echo "Unknown subcommand: $SUBCOMMAND" >&2
    usage
    exit 1
    ;;
esac

# ============================================================================
# up
# ============================================================================

ASSETS_DEPS_MODE="auto"
AUTOMATION_DEPS_MODE="auto"
MIX_DEPS_MODE="auto"
BRANCH=""
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assets-deps=*) ASSETS_DEPS_MODE="${1#*=}" ;;
    --automation-deps=*) AUTOMATION_DEPS_MODE="${1#*=}" ;;
    --mix-deps=*) MIX_DEPS_MODE="${1#*=}" ;;
    --no-ide) OPEN_IDE=false ;;
    --no-server) OFFER_SERVER=false ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$BRANCH" ]]; then
        BRANCH="$1"
      elif [[ -z "$NAME" ]]; then
        NAME="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$BRANCH" ]]; then
  usage
  exit 1
fi

for mode in "$ASSETS_DEPS_MODE" "$AUTOMATION_DEPS_MODE" "$MIX_DEPS_MODE"; do
  case "$mode" in
    auto|copy|install) ;;
    *) echo "Invalid deps mode: $mode (use auto|copy|install)" >&2; exit 1 ;;
  esac
done

# --- personal config (already sourced above, before the config subcommand check) ---

if $HAS_CONFIG; then
  echo "Generating worktree with your custom config ($CONFIG_FILE)."
else
  echo "Generating worktree with the default config. Run 'worktree config' to define your own."
fi

# --- worktree name -----------------------------------------------------------

if [[ -z "$NAME" ]]; then
  ticket="$(echo "$BRANCH" | grep -oE '[A-Za-z]+-[0-9]+' | head -1 || true)"
  if [[ -n "$ticket" ]]; then
    NAME="$ticket"
  else
    # No ticket-like token in the branch name — fall back to the full branch
    # name, sanitized for a directory (/ -> -).
    NAME="$(echo "$BRANCH" | tr '/' '-')"
  fi
fi

WORKTREE_PATH="$(dirname "$BASE_ROOT")/$NAME"

if [[ -e "$WORKTREE_PATH" ]]; then
  echo "Something already exists at $WORKTREE_PATH."
  read -r -p "Open it instead? [Y/n] " open_choice || true
  if [[ ! "$open_choice" =~ ^[Nn]$ ]]; then
    # $NAME is reliable here (WORKTREE_PATH was built from it, so it's
    # exactly that folder's basename) — but $BRANCH is just what the user
    # typed, which may not be this folder's actual branch (e.g. they typed
    # the folder name itself, not a branch). Let the function look up the
    # real branch instead of trusting $BRANCH.
    open_existing_worktree "$WORKTREE_PATH" "$NAME"
    exit 0
  fi
  echo "  See your current worktrees: worktree list" >&2
  echo "  If you don't need it anymore: worktree remove \"$NAME\"" >&2
  echo "  Otherwise, pick another name: worktree up $BRANCH <name>" >&2
  exit 1
fi

# --- create the worktree -----------------------------------------------------

echo "==> Preparing worktree '$NAME' for branch '$BRANCH' at $WORKTREE_PATH"

git -C "$BASE_ROOT" fetch origin "$BRANCH" 2>/dev/null || true

# Wraps `git worktree add` so a failure because the branch is already checked
# out elsewhere gets guidance pointing at that other worktree (git's own
# error already names its path — this just makes it actionable), instead of
# just dying on `set -e` with git's raw one-liner.
worktree_add() {
  local output status
  set +e
  output="$(git -C "$BASE_ROOT" "$@" 2>&1)"
  status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "$output"
    return 0
  fi

  echo "$output" >&2
  local existing_path
  existing_path="$(echo "$output" | grep -oE "already used by worktree at '[^']+'" | sed -E "s/.*'(.+)'/\1/")"
  if [[ -n "$existing_path" ]]; then
    echo
    echo "That branch is already checked out at $existing_path."
    read -r -p "Open it instead? [Y/n] " open_choice || true
    if [[ ! "$open_choice" =~ ^[Nn]$ ]]; then
      # $BRANCH is reliable here (git itself reported that's the branch
      # already checked out at $existing_path) — but $NAME was computed for
      # the new path we were about to create, unrelated to $existing_path's
      # actual folder name, so leave it out and let the function default to
      # $existing_path's real basename.
      open_existing_worktree "$existing_path" "" "$BRANCH"
      exit 0
    fi
    echo "  See all your current worktrees: worktree list" >&2
    echo "  If you don't need it anymore: worktree remove \"$existing_path\"" >&2
  fi
  exit 1
}

if git -C "$BASE_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  worktree_add worktree add "$WORKTREE_PATH" "$BRANCH"
elif git -C "$BASE_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  worktree_add worktree add -b "$BRANCH" "$WORKTREE_PATH" "origin/$BRANCH"
else
  current_ref="$(git -C "$BASE_ROOT" branch --show-current)"
  if [[ -n "$current_ref" ]]; then
    current_label="your current branch ($current_ref)"
  else
    current_label="your current commit ($(git -C "$BASE_ROOT" rev-parse --short HEAD))"
  fi

  # Prefer the ref git already recorded for the remote's default branch (no
  # network call); fall back to probing common names if that isn't set.
  default_branch="$(git -C "$BASE_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
  if [[ -z "$default_branch" ]]; then
    for candidate in main master; do
      if git -C "$BASE_ROOT" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
        default_branch="$candidate"
        break
      fi
    done
  fi

  echo "Branch '$BRANCH' not found locally or on origin."
  echo "  1) Create it from $current_label"
  if [[ -n "$default_branch" ]]; then
    echo "  2) Create it from origin/$default_branch"
  fi
  echo "  3) Don't create it"
  read -r -p "Choice [3]: " branch_choice || true

  case "$branch_choice" in
    1)
      worktree_add worktree add -b "$BRANCH" "$WORKTREE_PATH" HEAD
      ;;
    2)
      if [[ -z "$default_branch" ]]; then
        echo "Couldn't detect a main/master branch on origin." >&2
        exit 1
      fi
      git -C "$BASE_ROOT" fetch origin "$default_branch" 2>/dev/null || true
      worktree_add worktree add -b "$BRANCH" "$WORKTREE_PATH" "origin/$default_branch"
      ;;
    *)
      exit 1
      ;;
  esac
fi

# --- local env files (gitignored, not brought in by `git worktree add`) -----

for env_file in oli.env postgres.env seeds.json; do
  if [[ -f "$BASE_ROOT/$env_file" ]]; then
    cp "$BASE_ROOT/$env_file" "$WORKTREE_PATH/$env_file"
  fi
done

# Keep Phoenix's listener and public URL in step with the URL that Playwright
# receives after it sources this worktree's oli.env in assets/automation.
if [[ -f "$WORKTREE_PATH/oli.env" ]]; then
  sync_worktree_port_env "$WORKTREE_PATH/oli.env" "$SERVER_PORT"
fi

# --- dependency sync/install --------------------------------------------------

STATUS_DIR="$(mktemp -d)"
# Outside the worktree on purpose: a log dir *inside* it would always show
# up as untracked in `git status` (for anyone using this tool, on any
# worktree) and make `worktree remove` always need --force. Cleaned up in
# `remove` below.
LOG_DIR="$HOME/.cache/torus-worktree/logs/$NAME"
mkdir -p "$LOG_DIR"

fast_copy_dir() {
  local src="$1" dst="$2"
  rm -rf "$dst"
  if cp -c -R "$src" "$dst" 2>/dev/null; then return 0; fi
  if cp -al "$src" "$dst" 2>/dev/null; then return 0; fi
  cp -R "$src" "$dst"
}

# sync_deps <tag> <mode> <work_dir_rel> <lockfile_name> <copy_subdir> <install_cmd...>
sync_deps() {
  local tag="$1" mode="$2" work_dir_rel="$3" lockfile_name="$4" copy_subdir="$5"
  shift 5
  local install_cmd=("$@")

  local base_work="$BASE_ROOT/$work_dir_rel"
  local new_work="$WORKTREE_PATH/$work_dir_rel"
  local base_target="$base_work/$copy_subdir"
  local new_target="$new_work/$copy_subdir"

  local do_copy=false
  case "$mode" in
    copy) do_copy=true ;;
    install) do_copy=false ;;
    auto)
      if [[ -d "$base_target" ]] \
        && [[ -f "$base_work/$lockfile_name" && -f "$new_work/$lockfile_name" ]] \
        && cmp -s "$base_work/$lockfile_name" "$new_work/$lockfile_name"; then
        do_copy=true
      fi
      ;;
  esac

  if $do_copy; then
    log "$tag" "lockfile matches -> copying $copy_subdir from the base worktree"
    fast_copy_dir "$base_target" "$new_target"
  else
    log "$tag" "installing (mode: $mode)"
    (cd "$new_work" && "${install_cmd[@]}")
  fi
}

run_job() {
  local tag="$1"; shift
  (
    set +e
    "$@" 2>&1 | sed -u "s/^/[$tag] /" | tee -a "$LOG_DIR/$tag.log"
    echo "${PIPESTATUS[0]}" > "$STATUS_DIR/$tag"
  ) &
}

assets_job() {
  sync_deps "assets" "$ASSETS_DEPS_MODE" "assets" "yarn.lock" "node_modules" yarn install
}

automation_job() {
  sync_deps "automation" "$AUTOMATION_DEPS_MODE" "assets/automation" "package-lock.json" "node_modules" npm i
}

backend_job() {
  # `gleam build` must run before `mix compile`: mix's :gleam/:gleam_runtime
  # compilers (see mix.exs) expect gleam's erlang build output to already
  # exist on disk, and error out otherwise.
  if [[ -d "$BASE_ROOT/gleam/build" ]]; then
    log "gleam" "priming gleam/build from the base worktree"
    fast_copy_dir "$BASE_ROOT/gleam/build" "$WORKTREE_PATH/gleam/build"
  fi
  log "gleam" "gleam deps download + build --target erlang"
  (cd "$WORKTREE_PATH/gleam" && gleam deps download && gleam build --target erlang)

  # No _build priming here: tried it (with mtime fixes and Elixir 1.19's
  # check_cwd:false, per
  # https://ryanzidago.com/posts/reducing-elixir-worktree-setup-time-by-83-percent/),
  # Mix still fully recompiles regardless — this project invalidates the
  # manifest cache across worktree paths for reasons beyond cwd (likely the
  # Cldr compile-time locale generation, among others). Not worth chasing
  # further; a full `mix compile` it is.
  log "mix" "mix compile"
  (cd "$WORKTREE_PATH" && mix compile)
}

# Synced here, before the parallel phase below, and NOT inside backend_job:
# assets/package.json has `file:../deps/*` dependencies (phoenix, phoenix_html,
# phoenix_live_view, etc.) — `yarn install` in assets_job needs deps/ to
# already exist, so it can't run concurrently with the mix deps sync without
# risking exactly that race.
echo "==> Syncing mix deps (assets/ needs deps/ to exist before it can install)"
sync_deps "mix" "$MIX_DEPS_MODE" "." "mix.lock" "deps" mix deps.get 2>&1 | tee -a "$LOG_DIR/mix-deps.log"

echo "==> Setting up environment (assets, automation, gleam+compile in parallel)"
echo "    full logs in $LOG_DIR/"

run_job "assets" assets_job
run_job "automation" automation_job
run_job "backend" backend_job

wait

FAILED=false
for tag in assets automation backend; do
  status="$(cat "$STATUS_DIR/$tag" 2>/dev/null || echo 1)"
  if [[ "$status" != "0" ]]; then
    echo "!! Step '$tag' failed — see $LOG_DIR/$tag.log"
    FAILED=true
  fi
done
rm -rf "$STATUS_DIR"

if $FAILED; then
  echo "==> Environment has errors. Check the logs before continuing."
  exit 1
fi

echo "==> Environment ready at $WORKTREE_PATH"
echo "    DB and MinIO are shared with your other worktrees (same Postgres, same MinIO on :9000/:9001)."

# Server hint + macOS notification + IDE — same as `open`/the "already
# exists" shortcut, so all three behave identically from here on.
open_existing_worktree "$WORKTREE_PATH" "$NAME" "$BRANCH"
