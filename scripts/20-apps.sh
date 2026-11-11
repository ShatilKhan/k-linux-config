#!/usr/bin/env bash
# Desktop apps and base packages. Every app comes from a source that updates:
# vendor apt repos and the Ubuntu archive (apt upgrade), snap (snap refresh),
# Flathub (flatpak update). See docs/decisions.md.
source "$(dirname "$0")/lib.sh"
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

# Infisical publishes only a setup script for its repo.
[[ -f /etc/apt/sources.list.d/infisical-infisical-cli.list || -f /etc/apt/sources.list.d/infisical.list ]] ||
  run bash -c "curl -1sLf https://artifacts-cli.infisical.com/setup.deb.sh | sudo -E bash"

# PPAs
grep -rqs obsproject /etc/apt/sources.list.d || run sudo add-apt-repository -y ppa:obsproject/obs-studio
grep -rqs jdxcode /etc/apt/sources.list.d || run sudo add-apt-repository -y ppa:jdxcode/mise

run sudo apt-get update

# Firefox: replace the snap with the Mozilla .deb (profile stays in ~/.mozilla after first run).
if snap list firefox >/dev/null 2>&1; then run sudo snap remove --purge firefox; fi

APT_PKGS=(
  git rsync wget unzip build-essential cmake pkg-config shellcheck
  jq ripgrep ffmpeg pipewire vlc mycli postgresql-client
  google-chrome-stable brave-browser code gh cloudflared firefox infisical
  obs-studio v4l2loopback-dkms mise
  flatpak gnome-software-plugin-flatpak
)
run sudo apt-get install -y "${APT_PKGS[@]}"

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

Manual installs (vendor .deb files; each adds its own apt repo or updates itself):
  - Claude Desktop:  https://claude.ai/download          sudo apt install ./claude-desktop*.deb
  - ChatGPT/Codex desktop app: https://chatgpt.com/download   sudo apt install ./<file>.deb
  - Hubstaff:        https://app.hubstaff.com/download   (Linux installer; updates from the tray menu)
EOF
mark_done
log "done. Next: scripts/30-gpu.sh"
