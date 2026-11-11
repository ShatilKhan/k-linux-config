#!/usr/bin/env bash
# One-line start on a fresh Ubuntu 26.04 install (run as your user, in a terminal):
#   curl -fsSL https://raw.githubusercontent.com/ShatilKhan/k-linux-config/main/bootstrap.sh | bash
# It runs the steps that must finish before Claude Code first starts (preflight, data copy,
# permissions), installs Claude Code, then starts Claude to do the rest (AGENT.md).
# sudo asks for your password in this terminal; nothing gets passwordless sudo.
# Dry run: curl ... | bash -s -- --check
set -euo pipefail

# Everything is inside main so bash reads the whole script before running it
# (needed for `curl | bash`, because main switches stdin to the terminal).
main() {
  REPO_URL="https://github.com/ShatilKhan/k-linux-config"
  DIR="$HOME/k-linux-config"
  CHECK=(); [[ " $* " == *" --check "* ]] && CHECK=(--check)

  [[ "$(id -u)" -ne 0 ]] || { echo "Run this as your normal user, not root." >&2; exit 1; }
  say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

  # stdin is this script when piped from curl; prompts must read the terminal.
  exec </dev/tty

  if ((${#CHECK[@]} == 0)); then
    say "Base packages (sudo asks for your password)"
    sudo apt-get update -qq
    sudo apt-get install -y git curl rsync
  fi

  say "Repo"
  if [[ -d "$DIR/.git" ]]; then git -C "$DIR" pull --ff-only; else git clone "$REPO_URL" "$DIR"; fi
  cd "$DIR"

  # The copy brings ~/.claude and ~/.claude.json (memories, sessions, MCP config). It must run
  # before Claude Code starts, or Claude can overwrite the copied config when it exits.
  say "Preflight";   scripts/00-preflight.sh --fix-swap "${CHECK[@]}"
  say "Copy data";   scripts/10-migrate.sh "${CHECK[@]}"
  say "Permissions"; scripts/15-secure.sh "${CHECK[@]}"

  if ((${#CHECK[@]})); then say "Check mode: stopping before Claude Code is installed."; exit 0; fi

  say "Claude Code"
  [[ -x "$HOME/.local/bin/claude" ]] || curl -fsSL https://claude.ai/install.sh | bash

  say "Starting Claude. Log in, then it continues the setup from AGENT.md."
  exec "$HOME/.local/bin/claude" "Follow AGENT.md. Read ~/.local/state/k-setup first and continue with the first script that has no .done file."
}

main "$@"
