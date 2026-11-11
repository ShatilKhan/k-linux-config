# Manual install (the owner does this)

## 1. Make the USB installer

1. Write `ubuntu-26.04.1-desktop-amd64.iso` to a USB stick with balenaEtcher. This erases the stick.
2. Boot from the stick (ASUS: press F8 at power-on for the boot menu).

## 2. Partition the new disk

In the installer, select **Manual partitioning**. Use the new disk only.

| Partition | Size | Format | Mount point |
|---|---|---|---|
| EFI | 1 GB | FAT32 | `/boot/efi` |
| Root | 150 GB | ext4 | `/` |
| Home | the remaining space | ext4 | `/home` |

- Delete any old partitions on the new disk first.
- Do not make a swap partition. Ubuntu makes a swap file. `00-preflight.sh --fix-swap` sets it to 16 GB.
- Do not touch the old disk. The scripts mount its `/home` partition read-only.
- Keep ext4. A FAT or NTFS partition loses Linux permissions, symlinks, and Git file modes.

## 3. Create the user

- Username: **`k`**. Claude Code stores sessions and memory by path (`/home/k/...`),
  so the username and folder layout must stay the same.
- Turn off Secure Boot only if the NVIDIA driver fails to load.

## 4. Run the bootstrap (one line)

Open a terminal on the new system and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ShatilKhan/k-linux-config/main/bootstrap.sh | bash
```

It asks for your sudo password, then:
1. installs git, curl, and rsync, and clones this repo to `~/k-linux-config`;
2. runs the preflight (`--fix-swap`), the data copy, and the permission fix;
3. installs Claude Code and starts it.

Log in to Claude. It continues from `AGENT.md` and asks you to run each sudo step in a terminal.
The copy runs before Claude Code first starts, so Claude finds its old memories and sessions.

Dry run first, which changes nothing: `curl -fsSL <same URL> | bash -s -- --check`

## Manual fallback

```bash
sudo apt update && sudo apt install -y git curl rsync
git clone https://github.com/ShatilKhan/k-linux-config ~/k-linux-config
cd ~/k-linux-config
scripts/00-preflight.sh --fix-swap
scripts/10-migrate.sh
scripts/15-secure.sh
curl -fsSL https://claude.ai/install.sh | bash
claude                         # log in, then: "Follow AGENT.md"
```
