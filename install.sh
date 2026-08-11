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

for command in git bash lsof; do
  require_command "$command"
done

if [[ -f "$SCRIPT_DIR/worktree.sh" && -f "$SCRIPT_DIR/run-server.sh" && -d "$SCRIPT_DIR/.git" ]]; then
  INSTALL_DIR="$SCRIPT_DIR"
  echo "Installing from existing checkout: $INSTALL_DIR"
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "Installation directory already exists: $INSTALL_DIR" >&2
  echo "Run 'worktree update' to update it, or remove it before installing again." >&2
  exit 1
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  echo "Cloning torus-worktree into $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

touch "$INSTALL_DIR/.torus-worktree-install"
mkdir -p "$BIN_DIR"
ln -sfn "$INSTALL_DIR/worktree.sh" "$BIN_DIR/worktree"
ln -sfn "$INSTALL_DIR/worktree.sh" "$BIN_DIR/wt"
ln -sfn "$INSTALL_DIR/run-server.sh" "$BIN_DIR/run-server"

ensure_path

echo
echo "torus-worktree installed."
echo "  worktree version"
echo "  worktree config"
echo "  worktree up MER-1234-some-branch"
