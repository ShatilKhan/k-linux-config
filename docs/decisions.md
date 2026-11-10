# Decisions

## Disk layout
- `/` and `/home` are separate partitions. Large data stays on `/home`. A full `/home` does not stop the system.
- Large data includes the Docker Engine data, the Docker Desktop VM, Ollama models, and repos.
- Swap is a 16 GB file. 24 GB RAM plus heavy test runs caused kernel out-of-memory kills before.

## GPU and freezes
- Driver: `nvidia-driver-595-open` from the Ubuntu archive. NVIDIA recommends the open modules for Turing and newer GPUs. `ubuntu-drivers` installs prebuilt signed modules, so no DKMS build runs.
- PRIME on-demand: the AMD iGPU drives the desktop, and the NVIDIA GPU runs only when an app asks for it.
- `NVreg_UseKernelSuspendNotifiers=1`: the open driver gets suspend events from the kernel. The old `nvidia-suspend/resume/hibernate` units are masked, so two mechanisms do not run at the same time.
- `NVreg_PreserveVideoMemoryAllocations=1` with `TemporaryFilePath=/var/tmp`: GPU memory is saved to disk, not to tmpfs.
- `amdgpu.dcdebugmask=0x600` disables Panel Self Refresh and Panel Replay on the Renoir iGPU. Reports show this stops freezes at screen lock and screen blank.
- The laptop never suspends. Closing the lid locks the screen. Kernel 7.0 on 26.04 has a known hang at lid-close suspend on AMD+NVIDIA laptops (Launchpad #2149963). If the laptop does not suspend, this bug cannot occur.
- `asusctl` and `supergfxctl` are not installed. On Ubuntu they need a source build, and they overlap with PRIME and `power-profiles-daemon`.

## Wi-Fi and Bluetooth
- MT7921 Wi-Fi had regressions on some 26.04 kernels (7.0.0-27, 7.0.0-30). `35-net-check.sh --hold` keeps a kernel that works.
- Bluetooth `13d3:3563` works with the stock `btusb` driver and `linux-firmware`.

## Docker
- Engine from Docker's apt repo, so `apt upgrade` updates it. Docker Desktop is a `.deb` with no apt repo. Software Updater cannot upgrade it, so it updates from its own app.
- Engine `data-root` is `/home/docker`. Engine 29 keeps images in `/var/lib/containerd` (the containerd image store). `data-root` does not move it, so `/var/lib/containerd` is bind-mounted from `/home/containerd`.
- Docker Desktop limits: 10 GB RAM, 12 of 16 CPUs (4 stay for the desktop), 4 GB swap, 128 GB disk ceiling.
- PostgreSQL and Redis run only in project containers. A PostgreSQL server on the host would take port 5432 from them.
- Engine and Desktop are both installed. Use `docker context use` to switch, and do not run both on the same ports.

## Runtimes: mise
- mise replaces nvm and sdkman. One file (`~/.config/mise/config.toml`) sets every runtime and global CLI.
- Projects with `.nvmrc` or `.node-version` files get their own Node version.
- Node 26 (LTS). Node 25 is end-of-life.
- Bun is pinned to an exact version. Python is 3.14.
- The mise shims are on PATH in `~/.profile`. Claude Code, MCP stdio servers, and GUI apps start programs without an interactive shell, so they need the shims to find `node`.
- npm: `ignore-scripts=true` and `min-release-age=7`. Bun: `minimumReleaseAge` 7 days. These limit npm supply-chain worms (Shai-Hulud and later).

## Apps
- An app comes from a vendor apt repo, the Ubuntu archive, a snap, or Flathub. Each of these updates automatically.
- Firefox comes from Mozilla's apt repo, pinned above Ubuntu's snap wrapper.
- Obsidian comes from Flathub. Its AppImage does not update.
- AppImages are not used.

## Git: two accounts
- Personal identity and key are the defaults in `~/.gitconfig`.
- `includeIf "gitdir:<work dir>/"` loads `~/.gitconfig-work`, which has the work identity and `core.sshCommand` with the work key.
- Remotes use plain `git@github.com:`. SSH host aliases are not needed.
- gh keeps both accounts. `ghp` and `ghw` switch the active account.
- gh tokens are in the system keyring, so copying `hosts.yml` does not move them. Log in again on each new machine.

## MCP servers
- Executor (local CLI mode, `scripts/65-executor.sh`) is the one login for many services. You connect each account once in its dashboard. Agents use one MCP endpoint (`http://127.0.0.1:4312/mcp`) and never see the credentials.
  - Its keys are in the GNOME keyring, so the Executor setup is redone on each machine, not copied.
  - The existing MCP entries stay until each service works through Executor. Then the old entry is removed, so no tool appears twice.
  - Slack stays on the Slack plugin, because Executor does not support Slack's own MCP server. Two Slack workspaces may need one Slack MCP entry per project folder.
  - Executor's support for the OAuth flow of remote MCP servers (custom app by URL) is not confirmed in its docs. Test each service before removing its old entry.
- claude.ai connectors also go with the Claude account to every machine.
- Local stdio servers and CLIs need one login on each machine.
- IBM ContextForge was evaluated and not used. You must run and patch your own server. It had several CVEs in 2026. It still needs one login for each upstream service.
- Playwright is not installed globally (an old bundled Chromium had CVEs). Projects that need it install it as a dev dependency.

## Copy and verify
- `rsync -aHAXS --numeric-ids` keeps hard links, ACLs, xattrs, sparse files, and owners.
- The old partition is mounted read-only only during copy and verify. It is never in fstab, so the new system does not depend on it.
- Login tokens are not copied (`~/.claude/.credentials.json`, `~/.codex/auth.json`, the keyring). You log in again on the new machine.
- `90-verify.sh` writes **COPY VERIFIED** only when these checks pass:
  - no old file is missing or newer on the new side;
  - every repo passes `git fsck`;
  - `git status` and stashes match the old repos;
  - every worktree exists;
  - the Claude project, session, and memory counts match.
