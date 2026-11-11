#!/usr/bin/env bash
# NVIDIA RTX 3050 Laptop (GA107M) + AMD Renoir iGPU, PRIME on-demand.
# Goal: no freezes. The laptop never suspends; closing the lid locks the screen.
# Reboot after the first run, then run again with --check.
source "$(dirname "$0")/lib.sh"
owner_sudo "$@"
need_ubuntu_2604
CFG="$REPO_DIR/config"

# 1. Driver: 595 open kernel modules from the Ubuntu archive. ubuntu-drivers picks the
#    prebuilt signed module package for the running kernel (no DKMS build).
if ! dpkg -s nvidia-driver-595-open >/dev/null 2>&1; then
  run sudo apt-get install -y ubuntu-drivers-common
  run sudo ubuntu-drivers install nvidia:595-open
  need_reboot=1
fi
run sudo prime-select on-demand

# 2. Module options (suspend memory handling via kernel notifiers).
sudo_write /etc/modprobe.d/zz-k-nvidia.conf "$(cat "$CFG/nvidia.conf")"
# With kernel suspend notifiers, the old systemd units must not run as well.
for u in nvidia-suspend nvidia-resume nvidia-hibernate nvidia-suspend-then-hibernate; do
  systemctl list-unit-files "$u.service" >/dev/null 2>&1 && run sudo systemctl mask "$u.service" || true
done

# 3. Renoir display freeze fix (PSR/Panel Replay off) on the kernel command line.
if ! grep -q 'amdgpu.dcdebugmask=0x600' /etc/default/grub; then
  run sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"/\1 amdgpu.dcdebugmask=0x600"/' /etc/default/grub
  run sudo update-grub
  need_reboot=1
fi

# 4. Never suspend: lid close locks, no automatic suspend in GNOME.
sudo_write /etc/systemd/logind.conf.d/10-k-no-suspend.conf "$(cat "$CFG/logind-no-suspend.conf")"
run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
run gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'interactive'

run sudo update-initramfs -u

if [[ "${need_reboot:-0}" == 1 && $CHECK_ONLY -eq 0 ]]; then
  log "REBOOT now, then run: scripts/30-gpu.sh --check"
  exit 0
fi

# Checks (after reboot)
rc=0
verify_tool nvidia-driver || rc=1
[[ "$(prime-select query)" == on-demand ]] || { warn "PRIME is not on-demand"; rc=1; }
grep -q 'amdgpu.dcdebugmask=0x600' /proc/cmdline || { warn "amdgpu flag not active (reboot?)"; rc=1; }
grep -q 'UseKernelSuspendNotifiers: 1' /proc/driver/nvidia/params || { warn "UseKernelSuspendNotifiers is not 1 (reboot?)"; rc=1; }
grep -q 'PreserveVideoMemoryAllocations: 1' /proc/driver/nvidia/params || { warn "PreserveVideoMemoryAllocations is not 1"; rc=1; }
[[ "$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type)" == "'nothing'" ]] || { warn "GNOME auto-suspend (AC) still on"; rc=1; }
systemd-analyze cat-config systemd/logind.conf 2>/dev/null | grep -q '^HandleLidSwitch=lock' || { warn "logind lid setting not loaded"; rc=1; }
((rc == 0)) && log "GPU and power checks PASS" || die "GPU and power checks failed (see above)"
mark_done
log "Next: scripts/35-net-check.sh"
