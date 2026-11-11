#!/usr/bin/env bash
# Coding agents. Their state (~/.claude, ~/.codex, ~/.agents, ~/.config/opencode)
# arrives with scripts/10-migrate.sh; this script installs the binaries and cleans up.
source "$(dirname "$0")/lib.sh"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# 1. Claude Code: native installer (~/.local/bin/claude, updates itself).
command -v claude >/dev/null || run bash -c "curl -fsSL https://claude.ai/install.sh | bash"

# 2. Codex CLI: official installer puts `codex` on PATH; npm package as fallback.
if ! command -v codex >/dev/null; then
  run bash -c "curl -fsSL https://chatgpt.com/codex/install.sh | sh" ||
    run mise use -g "npm:@openai/codex@latest"
fi

# 3. opencode comes from mise (config.toml); its config stays in ~/.config/opencode.

# 4. Cleanup decided for the new machine.
# Removed skills are moved aside (not deleted) to ~/.local/share/k-removed-skills/.
AWAY="$HOME/.local/share/k-removed-skills"
for d in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' s; do
    run mkdir -p "$AWAY/${d#"$HOME"/}"
    run mv "$s" "$AWAY/${d#"$HOME"/}/"
  done < <(find "$d" -mindepth 1 -maxdepth 1 \( -name 'flutter-*' -o -name 'dart-*' -o -name 'playwright-cli' \) -print0)
done
# Global Playwright CLI and the home-level playwright MCP are dropped (project-level ones stay).
if command -v claude >/dev/null && (cd "$HOME" && claude mcp get playwright >/dev/null 2>&1); then
  (cd "$HOME" && run claude mcp remove playwright -s local) || true
fi

# 5. Plugins: the copied ~/.claude/plugins holds marketplaces and cache; refresh them.
command -v claude >/dev/null && run claude plugin marketplace update || warn "plugin marketplace update failed; run it inside Claude: /plugin"

# 6. herdsman skill (the binary comes from mise). The skill must match the binary's release.
HS_VER="$(herdsman version 2>/dev/null | grep -oE 'v?[0-9]+(\.[0-9]+)+' | head -1 || true)"
if ! gh skill list 2>/dev/null | grep -qw herdsman; then
  if gh auth status >/dev/null 2>&1 && [[ -n "$HS_VER" ]]; then
    run gh skill install arafathusayn/herdsman herdsman --agent claude-code --scope user --pin "v${HS_VER#v}"
  else
    echo "LOGIN-NEEDED herdsman skill (after 70-git.sh): gh skill install arafathusayn/herdsman herdsman --agent claude-code --scope user --pin v<herdsman version>"
  fi
fi

# Checks
((CHECK_ONLY)) || verify_rows claude codex opencode dcg herdr herdsman
((CHECK_ONLY)) || herdsman doctor || warn "herdsman doctor reported problems (gh login or herdr session may be missing)"
if [[ -f "$HOME/.claude/settings.json" ]]; then
  miss=0
  while read -r p; do
    name="${p%@*}"; mkt="${p#*@}"
    [[ -d "$HOME/.claude/plugins/cache/$mkt/$name" ]] || { warn "plugin not installed: $p"; miss=1; }
  done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' "$HOME/.claude/settings.json")
  ((miss)) && warn "install missing plugins inside Claude with /plugin" || log "all enabled plugins present"
fi
log "Next: scripts/65-executor.sh"
