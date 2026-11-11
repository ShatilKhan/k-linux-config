#!/usr/bin/env bash
# Desktop apps and base packages. Every app comes from a source that updates:
# vendor apt repos and the Ubuntu archive (apt upgrade), snap (snap refresh),
# Flathub (flatpak update). See docs/decisions.md.
source "$(dirname "$0")/lib.sh"
owner_sudo "$@"
need_ubuntu_2604

# key <url> <keyring-path> [dearmor]
key() {
  [[ -s "$2" ]] && return 0
  if [[ "${3:-}" == dearmor ]]; then run bash -c "curl -fsSL '$1' | gpg --dearmor | sudo tee '$2' >/dev/null"
  else run sudo curl -fsSL "$1" -o "$2"; fi
}

run sudo apt-get update
run sudo apt-get install -y ca-certificates curl gpg software-properties-common
run sudo install -d -m 0755 /etc/apt/keyrings

# --- vendor apt repos ---
key https://dl.google.com/linux/linux_signing_key.pub /usr/share/keyrings/google-chrome.gpg dearmor
sudo_write /etc/apt/sources.list.d/google-chrome.sources "Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg"

key https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg /usr/share/keyrings/brave-browser-archive-keyring.gpg
sudo_write /etc/apt/sources.list.d/brave-browser-release.sources "Types: deb
URIs: https://brave-browser-apt-release.s3.brave.com
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/brave-browser-archive-keyring.gpg"

key https://packages.microsoft.com/keys/microsoft.asc /usr/share/keyrings/microsoft.gpg dearmor
sudo_write /etc/apt/sources.list.d/vscode.sources "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg"

key https://cli.github.com/packages/githubcli-archive-keyring.gpg /etc/apt/keyrings/githubcli-archive-keyring.gpg
sudo_write /etc/apt/sources.list.d/github-cli.sources "Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg"

key https://pkg.cloudflare.com/cloudflare-main.gpg /usr/share/keyrings/cloudflare-main.gpg
sudo_write /etc/apt/sources.list.d/cloudflared.sources "Types: deb
URIs: https://pkg.cloudflare.com/cloudflared
Suites: any
Components: main
Signed-By: /usr/share/keyrings/cloudflare-main.gpg"

# Firefox from Mozilla's apt repo, pinned above Ubuntu's snap-wrapper package.
key https://packages.mozilla.org/apt/repo-signing-key.gpg /etc/apt/keyrings/packages.mozilla.org.asc
sudo_write /etc/apt/sources.list.d/mozilla.sources "Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc"
sudo_write /etc/apt/preferences.d/mozilla "Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000"

# fpr_check <keyring> <fingerprint>: stop unless the keyring holds exactly this key.
fpr_check() {
  ((CHECK_ONLY)) && [[ ! -s "$1" ]] && return 0
  local got
  got="$(gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
  [[ "$got" == "$2" ]] || die "$1: key fingerprint '${got:-none}' is not $2"
}

# Claude Desktop (Anthropic's apt repo; the package also writes this same list file).
# Key and fingerprint: code.claude.com/docs/en/desktop-linux.
key https://downloads.claude.ai/claude-desktop/key.asc /usr/share/keyrings/claude-desktop-archive-keyring.asc
fpr_check /usr/share/keyrings/claude-desktop-archive-keyring.asc 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
sudo_write /etc/apt/sources.list.d/claude-desktop.list \
  "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main"

# ChatGPT desktop app, with Codex (OpenAI's apt repo). OpenAI publishes no key URL. The key in
# config/keys is the one the package's postinst installs, and it signs the repo's InRelease.
# The sources text matches what the postinst writes, so the package keeps this file as it is.
if [[ ! -s /usr/share/keyrings/chatgpt-archive-keyring.gpg ]]; then
  run sudo install -D -m 644 "$REPO_DIR/config/keys/chatgpt-archive-keyring.gpg" /usr/share/keyrings/chatgpt-archive-keyring.gpg
fi
fpr_check /usr/share/keyrings/chatgpt-archive-keyring.gpg 3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4
sudo_write /etc/apt/sources.list.d/chatgpt.sources "### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# Remove it to opt out of automatic package updates.
X-Repolib-Name: ChatGPT
Types: deb
URIs: https://persistent.oaistatic.com/codex-app-prod/linux/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/chatgpt-archive-keyring.gpg"

# Infisical publishes only a setup script for its repo.
[[ -f /etc/apt/sources.list.d/infisical-infisical-cli.list || -f /etc/apt/sources.list.d/infisical.list ]] ||
  run bash -c "curl -1sLf https://artifacts-cli.infisical.com/setup.deb.sh | sudo -E bash"

# PPAs
grep -rqs obsproject /etc/apt/sources.list.d || run sudo add-apt-repository -y ppa:obsproject/obs-studio
grep -rqs jdxcode /etc/apt/sources.list.d || run sudo add-apt-repository -y ppa:jdxcode/mise

run sudo apt-get update

# Firefox: replace the snap with the Mozilla .deb (profile stays in ~/.mozilla after first run).
if snap list firefox >/dev/null 2>&1; then run sudo snap remove --purge firefox; fi
# Ubuntu's stub package is versioned "1:1snap1-…"; its epoch makes Mozilla's real build look like a
# downgrade, which apt-get -y refuses. Allow the downgrade for this one package only.
if dpkg-query -W -f='${Version}' firefox 2>/dev/null | matches snap; then
  run sudo apt-get install -y --allow-downgrades firefox
fi

APT_PKGS=(
  git rsync wget unzip build-essential cmake pkg-config shellcheck
  jq ripgrep ffmpeg pipewire vlc mycli postgresql-client
  google-chrome-stable brave-browser code gh cloudflared firefox infisical
  obs-studio v4l2loopback-dkms mise
  flatpak gnome-software-plugin-flatpak
  claude-desktop chatgpt
)
run sudo apt-get install -y "${APT_PKGS[@]}"

# Claude Desktop's Cowork VM needs /dev/kvm and /dev/vhost-vsock (kvm group). Applies after a reboot.
id -nG "$USER" | matches -w kvm || run sudo usermod -aG kvm "$USER"

# Slack: official snap (auto-refreshes).
snap list slack >/dev/null 2>&1 || run sudo snap install slack

# Obsidian: Flathub (the AppImage never updates). Vaults live under ~/dev.
run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
run flatpak install --user -y flathub md.obsidian.Obsidian
run flatpak override --user --filesystem=home md.obsidian.Obsidian

if ((!CHECK_ONLY)); then
  verify_pkgs "${APT_PKGS[@]}"
  verify_rows git curl jq ripgrep ffmpeg gcc make psql mycli google-chrome brave firefox vscode \
    vlc obs slack obsidian gh infisical cloudflared mise
fi

cat <<'EOF'

Manual install (no apt repo; per-user, never with sudo):
  - Hubstaff: https://hubstaff.com/download -> Linux .sh
      sh ./Hubstaff-*.sh -- --silent --destination="$HOME/Hubstaff"
    Rerunning a newer installer upgrades it in place; quit Hubstaff first.
EOF
mark_done
log "done. Next: scripts/30-gpu.sh"
