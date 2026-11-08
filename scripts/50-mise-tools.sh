#!/usr/bin/env bash
# Runtimes and CLIs through mise (replaces nvm and sdkman), plus tools with their own
# official installers: aws, ollama, xhisper.
source "$(dirname "$0")/lib.sh"
CFG="$REPO_DIR/config"
command -v mise >/dev/null || die "mise missing; run scripts/20-apps.sh first"

# 1. Config files (copied, not linked, so a repo edit never changes a live machine).
run install -D -m 644 "$CFG/mise.toml" "$HOME/.config/mise/config.toml"
run install -m 644 "$CFG/npmrc" "$HOME/.npmrc"
run install -m 644 "$CFG/bunfig.toml" "$HOME/.bunfig.toml"

# 2. Shell setup. Interactive shells: `mise activate`. Login shells without a terminal
#    (Claude Code, MCP stdio servers, GUI apps): the shims dir on PATH from ~/.profile.
add_block "$HOME/.profile" mise-shims 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"'
add_block "$HOME/.bashrc" mise-activate 'eval "$(mise activate bash)"'
add_block "$HOME/.bashrc" update-all 'update-all() {
  sudo apt update && sudo apt full-upgrade -y
  sudo snap refresh
  flatpak update -y
  mise upgrade
  claude update
  echo "Docker Desktop and Hubstaff update from their own app menus."
}'
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# 3. Install everything in config.toml (runtimes first, then the npm/pipx/github CLIs).
run mise trust "$HOME/.config/mise/config.toml"
run mise install node bun python uv rust
run mise install
run mise reshim

# 4. AWS CLI v2: official installer (into /usr/local).
if ! command -v aws >/dev/null; then
  tmp="$(mktemp -d)"
  run curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$tmp/aws.zip"
  run unzip -q "$tmp/aws.zip" -d "$tmp"
  run sudo "$tmp/aws/install" --update
  rm -rf "$tmp"
fi

# 5. Ollama: official installer + models on /home, API on localhost only.
command -v ollama >/dev/null || run bash -c "curl -fsSL https://ollama.com/install.sh | sh"
run mkdir -p "$HOME/dev/models"
run sudo chown ollama:ollama "$HOME/dev/models"
# The ollama user must traverse /home/k and /home/k/dev to reach the models folder.
run chmod o+x "$HOME" "$HOME/dev"
sudo_write /etc/systemd/system/ollama.service.d/override.conf "$(cat "$CFG/ollama-override.conf")"
run sudo systemctl daemon-reload
run sudo systemctl restart ollama

# 6. xhisper (dictation tool) from the owner's fork; deps from its README.
if ! command -v xhisper >/dev/null; then
  run sudo apt-get install -y pipewire jq curl ffmpeg gcc make
  src="$HOME/dev/xhisper"
  [[ -d "$src/.git" ]] || run git clone https://github.com/ShatilKhan/xhisper.git "$src"
  run make -C "$src"
  run sudo make -C "$src" install
fi

# Checks
((CHECK_ONLY)) || verify_rows mise node npm bun python uv rustc cargo ctx7 posthog-cli cf \
  firefox-devtools-mcp lstk vercel cocoindex-code hf d2 sentry-cli railway opencode aws ollama xhisper
if ((!CHECK_ONLY)); then
  systemctl show ollama -p Environment | grep -q "OLLAMA_MODELS=$HOME/dev/models" || die "ollama models path not set"
fi
log "Next: scripts/60-agents.sh"
