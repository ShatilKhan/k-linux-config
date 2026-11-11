#!/usr/bin/env bash
# Executor (https://executor.sh), local CLI mode: one MCP endpoint for many connected
# accounts. You connect each account once in its dashboard; agents see one server.
#   Endpoint:  http://127.0.0.1:4312/mcp     Data: ~/.executor/v2/cli
#   Keys:      Linux Secret Service (GNOME keyring), service com.usefulsoftware.executor.v2
# Executor does not start at boot by itself, so a systemd user unit runs it at login.
# Executor 2 has no CLI tool commands (v1 `call`/`tools` were removed); agents use MCP.
# Existing MCP servers stay configured until each one works through Executor.
source "$(dirname "$0")/lib.sh"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

command -v executor >/dev/null || run bash -c "curl -fsSL https://executor.sh/docs/install.sh | sh"

UNIT="$HOME/.config/systemd/user/executor.service"
# systemd runs `executor serve` in the foreground (no browser) and restarts it if it crashes.
WANT="[Unit]
Description=Executor local MCP server
After=graphical-session.target

[Service]
Type=simple
ExecStart=$(command -v executor || echo "$HOME/.local/bin/executor") serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target"
if [[ "$(cat "$UNIT" 2>/dev/null)" != "$WANT" ]]; then
  if ((CHECK_ONLY)); then log "would write $UNIT"
  else mkdir -p "$(dirname "$UNIT")"; printf '%s\n' "$WANT" >"$UNIT"; fi
fi
run systemctl --user daemon-reload
run systemctl --user enable executor.service
run systemctl --user restart executor.service

# Register the local endpoint with Claude Code and Codex (user scope; sign-in opens a browser).
if command -v claude >/dev/null && ! claude mcp get executor >/dev/null 2>&1; then
  run claude mcp add --transport http --scope user executor http://127.0.0.1:4312/mcp
fi
if command -v codex >/dev/null && ! codex mcp list 2>/dev/null | grep -q '^executor'; then
  run codex mcp add executor --url http://127.0.0.1:4312/mcp
fi

# Checks
((CHECK_ONLY)) && exit 0
verify_tool executor || die "executor not installed"
code=000
for _ in $(seq 20); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4312/mcp || true)"
  [[ "$code" != 000 ]] && break; sleep 1
done
[[ "$code" != 000 ]] || die "Executor is not listening on 127.0.0.1:4312"
log "Executor answers on :4312 (HTTP $code), RAM $(executor_ram)"
cat <<'TXT'
Next steps for you:
  1. Connect each account once: run `executor` (dashboard), or ask an agent to connect it
     (it calls appAccounts.userConnect and gives you a sign-in link).
  2. In Claude Code run /mcp and sign in to "executor".
  3. When a service works through Executor, remove its old MCP entry to avoid duplicate tools.
TXT
log "Next: scripts/70-git.sh"
