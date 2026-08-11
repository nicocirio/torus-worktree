#!/usr/bin/env bash
# Installs torus-worktree from a checkout or from GitHub when run via curl.

set -euo pipefail

REPO_URL="https://github.com/nicocirio/torus-worktree.git"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/torus-worktree"
BIN_DIR="$HOME/.local/bin"
# BASH_SOURCE is unset when this script is piped to `bash` from curl. In that
# case $0 is enough: it resolves to `bash`, so this directory will not look
# like a checkout and the installer follows the clone-from-GitHub path below.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
  esac

  local shell_rc="$HOME/.zshrc"
  [[ "${SHELL:-}" == */bash ]] && shell_rc="$HOME/.bashrc"

  echo "Note: $BIN_DIR is not on your PATH in this shell."
  read -r -p "Add it to $shell_rc for future shells? [Y/n] " choice || true
  if [[ ! "$choice" =~ ^[Nn]$ ]]; then
    if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$shell_rc" 2>/dev/null; then
      printf '\n# Local command-line tools\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$shell_rc"
    fi
    echo "Added $BIN_DIR to $shell_rc. Open a new terminal before using the commands."
  else
    echo "Add this yourself before using the commands: export PATH=\"$HOME/.local/bin:\$PATH\""
  fi
}

setup_zsh_completion() {
  if [[ "${SHELL:-}" != */zsh ]]; then
    echo "Skipping zsh completion: your current shell is not zsh. Commands are installed normally."
    return 0
  fi

  if ! command -v zsh >/dev/null 2>&1; then
    echo "Skipping zsh completion: zsh is not available. Commands are installed normally."
    return 0
  fi

  local zshrc="$HOME/.zshrc"
  local start_marker='# >>> torus-worktree completion >>>'
  local end_marker='# <<< torus-worktree completion <<<'

  if grep -Fqx "$start_marker" "$zshrc" 2>/dev/null; then
    echo "zsh completion is already configured."
    return 0
  fi

  read -r -p "Enable zsh tab completion for worktree and wt? [Y/n] " choice || true
  if [[ "$choice" =~ ^[Nn]$ ]]; then
    echo "Skipping zsh completion. Commands are installed normally."
    return 0
  fi

  if ! {
    printf '\n%s\n' "$start_marker"
    printf 'source %q\n' "$INSTALL_DIR/completions/_worktree"
    printf 'compdef _worktree worktree wt\n'
    printf '%s\n' "$end_marker"
  } >> "$zshrc"; then
    echo "Could not enable zsh completion in $zshrc. Commands are installed normally." >&2
    echo "You can configure it later using the instructions in the README." >&2
    return 1
  fi

  echo "Enabled zsh completion in $zshrc. Open a new terminal to load it."
}

for command in git bash lsof; do
  require_command "$command"
done

cloned=false
if [[ -f "$SCRIPT_DIR/worktree.sh" && -f "$SCRIPT_DIR/run-server.sh" && -d "$SCRIPT_DIR/.git" ]]; then
  INSTALL_DIR="$SCRIPT_DIR"
  echo "Installing from existing checkout: $INSTALL_DIR"
elif [[ -f "$INSTALL_DIR/worktree.sh" && -f "$INSTALL_DIR/run-server.sh" && -d "$INSTALL_DIR/.git" ]]; then
  echo "Using existing installation: $INSTALL_DIR"
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "Installation directory already exists: $INSTALL_DIR" >&2
  echo "Run 'worktree update' to update it, or remove it before installing again." >&2
  exit 1
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  echo "Cloning torus-worktree into $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
  cloned=true
fi

# A versioned bootstrap script can be older than the checkout it just cloned.
# Re-run the installed copy so new setup steps (such as shell completion) are
# applied immediately, while the second run takes the existing-install path.
if $cloned; then
  exec bash "$INSTALL_DIR/install.sh"
fi

touch "$INSTALL_DIR/.torus-worktree-install"
mkdir -p "$BIN_DIR"
ln -sfn "$INSTALL_DIR/worktree.sh" "$BIN_DIR/worktree"
ln -sfn "$INSTALL_DIR/worktree.sh" "$BIN_DIR/wt"
ln -sfn "$INSTALL_DIR/run-server.sh" "$BIN_DIR/run-server"

ensure_path
if ! setup_zsh_completion; then
  echo "zsh completion was not configured; commands remain installed and usable."
fi

echo
echo "torus-worktree installed."
echo "  worktree version"
echo "  worktree config"
echo "  worktree up MER-1234-some-branch"
