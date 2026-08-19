#!/usr/bin/env bash
# Shared port configuration for worktree.sh and run-server.sh.

find_free_port() {
  local candidate="$1"
  while lsof -nP -iTCP:"$candidate" -sTCP:LISTEN >/dev/null 2>&1; do
    candidate=$((candidate + 1))
  done
  echo "$candidate"
}

# sync_worktree_port_env <oli.env path> <port> — keeps the Phoenix listener,
# Phoenix's public URL, and Playwright's target in one shared per-worktree
# file. The replacement is atomic so another terminal never reads a partial
# port configuration.
sync_worktree_port_env() {
  local file="$1" port="$2" tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")"

  awk -v port="$port" '
    /^HTTP_PORT=/ { print "HTTP_PORT=" port; saw_http = 1; next }
    /^PORT=/ { print "PORT=" port; saw_port = 1; next }
    /^PLAYWRIGHT_BASE_URL=/ {
      print "PLAYWRIGHT_BASE_URL=http://localhost:" port
      saw_playwright = 1
      next
    }
    { print }
    END {
      if (!saw_http) print "HTTP_PORT=" port
      if (!saw_port) print "PORT=" port
      if (!saw_playwright) print "PLAYWRIGHT_BASE_URL=http://localhost:" port
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
