# k-linux-config

Setup scripts for my Ubuntu 26.04 LTS developer laptop (ASUS TUF A15, Ryzen 7 4800H, RTX 3050 Laptop GPU).
A Claude Code session on a fresh install runs them. [AGENT.md](AGENT.md) has its instructions.

The scripts install software, package managers, drivers, Docker, and two GitHub identities.
They also copy user data from an old Linux `/home` partition and check the copy.
This repo contains no private data. Private lists live in `~/.config/k-migration/`, which is outside this repo.

## Run order

| Step | Script | What it does |
|---|---|---|
| 0 | `docs/install.md` | You install Ubuntu by hand: EFI, `/`, `/home` on separate partitions, user `k`. |
| 0b | `bootstrap.sh` | One pasted line: runs steps 1 to 3, installs Claude Code, and starts it to do the rest. |
| 1 | `scripts/00-preflight.sh` | Checks the OS, user, partitions, swap, and network. `--fix-swap` sets swap to 16G. |
| 2 | `scripts/10-migrate.sh` | Mounts the old `/home` read-only and copies the paths in the private copy list. |
| 3 | `scripts/15-secure.sh` | Sets permissions on keys and agent state. |
| 4 | `scripts/20-apps.sh` | Adds vendor apt repos and installs the apps. |
| 5 | `scripts/30-gpu.sh` | Installs the NVIDIA 595 open driver and the no-freeze settings. Reboot after it. |
| 6 | `scripts/35-net-check.sh` | Checks Wi-Fi and Bluetooth, and can hold a good kernel. |
| 7 | `scripts/40-docker.sh` | Installs Docker Engine and Docker Desktop, with data on `/home`. |
| 8 | `scripts/50-mise-tools.sh` | Installs runtimes and CLIs with mise, plus aws, Ollama, and xhisper. |
| 9 | `scripts/60-agents.sh` | Installs Claude Code, Codex CLI, and opencode, adds the herdsman skill, and cleans up skills. |
| 9b | `scripts/65-executor.sh` | Installs Executor (one MCP endpoint for many accounts) and registers it with Claude Code and Codex. |
| 10 | `scripts/70-git.sh` | Sets up the personal and work Git identities by folder. |
| 11 | `scripts/90-verify.sh` | Checks everything and writes `~/verify-report.md`. |

Each script:

- writes its output to `~/.local/state/k-setup/<script>.log` and, when all checks pass, a `<script>.done` file;

- can run again safely;
- has a `--check` mode that only reports;
- checks each tool after it installs it (`config/tools.tsv`);
- never prints a secret.

## Updates

`update-all` (a shell function) runs apt, snap, flatpak, mise, and Claude Code updates.
Docker Desktop and Hubstaff update from their own app menus.

## Key choices

See [docs/decisions.md](docs/decisions.md).
