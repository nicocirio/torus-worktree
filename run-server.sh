#!/usr/bin/env bash
#
# Starts the Phoenix dev server for the checkout you're currently in. The
# worktree's oli.env is the shared source of truth for Phoenix's port and the
# Playwright URL, so a separate automation terminal targets this same server.
#
# Usage:
#   run-server
#
# Run it from inside the worktree you want to serve (any worktree has its own
# oli.env, copied there by worktree). If its assigned port was claimed since
# the worktree was opened, this command finds a new one and updates oli.env.

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SCRIPT_SOURCE" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "$SCRIPT_DIR/lib/worktree-port.sh"

if [[ $# -ne 0 ]]; then
  echo "Usage: run-server" >&2
  exit 1
fi

if [[ ! -f oli.env ]]; then
  echo "No oli.env here — run this from inside a checkout of this project." >&2
  exit 1
fi

set -a
source oli.env
set +a

env_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { value=$2 } END { print value }' oli.env
}

http_port="$(env_value HTTP_PORT)"
public_port="$(env_value PORT)"
playwright_url="$(env_value PLAYWRIGHT_BASE_URL)"
playwright_port="$(echo "$playwright_url" | sed -nE 's#^https?://[^/:]+:([0-9]+)(/.*)?$#\1#p')"

for value_name in http_port public_port playwright_port; do
  value="${!value_name}"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    echo "Invalid ${value_name//_/ } in oli.env: '$value'" >&2
    exit 1
  fi
done

# HTTP_PORT is the listener Phoenix will use, so it is authoritative when a
# hand-edited oli.env disagrees with the public URL or Playwright target.
if [[ -n "$http_port" ]]; then
  port="$http_port"
elif [[ -n "$public_port" ]]; then
  port="$public_port"
elif [[ -n "$playwright_port" ]]; then
  # Supports worktrees made before HTTP_PORT and PORT were persisted.
  port="$playwright_port"
else
  port=80
fi

if [[ ( -n "$public_port" && "$public_port" != "$port" ) ||
      ( -n "$playwright_port" && "$playwright_port" != "$port" ) ]]; then
  echo "Port configuration is inconsistent (HTTP_PORT=${http_port:-unset}, PORT=${public_port:-unset}, PLAYWRIGHT_BASE_URL=${playwright_url:-unset}); normalizing to port $port."
fi

if [[ ! "$port" =~ ^[0-9]+$ ]]; then
  echo "Invalid selected port in oli.env: '$port'" >&2
  exit 1
fi

available_port="$(find_free_port "$port")"
if [[ "$available_port" != "$port" ]]; then
  echo "Port $port is already in use; reassigned this worktree to port $available_port."
  port="$available_port"
fi

# Normalize the three values even when the assigned port was still free. This
# also repairs worktrees made with older versions of the tool.
sync_worktree_port_env "oli.env" "$port"
HTTP_PORT="$port"
PORT="$port"
PLAYWRIGHT_BASE_URL="http://127.0.0.1:$port"

echo "Starting Phoenix at http://localhost:$port"
exec iex -S mix phx.server
